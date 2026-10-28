# Diccionario de archivos principales

Los nombres de columna se conservan tal como fueron exportados. RSSI se expresa en dBm y SNR en dB; porcentajes y proporciones se distinguen por el encabezado. Un campo vacío no equivale a cero.


## data/simulation/F04_intervalos95.csv

Filas de datos: 26.


`sf`, `period_seconds`, `metric`, `n`, `mean`, `sample_sd`, `ci95_half_width`, `ci95_low`, `ci95_high`, `method`.


## data/simulation/F07_resumen_K_RF_por_SF.csv

Filas de datos: 2.


`sf`, `sensitivity_dbm`, `n_nodes`, `n_gateways`, `coverage_pct`, `K0_pct`, `K1_pct`, `K2_pct`, `K_ge3_pct`, `K_ge2_pct`, `mean_K`, `denominator`.


## data/simulation/F10_resiliencia_estatica_resumen.csv

Filas de datos: 12.


`algorithm`, `threshold_dbm`, `n_nodes`, `n_gateways`, `coverage_pct`, `K0_pct`, `K1_pct`, `K2_pct`, `Kge3_pct`, `post_failure_coverage_min_pct`, `post_failure_coverage_mean_pct`, `post_failure_coverage_max_pct`, `loss_max_pp`, `loss_mean_pp`, `loss_min_pp`.


## data/simulation/F11_comparacion_modelos_carga.csv

Filas de datos: 12.


`rf_model`, `sf`, `period_s`, `n_runs`, `mean_pdr_pct`, `sample_sd_pct`, `ci95_low`, `ci95_high`, `scope`, `generated_per_run`, `mean_server_unique`.


## experiments/ns3_archive/gateways.csv

Filas de datos: 10.


`Gateway_ID`, `Latitude`, `Longitude`, `Height_m`.
