#!/usr/bin/env bash
set -euo pipefail

# Build OHOS Distribution Tarballs
# Splits the community pre-compiled Rust toolchain into rust-installer v3 format
# component tarballs, signs all ELF binaries, and generates SHA-256 hashes.
#
# Usage: build-ohos-dist.sh [OPTIONS]
#   -v, --version       Rust version (default: 1.95.0)
#   -t, --target        Target triple (default: aarch64-unknown-linux-ohos)
#   -T, --toolchain-dir Path to pre-compiled toolchain (default: ~/usr/rust-<version>-<target>)
#   -d, --dist-dir      Output directory for tarballs (default: ./dist)
#   -s, --sign-tool     Path to binary-sign-tool (default: binary-sign-tool)
#   -h, --help          Show this help message

VERSION="1.95.0"
TARGET="aarch64-unknown-linux-ohos"
TOOLCHAIN_DIR=""
DIST_DIR=""
SIGN_TOOL="binary-sign-tool"

usage() {
    cat <<'USAGE'
Usage: build-ohos-dist.sh [OPTIONS]

Options:
  -v, --version       Rust version (default: 1.95.0)
  -t, --target        Target triple (default: aarch64-unknown-linux-ohos)
  -T, --toolchain-dir Path to pre-compiled toolchain (default: ~/usr/rust-<version>-<target>)
  -d, --dist-dir      Output directory for tarballs (default: ./dist)
  -s, --sign-tool     Path to binary-sign-tool (default: binary-sign-tool)
  -h, --help          Show this help message

Example:
  build-ohos-dist.sh -v 1.95.0 -t aarch64-unknown-linux-ohos
  build-ohos-dist.sh -v 1.96.0 -t x86_64-unknown-linux-ohos -T /path/to/toolchain
USAGE
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--version)       VERSION="$2"; shift 2;;
        -t|--target)        TARGET="$2"; shift 2;;
        -T|--toolchain-dir) TOOLCHAIN_DIR="$2"; shift 2;;
        -d|--dist-dir)      DIST_DIR="$2"; shift 2;;
        -s|--sign-tool)     SIGN_TOOL="$2"; shift 2;;
        -h|--help)          usage;;
        *)                  echo "Unknown option: $1"; usage;;
    esac
done

# Derive defaults from version/target if not explicitly set
: "${TOOLCHAIN_DIR:="$HOME/usr/rust-${VERSION}-${TARGET}"}"
: "${DIST_DIR:="./dist"}"

# Validate toolchain directory exists
if [[ ! -d "${TOOLCHAIN_DIR}" ]]; then
    echo "ERROR: Toolchain directory not found: ${TOOLCHAIN_DIR}"
    echo "  Expected pre-compiled Rust ${VERSION} for ${TARGET}"
    exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }

mkdir -p "${DIST_DIR}"

# Sign a single ELF binary
sign_elf() {
    local f="$1"
    if file "$f" | grep -q "ELF"; then
        "${SIGN_TOOL}" sign -selfSign 1 -signAlg SHA256withECDSA \
            -inFile "$f" -outFile "${f}.signed" 2>&1 | grep -v "^$" || true
        if [[ -f "${f}.signed" ]]; then
            mv "${f}.signed" "$f"
            chmod +x "$f"
        fi
    fi
}

