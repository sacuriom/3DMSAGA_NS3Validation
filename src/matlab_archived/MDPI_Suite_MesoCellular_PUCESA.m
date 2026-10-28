function MDPI_Suite_MesoCellular_Offline
    % =====================================================================
    % TESIS DOCTORAL: OPTIMIZACIÓN LORAWAN 3D-M-SAGA (PARSER GEOJSON NATIVO)
    % Campus PUCESA como Gateway Ancla Invariable + Zona Urbana de Ambato
    % Rigor Metodológico para Revistas MDPI (Sensors / IoT)
    % =====================================================================
    clc; close all; warning('off', 'all');
    
    disp('=================================================================');
    disp(' INICIALIZANDO OPTIMIZADOR 3D LORAWAN (MODO GEOJSON LOCAL)       ');
    disp('=================================================================');
    
    %% 1. DEFINICIÓN DEL GATEWAY ANCLA (TELEMETRÍA TTN) Y PARÁMETROS BASE
    GW_Anchor.Name = 'Gateway2PUCESA';
    GW_Anchor.Lat  = -1.27458;
    GW_Anchor.Lon  = -78.63920;
    GW_Anchor.Alt  = 2855.0; % Cota base del terreno reportada por TTN
    
    City.Name = 'Ambato - Sector PUCESA y Centro';
    City.Lat  = (GW_Anchor.Lat + (-1.2417)) / 2; % Centroide de proyección
    City.Lon  = (GW_Anchor.Lon + (-78.6197)) / 2;
    City.Alt  = 2700;
    
    geojson_file = 'ambato_pucesa_osm.json';
    if ~isfile(geojson_file)
        error('Archivo "%s" no encontrado. Verifique la ruta en el directorio activo.', geojson_file);
    end
    
    %% 2. PARÁMETROS DE HARDWARE RF (MILESIGHT UG67 OUTDOOR)
    prompt = {'Spreading Factor (SF 7 a 12):', ...
              'Altura del Mástil del Gateway (metros):', ...
              'Cobertura Objetivo (%):'};
    dlgtitle = 'Configuración RF ITU-R 3D';
    dims = [1 65];
    definput = {'10', '6', '90'};
    answer = inputdlg(prompt, dlgtitle, dims, definput);
    if isempty(answer), disp('Operación cancelada por el usuario.'); return; end
    
    HW.Name = 'Milesight UG67 Outdoor';
    HW.Freq = 915;          % MHz (Banda ISM US915)
    HW.Ptx = 27;            % dBm
    HW.Gain = 5;            % dBi
    HW.PenetrationLoss = 0; % dB outdoor
    HW.SF = str2double(answer{1});
    HW.Height = str2double(answer{2});
    Target_Cov = str2double(answer{3}) / 100;
    
    Sens_Map = containers.Map({7,8,9,10,11,12}, {-125, -128, -131, -134, -136, -137});
    if isKey(Sens_Map, HW.SF)
        HW.Sens = Sens_Map(HW.SF);
    else
        error('SF inválido. Ingrese un valor entre 7 y 12.');
    end
    
    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    folder_name = sprintf('Results_PUCESA_GeoJSON_SF%d_%s', HW.SF, timestamp);
    mkdir(folder_name);
    
    %% 3. CONSTRUCCIÓN DEL GEMELO DIGITAL MEDIANTE GEOJSON LOCAL
    disp(' -> [FASE 1] Decodificando GeoJSON, extrayendo intersecciones y alturas SRTM...');
    T_Twin = Build_DigitalTwin_From_GeoJSON(geojson_file, City, GW_Anchor);
    if isempty(T_Twin), error('Error crítico procesando la topología GeoJSON.'); end
    
    N_nodes = height(T_Twin);
    fprintf(' -> Éxito: %d intersecciones viales consolidadas. Nodo 1 = Campus PUCESA.\n', N_nodes);
    
    %% 4. CÁLCULO DE LA MATRIZ DE PROPAGACIÓN NATIVA 3D (ITU-R)
    disp(' -> [FASE 2] Computando matriz de propagación RF 3D (Difracción y Morfología)...');
    [BinM_3D, Pts_3D, RSSI_Matrix] = Precompute_RF_ITU(T_Twin, HW);
    
    anchor_idx = 1;
    cov_pucesa_base = (sum(BinM_3D(:, anchor_idx)) / N_nodes) * 100;
    fprintf(' -> [BASE EMPÍRICA] Cobertura aportada por Gateway PUCESA aislado (SF%d): %.2f%%\n', HW.SF, cov_pucesa_base);
    
    max_achievable = sum(sum(BinM_3D, 2) > 0) / N_nodes;
    if max_achievable < Target_Cov
        Target_Cov = max_achievable * 0.99;
        fprintf('    [!] Target ajustado por relieve orográfico a: %.2f%%\n', Target_Cov * 100);
    end
    Area_km2 = (max(T_Twin.Lat) - min(T_Twin.Lat)) * 111.32 * ...
               (max(T_Twin.Lon) - min(T_Twin.Lon)) * 111.32 * cosd(mean(T_Twin.Lat));
    
    %% 5. BENCHMARK CON GATEWAY PUCESA FIJO (3D-M-SAGA VS OTROS)
    disp(' -> [FASE 3] Ejecutando benchmark metaheurístico (PUCESA fijo e invariable)...');
    Results = table('Size',[4 7], 'VariableTypes', {'string','double','double','double','double','double','double'}, ...
                    'VariableNames', {'Algorithm', 'Gateways', 'Coverage_Pct', 'Cov_1GW', 'Cov_2GW', 'Cov_3PlusGW', 'Time_s'});
    Solutions = cell(4,1);
    Exec_Logs = strings(4,1);
    Algo_Names = ["Greedy SCP (PUCESA Fijo)", "K-Medoids 3D (PUCESA Fijo)", ...
                  "Standard SAGA (PUCESA Fijo)", "Proposed 3D-M-SAGA (PUCESA Fijo)"];
    
    % A. Greedy
    tic; [Solutions{1}, Exec_Logs(1)] = Run_Greedy_Anchor(BinM_3D, Target_Cov, anchor_idx); t1 = toc;
    Results(1,:) = Extract_KPIs(Algo_Names(1), Solutions{1}, BinM_3D, t1);
    
    % B. K-Medoids
    tic; [Solutions{2}, Exec_Logs(2)] = Run_KMedoids_Anchor(Pts_3D, BinM_3D, Target_Cov, anchor_idx); t2 = toc;
    Results(2,:) = Extract_KPIs(Algo_Names(2), Solutions{2}, BinM_3D, t2);
    
    % C. Standard SAGA
    tic; [Solutions{3}, Exec_Logs(3)] = Run_GA_Anchor(BinM_3D, Target_Cov, false, "Standard SAGA", anchor_idx); t3 = toc;
    Results(3,:) = Extract_KPIs(Algo_Names(3), Solutions{3}, BinM_3D, t3);
    
    % D. 3D-M-SAGA (Memético de Tesis)
    tic; [Solutions{4}, Exec_Logs(4)] = Run_GA_Anchor(BinM_3D, Target_Cov, true, "3D-M-SAGA", anchor_idx); t4 = toc;
    Results(4,:) = Extract_KPIs(Algo_Names(4), Solutions{4}, BinM_3D, t4);
    
    %% 6. VISUALIZACIÓN DE TABLA COMPARATIVA
    disp(' ');
    disp('==================================================================================================');
    disp(' BENCHMARK DE DESPLIEGUE CON GATEWAY PUCESA ANCLADO (K-COVERAGE) ');
    disp('==================================================================================================');
    fprintf('%-30s | %-5s | %-10s | %-10s | %-10s | %-10s | %-8s\n', ...
            'Algoritmo', 'GWs', 'Cob %', 'K=1', 'K=2', 'K>=3', 'Tiempo');
    disp('--------------------------------------------------------------------------------------------------');
    for i = 1:4
        fprintf('%-30s | %-5d | %-10.2f | %-10.2f | %-10.2f | %-10.2f | %-8.2fs\n', ...
            Results.Algorithm(i), Results.Gateways(i), ...
            Results.Coverage_Pct(i), Results.Cov_1GW(i), Results.Cov_2GW(i), Results.Cov_3PlusGW(i), Results.Time_s(i));
    end
    disp('==================================================================================================');
    
    %% 7. EXPORTACIÓN DE ENTREGABLES CIENTÍFICOS Y GRÁFICOS 3D
    disp(' -> [FASE 4] Exportando dataset CSV, reporte HTML y mapas 3D...');
    Generate_Academic_Report(City, HW, Target_Cov, Area_km2, Results, Solutions, Algo_Names, T_Twin, RSSI_Matrix, Exec_Logs, folder_name);
    
    for k = 1:4
        Export_CSV_Data(Algo_Names(k), Solutions{k}, T_Twin, RSSI_Matrix, HW, folder_name);
    end
    
    pos = {[50, 500, 600, 450], [660, 500, 600, 450], [50, 40, 600, 450], [660, 40, 600, 450]};
    for k = 1:4
        Render_Interactive_3D(T_Twin, Solutions{k}, RSSI_Matrix, BinM_3D, HW, City.Name, Algo_Names(k), pos{k}, folder_name, anchor_idx); 
    end
    
    fprintf('\nEjecución finalizada con éxito. Archivos guardados en: %s\n', folder_name);
