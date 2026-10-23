import Foundation
import Testing
import AudiobookCore
import DownloadCore
@testable import FanFicToAudio

@MainActor struct SelectionTests {
    @Test func missingRestoredEPUBDoesNotBlockDownloadScreen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let queue = AudiobookQueue(storage: root.appendingPathComponent("queue.json"))
        queue.add([root.appendingPathComponent("moved.epub")])
        queue.rememberSelection(queue.jobs[0].id)
        let model = AppModel(storageRoot: root)
        for _ in 0..<100 {
            if !model.isLoading { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.stage == 0)
        #expect(model.errorMessage == nil)
        #expect(model.status.contains("unavailable"))
        #expect(model.audiobookQueue.jobs.count == 1)
        await model.shutdown()
    }

    @Test func exactWPMInputIsFiniteBoundedAndDoesNotRecurse() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let previous = UserDefaults.standard.object(forKey: "speakingRate")
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: "speakingRate") }
            else { UserDefaults.standard.removeObject(forKey: "speakingRate") }
            try? FileManager.default.removeItem(at: root)
        }
        let model = AppModel(storageRoot: root)
        model.rate = 617; #expect(model.rate == 617)
        model.rate = 1200; #expect(model.rate == 1000)
        model.rate = 1; #expect(model.rate == 80)
        model.rate = .nan; #expect(model.rate == 175)
        await model.shutdown()
    }

    @Test func queueSelectionCannotChangeDuringIndividualExportOrDownload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(storageRoot: root)
        let first = root.appendingPathComponent("first.epub")
        let second = root.appendingPathComponent("second.epub")
        model.audiobookQueue.add([first, second])
        let firstID = model.audiobookQueue.jobs[0].id
        let secondID = model.audiobookQueue.jobs[1].id
        model.selectedQueueJob = firstID
        model.book = EPUBBook(title: "First", author: "", language: "en", chapters: [], source: first)
        model.isExporting = true
        #expect(!model.canSelectQueue)
        model.selectedQueueJob = secondID
        #expect(model.selectedQueueJob == firstID)
        #expect(model.book?.source == first)
        model.isExporting = false; model.downloadInProgress = true
        model.selectedQueueJob = secondID
        #expect(model.selectedQueueJob == firstID)
        model.downloadInProgress = false
        #expect(model.canSelectQueue)
        model.selectedQueueJob = secondID
        #expect(model.selectedQueueJob == secondID)
        await model.shutdown()
    }
}

@MainActor struct WorkspaceTests {
    @Test func renamingUsesCustomTitlesAndRestoresOriginals() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(storageRoot: root)
        model.book = EPUBBook(title: "Book", author: "", language: "en", chapters: [
            BookChapter(id: "1", title: "Ch 1", text: "One two."), BookChapter(id: "2", title: "Ch 2", text: "Three.")
        ], source: root.appendingPathComponent("book.epub"))
        model.chapterOrder = ["2", "1"]
        model.renameChapter("1", to: "  The   Lake ")
        #expect(model.orderedChapters.map(\.title) == ["Ch 2", "The Lake"])
        #expect(model.customChapterTitles == ["1": "The Lake"])
        model.renameChapter("1", to: "Ch 1")
        #expect(model.customChapterTitles == nil)
        model.renameChapter("2", to: "Shore"); model.renameChapter("2", to: "")
        #expect(model.chapterTitles.isEmpty)
        await model.shutdown()
    }

    @Test func severalOpenedEPUBsJoinTheQueue() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(storageRoot: root)
        model.openFiles([root.appendingPathComponent("a.epub"), root.appendingPathComponent("b.EPUB"), root.appendingPathComponent("notes.txt")])
        #expect(model.audiobookQueue.jobs.map(\.source.lastPathComponent) == ["a.epub", "b.EPUB"])
        #expect(model.pane == .queue && model.stage == 1)
        await model.shutdown()
    }

    @Test func downloadListIsRestoredAndInterruptedJobsWait() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("downloads.json")
        let first = DownloadModel(storage: storage)
        first.jobs = [StoryJob(request: DownloadRequest(source: "https://example.com/s/1", output: root.path), title: "Running", state: .running, progress: 40),
                      StoryJob(request: DownloadRequest(source: "https://example.com/s/2", output: root.path), title: "Done", state: .done)]
        let restored = DownloadModel(storage: storage)
        #expect(restored.jobs.map(\.title) == ["Running", "Done"])
        #expect(restored.jobs.map(\.state) == [.queued, .done])
        #expect(restored.jobs[0].progress == nil && restored.hasQueued)
        #expect(restored.jobs.map(\.id) == first.jobs.map(\.id))
    }
}
