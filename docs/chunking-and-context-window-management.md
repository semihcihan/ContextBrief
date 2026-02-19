# Densification Chunking and Context Window Management (Current Behavior)

## Purpose
- Document how snapshot densification currently handles context-window limits.
- Capture behavior exactly as implemented today, including fallback and retry paths.

## Scope
- Applies to snapshot densification (`DensificationService` -> `ProviderClient`).
- Covers Apple Foundation Models and remote providers (OpenAI/Anthropic/Gemini).
- Describes runtime behavior, not planned changes.

## Terminology quick guide
- **Context-window cap**: maximum total tokens a model call can use (`input + prompt + output`).
- **Chunk budget (`chunkInputTokens`)**: max estimated tokens allowed for each chunk's source text before prompt wrappers are added.
- **Merge budget (`mergeInputTokens`)**: max estimated tokens allowed for merge input text (partials combined for one merge call).
- **Chunk**: one section of original snapshot text produced by chunking.
- **Partial**: dense output produced from a single chunk (`P1`, `P2`, ...).
- **Merge group**: one set of partials merged together in a single merge call.
- **Merge pass**: one full round of merge calls across current partials/groups; can repeat until one final output remains.
- **Output reserve**: token space intentionally kept for model output.
- **Safety margin**: extra buffer for token-estimation drift and provider-side accounting differences.

## High-level flow
1. `DensificationService` receives one captured snapshot and estimates input tokens.
2. If estimated tokens exceed `maxDensificationInputTokens` (default `100_000`), densification is rejected early with `densificationInputTooLong`.
3. Otherwise the request is delegated to the selected `ProviderClient`.
4. Provider client runs densification using either:
   - direct one-shot attempt with fallback to chunking (remote providers), or
   - proactive chunking (Apple).
5. Any unrecovered provider error is handled by `CaptureWorkflow`, which retries densification one additional time before marking snapshot as failed.

## Provider-specific entry behavior

### Remote providers (OpenAI/Anthropic/Gemini)
- First attempt is a single densification call with the full input.
- If and only if error classification says "context window exceeded", fallback switches to adaptive chunking.
- Non-context-window failures are returned immediately.

### Apple Foundation Models
- Densification starts directly in adaptive chunking mode (no single full-input call first).
- Initial chunk/merge budgets are computed dynamically from Apple's `4096` context cap (`input + prompt + output`).

## Entry strategy vs adaptation strategy
- Apple is proactive at entry: it starts in chunking mode.
- Remote providers are reactive at entry: they try full-input first, then switch to chunking only after context-window failure.
- Once chunking is active, both Apple and remote providers use reactive adaptation:
  - merge-path context-window failure triggers merge-local budget reduction first,
  - chunk-path context-window failure triggers smaller chunk budget and retry.
- So Apple effectively uses proactive entry + reactive adaptation; remote providers use reactive entry + reactive adaptation with the same merge-local recovery in chunk mode.

## Context-window error detection
- Fallback is driven by message-based classification (`isContextWindowExceededError`).
- It checks known phrases such as:
  - `context window`
  - `context_length_exceeded`
  - `maximum context length`
  - `prompt is too long`
  - `input token count ... exceeds ... maximum`
- It also avoids misclassifying common rate-limit signals (`tokens per minute`, `rpm`, `quota`, etc.).

## Adaptive chunking loop

### Budget values
- Minimum chunk budget: `320` tokens.
- Context-window caps used by budgeting:
  - Apple path: `4096`.
  - Remote reactive path: `100_000` (high initial assumption, then adapted down by failures).
- Chunk and merge budgets are computed per run from:
  - context-window cap,
  - prompt overhead estimate,
  - reserved output tokens,
  - safety margin for estimation drift.
- Word targets in chunk/merge prompts are also computed dynamically from budgeted input sizes (with floors/ceilings as safeguards).

### Do we include potential output tokens in input sizing?
- Yes, via reservation.
- We do **not** directly add predicted output tokens to input token estimates.
- Instead, we compute allowed input by subtracting reserves from context cap:
  - `allowedInput = contextCap - promptOverhead - outputReserve - safetyMargin`
- Then chunk and merge budgets are derived from `allowedInput`.
- Practical effect: input is intentionally capped lower so the model has room to produce output without crossing context window.

### Retry strategy
- Run `densifyInChunks(...)` with current `chunkInputTokens`.
- If chunk densification fails with context-window overflow, halve `chunkInputTokens` and retry.
- If merge fails with context-window overflow, first perform merge-local retry by halving merge budget only.
- Stop halving at minimum (`320`).
- If merge-local retry cannot recover at minimum merge budget, fall back to chunk-budget reduction.
- If still failing at minimum chunk budget (or if error is non-context-window), surface error.

## `densifyInChunks(...)` behavior

### 1) Chunk the original snapshot text
- Planner splits input into chunks using token estimates.
- Oversized segments are recursively split by words/characters as needed.

### 2) Densify each chunk
- Each chunk is sent to the provider with a chunk prompt:
  - keep facts/intent/actions/outcomes/constraints/errors
  - remove low-signal duplicates
  - target concise output
- Runs are parallelized, bounded by provider-wide work limit.

### 3) Merge partial outputs by passes
- Chunk outputs become `mergedPartials`.
- While more than one partial remains:
  - planner forms `mergeGroups` under merge token budget,
  - each group is merged via provider call,
  - resulting outputs become next pass inputs.
- This is hierarchical merge (multi-pass), not a single always-final full merge.
- If a merge run overflows context window, merge retries run locally with smaller merge budget before chunk recomputation is attempted.

### 4) Non-reducing merge guard
- If merge grouping cannot reduce count (every group size is `1`), merge loop exits and returns joined partials directly.
- This prevents infinite looping when grouping cannot progress.

## What happens when merge pass overflows?
- Merge overflow first triggers merge-local recovery (no chunk recomputation yet).
- Existing chunk partials are reused.
- Merge budget is halved and merge passes are retried on the same partials.
- If merge-local retries fail at minimum merge budget, error bubbles to outer adaptive loop, which halves chunk budget and restarts chunk+merge from original snapshot input.

## Capture-level retry and final failure
- `CaptureWorkflow` retries densification up to `2` attempts total for provider request failures.
- If all attempts fail:
  - snapshot is persisted with `status = failed`,
  - failure message is stored.

## Example: 4-chunk snapshot
- First full-input attempt fails with context-window error (remote providers) or is skipped (Apple).
- Input is split into `C1`, `C2`, `C3`, `C4`.
- Chunk densification returns `P1`, `P2`, `P3`, `P4`.
- Initial merge pass overflows.
- Merge-local retry halves merge budget and regroups partials (for example `[P1, P2]` and `[P3, P4]`), then continues merging by passes.
- If merge-local retries still overflow at minimum merge budget, adaptive loop reduces chunk budget and reruns from original input.

## Current trade-off
- Dynamic budgeting and merge-local retry reduce token/call waste on large snapshots.
- Complexity is higher than the previous single-loop strategy, but recovery is still deterministic:
  - merge-local adaptation first,
  - chunk-level adaptation second.

## Naming update
- Planner is now `ContextWindowPlanner` to reflect provider-neutral usage.
