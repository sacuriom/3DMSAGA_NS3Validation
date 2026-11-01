function MDPI_Suite_MesoCellular_6
    % =====================================================================
    % DOCTORAL THESIS: MESO-CELLULAR SUITE (NATIVE 3D ENGLISH VERSION)
    % QoS Tables, K-Coverage, HD Export & Academic Perspectives
    % =====================================================================
    clc; close all; warning('off', 'all');
    
    disp('======================================================');
    disp(' INITIALIZING 3D LORAWAN SIMULATOR (ENGLISH RELEASE) ');
    disp('======================================================');
    
    %% 1. CITY SELECTION
    Cities(1) = struct('Name','Ambato, ECU', 'Lat',-1.2417, 'Lon',-78.6197, 'Alt',2580);
    Cities(2) = struct('Name','Cuenca, ECU', 'Lat',-2.9001, 'Lon',-79.0059, 'Alt',2560);
    Cities(3) = struct('Name','Quito, ECU',  'Lat',-0.1807, 'Lon',-78.4678, 'Alt',2850);
    
    [indx, tf] = listdlg('PromptString', 'Select City for Optimization:', ...
                         'SelectionMode', 'single', 'ListString', {Cities.Name}, 'ListSize', [250 120]);
    if ~tf, disp('Operation cancelled by user.'); return; end
    City = Cities(indx);
    
    %% 2. USER INTERFACE: RF & COVERAGE PARAMETERS
    prompt = {'Spreading Factor (SF 7 to 12):', ...
              'Gateway Antenna Installation Height (meters):', ...
              'Target Physical Coverage (%):'};
    dlgtitle = 'Simulation Parameters (ITU-R 3D Model)';
    dims = [1 65];
    definput = {'10', '6', '95'}; % Default: SF10, 6m pole, 95% cov
    answer = inputdlg(prompt, dlgtitle, dims, definput);
    
    if isempty(answer), disp('Operation cancelled by user.'); return; end
    
    HW.Name = 'Milesight UG67 Outdoor';
    HW.Freq = 915;          
    HW.Ptx = 27;            
    HW.Gain = 5;            
    HW.PenetrationLoss = 0; 
    
    HW.SF = str2double(answer{1});
    HW.Height = str2double(answer{2});
    Target_Cov = str2double(answer{3}) / 100;
    
    Sens_Map = containers.Map({7,8,9,10,11,12}, {-125, -128, -131, -134, -136, -137});
    if isKey(Sens_Map, HW.SF), HW.Sens = Sens_Map(HW.SF);
    else, disp('Error: Invalid Spreading Factor. Must be an integer between 7 and 12.'); return; end
    
    fecha_hora = datestr(now, 'yyyymmdd_HHMMSS');
    folder_name = sprintf('Results_Meso_%s_SF%d_%s', strrep(City.Name, ', ', '_'), HW.SF, fecha_hora);
    mkdir(folder_name);
    
    fprintf('\n -> RF PARAMETERIZATION LOADED:\n');
    fprintf('    - City: %s\n', City.Name);
    fprintf('    - Spreading Factor: SF%d (Rx Sensitivity: %d dBm)\n', HW.SF, HW.Sens);
    fprintf('    - Antenna Height: %d meters | Target Coverage: %.1f%%\n\n', HW.Height, Target_Cov*100);
    
    %% 3. DIGITAL TWIN & TOPOLOGY EXTRACTION
    disp(' -> [PHASE 1] Downloading OSM Topology and SRTM DEM Elevation...');
    T_Twin = Build_DigitalTwin_Robust(City, 0.020); 
    if isempty(T_Twin), disp('Critical Error building the Digital Twin.'); return; end
    N_nodes = height(T_Twin);
    fprintf(' -> Success! %d road intersections mapped with 3D terrain.\n', N_nodes);
    
    %% 4. NATIVE 3D RF MATRIX COMPUTATION
    disp(' -> [PHASE 2] Computing 3D RF Propagation Matrix (Diffraction & Clutter)...');
    [BinM_3D, Pts_3D, RSSI_Matrix] = Precompute_RF_ITU(T_Twin, HW);
    
    max_cov = sum(sum(BinM_3D, 2) > 0) / N_nodes;
    if max_cov < Target_Cov
        Target_Cov = max_cov * 0.99; 
        fprintf('    [!] Adjusted for severe terrain attenuation: New Target = %.2f%%\n', Target_Cov*100);
    end
    Area_km2 = (max(T_Twin.Lat) - min(T_Twin.Lat)) * 111.32 * (max(T_Twin.Lon) - min(T_Twin.Lon)) * 111.32 * cosd(mean(T_Twin.Lat));
    
    %% 5. OPTIMIZATION BENCHMARK
    disp(' -> [PHASE 3] Executing Algorithm Benchmark...');
    Results = table('Size',[4 7], 'VariableTypes', {'string','double','double','double','double','double','double'}, ...
                    'VariableNames', {'Algorithm', 'Gateways', 'Coverage_Pct', 'Cov_1GW', 'Cov_2GW', 'Cov_3PlusGW', 'Time_s'});
    Solutions = cell(4,1);
    Exec_Logs = strings(4,1);
    Algo_Names = ["Greedy SCP", "K-Medoids 3D", "Standard SAGA", "Proposed 3D-M-SAGA"];
    
    disp('    [A] Running Greedy Heuristic...');
    tic; [Solutions{1}, Exec_Logs(1)] = Run_Greedy(BinM_3D, Target_Cov); t1 = toc;
    Results(1,:) = Extract_KPIs(Algo_Names(1), Solutions{1}, BinM_3D, t1);
    
    disp('    [B] Running Spatial K-Medoids...');
    tic; [Solutions{2}, Exec_Logs(2)] = Run_KMedoids(Pts_3D, BinM_3D, Target_Cov); t2 = toc;
    Results(2,:) = Extract_KPIs(Algo_Names(2), Solutions{2}, BinM_3D, t2);
    
    disp('    [C] Running Standard Genetic Algorithm (SAGA)...');
    tic; [Solutions{3}, Exec_Logs(3)] = Run_GA(BinM_3D, Target_Cov, false, "Standard SAGA"); t3 = toc;
    Results(3,:) = Extract_KPIs(Algo_Names(3), Solutions{3}, BinM_3D, t3);
    
    disp('    [D] Running Memetic Spatially-Aware GA (3D-M-SAGA)...');
    tic; [Solutions{4}, Exec_Logs(4)] = Run_GA(BinM_3D, Target_Cov, true, "3D-M-SAGA"); t4 = toc;
    Results(4,:) = Extract_KPIs(Algo_Names(4), Solutions{4}, BinM_3D, t4);
    
    %% 6. CONSOLE TABLE OUPUT
    disp(' ');
    disp('==================================================================================================');
    disp(' NETWORK HEALTH & K-COVERAGE COMPARATIVE TABLE ');
    disp('==================================================================================================');
    fprintf('%-20s | %-8s | %-12s | %-12s | %-12s | %-12s | %-10s\n', 'Algorithm', 'Gateways', 'Coverage %', 'K=1 (Risk)', 'K=2 (Ideal)', 'K>=3 (Excess)', 'Time (s)');
    disp('--------------------------------------------------------------------------------------------------');
    for i = 1:4
        fprintf('%-20s | %-8d | %-12.2f | %-12.2f | %-12.2f | %-12.2f | %-10.2f\n', ...
            Results.Algorithm(i), Results.Gateways(i), ...
            Results.Coverage_Pct(i), Results.Cov_1GW(i), Results.Cov_2GW(i), Results.Cov_3PlusGW(i), Results.Time_s(i));
    end
    disp('==================================================================================================');
    
    %% 7. EXPORT REPORTS & 3D HD RENDERS
    disp(' -> [PHASE 4] Generating HTML Reports and Exporting 600 DPI 3D Maps...');
    Generate_Academic_Report(City, HW, Target_Cov, Area_km2, Results, Solutions, Algo_Names, T_Twin, RSSI_Matrix, Exec_Logs, folder_name);
    
    for k = 1:4, Export_CSV_Data(Algo_Names(k), Solutions{k}, T_Twin, RSSI_Matrix, HW, folder_name); end
    
    pos = {[50, 500, 600, 450], [660, 500, 600, 450], [50, 40, 600, 450], [660, 40, 600, 450]};
    for k = 1:4
        Render_Interactive_3D(T_Twin, Solutions{k}, RSSI_Matrix, BinM_3D, HW, City.Name, Algo_Names(k), pos{k}, folder_name); 
    end
    
    disp('======================================================');
    disp(' -> SUCCESS! All academic assets (.csv, .html, .png, .fig) saved.');
    disp([' -> Check directory: ', folder_name]);
    disp('======================================================');
