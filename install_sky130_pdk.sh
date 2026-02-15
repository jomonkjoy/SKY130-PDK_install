#!/usr/bin/env bash
# =============================================================================
#  install_sky130_pdk.sh
#  Installs the SkyWater SKY130 PDK via open_pdks on Ubuntu 20.04 / 22.04
#
#  What this script does:
#    1. Installs system dependencies (Magic, Netgen, Python3, etc.)
#    2. Clones the google/skywater-pdk foundry source
#    3. Clones RTimothyEdwards/open_pdks (the PDK builder)
#    4. Builds and installs sky130A into $PDK_ROOT/sky130A
#    5. Writes PDK_ROOT to your shell rc file
#
#  Usage:
#    chmod +x install_sky130_pdk.sh
#    ./install_sky130_pdk.sh
#
#  Default install location: $HOME/pdk
#  Override:  PDK_ROOT=/your/path ./install_sky130_pdk.sh
#
#  Disk space required: ~30–45 GB
#  Time:                30–90 minutes (depends on internet speed)
# =============================================================================

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
PDK_ROOT="${PDK_ROOT:-$HOME/pdk}"
WORK_DIR="$HOME/.sky130_build"        # Temporary build area
LOG_FILE="$HOME/sky130_pdk_install.log"

# open_pdks install prefix — PDK lands at $PREFIX/share/pdk/sky130A
PREFIX="$PDK_ROOT"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${GREEN}[✔]${NC} $*" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*" | tee -a "$LOG_FILE"; }
error()   { echo -e "${RED}[✘] ERROR:${NC} $*" | tee -a "$LOG_FILE"; exit 1; }
section() { echo -e "\n${BOLD}${CYAN}── $* ──${NC}" | tee -a "$LOG_FILE"; }

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║   SkyWater SKY130 PDK Installer             ║"
echo "  ║   via open_pdks  |  Ubuntu 20.04 / 22.04    ║"
echo "  ╚══════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${BOLD}PDK install path :${NC} $PDK_ROOT/share/pdk/sky130A"
echo -e "  ${BOLD}Build work dir   :${NC} $WORK_DIR"
echo -e "  ${BOLD}Log file         :${NC} $LOG_FILE"
echo -e "  ${YELLOW}Estimated time   : 30–90 min  |  ~30–45 GB disk${NC}"
echo ""

echo "SKY130 PDK Install — $(date)" > "$LOG_FILE"
echo "PDK_ROOT=$PDK_ROOT" >> "$LOG_FILE"

# ── 1. Preflight ──────────────────────────────────────────────────────────────
section "Preflight checks"

[[ "$(uname -s)" == "Linux" ]] || error "Linux (Ubuntu 20.04/22.04) required."
[[ "$EUID" -ne 0 ]]            || error "Do not run as root. Use a normal user with sudo."
command -v python3 &>/dev/null  || error "python3 not found. Install it first."
sudo -v 2>/dev/null             || error "sudo access required."

# Disk space check — require at least 45 GB free
AVAIL_KB=$(df -k "$HOME" | awk 'NR==2 {print $4}')
REQUIRED_KB=$((45 * 1024 * 1024))
if (( AVAIL_KB < REQUIRED_KB )); then
    warn "Less than 45 GB free in $HOME ($(( AVAIL_KB / 1024 / 1024 )) GB available)."
    warn "The build may fail. Free up space or set PDK_ROOT to a larger disk."
fi

# git large-file buffer — prevents clone failures on slow connections
git config --global http.postBuffer    2147483648 2>/dev/null || true
git config --global http.maxRequestBuffer 2147483648 2>/dev/null || true
git config --global http.version       HTTP/1.1   2>/dev/null || true

log "Preflight OK"

# ── 2. System packages ────────────────────────────────────────────────────────
section "Installing system packages"

sudo apt-get update -qq 2>&1 | tee -a "$LOG_FILE"

sudo apt-get install -y \
    git \
    python3 python3-pip \
    build-essential \
    m4 tcsh csh \
    tcl-dev tk-dev \
    libcairo2-dev \
    libx11-dev \
    libxaw7-dev \
    libreadline-dev \
    ncurses-dev \
    libglu1-mesa-dev \
    freeglut3-dev \
    wget curl unzip \
    2>&1 | tee -a "$LOG_FILE" \
    || error "APT install failed — see $LOG_FILE"

log "System packages installed."

