# Title from JSON and Naming Fallback

## Why this document exists

- We have two logical requests per snapshot: densification (dense content) and naming (snapshot title). For Codex and Claude we can get both from a single densification call by using structured JSON output. For Gemini we ask for a title in the prompt and parse it from the response when present.
- When the densification response includes a valid `title`, we use it and skip the second NamingService call. When we cannot deduce a title (provider does not support structured JSON, field missing, or parse failure), we fall back to NamingService.

## Decisions (locked)

### 1) Enforce output shape via CLI where supported (Codex, Claude)

- **Codex**: Use `--output-schema <path>` with a JSON Schema file (see [Codex CLI reference](https://developers.openai.com/codex/cli/reference)). We write a temp schema file requiring `content` and `title` and pass its path. No need to ask for JSON in the prompt.
- **Claude**: Use `--json-schema '<schema>'` (print mode) so the CLI returns validated JSON matching the schema (see [Claude CLI reference](https://code.claude.com/docs/en/cli-reference)). We pass the same schema as a single argument. No need to ask for JSON in the prompt.
- For both, we use a prompt that asks for dense content and a short title but does not instruct "respond with JSON"; the CLI enforces the shape.

### 2) Prompt-only for Gemini

- Gemini does not support structured output in the CLI. We ask in the densification prompt for a JSON object with `content` and `title` and parse the response; if `title` is missing or parsing fails, we fall back to NamingService.

### 3) Check for `title` in the response for all providers

- After parsing the densification response (from structured output or best-effort JSON), we look for a non-empty `title` field in the parsed payload.
- Extraction uses `content` (or existing keys such as `result`, `response`, `output`, `message`, `text`) for the main text and `title` for the snapshot title. If `title` is present and non-empty, we use it and do not call NamingService for that snapshot.

### 4) NamingService as fallback when title is missing

- If the densification response has no valid `title` (missing, empty, or JSON parsing failed), we call NamingService to generate the snapshot title. Errors and retries for densification are unchanged; only the success path is extended with optional title and fallback.

## Flow summary

1. **Densification request**  
   Send a single request with a prompt that asks for JSON with `content` and `title`. Use structured output for Codex/Claude when supported.

2. **Parse response**  
   Parse JSON from the provider (existing logic: `parseJSONPayload`). Extract content and, when present, `title` (`extractCLIText`, `extractCLITitle`).

3. **Use title from response when present**  
   If the payload has a non-empty `title`, use it as the suggested snapshot title and do not call NamingService for this snapshot.

4. **Fallback to NamingService**  
   If there is no usable `title` in the response, call NamingService to generate the snapshot title (existing `suggestSnapshotTitle`).

## Non-goals

- Do not require Gemini to support JSON schema; prompt-based request for `title` and best-effort parsing are sufficient, with NamingService as fallback.

## Context title from first snapshot

- When the first snapshot is added to a context (capture or promote), the context title is set to that snapshot’s title (from densification or NamingService).
- The context title is refreshed every N successful snapshots (see provider-parallelism-and-context-routing.md; e.g. every 3 turns) via NamingService; the first snapshot sets the initial title, then it is updated on the configured cadence.

## Implementation notes

- **Schema**: Shared JSON Schema `{"type":"object","properties":{"content":{"type":"string"},"title":{"type":"string"}},"required":["content","title"],"additionalProperties":false}`. Codex gets it via a temp file path (`--output-schema`); Claude gets it as the `--json-schema` argument.
- **Prompts**: `densificationPromptForStructuredOutput(for:)` for Codex/Claude (no "respond with JSON" instruction). `densificationPrompt(for:)` for Gemini (includes explicit JSON instruction).
- **ProviderClient**: `densify` returns `DensificationResult(content: String, title: String?)`. `requestDensification` runs the CLI with schema (Codex/Claude) or prompt-only (Gemini) and parses response for both `content` and `title`. When the payload has a `structured_output` object (e.g. Claude CLI), we read `content` and `title` from it first; otherwise we use top-level keys: `content`, `result`, `response`, `output`, `message`, `text` for content and `title` for the snapshot title.
- **CaptureWorkflow**: Passes `suggestedSnapshotTitle` from the densification outcome in `CaptureWorkflowResult`. When densification succeeds with a title, it is set; otherwise `nil`.
- **applyGeneratedNames**: Uses `result.suggestedSnapshotTitle` when present and non-empty; otherwise calls `namingService.suggestSnapshotTitle(...)`.