end

%% ========================================================================
%% 1. DIGITAL TWIN CONSTRUCTION
%% ========================================================================
function T = Build_DigitalTwin_Robust(City, dist)
    min_lat = City.Lat - dist; min_lon = City.Lon - dist; max_lat = City.Lat + dist; max_lon = City.Lon + dist;
    options = weboptions('Timeout', 120); 
    q_osm = sprintf('[out:json][timeout:120];(way["highway"~"^(primary|secondary|tertiary|residential)$"](%f,%f,%f,%f););out body;>;out skel qt;', min_lat, min_lon, max_lat, max_lon);
    try data = webread('https://lz4.overpass-api.de/api/interpreter', 'data', q_osm, options); catch, disp('[!] OSM Download Error.'); T = []; return; end
    
    c_nodes = containers.Map('KeyType','uint64','ValueType','any'); c_names = containers.Map('KeyType','uint64','ValueType','any');
    for i=1:length(data.elements)
        e = data.elements(i); if iscell(data.elements), e=e{1}; end
        if strcmp(e.type,'node'), c_nodes(e.id) = [e.lat, e.lon];
        elseif strcmp(e.type,'way') && isfield(e, 'nodes')
            street = "Unnamed Road"; if isfield(e, 'tags') && isfield(e.tags, 'name'), street = string(e.tags.name); end
            for k=1:length(e.nodes), nid = e.nodes(k); if iscell(e.nodes), nid=nid{1}; end
                if isKey(c_names, nid), c_names(nid) = [c_names(nid), street]; else, c_names(nid) = street; end
            end
        end
    end
    
    lat = []; lon = []; c1 = []; c2 = []; keys_n = c_names.keys;
    for k = 1:length(keys_n)
        nid = keys_n{k}; noms = unique(c_names(nid)); 
        if length(noms) >= 2 && isKey(c_nodes, nid), coords = c_nodes(nid); lat = [lat; coords(1)]; lon = [lon; coords(2)]; c1 = [c1; noms(1)]; c2 = [c2; noms(2)]; end
    end
    N = length(lat); Alt_m = zeros(N, 1);
    
    disp('      -> Fetching NASA SRTM Topography...');
    chunk = 80; err_api = 0;
    for b = 1:chunk:N
        fin = min(b + chunk - 1, N); loc_str = strjoin(arrayfun(@(idx) sprintf('%f,%f', lat(idx), lon(idx)), b:fin, 'UniformOutput', false), '|'); exito = false;
        for retry = 1:3
            try res = webread(sprintf('https://api.opentopodata.org/v1/srtm30m?locations=%s', loc_str), weboptions('Timeout', 20)); if isfield(res, 'results'), Alt_m(b:fin) = arrayfun(@(x) x.elevation, res.results); exito = true; break; end; catch, pause(2); end
        end
        if ~exito, err_api = err_api + 1; Alt_m(b:fin) = City.Alt; end; pause(1.2); 
    end
    
    R_earth = 6371000; X_m = deg2rad(lon - City.Lon) * R_earth * cosd(City.Lat); Y_m = deg2rad(lat - City.Lat) * R_earth;
    Clutter = strings(N, 1);
    for i = 1:N
        neighbors = sum(sqrt((X_m - X_m(i)).^2 + (Y_m - Y_m(i)).^2) < 300);
        if neighbors > 40, Clutter(i) = "Dense Urban"; elseif neighbors > 15, Clutter(i) = "Residential"; else, Clutter(i) = "Park/Periphery"; end
    end
    T = unique(table(c1, c2, Alt_m, lat, lon, X_m, Y_m, Clutter, 'VariableNames', {'Street_1', 'Street_2', 'Altitude_m', 'Lat', 'Lon', 'X_m', 'Y_m', 'Clutter'}), 'rows');
