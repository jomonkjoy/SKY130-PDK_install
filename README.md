# SKY130 PDK Installation Guide

Install the SkyWater SKY130 process design kit on Ubuntu 20.04 / 22.04
using `install_sky130_pdk.sh`.

---

## Before You Start

| Requirement | Detail |
|-------------|--------|
| OS | Ubuntu 20.04 or 22.04 LTS |
| Disk space | ~45 GB free |
| RAM | 4 GB minimum |
| Internet | Required — downloads several GB |
| Time | 30–90 minutes |

> **macOS / Windows:** Not supported natively. Use WSL2 on Windows or a
> Linux VM.

---

## Install

```bash
chmod +x install_sky130_pdk.sh
./install_sky130_pdk.sh
```

When it finishes, reload your shell:

```bash
source ~/.bashrc    # or: source ~/.zshrc
```

### Custom install path

By default the PDK is installed to `~/pdk/share/pdk/sky130A`.
To change this, set `PDK_ROOT` before running:

```bash
PDK_ROOT=/opt/pdk ./install_sky130_pdk.sh
```

---

## What Gets Installed

```
$PDK_ROOT/share/pdk/sky130A/
│
├── libs.tech/
│   ├── magic/       ← Magic technology files (.tech, .magicrc)
│   ├── ngspice/     ← SPICE device models  (sky130.lib.spice)
│   ├── netgen/      ← LVS setup file
│   └── klayout/     ← DRC rules
│
└── libs.ref/
    ├── sky130_fd_sc_hd/        ← High-density standard cells
    │   ├── gds/                   GDS2 layout
    │   ├── lef/                   Abstract layout (P&R)
    │   ├── lib/                   Liberty timing files
    │   ├── verilog/               Verilog models
    │   └── spice/                 SPICE netlists
    ├── sky130_fd_sc_hvl/       ← High-voltage standard cells
    ├── sky130_fd_io/           ← I/O ring cells
    └── sky130_sram_macros/     ← Pre-built OpenRAM SRAM macros
```

---

## Environment Variables

The installer writes these three variables to your `.bashrc` / `.zshrc`:

| Variable | Value | Used by |
|----------|-------|---------|
| `PDK_ROOT` | `~/pdk/share/pdk` | OpenLane, Magic, Netgen |
| `PDK` | `sky130A` | OpenLane |
| `STD_CELL_LIBRARY` | `sky130_fd_sc_hd` | Synthesis, P&R |

Verify they are set after reloading your shell:

```bash
echo $PDK_ROOT
# → /home/yourname/pdk/share/pdk

echo $PDK
# → sky130A
```

---

## What the Script Does — Step by Step

| Step | What happens |
|------|-------------|
| 1 | Checks OS, user, python3, sudo, and free disk space |
| 2 | Installs APT system packages (tcl, cairo, X11 libs, etc.) |
| 3 | Builds and installs **Magic** VLSI tool from source (needed by open_pdks) |
| 4 | Clones `google/skywater-pdk` and pulls only the required cell library submodules |
| 5 | Clones `RTimothyEdwards/open_pdks` (the PDK build system) |
| 6 | Runs `./configure` — points open_pdks at the skywater-pdk source, enables SRAM macros |
| 7 | Runs `make` — processes all GDS, SPICE, LEF, Liberty, and Verilog files (~20–60 min) |
| 8 | Runs `sudo make install` — copies the finished PDK to `$PDK_ROOT` |
| 9 | Verifies expected directories are present |
| 10 | Writes `PDK_ROOT`, `PDK`, `STD_CELL_LIBRARY` to your shell rc file |
| 11 | Offers to delete the build work directory (~10–20 GB) |

---

## Using the PDK

### Magic — open a layout

```bash
magic -T $PDK_ROOT/sky130A/libs.tech/magic/sky130A.tech
```

### ngspice — run a simulation with SKY130 models

Include this at the top of your SPICE deck:

```spice
.lib $PDK_ROOT/sky130A/libs.tech/ngspice/sky130.lib.spice tt
```

Replace `tt` with `ff` or `ss` for fast/slow corners.

### Netgen — run LVS

```bash
netgen -batch lvs \
    "layout.spice cell_name" \
    "schematic.spice cell_name" \
    $PDK_ROOT/sky130A/libs.tech/netgen/sky130A_setup.tcl \
    lvs_report.txt
```

### OpenRAM — point to the PDK

In your `sram_config.py`, the `tech_name = "sky130"` entry already
references the PDK via `OPENRAM_TECH`. No extra configuration needed
once both the PDK and OpenRAM are installed.

---

## Troubleshooting

**Build runs out of disk space mid-way**

The build requires ~45 GB. Check space and re-run — the script skips
already-completed clone steps:

```bash
df -h ~
./install_sky130_pdk.sh
```

**`magic: command not found` during configure**

Step 3 builds Magic from source. If it failed, build it manually:

```bash
cd ~/.sky130_build/magic
./configure && make -j$(nproc) && sudo make install
```

**`make timing` fails in skywater-pdk**

This step generates Liberty timing data and can fail if submodules
are incomplete. It is non-fatal — the script continues. Re-run
`make timing` manually inside `~/.sky130_build/skywater-pdk` if needed.

**`libs.ref/sky130_sram_macros` is missing**

The `--enable-sram-sky130` flag was not applied. Re-run the script —
it will skip the clone steps and re-run configure/make/install cleanly.

**Re-running the script**

Safe to re-run at any time. Already-cloned repos are pulled rather
than re-cloned, and the env block in your shell rc is replaced, not
duplicated.

---

## Uninstalling

```bash
# Remove the installed PDK
rm -rf ~/pdk/share/pdk/sky130A

# Remove the build work directory (if kept)
rm -rf ~/.sky130_build

# Remove env vars — edit ~/.bashrc or ~/.zshrc and delete the block between:
#   # >>> SKY130 PDK >>>
#   # <<< SKY130 PDK <<<
```

---

## Related Scripts

| Script | Purpose |
|--------|---------|
| `install_sky130_pdk.sh` | This script — installs the full SKY130 PDK |
| `install_openram.sh` | Installs the OpenRAM SRAM compiler |
| `my_sram_project/run.sh` | Generates a custom SRAM macro with OpenRAM |
