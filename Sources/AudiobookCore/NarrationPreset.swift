import Foundation

public struct PronunciationRule: Codable, Sendable, Identifiable, Equatable {
    public var id = UUID()
    public var word: String
    public var spokenAs: String
    public init(word: String, spokenAs: String) { self.word = word; self.spokenAs = spokenAs }
}

public struct NarrationPreferences: Codable, Sendable, Equatable {
    public var chapterPause: Double
    public var skipFrontMatter: Bool
    public var skipFootnotes: Bool
    public var pronunciations: [PronunciationRule]
    public init(chapterPause: Double = 0.7, skipFrontMatter: Bool = false, skipFootnotes: Bool = false, pronunciations: [PronunciationRule] = []) {
        self.chapterPause = chapterPause; self.skipFrontMatter = skipFrontMatter
        self.skipFootnotes = skipFootnotes; self.pronunciations = pronunciations
    }
    public func text(for chapter: BookChapter) -> String {
        prepare(skipFootnotes ? chapter.textWithoutFootnotes ?? chapter.text : chapter.text)
    }
    public func prepare(_ text: String) -> String {
        var result = text
        for rule in pronunciations where !rule.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !rule.spokenAs.isEmpty {
            let pattern = #"(?<![\p{L}\p{N}_])"# + NSRegularExpression.escapedPattern(for: rule.word) + #"(?![\p{L}\p{N}_])"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result),
                    withTemplate: NSRegularExpression.escapedTemplate(for: rule.spokenAs))
            }
        }
        return result.replacingOccurrences(of: "[[", with: "[ [").replacingOccurrences(of: "]]", with: "] ]")
    }
}

public struct NarrationPreset: Codable, Sendable, Identifiable {
    public var id = UUID()
    public var name: String
    public var voice: String
    public var wordsPerMinute: Int
    public var bitrate: Int
    public var mode: ExportMode
    public var narration: NarrationPreferences
    public init(name: String = "Current settings", voice: String, wordsPerMinute: Int, bitrate: Int, mode: ExportMode, narration: NarrationPreferences = .init()) {
        self.name = name; self.voice = voice; self.wordsPerMinute = wordsPerMinute
        self.bitrate = bitrate; self.mode = mode; self.narration = narration
    }
}

public struct ProgressEstimator {
    private var characters = 0
    private var seconds = 0.0
    public init() {}
    public mutating func record(characters count: Int, seconds elapsed: Double) {
        guard count > 0, elapsed.isFinite, elapsed > 0 else { return }
        characters += count; seconds += elapsed
    }
    public func remaining(characters count: Int) -> Double? {
        guard characters > 0, seconds >= 0.2 else { return nil }
        return max(0, Double(count) * seconds / Double(characters))
    }
}
