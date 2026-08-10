#!/usr/bin/env bash
set -euo pipefail

# Generate channel-rust-stable.toml from dist directory tarballs
# Auto-discovers available triples from .sha256 files
#
# Usage: generate-manifest.sh [-v VERSION] [-d DIST_DIR]
#   -v, --version     Rust version (default: 1.95.0)
#   -d, --dist-dir    Dist directory path (default: ./dist)
#   -h, --help        Show help

VERSION="1.95.0"
DIST_DIR=""
URL_BASE="https://gitcode.com/OpenHarmonyPCDeveloper/rust/releases/download/dist-1.95.0"
RUSTC_VERSION="rustc 1.95.0 (59807616e 2026-04-14) (built from a source tarball)"
CARGO_VERSION="cargo 1.95.0 (f2d3ce0bd 2026-03-21) (built from a source tarball)"
RUSTFMT_VERSION="rustfmt 1.95.0-stable (59807616e 2026-04-14)"
CLIPPY_VERSION="clippy 1.95.0-stable (59807616e 2026-04-14)"
RA_VERSION="rust-analyzer 1.95.0-stable (59807616e 2026-04-14)"

usage() {
    cat <<'USAGE'
Usage: generate-manifest.sh [-v VERSION] [-d DIST_DIR]

Options:
  -v, --version     Rust version (default: 1.95.0)
  -d, --dist-dir    Dist directory path (default: ~/work/ohos-dist-server/dist)
  -h, --help        Show this help

The script auto-discovers available target triples from .sha256 files
in the dist directory and generates a multi-arch channel-rust-stable.toml.
USAGE
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--version)  VERSION="$2"; shift 2;;
        -d|--dist-dir) DIST_DIR="$2"; shift 2;;
        -h|--help)     usage;;
        *)             echo "Unknown option: $1"; usage;;
    esac
done

: "${DIST_DIR:="./dist"}"

if [[ ! -d "${DIST_DIR}" ]]; then
    echo "ERROR: Dist directory not found: ${DIST_DIR}"
    exit 1
fi

# Discover available triples from rustc tarball sha256 files
# Pattern: rustc-<version>-<triple>.tar.gz.sha256
TRIPLES=()
for sha_file in "${DIST_DIR}/rustc-${VERSION}-"*".tar.gz.sha256"; do
    [[ -e "$sha_file" ]] || continue
    # Extract triple from filename: rustc-1.95.0-aarch64-unknown-linux-ohos.tar.gz.sha256
    basename="$(basename "$sha_file")"
    triple="${basename#rustc-${VERSION}-}"
    triple="${triple%.tar.gz.sha256}"
    TRIPLES+=("$triple")
done

