import Foundation

struct AppleFoundationContextWindowPlanner {
    private let maxChunkInputTokens: Int
    private let maxMergeInputTokens: Int
    private let minimumChunkInputTokens: Int

    init(
        maxChunkInputTokens: Int = 1800,
        maxMergeInputTokens: Int = 2000,
        minimumChunkInputTokens: Int = 320
    ) {
        self.maxChunkInputTokens = maxChunkInputTokens
        self.maxMergeInputTokens = maxMergeInputTokens
        self.minimumChunkInputTokens = minimumChunkInputTokens
    }

    func chunkInput(_ text: String) -> [String] {
        chunk(text: text, maxTokens: maxChunkInputTokens)
    }

    func mergeGroups(for partials: [String]) -> [[String]] {
        let normalized = partials
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else {
            return []
        }

        var groups: [[String]] = []
        var current: [String] = []
        var currentTokens = 0
        for partial in normalized {
            let sections = estimatedTokenCount(for: partial) <= maxMergeInputTokens
                ? [partial]
                : chunk(
                    text: partial,
                    maxTokens: max(minimumChunkInputTokens, maxMergeInputTokens / 2)
                )
            for section in sections {
                let sectionTokens = estimatedTokenCount(for: section)
                let separatorTokens = current.isEmpty ? 0 : mergeSeparatorTokens
                let candidateTokens = currentTokens + separatorTokens + sectionTokens
                if candidateTokens > maxMergeInputTokens, !current.isEmpty {
                    groups.append(current)
                    current = [section]
                    currentTokens = sectionTokens
                    continue
                }
                current.append(section)
                currentTokens = candidateTokens
            }
        }

        if !current.isEmpty {
            groups.append(current)
        }
        return groups
    }

    func estimatedTokenCount(for text: String) -> Int {
        TokenCountEstimator.estimate(for: text)
    }

    private func chunk(text: String, maxTokens: Int) -> [String] {
        let trimmed = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        let paragraphs = trimmed
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chunks: [String] = []
        var current: [String] = []
        var currentTokens = 0
        for paragraph in paragraphs {
            let sections = estimatedTokenCount(for: paragraph) <= maxTokens
                ? [paragraph]
                : splitOversizedSegment(paragraph, maxTokens: maxTokens)
            for section in sections {
                let sectionTokens = estimatedTokenCount(for: section)
                let separatorTokens = current.isEmpty ? 0 : paragraphSeparatorTokens
                let candidateTokens = currentTokens + separatorTokens + sectionTokens
                if candidateTokens > maxTokens, !current.isEmpty {
                    chunks.append(current.joined(separator: paragraphSeparator))
                    current = [section]
                    currentTokens = sectionTokens
                    continue
                }
                current.append(section)
                currentTokens = candidateTokens
            }
        }

        if !current.isEmpty {
            chunks.append(current.joined(separator: paragraphSeparator))
        }
        return chunks
    }

    private func splitOversizedSegment(_ segment: String, maxTokens: Int) -> [String] {
        let words = segment.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else {
            return splitByCharacterCount(segment, maxCharacters: max(minimumChunkInputTokens, maxTokens))
        }

        var chunks: [String] = []
        var currentWords: [String] = []
        var currentTokens = 0
        for word in words {
            let wordTokens = estimatedTokenCount(for: word)
            if wordTokens > maxTokens {
                if !currentWords.isEmpty {
                    chunks.append(currentWords.joined(separator: " "))
                    currentWords = []
                    currentTokens = 0
                }
                chunks.append(
                    contentsOf: splitByCharacterCount(
                        word,
                        maxCharacters: max(minimumChunkInputTokens, maxTokens)
                    )
                )
                continue
            }

            let separatorTokens = currentWords.isEmpty ? 0 : 1
            let candidateTokens = currentTokens + separatorTokens + wordTokens
            if candidateTokens > maxTokens, !currentWords.isEmpty {
                chunks.append(currentWords.joined(separator: " "))
                currentWords = [word]
                currentTokens = wordTokens
                continue
            }
            currentWords.append(word)
            currentTokens = candidateTokens
        }

        if !currentWords.isEmpty {
            chunks.append(currentWords.joined(separator: " "))
        }

        return chunks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func splitByCharacterCount(_ value: String, maxCharacters: Int) -> [String] {
        guard maxCharacters > 0 else {
            return [value]
        }

        var chunks: [String] = []
        var start = value.startIndex
        while start < value.endIndex {
            let end = value.index(start, offsetBy: maxCharacters, limitedBy: value.endIndex) ?? value.endIndex
            chunks.append(String(value[start ..< end]))
            start = end
        }
        return chunks
    }
}

private let paragraphSeparator = "\n\n"
private let mergeSeparator = "\n\n---\n\n"
private let latinCharactersPerToken = 3.0
private let paragraphSeparatorTokens = Int(ceil(Double(paragraphSeparator.count) / latinCharactersPerToken))
private let mergeSeparatorTokens = Int(ceil(Double(mergeSeparator.count) / latinCharactersPerToken))
