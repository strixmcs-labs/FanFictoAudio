import Foundation
import Testing
@testable import AudiobookCore

struct NarrationTextTests {
    private let skip = NarrationTextOptions(skipAuthorNotes: true)
    private let titles = NarrationTextOptions(announceChapterTitles: true)

    @Test func leadingNoteBlockIsRemovedThroughTheSceneBreak() {
        let text = paragraphs("Chapter 3: The Lake", "A/N: Thanks for all the reviews!", "This one took a while.", "* * *", "The water was cold.", "She kept swimming.")
        #expect(prepare(text, skip) == paragraphs("Chapter 3: The Lake", "The water was cold.", "She kept swimming."))
    }

    @Test func noteWithoutANearbyBreakRemovesOnlyItsParagraph() {
        let text = paragraphs("**Author's Note:** Short one today.", "The water was cold.", "She kept swimming.")
        #expect(prepare(text, skip) == paragraphs("The water was cold.", "She kept swimming."))
    }

    @Test func shortTrailingNoteIsRemovedToTheEnd() {
        let text = paragraphs("The water was cold.", "She kept swimming.", "oOo", "AN: Please review!", "See you next week.")
        #expect(prepare(text, skip) == paragraphs("The water was cold.", "She kept swimming."))
        // A marker followed by a long passage only loses the marker paragraph.
        let story = Array(repeating: "She kept swimming toward the far shore.", count: 80).joined(separator: " ")
        let long = paragraphs("The water was cold.", "Disclaimer: I own nothing.", story)
        #expect(prepare(long, skip) == paragraphs("The water was cold.", story))
    }

    @Test func shortSectionsKeepTheirStory() {
        let text = paragraphs("A/N: Quick one.", "The water was cold.", "She kept swimming.", "Then she rested.")
        #expect(prepare(text, skip) == paragraphs("The water was cold.", "She kept swimming.", "Then she rested."))
        // A scene break far into a long story is not mistaken for the end of a leading note.
        let story = Array(repeating: "She kept swimming toward the far shore.", count: 30).joined(separator: " ")
        let long = paragraphs("A/N: Quick one.", story, story, "***", "Later that day.")
        #expect(prepare(long, skip) == paragraphs(story, story, "***", "Later that day."))
    }

    @Test func inlineAsidesAndArchiveNotesAreRemoved() {
        let text = paragraphs("Notes:", "(See the end of the chapter for more notes.)", "See the end of the chapter for more notes.",
                              "The water (A/N: it was January) was cold.", "Chapter End Notes", "Thanks!")
        #expect(prepare(text, skip) == "The water was cold.")
    }

    @Test func ordinaryProseIsKept() {
        let text = paragraphs("An apple fell.", "Notes from the meeting were lost.", "Note the date.", "Authority noted nothing.", "Disclaimers were everywhere.", "Ooo, she said.")
        #expect(prepare(text, skip) == text)
    }

    @Test func sectionsThatAreOnlyNotesAreDroppedFromTheNarratedBook() {
        let book = EPUBBook(title: "T", author: "A", language: "en", chapters: [
            BookChapter(id: "1", title: "Hiatus", text: "A/N: This story is on hiatus."),
            BookChapter(id: "2", title: "One", text: "The water was cold.")
        ], source: URL(fileURLWithPath: "/tmp/book.epub"))
        #expect(book.narrated(skip).chapters.map(\.id) == ["2"])
        #expect(book.narrated(.unchanged).chapters.map(\.id) == ["1", "2"])
    }

    @Test func titlesAreAnnouncedOnlyWhenMissing() {
        #expect(prepare("The water was cold.", titles, title: "Chapter 3: The Lake") == paragraphs("Chapter 3: The Lake.", "The water was cold."))
        #expect(prepare("The water was cold.", titles, title: "Is it over?") == paragraphs("Is it over?", "The water was cold."))
        let headed = paragraphs("Chapter 3: The Lake", "The water was cold.")
        #expect(prepare(headed, titles, title: "Chapter 3: The Lake") == headed)
        #expect(prepare(headed, titles, title: "Chapter 3") == headed)
        #expect(prepare(paragraphs("Chapter 3", "The water was cold."), titles, title: "Chapter 3 - The Lake") == paragraphs("Chapter 3", "The water was cold."))
        // Notes are removed before deciding, so the title follows a removed leading note.
        let both = NarrationTextOptions(skipAuthorNotes: true, announceChapterTitles: true)
        #expect(prepare(paragraphs("A/N: Hi!", "The water was cold."), both, title: "The Lake") == paragraphs("The Lake.", "The water was cold."))
    }