end

%% ========================================================================
%% 2. NATIVE 3D RF LINK BUDGET (ITU-R)
%% ========================================================================
function [BinM_3D, Pts_3D, RSSI_Matrix] = Precompute_RF_ITU(T, HW)
    N = height(T); BinM_3D = false(N, N); RSSI_Matrix = zeros(N,N) - 150; Pts_3D = [T.X_m, T.Y_m, T.Altitude_m];
    L0 = 20*log10(HW.Freq) - 27.55; 
    for gw = 1:N
        d_m = sqrt((T.X_m - T.X_m(gw)).^2 + (T.Y_m - T.Y_m(gw)).^2 + (T.Altitude_m - T.Altitude_m(gw)).^2); d_m(d_m < 1) = 1; 
        n_path = 3.2 * ones(N, 1); L_clut = zeros(N,1);
        idx_den = T.Clutter == "Dense Urban"; L_clut(idx_den) = 18; n_path(idx_den) = 3.8; 
        idx_prk = T.Clutter == "Park/Periphery"; L_clut(idx_prk) = 12; n_path(idx_prk) = 3.5; 
        
        Alt_GW_Real = T.Altitude_m(gw) + HW.Height; diff_alt = Alt_GW_Real - T.Altitude_m; 
        L_topo = zeros(N, 1); v_idx = diff_alt > 15; L_topo(v_idx) = min(15 * log10(diff_alt(v_idx)), 35); 
        c_idx = diff_alt < -15; L_topo(c_idx) = min(10 * log10(abs(diff_alt(c_idx))), 35); 
        
        rssi = (HW.Ptx + HW.Gain) - L0 - 10 .* n_path .* log10(d_m) - L_clut - HW.PenetrationLoss - L_topo;
        RSSI_Matrix(:, gw) = rssi; BinM_3D(:, gw) = rssi >= HW.Sens;
        if mod(gw, 500) == 0, fprintf('      -> Computing RF Links: %d / %d\n', gw, N); end
    end
