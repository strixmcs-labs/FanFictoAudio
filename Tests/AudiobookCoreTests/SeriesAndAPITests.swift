import Foundation
import AVFAudio
import Testing
@testable import AudiobookCore

struct SeriesAndAPITests {
    @Test func mergePreservesBookOrderResourcesLabelsAndOptionalSections() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let first = try fixture(root, name: "first.epub", title: "First & Book", text: "First story.")
        let second = try fixture(root, name: "second.epub", title: "Second Book", text: "Second story.")
        let originals = try [first, second].map { try Data(contentsOf: $0) }
        let destination = root.appendingPathComponent("series.epub")
        let combined = try EPUBMerger.combine([second, first], title: "Series & Friends", destination: destination)
        #expect(combined.title == "Series & Friends")
        #expect(combined.chapters.map(\.title) == ["Second Book", "Chapter Label", "Contents", "First & Book", "Chapter Label", "Contents"])
        #expect(combined.chapters.map(\.includedByDefault) == [true, true, false, true, true, false])
        #expect(combined.chapters[1].text.contains("Second story."))
        #expect(combined.chapters[4].text.contains("First story."))
        #expect(try [first, second].map { try Data(contentsOf: $0) } == originals)
        let archive = try ZIPArchive(url: destination)
        #expect(try archive.read("EPUB/books/1/OPS/style.css") == Data("p {color: blue}".utf8))
        #expect(try archive.read("EPUB/books/2/OPS/picture.png") == Data([1, 2, 3, 4]))
        #expect(try archive.read("EPUB/books/1/OPS/chapter.xhtml").contains(Data("href=\"style.css\"".utf8)))
        #expect(archive.entries["mimetype"]?.method == 0)
        #expect(archive.entries["EPUB/package.opf"]?.method == 8)
        let before = try Data(contentsOf: destination)
        #expect(throws: (any Error).self) { try EPUBMerger.combine([first, second], title: "Again", destination: destination) }
        #expect(try Data(contentsOf: destination) == before)
        let bad = root.appendingPathComponent("bad.epub"); try Data("bad".utf8).write(to: bad)
        #expect(throws: (any Error).self) { try EPUBMerger.combine([first, bad], title: "Broken", destination: root.appendingPathComponent("broken.epub")) }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("broken.epub").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".series-") })
    }

    @Test func libraryInvalidatesWhenEPUBChanges() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let source = try fixture(root, name: "book.epub", title: "Before", text: "Old content.")
        let library = EPUBLibrary()
        #expect(try await library.read(source).title == "Before")
        #expect(try await library.read(source).title == "Before")
        _ = try fixture(root, name: "book.epub", title: "After editing", text: "New longer content.")
        #expect(try await library.read(source).title == "After editing")
    }

    @Test func providerRequestsUseCorrectEndpointsFormatsAndCredentials() throws {
        let client = APISpeechClient()
        let open = try client.speechRequest(text: "A short sample.", settings: settings(.openAI))
        #expect(open.url?.absoluteString == "https://api.openai.com/v1/audio/speech")
        #expect(open.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        let bodyData = try #require(open.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(body["input"] as? String == "A short sample.")
        #expect(body["response_format"] as? String == "wav")
        #expect(body["speed"] as? Double == 1)
        let eleven = try client.speechRequest(text: "Another sample.", settings: settings(.elevenLabs))
        #expect(eleven.url?.path == "/v1/text-to-speech/voice123")
        #expect(eleven.url?.query == "output_format=mp3_44100_128")
        #expect(eleven.value(forHTTPHeaderField: "xi-api-key") == "test-key")
        #expect(eleven.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(throws: (any Error).self) { try client.speechRequest(text: String(repeating: "x", count: 1501), settings: settings(.openAI)) }
        #expect(throws: (any Error).self) { try client.speechRequest(text: "sample", settings: APINarration(provider: .elevenLabs, model: "test", voice: "../bad", speed: 2, apiKey: "test")) }
    }

    @Test func openRouterRequestsSendMP3AndOnlyNonDefaultOptions() throws {
        let client = APISpeechClient()
        let router = try client.speechRequest(text: "A short sample.", settings: settings(.openRouter))
        #expect(router.url?.absoluteString == "https://openrouter.ai/api/v1/audio/speech")
        #expect(router.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        let routerData = try #require(router.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: routerData) as? [String: Any])
        #expect(body["model"] as? String == "hexgrad/kokoro-82m")
        #expect(body["voice"] as? String == "af_heart")
        #expect(body["response_format"] as? String == "mp3")
        #expect(body["speed"] == nil && body["instructions"] == nil)
        let styled = APINarration(provider: .openRouter, model: "microsoft/mai-voice-2", voice: "en-US-Harper:MAI-Voice-2",
                                  speed: 1.25, instructions: "Warm", apiKey: "test-key")
        let styledData = try #require(try client.speechRequest(text: "Sample.", settings: styled).httpBody)
        let styledBody = try #require(JSONSerialization.jsonObject(with: styledData) as? [String: Any])
        #expect(styledBody["speed"] == nil)
        #expect(styledBody["instructions"] as? String == "Warm")
        #expect(throws: (any Error).self) { try client.speechRequest(text: String(repeating: "é", count: 1100), settings: settings(.openRouter)) }
        #expect(throws: (any Error).self) { try client.speechRequest(text: "sample", settings: APINarration(provider: .openRouter, model: "m", voice: "a/b", apiKey: "k")) }
        #expect(throws: (any Error).self) { try client.speechRequest(text: "sample", settings: APINarration(provider: .openRouter, model: "m", voice: "v", speed: 6.5, apiKey: "k")) }
    }

    @Test func speedsBeyondProviderLimitsAreSentAtTheLimitAndAppliedLocally() throws {
        let client = APISpeechClient()
        func sent(_ provider: NarrationProvider, _ speed: Double) throws -> (body: [String: Any], tempo: Double) {
            let base = settings(provider)
            let narration = APINarration(provider: provider, model: base.model, voice: base.voice, speed: speed, apiKey: "test-key")
            let data = try #require(try client.speechRequest(text: "Sample.", settings: narration).httpBody)
            return (try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]), narration.tempo)
        }
        let openAI = try sent(.openAI, 6)
        #expect(openAI.body["speed"] as? Double == 4 && openAI.tempo == 1.5)
        let native = try sent(.openAI, 2)
        #expect(native.body["speed"] as? Double == 2 && native.tempo == 1)
        let eleven = try sent(.elevenLabs, 3)
        #expect((eleven.body["voice_settings"] as? [String: Any])?["speed"] as? Double == 1.2 && abs(eleven.tempo - 2.5) < 1e-9)
        let slow = try sent(.elevenLabs, 0.5)
        #expect((slow.body["voice_settings"] as? [String: Any])?["speed"] as? Double == 0.7)
        let router = try sent(.openRouter, 4)
        #expect(router.body["speed"] == nil && router.tempo == 4)
    }

    @Test func fasterThanProviderExportShortensAudio() async throws {
        let ffmpeg = try #require(SpeechTools.findFFmpeg(), "FFmpeg is required for the audio integration tests.")
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let wav = root.appendingPathComponent("fixture.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        let frames: AVAudioFrameCount = 24000 * 3
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for index in 0..<Int(frames) { buffer.floatChannelData![0][index] = sin(Float(index) * 0.12) * 0.3 }
        do { let file = try AVAudioFile(forWriting: wav, settings: format.settings); try file.write(from: buffer) }
        let data = try Data(contentsOf: wav)
        let client = APISpeechClient(transport: { request in
            (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "audio/wav"])!)
        })
        let book = EPUBBook(title: "Tempo", author: "Test", language: "en", chapters: [BookChapter(id: "1", title: "One", text: "Sample.")],
                            source: root.appendingPathComponent("original.epub"))
        func duration(speed: Double) async throws -> Double {
            let destination = root.appendingPathComponent("audio-\(speed).mp3")
            let api = APINarration(provider: .openAI, model: "gpt-4o-mini-tts", voice: "marin", speed: speed, apiKey: "test-key")
            let options = ExportOptions(voice: "", wordsPerMinute: 175, bitrate: 128, mode: .single, chapterIDs: ["1"], ffmpeg: ffmpeg, api: api)
            _ = try await AudiobookExporter.export(book: book, options: options, destination: destination, apiClient: client)
            let decoded = root.appendingPathComponent("decoded-\(speed).wav")
            _ = try await ProcessRunner().run(ffmpeg, arguments: ["-nostdin", "-hide_banner", "-loglevel", "error", "-i", destination.path, "-c:a", "pcm_s16le", decoded.path])
            let file = try AVAudioFile(forReading: decoded)
            return Double(file.length) / file.processingFormat.sampleRate
        }
        // The mocked provider returns 3 s of audio either way; the final 0.7 s of padding is added after the tempo change.
        let nativeSpeed = try await duration(speed: 4)
        let faster = try await duration(speed: 6)
        #expect(abs(nativeSpeed - 3.7) < 0.15)
        #expect(abs(faster - 2.7) < 0.15)
    }

    @Test func openRouterCatalogListsDecodableModelsWithoutCredentials() async throws {
        let json = """
        {"data":[
          {"id":"hexgrad/kokoro-82m","name":"hexgrad: Kokoro 82M","pricing":{"prompt":"0.00000062","completion":"0"},"supported_voices":["af_heart","am_adam"]},
          {"id":"google/gemini-3.8-flash-tts","name":"Google: Gemini","pricing":{"prompt":"0.0000005","completion":"0.000009"},"supported_voices":["Puck"]},
          {"id":"bytedance-seed/seed-audio-1-0","name":"ByteDance Seed: Audio","pricing":{"prompt":"0","completion":"0.0025"}},
          {"id":"heygen/heygen-voice-1","name":"HeyGen Voice","pricing":{"prompt":"0.000015","completion":"0"},"supported_voices":["nadine"]}
        ]}
        """
        let client = APISpeechClient(transport: { request in
            #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/models?output_modalities=speech")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let models = try await client.openRouterSpeechModels()
        #expect(models.map(\.id) == ["bytedance-seed/seed-audio-1-0", "hexgrad/kokoro-82m"])
        #expect(models[0].voices.isEmpty && models[0].pricePerMillionCharacters == nil)
        #expect(models[1].voices == ["af_heart", "am_adam"])
        #expect(abs((models[1].pricePerMillionCharacters ?? 0) - 0.62) < 1e-9)
    }

    @Test func APIErrorDoesNotExposeResponseAndDoesNotRetry() async throws {
        let recorder = RequestCount()
        let client = APISpeechClient(transport: { request in
            await recorder.increment()
            return (Data("test-key SECRET BOOK TEXT".utf8), HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!)
        })
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        do {
            try await client.synthesize(text: "sample", settings: settings(.openAI), destination: root.appendingPathComponent("audio.wav"))
            Issue.record("Expected API error")
        } catch {
            #expect(error.localizedDescription.contains("HTTP 429"))
            #expect(!error.localizedDescription.contains("test-key"))
            #expect(!error.localizedDescription.contains("SECRET"))
        }
        #expect(await recorder.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func APITransportSupportsCancellationAndVoicePagination() async throws {
        let client = APISpeechClient(transport: { request in
            if request.url?.query?.contains("next_page_token") == true {
                return (Data("{\"voices\":[{\"voice_id\":\"b\",\"name\":\"Beta\"}],\"has_more\":false}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            return (Data("{\"voices\":[{\"voice_id\":\"a\",\"name\":\"Alpha\"}],\"has_more\":true,\"next_page_token\":\"page2\"}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        #expect(try await client.elevenLabsVoices(apiKey: "test").map(\.id) == ["a", "b"])
        let cancelClient = APISpeechClient(transport: { request in
            try await Task.sleep(for: .seconds(30))
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let task = Task { try await cancelClient.synthesize(text: "Sample", settings: settings(.openAI), destination: root.appendingPathComponent("audio.wav")) }
        task.cancel()
        do { try await task.value; Issue.record("Expected cancellation") } catch is CancellationError {} catch { Issue.record("Wrong cancellation error") }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func unicodeChunkingIsBoundedAndRetainsEveryScalar() {
        let text = String(repeating: "Hello 👩🏽‍💻. Another sentence.\n\n", count: 200)
        let chunks = AudiobookExporter.speechChunks(text, limit: 1500, utf8Limit: 2000)
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.unicodeScalars.count <= 1500 })
        #expect(chunks.allSatisfy { $0.utf8.count <= 2000 })
        #expect(chunks.joined() == text)
    }

    @Test(arguments: [NarrationProvider.openAI, .elevenLabs, .openRouter]) func mockedAPIExportProducesAudibleMP3AndCleansStaging(provider: NarrationProvider) async throws {
        let ffmpeg = try #require(SpeechTools.findFFmpeg(), "FFmpeg is required for the audio integration tests.")
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let wav = root.appendingPathComponent("fixture.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2400)!
        buffer.frameLength = 2400
        for index in 0..<2400 { buffer.floatChannelData![0][index] = sin(Float(index) * 0.12) * 0.3 }
        do { let file = try AVAudioFile(forWriting: wav, settings: format.settings); try file.write(from: buffer) }
        var audioSource = wav
        if provider.audioExtension == "mp3" {
            audioSource = root.appendingPathComponent("fixture.mp3")
            _ = try await ProcessRunner().run(ffmpeg, arguments: ["-nostdin", "-hide_banner", "-loglevel", "error", "-i", wav.path, "-c:a", "libmp3lame", audioSource.path])
        }
        let data = try Data(contentsOf: audioSource)
        let client = APISpeechClient(transport: { request in
            (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "audio/wav"])!)
        })
        let source = root.appendingPathComponent("original.epub")
        let book = EPUBBook(title: "Synthetic API Book", author: "Test", language: "en", chapters: [BookChapter(id: "1", title: "One", text: "First sample."), BookChapter(id: "2", title: "Two", text: "Second sample.")], source: source)
        let destination = root.appendingPathComponent("audio.mp3")
        let options = ExportOptions(voice: "", wordsPerMinute: 175, bitrate: 128, mode: .single, chapterIDs: ["1", "2"], ffmpeg: ffmpeg, api: settings(provider))
        _ = try await AudiobookExporter.export(book: book, options: options, destination: destination, apiClient: client)
        #expect((try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 1000)
        let decoded = root.appendingPathComponent("decoded.wav")
        _ = try await ProcessRunner().run(ffmpeg, arguments: ["-nostdin", "-hide_banner", "-loglevel", "error", "-i", destination.path, "-c:a", "pcm_s16le", decoded.path])
        try AudiobookExporter.validateSpeech(decoded, voice: "Mock API")
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".epub-audio-") })
    }

    private func settings(_ provider: NarrationProvider) -> APINarration {
        switch provider {
        case .openAI: APINarration(provider: provider, model: "gpt-4o-mini-tts", voice: "marin", apiKey: "test-key")
        case .openRouter: APINarration(provider: provider, model: "hexgrad/kokoro-82m", voice: "af_heart", apiKey: "test-key")
        default: APINarration(provider: provider, model: "eleven_multilingual_v2", voice: "voice123", apiKey: "test-key")
        }
    }
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("series-api-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false); return root
    }
    private func fixture(_ root: URL, name: String, title: String, text: String) throws -> URL {
        let resources: [(String, String)] = [
            ("mimetype", "application/epub+zip"),
            ("META-INF/container.xml", "<container><rootfiles><rootfile full-path=\"OPS/book.opf\"/></rootfiles></container>"),
            ("OPS/book.opf", "<package><metadata><title>\(title.replacingOccurrences(of: "&", with: "&amp;"))</title><creator>Author</creator><language>en</language></metadata><manifest><item id=\"ch\" href=\"chapter.xhtml\" media-type=\"application/xhtml+xml\"/><item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/><item id=\"css\" href=\"style.css\" media-type=\"text/css\"/><item id=\"img\" href=\"picture.png\" media-type=\"image/png\"/></manifest><spine><itemref idref=\"ch\"/><itemref idref=\"nav\"/></spine></package>"),
            ("OPS/chapter.xhtml", "<html><head><link href=\"style.css\" rel=\"stylesheet\"/></head><body><h1>Heading</h1><p>\(text)</p><img src=\"picture.png\"/></body></html>"),
            ("OPS/nav.xhtml", "<html><body><nav role=\"doc-toc\"><h1>Contents</h1><a href=\"chapter.xhtml\">Chapter Label</a></nav></body></html>"),
            ("OPS/style.css", "p {color: blue}")]
        let url = root.appendingPathComponent(name)
        try EPUBZIPWriter.encode(resources.map { ($0.0, Data($0.1.utf8)) } + [("OPS/picture.png", Data([1, 2, 3, 4]))]).write(to: url, options: .atomic)
        return url
    }
}
private actor RequestCount { var count = 0; func increment() { count += 1 } }
