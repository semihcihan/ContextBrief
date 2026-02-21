# Provider Parallelism and Context Routing

## Why this document exists
- Define one clear concurrency model for all provider work (Apple/OpenAI/Anthropic/Gemini).
- Lock routing behavior when current context changes during snapshot processing.
- Define context title generation cadence and scheduling rules.
- Provide one implementation plan that ships all changes in a single rollout.

## Product goals
- Users should not need to manage context carefully while model work is running.
- Provider usage should be globally controlled by provider capacity, not by feature-specific limits.
- No snapshot data should be lost, even if contexts change or are deleted during processing.
- Context titles should be meaningful, stable, and generated with low overhead.

## Decisions (locked)

### 1) Provider-wide parallel work limit
- Each provider has a single max parallel work limit.
- This limit applies to all provider calls, regardless of source:
  - snapshot densification
  - snapshot title generation
  - context title generation
  - setup/health-check model calls
- Default limit is `10` for all providers.
- Per-provider overrides are supported.

### 2) Context changes reroute unfinished work
- Any change to current context reroutes unfinished snapshot processing:
  - creating a new context (which becomes current)
  - selecting/switching to another existing context
- "Unfinished" means snapshot is not yet persisted.
- Persisted snapshots are not moved automatically.
- Captures tapped after the context change use the new current context.

### 3) No data loss fallback
- If the intended context for an unfinished job is unavailable at save time:
  - save to current context if available
  - otherwise create a recovery context and save there
- Never drop snapshot data due to missing/deleted context.
- Surface a user-visible notice when fallback routing is used.

### 4) Context title cadence and timing
- Context title refresh cadence is based on successful snapshots only (`status == ready`).
- Generate context title every `X` successful snapshots.
- Defer context title generation until snapshot processing is idle.
- Coalesce repeated triggers so each threshold is generated once.

## Non-goals
- Do not move already persisted snapshots across contexts automatically.
- Do not tie provider parallel limits to feature type (densify/title/setup); limits are provider-wide.

## Configuration model

### New config keys
- `providerParallelWorkLimitDefault` (default `10`)
- `providerParallelWorkLimitApple` (optional override)
- `providerParallelWorkLimitOpenAI` (optional override)
- `providerParallelWorkLimitAnthropic` (optional override)
- `providerParallelWorkLimitGemini` (optional override)

### Resolution rule
- Effective limit for provider:
  - provider-specific override if present
  - otherwise `providerParallelWorkLimitDefault`
  - always clamp to minimum `1`

## Single rollout implementation plan

### Scope
- Introduce provider-wide concurrency control for all provider calls.
- Implement rerouting for unfinished jobs on any current context change.
- Implement successful-only, deferred context title scheduling.
- Support broader snapshot parallelization safely under the same rollout.

### Required execution order (single rollout)
1. Add provider-wide limiter foundation.
   - Add `ProviderWorkLimiter` actor.
   - Track in-flight count per provider.
   - Queue waiters per provider (FIFO).
   - Expose `acquire(provider)` and `release(provider)`.
2. Add provider parallel config plumbing.
   - Add `DevelopmentConfig.providerParallelWorkLimit(for:)`.
   - Load new plist keys.
   - Apply default and per-provider override logic.
3. Apply provider limiter to all provider request boundaries.
   - Wrap outbound model execution paths (HTTP and Apple respond call).
   - Ensure densification, title generation, and setup validation all pass through the limiter.
4. Keep densification execution under the same provider-wide limit.
   - Densification remains a single provider request per snapshot.
5. Remove old concurrency controls.
   - Remove hardcoded densification parallel constants (`6`/`3`).
   - Remove Apple-only `serializeProviderCalls` behavior.
6. Add unfinished-job reroute semantics.
   - Any current-context change reroutes unfinished snapshot jobs.
   - Persisted snapshots remain in place.
   - Captures tapped after a context change use the new current context.
7. Add no-loss save fallback.
   - If intended context is unavailable at save time, save to current context.
   - If no current context is available, create a recovery context and save there.
   - Emit user-visible feedback when fallback routing happens.
8. Add successful-only deferred context title scheduler.
   - Track per-context successful-snapshot thresholds.
   - Mark refresh due when thresholds are crossed.
   - Flush refreshes only when processing is idle.
9. Increase snapshot/retry parallelism only after steps 1-8 are in place.
10. Update tests for all above behavior.
   - Mixed workload concurrency cap by provider.
   - Config override precedence and clamping.
   - Reroute semantics on any current-context change.
   - No-loss fallback behavior.
   - Successful-only title threshold behavior.

### Successful snapshot threshold logic
- `successfulCount = snapshots(in: context).filter { $0.status == .ready }.count`
- `threshold = (successfulCount / refreshEvery) * refreshEvery`
- Generate title only if:
  - `threshold > 0`
  - `threshold > lastGeneratedThreshold`
  - processing is idle

### Acceptance criteria
- In-flight provider calls never exceed effective configured limit.
- Limit is shared across densify, titles, and setup validation calls.
- Default behavior is `10` for all providers without overrides.
- Switching current context during processing reroutes all unfinished jobs.
- Saved snapshots remain where they were saved.
- Context deletion during processing does not lose data.
- Context titles are generated every `X` successful snapshots only, deferred until idle.

## Rollout notes
- Ship as one rollout, but keep implementation in the required execution order above.
- Keep telemetry/logging around:
  - provider limiter waits/acquires/releases
  - reroute and fallback events
  - title threshold enqueue/flush behavior