end

%% ========================================================================
%% 3. ALGORITHMS (WITH ENGLISH LOGGING)
%% ========================================================================
function [sol, log_str] = Run_Greedy(BinM_3D, target)
    [N, C] = size(BinM_3D); sol = false(1, C); cov = false(N, 1); log_str = ">> STARTING GREEDY SCP HEURISTIC\n"; iter = 1;
    while (sum(cov)/N) < target
        b_g = 0; b_n = -1; cands = find(~sol);
        for i = cands, g = sum(BinM_3D(:, i) & ~cov); if g>b_g, b_g=g; b_n=i; end, end
        if b_n > 0
            sol(b_n) = true; cov = cov | BinM_3D(:, b_n); 
            log_str = log_str + sprintf("Step %d: Gateway assigned at index [%d]. Marginal Gain: +%d nodes. Current Cov: %.2f%%\n", iter, b_n, b_g, (sum(cov)/N)*100); iter=iter+1;
        else, log_str = log_str + "Final Step: No candidates provide additional coverage. Halting.\n"; break; end
    end
    log_str = log_str + sprintf(">> END GREEDY. Total Gateways: %d", sum(sol));
end

function [sol, log_str] = Run_KMedoids(Pts_3D, BinM_3D, target)
    N_c = size(BinM_3D, 2); sol = false(1, N_c); max_k = 30; log_str = ">> STARTING SPATIAL K-MEDOIDS 3D\n";
    for k = 1:2:max_k 
        log_str = log_str + sprintf("Iteration K=%d: Clustering intersections...", k);
        [~, C] = kmedoids(Pts_3D, k, 'Distance', 'euclidean', 'Replicates', 1, 'Options', statset('UseParallel', false));
        idx_m = zeros(1, k); for i=1:k, [~, real_i] = min(sum((Pts_3D - C(i,:)).^2, 2)); idx_m(i) = real_i; end
        cov_real = sum(sum(BinM_3D(:, idx_m), 2) > 0) / size(BinM_3D, 1);
        log_str = log_str + sprintf(" RF Matrix Evaluated. Coverage: %.2f%%\n", cov_real*100);
        if cov_real >= target, sol(idx_m) = true; log_str = log_str + sprintf(">> END K-MEDOIDS. Target reached with %d Gateways.", k); break; end
    end
