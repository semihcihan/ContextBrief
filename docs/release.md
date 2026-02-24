# Release Runbook

## Release strategy
- Distribution channels: GitHub Releases DMG and Homebrew Cask tap.
- Update strategy: in-app GitHub release check that opens release page.
- Signing strategy: Developer ID signed + notarized DMG.

## Prerequisites
- GitHub Actions enabled for this repository.
- A Homebrew tap repository (example: `semihcihan/homebrew-contextbrief`).
- Repository variable:
  - `HOMEBREW_TAP_REPO` (example: `semihcihan/homebrew-contextbrief`)
- Repository secret:
  - `HOMEBREW_TAP_REPO_TOKEN` (token with push access to tap repository)

If the Homebrew variable or secret is missing, release still succeeds but tap update is skipped.

## Local preflight
```bash
swift test
make release-dmg VERSION=1.0.0 BUILD_NUMBER=1
```

To test "installed app" behavior (minimal PATH, as when user opens the app from DMG or Applications) without using GitHub or brew:
- `make run-release-app-minimal-env` — runs the release executable with `PATH=/usr/bin:/bin:/usr/sbin:/sbin` so CLI resolution (e.g. finding `codex` under `/opt/homebrew/bin`) is exercised.
- `make open-release-app` — opens the built `.app` via Finder (same as double-click after install); the process gets the same minimal environment as a real install.

Verify artifacts:
- `.build/release/ContextBrief.app`
- `.build/release/ContextBrief.dmg`

## Release process
1. Ensure `main` contains the desired release changes.
2. Create and push a tag:
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```
3. GitHub Actions workflow `.github/workflows/release.yml` runs automatically.
4. Workflow will:
   - Derive version from tag (`v1.0.0` -> `1.0.0`)
   - Build app bundle and DMG
   - Compute DMG SHA256
   - Publish GitHub Release with DMG asset
   - Update Homebrew cask in tap repo (if configured)

## First-launch guidance for users
Signed and notarized builds should open directly after drag-and-drop install.

## Rollback
If a bad release is published:
1. Mark the GitHub release as pre-release or remove it.
2. Push a new patch tag (for example `v1.0.1`) with fixes.
3. Confirm Homebrew cask points to the corrected tag and SHA256.

## Future hardening
- Add automated verification checks against release artifacts on a clean machine.
