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

### D-007: Automatic Linking Is Required in V1
- **Status:** Accepted
- **Decision:** Auto-linking cannot be optional/manual-only in V1.
- **Why:** Manual curation alone is not acceptable for desired user experience.
- **Implications:** Must ship reliable enrichment/linking flow in initial version, not as later add-on.

### D-008: LLM Processing Uses User API Keys
- **Status:** Accepted
- **Decision:** Summarization, categorization, and linking use user-provided provider keys.
- **Why:** Enables immediate customization and avoids hosted-inference complexity in V1.
- **Implications:** Need secure key storage (Keychain), provider configuration UX, and failure handling.

### D-009: Supported Providers in V1
- **Status:** Accepted
- **Decision:** Support OpenAI, Anthropic, and Google only.
- **Why:** Keeps integration scope focused while covering major provider choices.
- **Implications:** Provider abstraction should be extensible but only three adapters are required now.

## Deferred Decisions

### D-010: Hosted Backend / Sync
- **Status:** Deferred
- **Decision:** No hosted sync/storage features in V1.
- **Why:** Out of scope for local-first launch.
- **Revisit Trigger:** Need for multi-device sync, backup, or collaboration.

## Open Decisions

### D-011: Browser Fidelity Strategy
- **Status:** Open
- **Decision Needed:** Whether to add browser extension support after V1 for higher-fidelity extraction.
- **Options:** Screen/AX only vs extension-assisted extraction.

### D-012: Similarity Retrieval Implementation
- **Status:** Open
- **Decision Needed:** How to rank candidate links before LLM verification.
- **Options:** Provider embeddings vs lightweight local embeddings.

### D-013: Context Retention Policy
- **Status:** Open
- **Decision Needed:** Default retention/deletion behavior for local context data.
- **Options:** Indefinite retention vs configurable retention windows.

## Decision Impact Summary
- V1 is explicitly optimized for **privacy + speed of capture + automatic organization**.
- Engineering effort should prioritize **capture reliability** and **auto-link quality** over cloud features.
- Product risk concentrates around cross-app extraction quality and provider latency; these should be tracked as top launch risks.
