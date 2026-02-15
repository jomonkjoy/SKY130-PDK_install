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

# ── Install GCC-12 and fix missing libstdc++ / linux-libc-dev (Debian/Ubuntu) ─
install_gcc12_and_fixes() {
    detect_os
    case "${OS_FAMILY}" in
        *debian*|*ubuntu*|debian|ubuntu)
            info "Installing gcc-12 and fix packages (libstdc++, linux-libc-dev)..."
            sudo apt-get install -y \
                gcc-12 \
                g++-12 \
                libstdc++-12-dev \
                linux-libc-dev
            success "gcc-12 and fix packages installed."
            ;;
        *)
            warn "gcc-12 fix step is only applicable on Debian/Ubuntu. Skipping."
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

# ── Patch txInput.c: replace obsolete termio with POSIX termios ──────────────
patch_txinput() {
    local txinput="${BUILD_DIR}/textio/txInput.c"

    if [[ ! -f "${txinput}" ]]; then
        warn "txInput.c not found at ${txinput}. Skipping patch."
        return
    fi

    # Only patch if not already patched
    if grep -q "termios.h" "${txinput}"; then
        info "txInput.c already patched. Skipping."
        return
    fi

    info "Patching txInput.c: replacing obsolete termio with POSIX termios..."

    # Add missing headers at the very top of the file
    sed -i '1s/^/#include <termios.h>\n#include <sys\/ioctl.h>\n/' "${txinput}"

    # Replace old struct termio with struct termios (various forms)
    sed -i 's/struct termio \*/struct termios */g' "${txinput}"
    sed -i 's/struct termio$/struct termios/g'     "${txinput}"
    sed -i 's/struct termio /struct termios /g'    "${txinput}"

    # Replace obsolete SVR4 ioctl constants with POSIX equivalents
    sed -i 's/TCGETA/TCGETS/g'   "${txinput}"
    sed -i 's/TCSETAF/TCSETSF/g' "${txinput}"

    success "txInput.c patched successfully."
}

# ── Build & install ───────────────────────────────────────────────────────────
build_and_install() {
    info "Cleaning any previous build artifacts..."
    cd "${BUILD_DIR}"
    make clean 2>/dev/null || true

    info "Configuring Magic (prefix: ${INSTALL_PREFIX}, compiler: gcc-12)..."
    ./configure \
        CC=gcc-12 \
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

    install_dependencies        # base deps (tcl, tk, cairo, etc.)
    install_gcc12_and_fixes     # gcc-12, g++-12, libstdc++-12-dev, linux-libc-dev
    fetch_source                # clone or update the Magic repo
    patch_txinput               # fix obsolete termio → termios in txInput.c
    build_and_install           # clean → configure → make → install
    verify_install              # confirm binary exists and report version

    echo
    success "All done! Run 'magic' to launch the tool."
    echo -e "  Docs: ${CYAN}http://opencircuitdesign.com/magic/${RESET}"
    echo
}

main "$@"
