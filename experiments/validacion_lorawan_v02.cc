/*
 * Audited, reproducible uplink experiment for ns-3.48 and lorawan v0.3.7.
 * custom915 is experimental. US915_8ch models a configured 125 kHz uplink subset;
 * it does not implement regional join/downlink procedures or emulate UG67 hardware.
 * Propagation is a replay of an external RSSI matrix, not a field measurement.
 */
#include "ns3/core-module.h"
#include "ns3/lorawan-module.h"
#include "ns3/mobility-module.h"
#include "ns3/network-module.h"
#include "ns3/point-to-point-module.h"

#include <algorithm>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <map>
#include <numeric>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

using namespace ns3;
using namespace ns3::lorawan;
namespace fs = std::filesystem;

namespace ns3
{
/** Stable application identity; packet tags do not increase the radio payload. */
class ThesisMessageTag : public Tag
{
  public:
    static TypeId GetTypeId()
    {
        static TypeId tid = TypeId("ns3::ThesisMessageTag")
                                .SetParent<Tag>()
                                .AddConstructor<ThesisMessageTag>();
        return tid;
    }
    TypeId GetInstanceTypeId() const override { return GetTypeId(); }
    uint32_t GetSerializedSize() const override { return 8; }
    void Serialize(TagBuffer b) const override { b.WriteU32(device); b.WriteU32(sequence); }
    void Deserialize(TagBuffer b) override { device = b.ReadU32(); sequence = b.ReadU32(); }
    void Print(std::ostream& os) const override { os << device << ':' << sequence; }
    uint32_t device{0};   ///< Index in the selected device cohort.
    uint32_t sequence{0}; ///< Message sequence within a device.
};
NS_OBJECT_ENSURE_REGISTERED(ThesisMessageTag);
}

