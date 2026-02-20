# CLI-Only LLM and Session Handoff

## Why this document exists

- Lock the new architecture direction: remove internal model providers and run LLM tasks through installed CLIs only.
- Capture what is feasible today for densification, naming, and session handoff.
- Define implementation guidance based on proven headless CLI patterns.

## Decisions (locked)

1. `cn` / Continue is reference-only and not supported in this app.
2. Internal providers are removed as a product direction (OpenAI/Anthropic/Gemini/Apple provider path is not the target).
3. Both snapshot densification and naming use the same CLI-based execution path.
4. Session-resume/injection mode is out of scope for now ("mode B" deferred).
5. Primary handoff remains copy + paste into the user’s current chat/session.

## Scope

In scope:

- Densification through headless CLI commands.
- Snapshot/context naming through headless CLI commands.
- Direct paste workflow support (copy prepared text and auto-paste where possible).
- CLI backend configuration and execution reliability.

Out of scope (for this rollout):

- Resuming last session and injecting prompts into that session.
- Targeting arbitrary existing active sessions across different tools.
- Supporting `cn` / Continue as a backend.

## Feasibility summary

### Densification and naming

Both are feasible without a working directory requirement in the general case. They are text-in/text-out tasks and can run from a neutral temporary directory as long as the CLI supports non-interactive operation.

### Session injection

Cross-CLI "inject into whatever session is currently active" is not a reliable universal capability. The robust cross-tool flow is clipboard handoff and user paste (with optional auto-paste best effort, same as current behavior).

### Working directory

- Not required for pure densification/naming in principle.
- May be required by some CLIs if they assume repository context.
- For Codex non-interactive runs, `--skip-git-repo-check` enables execution outside a git repository.

## External references

- Codex CLI reference (`codex exec`, `--json`, `--output-last-message`, `--skip-git-repo-check`, resume semantics): [OpenAI Codex CLI](https://developers.openai.com/codex/cli/reference#codex-exec)
- Claude headless/non-interactive usage (`-p`, output formats): [Claude headless docs](https://code.claude.com/docs/en/headless)
- VS Code chat CLI and stdin behavior: [VS Code command-line docs](https://code.visualstudio.com/docs/configure/command-line)

## Reference patterns from summarize-main

The project at `/Users/semihcihan/Downloads/summarize-main/src/llm` has production-quality patterns we should reuse.

### 1) Binary resolution with overrides

- Resolve executable path in this order:
  1. app config (`binary`)
  2. provider-specific env override (for example `CODEX_PATH`)
  3. app-level env override
  4. default binary name

### 2) Non-interactive execution contract

- Use a process runner that supports:
  - stdin input
  - timeout
  - cwd override
  - merged environment
  - large stdout buffer
- Return `stdout` and `stderr`; on failure include trimmed `stderr` in error message.

### 3) Provider/CLI-specific argument building

- Build arguments per CLI adapter, not in shared logic.
- Keep shared runner generic; adapter owns flags like `--print`, `--output-format json`, or `codex exec` flags.

### 4) Codex-specific robustness

- Prefer `codex exec --output-last-message <file> --skip-git-repo-check --json`.
- Parse JSONL for usage/cost when needed.
- Read `<file>` as primary result; use stdout fallback if file is empty.

### 5) Structured-output fallback strategy

- For CLIs that emit JSON, parse JSON payloads and extract canonical text fields.
- If JSON parsing fails, fallback to trimmed stdout.
- Treat empty outputs as hard failures.

### 6) Optional cwd

- Keep `cwd` optional in adapter options.
- Use neutral cwd by default for pure text tasks.
- Allow configured/explicit cwd for CLIs that need repo context.

## Target architecture in Context Generator

### New runtime seam

- Introduce a CLI-backed text generation seam used by both:
  - `DensificationService`
  - `NamingService`

Proposed shape:

- `CLICommandRunning` (process execution)
- `CLITextGenerating` (prompt -> text)
- `CLIAdapter` implementations per supported CLI

### Prompt ownership

- Keep prompt templates in app code (deterministic, testable).
- Adapters only execute prompts and parse outputs.
- Densification and naming keep separate prompt builders.

### Error model

- Normalize process failures into app-level errors with user-facing messages.
- Include key context (`cli`, `exit code`, `stderr summary`) in logs.
- Preserve retry behavior for transient request/process failures where appropriate.

## Product behavior (v1 for this direction)

### Densification

- Capture pipeline calls CLI backend for dense output.
- If output is empty, treat as failure and apply existing retry/failure semantics.

### Naming

- Snapshot/context title generation calls the same CLI backend with naming prompts.
- Existing fallback behavior remains: if generation fails/empty, use fallback title.

### Session handoff

- Continue with copy + optional auto-paste behavior.
- No background "resume and inject into last session" behavior in this rollout.

## Migration plan (single direction)

1. Add CLI execution primitives (runner + adapter interface + one adapter).
2. Route `DensificationService` through CLI backend.
3. Route `NamingService` through CLI backend.
4. Remove provider-based setup requirements from onboarding/runtime gates.
5. Remove provider client usage and provider-specific request routing paths.
6. Simplify app state/config to CLI-oriented fields.
7. Delete obsolete provider-only code once parity tests pass.

## Configuration direction

Configuration should be CLI-oriented, not API-provider-oriented.

### Runtime config (backing settings, not UI)

The following fields are runtime/backing configuration values the app uses to run CLI commands:

- selected CLI (`codex`, `claude`, etc.)
- optional binary override
- optional model override
- optional extra args
- timeout
- optional working directory override

### Settings UI changes

Setup/settings UI should be updated to reflect the CLI-only architecture:

- Replace provider + API key setup with a CLI tool selector.
- Keep model as an optional override (not mandatory for every CLI).
- Add an optional binary path override field.
- Add optional advanced args and timeout controls.
- Keep working directory optional and hidden under advanced settings.
- Run a setup-time "CLI availability check" and show actionable errors when missing.

## Test strategy

- Unit:
  - command runner error/timeout handling
  - adapter argument construction
  - parser behavior (json, jsonl, plain text, empty output)
- Integration:
  - densification happy path and failure path
  - naming happy path and fallback path
- Regression:
  - capture retry behavior unchanged
  - copy/paste export behavior unchanged

## Risks and mitigations

- CLI output format drift:
  - keep parser tolerant
  - prefer explicit flags for stable formats
- Missing binary on user machine:
  - detect early in setup, show clear fix instructions
- Permission/interactive prompts in headless runs:
  - use non-interactive flags where available
  - fail fast with actionable error messaging
