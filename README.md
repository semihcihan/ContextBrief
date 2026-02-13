# Context Generator Demo

Minimal macOS menu bar demo for testing capture reliability from desktop apps and web pages.

## What this demo does
- Adds a menu bar item labeled `Ctx`.
- Requests Accessibility + Screen Recording permissions on launch.
- Captures context from the frontmost app when you click `Capture Context`.
- Stores a single latest context locally.
- Copies the latest captured context to clipboard with `Copy Last Context`.

## Run
```bash
swift run ContextGeneratorDemo
```

## Saved files
The latest capture is saved at:
- `~/Library/Application Support/ContextGeneratorDemo/latest-context.json`
- `~/Library/Application Support/ContextGeneratorDemo/latest-context.txt`
- `~/Library/Application Support/ContextGeneratorDemo/latest-screenshot.png` (when screenshot capture succeeds)

## Notes on reliability
- The app uses Accessibility extraction first and OCR from screenshot as fallback/supplement.
- Browser pages often need OCR fallback depending on browser accessibility exposure.
- If capture is empty, verify permissions in:
  - `System Settings -> Privacy & Security -> Accessibility`
  - `System Settings -> Privacy & Security -> Screen Recording`