# ── 3. Install Magic (required by open_pdks) ──────────────────────────────────
section "Installing Magic VLSI layout tool"

if command -v magic &>/dev/null; then
    log "Magic already installed: $(magic --version 2>&1 | head -1 || echo 'found')"
else
    log "Cloning and building Magic from source..."
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"

    if [[ -d magic/.git ]]; then
        warn "Magic repo already cloned — pulling latest."
        git -C magic pull 2>&1 | tee -a "$LOG_FILE"
    else
        git clone https://github.com/RTimothyEdwards/magic.git \
            2>&1 | tee -a "$LOG_FILE" \
            || error "Failed to clone Magic repo."
    fi

    cd magic
    ./configure 2>&1 | tee -a "$LOG_FILE" \
        || error "Magic ./configure failed."
    make -j"$(nproc)" 2>&1 | tee -a "$LOG_FILE" \
        || error "Magic make failed."
    sudo make install 2>&1 | tee -a "$LOG_FILE" \
        || error "Magic make install failed."

    log "Magic installed: $(magic --version 2>&1 | head -1 || echo 'OK')"
fi

# ── 4. Clone google/skywater-pdk ──────────────────────────────────────────────
section "Cloning google/skywater-pdk foundry source"
# NOTE: This is the raw foundry data (~10–15 GB with submodules).
# We only pull the standard-cell libraries needed for most designs.

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

if [[ -d skywater-pdk/.git ]]; then
    warn "skywater-pdk already cloned — skipping re-clone."
else
    log "Cloning skywater-pdk (shallow) ..."
    git clone https://github.com/google/skywater-pdk.git \
        2>&1 | tee -a "$LOG_FILE" \
        || error "Failed to clone skywater-pdk."
fi

cd skywater-pdk

# Pull the submodules we actually need
# sky130_fd_sc_hd  — high-density standard cells (required for most flows)
# sky130_fd_sc_hvl — high-voltage standard cells
# sky130_fd_io     — I/O cells
log "Initialising required submodules (this downloads several GB)..."
for lib in \
    libraries/sky130_fd_sc_hd/latest \
    libraries/sky130_fd_sc_hvl/latest \
    libraries/sky130_fd_io/latest \
    libraries/sky130_fd_pr/latest
do
    log "  → $lib"
    git submodule update --init "$lib" \
        2>&1 | tee -a "$LOG_FILE" \
        || warn "Submodule $lib failed — continuing."
done

log "Generating timing data (make timing) ..."
make timing 2>&1 | tee -a "$LOG_FILE" \
    || warn "'make timing' reported errors — may be safe to continue."

log "skywater-pdk source ready."

# ── 5. Clone open_pdks ────────────────────────────────────────────────────────
section "Cloning open_pdks (PDK builder)"

cd "$WORK_DIR"

if [[ -d open_pdks/.git ]]; then
    warn "open_pdks already cloned — pulling latest."
    git -C open_pdks pull 2>&1 | tee -a "$LOG_FILE"
else
    log "Cloning open_pdks..."
    git clone https://github.com/RTimothyEdwards/open_pdks.git \
        2>&1 | tee -a "$LOG_FILE" \
        || error "Failed to clone open_pdks."
fi

log "open_pdks source ready."

# ── 6. Configure open_pdks ────────────────────────────────────────────────────
section "Configuring open_pdks for SKY130"

cd "$WORK_DIR/open_pdks"

# --enable-sky130-pdk          : build the SKY130 PDK
# --enable-sky130-pdk=PATH     : use our already-cloned skywater-pdk source
# --prefix=PATH                : install to $PREFIX/share/pdk/
# --enable-sram-sky130         : include pre-compiled OpenRAM SRAM macros
# --disable-gf180mcu-pdk       : skip the GlobalFoundries PDK
#
# open_pdks will automatically pull any remaining sources it needs.

log "Running ./configure ..."
./configure \
    --enable-sky130-pdk="$WORK_DIR/skywater-pdk/libraries" \
    --prefix="$PREFIX" \
    --enable-sram-sky130 \
    --disable-gf180mcu-pdk \
    2>&1 | tee -a "$LOG_FILE" \
    || error "./configure failed — see $LOG_FILE"

log "Configuration complete."

# ── 7. Build PDK ──────────────────────────────────────────────────────────────
section "Building PDK (make) — this takes the longest"
# Processes all foundry GDS, SPICE, LEF, Liberty, and Verilog files.
# Expected time: 20–60 minutes depending on CPU and internet speed.

