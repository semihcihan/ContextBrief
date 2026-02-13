# Context Generator V1 PRD

## Product Summary
Context Generator is a local-first macOS menu bar app that helps users capture, organize, and reuse context for LLMs and coding agents. The app captures context from desktop apps and browser tabs, enriches it with the user's own model API key, auto-links related contexts, and lets users quickly assemble reusable context packs.

## Problem
Users collect relevant information across many surfaces (desktop apps, browser tabs, docs, chats, code), but turning that into high-quality model input is slow and manual.

## Goals (V1)
- Capture context from the currently active macOS app and browser tab with low friction.
- Trigger capture from a menu bar button or global shortcut.
- Process captures with user-provided model credentials (OpenAI, Anthropic, Google).
- Automatically summarize, categorize, and link related contexts.
- Store all captured data locally with privacy-first defaults.
- Let users quickly select and copy one or more contexts for model use.

## Non-Goals (V1)
- Team collaboration, cloud sync, or hosted workspace features.
- Additional model providers beyond OpenAI, Anthropic, and Google.
- Deep manual curation workflows as a primary experience.
- Cross-platform desktop support outside macOS.

## Target Users
- Individual developers and knowledge workers using LLMs heavily.
- Users who gather context from multiple tools and want one reuse layer.

## Core User Flows
1. **Onboard**
   - Install app, launch from menu bar.
   - Complete onboarding and grant required permissions up front.
   - Add model provider and API key.
2. **Capture**
   - Press global shortcut or click menu bar action.
   - App captures current context from active desktop app or browser tab.
   - App stores raw capture and processed output locally.
3. **Auto-Enrich**
   - App summarizes, tags, and links context automatically using user model.
4. **Reuse**
   - Open menu bar panel, search/select contexts, copy formatted result.

## Functional Requirements

### 1) App Shell and Triggers
- macOS menu bar app with:
  - `Capture now`
  - `Open context library`
  - `Build context pack`
  - `Settings`
- Global keyboard shortcut for capture.
- Optional notification/toast confirming capture success/failure.

### 2) Onboarding and Permissions
- Request permissions during onboarding (not lazily):
  - Accessibility permission.
  - Screen recording permission.
- Explain why each permission is needed and what data remains local.
- Block capture actions until onboarding is complete.

### 3) Context Capture
- Capture active app/window metadata:
  - App name, window title, timestamp, capture method.
- Supported sources in V1:
  - macOS desktop apps.
  - Browser tabs (through active browser window context and screen-based fallback).
- Capture pipeline (ordered):
  1. Accessibility/text extraction when available.
  2. Screenshot capture as fallback or supplement.
  3. OCR/transcription from screenshot when needed.
- Persist both raw and normalized text outputs.

### 4) LLM Processing (User Key)
- Provider support: OpenAI, Anthropic, Google only.
- Store API key in macOS Keychain.
- For each capture, run enrichment:
  - Summary (short and detailed).
  - Category labels.
  - Entities/keywords.
  - Suggested links to existing contexts.

### 5) Automatic Linking
- Manual-only curation is not sufficient for V1.
- Auto-linking must happen by default after each processed capture.
- Linking approach:
  - Retrieve candidates from local index (metadata + semantic similarity).
  - Use LLM to score/confirm top links.
  - Save link type and confidence.
- Users can still edit links, but core value must come from automatic linking.

### 6) Local Context Library
- Local storage for:
  - Raw capture data.
  - Processed summaries/tags.
  - Links/relations.
  - Source metadata.
- Search and filter by app, date, tags, and keyword.
- Open a context to inspect and edit text/metadata.

### 7) Reuse and Export
- Multi-select contexts in library.
- Generate reusable output from selected contexts:
  - Compact prompt mode.
  - Detailed prompt mode.
- Copy output to clipboard from menu bar flow.

## Data Model (V1)
- **ContextItem**
  - `id`, `createdAt`, `updatedAt`
  - `sourceType` (`desktop_app` | `browser_tab`)
  - `appName`, `windowTitle`, `url?`
  - `captureMethod` (`accessibility` | `screenshot` | `hybrid`)
  - `rawContent`, `normalizedContent`
  - `summaryShort`, `summaryLong`
  - `categories[]`, `keywords[]`
  - `provider`, `model`
- **ContextLink**
  - `id`, `fromContextId`, `toContextId`
  - `relationType`
  - `confidence`
  - `createdAt`
- **ProviderConfig**
  - `provider` (`openai` | `anthropic` | `google`)
  - `keychainReference`
  - `defaultModel`

## Privacy and Security Requirements
- Local-first architecture with local persistence by default.
- No hosted sync/storage in V1.
- API requests only to user-selected model provider using user API key.
- API keys must never be stored in plaintext files.
- Provide clear in-product data handling disclosures.

## Performance and UX Requirements
- Capture action starts within 300ms from shortcut/button.
- User feedback appears immediately after trigger.
- Initial processed result should be available within 10s on normal network conditions.
- Search in library should feel instant for at least 10,000 contexts.

## Success Metrics (V1)
- Capture success rate >= 95%.
- Median capture-to-processed time <= 10s.
- >= 70% of captures produce at least one accepted auto-link candidate.
- Weekly active usage: users perform at least 3 capture sessions/week.
- Reuse rate: >= 50% of captured contexts are later selected for export/copy.

## Milestones
1. **M1 - App Foundation**
   - Menu bar shell, onboarding, permissions, local DB setup.
2. **M2 - Capture Engine**
   - Accessibility + screenshot capture, metadata normalization.
3. **M3 - LLM Enrichment**
   - Provider setup, summarization/categorization, keychain integration.
4. **M4 - Auto-Linking + Library**
   - Candidate retrieval, LLM link scoring, searchable library.
5. **M5 - Reuse Flow**
   - Multi-select export, prompt templates, clipboard integration.

## Open Questions for Next Iteration
- Should browser capture include a lightweight browser extension in V1.1 for higher-fidelity page extraction?
- Which embedding strategy should power candidate retrieval (provider-native embeddings vs local model)?
- What is the default global shortcut?
- What retention controls should be offered (e.g., auto-delete after N days)?
