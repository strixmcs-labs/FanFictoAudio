import Foundation
import Darwin
import AudiobookCore

@main
struct EPUBAudioCLI {
    static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            if args == ["voices"] {
                for voice in try await SpeechTools.voices() { print(voice.label) }
                return
            }
            guard args.count >= 2 else {
                print("Usage: epub-audio inspect BOOK.epub\n       epub-audio export BOOK.epub OUTPUT [--voice NAME] [--rate 175] [--bitrate 128] [--chapters | --m4b] [--checkpoint PATH] [--pause-seconds 0.7] [--skip-front-matter] [--skip-footnotes] [--ffmpeg PATH]\n       epub-audio voices")
                return
            }
            let book = try EPUBReader.read(URL(fileURLWithPath: args[1]))
            if args[0] == "inspect" {
                print("\(book.title)\n\(book.author)\nLanguage: \(book.language)")
                for chapter in book.chapters { print("\(chapter.includedByDefault ? "✓" : "·") \(chapter.title) — \(chapter.wordCount) words") }
                for warning in book.warnings { print("Warning: \(warning)") }
                return
            }
            guard args[0] == "export", args.count >= 3 else { throw AudiobookError.conversion("Expected inspect or export; export requires a destination.") }
            func option(_ flag: String) throws -> String? {
                guard let index = args.firstIndex(of: flag) else { return nil }
                guard index + 1 < args.count else { throw AudiobookError.conversion("Missing value for \(flag).") }
                return args[index + 1]
            }
            let voice = try await SpeechTools.voices().first(where: { $0.name == "Samantha" })?.name ?? "Alex"
            let ffmpeg = try option("--ffmpeg").map { URL(fileURLWithPath: $0) } ?? SpeechTools.findFFmpeg()
            guard let ffmpeg else { throw AudiobookError.conversion("FFmpeg is missing. Install it or pass --ffmpeg PATH.") }
            guard let rate = Int(try option("--rate") ?? "175"), let bitrate = Int(try option("--bitrate") ?? "128"),
                  let pause = Double(try option("--pause-seconds") ?? "0.7"), !(args.contains("--m4b") && args.contains("--chapters")) else {
                throw AudiobookError.conversion("Invalid rate, bitrate, pause, or conflicting output modes.")
            }
            let options = try ExportOptions(voice: option("--voice") ?? voice,
                wordsPerMinute: rate, bitrate: bitrate,
                mode: args.contains("--m4b") ? .m4b : args.contains("--chapters") ? .chapters : .single,
                chapterIDs: Set(book.chapters.filter(\.includedByDefault).map(\.id)), ffmpeg: ffmpeg,
                checkpoint: option("--checkpoint").map { URL(fileURLWithPath: $0) },
                narration: NarrationPreferences(chapterPause: pause, skipFrontMatter: args.contains("--skip-front-matter"), skipFootnotes: args.contains("--skip-footnotes")))
            let runner = ProcessRunner()
            signal(SIGINT, SIG_IGN); signal(SIGTERM, SIG_IGN)
            let signals = [SIGINT, SIGTERM].map { value in
                let source = DispatchSource.makeSignalSource(signal: value, queue: .global())
                source.setEventHandler { runner.cancel() }; source.resume(); return source
            }
            defer { signals.forEach { $0.cancel() } }
            let result = try await AudiobookExporter.export(book: book, options: options, destination: URL(fileURLWithPath: args[2]), runner: runner) { status in
                print("\(Int(status.fraction * 100))% \(status.message)")
            }
            print(result.path)
        } catch is CancellationError {
            FileHandle.standardError.write(Data("Paused. Run the same command with --checkpoint to resume completed passages.\n".utf8))
            exit(130)
        } catch {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
