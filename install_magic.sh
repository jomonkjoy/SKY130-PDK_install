#!/usr/bin/env bash
# =============================================================================
# install_magic.sh
# Installs the latest Magic VLSI Layout Tool from source
# Repository: https://github.com/RTimothyEdwards/magic
# =============================================================================

set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }

# ── Configuration (override via environment variables) ────────────────────────
REPO_URL="${MAGIC_REPO_URL:-https://github.com/RTimothyEdwards/magic.git}"
BRANCH="${MAGIC_BRANCH:-master}"
BUILD_DIR="${MAGIC_BUILD_DIR:-/tmp/magic-build}"
INSTALL_PREFIX="${MAGIC_PREFIX:-/usr/local}"
JOBS="${MAGIC_JOBS:-$(nproc 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo 4)}"

# ── OS detection ──────────────────────────────────────────────────────────────
detect_os() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_FAMILY="${ID_LIKE:-$OS_ID}"
    elif [[ "$(uname)" == "Darwin" ]]; then
        OS_ID="macos"
        OS_FAMILY="macos"
    else
        OS_ID="unknown"
        OS_FAMILY="unknown"
    fi
}

# ── Dependency installation ───────────────────────────────────────────────────
install_deps_debian() {
    info "Installing dependencies via apt-get..."
    sudo apt-get update -qq
    sudo apt-get install -y \
        git build-essential \
        tcl-dev tk-dev \
        libx11-dev libxext-dev libxt-dev \
        libcairo2-dev \
        libncurses-dev \
        m4 csh
    success "Dependencies installed."
}

install_deps_fedora() {
    info "Installing dependencies via dnf..."
    sudo dnf install -y \
        git gcc make \
        tcl-devel tk-devel \
        libX11-devel libXext-devel libXt-devel \
        cairo-devel \
        ncurses-devel \
        m4 tcsh
    success "Dependencies installed."
}

install_deps_arch() {
    info "Installing dependencies via pacman..."
    sudo pacman -Sy --noconfirm \
        git base-devel \
        tcl tk \
        libx11 libxext libxt \
        cairo \
        ncurses \
        m4 tcsh
    success "Dependencies installed."
}

install_deps_macos() {
    if ! command -v brew &>/dev/null; then
        error "Homebrew is required on macOS. Install it from https://brew.sh"
    fi
    info "Installing dependencies via Homebrew..."
    brew install tcl-tk cairo
    success "Dependencies installed."
}

install_dependencies() {
    detect_os
    case "${OS_FAMILY}" in
        *debian*|*ubuntu*|debian|ubuntu)  install_deps_debian ;;
        *fedora*|*rhel*|*centos*|fedora)  install_deps_fedora ;;
        arch)                             install_deps_arch   ;;
        macos)                            install_deps_macos  ;;
        *)
            warn "Unrecognised OS '${OS_ID}'. Skipping automatic dependency install."
            warn "Please manually install: git, gcc, make, tcl-dev, tk-dev,"
            warn "  libx11-dev, libcairo-dev, ncurses-dev, m4"
            ;;
    esac
}

# ── Fetch latest source ───────────────────────────────────────────────────────
fetch_source() {
    if [[ -d "${BUILD_DIR}/.git" ]]; then
        info "Source directory already exists – pulling latest changes..."
        git -C "${BUILD_DIR}" fetch --tags
        git -C "${BUILD_DIR}" checkout "${BRANCH}"
        git -C "${BUILD_DIR}" pull --ff-only
    else
        info "Cloning Magic VLSI repository (branch: ${BRANCH})..."
        git clone --depth 1 --branch "${BRANCH}" "${REPO_URL}" "${BUILD_DIR}"
    fi

    # Report the exact version we are about to build
    local version
    version="$(cat "${BUILD_DIR}/VERSION" 2>/dev/null || \
               git -C "${BUILD_DIR}" describe --tags 2>/dev/null || echo 'unknown')"
    success "Source ready – version ${version}"
}

# ── Build & install ───────────────────────────────────────────────────────────
build_and_install() {
    info "Configuring Magic (prefix: ${INSTALL_PREFIX})..."
    cd "${BUILD_DIR}"

    ./configure \
        --prefix="${INSTALL_PREFIX}" \
        --with-tcl \
        --with-tk \
        --with-cairo \
        --enable-readline

    info "Building with ${JOBS} parallel jobs..."
    make -j"${JOBS}"

    info "Installing to ${INSTALL_PREFIX}..."
    sudo make install

    success "Magic installed successfully."
}

# ── Post-install verification ─────────────────────────────────────────────────
verify_install() {
    local magic_bin="${INSTALL_PREFIX}/bin/magic"
    if [[ -x "${magic_bin}" ]]; then
        local installed_version
        installed_version="$("${magic_bin}" --version 2>&1 | head -1 || true)"
        success "Binary found: ${magic_bin}"
        info    "Version report: ${installed_version}"
    else
        warn "Binary not found at ${magic_bin}."
        warn "Check that ${INSTALL_PREFIX}/bin is in your PATH."
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo -e "\n${BOLD}══════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}   Magic VLSI Layout Tool – Installer         ${RESET}"
    echo -e "${BOLD}══════════════════════════════════════════════${RESET}\n"

    # Ensure git is available before anything else
    command -v git &>/dev/null || error "git is required. Please install git first."

    install_dependencies
    fetch_source
    build_and_install
    verify_install

    echo
    success "All done! Run 'magic' to launch the tool."
    echo -e "  Docs: ${CYAN}http://opencircuitdesign.com/magic/${RESET}"
    echo
}

main "$@"