# Create a rust-installer v3 format component package
# Instead of glob patterns in file lists (which don't work with [[ -e ]]),
# we use a function-based approach: copy files by directory/pattern expansion,
# then generate manifest.in from what's actually present.
# Args: component_name, setup_function_name
create_component_pkg() {
    local comp_name="$1"
    local setup_fn="$2"
    local pkg_name="${comp_name}-${VERSION}-${TARGET}"

    info "Creating package: ${pkg_name}"

    local tmp_dir=$(mktemp -d)
    local pkg_dir="${tmp_dir}/${pkg_name}"

    mkdir -p "${pkg_dir}/${comp_name}"

    # Create rust-installer-version file
    echo "3" > "${pkg_dir}/rust-installer-version"

    # Create components file
    echo "${comp_name}" > "${pkg_dir}/components"

    # Call the setup function to copy and sign files
    "${setup_fn}" "${pkg_dir}/${comp_name}"

    # Create manifest.in from actual files (rust-installer format: "file:path" per line)
    cd "${pkg_dir}/${comp_name}"
    find . -type f ! -name "manifest.in" | sed 's|^\./||' | while read f; do
        echo "file:${f}"
    done > "manifest.in"
    cd - >/dev/null

    info "Manifest for ${comp_name}: $(wc -l < "${pkg_dir}/${comp_name}/manifest.in") entries"

    # Create tarball
    info "Packaging ${pkg_name}.tar.gz"
    cd "${tmp_dir}"
    tar -czf "${DIST_DIR}/${pkg_name}.tar.gz" "${pkg_name}"
    cd - >/dev/null

    # Compute SHA-256
    local hash=$(sha256sum "${DIST_DIR}/${pkg_name}.tar.gz" | awk '{print $1}')
    echo "${hash}" > "${DIST_DIR}/${pkg_name}.tar.gz.sha256"
    info "SHA-256: ${hash}"

    rm -rf "${tmp_dir}"
    echo "${hash}"
}

# === Component setup functions ===

# rustc: compiler binary + driver libs + debugger scripts
setup_rustc() {
    local dst="$1"
    # Binaries
    for f in bin/rustc bin/rustdoc; do
        mkdir -p "${dst}/$(dirname $f)"
        cp -a "${TOOLCHAIN_DIR}/$f" "${dst}/$f"
        sign_elf "${dst}/$f"
    done
    # rust-objcopy
    mkdir -p "${dst}/lib/rustlib/${TARGET}/bin"
    cp -a "${TOOLCHAIN_DIR}/lib/rustlib/${TARGET}/bin/rust-objcopy" "${dst}/lib/rustlib/${TARGET}/bin/rust-objcopy"
    sign_elf "${dst}/lib/rustlib/${TARGET}/bin/rust-objcopy"
    # rustc driver .so files (critical for rustc, rustfmt, clippy)
    for so in librustc_driver librustc_macros librustc_index_macros librustc_type_ir_macros; do
        local pattern="${TOOLCHAIN_DIR}/lib/${so}-*.so"
        for candidate in ${pattern}; do
            [[ -e "$candidate" ]] && {
                local rel="${candidate#${TOOLCHAIN_DIR}/}"
                mkdir -p "${dst}/$(dirname $rel)"
                cp -a "$candidate" "${dst}/$rel"
                sign_elf "${dst}/$rel"
            }
        done
    done
    # Debugger scripts
    for f in lib/rustlib/etc/gdb_load_rust_pretty_printers.py \
             lib/rustlib/etc/gdb_lookup.py \
             lib/rustlib/etc/gdb_providers.py \
             lib/rustlib/etc/lldb_commands \
             lib/rustlib/etc/lldb_lookup.py; do
        mkdir -p "${dst}/$(dirname $f)"
        cp -a "${TOOLCHAIN_DIR}/$f" "${dst}/$f"
    done
}