end

function [sol, log_str] = Run_GA(BinM_3D, target, use_memetic, algo_name)
    [N, C] = size(BinM_3D); p_size = 24; gen = 30; Pop = rand(p_size, C) < (10/C); [Pop(1,:), ~] = Run_Greedy(BinM_3D, target); 
    log_str = sprintf(">> STARTING %s (Pop Size: %d, Generations: %d)\n", upper(algo_name), p_size, gen);
    for g = 1:gen
        Fit = zeros(p_size, 1); max_cov = 0; min_gw = C;
        for i = 1:p_size
            mapa = sum(BinM_3D(:, find(Pop(i,:))), 2); c_tot = sum(mapa >= 1)/N; c_k2 = sum(mapa >= 2)/N; gw_cnt = sum(Pop(i,:));
            if c_tot > max_cov, max_cov = c_tot; min_gw = gw_cnt; end
            Fit(i) = (c_tot * 10000) + (c_k2 * 1000) - (gw_cnt * 50);
            if c_tot < target, Fit(i) = Fit(i) - 50000; end
        end
        if mod(g, 5) == 0 || g == 1, log_str = log_str + sprintf("Gen %d: Best individual -> Cov: %.2f%% | GWs: %d\n", g, max_cov*100, min_gw); end
        [~, b] = max(Fit); Best = Pop(b,:); NewPop = Pop;
        for i = 2:2:p_size
            p1 = Pop(randi(p_size),:); p2 = Pop(randi(p_size),:); mask = rand(1, C) > 0.5; c1 = p1; c1(mask) = p2(mask);
            if rand < 0.8, if use_memetic, c1 = Smart_Repair(c1, BinM_3D, target); else, mut = randi(C); c1(mut) = ~c1(mut); end; end
            NewPop(i,:) = c1;
        end
        Pop = NewPop; Pop(1,:) = Best;
    end
    sol = Pop(1,:); log_str = log_str + sprintf(">> END %s. Best solution exported with %d Gateways.", upper(algo_name), sum(sol));
end

function ind = Smart_Repair(ind, BinM_3D, target)
    N = size(BinM_3D, 1); max_iter = 10; iter = 0;
    while iter < max_iter
        iter = iter + 1; idx = find(ind); mapa = sum(BinM_3D(:, idx), 2);
        if (sum(mapa >= 1) / N) >= target
            if length(idx) > 1, unq = (mapa == 1); sc = sum(BinM_3D(:, idx) & unq, 1); [val, w] = min(sc); if val < 5, ind(idx(w)) = false; continue; end; end; break;
        else
            unc = (mapa == 0); cands = find(~ind); if isempty(cands), break; end
            gains = sum(BinM_3D(unc, cands), 1); [bg, best_idx] = max(gains);
            if bg > 0, bn = cands(best_idx); ind(bn) = true; else, break; end
        end
    end
end

%% ========================================================================
%% EXPORT DATA & REPORTS (ENGLISH)
%% ========================================================================
function row = Extract_KPIs(name, sol, BinM_3D, time_s)
    idx = find(sol); n_gws = length(idx); N = size(BinM_3D, 1);
    if n_gws == 0, row = {name, 0, 0, 0, 0, 0, round(time_s,2)}; return; end
    mapa = sum(BinM_3D(:, idx), 2);
    c_tot = round((sum(mapa >= 1)/N)*100, 2);
    k1 = round((sum(mapa == 1)/N)*100, 2); k2 = round((sum(mapa == 2)/N)*100, 2); k3 = round((sum(mapa >= 3)/N)*100, 2);
    row = {name, n_gws, c_tot, k1, k2, k3, round(time_s, 2)};
end

