# Densification prompt (Remote Config)

The common prompt used for densification (UI/OCR → dense text) can be overridden via Firebase Remote Config. If not set remotely, the app uses the in-code default so you do not need to copy it in the Firebase console.

## Behavior

- **Default**: `ProviderTextRequest.defaultCommonPrompt` in `ProviderClient.swift` is used at launch and whenever Remote Config has not returned a valid value.
- **Override**: Firebase Remote Config parameter `densificationCommonPrompt` (string; key matches the property name via `#function`) must be a JSON array of strings, e.g. `["Line 1","Line 2"]`. After fetch and activate, that array is used for all new densification requests.
- **Provider**: The app sets `ProviderTextRequest.commonPromptProvider` at startup so the library reads the current prompt (default or remote) without depending on Firebase.

## Firebase console

1. In Firebase → Remote Config, add a parameter with key `densificationCommonPrompt`.
2. Value: JSON array of prompt lines, e.g. the same structure as the in-code default (each bullet block as one string element).
3. Optional: set a default value in the console; the app still falls back to the in-code default if the parameter is missing or invalid.

## Code

- **Library**: `Sources/ContextGenerator/Providers/ProviderClient.swift` — `defaultCommonPrompt`, `commonPromptProvider`, and `commonPrompt` (resolved at request time).
- **App**: `Sources/ContextGeneratorApp/App/RemoteConfiguration.swift` — centralized remote config in the same style as the WhatBeatsRock example: `ConfigDefaults` (class, Codable) holds in-code defaults; `RemoteConfiguration` subclasses `ConfigDefaults`, overrides properties to read from `remoteConfig.configValue(forKey: #function)` with fallback to `currentValues`; `setDefaults(from: currentValues)` and fetch/activate/update listener in init; `main.swift` touches `RemoteConfiguration.shared` after Firebase is configured.
