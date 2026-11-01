#!/usr/bin/env python3
"""Reconstruct the archived Proposed deployment's native MATLAB RSSI matrix.

The export is allowed only after agreement with the archived best-link RSSI,
CONNECTED/OUTAGE classification and local serving gateway identifiers. NumPy
float64 reproduces the deterministic per-link calculation; no random RF input
is invented and OUTAGE=-150 is treated only as an archived censoring sentinel.
"""
from __future__ import annotations

import csv
import datetime as dt
import hashlib
import io
import json
import math
from pathlib import Path, PureWindowsPath
import platform
import sys

import numpy as np


BASE = Path(__file__).resolve().parent
THESIS = BASE.parents[1]
MATLAB = THESIS / "MDPI/3D/MDPI_Suite_MesoCellular_6.m"
FAMILY = THESIS / "MDPI/3D/Results_Meso_Ambato_ECU_SF11_20260228_115243"
PROPOSED = FAMILY / "DigitalTwin_Proposed_3D-M-SAGA.csv"
REPORT = FAMILY / "Academic_Deployment_Report.html"
ASSOCIATION = BASE / "asociacion_topologia.json"
GATEWAYS = BASE / "gateways.csv"
TOPOLOGY = BASE / "referencia_original/Matrix_PathLoss_3D.csv"
OUTPUT = BASE / "inputs/Matrix_RSSI_3DMSAGA_reconstruida.csv"
NODE_AUDIT = BASE / "inputs/Nodos_RSSI_3DMSAGA_reconstruida.csv"
MANIFEST = BASE / "inputs/Matrix_RSSI_3DMSAGA_reconstruida_manifest.json"
PINNED_MATLAB_SHA256 = "f653c048402a895652b4d09aa04cafe9219e64a3aa52936cde467aaf96657214"
PARAMETERS = {
    "city": "Ambato, ECU", "city_latitude_deg": -1.2417,
    "city_longitude_deg": -78.6197, "earth_radius_m": 6371000.0,
    "frequency_mhz": 915.0, "tx_power_dbm": 27.0, "gain_db": 5.0,
    "penetration_loss_db": 0.0, "gateway_height_m": 6.0,
    "archived_sf": 11, "archived_sensitivity_dbm": -136.0,
    "distance_floor_m": 1.0, "topography_transition_m": 15.0,
    "topography_cap_db": 35.0,
    "clutter": {"Dense Urban": {"n": 3.8, "loss_db": 18.0},
                "Residential": {"n": 3.2, "loss_db": 0.0},
                "Park/Periphery": {"n": 3.5, "loss_db": 12.0}},
}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_csv(path):
    with Path(path).open(newline="", encoding="utf-8-sig") as stream:
        return list(csv.DictReader(stream))


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def atomic_identical(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        require(path.read_bytes() == data, f"Existing output differs and was preserved: {path}")
        return
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_bytes(data)
    temporary.replace(path)


def native_basename(text):
    return PureWindowsPath(text).name if "\\" in text else Path(text).name


def main():
    require(sha(MATLAB) == PINNED_MATLAB_SHA256,
            "MATLAB source changed: the pinned RF translation requires a new source audit")
    association = json.loads(ASSOCIATION.read_text(encoding="utf-8-sig"))
    require(association.get("all_ten_associations_passed") is True,
            "The ten archived gateway associations have not passed validation")
    source_expectations = {native_basename(item["path"]): item["sha256"]
                           for item in association["sources"]}
    for path in (PROPOSED, REPORT, GATEWAYS):
        require(source_expectations.get(path.name) == sha(path),
                f"Associated input changed or is unrecognized: {path}")

    source_text = MATLAB.read_text(encoding="utf-8-sig")
    rf_start = source_text.index("function [BinM_3D, Pts_3D, RSSI_Matrix] = Precompute_RF_ITU")
    rf_end = source_text.index("%% ========================================================================", rf_start)
    rf_function = source_text[rf_start:rf_end].strip()
    require("rand" not in rf_function.lower(), "RF function unexpectedly contains a random component")
    report_text = REPORT.read_text(encoding="utf-8-sig")
    for token in ("915 MHz", "<strong>SF11</strong>", "-136.0 dBm", "27.0 dBm", "<strong>6 meters</strong>"):
        require(token in report_text, f"Archived RF report parameter missing: {token}")

    rows, topology = read_csv(PROPOSED), read_csv(TOPOLOGY)
    require(len(rows) == len(topology) == 2153, "Expected the validated 2153-node archived family")
    ids = np.array([int(row["Node_ID"]) for row in rows], dtype=np.int64)
    require(np.array_equal(ids, np.arange(1, 2154)), "Node IDs must retain the archived consecutive ordering")
    for left, right in zip(rows, topology):
        require(all(left[key] == right[key] for key in ("Node_ID", "Latitude", "Longitude")),
                f"Archived CSV and reference topology do not match at node {left['Node_ID']}")

    lat = np.array([float(row["Latitude"]) for row in rows], dtype=np.float64)
    lon = np.array([float(row["Longitude"]) for row in rows], dtype=np.float64)
    alt = np.array([float(row["Altitude_m"]) for row in rows], dtype=np.float64)
    clutter = np.array([row["Morphological_Clutter"] for row in rows])
    archived_rssi = np.array([float(row["RSSI_dBm"]) for row in rows], dtype=np.float64)
    archived_serving = np.array([int(row["Serving_GW_ID"]) for row in rows], dtype=np.int64)
    status = np.array([row["Status"] for row in rows])
    require(all(np.isfinite(array).all() for array in (lat, lon, alt, archived_rssi)), "Non-finite input metadata")
    require(set(clutter).issubset(PARAMETERS["clutter"]), "Unknown morphological clutter category")
    require(set(status).issubset({"CONNECTED", "OUTAGE"}), "Unknown archived status label")
    connected = status == "CONNECTED"
    require(int(connected.sum()) == 2133, "Unexpected archived CONNECTED count")
    require(np.all(archived_rssi[~connected] == -150) and np.all(archived_serving[~connected] == 0),
            "OUTAGE sentinel semantics changed; no signal values may be imputed")

    sites = sorted(association["gateways"], key=lambda row: row["matrix_gateway_id"])
    require([site["matrix_gateway_id"] for site in sites] == list(range(1, 11)), "Gateway columns must retain IDs 1..10")
    gateway_rows = read_csv(GATEWAYS)
    require([int(row["Gateway_ID"]) for row in gateway_rows] == list(range(1, 11)), "Gateway CSV ordering changed")
    gateway_indices = np.array([int(site["node_id"]) - 1 for site in sites], dtype=np.int64)
    require(len(set(gateway_indices.tolist())) == 10, "Gateway sites are not unique")
    mapping = []
    for site, row, index in zip(sites, gateway_rows, gateway_indices):
        require(int(rows[index]["Node_ID"]) == int(site["node_id"]), "Gateway node lookup changed")
        require(lat[index] == site["node_latitude"] and lon[index] == site["node_longitude"], "Associated site metadata changed")
        require(float(row["Latitude"]) == site["gateway_latitude"]
                and float(row["Longitude"]) == site["gateway_longitude"]
                and float(row["Height_m"]) == PARAMETERS["gateway_height_m"], "Gateway CSV differs from validated association")
        dx = np.deg2rad(lon - float(row["Longitude"])) * PARAMETERS["earth_radius_m"] * math.cos(math.radians(float(row["Latitude"])))
        dy = np.deg2rad(lat - float(row["Latitude"])) * PARAMETERS["earth_radius_m"]
        distances = np.sqrt(dx * dx + dy * dy)
        require(int(np.argmin(distances)) == index and float(distances[index]) < 0.15,
                "Nearest gateway intersection association is no longer valid")
        require(int(archived_serving[index]) == int(site["matrix_gateway_id"]), "Local serving GW ID at its own site changed")
        mapping.append({"matrix_gateway_id": int(site["matrix_gateway_id"]),
                        "node_id": int(ids[index]), "csv_row_1based": int(index + 1),
                        "latitude_used": float(lat[index]), "longitude_used": float(lon[index]),
                        "ground_altitude_m": float(alt[index]),
                        "gateway_height_m": PARAMETERS["gateway_height_m"],
                        "rounded_gateway_coordinate_distance_m": float(distances[index])})

    # Preserve the MATLAB projection and operation ordering. Gateway height is
    # used ONLY in L_topo; the archived d_m uses ground elevation differences.
    x = np.deg2rad(lon - PARAMETERS["city_longitude_deg"]) * PARAMETERS["earth_radius_m"] * math.cos(math.radians(PARAMETERS["city_latitude_deg"]))
    y = np.deg2rad(lat - PARAMETERS["city_latitude_deg"]) * PARAMETERS["earth_radius_m"]
    distance = np.sqrt((x[:, None] - x[gateway_indices]) ** 2
                       + (y[:, None] - y[gateway_indices]) ** 2
                       + (alt[:, None] - alt[gateway_indices]) ** 2)
    distance[distance < 1] = 1
    n_path = np.full(len(rows), 3.2, dtype=np.float64)
    clutter_loss = np.zeros(len(rows), dtype=np.float64)
    dense, park = clutter == "Dense Urban", clutter == "Park/Periphery"
    n_path[dense], clutter_loss[dense] = 3.8, 18.0
    n_path[park], clutter_loss[park] = 3.5, 12.0
    altitude_delta = alt[gateway_indices] + PARAMETERS["gateway_height_m"] - alt[:, None]
    topography_loss = np.zeros_like(distance)
    above, below = altitude_delta > 15, altitude_delta < -15
    topography_loss[above] = np.minimum(15 * np.log10(altitude_delta[above]), 35)
    topography_loss[below] = np.minimum(10 * np.log10(np.abs(altitude_delta[below])), 35)
    l0 = 20 * np.log10(PARAMETERS["frequency_mhz"]) - 27.55
    rssi = ((PARAMETERS["tx_power_dbm"] + PARAMETERS["gain_db"])
            - l0 - 10 * n_path[:, None] * np.log10(distance) - clutter_loss[:, None]
            - PARAMETERS["penetration_loss_db"] - topography_loss)
    require(rssi.shape == (2153, 10) and np.isfinite(rssi).all(), "Invalid reconstructed RF matrix")
    require(np.allclose(rssi[gateway_indices, np.arange(10)],
                        PARAMETERS["tx_power_dbm"] + PARAMETERS["gain_db"] - l0 - clutter_loss[gateway_indices],
                        rtol=0, atol=1e-12), "Self-site RSSI does not match the source distance floor/clutter/gain formula")

    # NumPy argmax keeps the first maximum, matching MATLAB's column-order max.
    best = rssi.max(axis=1)
    serving = rssi.argmax(axis=1) + 1
    reconstructed_connected = best >= PARAMETERS["archived_sensitivity_dbm"]
    error = best[connected] - archived_rssi[connected]
    max_error = float(np.max(np.abs(error)))
    status_mismatches = np.flatnonzero(reconstructed_connected != connected)
    serving_mismatches = np.flatnonzero(connected & (serving != archived_serving))
    # MATLAB round(value,2) uses ties away from zero, unlike Python round.
    rounded = np.copysign(np.floor(np.abs(best) * 100 + 0.5) / 100, best)
    rounded_mismatches = np.flatnonzero(connected & (np.abs(rounded - archived_rssi) > 1e-9))
    require(max_error < 0.011, f"Best-link RSSI error {max_error:.12g} dB exceeds the 0.011 dB acceptance limit")
    require(len(status_mismatches) == 0, f"CONNECTED/OUTAGE classification mismatches: {(status_mismatches + 1).tolist()}")
    require(len(serving_mismatches) == 0, f"Serving GW mismatches: {(serving_mismatches + 1).tolist()}")
    require(len(rounded_mismatches) == 0, f"Rounded RSSI mismatches: {(rounded_mismatches + 1).tolist()}")
    require(np.array_equal(serving[gateway_indices], np.arange(1, 11)), "Reconstructed gateway-site serving identities do not agree")

    buffer = io.StringIO(newline="")
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow(["Node_ID", "Latitude", "Longitude"] + [f"GW_{i}_RSSI" for i in range(1, 11)])
    for index, row in enumerate(rows):
        writer.writerow([row["Node_ID"], row["Latitude"], row["Longitude"]]
                        + [format(value, ".17g") for value in rssi[index]])
    output_bytes = buffer.getvalue().encode("utf-8")
    node_buffer = io.StringIO(newline="")
    node_writer = csv.writer(node_buffer, lineterminator="\n")
    node_writer.writerow(["Node_ID", "Latitude", "Longitude", "Altitude_m", "Morphological_Clutter",
                          "Best_RSSI_raw_dBm", "Serving_GW_raw_ID", "K_ge_m136", "K_ge_m135", "K_ge_m130",
                          "Archived_Status", "Archived_RSSI_dBm", "Archived_Serving_GW_ID"])
    k_values = {threshold: np.sum(rssi >= threshold, axis=1) for threshold in (-136, -135, -130)}
    for index, row in enumerate(rows):
        node_writer.writerow([row["Node_ID"], row["Latitude"], row["Longitude"], row["Altitude_m"],
                              row["Morphological_Clutter"], format(best[index], ".17g"), int(serving[index]),
                              *[int(k_values[threshold][index]) for threshold in (-136, -135, -130)],
                              row["Status"], row["RSSI_dBm"], row["Serving_GW_ID"]])
    node_bytes = node_buffer.getvalue().encode("utf-8")
    source_files = (MATLAB, PROPOSED, REPORT, ASSOCIATION, GATEWAYS, TOPOLOGY, Path(__file__))
    identity = {"sources_sha256": {str(path.resolve()): sha(path) for path in source_files},
                "output_sha256": hashlib.sha256(output_bytes).hexdigest(),
                "node_audit_sha256": hashlib.sha256(node_bytes).hexdigest(), "parameters": PARAMETERS}
    validation = {"nodes": 2153, "gateways": 10, "connected_compared": int(connected.sum()),
                  "outage_censored_rows": int((~connected).sum()),
                  "best_link_connected_max_abs_error_db": max_error,
                  "best_link_connected_rmse_db": float(np.sqrt(np.mean(error ** 2))),
                  "best_link_connected_mean_error_db": float(np.mean(error)),
                  "rounded_rssi_mismatches": int(len(rounded_mismatches)),
                  "status_mismatches": int(len(status_mismatches)),
                  "serving_gateway_mismatches_connected": int(len(serving_mismatches)),
                  "raw_rssi_min_dbm": float(rssi.min()), "raw_rssi_max_dbm": float(rssi.max()),
                  "best_outage_min_dbm": float(best[~connected].min()),
                  "best_outage_max_dbm": float(best[~connected].max()),
                  "best_link_coverage_pct": {str(threshold): float(np.mean(best >= threshold) * 100)
                                             for threshold in (-136, -135, -131, -130, -125)},
                  "k_coverage_pct": {str(threshold): {
                      "K0": float(np.mean(values == 0) * 100), "K1": float(np.mean(values == 1) * 100),
                      "K2": float(np.mean(values == 2) * 100), "Kge3": float(np.mean(values >= 3) * 100)}
                      for threshold, values in k_values.items()},
                  "self_site_rssi_and_gateway_identity_passed": True,
                  "acceptance_limit_max_abs_error_db": 0.011,
                  "all_acceptance_checks_passed": True}
    manifest = {"created_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
                "identity": identity, "validation": validation, "gateway_mapping": mapping,
                "output": str(OUTPUT), "shape": [2153, 10],
                "node_audit_output": str(NODE_AUDIT), "associated_gateway_csv": str(GATEWAYS),
                "formula": "RSSI=(Ptx+Gain)-(20*log10(freqMHz)-27.55)-10*n_receiver*log10(max(d_ground3D,1))-L_clutter_receiver-L_penetration-L_topography",
                "source_function": "Precompute_RF_ITU, MDPI_Suite_MesoCellular_6.m:179-196",
                "source_function_sha256": hashlib.sha256(rf_function.encode("utf-8")).hexdigest(),
                "projection_source": "Build_DigitalTwin_Robust, MDPI_Suite_MesoCellular_6.m:167",
                "numeric_semantics": "NumPy float64; first-column maximum; MATLAB ties-away-from-zero round only for archive comparison. Export retains unrounded per-link values.",
                "outage_semantics": "Archived OUTAGE=-150 is censored. No RSSI values are imputed from this sentinel. Raw OUTAGE link values are recomputed from the deterministic source formula.",
                "gateway_semantics": "Columns preserve validated local Proposed GW IDs1..10. RF calculation uses the associated intersection node's full CSV coordinates and altitude; rounded gateway CSV coordinates are used only to verify association.",
                "height_semantics": "Exactly as archived MATLAB: gateway installation height enters topography loss, not d_ground3D. No physical-model correction has been introduced.",
                "scope": "Reconstructs the deterministic archived native model. This is agreement with saved model outputs, not independent field validation and not a newly optimized SF7/SF9 deployment.",
                "gain_semantics": "The single MATLAB HW.Gain=5 dB term is already included in RSSI; importing as matrixReferenceDbm-RSSI must not add it again.",
                "randomness": "None in RF evaluation; stochastic optimization is not rerun. The saved Proposed ten gateway sites are reused.",
                "input_edits": "None: no RSSI clamping, no synthetic replacement of altitude, clutter or censored signal.",
                "environment": {"python": sys.version, "numpy": np.__version__, "platform": platform.platform()}}
    if MANIFEST.exists():
        previous = json.loads(MANIFEST.read_text(encoding="utf-8-sig"))
        require(previous.get("identity") == identity, "Existing reconstruction manifest belongs to different sources or output and was preserved")
        require(previous.get("validation") == validation, "Existing reconstruction validation differs and was preserved")
    atomic_identical(OUTPUT, output_bytes)
    atomic_identical(NODE_AUDIT, node_bytes)
    if not MANIFEST.exists():
        atomic_identical(MANIFEST, (json.dumps(manifest, indent=2, ensure_ascii=False, allow_nan=False) + "\n").encode("utf-8"))
    require(sha(OUTPUT) == identity["output_sha256"], "Output read-back hash mismatch")
    require(sha(NODE_AUDIT) == identity["node_audit_sha256"], "Node audit read-back hash mismatch")
    print(json.dumps({"output": str(OUTPUT), "node_audit": str(NODE_AUDIT),
                      "manifest": str(MANIFEST), **validation}, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        report = ("# Reconstrucción del modelo nativo\n\n"
                  "La reconstrucción no superó las verificaciones; no se autoriza una nueva exportación.\n\n"
                  f"Motivo: {error}\n\n"
                  "Los archivos originales y cualquier exportación anterior se conservan.\n")
        (BASE / "reconstruccion_modelo.md").write_text(report, encoding="utf-8")
        print("ERROR:", error, file=sys.stderr)
        sys.exit(1)