end

%% ========================================================================
%% PARSER NATIVO GEOJSON PARA TOPOLOGÍA VIAL
%% ========================================================================
function T = Build_DigitalTwin_From_GeoJSON(filename, City, GW_Anchor)
    raw = fileread(filename);
    data = jsondecode(raw);
    
    if ~isfield(data, 'features')
        error('El archivo JSON no contiene un FeatureCollection GeoJSON válido.');
    end
    
    % Contenedores de vértices y calles
    all_coords = []; 
    street_tags = string.empty(0, 1);
    
    for i = 1:length(data.features)
        f = data.features(i);
        if iscell(data.features), f = f{1}; end
        
        st_name = "Vía Sin Nombre";
        if isfield(f, 'properties') && isstruct(f.properties)
            if isfield(f.properties, 'name') && ~isempty(f.properties.name)
                st_name = string(f.properties.name);
            end
        end
        
        geom = f.geometry;
        if strcmp(geom.type, 'LineString')
            coords = geom.coordinates; % [lon, lat]
            n_pts = size(coords, 1);
            all_coords = [all_coords; coords]; %#ok<AGROW>
            street_tags = [street_tags; repmat(st_name, n_pts, 1)]; %#ok<AGROW>
        end
    end
    
    % Detección de intersecciones (puntos compartidos con tolerancia ~1 m)
    % Redondeo a 5 decimales (~1.1 metros de resolución)
    coords_round = round(all_coords, 5);
    [unique_pts, ~, ic] = unique(coords_round, 'rows');
    
    c1 = strings(size(unique_pts, 1), 1);
    c2 = strings(size(unique_pts, 1), 1);
    counts = zeros(size(unique_pts, 1), 1);
    
    for u = 1:size(unique_pts, 1)
        idx_match = find(ic == u);
        st_list = unique(street_tags(idx_match));
        counts(u) = length(st_list);
        c1(u) = st_list(1);
        if length(st_list) > 1
            c2(u) = st_list(2);
        else
            c2(u) = "Tramo Continuo";
        end
    end
    
    % Priorizar intersecciones viales reales (cruce de >= 2 vías nominadas)
    inter_idx = find(counts >= 2);
    if length(inter_idx) < 100
        % Si el GeoJSON contiene pocas intersecciones, conservar todos los vértices
        inter_idx = (1:size(unique_pts, 1))';
    end
    
    lon = unique_pts(inter_idx, 1);
    lat = unique_pts(inter_idx, 2);
    c1  = c1(inter_idx);
    c2  = c2(inter_idx);
    
    % Forzar la inclusión del Gateway PUCESA como NODO 1
    lat = [GW_Anchor.Lat; lat];
    lon = [GW_Anchor.Lon; lon];
    c1  = ["Campus PUCESA"; c1];
    c2  = ["Nodo Maestro TTN"; c2];
    
    N = length(lat);
    Alt_m = zeros(N, 1);
    Alt_m(1) = GW_Anchor.Alt; % Altura precisa confirmada por TTN
    
    % Gestión de caché local para elevaciones NASA SRTM
    cache_file = 'SRTM_Elevation_Cache.mat';
    loaded_cache = false;
    
    if isfile(cache_file)
        cached = load(cache_file);
        if isfield(cached, 'lat') && length(cached.lat) == N && norm(cached.lat - lat) < 1e-4
            Alt_m = cached.Alt_m;
            loaded_cache = true;
            disp('      -> Modelo digital de elevación cargado desde caché local (SRTM_Elevation_Cache.mat).');
        end
    end
    
    if ~loaded_cache
        disp('      -> Consultando cotas SRTM 30m vía API...');
        chunk = 80;
        for b = 2:chunk:N
            fin = min(b + chunk - 1, N);
            loc_str = strjoin(arrayfun(@(idx) sprintf('%f,%f', lat(idx), lon(idx)), b:fin, 'UniformOutput', false), '|');
            exito = false;
            for retry = 1:3
                try
                    res = webread(sprintf('https://api.opentopodata.org/v1/srtm30m?locations=%s', loc_str), weboptions('Timeout', 15));
                    if isfield(res, 'results')
                        Alt_m(b:fin) = arrayfun(@(x) x.elevation, res.results);
                        exito = true;
                        break;
                    end
                catch
                    pause(1.2);
                end
            end
            if ~exito, Alt_m(b:fin) = City.Alt; end
            pause(0.5);
        end
        save(cache_file, 'lat', 'lon', 'Alt_m');
        disp('      -> Elevaciones topográficas almacenadas en caché local.');
    end
    
    % Proyección planar métrica respecto al centroide de estudio
    R_earth = 6371000;
    X_m = deg2rad(lon - City.Lon) * R_earth * cosd(City.Lat);
    Y_m = deg2rad(lat - City.Lat) * R_earth;
    
    % Clasificación morfológica de clutter según densidad de intersecciones
    Clutter = strings(N, 1);
    for i = 1:N
        neighbors = sum(sqrt((X_m - X_m(i)).^2 + (Y_m - Y_m(i)).^2) < 300);
        if neighbors > 35
            Clutter(i) = "Dense Urban";
        elseif neighbors > 12
            Clutter(i) = "Residential";
        else
            Clutter(i) = "Park/Periphery";
        end
    end
    Clutter(1) = "Campus / Mixed Urban";
    
    T = table(c1, c2, Alt_m, lat, lon, X_m, Y_m, Clutter, ...
        'VariableNames', {'Street_1', 'Street_2', 'Altitude_m', 'Lat', 'Lon', 'X_m', 'Y_m', 'Clutter'});
