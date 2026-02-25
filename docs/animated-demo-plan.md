# Animated Demo Plan (HTML)

Plan for a short animated demo that shows Context Brief’s capture-from-multiple-sources → paste-one-brief flow. Built as a single HTML (+ CSS/JS) experience so it can be run in a browser, screen-recorded, or exported to video/GIF.

## Format and framing

- **Aspect ratio:** 16:9 (e.g. 1280×720 or 1920×1080).
- **Each scene:** One app at a time, shown **full screen** (fills the entire frame; no floating windows). Viewer feels like they’re inside that app.
- **Style:** Graphic/cartoony representations — **not** full app UIs. Simplified screens with recognizable layout, colors, and app name. Some real titles/labels; body text is mostly **redacted** (blocks, lines, or placeholder bars).

## Why HTML

- One stack: HTML/CSS/JS, no design tool lock-in.
- Easy to tweak copy, timing, and transitions without re-recording.
- Works in any browser; record with OBS, QuickTime, or browser DevTools.
- Can be embedded on a landing page or README later.
- Scenes are simple divs + text + redacted blocks; no need to replicate full Jira/Slack/GitHub.

## Sequence Overview

1. **Jira** (cartoony ticket) → “Add snapshot” → flash + caption `⌃ ⌘ C`
2. **Transition** (e.g. slide left)
3. **Slack** (cartoony thread) → “Add snapshot” → flash + caption `⌃ ⌘ C`
4. **Transition**
5. **GitHub** (cartoony PR) → “Add snapshot” → flash + caption `⌃ ⌘ C`
6. **Transition**
7. **Terminal** (cartoony) → “Copy current context” then paste → flash + caption `⌃ ⌘ V` → show pasted content

## Scene Specs

Each scene is a **graphic/simplified** version of the app: recognizable layout and colors, app name visible, a few real titles/labels, and **mostly redacted** body content (gray blocks, lines, or “lorem” bars). No need to build full Jira/Slack/GitHub UIs. Full-screen per scene (16:9 frame).

### 1. Jira (graphic ticket)

- **Layout/colors:** Jira-style (blue header/top bar, light content area, left sidebar). “Jira” + icon visible.
- **Content:** One **bug** ticket — e.g. “AUTH-891 Login fails on Safari — redirect loop after sign-in”, status badge; description area redacted.
- Full-screen fill. Then: add snapshot → **flash** → **caption:** `⌃ ⌘ C`.

### 2. Slack (graphic thread)

- **Layout/colors:** Slack-style (purple sidebar, dark thread area). “Slack” + icon visible.
- **Content:** Channel e.g. #auth-safari-bug. Messages: **scope clarification** (e.g. “Only Safari or other browsers too?” “Only Safari.”) and **extra direction** (e.g. “When you fix it, add some logging around that path so we can debug if it happens again.”).
- Full-screen fill. Then: add snapshot → **flash** → **caption:** `⌃ ⌘ C`.

### 3. GitHub (external library issue)

- **Layout/colors:** GitHub-style (dark header, white/gray content). “GitHub” + repo name (e.g. auth-lib/session).
- **Content:** **Resolved issue** on an external library repo — e.g. “Safari redirect loop with SameSite cookies” #142 closed. Visible solution (e.g. set SameSite=None; Secure, fixed in v3.2). Points us at how to fix the bug.
- Full-screen fill. Then: add snapshot → **flash** → **caption:** `⌃ ⌘ C`.

### 4. Terminal / coding agent (graphic)

- **Layout/colors:** Terminal or chat UI (dark background). “Coding agent” or “Terminal” visible.
- **Content:** Prompt; then paste. **Pasted brief** = Jira bug summary + Slack scope/direction + GitHub issue solution (one clean combined context).
- **Flash** → **caption:** `⌃ ⌘ V` → pasted content appears.

## Interactions and Effects

- **Flash:** CSS animation (e.g. white/light overlay or border pulse) on the whole scene for ~0.3–0.5s when “Add snapshot” or “Paste” is triggered.
- **Caption:** Centered or corner overlay with `⌃ ⌘ C` or `⌃ ⌘ V`; same style each time; show for ~1–1.5s then fade out.
- **Add snapshot:** Can be implied by flash + caption only, or a small UI hint (e.g. menu bar icon, tooltip “Snapshot added”) before the flash.

## Transitions Between Apps

- **Slide:** e.g. current scene slides out left, next scene slides in from right (or vice versa). Consistent direction for the whole sequence.
- **Alternative:** Simple crossfade.
- Duration: ~0.4–0.6s per transition so it feels snappy but readable.

