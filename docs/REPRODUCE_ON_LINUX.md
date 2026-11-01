# Reproduce the archived experiment on Linux

This is a preparation recipe for a fresh installation, followed by the archived replay workflow. The fresh-install recipe was not executed as part of the manuscript preparation. Recalculation of all 128 saved run summaries did pass; see the article's verification report.

## 1. Prepare the recorded software revisions

The recorded platform used Ubuntu/WSL2, g++ 13.3.0 and Python 3.12.3. Keep a record of your actual compiler, CMake, Python and operating system versions; different builds need their own binary identity.

Typical Ubuntu build prerequisites are:

```sh
sudo apt update
sudo apt install g++ python3 cmake ninja-build git pkg-config ccache
git clone https://gitlab.com/nsnam/ns-3-dev.git ns-3
git -C ns-3 checkout f576896f5c2387874f49be221c13ae371e4f8f86
git clone https://github.com/signetlabdei/lorawan.git ns-3/contrib/lorawan
git -C ns-3/contrib/lorawan checkout 67bcaefdeb45d367010e09a80083b9a0527f766b
```

Consult the upstream ns-3 installation guide if optional dependencies differ on your platform. Do not replace the pinned revisions with the latest releases and still describe the result as historical reproduction.

## 2. Configure the build

From the simulator directory:

```sh
./ns3 configure --enable-tests
```

The companion root is the folder containing `scripts/` and `experiments/`. From that root, inspect the environment and one replay plan:

```sh
python3 scripts/verify_linux_environment.py --ns3-root /absolute/path/to/ns-3
python3 scripts/replay_ns3.py --ns3-root /absolute/path/to/ns-3 --run-index 0
```

The plan resolves the correct frozen matrix by SHA-256 and retains all options from the selected run manifest. The program is C++, not C. The replay launcher copies the exact source into `scratch/validacion_lorawan_v02.cc` only when it will not overwrite a different source.

## 3. Execute an explicitly selected run

```sh
python3 scripts/replay_ns3.py --ns3-root /absolute/path/to/ns-3 --run-index 0 --execute
```

The launcher builds `validacion_lorawan_v02` and starts the resulting binary. If a build profile names it differently, pass `--binary /absolute/path/to/the/binary`. A new `outputs/run_000` folder is used. An existing output folder is preserved instead of being overwritten.

Run indices 0--127 refer to sorted accepted manifests and are not identical to the simulation's internal Run identifier. Inspect each plan before scheduling a full campaign. Rebuilt binaries are recorded with a new SHA-256; bit identity across compiler builds is not assumed.

## 4. Inspect and compare

For the provided archived evidence:

```sh
python3 scripts/verify_release.py
```

This command recalculates run metrics, verifies supplied artifact hashes, and checks node aggregates and Student-t intervals without rerunning ns-3. A check against aggregate records is not a new complete event-level audit. Detailed packet/event archives are separate artifacts identified in the provenance inventory; only twelve event CSVs were retained historically.

For newly generated output, preserve its configuration, source/input/binary identities and raw records before comparing counts. Do not copy its results over the archived observations. RF reconstruction agreement is a numerical-transfer check and is not field validation.
