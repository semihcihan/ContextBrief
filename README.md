# Context Generator V1 Prototype

Local-first macOS menu bar app for collecting context from desktop apps and browser tabs into a selected current context.

## What this build does
- Adds a menu bar item labeled `Ctx`.
- Enforces onboarding before capture:
  - Accessibility permission.
  - Screen Recording permission.
  - Provider setup (OpenAI, Anthropic, Google) + API key.
- Captures full frontmost app context (AX + screenshot/OCR fallback).
- Densifies each capture through the selected provider using your API key.
- Appends captures as ordered pieces to one selected current context.
- Supports:
  - Create/select current context.
  - Undo last capture in current context.
  - Promote last capture into a new context.
  - Copy current context in dense or raw mode.

## Run
```bash
swift run ContextGeneratorApp
```

## Saved files
Data is stored at:
- `~/Library/Application Support/ContextGenerator/store.json`
- `~/Library/Application Support/ContextGenerator/artifacts/*.png`

## Tests
```bash
swift test
```

## Notes on reliability
- The app uses Accessibility extraction first and OCR from screenshot as fallback/supplement.
- Browser pages often need OCR fallback depending on browser accessibility exposure.
- If capture is empty, verify permissions in:
  - `System Settings -> Privacy & Security -> Accessibility`
  - `System Settings -> Privacy & Security -> Screen Recording`