namespace
{
struct Message
{
    uint32_t device{0}, sequence{0};
    double generated{0}, firstTx{-1}, firstServer{-1};
    uint32_t attempts{0}, sf{0};
    std::set<uint32_t> gateways;
    std::set<uint32_t> macGateways;
    uint32_t serverEvents{0};
    std::map<std::string, uint32_t> outcomes;
};

struct Audit
{
    std::map<uint64_t, Message> messages;
    std::ofstream events;
    uint64_t unknown{0}, gwEvents{0}, serverEvents{0}, suppressedReplies{0};
    std::map<std::string, uint64_t> outcomes;
} audit;

/** Enforce an explicitly uplink-only experiment, including late ADR keepalives. */
class UplinkOnlyController : public NetworkControllerComponent
{
  public:
    static TypeId GetTypeId()
    {
        static TypeId tid = TypeId("ns3::ThesisUplinkOnlyController")
            .SetParent<NetworkControllerComponent>().AddConstructor<UplinkOnlyController>();
        return tid;
    }
    void OnReceivedPacket(Ptr<const Packet>, Ptr<EndDeviceStatus> status,
                          Ptr<NetworkStatus>) override
    {
        if (status->m_reply.needsReply) ++audit.suppressedReplies;
        status->m_reply.needsReply = false;
    }
    void BeforeSendingReply(Ptr<EndDeviceStatus> status, Ptr<NetworkStatus>) override
    {
        status->m_reply.needsReply = false;
    }
    void OnFailedReply(Ptr<EndDeviceStatus>, Ptr<NetworkStatus>) override {}
};

uint64_t Key(const ThesisMessageTag& tag)
{
    return (uint64_t(tag.device) << 32) | tag.sequence;
}

Message* FindMessage(Ptr<const Packet> packet)
{
    ThesisMessageTag tag;
    if (!packet->PeekPacketTag(tag))
    {
        ++audit.unknown;
        return nullptr;
    }
    auto it = audit.messages.find(Key(tag));
    if (it == audit.messages.end())
    {
        ++audit.unknown;
        return nullptr;
    }
    return &it->second;
}

void Event(const std::string& name, const Message& m, int64_t observer, uint64_t uid)
{
    if (audit.events.is_open())
    {
        audit.events << std::setprecision(12) << Simulator::Now().GetSeconds() << ','
                     << name << ',' << m.device << ',' << m.sequence << ','
                     << observer << ',' << uid << '\n';
    }
}

void PhyTx(Ptr<const Packet> packet, uint32_t nodeId)
{
    if (auto* m = FindMessage(packet))
    {
        if (m->attempts++ == 0) m->firstTx = Simulator::Now().GetSeconds();
        LoraTag tag;
        if (packet->PeekPacketTag(tag)) m->sf = tag.GetSpreadingFactor();
        Event("phy_tx", *m, nodeId, packet->GetUid());
    }
}

void Outcome(std::string kind, Ptr<const Packet> packet, uint32_t gatewayId)
{
    if (auto* m = FindMessage(packet))
    {
        ++audit.outcomes[kind];
        ++m->outcomes[kind];
        if (kind == "gw_rx")
        {
            m->gateways.insert(gatewayId);
            ++audit.gwEvents;
        }
        Event(kind, *m, gatewayId, packet->GetUid());
    }
}

void GatewayMacRx(uint32_t gatewayId, Ptr<const Packet> packet)
{
    if (auto* m = FindMessage(packet))
    {
        m->macGateways.insert(gatewayId);
        Event("gw_mac_rx", *m, gatewayId, packet->GetUid());
    }
}

void ServerRx(Ptr<const Packet> packet)
{
    if (auto* m = FindMessage(packet))
    {
        if (m->serverEvents++ == 0) m->firstServer = Simulator::Now().GetSeconds();
        ++audit.serverEvents;
        Event("server_rx", *m, -1, packet->GetUid());
    }
}

void Delayed(Ptr<const Packet> packet)
{
    if (auto* m = FindMessage(packet))
    {
        ++audit.outcomes["mac_delayed"];
        ++m->outcomes["mac_delayed"];
        Event("mac_delayed", *m, m->device, packet->GetUid());
    }
}

/** Periodic source with exactly one explicit initial random offset. */
class AuditedSender : public Application
{
  public:
    static TypeId GetTypeId()
    {
        static TypeId tid = TypeId("ns3::AuditedSender")
                                .SetParent<Application>()
                                .AddConstructor<AuditedSender>();
        return tid;
    }
    void Configure(Ptr<EndDeviceLorawanMac> mac, uint32_t device, uint32_t payload,
                   double period, double offset, double stop)
    {
        m_mac = mac; m_device = device; m_payload = payload;
        m_period = period; m_offset = offset; m_stop = stop;
    }
  private:
    void StartApplication() override
    {
        m_next = Simulator::Schedule(Seconds(m_offset), &AuditedSender::Send, this);
    }
    void StopApplication() override { Simulator::Cancel(m_next); }
    void Send()
    {
        if (Simulator::Now().GetSeconds() >= m_stop) return;
        Ptr<Packet> packet = Create<Packet>(m_payload);
        ThesisMessageTag tag;
        tag.device = m_device; tag.sequence = m_sequence++;
        packet->AddPacketTag(tag);
        Message m;
        m.device = m_device; m.sequence = tag.sequence;
        m.generated = Simulator::Now().GetSeconds();
        auto [it, inserted] = audit.messages.emplace(Key(tag), m);
        NS_ABORT_MSG_IF(!inserted, "Duplicate application message identity");
        Event("generated", it->second, m_device, packet->GetUid());
        m_mac->Send(packet);
        m_next = Simulator::Schedule(Seconds(m_period), &AuditedSender::Send, this);
    }
    Ptr<EndDeviceLorawanMac> m_mac; ///< MAC configured by the experiment.
    uint32_t m_device{0}, m_payload{51}, m_sequence{0};
    double m_period{3600}, m_offset{0}, m_stop{86400};
    EventId m_next; ///< Next generation event, cancelled at application stop.
};

struct Row
{
    std::string id;
    double latitude, longitude;
    std::vector<double> rssi;
};
struct Gateway
{
    uint32_t id;
    double latitude, longitude, height;
};

std::vector<std::string> Split(const std::string& line)
{
    if (line.find('"') != std::string::npos)
        throw std::runtime_error("Quoted CSV fields are not supported; use plain numeric CSV");
    std::vector<std::string> result;
    std::stringstream ss(line);
    std::string item;
    while (std::getline(ss, item, ','))
    {
        if (!item.empty() && item.back() == '\r') item.pop_back();
        result.push_back(item);
    }
    if (!line.empty() && (line.back() == ',' ||
        (line.size() > 1 && line.back() == '\r' && line[line.size()-2] == ',')))
        result.push_back("");
    return result;
}

double Number(const std::string& text)
{
    size_t consumed = 0;
    double value;
    try { value = std::stod(text, &consumed); }
    catch (const std::exception&) { throw std::runtime_error("Invalid CSV number: " + text); }
    if (consumed != text.size() || !std::isfinite(value))
        throw std::runtime_error("Invalid/non-finite numeric CSV value: " + text);
    return value;
}

uint32_t PositiveInt(const std::string& text)
{
    double value = Number(text);
    if (value < 1 || value > 1000000000 || std::floor(value) != value)
        throw std::runtime_error("Expected positive integer: " + text);
    return static_cast<uint32_t>(value);
}

void Coordinates(double lat, double lon)
{
    if (std::abs(lat) > 90 || std::abs(lon) > 180)
        throw std::runtime_error("Latitude/longitude out of range");
}

std::vector<Row> ReadMatrix(const std::string& path, std::vector<uint32_t>& gatewayIds)
{
    std::ifstream file(path);
    if (!file) throw std::runtime_error("Cannot open matrix: " + path);
    std::string line;
    if (!std::getline(file, line)) throw std::runtime_error("Empty matrix");
    auto header = Split(line);
    if (header.size() < 4 || header[0] != "Node_ID" || header[1] != "Latitude" ||
        header[2] != "Longitude") throw std::runtime_error("Incorrect matrix header");
    std::set<uint32_t> uniqueGateways;
    for (size_t i = 3; i < header.size(); ++i)
    {
        auto h = header[i];
        if (h.size() < 9 || h.substr(0, 3) != "GW_" || h.substr(h.size()-5) != "_RSSI")
            throw std::runtime_error("Expected GW_<integer>_RSSI column");
        auto id = PositiveInt(h.substr(3, h.size()-8));
        if (!uniqueGateways.insert(id).second) throw std::runtime_error("Duplicate gateway column");
        gatewayIds.push_back(id);
    }
    std::vector<Row> rows;
    std::set<std::string> ids;
    while (std::getline(file, line))
    {
        if (line.empty() || line == "\r") continue;
        auto fields = Split(line);
        if (fields.size() != header.size()) throw std::runtime_error("Incorrect matrix row width");
        if (fields[0].empty() || !ids.insert(fields[0]).second)
            throw std::runtime_error("Empty/duplicate Node_ID");
        Row row{fields[0], Number(fields[1]), Number(fields[2]), {}};
        Coordinates(row.latitude, row.longitude);
        for (size_t i = 3; i < fields.size(); ++i) row.rssi.push_back(Number(fields[i]));
        rows.push_back(row);
    }
    if (rows.empty()) throw std::runtime_error("Matrix has no devices");
    return rows;
}

std::map<uint32_t, Gateway> ReadGateways(const std::string& path)
{
    std::ifstream file(path);
    if (!file) throw std::runtime_error("Cannot open gateways CSV: " + path);
    std::string line;
    std::getline(file, line);
    if (Split(line) != std::vector<std::string>{"Gateway_ID","Latitude","Longitude","Height_m"})
        throw std::runtime_error("Incorrect gateways CSV header");
    std::map<uint32_t, Gateway> result;
    while (std::getline(file, line))
    {
        if (line.empty() || line == "\r") continue;
        auto f = Split(line);
        if (f.size() != 4) throw std::runtime_error("Incorrect gateways CSV row width");
        Gateway g{PositiveInt(f[0]), Number(f[1]), Number(f[2]), Number(f[3])};
        Coordinates(g.latitude, g.longitude);
        if (g.height < 0 || !result.emplace(g.id, g).second)
            throw std::runtime_error("Invalid height/duplicate gateway ID");
    }
    return result;
}

std::string JsonString(const std::string& text)
{
    std::string result = "\"";
    for (char c : text)
    {
        if (c == '\\' || c == '"') result += '\\';
        if (static_cast<unsigned char>(c) < 32) throw std::runtime_error("Control character in path");
        result += c;
    }
    return result + '"';
}

double Percent(uint64_t numerator, uint64_t denominator)
{
    return denominator ? 100.0 * numerator / denominator : 0.0;
}

Vector Position(double lat, double lon, double height, double lat0, double lon0)
{
    constexpr double rad = 3.14159265358979323846 / 180.0;
    constexpr double radius = 6371000.0;
    return Vector(radius * (lon-lon0) * rad * std::cos(lat0*rad),
                  radius * (lat-lat0) * rad, height);
}

void Connect(Ptr<Object> object, const std::string& name, const CallbackBase& callback)
{
    if (!object->TraceConnectWithoutContext(name, callback))
        throw std::runtime_error("Missing trace source: " + name);
}

void Us915DataRates(Ptr<LorawanMac> mac)
{
    // RP002-1.0.4, US902-928: uplink DR0..3 and downlink DR8..13.
    // Reserved entries are not enabled as transmission channels.
    mac->SetSfForDataRate({10,9,8,7,8,0,0,0,12,11,10,9,8,7,0,0});
    mac->SetBandwidthForDataRate({125000,125000,125000,125000,500000,0,0,0,
                                 500000,500000,500000,500000,500000,500000,0,0});
    mac->SetMaxMacPayloadForDataRate({19,61,133,230,230,0,0,0,61,137,230,230,230,230,0,0});
}
}

