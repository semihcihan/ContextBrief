# Densification Chunking and Context Window Management (Current Behavior)

## Purpose
- Document how snapshot densification currently handles context-window limits.
- Capture behavior exactly as implemented today, including fallback and retry paths.

## Scope
- Applies to snapshot densification (`DensificationService` -> `ProviderClient`).
- Covers Apple Foundation Models and remote providers (OpenAI/Anthropic/Gemini).
- Describes runtime behavior, not planned changes.

## High-level flow
1. `DensificationService` receives one captured snapshot and estimates input tokens.
2. If estimated tokens exceed `maxDensificationInputTokens` (default `64_000`), densification is rejected early with `densificationInputTooLong`.
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
- Initial chunk budget is conservative for Apple context limits.

## Entry strategy vs adaptation strategy
- Apple is proactive at entry: it starts in chunking mode.
- Remote providers are reactive at entry: they try full-input first, then switch to chunking only after context-window failure.
- Once chunking is active, both Apple and remote providers use reactive adaptation:
  - context-window failure in chunk/merge path triggers smaller chunk budget and retry.
- So Apple effectively uses proactive entry + reactive adaptation; remote providers use reactive entry + reactive adaptation.

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
- Merge input budget: `max(320, min(chunkInputTokens, 2000))`.
- Initial budgets:
  - Apple proactive path: `1_800`.
  - Reactive fallback path: `100_000` (then reduced if needed).

### Retry strategy
- Run `densifyInChunks(...)` with current `chunkInputTokens`.
- If a context-window error occurs, halve the chunk budget and retry.
- Stop halving at minimum (`320`).
- If still failing at minimum (or if error is non-context-window), surface error.

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

### 4) Non-reducing merge guard
- If merge grouping cannot reduce count (every group size is `1`), merge loop exits and returns joined partials directly.
- This prevents infinite looping when grouping cannot progress.

## What happens when merge pass overflows?
- If a merge run throws context-window error, current implementation does **not** perform merge-only local recovery.
- Error bubbles to outer adaptive loop.
- Outer loop halves chunk budget and restarts chunk+merge from original snapshot input.
- This means successful chunk runs from the failed attempt are recomputed.

## Capture-level retry and final failure
- `CaptureWorkflow` retries densification up to `2` attempts total for provider request failures.
- If all attempts fail:
  - snapshot is persisted with `status = failed`,
  - failure message is stored.

## Example: 3-chunk snapshot
- First full-input attempt fails with context-window error (remote providers) or is skipped (Apple).
- Input is split into `C1`, `C2`, `C3`.
- Chunk densification returns `P1`, `P2`, `P3`.
- Merge pass:
  - if planner can fit all three together, one merge call returns final dense output;
  - otherwise planner may merge as groups (for example `[P1, P2]` and `[P3]`), then run another pass.
- If a merge call still overflows, adaptive loop reduces chunk budget and reruns from original input.

## Current trade-off
- Current recovery strategy is simple and robust (single adaptive control path),
- but can be more expensive because merge overflow triggers full recomputation rather than merge-local regrouping and retry.

## Known problems (agreed)
- `maxMergeInputTokens` is not truly provider/model dynamic today. Current merge budget uses a global cap (`2000`) that is conservative for large-window non-Apple providers.
- `AppleFoundationContextWindowPlanner` is a misleading name because it is used for all providers when chunking is active, not only Apple.

## Design discussion: static constants vs dynamic budgeting
- Concern: there are many fixed constants (`chunkInputTokens`, merge cap, target word limits) that do not directly reflect per-model context windows.
- If effective context window is known, budgets should be derived from:
  - context window limit (`input + output`),
  - prompt overhead token count (system + instructions + labels),
  - desired output reserve,
  - a safety margin for estimator error.
- Under that model, chunk input size, merge group budget, and output targets become computed per run rather than primarily constant-driven.
- Static values can still exist as defensive floors/ceilings, but should be safeguards around dynamic calculations, not the primary control mechanism.