if [[ ${#TRIPLES[@]} -eq 0 ]]; then
    echo "ERROR: No rustc tarballs found for version ${VERSION}"
    exit 1
fi

info() { echo "[INFO] $*"; }
info "Found ${#TRIPLES[@]} target triples: ${TRIPLES[*]}"

# Read SHA-256 hash from a .sha256 file
get_hash() {
    local pkg="$1"
    local target="$2"
    local sha_file="${DIST_DIR}/${pkg}-${VERSION}-${target}.tar.gz.sha256"
    if [[ -f "$sha_file" ]]; then
        head -1 "$sha_file"
    else
        echo ""
    fi
}

# Validate that all required component tarballs exist for a triple
validate_triple() {
    local triple="$1"
    local missing=0
    for pkg in rustc cargo rust-std rustfmt-preview clippy-preview rust-analyzer-preview; do
        local sha_file="${DIST_DIR}/${pkg}-${VERSION}-${triple}.tar.gz.sha256"
        if [[ ! -f "$sha_file" ]]; then
            info "WARNING: Missing ${pkg} for ${triple} — skipping this triple"
            missing=1
            break
        fi
    done
    return $missing
}

# Generate the manifest
DATE="$(date +%Y-%m-%d)"
OUT_FILE="${DIST_DIR}/channel-rust-stable.toml"

info "Generating manifest: ${OUT_FILE}"

{
    echo "manifest-version = \"2\""
    echo "date = \"${DATE}\""
    echo ""

    # === pkg.rust (combined meta-package) ===
    echo "[pkg.rust]"
    echo "version = \"${RUSTC_VERSION}\""
    echo ""

    VALID_TRIPLES=()
    for triple in "${TRIPLES[@]}"; do
        if validate_triple "$triple"; then
            VALID_TRIPLES+=("$triple")
        fi
    done

    for triple in "${VALID_TRIPLES[@]}"; do
        hash=$(get_hash "rust" "$triple")
        if [[ -z "$hash" ]]; then
            # rust combined package may not exist; skip
            continue
        fi
        echo "[pkg.rust.target.${triple}]"
        echo "available = true"
        echo "url = \"${URL_BASE}/rust-${VERSION}-${triple}.tar.gz\""
        echo "hash = \"${hash}\""
        echo ""
        # Components (arch-specific)
        for comp_pkg in rustc cargo rust-std rustfmt-preview clippy-preview; do
            echo "[[pkg.rust.target.${triple}.components]]"
            echo "pkg = \"${comp_pkg}\""
            echo "target = \"${triple}\""
            echo ""
        done
        # Extensions (arch-specific)
        echo "[[pkg.rust.target.${triple}.extensions]]"
        echo "pkg = \"rust-analyzer-preview\""
        echo "target = \"${triple}\""
        echo ""
        echo "[[pkg.rust.target.${triple}.extensions]]"
        echo "pkg = \"rust-src\""
        echo "target = \"*\""
        echo ""
    done

    # === pkg.rustc ===
    echo "[pkg.rustc]"
    echo "version = \"${RUSTC_VERSION}\""
    echo ""

    for triple in "${VALID_TRIPLES[@]}"; do
        hash=$(get_hash "rustc" "$triple")
        echo "[pkg.rustc.target.${triple}]"
        echo "available = true"
        echo "url = \"${URL_BASE}/rustc-${VERSION}-${triple}.tar.gz\""
        echo "hash = \"${hash}\""
        echo ""
    done

    # === pkg.cargo ===
    echo "[pkg.cargo]"
    echo "version = \"${CARGO_VERSION}\""
    echo ""

    for triple in "${VALID_TRIPLES[@]}"; do
        hash=$(get_hash "cargo" "$triple")
        echo "[pkg.cargo.target.${triple}]"
        echo "available = true"
        echo "url = \"${URL_BASE}/cargo-${VERSION}-${triple}.tar.gz\""
        echo "hash = \"${hash}\""
        echo ""
    done

    # === pkg.rust-std ===
    echo "[pkg.rust-std]"
    echo "version = \"${RUSTC_VERSION}\""
    echo ""

    for triple in "${VALID_TRIPLES[@]}"; do
        hash=$(get_hash "rust-std" "$triple")
        echo "[pkg.rust-std.target.${triple}]"
        echo "available = true"
        echo "url = \"${URL_BASE}/rust-std-${VERSION}-${triple}.tar.gz\""
        echo "hash = \"${hash}\""
        echo ""
    done

    # === pkg.rustfmt-preview ===
    echo "[pkg.rustfmt-preview]"
    echo "version = \"${RUSTFMT_VERSION}\""
    echo ""

    for triple in "${VALID_TRIPLES[@]}"; do
        hash=$(get_hash "rustfmt-preview" "$triple")
        echo "[pkg.rustfmt-preview.target.${triple}]"
        echo "available = true"
        echo "url = \"${URL_BASE}/rustfmt-preview-${VERSION}-${triple}.tar.gz\""
        echo "hash = \"${hash}\""
        echo ""
    done

    # === pkg.clippy-preview ===
    echo "[pkg.clippy-preview]"
    echo "version = \"${CLIPPY_VERSION}\""
    echo ""

    for triple in "${VALID_TRIPLES[@]}"; do
        hash=$(get_hash "clippy-preview" "$triple")
        echo "[pkg.clippy-preview.target.${triple}]"
        echo "available = true"
        echo "url = \"${URL_BASE}/clippy-preview-${VERSION}-${triple}.tar.gz\""
        echo "hash = \"${hash}\""
        echo ""
    done

    # === pkg.rust-analyzer-preview ===
    echo "[pkg.rust-analyzer-preview]"
    echo "version = \"${RA_VERSION}\""
    echo ""

    for triple in "${VALID_TRIPLES[@]}"; do
        hash=$(get_hash "rust-analyzer-preview" "$triple")
        echo "[pkg.rust-analyzer-preview.target.${triple}]"
        echo "available = true"
        echo "url = \"${URL_BASE}/rust-analyzer-preview-${VERSION}-${triple}.tar.gz\""
        echo "hash = \"${hash}\""
        echo ""
    done

    # === pkg.rust-src (platform-independent, uses first triple's tarball) ===
    echo "[pkg.rust-src]"
    echo "version = \"${RUSTC_VERSION}\""
    echo ""

    if [[ ${#VALID_TRIPLES[@]} -gt 0 ]]; then
        first_triple="${VALID_TRIPLES[0]}"
        hash=$(get_hash "rust-src" "$first_triple")
        echo "[pkg.rust-src.target.\"*\"]"
        echo "available = true"
        echo "url = \"${URL_BASE}/rust-src-${VERSION}-${first_triple}.tar.gz\""
        echo "hash = \"${hash}\""
        echo ""
    fi

    # === renames ===
    echo "[renames]"
    echo "rustfmt = { to = \"rustfmt-preview\" }"
    echo "clippy = { to = \"clippy-preview\" }"
    echo "rust-analyzer = { to = \"rust-analyzer-preview\" }"
    echo ""

    # === profiles ===
    echo "[profiles]"
    echo "minimal = [\"rustc\", \"cargo\", \"rust-std\"]"
    echo "default = [\"rustc\", \"cargo\", \"rust-std\", \"rustfmt-preview\", \"clippy-preview\"]"
    echo "complete = [\"rustc\", \"cargo\", \"rust-std\", \"rustfmt-preview\", \"clippy-preview\", \"rust-analyzer-preview\", \"rust-src\"]"
} > "${OUT_FILE}"

# Generate SHA-256 for the manifest itself
manifest_hash=$(sha256sum "${OUT_FILE}" | awk '{print $1}')
echo "${manifest_hash}" > "${OUT_FILE}.sha256"

info "Manifest written: ${OUT_FILE}"
info "Manifest SHA-256: ${manifest_hash}"
info "Contains ${#VALID_TRIPLES[@]} valid target triples"

# Show summary
echo ""
echo "=== Manifest Summary ==="
echo "Triples: ${VALID_TRIPLES[*]}"
echo "Packages: rust, rustc, cargo, rust-std, rustfmt-preview, clippy-preview, rust-analyzer-preview, rust-src"
echo "Profiles: minimal, default, complete"
