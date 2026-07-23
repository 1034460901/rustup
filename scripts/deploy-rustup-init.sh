#!/data/service/hnp/bin/bash
set -euo pipefail

# Phase 7: Deploy rustup-init for curl | sh installation on OHOS
# Signs the rustup-init binary, places it in the dist server tree,
# generates release-stable.toml, and deploys the patched rustup-init.sh.
#
# Usage: deploy-rustup-init.sh [OPTIONS]
#   -v, --version       Rustup version (default: 1.30.0)
#   -t, --target        Target triple (default: aarch64-unknown-linux-ohos)
#   -d, --dist-dir      Dist directory (default: ~/work/ohos-dist-server/dist)
#   -r, --rustup-dir    Rustup source dir (default: ~/work/rustup-ohos)
#   -s, --sign-tool     Path to binary-sign-tool (default: /data/service/hnp/bin/binary-sign-tool)
#   -u, --update-root   RUSTUP_UPDATE_ROOT URL (default: http://127.0.0.1:8080/rustup)
#   -h, --help          Show help

RUSTUP_VERSION="1.30.0"
TARGET="aarch64-unknown-linux-ohos"
DIST_DIR="/storage/Users/currentUser/work/ohos-dist-server/dist"
RUSTUP_DIR="/storage/Users/currentUser/work/rustup-ohos"
SIGN_TOOL="/data/service/hnp/bin/binary-sign-tool"
UPDATE_ROOT="http://127.0.0.1:8080/rustup"
DIST_SERVER="http://127.0.0.1:8080"

usage() {
    cat <<'USAGE'
Usage: deploy-rustup-init.sh [OPTIONS]

Options:
  -v, --version       Rustup version (default: 1.30.0)
  -t, --target        Target triple (default: aarch64-unknown-linux-ohos)
  -d, --dist-dir      Dist directory (default: ~/work/ohos-dist-server/dist)
  -r, --rustup-dir    Rustup source dir (default: ~/work/rustup-ohos)
  -s, --sign-tool     Path to binary-sign-tool
  -u, --update-root   RUSTUP_UPDATE_ROOT URL (default: http://127.0.0.1:8080/rustup)
  -h, --help          Show help

Example:
  deploy-rustup-init.sh
  deploy-rustup-init.sh -v 1.30.0 -t x86_64-unknown-linux-ohos
USAGE
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--version)     RUSTUP_VERSION="$2"; shift 2;;
        -t|--target)      TARGET="$2"; shift 2;;
        -d|--dist-dir)    DIST_DIR="$2"; shift 2;;
        -r|--rustup-dir)  RUSTUP_DIR="$2"; shift 2;;
        -s|--sign-tool)   SIGN_TOOL="$2"; shift 2;;
        -u|--update-root) UPDATE_ROOT="$2"; shift 2;;
        -h|--help)        usage;;
        *)                echo "Unknown option: $1"; usage;;
    esac
done

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }

RUSTUP_INIT_BIN="${RUSTUP_DIR}/target/${TARGET}/release/rustup-init"

# === Step 1: Validate prerequisites ===
info "Step 1: Validating prerequisites..."

if [[ ! -x "${RUSTUP_INIT_BIN}" ]]; then
    echo "ERROR: rustup-init binary not found at ${RUSTUP_INIT_BIN}"
    echo "  Build it with:"
    echo "  cd ${RUSTUP_DIR} && cargo build --release \\"
    echo "    --features 'no-self-update,reqwest-native-tls' \\"
    echo "    --target ${TARGET} --locked"
    exit 1
fi

if [[ ! -x "${SIGN_TOOL}" ]]; then
    echo "ERROR: binary-sign-tool not found at ${SIGN_TOOL}"
    exit 1
fi

if [[ ! -f "${RUSTUP_DIR}/rustup-init.sh" ]]; then
    echo "ERROR: rustup-init.sh not found at ${RUSTUP_DIR}/rustup-init.sh"
    exit 1
fi

if [[ ! -d "${DIST_DIR}" ]]; then
    echo "ERROR: Dist directory not found: ${DIST_DIR}"
    exit 1
fi

info "All prerequisites OK"

# === Step 2: Sign rustup-init binary ===
info "Step 2: Signing rustup-init binary..."

SIGNED_BIN="${DIST_DIR}/rustup-init-signed-tmp"
"${SIGN_TOOL}" sign -selfSign 1 -signAlg SHA256withECDSA \
    -inFile "${RUSTUP_INIT_BIN}" \
    -outFile "${SIGNED_BIN}" 2>&1 | grep -v "^$" || true

if [[ ! -f "${SIGNED_BIN}" ]]; then
    echo "ERROR: Signing failed — output file not created"
    exit 1
fi

# Verify .codesign section
if ! readelf -S "${SIGNED_BIN}" 2>/dev/null | grep -q '\.codesign'; then
    echo "ERROR: Signed binary lacks .codesign section"
    rm -f "${SIGNED_BIN}"
    exit 1
fi

chmod +x "${SIGNED_BIN}"
info "Signing verified (.codesign section present)"

# === Step 3: Create directory structure and deploy binary ===
info "Step 3: Deploying signed binary to dist tree..."

