#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE_PATH="${1:-.build/release/ContextBrief.app}"
DMG_PATH="${2:-.build/release/ContextBrief.dmg}"

if [[ ! -d "${APP_BUNDLE_PATH}" ]]; then
  echo "App bundle not found: ${APP_BUNDLE_PATH}"
  exit 1
fi

APP_NAME="$(basename "${APP_BUNDLE_PATH}")"
VOLUME_NAME="${APP_NAME%.app}"
STAGING_DIR="$(dirname "${DMG_PATH}")/dmg_staging"

rm -f "${DMG_PATH}"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

cp -R "${APP_BUNDLE_PATH}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}" \
  -quiet

rm -rf "${STAGING_DIR}"
echo "DMG created at ${DMG_PATH}"