log "Running make (grab a coffee) ..."
make -j"$(nproc)" 2>&1 | tee -a "$LOG_FILE" \
    || error "make failed — see $LOG_FILE"

log "Build complete."

# ── 8. Install PDK ────────────────────────────────────────────────────────────
section "Installing PDK (sudo make install)"

sudo make install 2>&1 | tee -a "$LOG_FILE" \
    || error "make install failed — see $LOG_FILE"

SKY130A_PATH="$PREFIX/share/pdk/sky130A"
log "PDK installed to: $SKY130A_PATH"

# ── 9. Verify install ─────────────────────────────────────────────────────────
section "Verifying installation"

FAIL=0
for expected_dir in \
    "$SKY130A_PATH/libs.tech/magic" \
    "$SKY130A_PATH/libs.tech/ngspice" \
    "$SKY130A_PATH/libs.tech/netgen" \
    "$SKY130A_PATH/libs.ref/sky130_fd_sc_hd" \
    "$SKY130A_PATH/libs.ref/sky130_fd_io"
do
    if [[ -d "$expected_dir" ]]; then
        log "  ✔  $(basename "$expected_dir")"
    else
        warn "  ✘  Missing: $expected_dir"
        FAIL=1
    fi
done

# Check SRAM macros
if [[ -d "$SKY130A_PATH/libs.ref/sky130_sram_macros" ]]; then
    log "  ✔  sky130_sram_macros (OpenRAM pre-built macros)"
else
    warn "  ✘  sky130_sram_macros not found (--enable-sram-sky130 may have been skipped)"
fi

if [[ $FAIL -eq 1 ]]; then
    warn "Some expected directories are missing. Check $LOG_FILE for build errors."
fi

# ── 10. Set environment variables ────────────────────────────────────────────
section "Setting environment variables"

if [[ -f "$HOME/.zshrc" ]]; then
    SHELL_RC="$HOME/.zshrc"
else
    SHELL_RC="$HOME/.bashrc"
fi

MARKER="# >>> SKY130 PDK >>>"
END_MARKER="# <<< SKY130 PDK <<<"

# Remove stale block on re-runs
if grep -q "$MARKER" "$SHELL_RC" 2>/dev/null; then
    warn "Updating existing SKY130 PDK block in $SHELL_RC"
    sed -i "/$MARKER/,/$END_MARKER/d" "$SHELL_RC"
fi

cat >> "$SHELL_RC" <<EOF

$MARKER
export PDK_ROOT="$PREFIX/share/pdk"
export PDK="sky130A"
export STD_CELL_LIBRARY="sky130_fd_sc_hd"
$END_MARKER
EOF

# Export for current session
export PDK_ROOT="$PREFIX/share/pdk"
export PDK="sky130A"
export STD_CELL_LIBRARY="sky130_fd_sc_hd"

log "Env vars written to $SHELL_RC"

# ── 11. Optional cleanup ─────────────────────────────────────────────────────
section "Optional: Clean up build area"
echo ""
echo -e "  The build directory at ${CYAN}$WORK_DIR${NC} is no longer needed."
echo -e "  It contains the raw source checkouts (~10–20 GB)."
echo ""
read -rp "  Delete build directory now? [y/N] " CLEAN_UP
if [[ "${CLEAN_UP,,}" == "y" ]]; then
    rm -rf "$WORK_DIR"
    log "Build directory removed."
else
    warn "Build directory kept at $WORK_DIR"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}  ╔══════════════════════════════════════════════╗"
echo    "  ║   SKY130 PDK installation complete!        ║"
echo -e "  ╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}PDK location:${NC}"
echo -e "  ${CYAN}  $SKY130A_PATH${NC}"
echo ""
echo -e "  ${BOLD}Key subdirectories:${NC}"
echo    "    libs.tech/magic/    — Magic technology files"
echo    "    libs.tech/ngspice/  — SPICE device models"
echo    "    libs.tech/netgen/   — LVS setup"
echo    "    libs.ref/sky130_fd_sc_hd/  — Standard cells (GDS, LEF, LIB, Verilog)"
echo    "    libs.ref/sky130_sram_macros/ — Pre-built OpenRAM SRAM macros"
echo ""
echo -e "  ${YELLOW}Reload your shell to activate env variables:${NC}"
echo -e "  ${CYAN}    source $SHELL_RC${NC}"
echo ""
echo -e "  ${BOLD}Log file:${NC} $LOG_FILE"
echo ""
