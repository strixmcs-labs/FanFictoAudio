import Foundation
import Testing
@testable import AudiobookCore

struct NextVersionTests {
    @Test func pronunciationUsesWholeWordsAndLiteralReplacement() {
        let settings = NarrationPreferences(pronunciations: [PronunciationRule(word: "SQL", spokenAs: "sequel $1"), PronunciationRule(word: "name", spokenAs: "[[rate 999]]")])
        #expect(settings.prepare("SQL sql MySQL SQLish name") == "sequel $1 sequel $1 MySQL SQLish [ [rate 999] ]")
    }

    @Test func skipsSemanticFootnotesWithoutDroppingNormalText() throws {
        let doc = try XMLDocument(xmlString: "<body xmlns:epub='http://www.idpf.org/2007/ops'><p>Story<a epub:type='noteref'>1</a> continues.</p><aside epub:type='footnote'>A footnote.</aside><p>More story.</p></body>")
        let normal = EPUBReader.readableText(doc.rootElement()!)
        let filtered = EPUBReader.readableText(doc.rootElement()!, skipFootnotes: true)
        #expect(normal.contains("A footnote."))
        #expect(filtered == "Story continues.\n\nMore story.")
        let chapter = BookChapter(id: "one", title: "One", text: normal, textWithoutFootnotes: filtered)
        #expect(NarrationPreferences(skipFootnotes: true).text(for: chapter) == filtered)
    }

