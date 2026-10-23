import Foundation

/// Optional cleanup of section text before narration. The defaults read the book as written.
public struct NarrationTextOptions: Codable, Sendable, Equatable {
    public var skipAuthorNotes: Bool
    public var announceChapterTitles: Bool
    public init(skipAuthorNotes: Bool = false, announceChapterTitles: Bool = false) {
        self.skipAuthorNotes = skipAuthorNotes; self.announceChapterTitles = announceChapterTitles
    }
    public static let unchanged = NarrationTextOptions()
    public var isUnchanged: Bool { self == .unchanged }
}

public enum NarrationText {
    public static func prepare(_ chapter: BookChapter, options: NarrationTextOptions) -> String {
        var text = chapter.text
        if options.skipAuthorNotes { text = removingAuthorNotes(text) }
        if options.announceChapterTitles, !text.isEmpty { text = announcing(chapter.title, in: text) }
        return text
    }

    // A note can span several paragraphs. Only blocks this close to the start or end of a
    // section, ending at a scene break or the section end, are removed as a whole.
    static let noteBlockLimit = 8
    static let noteBlockCharacterLimit = 1500

    static func removingAuthorNotes(_ text: String) -> String {
        var paragraphs = text.components(separatedBy: "\n\n").map(removingInlineNotes).filter { !$0.isEmpty }
        func length(_ range: Range<Int>) -> Int { paragraphs[range].reduce(0) { $0 + $1.count } }
        // Leading note: it may follow a heading, and usually ends at a scene break.
        if let start = paragraphs.prefix(3).firstIndex(where: isNoteStart) {
            let window = (start + 1)..<min(paragraphs.count, start + noteBlockLimit)
            let end = window.first(where: { isSeparator(paragraphs[$0]) && length(start..<$0) <= noteBlockCharacterLimit }) ?? start
            paragraphs.removeSubrange(start...end)
        }
        // Trailing note: a marker near the end, followed by a short closing block that is
        // smaller than the story before it, so a short section is never emptied.
        let total = length(paragraphs.indices)
        if let start = paragraphs.indices.suffix(noteBlockLimit).first(where: { index in
            guard index > 0, isNoteStart(paragraphs[index]) else { return false }
            let block = length(index..<paragraphs.count)
            return block <= noteBlockCharacterLimit && block * 2 < total
        }) {
            paragraphs.removeSubrange(start...)
        }
        paragraphs.removeAll(where: isNoteStart)
        while let first = paragraphs.first, isSeparator(first) { paragraphs.removeFirst() }
        while let last = paragraphs.last, isSeparator(last) { paragraphs.removeLast() }
        return paragraphs.joined(separator: "\n\n")
    }

    static func announcing(_ title: String, in text: String) -> String {
        let spokenTitle = EPUBReader.normalized(title)
        let heading = text.components(separatedBy: "\n\n").first ?? ""
        let headingKey = key(heading), titleKey = key(spokenTitle)
        // Most fanfic EPUBs already open each section with its heading; never read it twice.
        guard !titleKey.isEmpty, !headingKey.hasPrefix(titleKey),
              !(heading.count <= 200 && !headingKey.isEmpty && titleKey.hasPrefix(headingKey)) else { return text }
        let ending = spokenTitle.last.map { ".!?…:".contains($0) } ?? false
        return spokenTitle + (ending ? "" : ".") + "\n\n" + text
    }

    static func isNoteStart(_ paragraph: String) -> Bool {
        paragraph.range(of: notePattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func isSeparator(_ paragraph: String) -> Bool {
        let trimmed = paragraph.trimmingCharacters(in: .whitespaces)
        return trimmed.range(of: #"^[^\p{L}\p{N}]{3,}$|^(?:oO|Oo|xX|Xx)+[oOxX]?$"#, options: .regularExpression) != nil
            || trimmed.range(of: #"^(?:line|page|scene) ?break$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func removingInlineNotes(_ paragraph: String) -> String {
        paragraph.replacingOccurrences(of: #"\s*[\(\[]\s*(?:A\s?/\s?N\b|AN\s*:|Authors?['’]?s?\s+Notes?\b)[^\)\]]*[\)\]]"#,
                                       with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
    }

    private static func key(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    // Markers that open author, translator, or archive notes, after optional decoration
    // such as "**", "(", or "~". "AN" and "Notes" need a colon to avoid ordinary prose.
    private static let notePattern = #"^[\s\*\(\[\{~_=#>•\-–—]*(?:A\s?/\s?N\b|A\.\s?N\.|AN\s*:|T\s?/\s?N\b|Authors?['’]?s?\s+Notes?\b|Note\s+from\s+the\s+author\b|Translator['’]?s?\s+Notes?\b|Disclaimer\b|(?:Chapter\s+)?(?:End\s+)?Notes?\s*:|Chapter\s+(?:End\s+)?Notes\b|See\s+the\s+end\s+of\s+the\s+chapter\s+for\b)"#
}

extension EPUBBook {
    /// The book as it will be narrated. Sections left with no text are omitted.
    public func narrated(_ options: NarrationTextOptions) -> EPUBBook {
        guard !options.isUnchanged else { return self }
        let prepared = chapters.compactMap { chapter -> BookChapter? in
            let text = NarrationText.prepare(chapter, options: options)
            if text == chapter.text { return chapter }
            return text.isEmpty ? nil : BookChapter(id: chapter.id, title: chapter.title, text: text, includedByDefault: chapter.includedByDefault)
        }
        return EPUBBook(title: title, author: author, language: language, chapters: prepared, source: source, warnings: warnings, cover: cover)
    }
}