function Export_CSV_Data(algo, sol, T, RSSI, HW, folder)
    idx = find(sol); N = height(T);
    Srv = zeros(N, 1); Pwr = zeros(N, 1) - 150; Status = strings(N, 1); Status(:) = "OUTAGE";
    if ~isempty(idx)
        [max_r, max_i] = max(RSSI(:, idx), [], 2);
        for i = 1:N, if max_r(i) >= HW.Sens, Pwr(i) = round(max_r(i), 2); Srv(i) = max_i(i); Status(i) = "CONNECTED"; end; end
    end
    Export = table((1:N)', T.Street_1, T.Street_2, T.Clutter, T.Altitude_m, T.Lat, T.Lon, Srv, Pwr, Status, ...
        'VariableNames', {'Node_ID', 'Primary_Street', 'Secondary_Street', 'Morphological_Clutter', 'Altitude_m', 'Latitude', 'Longitude', 'Serving_GW_ID', 'RSSI_dBm', 'Status'});
    writetable(Export, fullfile(folder, sprintf('DigitalTwin_%s.csv', strrep(algo, ' ', '_'))));
end

function Generate_Academic_Report(City, HW, T_Cov, Area, Res, Sols, Names, T, RSSI, Logs, folder)
    file = fullfile(folder, 'Academic_Deployment_Report.html'); fid = fopen(file, 'w', 'n', 'UTF-8');
    
    fprintf(fid, '<!DOCTYPE html><html><head><meta charset="UTF-8"><style>body{font-family:Arial, sans-serif;margin:40px;color:#333;line-height:1.6;} table{border-collapse:collapse;width:100%%;margin-bottom:30px;} th,td{border:1px solid #ccc;padding:10px;text-align:center;font-size:14px;} th{background-color:#003366;color:white;} .box{background-color:#f0f4f8;padding:20px;border-left:5px solid #003366;margin-bottom:20px;} h2{color:#003366;border-bottom:2px solid #ccc;padding-bottom:5px;} .log{background-color:#1e1e1e;color:#00ff00;padding:15px;font-family:monospace;font-size:12px;white-space:pre-wrap;}</style></head><body>\n');
    fprintf(fid, '<h1>LoRaWAN Network Deployment & QoS Report</h1>\n');
    fprintf(fid, '<div class="box"><p><strong>Target City:</strong> %s</p><p><strong>Evaluated Area:</strong> %.2f km²</p><p><strong>Required Coverage:</strong> %.1f%%</p></div>\n', City.Name, Area, T_Cov*100);
    
    % Section 1
    fprintf(fid, '<h2>1. A Priori RF Parameters (ITU-R 3D Constraints)</h2>\n');
    fprintf(fid, '<table><tr><th>Hardware Profile</th><th>Frequency</th><th>Spreading Factor</th><th>Sensitivity Limit</th><th>Tx Power</th><th>Antenna Height ($H_{ant}$)</th></tr><tr><td>%s</td><td>%d MHz</td><td><strong>SF%d</strong></td><td>%.1f dBm</td><td>%.1f dBm</td><td><strong>%d meters</strong></td></tr></table>\n', HW.Name, HW.Freq, HW.SF, HW.Sens, HW.Ptx, HW.Height);
    
    % Section 2
    fprintf(fid, '<h2>2. Algorithm Benchmark & Network Health (K-Coverage)</h2>\n');
    fprintf(fid, '<table><tr><th>Optimization Algorithm</th><th>Gateways Deployed</th><th>Physical Coverage</th><th>K=1 (Single Point Failure Risk)</th><th>K=2 (Ideal Redundancy)</th><th>K&ge;3 (Over-provisioning)</th><th>CPU Time (s)</th></tr>\n');
    for i = 1:height(Res), fprintf(fid, '<tr><td><strong>%s</strong></td><td>%d</td><td>%.2f%%</td><td><span style="color:#d32f2f;">%.2f%%</span></td><td><span style="color:#388e3c;font-weight:bold;">%.2f%%</span></td><td>%.2f%%</td><td>%.2fs</td></tr>\n', Res.Algorithm(i), Res.Gateways(i), Res.Coverage_Pct(i), Res.Cov_1GW(i), Res.Cov_2GW(i), Res.Cov_3PlusGW(i), Res.Time_s(i)); end
    fprintf(fid, '</table>\n');
    
    % Section 3: QOS TABLES PER ALGORITHM
    fprintf(fid, '<h2>3. Detailed Gateway Deployment & QoS Analysis (Spreading Factor Breakdown)</h2>\n');
    for k = 1:4
        idx_gws = find(Sols{k}); if isempty(idx_gws), continue; end
        fprintf(fid, '<h3>Algorithm: %s</h3>\n', Names(k));
        fprintf(fid, '<table><tr><th>GW ID</th><th>Location (Intersection)</th><th>Altitude (Terrain + $H_{ant}$)</th><th>Average Serving Radius (m)</th><th style="background-color:#2e7d32;">Excellent (SF7-8)</th><th style="background-color:#f57f17;">Good (SF9-10)</th><th style="background-color:#c62828;">Marginal (SF11-12)</th><th>Total Nodes Served</th></tr>\n');
        
        Sub_RSSI = RSSI(:, idx_gws); [max_r, max_i] = max(Sub_RSSI, [], 2);
        for g = 1:length(idx_gws)
            gw_id = idx_gws(g);
            idx_served = find((max_i == g) & (max_r >= HW.Sens));
            n_tot = length(idx_served);
            if n_tot > 0
                rs = max_r(idx_served);
                n_exc = sum(rs >= -105); n_gd = sum(rs < -105 & rs >= -115); n_mg = sum(rs < -115);
                dist = sqrt((T.X_m(idx_served) - T.X_m(gw_id)).^2 + (T.Y_m(idx_served) - T.Y_m(gw_id)).^2);
                rad = mean(dist);
            else, n_exc=0; n_gd=0; n_mg=0; rad=0; end
            
            loc = sprintf('%s & %s', T.Street_1(gw_id), T.Street_2(gw_id));
            fprintf(fid, '<tr><td><strong>GW-%d</strong></td><td>%s</td><td>%.1f m</td><td>%.1f m</td><td>%d</td><td>%d</td><td>%d</td><td><strong>%d</strong></td></tr>\n', g, loc, T.Altitude_m(gw_id)+HW.Height, rad, n_exc, n_gd, n_mg, n_tot);
        end
        fprintf(fid, '</table>\n');
    end
    
    % Section 4: LOGS (Renumerado)
    fprintf(fid, '<h2>4. Heuristic Execution Logs</h2>\n');
    for k = 1:4, fprintf(fid, '<h3>%s</h3>\n<div class="log">%s</div>\n', Names(k), Logs(k)); end
    
    fprintf(fid, '</body></html>\n'); fclose(fid);