    @Test func checkpointReusesOnlyMatchingSpeechAndChecksIntegrity() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let book = fixture(root.appendingPathComponent("book.epub"))
        func options(rate: Int = 200, mode: ExportMode = .single, narration: NarrationPreferences = .init()) -> ExportOptions {
            ExportOptions(voice: "Test", wordsPerMinute: rate, bitrate: 128, mode: mode, chapterIDs: ["one"], ffmpeg: URL(fileURLWithPath: "/usr/bin/true"), narration: narration)
        }
        let original = try ConversionCheckpoint(root: root, book: book, options: options())
        let source = root.appendingPathComponent("fake.flac")
        try Data("completed passage".utf8).write(to: source)
        try original.commit("c0-p0.flac", from: source, duration: 3)
        let restored = try ConversionCheckpoint(root: root, book: book, options: options(mode: .m4b))
        #expect(restored.cached("c0-p0.flac")?.duration == 3)
        #expect(try ConversionCheckpoint(root: root, book: book, options: options(rate: 300)).directory != original.directory)
        let changed = NarrationPreferences(pronunciations: [PronunciationRule(word: "Some", spokenAs: "Many")])
        #expect(try ConversionCheckpoint(root: root, book: book, options: options(narration: changed)).directory != original.directory)
        try Data("damaged".utf8).write(to: restored.directory.appendingPathComponent("c0-p0.flac"))
        #expect(restored.cached("c0-p0.flac") == nil)
        original.discardCompleted()
        #expect(!FileManager.default.fileExists(atPath: original.directory.path))
    }

    @Test func metadataHasEscapedTitlesAndMonotonicChapters() {
        let source = URL(fileURLWithPath: "/tmp/book.epub")
        let chapters = [BookChapter(id: "1", title: "One #;=\n", text: "One."), BookChapter(id: "2", title: "Two", text: "Two.")]
        let book = EPUBBook(title: "Book", author: "Author", language: "en", chapters: chapters, source: source)
        let metadata = AudiobookExporter.metadata(book: book, title: book.title, chapters: chapters, durations: [1.25, 2.5])
        #expect(metadata.contains("START=0\nEND=1250"))
        #expect(metadata.contains("START=1250\nEND=3750"))
        #expect(metadata.contains("title=One \\#\\;\\= "))
    }

    @Test func progressEstimatorIgnoresBadSamplesAndUsesActualTime() {
        var estimate = ProgressEstimator()
        #expect(estimate.remaining(characters: 1000) == nil)
        estimate.record(characters: 500, seconds: 5)
        #expect(estimate.remaining(characters: 1000) == 10)
        estimate.record(characters: 1000, seconds: .nan)
        #expect(estimate.remaining(characters: 1000) == 10)
        #expect(estimate.remaining(characters: -1) == 0)
    }

    @Test func exactSpeechRateRetainsWholeNumbersAndBoundsInvalidInput() {
        #expect(SpeechRate.normalized(617) == 617)
        #expect(SpeechRate.normalized(79) == 80)
        #expect(SpeechRate.normalized(1001) == 1000)
        #expect(SpeechRate.normalized(.nan) == 175)
        #expect(SpeechRate.normalized(.infinity) == 175)
    }

    @Test func filenamesRespectFilesystemByteLimits() {
        #expect(FileNames.safe(String(repeating: "📖", count: 100)).utf8.count <= 180)
        #expect(FileNames.safe(String(repeating: "章", count: 100)).utf8.count <= 180)
    }

    @Test func mixedDocumentDoesNotLoseBodyMatter() throws {
        let doc = try XMLDocument(xmlString: "<body xmlns:epub='http://www.idpf.org/2007/ops'><section epub:type='frontmatter'><h1>Foreword</h1></section><section epub:type='chapter bodymatter'><p>The story begins.</p></section></body>")
        #expect(!EPUBReader.isFrontMatter(doc.rootElement()!, title: "Foreword"))
        let front = try XMLDocument(xmlString: "<body xmlns:epub='http://www.idpf.org/2007/ops' epub:type='frontmatter titlepage'><p>Title</p></body>")
        #expect(EPUBReader.isFrontMatter(front.rootElement()!, title: "Title"))
    }

    @MainActor @Test func changingQueuedFormatReleasesTheOldDestination() throws {
        let queue = AudiobookQueue()
        let preset = NarrationPreset(voice: "Test", wordsPerMinute: 200, bitrate: 128, mode: .single)
        let output = URL(fileURLWithPath: "/tmp/reserved.mp3")
        queue.add([URL(fileURLWithPath: "/tmp/book.epub")], narration: preset, destination: output)
        let id = queue.jobs[0].id
        var changed = preset; changed.wordsPerMinute = 500
        queue.updateNarration(id, preset: changed)
        #expect(queue.jobs[0].output == output)
        changed.mode = .m4b
        queue.updateNarration(id, preset: changed)
        #expect(queue.jobs[0].output == nil)
        #expect(queue.jobs[0].narration?.mode == .m4b)
    }

    @Test func stalledCommandHasBoundedTimeout() async {
        let runner = ProcessRunner(cancellationGrace: 0.05, commandTimeout: 0.1)
        let started = Date()
        do { _ = try await runner.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["20"]); Issue.record("Expected timeout") }
        catch { #expect(error.localizedDescription.contains("timeout")) }
        #expect(Date().timeIntervalSince(started) < 3)
    }

    @MainActor @Test func queueSerializesJobsAndSnapshotsPresets() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let recorder = ExportRecorder()
        let queue = AudiobookQueue(reader: { fixture($0) }, exporter: { try await recorder.export($0, $1, $2, $3, $4) })
        let urls = [root.appendingPathComponent("one.epub"), root.appendingPathComponent("two.epub")]
        let preset = NarrationPreset(voice: "Saved Voice", wordsPerMinute: 600, bitrate: 96, mode: .m4b)
        #expect(queue.add(urls, narration: preset) == 2)
        #expect(queue.add(urls) == 0)
        try queue.start(settings: BatchNarrationSettings(preset: NarrationPreset(voice: "Different", wordsPerMinute: 200, bitrate: 128, mode: .single), ffmpeg: URL(fileURLWithPath: "/usr/bin/true")), folder: root)
        await queue.waitUntilFinished()
        #expect(queue.jobs.allSatisfy { $0.state == .done })
        #expect(await recorder.maximumActive == 1)
        #expect(await recorder.options.allSatisfy { $0.voice == "Saved Voice" && $0.wordsPerMinute == 600 && $0.mode == .m4b })
        #expect(Set(queue.jobs.compactMap(\.output)).count == 2)
    }

    @MainActor @Test func pausedQueueSurvivesRelaunchAndResumesInOrder() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("queue.json")
        let recorder = ExportRecorder(delayFirst: true)
        let preset = NarrationPreset(voice: "Test", wordsPerMinute: 200, bitrate: 128, mode: .single)
        let settings = BatchNarrationSettings(preset: preset, ffmpeg: URL(fileURLWithPath: "/usr/bin/true"))
        let queue = AudiobookQueue(storage: storage, checkpointRoot: root.appendingPathComponent("cache"), reader: { fixture($0) }, exporter: { try await recorder.export($0, $1, $2, $3, $4) })
        queue.add([root.appendingPathComponent("first.epub"), root.appendingPathComponent("second.epub")], narration: preset)
        try queue.start(settings: settings, folder: root)
        for _ in 0..<100 {
            if await recorder.options.count > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        queue.cancelAndPause(); await queue.waitUntilFinished()
        #expect(queue.jobs[0].state == .paused)
        #expect(queue.jobs[1].state == .queued)
        let restored = AudiobookQueue(storage: storage, checkpointRoot: root.appendingPathComponent("cache"), reader: { fixture($0) }, exporter: { try await recorder.export($0, $1, $2, $3, $4) })
        #expect(restored.jobs[0].id == queue.jobs[0].id)
        #expect(restored.jobs[0].narration?.wordsPerMinute == 200)
        try restored.start(settings: settings, folder: root)
        await restored.waitUntilFinished()
        #expect(restored.jobs.allSatisfy { $0.state == .done })
        #expect(await recorder.sources.map(\.lastPathComponent) == ["first.epub", "first.epub", "second.epub"])
    }

    @MainActor @Test func unreadableQueueIsPreservedAndBlocksStarting() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("queue.json")
        try Data("damaged original queue".utf8).write(to: storage)
        let queue = AudiobookQueue(storage: storage)
        queue.add([root.appendingPathComponent("book.epub")])
        #expect(queue.persistenceError != nil)
        #expect(throws: (any Error).self) {
            try queue.start(settings: BatchNarrationSettings(preset: NarrationPreset(voice: "Test", wordsPerMinute: 200, bitrate: 128, mode: .single), ffmpeg: URL(fileURLWithPath: "/usr/bin/true")), folder: root)
        }
        #expect(try String(contentsOf: storage, encoding: .utf8) == "damaged original queue")
    }
}

private func temporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("epub-next-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false); return root
}
private func fixture(_ url: URL) -> EPUBBook {
    EPUBBook(title: "Shared title", author: "Author", language: "en", chapters: [BookChapter(id: "one", title: "One", text: "Some words.")], source: url)
}
private actor ExportRecorder {
    var options: [ExportOptions] = []
    var sources: [URL] = []
    var active = 0
    var maximumActive = 0
    var delayFirst: Bool
    init(delayFirst: Bool = false) { self.delayFirst = delayFirst }
    func export(_ book: EPUBBook, _ option: ExportOptions, _ output: URL, _ runner: ProcessRunner, _ progress: @Sendable (ExportProgress) -> Void) async throws -> URL {
        options.append(option); sources.append(book.source); active += 1; maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        progress(ExportProgress(0.25, "Working", remainingSeconds: 10))
        if delayFirst { delayFirst = false; try await Task.sleep(for: .seconds(20)) }
        else { try await Task.sleep(for: .milliseconds(20)) }
        try runner.checkCancellation()
        try Data("audio".utf8).write(to: output, options: .withoutOverwriting)
        return output
    }
}