## URL parameters (same page, different view)

Use query params to show different states of a scene without separate HTML files:

- **`?caption=1`** — Show the shortcut caption overlay (reusable component). Default keys = copy (`⌃ ⌘ C`).
- **`?keys=paste`** — Use with `caption=1` to show paste shortcut (`⌃ ⌘ V`) instead of copy.
- **`?flash=1`** — Run the flash animation once on load.
- **`?flash=1&caption=1`** — Flash plays, then caption appears (for capture/paste moment).
- **`?state=flash`** / **`?state=caption`** — Same as `flash=1` or `caption=1`.
- **`?scene=jira|slack|github|terminal`** — Show only that scene (for single-scene view or recording).
- **`?play=1`** — Run the full sequence: Jira → flash+caption (copy) → slide → Slack → flash+caption → slide → GitHub → flash+caption → slide → Terminal → flash+caption (paste) → show pasted brief. No other params needed.

Example: `index.html?play=1` for full demo; `index.html?scene=slack&caption=1` for Slack with caption.

## Implementation approach: single HTML + scripts

**One `index.html`** holds all scenes and the shared overlays:

- **Shared (always in the DOM):** `.frame`, `.flash-overlay`, `.caption-overlay`, `.caption-keys`.
- **Scenes (siblings inside `.frame`):** `.jira-scene`, `.slack-scene`, `.github-scene`, `.terminal-scene`. Each scene is a full-screen block (e.g. `position: absolute; inset: 0` or a wrapper that shows one at a time).

**Visibility:** Only one scene is “active” at a time. Use a single active class or attribute (e.g. `data-active="jira"` on `.frame` and `[data-scene="jira"]` on each scene), and CSS like:

- `[data-scene]:not([data-active]) { visibility: hidden; opacity: 0; pointer-events: none; }`  
  or
- `.frame [data-scene] { position: absolute; inset: 0; }` and `.frame[data-active="jira"] [data-scene="jira"] { z-index: 1; }` so the active scene stacks on top.

**Transitions:** Implement the slide with CSS + JS:

- Put all scenes in a **track** (e.g. a horizontal flex or grid, or a wrapper with `transform: translateX`). The track’s width is `100% * number of scenes`. Active “slide” = `translateX(-(index * 100%)`. Transition the track’s `transform` (e.g. `transition: transform 0.5s ease-out`) when changing the active index.  
  **Or:** Keep scenes stacked (all `position: absolute; inset: 0`). On “next”: current scene gets a class that animates it out (e.g. `transform: translateX(-100%)`), incoming scene is positioned at `translateX(100%)` and animates to `translateX(0)`. Same idea in reverse for “previous” if needed.

**Script (`script.js`):**

- **URL params (current behavior):** `?scene=jira|slack|github|terminal` to show that scene; `?flash=1`, `?caption=1`, `?keys=paste` for overlays. No param = default scene (e.g. jira).
- **Optional auto-play:** e.g. `?play=1` runs a timeline: show scene 1 → wait → trigger flash → show caption → wait → transition to scene 2 → … → terminal → paste caption → show pasted content. Implement with `setTimeout` or a small sequence runner that sets `frame.dataset.active = 'slack'`, triggers flash/caption, then advances after a delay.

**Summary:** All pages live inside `index.html` as separate scene divs. Scripts switch the active scene (and optionally run the full sequence) and control flash/caption; CSS handles slide (or crossfade) transitions.

## Timeline (rough)

- Jira visible: ~2s → flash + `⌃ ⌘ C` (~1s) → transition (~0.5s).
- Slack: ~2s → flash + `⌃ ⌘ C` (~1s) → transition.
- GitHub: ~2s → flash + `⌃ ⌘ C` (~1s) → transition.
- Terminal: ~1.5s → flash + `⌃ ⌘ V` (~1s) → pasted content visible ~3s.
- Total: ~15–20s (good for GIF or short video).

## Recording and Export

- **Viewport:** 16:9 only (e.g. 1280×720 or 1920×1080). Each scene is full-screen within this frame.
- Disable cursor or use a simple CSS cursor for “click” moments if desired.
- Record via OBS, QuickTime (screen), or DevTools → “Capture full size screenshot” / video if available.
- For GIF: trim to one loop (e.g. Jira → Slack → GitHub → Terminal → paste) and loop.

## Out of Scope for This Doc

- Exact copy for Jira/Slack/GitHub (use placeholders; can reference the earlier script in chat if needed).
- Brand colors/fonts (use neutral “cartoony” style unless you add a style guide).
- Sound or voiceover (can be added later to the recorded video).
