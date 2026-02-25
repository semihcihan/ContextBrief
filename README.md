# Context Brief

A macOS menu bar app that helps developers collect context from the frontmost app (GitHub, GitLab, Jira, Linear, Slack, Notion, Confluence, docs, and web pages) with `⌃ ⌘ C`, then paste one clean brief into coding agents with `⌃ ⌘ V`.

## What it does

- Captures context from the frontmost selected app or browser tab, including page content beyond what is currently visible.
- Cleans and densifies raw captures into a high-signal context your coding agent can use immediately.
- Lets you build one context from multiple snapshots, then paste the compiled result into any LLM or coding agent.
- Stores context history locally on your Mac so you can return to earlier tasks.

## Daily usage

1. Open the app/tab that contains relevant context (for example a GitHub PR, GitLab issue, Jira or Linear ticket, Slack thread, Notion page, Confluence page, or any web page).
2. Capture a snapshot with `Control + Command + C`.
3. Repeat in other apps/tabs to gather all related context for the same task.
4. Paste the compiled context with `Control + Command + V` into your coding agent.
5. Start a new context when you switch tasks, or reopen older ones from Context Library.

## Requirements

- macOS 13 or newer.
- Accessibility permission.
- Screen Recording permission.
- Coding Agent CLI installed and configured:
  - OpenAI
  - Anthropic
  - Google

## Install

### Option 1: DMG

1. Download `ContextBrief.dmg` from the [latest GitHub release](https://github.com/semihcihan/contextbrief/releases/latest).
2. Open the DMG and drag `ContextBrief.app` into `/Applications`.
3. Launch `ContextBrief`.

### Option 2: Homebrew

```bash
brew install semihcihan/contextbrief/contextbrief
```

To update:

```bash
brew update && brew upgrade contextbrief
```

## First launch setup

1. Grant permissions for capturing context:
   - Accessibility
   - Screen Recording
2. Select your CLI provider (Codex, Claude, or Gemini).
3. Enter model (optional).
4. Finish setup.

Until setup is complete, capture actions remain blocked.

## Data and privacy

- Contexts are stored locally:
  - `~/Library/Application Support/ContextBrief/store.json`
  - `~/Library/Application Support/ContextBrief/artifacts/*.png`
- No API keys; CLIs use their own auth.
- Model requests go through your installed CLI to your selected provider.

## License

MIT