end

%% ========================================================================
%% MODELO RF ITU-R 3D (ATENUACIÓN, CLUTTER Y DIFRACCIÓN TOPOGRÁFICA)
%% ========================================================================
function [BinM_3D, Pts_3D, RSSI_Matrix] = Precompute_RF_ITU(T, HW)
    N = height(T);
    BinM_3D = false(N, N);
    RSSI_Matrix = zeros(N, N) - 150;
    Pts_3D = [T.X_m, T.Y_m, T.Altitude_m];
    
    L0 = 20 * log10(HW.Freq) - 27.55; 
    for gw = 1:N
        d_m = sqrt((T.X_m - T.X_m(gw)).^2 + (T.Y_m - T.Y_m(gw)).^2 + (T.Altitude_m - T.Altitude_m(gw)).^2);
        d_m(d_m < 1) = 1;
        
        n_path = 3.2 * ones(N, 1);
        L_clut = zeros(N, 1);
        idx_den = T.Clutter == "Dense Urban"; L_clut(idx_den) = 18; n_path(idx_den) = 3.8; 
        idx_prk = T.Clutter == "Park/Periphery"; L_clut(idx_prk) = 12; n_path(idx_prk) = 3.5; 
        
        Alt_GW_Real = T.Altitude_m(gw) + HW.Height;
        diff_alt = Alt_GW_Real - T.Altitude_m;
        L_topo = zeros(N, 1);
        v_idx = diff_alt > 15; L_topo(v_idx) = min(15 * log10(diff_alt(v_idx)), 35); 
        c_idx = diff_alt < -15; L_topo(c_idx) = min(10 * log10(abs(diff_alt(c_idx))), 35); 
        
        rssi = (HW.Ptx + HW.Gain) - L0 - 10 .* n_path .* log10(d_m) - L_clut - HW.PenetrationLoss - L_topo;
        RSSI_Matrix(:, gw) = rssi;
        BinM_3D(:, gw) = (rssi >= HW.Sens);
        
        if mod(gw, 500) == 0, fprintf('      -> Enlaces calculados: %d / %d\n', gw, N); end
    end
