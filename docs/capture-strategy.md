# Capture Strategy

## Goals

- Preserve important context with high recall.
- Keep capture payloads short enough for densification.
- Use deterministic, auditable rules instead of subjective post-processing.

## Decision Model

### 1) App category

Each capture is categorized from bundle identifier:

- `browser`: Safari, Chrome, Firefox, Arc
- `webViewHeavy`: Slack, Teams, Notion, Electron-like apps
- `nativeApp`: everything else

### 2) Accessibility-first capture

Accessibility capture always runs first.

- `browser` and `webViewHeavy` avoid global chrome roots (`AXMenuBar`, app root) to reduce noise.
- `nativeApp` keeps broader roots for recall.
- Root seeding is window-based; `AXFocusedUIElement` is not used as a capture root.

### 3) Accessibility quality tier

Accessibility lines are scored deterministically:

- `high`: meaningful lines >= 8, or meaningful >= 4 with at least one must-keep anchor
- `medium`: meaningful lines 3...7
- `low`: meaningful lines <= 2

Must-keep anchors include failure/risk/status terms such as `error`, `warning`, `timeout`, `failed`, etc.

## OCR Policy

OCR policy is category-aware:

- `browser`: OCR is conditional and runs only when signal risk is high.
- `nativeApp` / `webViewHeavy`: OCR is always captured and used as a visibility anchor.

- `empty accessibility` -> run OCR
- `high accessibility` -> skip OCR
- `medium accessibility`:
  - run OCR if content root is missing
  - run OCR if must-keep anchors are missing
- `low accessibility` -> run OCR

## OCR Scope

- OCR uses front-window screenshot only.
- No automatic full-display fallback.
- If front-window capture is unavailable, OCR is skipped and logged.

This avoids cross-app leakage and keeps payloads focused.

## Browser Filtering

For browser snapshots:

1. Keep baseline capture.
2. Prefer tab/content-root lines as candidate lines.
3. Apply deterministic noise rules.
4. Carry over missing must-keep lines from baseline.
5. If filtered output is empty, fall back to baseline.

### Frequency-based noise

Repetition frequency is computed from normalized non-deduplicated candidate lines before final deduplication. This ensures repeated boilerplate detection remains effective.

### URL handling

- Keep one primary URL.
- Drop obvious in-page anchors.
- Keep hash-router style URLs (for example `/#/settings`) by avoiding over-aggressive `#` removal.

## Output Selection

- Baseline capture is always retained.
- Filtered capture is preferred when available and non-empty.
- For non-browser apps, filtered output keeps accessibility lines that align with OCR-visible tokens and merges OCR lines; if alignment fails, OCR lines are used.
