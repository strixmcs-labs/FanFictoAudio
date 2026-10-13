import Foundation
import AVFAudio

public enum AudiobookExporter {
    public static func export(book: EPUBBook, options: ExportOptions, destination: URL,
                              runner: ProcessRunner = ProcessRunner(),
                              progress: @escaping @Sendable (ExportProgress) -> Void = { _ in }) async throws -> URL {
        let chapters = book.chapters.filter {
            options.chapterIDs.contains($0.id) && !(options.narration.skipFrontMatter && $0.isFrontMatter)
        }.map { ($0, options.narration.text(for: $0)) }.filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !chapters.isEmpty else { throw AudiobookError.conversion("No readable chapters remain after your selection and narration filters.") }
        guard SpeechRate.allowedRange.contains(options.wordsPerMinute), [64, 96, 128, 192].contains(options.bitrate),
              !options.voice.isEmpty, options.narration.chapterPause.isFinite, (0...10).contains(options.narration.chapterPause) else {
            throw AudiobookError.conversion("Choose a valid voice, speed, quality and chapter pause (0–10 seconds).")
        }
        guard destination.isFileURL, destination.standardizedFileURL != book.source.standardizedFileURL else {
            throw AudiobookError.conversion("Choose a local export destination separate from the original EPUB.")
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw AudiobookError.conversion("That destination already exists. Choose a new name to preserve the existing file.")
        }
        progress(ExportProgress(0, "Checking audio encoder…"))
        try await SpeechTools.verifyFFmpeg(options.ffmpeg, runner: runner, mode: options.mode)
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Creating an audiobook")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        let stage = destination.deletingLastPathComponent().appendingPathComponent(".epub-audio-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: stage) }
        let work = stage.appendingPathComponent("work", isDirectory: true)
        let result = stage.appendingPathComponent("result", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: result, withIntermediateDirectories: false)
        let checkpoint = try options.checkpoint.map { try ConversionCheckpoint(root: $0, book: book, options: options) }
        var allAudio: [URL] = []
        var durations: [Double] = []
        var estimator = ProgressEstimator()
        let totalCharacters = max(1, chapters.reduce(0) { $0 + $1.1.count })
        var completedCharacters = 0
        for (chapterIndex, prepared) in chapters.enumerated() {
            let (chapter, text) = prepared
            var audio: [URL] = []
            var duration = 0.0
            let chunks = speechChunks(text)
            for (chunkIndex, chunk) in chunks.enumerated() {
                try runner.checkCancellation()
                let name = "c\(chapterIndex)-p\(chunkIndex).flac"
                let message = "Narrating \(chapterIndex + 1) of \(chapters.count): \(chapter.title) · passage \(chunkIndex + 1) of \(chunks.count)"
                progress(ExportProgress(Double(completedCharacters) / Double(totalCharacters) * 0.94, message,
                    remainingSeconds: estimator.remaining(characters: totalCharacters - completedCharacters)))
                if let checkpoint, let cached = checkpoint.cached(name) {
                    audio.append(checkpoint.directory.appendingPathComponent(name)); duration += cached.duration
                    completedCharacters += chunk.count
                    progress(ExportProgress(Double(completedCharacters) / Double(totalCharacters) * 0.94, "Resumed completed passage: \(chapter.title)"))
                    continue
                }
                let started = Date()
                let textFile = work.appendingPathComponent("passage.txt")
                let pcm = work.appendingPathComponent("passage.aiff")
                let part = work.appendingPathComponent(name)
                try chunk.write(to: textFile, atomically: true, encoding: .utf8)
                _ = try await runner.run(SpeechTools.say, arguments: ["-v", options.voice, "-r", String(options.wordsPerMinute),
                    "-f", textFile.path, "-o", pcm.path, "--data-format=BEI16@44100"])
                try runner.checkCancellation()
                try validateSpeech(pcm, voice: options.voice)
                let source = try AVAudioFile(forReading: pcm)
                let pause = chunkIndex == chunks.count - 1 ? options.narration.chapterPause : 0
                let passageDuration = Double(source.length) / source.fileFormat.sampleRate + pause
                var args = ["-nostdin", "-hide_banner", "-loglevel", "error", "-n", "-i", pcm.path,
                    "-map", "0:a:0", "-vn", "-ac", "1", "-ar", "44100", "-c:a", "flac"]
                if pause > 0 { args += ["-af", "apad=pad_dur=\(pause)"] }
                args += ["-map_metadata", "-1", part.path]
                _ = try await runner.run(options.ffmpeg, arguments: args)
                try FileManager.default.removeItem(at: pcm)
                if let checkpoint {
                    try checkpoint.commit(name, from: part, duration: passageDuration)
                    try FileManager.default.removeItem(at: part)
                    audio.append(checkpoint.directory.appendingPathComponent(name))
                } else { audio.append(part) }
                duration += passageDuration
                completedCharacters += chunk.count
                estimator.record(characters: chunk.count, seconds: Date().timeIntervalSince(started))
                progress(ExportProgress(Double(completedCharacters) / Double(totalCharacters) * 0.94, "Completed passage: \(chapter.title)",
                    remainingSeconds: estimator.remaining(characters: totalCharacters - completedCharacters)))
            }
            durations.append(duration)
            if options.mode == .chapters {
                let output = result.appendingPathComponent(String(format: "%03d", chapterIndex + 1) + " - " + FileNames.safe(chapter.title) + ".mp3")
                try await encode(audio, output: output, book: book, title: chapter.title,
                    chapters: [], durations: [], options: options, track: "\(chapterIndex + 1)/\(chapters.count)", work: work, runner: runner)
            } else { allAudio += audio }
        }
        try runner.checkCancellation()
        progress(ExportProgress(0.96, "Encoding the finished audiobook…"))
        if options.mode == .chapters {
            try FileManager.default.moveItem(at: result, to: destination)
        } else {
            let complete = stage.appendingPathComponent("audiobook." + options.mode.fileExtension)
            try await encode(allAudio, output: complete, book: book, title: book.title,
                chapters: chapters.map(\.0), durations: durations, options: options, work: work, runner: runner)
            try runner.checkCancellation()
            try FileManager.default.moveItem(at: complete, to: destination)
        }
        checkpoint?.discardCompleted()
        progress(ExportProgress(1, "Your audiobook is ready."))
        return destination
    }

    static func metadata(book: EPUBBook, title: String, chapters: [BookChapter], durations: [Double], track: String? = nil) -> String {
        func escape(_ value: String) -> String {
            value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "=", with: "\\=")
                .replacingOccurrences(of: ";", with: "\\;").replacingOccurrences(of: "#", with: "\\#")
                .replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        }
        var content = ";FFMETADATA1\ntitle=\(escape(title))\nartist=\(escape(book.author))\nalbum=\(escape(book.title))\ngenre=Audiobook\n"
        if let track { content += "track=\(escape(track))\n" }
        var position = 0.0
        for (chapter, duration) in zip(chapters, durations) {
            let start = Int((position * 1000).rounded()); position += duration
            content += "[CHAPTER]\nTIMEBASE=1/1000\nSTART=\(start)\nEND=\(Int((position * 1000).rounded()))\ntitle=\(escape(chapter.title))\n"
        }
        return content
    }

    private static func encode(_ inputs: [URL], output: URL, book: EPUBBook, title: String, chapters: [BookChapter],
                               durations: [Double], options: ExportOptions, track: String? = nil, work: URL, runner: ProcessRunner) async throws {
        let list = work.appendingPathComponent("join.txt")
        let lines = inputs.map { "file '\($0.path.replacingOccurrences(of: "'", with: "'\\''"))'" }.joined(separator: "\n") + "\n"
        guard inputs.allSatisfy({ !$0.path.contains("\n") && !$0.path.contains("\r") }) else { throw AudiobookError.conversion("Output and cache folder paths cannot contain line breaks.") }
        try lines.write(to: list, atomically: true, encoding: .utf8)
        let metadataFile = work.appendingPathComponent("metadata.txt")
        try metadata(book: book, title: title, chapters: options.mode == .m4b ? chapters : [], durations: durations, track: track)
            .write(to: metadataFile, atomically: true, encoding: .utf8)
        var args = ["-nostdin", "-hide_banner", "-loglevel", "error", "-n", "-f", "concat", "-safe", "0", "-i", list.path,
            "-f", "ffmetadata", "-i", metadataFile.path]
        if let cover = book.cover {
            let image = work.appendingPathComponent(cover.starts(with: [0xff, 0xd8]) ? "cover.jpg" : "cover.png")
            try cover.write(to: image)
            args += ["-f", "image2", "-pattern_type", "none", "-i", image.path, "-map", "2:v:0", "-c:v", "mjpeg", "-disposition:v:0", "attached_pic"]
        }
        args += ["-map", "0:a:0", "-c:a", options.mode == .m4b ? "aac" : "libmp3lame", "-ac", "1", "-ar", "44100",
            "-b:a", "\(options.bitrate)k", "-map_metadata", "1", "-map_chapters", options.mode == .m4b ? "1" : "-1"]
        args += options.mode == .m4b ? ["-movflags", "+faststart", "-f", "mp4"] : ["-id3v2_version", "3"]
        args.append(output.path)
        _ = try await runner.run(options.ffmpeg, arguments: args)
        guard (try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0 else { throw AudiobookError.conversion("The encoder produced an empty file.") }
    }

    static func validateSpeech(_ url: URL, voice: String) throws {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096)!
        while file.framePosition < file.length {
            try file.read(into: buffer)
            guard buffer.frameLength > 0, let samples = buffer.floatChannelData else { break }
            for channel in 0..<Int(buffer.format.channelCount) {
                if UnsafeBufferPointer(start: samples[channel], count: Int(buffer.frameLength)).contains(where: { abs($0) > 0.00001 }) { return }
            }
        }
        throw AudiobookError.conversion("macOS produced no audible speech for \(voice). Try another installed voice, or run the app directly outside a restricted command environment.")
    }

    // Bound PCM disk use and avoid speech engine limits on very long chapters.
    // Prefer paragraph and sentence boundaries; retain every character in order.
    static func speechChunks(_ text: String, limit: Int = 6000) -> [String] {
        var remaining = text[...]
        var chunks: [String] = []
        while !remaining.isEmpty {
            if remaining.count <= limit { chunks.append(String(remaining)); break }
            let cutoff = remaining.index(remaining.startIndex, offsetBy: limit)
            let prefix = remaining[..<cutoff]
            let floor = prefix.index(prefix.startIndex, offsetBy: limit / 2)
            let tail = prefix[floor...]
            let split: String.Index
            if let range = tail.range(of: "\n\n", options: .backwards) { split = range.upperBound }
            else if let range = tail.range(of: #"[.!?][\s]+"#, options: [.regularExpression, .backwards]) { split = range.upperBound }
            else if let whitespace = tail.lastIndex(where: { $0.isWhitespace }) { split = remaining.index(after: whitespace) }
            else { split = cutoff }
            chunks.append(String(remaining[..<split]))
            remaining = remaining[split...]
        }
        return chunks.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
