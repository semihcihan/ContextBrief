# Context Brief

Context Brief is a macOS menu bar app that captures what you are working on, cleans it up into high-signal context, and keeps it ready to copy into LLMs and coding agents.

## What it does

- Captures context from your frontmost app or browser tab.
- Uses Accessibility first, then screenshot + OCR fallback when needed.
- Densifies captured content with your own provider API key.
- Stores your context history locally on your Mac.
- Lets you keep one current context and keep appending snapshots to it.

## Requirements

- macOS 13 or newer.
- Accessibility permission.
- Screen Recording permission.
- One provider setup:
  - OpenAI
  - Anthropic
  - Google

## Install

### Option 1: Homebrew

```bash
brew install semihcihan/contextbrief/contextbrief
```

### Option 2: DMG

1. Download `ContextBriefApp.dmg` from the latest GitHub release.
2. Open the DMG and drag `ContextBriefApp.app` into `/Applications`.
3. Launch `ContextBriefApp`.

If macOS blocks the app on first launch (unsigned build), run:

```bash
xattr -cr /Applications/ContextBriefApp.app
```

Then right-click the app and choose `Open`.

## First launch setup

1. Open the app from the menu bar (`Ctx`).
2. Grant:
   - Accessibility
   - Screen Recording
3. Select your provider.
4. Enter model and API key.
5. Finish setup.

Until setup is complete, capture actions remain blocked.

## Daily usage

- Use menu bar action or shortcut to add a snapshot to the current context.
- Copy current context when you are ready to paste into an LLM.
- Create a new context for a new task.
- Undo last snapshot or promote last snapshot into a new context.
- Open Context Library to switch back to older contexts.

## Updates

- Use `Check for Updates...` in the app menu to compare your version with the latest GitHub release.
- On app launch, a silent check runs and only prompts when a newer version is available.
- Updating is manual download/install from releases.

## Data and privacy

- Contexts are stored locally:
  - `~/Library/Application Support/ContextBrief/store.json`
  - `~/Library/Application Support/ContextBrief/artifacts/*.png`
- API keys are stored in macOS Keychain.
- Model requests go only to your selected provider using your key.

## Troubleshooting

### Capture is empty or poor quality

- Re-check permissions in:
  - `System Settings -> Privacy & Security -> Accessibility`
  - `System Settings -> Privacy & Security -> Screen Recording`
- Browser content may rely on OCR fallback depending on browser accessibility exposure.

### App does not open because of macOS warning

- Run:
  ```bash
  xattr -cr /Applications/ContextBriefApp.app
  ```
- Then open via right-click -> `Open`.

## For developers

- Development and release commands are documented in `Makefile`.
- Run `make help` for target descriptions.
- Full release runbook: `docs/release.md`.
