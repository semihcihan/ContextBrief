# V1 Release Gates

## Alpha Gate
- [x] Core module split complete (`ContextGenerator` + thin app shell).
- [x] Onboarding gate implemented for permissions + provider/API key.
- [x] Context session model implemented (current context + piece append).
- [x] Capture reliability path implemented (AX + screenshot/OCR fallback).
- [x] Local persistence for contexts and pieces implemented.

## Beta Gate
- [x] Provider adapters implemented (OpenAI, Anthropic, Google).
- [x] Keychain API key storage implemented.
- [x] Densification pipeline integrated into capture workflow.
- [x] Context library implemented for browsing and selecting current context.
- [x] Export/copy implemented for dense and raw context output.
- [x] Unit/integration test suite passing (`swift test`).

## GA Gate
- [ ] Manual QA across target apps and browsers to verify capture quality.
- [ ] Manual QA for onboarding edge-cases (revoked permissions, missing key, invalid model).
- [ ] Densification quality review against real-world contexts.
- [ ] Perf validation for capture-to-dense latency under normal network conditions.
- [ ] Privacy/disclosure copy review before production release.

## Latest Verification Snapshot
- Build: `swift build` passed.
- Tests: `swift test` passed (5 tests, 0 failures).
