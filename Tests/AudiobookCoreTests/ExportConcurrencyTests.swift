import Foundation
import AVFoundation
import Testing
@testable import AudiobookCore

struct ExportConcurrencyTests {
    @Test func aiRequestsOverlapButAudioStaysInReadingOrder() async throws {
        let ffmpeg = try #require(SpeechTools.findFFmpeg())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("concurrency-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        // Section n returns n tenths of a second of audio, and later sections answer first.
        var clips: [Int: Data] = [:]
        for n in 1...6 { clips[n] = try tone(root, tenths: n) }
        let audio = clips
        let tracker = ActiveRequests()
        let client = APISpeechClient(transport: { request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            let n = Int((body?["input"] as? String ?? "").filter(\.isNumber)) ?? 0
            await tracker.begin()
            try await Task.sleep(for: .milliseconds(30 * (7 - n)))
            await tracker.end()
            return (audio[n] ?? Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let book = EPUBBook(title: "Order", author: "Test", language: "en", chapters: (1...6).map {
            BookChapter(id: "\($0)", title: "Section \($0)", text: "Section \($0).")
        }, source: root.appendingPathComponent("book.epub"))
        let options = ExportOptions(voice: "", wordsPerMinute: 175, bitrate: 128, mode: .m4b, chapterIDs: Set((1...6).map(String.init)), ffmpeg: ffmpeg,
            api: APINarration(provider: .openAI, model: "test-model", voice: "testVoice", apiKey: "test-key"))
        let destination = root.appendingPathComponent("book.m4b")
        _ = try await AudiobookExporter.export(book: book, options: options, destination: destination, apiClient: client)
        #expect(await tracker.maximum == NarrationProvider.openAI.concurrentRequests)
        let ffprobe = ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
        let result = try await ProcessRunner().run(ffprobe, arguments: ["-v", "error", "-show_chapters", "-of", "json", destination.path])
        let info = try #require(JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any])
        let chapters = try #require(info["chapters"] as? [[String: Any]])
        let durations = chapters.compactMap { chapter -> Double? in
            guard let start = Double(chapter["start_time"] as? String ?? ""), let end = Double(chapter["end_time"] as? String ?? "") else { return nil }
            return end - start
        }
        #expect(durations.count == 6)
        // Each section is 0.1 s longer than the last, plus the same closing pause.
        for (index, duration) in durations.enumerated() {
            #expect(abs(duration - (0.7 + 0.1 * Double(index + 1))) < 0.08, "Section \(index + 1) lasted \(duration) s")
        }
        #expect(NarrationProvider.elevenLabs.concurrentRequests == 2)
    }

    @Test func passagesReturnedBeforeAnEarlierFailureAreKeptForRetry() async throws {
        let ffmpeg = try #require(SpeechTools.findFFmpeg())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("concurrency-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let clip = try tone(root, tenths: 1)
        let sent = SentTexts()
        func client(failFirst: Bool) -> APISpeechClient {
            APISpeechClient(transport: { request in
                let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
                let text = body?["input"] as? String ?? ""
                await sent.record(text)
                if failFirst && text == "Section 1." {
                    // Fail only after the later sections have answered.
                    try await Task.sleep(for: .milliseconds(150))
                    throw AudiobookError.conversion("Synthetic interruption")
                }
                return (clip, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
        }
        let book = EPUBBook(title: "Retry", author: "Test", language: "en", chapters: (1...3).map {
            BookChapter(id: "\($0)", title: "Section \($0)", text: "Section \($0).")
        }, source: root.appendingPathComponent("book.epub"))
        let options = ExportOptions(voice: "", wordsPerMinute: 175, bitrate: 128, mode: .single, chapterIDs: ["1", "2", "3"], ffmpeg: ffmpeg,
            api: APINarration(provider: .openAI, model: "test-model", voice: "testVoice", apiKey: "test-key"),
            checkpoint: root.appendingPathComponent("checkpoint"))
        let destination = root.appendingPathComponent("book.mp3")
        await #expect(throws: AudiobookError.self) {
            try await AudiobookExporter.export(book: book, options: options, destination: destination, apiClient: client(failFirst: true))
        }
        #expect(Set(await sent.texts) == ["Section 1.", "Section 2.", "Section 3."])
        await sent.reset()
        _ = try await AudiobookExporter.export(book: book, options: options, destination: destination, apiClient: client(failFirst: false))
        #expect(await sent.texts == ["Section 1."])
    }

    private func tone(_ root: URL, tenths: Int) throws -> Data {
        let url = root.appendingPathComponent("tone-\(tenths).wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        let frames = AVAudioFrameCount(2400 * tenths)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for index in 0..<Int(frames) { buffer.floatChannelData![0][index] = sin(Float(index) * 0.12) * 0.3 }
        do { let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer) }
        return try Data(contentsOf: url)
    }
}

private actor SentTexts {
    var texts: [String] = []
    func record(_ text: String) { texts.append(text) }
    func reset() { texts = [] }
}

private actor ActiveRequests {
    var active = 0, maximum = 0
    func begin() { active += 1; maximum = max(maximum, active) }
    func end() { active -= 1 }
}