# cargo: package manager + proc-macro libs + SSL
setup_cargo() {
    local dst="$1"
    mkdir -p "${dst}/bin"
    cp -a "${TOOLCHAIN_DIR}/bin/cargo" "${dst}/bin/cargo"
    sign_elf "${dst}/bin/cargo"
    # Proc-macro .so files (cargo needs these for build scripts)
    for so in libserde_derive libthiserror_impl libderive_setters libderive_where \
              libdisplaydoc libproc_macro_hack libref_cast_impl libschemars_derive \
              libtracing_attributes libdarling_macro libyoke_derive libzerofrom_derive \
              libzerovec_derive libunic_langid_macros_impl; do
        local pattern="${TOOLCHAIN_DIR}/lib/${so}-*.so"
        for candidate in ${pattern}; do
            [[ -e "$candidate" ]] && {
                local rel="${candidate#${TOOLCHAIN_DIR}/}"
                mkdir -p "${dst}/$(dirname $rel)"
                cp -a "$candidate" "${dst}/$rel"
                sign_elf "${dst}/$rel"
            }
        done
    done
    # SSL libraries
    mkdir -p "${dst}/lib"
    cp -a "${TOOLCHAIN_DIR}/lib/libssl.so" "${dst}/lib/libssl.so"
    cp -a "${TOOLCHAIN_DIR}/lib/libcrypto.so" "${dst}/lib/libcrypto.so"
    # man pages and shell completions
    mkdir -p "${dst}/share/man/man1"
    for f in "${TOOLCHAIN_DIR}/share/man/man1/cargo"*.1; do
        [[ -e "$f" ]] && cp -a "$f" "${dst}/share/man/man1/"
    done
    mkdir -p "${dst}/share/zsh/site-functions"
    [[ -e "${TOOLCHAIN_DIR}/share/zsh/site-functions/_cargo" ]] && \
        cp -a "${TOOLCHAIN_DIR}/share/zsh/site-functions/_cargo" "${dst}/share/zsh/site-functions/_cargo"
    # Cargo docs
    mkdir -p "${dst}/share/doc/cargo"
    for f in "${TOOLCHAIN_DIR}/share/doc/cargo/"*; do
        [[ -e "$f" ]] && cp -a "$f" "${dst}/share/doc/cargo/"
    done
}

# rust-std: standard library (rlib + rmeta + so)
setup_rust_std() {
    local dst="$1"
    mkdir -p "${dst}/lib/rustlib/${TARGET}/lib"
    # Copy entire std lib directory (rlib, rmeta, so)
    cp -a "${TOOLCHAIN_DIR}/lib/rustlib/${TARGET}/lib/"* "${dst}/lib/rustlib/${TARGET}/lib/"
    # Sign ELF .so files in rust-std
    find "${dst}" -type f -name "*.so" | while read f; do sign_elf "$f"; done
}

# rustfmt: formatter
setup_rustfmt() {
    local dst="$1"
    mkdir -p "${dst}/bin"
    cp -a "${TOOLCHAIN_DIR}/bin/rustfmt" "${dst}/bin/rustfmt"
    sign_elf "${dst}/bin/rustfmt"
    cp -a "${TOOLCHAIN_DIR}/bin/cargo-fmt" "${dst}/bin/cargo-fmt"
    sign_elf "${dst}/bin/cargo-fmt"
}

# clippy: linter
setup_clippy() {
    local dst="$1"
    mkdir -p "${dst}/bin"
    cp -a "${TOOLCHAIN_DIR}/bin/clippy-driver" "${dst}/bin/clippy-driver"
    sign_elf "${dst}/bin/clippy-driver"
    cp -a "${TOOLCHAIN_DIR}/bin/cargo-clippy" "${dst}/bin/cargo-clippy"
    sign_elf "${dst}/bin/cargo-clippy"
}

# rust-analyzer: language server
setup_rust_analyzer() {
    local dst="$1"
    mkdir -p "${dst}/bin"
    cp -a "${TOOLCHAIN_DIR}/bin/rust-analyzer" "${dst}/bin/rust-analyzer"
    sign_elf "${dst}/bin/rust-analyzer"
}

# rust-src: source code (platform-independent, no signing needed)
setup_rust_src() {
    local dst="$1"
    # Copy entire src directory
    mkdir -p "${dst}/lib/rustlib/src/rust/library"
    for item in "${TOOLCHAIN_DIR}/lib/rustlib/src/rust/library/"*; do
        [[ -e "$item" ]] && cp -a "$item" "${dst}/lib/rustlib/src/rust/library/"
    done
    # Cargo lock/toml at library root
    for f in lib/rustlib/src/rust/library/Cargo.lock lib/rustlib/src/rust/library/Cargo.toml; do
        [[ -e "${TOOLCHAIN_DIR}/$f" ]] && {
            mkdir -p "${dst}/$(dirname $f)"
            cp -a "${TOOLCHAIN_DIR}/$f" "${dst}/$f"
        }
    done
}