end

%% ========================================================================
%% ALGORITMOS OPTIMIZADORES (PUCESA ANCLADO INVARIABLEMENTE)
%% ========================================================================
function [sol, log_str] = Run_Greedy_Anchor(BinM_3D, target, anchor_idx)
    [N, C] = size(BinM_3D);
    sol = false(1, C);
    sol(anchor_idx) = true;
    cov = BinM_3D(:, anchor_idx);
    
    log_str = sprintf(">> GREEDY SCP CON GATEWAY ANCLA (PUCESA [%d])\n", anchor_idx);
    iter = 1;
    while (sum(cov)/N) < target
        b_g = 0; b_n = -1;
        cands = find(~sol);
        for i = cands
            g = sum(BinM_3D(:, i) & ~cov);
            if g > b_g, b_g = g; b_n = i; end
        end
        if b_n > 0 && b_g > 0
            sol(b_n) = true;
            cov = cov | BinM_3D(:, b_n);
            log_str = log_str + sprintf("Paso %d: Gateway [%d] asignado. Ganancia: +%d nodos. Cob: %.2f%%\n", ...
                                        iter, b_n, b_g, (sum(cov)/N)*100);
            iter = iter + 1;
        else
            break;
        end
    end
    log_str = log_str + sprintf(">> FIN GREEDY. Total GWs: %d\n", sum(sol));
end

