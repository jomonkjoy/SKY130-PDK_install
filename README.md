# SKY130 PDK — Installation & Usage Guide

The SkyWater SKY130 is an open-source 130 nm process design kit (PDK)
maintained by Google and SkyWater Technology. It provides everything needed
to design, verify, and simulate analog and digital circuits targeting the
SKY130 process node.

---

## Requirements

| | |
|--|--|
| **OS** | Ubuntu 20.04 or 22.04 LTS |
| **Disk space** | ~45 GB free |
| **RAM** | 4 GB minimum |
| **Internet** | Required — downloads several GB |
| **Time** | 30–90 minutes |

---

## Install

```bash
chmod +x install_sky130_pdk.sh
./install_sky130_pdk.sh
```

Reload your shell when it finishes:

```bash
source ~/.bashrc    # or: source ~/.zshrc
```

**Custom install path** — default is `~/pdk`. Override with:

```bash
PDK_ROOT=/opt/pdk ./install_sky130_pdk.sh
```

---

## What Gets Installed

```
$PDK_ROOT/share/pdk/sky130A/
│
├── libs.tech/                  ← Tool configuration files
│   ├── magic/                     Magic layout tool (.tech, .magicrc)
│   ├── ngspice/                   SPICE device models
│   ├── netgen/                    LVS setup
│   └── klayout/                   DRC rules
│
└── libs.ref/                   ← Cell libraries
    ├── sky130_fd_sc_hd/           High-density standard cells
    │   ├── gds/                   Layout (GDS2)
    │   ├── lef/                   Abstract layout for P&R
    │   ├── lib/                   Liberty timing files
    │   ├── verilog/               Verilog simulation models
    │   └── spice/                 SPICE netlists
    ├── sky130_fd_sc_hvl/          High-voltage standard cells
    ├── sky130_fd_io/              I/O ring cells
    └── sky130_sram_macros/        Pre-compiled SRAM macros
```

---

## Environment Variables

The installer writes these to your `.bashrc` / `.zshrc` automatically:

```bash
export PDK_ROOT="~/pdk/share/pdk"
export PDK="sky130A"
export STD_CELL_LIBRARY="sky130_fd_sc_hd"
```

Verify after reloading your shell:

```bash
echo $PDK_ROOT    # → /home/you/pdk/share/pdk
echo $PDK         # → sky130A
```

---

## Using the PDK

### Magic — open a layout

```bash
magic -T $PDK_ROOT/sky130A/libs.tech/magic/sky130A.tech
```

### ngspice — SPICE simulation

Include this at the top of your SPICE deck:

```spice
.lib $PDK_ROOT/sky130A/libs.tech/ngspice/sky130.lib.spice tt
```

Replace `tt` with `ff` (fast) or `ss` (slow) for other process corners.

### Netgen — LVS check

```bash
netgen -batch lvs \
    "layout.spice cell_name" \
    "schematic.spice cell_name" \
    $PDK_ROOT/sky130A/libs.tech/netgen/sky130A_setup.tcl \
    lvs_report.txt
```

### KLayout — view GDS / run DRC

```bash
klayout -e layout.gds \
    -r $PDK_ROOT/sky130A/libs.tech/klayout/sky130A.drc
```

---

## PVT Corners

| Corner | Process | Voltage | Temp |
|--------|---------|---------|------|
| `tt`   | Typical | 1.8 V   | 25°C |
| `ff`   | Fast    | 1.95 V  | −40°C |
| `ss`   | Slow    | 1.6 V   | 85°C |
| `sf`   | Slow N / Fast P | 1.8 V | 25°C |
| `fs`   | Fast N / Slow P | 1.8 V | 25°C |

Reference the corner in your SPICE deck using the `.lib` directive:

```spice
.lib $PDK_ROOT/sky130A/libs.tech/ngspice/sky130.lib.spice ff
```

---

## Troubleshooting

**Not enough disk space mid-build**
```bash
df -h ~
# Free space, then re-run — already-cloned repos are skipped
./install_sky130_pdk.sh
```

**`magic: command not found` during configure**

Step 3 builds Magic from source. If it failed, build it manually:
```bash
cd ~/.sky130_build/magic
./configure && make -j$(nproc) && sudo make install
```

**`sky130_sram_macros` is missing**

The `--enable-sram-sky130` configure flag was not applied. Re-run the
script — it skips clone steps and re-runs configure/make/install only.

**Re-running the script**

Safe at any time. Repos are pulled (not re-cloned), and the env block
in your shell rc is replaced, not duplicated.

---

## Uninstalling

```bash
# Remove the installed PDK
rm -rf ~/pdk/share/pdk/sky130A

# Remove the build work directory (if you chose to keep it)
rm -rf ~/.sky130_build

# Remove env vars — open ~/.bashrc or ~/.zshrc and delete the lines between:
# >>> SKY130 PDK >>>
# <<< SKY130 PDK <<<
```
