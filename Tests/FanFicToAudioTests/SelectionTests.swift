import Foundation
import Testing
import AudiobookCore
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
