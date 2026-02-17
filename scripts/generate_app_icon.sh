#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SOURCE_HTML="${1:-${REPO_ROOT}/docs/app-icon.html}"
OUTPUT_DIR="${2:-${REPO_ROOT}/Sources/ContextGeneratorApp/Resources}"
ICON_NAME="${3:-AppIcon}"

if [[ ! -f "${SOURCE_HTML}" ]]; then
  echo "Source HTML not found: ${SOURCE_HTML}"
  exit 1
fi

for cmd in swift sips iconutil; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}"
    exit 1
  fi
done

mkdir -p "${OUTPUT_DIR}"

ABS_SOURCE_HTML="$(cd "$(dirname "${SOURCE_HTML}")" && pwd)/$(basename "${SOURCE_HTML}")"
ICONSET_DIR="${OUTPUT_DIR}/${ICON_NAME}.iconset"
ICNS_PATH="${OUTPUT_DIR}/${ICON_NAME}.icns"
RENDER_SCRIPT="${SCRIPT_DIR}/render_icon.swift"

if [[ ! -f "${RENDER_SCRIPT}" ]]; then
  echo "Missing render script: ${RENDER_SCRIPT}"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

swift "${RENDER_SCRIPT}" \
  --input "${ABS_SOURCE_HTML}" \
  --output "${TMP_DIR}/source.png" \
  --size 1024

rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"

resize_icon() {
  local size="$1"
  local file_name="$2"
  sips -z "${size}" "${size}" "${TMP_DIR}/source.png" --out "${ICONSET_DIR}/${file_name}" >/dev/null
}

resize_icon 16 "icon_16x16.png"
resize_icon 32 "icon_16x16@2x.png"
resize_icon 32 "icon_32x32.png"
resize_icon 64 "icon_32x32@2x.png"
resize_icon 128 "icon_128x128.png"
resize_icon 256 "icon_128x128@2x.png"
resize_icon 256 "icon_256x256.png"
resize_icon 512 "icon_256x256@2x.png"
resize_icon 512 "icon_512x512.png"
cp "${TMP_DIR}/source.png" "${ICONSET_DIR}/icon_512x512@2x.png"

iconutil -c icns "${ICONSET_DIR}" -o "${ICNS_PATH}"

echo "Generated icon assets:"
echo "  ${ICONSET_DIR}"
echo "  ${ICNS_PATH}"