end

% =========================================================================
% UPDATED: ACADEMIC 3D RENDERER WITH AXIS LABELS, COLORBAR, AND KPI OVERLAY
% =========================================================================
function Render_Interactive_3D(T, sol, RSSI_Matrix, BinM_3D, HW, city, algo, pos, folder)
    % Inputs: accepts BinM_3D to calculate redundant coverage on the fly
    idx = find(sol);
    if isempty(idx), return; end
    N = height(T);
    Best_R = zeros(N, 1)-150;
    Srv = zeros(N, 1);

    % Hard Handoff mapping
    [max_r, max_i] = max(RSSI_Matrix(:, idx), [], 2);
    for i=1:N
        if max_r(i)>=HW.Sens
            Best_R(i)=max_r(i);
            Srv(i)=max_i(i);
        end
    end
    alive = Best_R >= HW.Sens;
    dead = Best_R < HW.Sens;

    % --- NEW: KPI Calculation for text overlay ---
    % Calculate KPIs based on the specific solution 'sol' and coverage matrix 'BinM_3D'
    k_map = sum(BinM_3D(:, idx), 2); % Number of GWs serving each node
    cov_pct = (sum(k_map >= 1) / N) * 100;
    k2_plus_pct = (sum(k_map >= 2) / N) * 100;
    n_gws = length(idx);
    % ------------------------------------------------

    % Pre-existing Tooltip strings (Keep these for interactivity)
    s_sts = T.Street_1 + " & " + T.Street_2; s_ll = string(T.Lat) + ", " + string(T.Lon);
    s_alt = string(round(T.Altitude_m, 1)) + " msnm"; s_gw = strings(N,1); s_gw(:) = "Outage"; s_rs = strings(N,1); s_rs(:) = "No Signal";
    for i=1:N, if alive(i), s_gw(i) = "GW " + string(Srv(i)); s_rs(i) = string(round(Best_R(i), 1)) + " dBm"; end; end
    tips = [dataTipTextRow('Streets:', s_sts); dataTipTextRow('Coords:', s_ll); dataTipTextRow('Elevation:', s_alt); dataTipTextRow('Server:', s_gw); dataTipTextRow('Signal:', s_rs)];

    f3d = figure('Name', sprintf('[%s] 3D Twin - %s', algo, city), 'Position', pos, 'Color', 'w');
    a3d = axes(f3d);
    hold(a3d, 'on');
    grid(a3d, 'on');

    % Main scatter plots
    s_d = scatter3(a3d, T.X_m(dead), T.Y_m(dead), T.Altitude_m(dead), 10, [0.7 0.7 0.7], 'filled', 'MarkerFaceAlpha', 0.5);
    s_a = scatter3(a3d, T.X_m(alive), T.Y_m(alive), T.Altitude_m(alive), 25, Best_R(alive), 'filled', 'MarkerFaceAlpha', 0.9);
    s_d.DataTipTemplate.DataTipRows = tips; s_a.DataTipTemplate.DataTipRows = tips;

    % Gateway locations
    sgw = scatter3(a3d, T.X_m(idx), T.Y_m(idx), T.Altitude_m(idx)+HW.Height, 400, 'w', '^', 'filled', 'MarkerEdgeColor', 'k', 'LineWidth', 1.5);
    
    gtips = [dataTipTextRow('ID:', "GW-" + string(1:length(idx))'); dataTipTextRow('Location:', T.Street_1(idx) + " & " + T.Street_2(idx)); dataTipTextRow('RF Setup:', repmat(string(sprintf('SF%d | H: %dm', HW.SF, HW.Height)), length(idx), 1))];
    sgw.DataTipTemplate.DataTipRows = gtips;

    for k = 1:length(idx), text(a3d, T.X_m(idx(k)), T.Y_m(idx(k)), T.Altitude_m(idx(k))+HW.Height, num2str(k), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', 'FontWeight', 'bold', 'FontSize', 10, 'Color', 'k'); end

    % Plot appearance
    daspect(a3d, [1 1 0.1]); % 10x vertical exaggeration
    colormap(a3d, 'jet');
    clim(a3d, [HW.Sens, -70]);
    view(a3d, -35, 45);
    title(sprintf('%s Analysis', algo), 'FontSize', 12, 'FontWeight', 'bold');

    % --- NEW: Academic Axis Labels & Colorbar ---
    % X/Y must remain in projected meters for correct daspect geometry. Inform user.
    xlabel(a3d, 'Projected X (Meters)');
    ylabel(a3d, 'Projected Y (Meters)');
    zlabel(a3d, 'Altitude (MSNM)'); % Metric altitude label

    cb = colorbar(a3d);
    ylabel(cb, 'Received Signal Strength RSSI (dBm)');
    % ------------------------------------------------------

    % --- NEW: Dynamic KPI Text Overlay (Textbox annotation) ---
    % Create a professional info box in the top-left quadrant of the figure window
    infoStr = sprintf(['Gateways Deployed: %d\n', ...
                       'Physical Coverage: %.1f%%\n', ...
                       'Redundancy Index K\\ge2: %.1f%%'], n_gws, cov_pct, k2_plus_pct);
                   
    annotation(f3d, 'textbox', [0.15, 0.72, 0.35, 0.18], ... % [left bottom width height] (normalized)
        'String', infoStr, ...
        'FontSize', 10, ...
        'FontWeight', 'bold', ...
        'BackgroundColor', 'w', ...
        'EdgeColor', 'k', ...
        'FitBoxToText', 'on', ...
        'Margin', 8, ...
        'HorizontalAlignment', 'left');
    % -------------------------------------------------------------

    % Ensure everything is rendered before export
    drawnow; 
    
    name_cln = strrep(strrep(strrep(algo, ' ', '_'), '(', ''), ')', '');
    % High-resolution export
    exportgraphics(f3d, fullfile(folder, sprintf('3D_Map_%s.png', name_cln)), 'Resolution', 600);
    savefig(f3d, fullfile(folder, sprintf('Native_Fig_%s.fig', name_cln)));
end