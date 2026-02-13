# Context Generator V1 Decision Log

**Date:** 2026-02-13  
**Status Legend:** Accepted | Deferred | Open

## Accepted Decisions

### D-001: Product Scope Is Local-First
- **Status:** Accepted
- **Decision:** V1 stores contexts locally and does not require hosted backend storage.
- **Why:** Privacy is a top requirement and local-first reduces trust and compliance overhead.
- **Implications:** Data model and persistence must be robust locally; cloud sync is out of V1 scope.

### D-002: App Form Factor Is macOS Menu Bar
- **Status:** Accepted
- **Decision:** Primary UX is a menu bar app with quick actions.
- **Why:** Fast access and low friction for frequent capture/reuse loops.
- **Implications:** UX must optimize for compact flows and keyboard-first usage.

### D-003: Capture Is Triggered by Shortcut and Menu Bar Action
- **Status:** Accepted
- **Decision:** Users can trigger capture from a global shortcut and from menu bar UI.
- **Why:** Supports both power-user and discoverable interaction styles.
- **Implications:** Must implement global hotkey reliability and conflict handling.

### D-004: Capture Sources Include Desktop Apps and Browser Tabs
- **Status:** Accepted
- **Decision:** V1 must capture context from both macOS desktop apps and browser tabs.
- **Why:** Real workflows span native tools and web tools.
- **Implications:** Capture pipeline must handle heterogeneous sources and fidelity differences.

### D-005: Permission Requests Happen During Onboarding
- **Status:** Accepted
- **Decision:** Request required permissions up front during onboarding.
- **Why:** Permission needs are core and expected for this app category.
- **Implications:** Onboarding must clearly explain purpose and trust model for each permission.

### D-006: Capture Pipeline Uses Accessibility + Screenshot/OCR
- **Status:** Accepted
- **Decision:** Use accessibility extraction when available, with screenshot/OCR fallback or supplement.
- **Why:** Accessibility gives cleaner text when available; screenshot broadens coverage.
- **Implications:** Need robust fallback orchestration and confidence tracking by method.

### D-007: Context Session Model (No Inter-Context Linking)
- **Status:** Accepted
- **Decision:** V1 does not link contexts to each other; users capture into one selected current context.
- **Why:** Simpler and more predictable behavior for early production release.
- **Implications:** V1 must ship strong context session commands (new context, switch current, undo last capture, promote last capture to new context).

### D-008: LLM Processing Uses User API Keys for Densification
- **Status:** Accepted
- **Decision:** Capture densification (noise reduction + concise wording without losing meaningful information) uses user-provided provider keys.
- **Why:** Keeps local-first architecture while improving signal quality of captured context.
- **Implications:** Need secure key storage (Keychain), provider configuration UX, prompt contracts, and failure handling.

### D-009: Supported Providers in V1
- **Status:** Accepted
- **Decision:** Support OpenAI, Anthropic, and Google only.
- **Why:** Keeps integration scope focused while covering major provider choices.
- **Implications:** Provider abstraction should be extensible but only three adapters are required now.

### D-010: Current Context Can Be Switched to Historical Contexts
- **Status:** Accepted
- **Decision:** Users can select an older context as current and continue appending capture pieces.
- **Why:** Preserves the ability to continue ongoing workstreams without linking systems.
- **Implications:** Repository must support current-context state and piece ordering per context.

## Deferred Decisions

### D-011: Hosted Backend / Sync
- **Status:** Deferred
- **Decision:** No hosted sync/storage features in V1.
- **Why:** Out of scope for local-first launch.
- **Revisit Trigger:** Need for multi-device sync, backup, or collaboration.

## Open Decisions

### D-012: Browser Fidelity Strategy
- **Status:** Open
- **Decision Needed:** Whether to add browser extension support after V1 for higher-fidelity extraction.
- **Options:** Screen/AX only vs extension-assisted extraction.

### D-013: Default Global Shortcut
- **Status:** Open
- **Decision Needed:** What default capture shortcut should be assigned.
- **Options:** User-defined on first run vs predefined default with override.

### D-014: Context Retention Policy
- **Status:** Open
- **Decision Needed:** Default retention/deletion behavior for local context data.
- **Options:** Indefinite retention vs configurable retention windows.

## Decision Impact Summary
- V1 is explicitly optimized for **privacy + speed of capture + deterministic session workflow**.
- Engineering effort should prioritize **capture reliability** and **densification quality** over cloud features.
- Product risk concentrates around cross-app extraction quality and provider latency; these should be tracked as top launch risks.