int main(int argc, char* argv[])
{
    try
    {
        std::string matrix = "Matrix_PathLoss_3D.csv", gatewaysCsv = "gateways.csv";
        std::string output = "ns3_v02_output", selection = "all", gatewayIds = "all";
        std::string radioProfile = "US915_8ch";
        uint32_t nDevices = 0, payload = 51, sf = 9, seed = 42, channelCount = 8;
        uint32_t frequencyHz = 915000000, channelSpacingHz = 200000, receivers = 8;
        uint32_t us915StartChannel = 8;
        uint64_t run = 1;
        double duration = 86400, period = 3600, drain = 300;
        double txPowerDbm = 27, matrixReferenceDbm = 27, dutyCycle = 1;
        bool writeEvents = true, enableForwarder = true, synchronized = false;
        CommandLine cmd(__FILE__);
        cmd.AddValue("matrix", "RSSI matrix CSV path", matrix);
        cmd.AddValue("gatewaysCsv", "Gateway coordinates CSV path", gatewaysCsv);
        cmd.AddValue("output", "New output directory", output);
        cmd.AddValue("nDevices", "0 uses all matrix rows", nDevices);
        cmd.AddValue("selection", "all, first, or random (explicit cohort)", selection);
        cmd.AddValue("gatewayIds", "all or comma-separated matrix gateway IDs", gatewayIds);
        cmd.AddValue("radioProfile", "US915_8ch uplinks, custom915 experimental, or EU868 reference", radioProfile);
        cmd.AddValue("us915StartChannel", "First US915 channel index in an eight-channel bank", us915StartChannel);
        cmd.AddValue("frequencyHz", "First custom profile channel frequency in Hz", frequencyHz);
        cmd.AddValue("channelSpacingHz", "Custom channel spacing in Hz", channelSpacingHz);
        cmd.AddValue("channelCount", "Custom profile channel count", channelCount);
        cmd.AddValue("receivers", "Parallel gateway demodulators", receivers);
        cmd.AddValue("txPowerDbm", "Actual device transmission power in dBm", txPowerDbm);
        cmd.AddValue("matrixReferenceDbm", "Power used to produce matrix RSSI", matrixReferenceDbm);
        cmd.AddValue("dutyCycle", "Experimental custom profile duty-cycle fraction", dutyCycle);
        cmd.AddValue("payload", "Application payload bytes (tags add no airtime)", payload);
        cmd.AddValue("sf", "Fixed spreading factor, 7 to 12, BW125kHz", sf);
        cmd.AddValue("duration", "Application generation window in seconds", duration);
        cmd.AddValue("period", "Generation interval in seconds", period);
        cmd.AddValue("drain", "Extra observation time after generation stops", drain);
        cmd.AddValue("seed", "RNG seed, fixed across replications", seed);
        cmd.AddValue("run", "Independent RNG substream run number", run);
        cmd.AddValue("writeEvents", "Write detailed event CSV", writeEvents);
        cmd.AddValue("enableForwarder", "Enable gateway to server forwarding", enableForwarder);
        cmd.AddValue("synchronized", "Use zero initial offsets for controlled tests", synchronized);
        cmd.Parse(argc, argv);
        if (!(duration > 0) || !(period > 0) || !(drain > 0) || !std::isfinite(duration) ||
            !std::isfinite(period) || !std::isfinite(drain) || sf < 7 || sf > 12 || !seed ||
            payload < 1 || payload > (sf >= 10 ? 51u : sf == 9 ? 115u : 222u) ||
            !std::isfinite(txPowerDbm) || !std::isfinite(matrixReferenceDbm) ||
            !receivers || receivers > 64 || !run)
            throw std::runtime_error("Invalid experiment parameters/payload for data rate");
        if (radioProfile != "custom915" && radioProfile != "EU868" && radioProfile != "US915_8ch")
            throw std::runtime_error("Unsupported radio profile");
        const bool us915 = radioProfile == "US915_8ch";
        if (us915)
        {
            if (sf > 10 || us915StartChannel > 56 || us915StartChannel % 8 != 0 ||
                channelCount != 8 || dutyCycle != 1 || txPowerDbm > 30 ||
                payload > (sf == 10 ? 11u : sf == 9 ? 53u : sf == 8 ? 125u : 222u))
                throw std::runtime_error("Invalid US915 uplink SF/payload/channel-bank/power parameters");
            frequencyHz = 902300000 + us915StartChannel*200000;
            channelSpacingHz = 200000;
        }
        if (radioProfile == "EU868" && txPowerDbm > 14)
            throw std::runtime_error("EU868 default uplink channels reject power above 14 dBm");
        if (radioProfile == "custom915" && (!channelCount || channelCount > 16 ||
            frequencyHz < 902000000 || uint64_t(frequencyHz) +
            uint64_t(channelCount-1)*channelSpacingHz > 928000000 ||
            (channelCount > 1 && channelSpacingHz < 125000) ||
            !(dutyCycle > 0 && dutyCycle <= 1)))
            throw std::runtime_error("Invalid experimental 915 MHz channel profile");

        RngSeedManager::SetSeed(seed);
        RngSeedManager::SetRun(run);
        std::vector<uint32_t> matrixGatewayIds;
        auto rows = ReadMatrix(matrix, matrixGatewayIds);
        auto gatewayLocations = ReadGateways(gatewaysCsv);
        std::vector<size_t> gwColumns;
        std::set<uint32_t> requested;
        if (gatewayIds != "all")
            for (auto& token : Split(gatewayIds))
                if (!requested.insert(PositiveInt(token)).second)
                    throw std::runtime_error("Duplicate requested gateway ID");
        for (size_t col = 0; col < matrixGatewayIds.size(); ++col)
        {
            auto id = matrixGatewayIds[col];
            if (gatewayIds == "all" || requested.count(id))
            {
                if (!gatewayLocations.count(id)) throw std::runtime_error("Missing gateway coordinates");
                gwColumns.push_back(col);
            }
        }
        if (gwColumns.empty() || (gatewayIds != "all" && gwColumns.size() != requested.size()))
            throw std::runtime_error("Requested gateway ID absent from matrix");
        std::vector<size_t> selected(rows.size());
        std::iota(selected.begin(), selected.end(), 0);
        if (!nDevices) nDevices = rows.size();
        if (nDevices > rows.size() || (selection == "all" && nDevices != rows.size()) ||
            (selection != "all" && selection != "first" && selection != "random"))
            throw std::runtime_error("Invalid device selection; truncation requires selection=first/random");
        if (selection == "random")
        {
            auto choose = CreateObject<UniformRandomVariable>();
            choose->SetStream(1);
            for (size_t i = selected.size(); i > 1; --i)
                std::swap(selected[i-1], selected[choose->GetInteger(0, i-1)]);
        }
        selected.resize(nDevices);
        std::sort(selected.begin(), selected.end());
        for (const auto& row : rows)
            for (double rssi : row.rssi)
                if (matrixReferenceDbm - rssi < 0)
                    throw std::runtime_error("RSSI implies negative propagation loss");
        if (fs::exists(output))
            for (const auto& entry : fs::directory_iterator(output))
                if (entry.path().filename() != "run_manifest.json" && entry.path().filename() != "stdout.log")
                    throw std::runtime_error("Output already contains evidence; choose a new directory");
        fs::create_directories(output);
        auto stream = [&](const std::string& name) {
            std::ofstream file(fs::path(output)/name);
            if (!file) throw std::runtime_error("Cannot write output: " + name);
            file << std::setprecision(12);
            return file;
        };
        if (writeEvents)
        {
            audit.events = stream("events.csv");
            audit.events << "time_s,event,device_index,message_sequence,observer_node_id,packet_uid\n";
        }
        auto config = stream("configuration.json");
        config << "{\n\"program\":\"validacion_lorawan_v02\",\n"
               << "\"matrix\":" << JsonString(fs::absolute(matrix).string()) << ",\n"
               << "\"gateways_csv\":" << JsonString(fs::absolute(gatewaysCsv).string()) << ",\n"
               << "\"matrix_rows\":" << rows.size() << ",\n\"n_devices\":" << nDevices
               << ",\n\"n_gateways\":" << gwColumns.size() << ",\n\"selection\":" << JsonString(selection)
               << ",\n\"gateway_ids\":" << JsonString(gatewayIds)
               << ",\n\"radio_profile\":" << JsonString(radioProfile)
               << ",\n\"is_regional_deployment_validation\":false,\n\"frequency_hz\":"
               << (radioProfile != "EU868" ? frequencyHz : 868100000)
               << ",\n\"channel_count\":" << (radioProfile != "EU868" ? channelCount : 3)
               << ",\n\"channel_spacing_hz\":" << channelSpacingHz
               << ",\n\"duty_cycle\":" << (radioProfile != "EU868" ? dutyCycle : 0.01)
               << ",\n\"tx_power_dbm\":" << txPowerDbm
               << ",\n\"matrix_reference_dbm\":" << matrixReferenceDbm
               << ",\n\"fixed_sf\":" << sf << ",\n\"fixed_data_rate\":" << (us915 ? 10-sf : 12-sf)
               << ",\n\"us915_start_channel\":" << us915StartChannel
               << ",\n\"bandwidth_hz\":125000,\n\"adr\":false,\n"
               << "\"confirmed_uplinks\":false,\n\"transmissions_per_message\":1,\n\"receivers\":" << receivers
               << ",\n\"payload_bytes\":" << payload << ",\n\"duration_s\":" << duration
               << ",\n\"period_s\":" << period << ",\n\"drain_s\":" << drain
               << ",\n\"seed\":" << seed << ",\n\"run\":" << run
               << ",\n\"forwarder\":" << (enableForwarder ? "true" : "false")
               << ",\n\"synchronized\":" << (synchronized ? "true" : "false")
               << ",\n\"initial_offset_stream\":10,\n\"selection_stream\":1,\n"
               << "\"propagation\":\"external_matrix_effective_reciprocal_loss\",\n"
               << "\"coordinate_projection\":\"local_equirectangular_meters\",\n"
               << "\"mic_modeled\":false,\n\"field_node_power_confirmed\":false,\n\"field_channel_mask_confirmed\":false,\n"
               << "\"uplink_only_channel\":true,\n\"uplink_only_server_policy\":true,\n"
               << "\"gateway_phy_model\":\"SimpleGatewayLoraPhy (SX1301 abstraction; not UG67 SX1302 emulation)\",\n"
               << "\"profile_scope\":\"US915_8ch: preconfigured unconfirmed uplinks on one eight-channel 125kHz bank; no join, ADR, RX1 mapping or 500kHz uplinks validated\",\n"
               << "\"note\":\"Matrix evaluated at nominal 915MHz and replayed on all channels; node TX power and field channel mask require confirmation; matrix replay does not independently validate propagation\"\n}\n";
        config.close();

        NodeContainer devices, gateways, server;
        devices.Create(nDevices); gateways.Create(gwColumns.size()); server.Create(1);
        double lat0 = rows[selected.front()].latitude, lon0 = rows[selected.front()].longitude;
        MobilityHelper mobility;
        mobility.SetMobilityModel("ns3::ConstantPositionMobilityModel");
        mobility.Install(devices); mobility.Install(gateways);
        for (uint32_t i = 0; i < nDevices; ++i)
        {
            const auto& row = rows[selected[i]];
            devices.Get(i)->GetObject<MobilityModel>()->SetPosition(
                Position(row.latitude, row.longitude, 1.5, lat0, lon0));
        }
        auto mappedGateways = stream("selected_gateways.csv");
        mappedGateways << "gateway_node_id,matrix_gateway_id,latitude,longitude,height_m\n";
        for (size_t j = 0; j < gwColumns.size(); ++j)
        {
            auto g = gatewayLocations.at(matrixGatewayIds[gwColumns[j]]);
            gateways.Get(j)->GetObject<MobilityModel>()->SetPosition(
                Position(g.latitude, g.longitude, g.height, lat0, lon0));
            mappedGateways << gateways.Get(j)->GetId() << ',' << g.id << ',' << g.latitude
                           << ',' << g.longitude << ',' << g.height << '\n';
        }
        auto loss = CreateObject<MatrixPropagationLossModel>();
        loss->SetDefaultLoss(300);
        for (uint32_t i = 0; i < nDevices; ++i)
            for (size_t j = 0; j < gwColumns.size(); ++j)
                loss->SetLoss(devices.Get(i)->GetObject<MobilityModel>(),
                              gateways.Get(j)->GetObject<MobilityModel>(),
                              matrixReferenceDbm-rows[selected[i]].rssi[gwColumns[j]], true);
        auto channel = CreateObject<LoraChannel>(loss, CreateObject<ConstantSpeedPropagationDelayModel>());
        LoraPhyHelper phy;
        phy.SetChannel(channel);
        LorawanMacHelper mac;
        mac.SetRegion(LorawanMacHelper::EU);
        LoraHelper helper;
        helper.EnablePacketTracking();
        mac.SetAddressGenerator(CreateObject<LoraDeviceAddressGenerator>(54, 1));
        phy.SetDeviceType(LoraPhyHelper::ED); mac.SetDeviceType(LorawanMacHelper::ED_A);
        auto edNetDevices = helper.Install(phy, mac, devices);
        // No downlinks are generated in this experiment. Avoid scheduling copies
        // of every uplink at devices that cannot contribute to gateway reception.
        for (uint32_t i = 0; i < edNetDevices.GetN(); ++i)
            channel->Remove(DynamicCast<LoraNetDevice>(edNetDevices.Get(i))->GetPhy());
        phy.SetDeviceType(LoraPhyHelper::GW); mac.SetDeviceType(LorawanMacHelper::GW);
        NetDeviceContainer gwNetDevices;
        if (radioProfile == "EU868")
        {
            gwNetDevices = helper.Install(phy, mac, gateways);
        }
        else
        {
            // The stock PHY helper preloads EU filters and exposes no clearing API.
            // Construct gateways with an empty filter list; attach the same native tracker.
            auto* native = &helper.GetPacketTracker();
            for (uint32_t j = 0; j < gateways.GetN(); ++j)
            {
                auto net = CreateObject<LoraNetDevice>();
                auto gatewayPhy = CreateObject<SimpleGatewayLoraPhy>();
                gatewayPhy->SetChannel(channel);
                gatewayPhy->SetDevice(net);
                channel->Add(gatewayPhy);
                net->SetPhy(gatewayPhy);
                auto gatewayMac = CreateObject<GatewayLorawanMac>();
                gatewayMac->SetDevice(net);
                gatewayMac->SetPhy(gatewayPhy);
                gatewayMac->SetSfForDataRate({12,11,10,9,8,7,7});
                gatewayMac->SetBandwidthForDataRate({125000,125000,125000,125000,125000,125000,250000});
                gatewayMac->SetMaxMacPayloadForDataRate({59,59,59,123,230,230,230});
                net->SetMac(gatewayMac);
                Connect(gatewayPhy, "StartSending", MakeCallback(&LoraPacketTracker::TransmissionCallback,native));
                Connect(gatewayPhy, "ReceivedPacket", MakeCallback(&LoraPacketTracker::PacketReceptionCallback,native));
                Connect(gatewayPhy, "LostPacketBecauseInterference", MakeCallback(&LoraPacketTracker::InterferenceCallback,native));
                Connect(gatewayPhy, "LostPacketBecauseNoMoreReceivers", MakeCallback(&LoraPacketTracker::NoMoreReceiversCallback,native));
                Connect(gatewayPhy, "LostPacketBecauseUnderSensitivity", MakeCallback(&LoraPacketTracker::UnderSensitivityCallback,native));
                Connect(gatewayPhy, "NoReceptionBecauseTransmitting", MakeCallback(&LoraPacketTracker::LostBecauseTxCallback,native));
                Connect(gatewayMac, "SentNewPacket", MakeCallback(&LoraPacketTracker::MacTransmissionCallback,native));
                Connect(gatewayMac, "ReceivedPacket", MakeCallback(&LoraPacketTracker::MacGwReceptionCallback,native));
                gateways.Get(j)->AddDevice(net);
                gwNetDevices.Add(net);
            }
        }

        auto customChannels = [&]() {
            auto channels = Create<LogicalLoraChannelHelper>(channelCount);
            channels->AddSubBand(Create<SubBand>(frequencyHz-100000,
                frequencyHz+(channelCount-1)*channelSpacingHz+100000, dutyCycle, txPowerDbm));
            for (uint32_t k = 0; k < channelCount; ++k)
                channels->SetChannel(k, Create<LogicalLoraChannel>(frequencyHz+k*channelSpacingHz, 0, us915 ? 3 : 5));
            return channels;
        };
        auto deviceMap = stream("selected_devices.csv");
        deviceMap << "device_index,ns3_node_id,matrix_row_1based,node_id,latitude,longitude,devaddr,initial_offset_s,fixed_sf,tx_power_dbm\n";
        auto offset = CreateObject<UniformRandomVariable>();
        offset->SetStream(10);
        for (uint32_t i = 0; i < nDevices; ++i)
        {
            auto net = DynamicCast<LoraNetDevice>(edNetDevices.Get(i));
            auto edMac = DynamicCast<EndDeviceLorawanMac>(net->GetMac());
            if (radioProfile != "EU868")
                edMac->SetLogicalLoraChannelHelper(customChannels());
            if (us915)
            {
                Us915DataRates(edMac);
                auto classA = DynamicCast<ClassAEndDeviceLorawanMac>(edMac);
                classA->SetSecondReceiveWindowDataRate(8);
                classA->SetSecondReceiveWindowFrequency(923300000);
            }
            edMac->SetTransmissionPowerDbm(txPowerDbm);
            edMac->SetDataRate(us915 ? 10-sf : 12-sf);
            edMac->SetUplinkAdrBit(false);
            edMac->SetMaxNumberOfTransmissions(1);
            edMac->SetFType(LorawanMacHeader::FType::UNCONFIRMED_DATA_UP);
            Connect(net->GetPhy(), "StartSending", MakeCallback(&PhyTx));
            Connect(edMac, "CannotSendBecauseDutyCycle", MakeCallback(&Delayed));
            double initial = synchronized ? 0 : offset->GetValue(0, period);
            auto sender = CreateObject<AuditedSender>();
            sender->Configure(edMac, i, payload, period, initial, duration);
            devices.Get(i)->AddApplication(sender);
            sender->SetStartTime(Seconds(0)); sender->SetStopTime(Seconds(duration));
            const auto& row = rows[selected[i]];
            deviceMap << i << ',' << devices.Get(i)->GetId() << ',' << selected[i]+1 << ','
                      << row.id << ',' << row.latitude << ',' << row.longitude << ','
                      << edMac->GetDeviceAddress() << ',' << initial << ',' << sf << ',' << txPowerDbm << '\n';
        }
        for (size_t j = 0; j < gwColumns.size(); ++j)
        {
            auto net = DynamicCast<LoraNetDevice>(gwNetDevices.Get(j));
            auto gatewayPhy = DynamicCast<GatewayLoraPhy>(net->GetPhy());
            gatewayPhy->ResetReceptionPaths();
            for (uint32_t r = 0; r < receivers; ++r) gatewayPhy->AddReceptionPath();
            if (radioProfile != "EU868")
            {
                net->GetMac()->SetLogicalLoraChannelHelper(customChannels());
                if (us915) Us915DataRates(net->GetMac());
                for (uint32_t k = 0; k < channelCount; ++k)
                    gatewayPhy->AddFrequency(frequencyHz+k*channelSpacingHz);
            }
            for (const auto& [trace, kind] : std::vector<std::pair<std::string, std::string>>{
                    {"ReceivedPacket", "gw_rx"},
                    {"LostPacketBecauseInterference", "interference"},
                    {"LostPacketBecauseUnderSensitivity", "under_sensitivity"},
                    {"LostPacketBecauseNoMoreReceivers", "no_receiver"},
                    {"NoReceptionBecauseTransmitting", "gateway_tx"}})
                Connect(gatewayPhy, trace, MakeBoundCallback(&Outcome, kind));
            Connect(net->GetMac(), "ReceivedPacket",
                    MakeBoundCallback(&GatewayMacRx, gateways.Get(j)->GetId()));
        }
        PointToPointHelper p2p;
        p2p.SetDeviceAttribute("DataRate", StringValue("5Mbps"));
        p2p.SetChannelAttribute("Delay", StringValue("2ms"));
        P2PGwRegistration_t registration;
        for (uint32_t j = 0; j < gateways.GetN(); ++j)
        {
            auto link = p2p.Install(server.Get(0), gateways.Get(j));
            registration.emplace_back(DynamicCast<PointToPointNetDevice>(link.Get(0)), gateways.Get(j));
        }
        NetworkServerHelper serverHelper;
        serverHelper.EnableAdr(false);
        serverHelper.SetGatewaysP2P(registration);
        serverHelper.SetEndDevices(devices);
        auto serverApps = serverHelper.Install(server.Get(0));
        // The installed module requests keepalives after ADR_ACK_LIMIT even
        // with the ADR bit disabled. Add this last to override reply components.
        DynamicCast<NetworkServer>(serverApps.Get(0))->AddComponent(CreateObject<UplinkOnlyController>());
        Connect(serverApps.Get(0), "ReceivedPacket", MakeCallback(&ServerRx));
        if (enableForwarder) { ForwarderHelper forwarder; forwarder.Install(gateways); }
        deviceMap.close(); mappedGateways.close();
        std::cout << "Running measured uplinks: " << nDevices << " devices, " << gateways.GetN()
                  << " gateways, period=" << period << ", duration=" << duration << ", Run=" << run << std::endl;
        Simulator::Stop(Seconds(duration+drain));
        Simulator::Run();

        uint64_t generated = audit.messages.size(), tx = 0, attempts = 0, gw = 0, ns = 0, macGw = 0;
        double latencySum = 0;
        bool invariant = audit.unknown == 0;
        auto packets = stream("packets.csv");
        packets << "device_index,node_id,message_sequence,generated_s,first_tx_s,tx_attempts,sf,gw_unique_count,server_rx_events,first_server_s,interference_events,under_sensitivity_events,no_receiver_events,delay_events\n";
        auto perNode = stream("node_metrics.csv");
        perNode << "device_index,node_id,generated,tx_unique,gw_unique,server_unique,pdr_server_generated_pct\n";
        std::vector<std::vector<uint64_t>> nodes(nDevices, std::vector<uint64_t>(4));
        std::map<uint32_t, std::vector<uint64_t>> hours;
        for (const auto& [key, m] : audit.messages)
        {
            bool sent = m.attempts > 0, received = !m.gateways.empty(), delivered = m.serverEvents > 0;
            tx += sent; attempts += m.attempts; gw += received; ns += delivered;
            macGw += !m.macGateways.empty();
            invariant = invariant && (!received || sent) && (!delivered || received) &&
                        (m.gateways == m.macGateways) && (m.attempts <= 1) &&
                        (!sent || m.sf == sf);
            if (delivered) latencySum += m.firstServer-m.generated;
            auto values = std::vector<uint64_t>{1, uint64_t(sent), uint64_t(received), uint64_t(delivered)};
            auto& hour = hours[static_cast<uint32_t>(m.generated/3600)];
            if (hour.empty()) hour.resize(4);
            for (size_t k = 0; k < 4; ++k) { nodes[m.device][k] += values[k]; hour[k] += values[k]; }
            auto count = [&](const std::string& name) { auto it=m.outcomes.find(name); return it==m.outcomes.end()?0:it->second; };
            packets << m.device << ',' << rows[selected[m.device]].id << ',' << m.sequence << ','
                    << m.generated << ',' << m.firstTx << ',' << m.attempts << ',' << m.sf << ','
                    << m.gateways.size() << ',' << m.serverEvents << ',' << m.firstServer << ','
                    << count("interference") << ',' << count("under_sensitivity") << ','
                    << count("no_receiver") << ',' << count("mac_delayed") << '\n';
        }
        for (uint32_t i = 0; i < nDevices; ++i)
            perNode << i << ',' << rows[selected[i]].id << ',' << nodes[i][0] << ',' << nodes[i][1]
                    << ',' << nodes[i][2] << ',' << nodes[i][3] << ',' << Percent(nodes[i][3],nodes[i][0]) << '\n';
        auto hourly = stream("hourly_metrics.csv");
        hourly << "generation_hour_0based,generated,tx_unique,gw_unique,server_unique,pdr_server_generated_pct\n";
        for (const auto& [hour, v] : hours)
            hourly << hour << ',' << v[0] << ',' << v[1] << ',' << v[2] << ',' << v[3] << ',' << Percent(v[3],v[0]) << '\n';
        auto& tracker = helper.GetPacketTracker();
        std::stringstream trackerTotals(tracker.CountMacPacketsGlobally(Seconds(0), Seconds(duration+drain)));
        double trackerSent = -1, trackerReceived = -1;
        trackerTotals >> trackerSent >> trackerReceived;
        invariant = invariant && generated > 0 && tx > 0 && trackerSent == tx &&
                    trackerReceived == macGw && ns <= gw && gw <= tx && tx <= generated;
        auto gatewayMetrics = stream("gateway_metrics.csv");
        gatewayMetrics << "gateway_node_id,matrix_gateway_id,tx_attempts,received,interfered,no_receiver,under_sensitivity,gateway_tx,unclassified\n";
        for (uint32_t j = 0; j < gateways.GetN(); ++j)
        {
            auto counts = tracker.CountPhyPacketsPerGw(Seconds(0),Seconds(duration+drain),gateways.Get(j)->GetId());
            int classified = std::accumulate(counts.begin()+1, counts.end(), 0);
            invariant = invariant && counts[0] == static_cast<int>(attempts) && classified == counts[0];
            gatewayMetrics << gateways.Get(j)->GetId() << ',' << matrixGatewayIds[gwColumns[j]];
            for (int count : counts) gatewayMetrics << ',' << count;
            gatewayMetrics << ',' << counts[0]-classified << '\n';
        }
        auto metrics = stream("metrics.json");
        metrics << "{\n\"n_devices\":" << nDevices << ",\n\"n_gateways\":" << gateways.GetN()
                << ",\n\"generated\":" << generated << ",\n\"tx_unique\":" << tx
                << ",\n\"tx_attempts\":" << attempts << ",\n\"gw_unique\":" << gw
                << ",\n\"server_unique\":" << ns << ",\n\"not_transmitted\":" << generated-tx
                << ",\n\"pdr_gw_generated_pct\":" << Percent(gw,generated)
                << ",\n\"pdr_server_generated_pct\":" << Percent(ns,generated)
                << ",\n\"pdr_gw_tx_pct\":" << (tx ? std::to_string(Percent(gw,tx)) : "null")
                << ",\n\"pdr_server_tx_pct\":" << (tx ? std::to_string(Percent(ns,tx)) : "null")
                << ",\n\"gw_reception_events\":" << audit.gwEvents
                << ",\n\"server_reception_events\":" << audit.serverEvents
                << ",\n\"interference_events\":" << audit.outcomes["interference"]
                << ",\n\"under_sensitivity_events\":" << audit.outcomes["under_sensitivity"]
                << ",\n\"no_receiver_events\":" << audit.outcomes["no_receiver"]
                << ",\n\"delay_events\":" << audit.outcomes["mac_delayed"]
                << ",\n\"unknown_events\":" << audit.unknown
                << ",\n\"suppressed_reply_events\":" << audit.suppressedReplies
                << ",\n\"tracker_mac_sent\":" << trackerSent
                << ",\n\"tracker_mac_received\":" << trackerReceived
                << ",\n\"mean_server_latency_s\":";
        if (ns) metrics << latencySum/ns; else metrics << "null";
        metrics << ",\n\"invariants_ok\":" << (invariant ? "true" : "false") << "\n}\n";
        std::cout << "generated=" << generated << " tx_unique=" << tx << " gw_unique=" << gw
                  << " server_unique=" << ns << " PDR_server=" << Percent(ns,generated)
                  << "% invariants=" << invariant << std::endl;
        Simulator::Destroy();
        if (!invariant) throw std::runtime_error("Audit invariants failed; results are not valid");
        return 0;
    }
    catch (const std::exception& error)
    {
        std::cerr << "VALIDATION ERROR: " << error.what() << std::endl;
        return 1;
    }
}
