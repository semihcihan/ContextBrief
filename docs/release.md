# Release Runbook

## Release strategy
- Distribution channels: GitHub Releases DMG and Homebrew Cask tap.
- Update strategy: in-app GitHub release check that opens release page.
- Signing strategy: unsigned-first.

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

Verify artifacts:
- `.build/release/ContextBriefApp.app`
- `.build/release/ContextBriefApp.dmg`

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
Unsigned builds may trigger Gatekeeper warnings. Include this in release notes:

```bash
xattr -cr /Applications/ContextBriefApp.app
```

Then users can open the app via right-click -> `Open`.

## Rollback
If a bad release is published:
1. Mark the GitHub release as pre-release or remove it.
2. Push a new patch tag (for example `v1.0.1`) with fixes.
3. Confirm Homebrew cask points to the corrected tag and SHA256.

## Future hardening
- Add Developer ID signing.
- Add notarization and stapling.
- Remove `xattr` workaround from release notes once notarized distribution is live.