%% ========================================================================
%% ALGORITMO K-MEDOIDS 3D NATIVO (PAM PURO - INDEPENDIENTE DE TOOLBOXES)
%% ========================================================================
function [sol, log_str] = Run_KMedoids_Anchor(Pts_3D, BinM_3D, target, anchor_idx)
    [N, C] = size(BinM_3D);
    sol = false(1, C);
    max_k = 30;
    log_str = sprintf(">> SPATIAL K-MEDOIDS 3D NATIVO (PUCESA ANCLADO [%d])\n", anchor_idx);
    
    % Precomputar matriz de distancias euclidianas 3D solo entre candidatos
    % Evita dependencias de Statistics Toolbox y acelera convergencia PAM
    D_euc = sqrt( (Pts_3D(:,1) - Pts_3D(:,1)').^2 + ...
                  (Pts_3D(:,2) - Pts_3D(:,2)').^2 + ...
                  (Pts_3D(:,3) - Pts_3D(:,3)').^2 );
    
    for k = 1:2:max_k
        if k == 1
            idx_m = anchor_idx;
        else
            % Inicialización k-means++ determinística sobre el espacio 3D
            % garantizando que el nodo 1 (PUCESA) sea el centroide inicial
            k_extra = k - 1;
            c_idx = zeros(k_extra, 1);
            
            % Distancia mínima inicial a centros existentes (PUCESA)
            min_dist = D_euc(:, anchor_idx);
            
            for ki = 1:k_extra
                % Selección estocástica ponderada por distancia máxima (k-means++)
                min_dist(anchor_idx) = 0;
                if ki > 1, min_dist(c_idx(1:ki-1)) = 0; end
                
                [~, next_c] = max(min_dist);
                c_idx(ki) = next_c;
                min_dist = min(min_dist, D_euc(:, next_c));
            end
            
            medoids = unique([anchor_idx; c_idx]);
            
            % Fase de refinamiento PAM Local (máximo 5 iteraciones de intercambio)
            for iter_pam = 1:5
                % Asignación de clústeres
                [~, cluster_assign] = min(D_euc(:, medoids), [], 2);
                improved = false;
                
                for m = 2:length(medoids) % Preservar medoids(1) como anchor_idx
                    m_idx = medoids(m);
                    members = find(cluster_assign == m);
                    if isempty(members), continue; end
                    
                    % Buscar el miembro del clúster con la mínima distancia interna
                    sub_dists = sum(D_euc(members, members), 2);
                    [~, best_local] = min(sub_dists);
                    new_m = members(best_local);
                    
                    if new_m ~= m_idx && new_m ~= anchor_idx
                        medoids(m) = new_m;
                        improved = true;
                    end
                end
                if ~improved, break; end
            end
            idx_m = medoids;
        end
        
        % Evaluación de la cobertura física conjunta con la matriz binaria RF
        cov_real = sum(sum(BinM_3D(:, idx_m), 2) > 0) / N;
        log_str = log_str + sprintf("Iter K=%d: Cobertura física calculada: %.2f%%\n", length(idx_m), cov_real * 100);
        
        if cov_real >= target
            sol(idx_m) = true;
            log_str = log_str + sprintf(">> FIN K-MEDOIDS. Objetivo alcanzado con %d Gateways.\n", sum(sol));
            break;
        end
    end
    if sum(sol) == 0, sol(idx_m) = true; end
end

function [sol, log_str] = Run_GA_Anchor(BinM_3D, target, use_memetic, algo_name, anchor_idx)
    [N, C] = size(BinM_3D);
    p_size = 24; 
    gen = 30;
    
    Pop = rand(p_size, C) < (8/C);
    Pop(:, anchor_idx) = true;
    [Pop(1,:), ~] = Run_Greedy_Anchor(BinM_3D, target, anchor_idx);
    
    log_str = sprintf(">> %s INICIADO (Pop: %d, Gen: %d, Ancla: PUCESA)\n", upper(algo_name), p_size, gen);
    
    for g = 1:gen
        Fit = zeros(p_size, 1);
        max_cov = 0; min_gw = C;
        
        for i = 1:p_size
            mapa = sum(BinM_3D(:, find(Pop(i,:))), 2);
            c_tot = sum(mapa >= 1) / N;
            c_k2  = sum(mapa >= 2) / N;
            gw_cnt = sum(Pop(i,:));
            
            if c_tot > max_cov, max_cov = c_tot; min_gw = gw_cnt; end
            
            % Función de aptitud multiobjetivo
            Fit(i) = (c_tot * 10000) + (c_k2 * 1000) - (gw_cnt * 50);
            if c_tot < target
                Fit(i) = Fit(i) - 50000;
            end
        end
        
        if mod(g, 5) == 0 || g == 1
            log_str = log_str + sprintf("Gen %d: Cobertura: %.2f%% | GWs: %d\n", g, max_cov*100, min_gw);
        end
        
        [~, b] = max(Fit);
        Best = Pop(b,:);
        NewPop = Pop;
        
        for i = 2:2:p_size
            p1 = Pop(randi(p_size),:);
            p2 = Pop(randi(p_size),:);
            mask = rand(1, C) > 0.5;
            c1 = p1; c1(mask) = p2(mask);
            
            if rand < 0.8
                if use_memetic
                    c1 = Smart_Repair_Anchor(c1, BinM_3D, target, anchor_idx);
                else
                    mut = randi(C);
                    if mut ~= anchor_idx, c1(mut) = ~c1(mut); end
                end
            end
            c1(anchor_idx) = true; 
            NewPop(i,:) = c1;
        end
        Pop = NewPop;
        Pop(1,:) = Best;
        Pop(:, anchor_idx) = true;
    end
    sol = Pop(1,:);
    log_str = log_str + sprintf(">> FIN %s. Solución óptima: %d Gateways.\n", upper(algo_name), sum(sol));
end

function ind = Smart_Repair_Anchor(ind, BinM_3D, target, anchor_idx)
    N = size(BinM_3D, 1);
    max_iter = 10; iter = 0;
    ind(anchor_idx) = true;
    
    while iter < max_iter
        iter = iter + 1;
        idx = find(ind);
        mapa = sum(BinM_3D(:, idx), 2);
        
        if (sum(mapa >= 1) / N) >= target
            removable_idx = idx(idx ~= anchor_idx);
            if ~isempty(removable_idx)
                unq = (mapa == 1);
                sc = sum(BinM_3D(:, removable_idx) & unq, 1);
                [val, w] = min(sc);
                if val < 5
                    ind(removable_idx(w)) = false;
                    continue;
                end
            end
            break;
        else
            unc = (mapa == 0);
            cands = find(~ind);
            if isempty(cands), break; end
            gains = sum(BinM_3D(unc, cands), 1);
            [bg, best_idx] = max(gains);
            if bg > 0
                ind(cands(best_idx)) = true;
            else
                break;
            end
        end
    end
    ind(anchor_idx) = true;
end

%% ========================================================================
%% REPORTES, EXPORTACIÓN Y RENDERIZADOR 3D
%% ========================================================================
function row = Extract_KPIs(name, sol, BinM_3D, time_s)
    idx = find(sol); n_gws = length(idx); N = size(BinM_3D, 1);
    if n_gws == 0, row = {name, 0, 0, 0, 0, 0, round(time_s,2)}; return; end
    mapa = sum(BinM_3D(:, idx), 2);
    c_tot = round((sum(mapa >= 1)/N)*100, 2);
    k1 = round((sum(mapa == 1)/N)*100, 2); 
    k2 = round((sum(mapa == 2)/N)*100, 2); 
    k3 = round((sum(mapa >= 3)/N)*100, 2);
    row = {name, n_gws, c_tot, k1, k2, k3, round(time_s, 2)};
end

%% ========================================================================
%% EXPORTACIÓN DE DATASET EMPÍRICO (.CSV) PARA VALIDACIÓN DOCTORAL
%% ========================================================================
function Export_CSV_Data(algo, sol, T, RSSI, HW, folder)
    idx_gws = find(sol);
    N = height(T);
    
    Serving_GW_ID = zeros(N, 1);
    Serving_GW_Street = strings(N, 1);
    RSSI_dBm = zeros(N, 1) - 150.0;
    Link_Status = strings(N, 1);
    Link_Status(:) = "OUTAGE";
    
    if ~isempty(idx_gws)
        % Extracción del mejor servidor por enlace RF 3D
        [max_rssi, local_gw_idx] = max(RSSI(:, idx_gws), [], 2);
        
        for i = 1:N
            best_gw = idx_gws(local_gw_idx(i));
            if max_rssi(i) >= HW.Sens
                Serving_GW_ID(i) = best_gw;
                Serving_GW_Street(i) = sprintf('%s y %s', T.Street_1(best_gw), T.Street_2(best_gw));
                RSSI_dBm(i) = round(max_rssi(i), 2);
                Link_Status(i) = "CONNECTED";
            else
                Serving_GW_ID(i) = 0;
                Serving_GW_Street(i) = "N/A (Sin Cobertura)";
                RSSI_dBm(i) = round(max_rssi(i), 2);
                Link_Status(i) = "OUTAGE";
            end
        end
    end
    
    % Construcción de la tabla académica formal
    Empirical_Validation_Table = table(...
        (1:N)', ...
        T.Street_1, ...
        T.Street_2, ...
        T.Lat, ...
        T.Lon, ...
        round(T.Altitude_m, 1), ...
        T.Clutter, ...
        Serving_GW_ID, ...
        Serving_GW_Street, ...
        RSSI_dBm, ...
        Link_Status, ...
        'VariableNames', { ...
            'Node_ID', ...
            'Primary_Street', ...
            'Intersecting_Street', ...
            'Latitude', ...
            'Longitude', ...
            'Elevation_MSNM', ...
            'Clutter_Profile', ...
            'Serving_GW_ID', ...
            'Serving_GW_Streets', ...
            'RSSI_Predicted_dBm', ...
            'Coverage_Status' ...
        });
        
    csv_filename = fullfile(folder, sprintf('Empirical_Validation_%s.csv', strrep(algo, ' ', '_')));
    writetable(Empirical_Validation_Table, csv_filename);
    fprintf('    -> Dataset empírico guardado: %s\n', csv_filename);
end

function Generate_Academic_Report(City, HW, T_Cov, Area, Res, Sols, Names, T, RSSI, Logs, folder)
    file = fullfile(folder, 'Academic_Deployment_Report.html'); fid = fopen(file, 'w', 'n', 'UTF-8');
    fprintf(fid, '<!DOCTYPE html><html><head><meta charset="UTF-8"><style>body{font-family:Arial, sans-serif;margin:40px;color:#333;} table{border-collapse:collapse;width:100%%;margin-bottom:30px;} th,td{border:1px solid #ccc;padding:8px;text-align:center;} th{background-color:#003366;color:white;} .box{background-color:#f0f4f8;padding:15px;border-left:5px solid #003366;margin-bottom:20px;} .log{background-color:#1e1e1e;color:#00ff00;padding:10px;font-family:monospace;font-size:12px;white-space:pre-wrap;}</style></head><body>\n');
    fprintf(fid, '<h1>LoRaWAN Network Deployment Report: PUCESA Empirical Validation</h1>\n');
    fprintf(fid, '<div class="box"><p><strong>Área Analizada:</strong> %s (%.2f km²)</p><p><strong>Target:</strong> %.1f%%</p><p><strong>Gateway Ancla:</strong> Gateway2PUCESA (-1.27458, -78.63920, 2855 msnm)</p></div>\n', City.Name, Area, T_Cov*100);
    
    fprintf(fid, '<h2>1. Resumen de Desempeño y K-Coverage</h2>\n');
    fprintf(fid, '<table><tr><th>Algoritmo</th><th>Gateways</th><th>Cobertura</th><th>K=1</th><th>K=2</th><th>K&ge;3</th><th>Tiempo CPU</th></tr>\n');
    for i = 1:height(Res)
        fprintf(fid, '<tr><td><strong>%s</strong></td><td>%d</td><td>%.2f%%</td><td>%.2f%%</td><td><strong>%.2f%%</strong></td><td>%.2f%%</td><td>%.2fs</td></tr>\n', ...
            Res.Algorithm(i), Res.Gateways(i), Res.Coverage_Pct(i), Res.Cov_1GW(i), Res.Cov_2GW(i), Res.Cov_3PlusGW(i), Res.Time_s(i)); 
    end
    fprintf(fid, '</table>\n');
    
    fprintf(fid, '<h2>2. Logs de Ejecución</h2>\n');
    for k = 1:4, fprintf(fid, '<h3>%s</h3>\n<div class="log">%s</div>\n', Names(k), Logs(k)); end
    fprintf(fid, '</body></html>\n'); fclose(fid);
end

%% ========================================================================
%% RENDERIZADOR 3D INTERACTIVO ROBUSTO (CORRECCIÓN DE DATATIPROWS)
%% ========================================================================
function Render_Interactive_3D(T, sol, RSSI_Matrix, BinM_3D, HW, city, algo, pos, folder, anchor_idx)
    idx = find(sol);
    if isempty(idx), return; end
    N = height(T);
    
    Best_R = zeros(N, 1) - 150.0;
    Srv_ID = zeros(N, 1);
    Srv_St = strings(N, 1);
    Srv_St(:) = "Ninguno";

    [max_r, max_i] = max(RSSI_Matrix(:, idx), [], 2);
    for i = 1:N
        Best_R(i) = max_r(i);
        target_gw = idx(max_i(i));
        Srv_ID(i) = target_gw;
        Srv_St(i) = sprintf('GW-%d (%s y %s)', target_gw, T.Street_1(target_gw), T.Street_2(target_gw));
    end
    
    alive = Best_R >= HW.Sens;
    dead  = Best_R < HW.Sens;

    % Métricas de salud de red (K-Coverage)
    k_map = sum(BinM_3D(:, idx), 2);
    cov_pct = (sum(k_map >= 1) / N) * 100;
    k2_plus_pct = (sum(k_map >= 2) / N) * 100;
    n_gws = length(idx);

    f3d = figure('Name', sprintf('[%s] 3D Twin - %s', algo, city), 'Position', pos, 'Color', 'w');
    a3d = axes(f3d);
    hold(a3d, 'on'); grid(a3d, 'on');

    % Textos para DataTips de Intersecciones (Vectores Columna String)
    s_inter = T.Street_1 + " & " + T.Street_2;
    s_coords = string(round(T.Lat, 5)) + ", " + string(round(T.Lon, 5));
    s_elev = string(round(T.Altitude_m, 1)) + " msnm";
    s_rssi = string(round(Best_R, 1)) + " dBm";
    
    s_gw_info = strings(N, 1);
    for i = 1:N
        if alive(i)
            s_gw_info(i) = Srv_St(i);
        else
            s_gw_info(i) = "Sin Cobertura (Outage)";
        end
    end

    % 1. Capa Outage (Gris)
    if any(dead)
        s_d = scatter3(a3d, T.X_m(dead), T.Y_m(dead), T.Altitude_m(dead), ...
                       12, [0.75 0.75 0.75], 'filled', 'MarkerFaceAlpha', 0.45);
        s_d.DataTipTemplate.DataTipRows = [ ...
            dataTipTextRow('Intersección:', cellstr(s_inter(dead))); ...
            dataTipTextRow('Coordenadas:',  cellstr(s_coords(dead))); ...
            dataTipTextRow('Elevación:',    cellstr(s_elev(dead))); ...
            dataTipTextRow('Estado:',       repmat({'OUTAGE'}, sum(dead), 1)); ...
            dataTipTextRow('RSSI Máximo:',  cellstr(s_rssi(dead))) ];
    end

    % 2. Capa Conectados (Coloreados por RSSI)
    if any(alive)
        s_a = scatter3(a3d, T.X_m(alive), T.Y_m(alive), T.Altitude_m(alive), ...
                       26, Best_R(alive), 'filled', 'MarkerFaceAlpha', 0.9);
        s_a.DataTipTemplate.DataTipRows = [ ...
            dataTipTextRow('Intersección:',     cellstr(s_inter(alive))); ...
            dataTipTextRow('Coordenadas:',      cellstr(s_coords(alive))); ...
            dataTipTextRow('Elevación:',        cellstr(s_elev(alive))); ...
            dataTipTextRow('Gateway Servidor:', cellstr(s_gw_info(alive))); ...
            dataTipTextRow('Potencia RSSI:',    cellstr(s_rssi(alive))) ];
    end

    % 3. Gateways Complementarios
    other_gw = idx(idx ~= anchor_idx);
    if ~isempty(other_gw)
        sgw_other = scatter3(a3d, T.X_m(other_gw), T.Y_m(other_gw), T.Altitude_m(other_gw) + HW.Height, ...
                             280, 'w', '^', 'filled', 'MarkerEdgeColor', 'k', 'LineWidth', 1.8);
        
        gw_labels  = "GW-" + string(other_gw);
        gw_streets = T.Street_1(other_gw) + " y " + T.Street_2(other_gw);
        gw_coords  = string(round(T.Lat(other_gw), 5)) + ", " + string(round(T.Lon(other_gw), 5));
        gw_alt     = string(round(T.Altitude_m(other_gw) + HW.Height, 1)) + " msnm";
        
        sgw_other.DataTipTemplate.DataTipRows = [ ...
            dataTipTextRow('Gateway:',          cellstr(gw_labels)); ...
            dataTipTextRow('Ubicación Calles:', cellstr(gw_streets)); ...
            dataTipTextRow('Coordenadas:',      cellstr(gw_coords)); ...
            dataTipTextRow('Altura Radiante:',  cellstr(gw_alt)) ];
    end

    % 4. Gateway Ancla PUCESA (Punto Único)
    sgw_anchor = scatter3(a3d, T.X_m(anchor_idx), T.Y_m(anchor_idx), T.Altitude_m(anchor_idx) + HW.Height, ...
                          500, [1 0.84 0], 'p', 'filled', 'MarkerEdgeColor', [0.8 0 0], 'LineWidth', 2.2);
    
    pucesa_street = cellstr(sprintf('%s y %s', T.Street_1(anchor_idx), T.Street_2(anchor_idx)));
    pucesa_coords = cellstr(sprintf('%.5f, %.5f', T.Lat(anchor_idx), T.Lon(anchor_idx)));
    pucesa_alt    = cellstr(sprintf('%.1f msnm', T.Altitude_m(anchor_idx) + HW.Height));
    
    sgw_anchor.DataTipTemplate.DataTipRows = [ ...
        dataTipTextRow('Gateway Ancla:',    {'Gateway2PUCESA (TTN)'}); ...
        dataTipTextRow('Ubicación:',        pucesa_street); ...
        dataTipTextRow('Coordenadas:',      pucesa_coords); ...
        dataTipTextRow('Altura Radiante:',  pucesa_alt) ];

    text(a3d, T.X_m(anchor_idx), T.Y_m(anchor_idx), T.Altitude_m(anchor_idx) + HW.Height + 25, ...
         '  PUCESA (GW-1)', 'FontSize', 9, 'FontWeight', 'bold', 'Color', [0.7 0 0]);

    % Parámetros visuales y proyecciones
    daspect(a3d, [1 1 0.1]); 
    colormap(a3d, 'jet');
    clim(a3d, [HW.Sens, -70]);
    view(a3d, -35, 45);
    title(sprintf('%s (Ubicación Georreferenciada)', algo), 'FontSize', 11, 'FontWeight', 'bold');

    xlabel(a3d, 'X Proyectado (Metros)');
    ylabel(a3d, 'Y Proyectado (Metros)');
    zlabel(a3d, 'Altitud (MSNM)');

    cb = colorbar(a3d);
    ylabel(cb, 'Potencia de Recepción RSSI (dBm)');

    infoStr = sprintf(['Gateways: %d (PUCESA fijo)\n', ...
                       'Cobertura Total: %.1f%%\n', ...
                       'Redundancia K\\ge2: %.1f%%\n', ...
                       'Sensibilidad: %d dBm (SF%d)'], ...
                       n_gws, cov_pct, k2_plus_pct, HW.Sens, HW.SF);
                   
    annotation(f3d, 'textbox', [0.15, 0.74, 0.36, 0.16], ...
        'String', infoStr, 'FontSize', 9, 'FontWeight', 'bold', ...
        'BackgroundColor', 'w', 'EdgeColor', 'k', 'FitBoxToText', 'on', 'Margin', 6);

    drawnow;
    name_cln = strrep(strrep(strrep(algo, ' ', '_'), '(', ''), ')', '');
    exportgraphics(f3d, fullfile(folder, sprintf('3D_Map_%s.png', name_cln)), 'Resolution', 600);
    savefig(f3d, fullfile(folder, sprintf('Native_Fig_%s.fig', name_cln)));
end