# === Build each component ===
info "Building component packages..."

RUSTC_HASH=$(create_component_pkg "rustc" "setup_rustc")
CARGO_HASH=$(create_component_pkg "cargo" "setup_cargo")
RUSTSTD_HASH=$(create_component_pkg "rust-std" "setup_rust_std")
RUSTFMT_HASH=$(create_component_pkg "rustfmt-preview" "setup_rustfmt")
CLIPPY_HASH=$(create_component_pkg "clippy-preview" "setup_clippy")
RUSTANALYZER_HASH=$(create_component_pkg "rust-analyzer-preview" "setup_rust_analyzer")
RUSTSRC_HASH=$(create_component_pkg "rust-src" "setup_rust_src")

# === Build combined rust package ===
info "Creating combined rust package..."

RUST_PKG_NAME="rust-${VERSION}-${TARGET}"
RUST_TMP=$(mktemp -d)
RUST_PKG_DIR="${RUST_TMP}/${RUST_PKG_NAME}"

mkdir -p "${RUST_PKG_DIR}"

echo "3" > "${RUST_PKG_DIR}/rust-installer-version"
cat > "${RUST_PKG_DIR}/components" << 'EOF'
rustc
cargo
rust-std
rustfmt-preview
clippy-preview
EOF

# Copy and sign files for each component using the same setup functions
for comp_setup in "rustc:setup_rustc" "cargo:setup_cargo" "rust-std:setup_rust_std" "rustfmt-preview:setup_rustfmt" "clippy-preview:setup_clippy"; do
    comp="${comp_setup%%:*}"
    fn="${comp_setup##*:}"
    mkdir -p "${RUST_PKG_DIR}/${comp}"
    "${fn}" "${RUST_PKG_DIR}/${comp}"
done

# Create manifest.in for each component
for comp in rustc cargo rust-std rustfmt-preview clippy-preview; do
    cd "${RUST_PKG_DIR}/${comp}"
    find . -type f ! -name "manifest.in" | sed 's|^\./||' | while read f; do
        echo "file:${f}"
    done > "manifest.in"
    info "Combined ${comp} manifest: $(wc -l < "${RUST_PKG_DIR}/${comp}/manifest.in") entries"
    cd - >/dev/null
done

# Package and hash
info "Packaging ${RUST_PKG_NAME}.tar.gz"
cd "${RUST_TMP}"
tar -czf "${DIST_DIR}/${RUST_PKG_NAME}.tar.gz" "${RUST_PKG_NAME}"
cd - >/dev/null

RUST_HASH=$(sha256sum "${DIST_DIR}/${RUST_PKG_NAME}.tar.gz" | awk '{print $1}')
echo "${RUST_HASH}" > "${DIST_DIR}/${RUST_PKG_NAME}.tar.gz.sha256"
info "Combined rust SHA-256: ${RUST_HASH}"

rm -rf "${RUST_TMP}"

# === Output hashes for manifest generation ===
info "Hash summary for manifest generation:"
echo ""
echo "RUST_HASH=${RUST_HASH}"
echo "RUSTC_HASH=${RUSTC_HASH}"
echo "CARGO_HASH=${CARGO_HASH}"
echo "RUSTSTD_HASH=${RUSTSTD_HASH}"
echo "RUSTFMT_HASH=${RUSTFMT_HASH}"
echo "CLIPPY_HASH=${CLIPPY_HASH}"
echo "RUSTANALYZER_HASH=${RUSTANALYZER_HASH}"
echo "RUSTSRC_HASH=${RUSTSRC_HASH}"
echo ""
info "Tarballs created in ${DIST_DIR}/"
ls "${DIST_DIR}/"