DIST_DEFAULT_DIR="${DIST_DIR}/rustup/dist/${TARGET}"
ARCHIVE_DIR="${DIST_DIR}/rustup/archive/${RUSTUP_VERSION}/${TARGET}"

mkdir -p "${DIST_DEFAULT_DIR}"
mkdir -p "${ARCHIVE_DIR}"

# Deploy to both URL paths (dist + archive)
cp "${SIGNED_BIN}" "${DIST_DEFAULT_DIR}/rustup-init"
chmod +x "${DIST_DEFAULT_DIR}/rustup-init"

cp "${SIGNED_BIN}" "${ARCHIVE_DIR}/rustup-init"
chmod +x "${ARCHIVE_DIR}/rustup-init"

rm -f "${SIGNED_BIN}"

# Generate SHA-256 hashes
sha256sum "${DIST_DEFAULT_DIR}/rustup-init" | awk '{print $1}' \
    > "${DIST_DEFAULT_DIR}/rustup-init.sha256"
sha256sum "${ARCHIVE_DIR}/rustup-init" | awk '{print $1}' \
    > "${ARCHIVE_DIR}/rustup-init.sha256"

info "Binary deployed to:"
info "  ${DIST_DEFAULT_DIR}/rustup-init"
info "  ${ARCHIVE_DIR}/rustup-init"

# === Step 4: Generate release-stable.toml ===
info "Step 4: Generating release-stable.toml..."

RELEASE_TOML="${DIST_DIR}/rustup/release-stable.toml"

cat > "${RELEASE_TOML}" <<EOF
schema-version = "1"
version = "${RUSTUP_VERSION}"
EOF

sha256sum "${RELEASE_TOML}" | awk '{print $1}' > "${RELEASE_TOML}.sha256"
info "release-stable.toml written (version ${RUSTUP_VERSION})"

# === Step 5: Deploy patched rustup-init.sh ===
info "Step 5: Deploying patched rustup-init.sh..."

# Copy fresh from source (ensures idempotent re-runs)
cp "${RUSTUP_DIR}/rustup-init.sh" "${DIST_DIR}/rustup-init.sh"

# Inject RUSTUP_UPDATE_ROOT + RUSTUP_DIST_SERVER exports after shebang
# The script's own line 29 uses ${RUSTUP_UPDATE_ROOT:-default}, which
# respects pre-set env vars, so our injected export makes that a no-op.
TMPFILE=$(mktemp)
{
    head -1 "${DIST_DIR}/rustup-init.sh"    # shebang line
    echo ""
    echo "# === OHOS Local Dist Server Override ==="
    echo "# Auto-injected by deploy-rustup-init.sh"
    echo "export RUSTUP_UPDATE_ROOT=\"${UPDATE_ROOT}\""
    echo "export RUSTUP_DIST_SERVER=\"${DIST_SERVER}\""
    echo "# === End OHOS Override ==="
    echo ""
    tail -n +2 "${DIST_DIR}/rustup-init.sh"   # everything after shebang
} > "${TMPFILE}"
mv "${TMPFILE}" "${DIST_DIR}/rustup-init.sh"
chmod +x "${DIST_DIR}/rustup-init.sh"

sha256sum "${DIST_DIR}/rustup-init.sh" | awk '{print $1}' \
    > "${DIST_DIR}/rustup-init.sh.sha256"

info "rustup-init.sh deployed with:"
info "  RUSTUP_UPDATE_ROOT=${UPDATE_ROOT}"
info "  RUSTUP_DIST_SERVER=${DIST_SERVER}"

# === Step 6: Verify deployment ===
info "Step 6: Verifying deployment..."

ERRORS=0

for f in \
    "${DIST_DIR}/rustup-init.sh" \
    "${DIST_DIR}/rustup/release-stable.toml" \
    "${DIST_DEFAULT_DIR}/rustup-init" \
    "${DIST_DEFAULT_DIR}/rustup-init.sha256" \
    "${ARCHIVE_DIR}/rustup-init" \
    "${ARCHIVE_DIR}/rustup-init.sha256"; do
    if [[ -f "$f" ]]; then
        info "  ✓ $f"
    else
        warn "  ✗ MISSING: $f"
        ERRORS=$((ERRORS + 1))
    fi
done

# Verify signed binary has .codesign section
if readelf -S "${DIST_DEFAULT_DIR}/rustup-init" 2>/dev/null | grep -q '\.codesign'; then
    info "  ✓ .codesign section present"
else
    warn "  ✗ .codesign section MISSING"
    ERRORS=$((ERRORS + 1))
fi

# === Summary ===
echo ""
echo "========================================="
echo "  Phase 7 Deployment Complete"
echo "========================================="
echo ""
echo "Install command for new users:"
echo "  curl ${DIST_SERVER}/rustup-init.sh | sh"
echo ""
echo "Auto-install (non-interactive):"
echo "  curl ${DIST_SERVER}/rustup-init.sh | sh -s -- -y --default-toolchain stable"
echo ""

if [[ ${ERRORS} -gt 0 ]]; then
    echo "WARNING: ${ERRORS} verification check(s) failed!"
    exit 1
fi

info "Deployment successful"