    @Test func pronunciationsReplaceWholeWordsLongestFirst() {
        let options = NarrationTextOptions(pronunciations: [
            Pronunciation(word: "Hermione", sayAs: "Her-my-oh-nee"), Pronunciation(word: "Hermione Granger", sayAs: "Her-my-oh-nee Grain-jer"),
            Pronunciation(word: "Sirius", sayAs: ""), Pronunciation(word: "$5", sayAs: "five dollars")])
        #expect(options.pronunciations.count == 3)
        #expect(prepare("HERMIONE GRANGER smiled. Hermione's wand. Hermionely.", options) == "Her-my-oh-nee Grain-jer smiled. Her-my-oh-nee's wand. Hermionely.")
        // Incomplete rows are ignored instead of deleting the word; patterns and templates are literal.
        #expect(prepare("Sirius paid $5.", options) == "Sirius paid five dollars.")
        let withTitle = NarrationTextOptions(announceChapterTitles: true, pronunciations: [Pronunciation(word: "Hermione", sayAs: "Her-my-oh-nee")])
        #expect(prepare("Text.", withTitle, title: "Hermione") == paragraphs("Her-my-oh-nee.", "Text."))
    }

    @Test func savedTextOptionsDecodeMissingFieldsAsDefaults() throws {
        let older = try JSONDecoder().decode(NarrationTextOptions.self, from: Data(#"{"skipAuthorNotes":true,"announceChapterTitles":false}"#.utf8))
        #expect(older == NarrationTextOptions(skipAuthorNotes: true))
        let preset = NarrationPreset(voice: "Ava", wordsPerMinute: 175, bitrate: 128, mode: .single, api: nil, text: older)
        #expect(preset.isEquivalent(to: NarrationPreset(voice: "Ava", wordsPerMinute: 175, bitrate: 128, mode: .single, api: nil, text: older)))
        #expect(!preset.isEquivalent(to: NarrationPreset(voice: "Ava", wordsPerMinute: 175, bitrate: 128, mode: .single, api: nil)))
        // Settings unused by a provider don't count as differences.
        let api = APINarration(provider: .elevenLabs, model: "m", voice: "v", apiKey: "")
        #expect(NarrationPreset(voice: "Ava", wordsPerMinute: 175, bitrate: 128, mode: .m4b, api: api)
            .isEquivalent(to: NarrationPreset(voice: "Zoe", wordsPerMinute: 300, bitrate: 128, mode: .m4b, api: api)))
    }

    @Test func customTitlesApplyByIDWithoutChangingText() {
        let book = EPUBBook(title: "T", author: "A", language: "en", chapters: [
            BookChapter(id: "1", title: "Ch 1 (UPDATED)", text: "The water was cold."), BookChapter(id: "2", title: "Two", text: "Words.")
        ], source: URL(fileURLWithPath: "/tmp/book.epub"))
        let renamed = book.retitled(["1": "  The   Lake ", "2": "   ", "missing": "X"])
        #expect(renamed.chapters.map(\.title) == ["The Lake", "Two"])
        #expect(renamed.chapters[0].wordCount == 4 && renamed.chapters[0].text == "The water was cold.")
        #expect(book.retitled(nil).chapters.map(\.title) == ["Ch 1 (UPDATED)", "Two"])
    }

    @Test func presetsSavedBeforeTextOptionsStillDecodeAndUnchangedTextIsOmitted() throws {
        let unchanged = NarrationPreset(voice: "Ava", wordsPerMinute: 175, bitrate: 128, mode: .single, api: nil)
        let encoded = try JSONEncoder().encode(unchanged)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("\"text\""))
        let decoded = try JSONDecoder().decode(NarrationPreset.self, from: encoded)
        #expect(decoded.textOptions == .unchanged)
        let custom = NarrationPreset(voice: "Ava", wordsPerMinute: 175, bitrate: 128, mode: .single, api: nil, text: skip)
        #expect(try JSONDecoder().decode(NarrationPreset.self, from: JSONEncoder().encode(custom)).textOptions == skip)
    }

    @Test func exportRejectsSelectionsWithOnlyNotes() async throws {
        let book = EPUBBook(title: "T", author: "A", language: "en", chapters: [BookChapter(id: "1", title: "Hiatus", text: "A/N: On hiatus.")],
                            source: URL(fileURLWithPath: "/tmp/book.epub"))
        let options = ExportOptions(voice: "Ava", wordsPerMinute: 175, bitrate: 128, mode: .single, chapterIDs: ["1"],
                                    ffmpeg: URL(fileURLWithPath: "/usr/bin/true"), text: skip)
        await #expect(throws: AudiobookError.self) {
            try await AudiobookExporter.export(book: book, options: options, destination: URL(fileURLWithPath: "/tmp/never-written.mp3"))
        }
    }

    private func paragraphs(_ items: String...) -> String { items.joined(separator: "\n\n") }
    private func prepare(_ text: String, _ options: NarrationTextOptions, title: String = "Untitled") -> String {
        NarrationText.prepare(BookChapter(id: "1", title: title, text: text), options: options)
    }
}
