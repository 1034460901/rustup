#!/data/service/hnp/bin/bash
set -euo pipefail

# OHOS Rust Toolchain Setup Script
# Links a pre-compiled OHOS Rust toolchain into rustup's management
#
# Usage:
#   ohos-toolchain-setup [VERSION]              # Auto-detect from ~/usr/rust-VERSION-TRIPLE/
#   ohos-toolchain-setup --local PATH [VERSION] # Use existing local toolchain
#   ohos-toolchain-setup --source URL [VERSION] # Download from URL
#   ohos-toolchain-setup --uninstall [VERSION]  # Remove linked toolchain

RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
TRIPLE="aarch64-unknown-linux-ohos"
SIGN_TOOL="/data/service/hnp/bin/binary-sign-tool"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [VERSION]

Sets up a pre-compiled OHOS Rust toolchain under rustup management.

Arguments:
  VERSION         Rust version number (default: 1.95.0)

Options:
  --local PATH    Use existing local toolchain directory
  --source URL    Download URL for toolchain tarball
  --uninstall     Remove the linked toolchain
  --help          Show this help

Examples:
  $(basename "$0")                              # Auto-detect v1.95.0
  $(basename "$0") 1.89.0                       # Use v1.89.0
  $(basename "$0") --local ~/my-rust 1.95.0     # Use custom path
  $(basename "$0") --uninstall 1.95.0           # Remove toolchain

Environment:
  RUSTUP_HOME     rustup data directory (default: ~/.rustup)
  CARGO_HOME      cargo data directory (default: ~/.cargo)
  RUST_MIN_STACK  Must be set to 8388608 (8MB) for musl compatibility

EOF
}

ACTION="install"
LOCAL_PATH=""
SOURCE_URL=""
VERSION="1.95.0"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --local)   LOCAL_PATH="$2"; shift 2 ;;
        --source)  SOURCE_URL="$2"; shift 2 ;;
        --uninstall) ACTION="uninstall"; shift ;;
        --help)    usage; exit 0 ;;
        -*)        error "Unknown option: $1" ;;
        *)         VERSION="$1"; shift ;;
    esac
done

TOOLCHAIN_NAME="ohos-${VERSION}"

# Check rustup is available
if ! command -v rustup &>/dev/null; then
    error "rustup not found in PATH. Install rustup-ohos first."
fi

sign_binary() {
    local file="$1"
    if [[ -x "$SIGN_TOOL" ]]; then
        info "Signing binary: $file"
        "$SIGN_TOOL" sign -selfSign 1 -signAlg SHA256withECDSA \
            -inFile "$file" -outFile "${file}.signed" 2>&1 | grep -v "^$" || true
        if [[ -f "${file}.signed" ]]; then
            mv "${file}.signed" "$file"
            chmod +x "$file"
        fi
    else
        warn "binary-sign-tool not found at $SIGN_TOOL"
        warn "Binary must be signed manually before execution on HarmonyOS"
    fi
}

if [[ "$ACTION" == "uninstall" ]]; then
    info "Removing toolchain: ${TOOLCHAIN_NAME}"
    rustup toolchain uninstall "${TOOLCHAIN_NAME}" || warn "Toolchain not found or already removed"
    info "Uninstall complete"
    exit 0
fi

TOOLCHAIN_DIR="${RUSTUP_HOME}/toolchains/${TOOLCHAIN_NAME}"

# If toolchain dir already exists and is linked, skip setup
if rustup toolchain list | grep -q "${TOOLCHAIN_NAME}"; then
    info "Toolchain ${TOOLCHAIN_NAME} already registered with rustup"
    rustup show
    exit 0
fi

info "Setting up toolchain: ${TOOLCHAIN_NAME}"

if [[ -n "$LOCAL_PATH" ]]; then
    if [[ ! -d "$LOCAL_PATH" ]]; then
        error "Local path does not exist: ${LOCAL_PATH}"
    fi
    info "Using local toolchain: ${LOCAL_PATH}"
    # For local toolchains, use rustup toolchain link directly (symlink, not copy)
    # This avoids symlink loops caused by cp -a on directories with internal symlinks
    rustup toolchain link "${TOOLCHAIN_NAME}" "${LOCAL_PATH}"
    info "Linked toolchain to rustup via symlink"

elif [[ -n "$SOURCE_URL" ]]; then
    info "Downloading from: ${SOURCE_URL}"
    TMP=$(mktemp -d)
    curl -sSL "${SOURCE_URL}" -o "${TMP}/toolchain.tar.xz"
    info "Extracting..."
    tar -xJf "${TMP}/toolchain.tar.xz" -C "${TMP}"
    EXTRACTED=$(find "${TMP}" -maxdepth 1 -type d ! -path "${TMP}" | head -1)
    [[ -z "$EXTRACTED" ]] && EXTRACTED="${TMP}"
    LOCAL_PATH="${EXTRACTED}"

else
    # Auto-detect standard location
    STANDARD="$HOME/usr/rust-${VERSION}-${TRIPLE}"
    if [[ -d "$STANDARD" ]]; then
        info "Found local toolchain at: ${STANDARD}"
        # Use rustup toolchain link directly (symlink, not copy)
        rustup toolchain link "${TOOLCHAIN_NAME}" "${STANDARD}"
        info "Linked toolchain to rustup via symlink"
    else
        error "No toolchain source found. Use --local PATH, --source URL, or place at: ${STANDARD}"
    fi
fi

# For --local and --source modes, linking was already done above for --local
# For --source mode, still need to copy and then link
if [[ -n "$SOURCE_URL" ]]; then
    TOOLCHAIN_DIR="${RUSTUP_HOME}/toolchains/${TOOLCHAIN_NAME}"
    mkdir -p "${TOOLCHAIN_DIR}"
    cp -a "${LOCAL_PATH}/." "${TOOLCHAIN_DIR}/"

    # Sign all binaries in the toolchain that need signing
    info "Verifying/signing toolchain binaries..."
    for bin in "${TOOLCHAIN_DIR}/bin/"*; do
        if file "$bin" | grep -q "ELF"; then
            sign_binary "$bin"
            chmod +x "$bin"
        fi
    done

    # Link downloaded toolchain
    rustup toolchain link "${TOOLCHAIN_NAME}" "${TOOLCHAIN_DIR}"
fi

# Set as default
info "Setting ${TOOLCHAIN_NAME} as default toolchain..."
rustup default "${TOOLCHAIN_NAME}"

# Verify
info "Verification:"
echo ""
rustup show
echo ""
rustc --version
cargo --version

echo ""
info "Setup complete! Toolchain ${TOOLCHAIN_NAME} is active."
echo ""
warn "Important: Add these lines to your ~/.zshrc:"
echo "  export RUST_MIN_STACK=8388608    # 8MB stack for musl compatibility"
echo "  export PATH=\"\$HOME/.cargo/bin:\$PATH\""
