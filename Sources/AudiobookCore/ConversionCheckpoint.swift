import Foundation
import CryptoKit

struct CachedPassage: Codable { let hash: String; let duration: Double }

/// Fingerprints include the prepared text and all narration settings; corrupted
/// cached passages are regenerated. A completed export removes its checkpoints.
final class ConversionCheckpoint {
    let directory: URL
    private var passages: [String: CachedPassage] = [:]
    private var manifest: URL { directory.appendingPathComponent("passages.json") }
    init(root: URL, book: EPUBBook, options: ExportOptions) throws {
        var hash = SHA256()
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let settings = [options.voice, String(options.wordsPerMinute), String(options.narration.chapterPause)]
        hash.update(data: try encoder.encode(settings))
        hash.update(data: Data("epub-checkpoint-flac-v1\0".utf8))
        for chapter in book.chapters where options.chapterIDs.contains(chapter.id) && !(options.narration.skipFrontMatter && chapter.isFrontMatter) {
            for string in [chapter.id, options.narration.text(for: chapter)] { hash.update(data: Data(string.utf8)); hash.update(data: Data([0])) }
        }
        directory = root.appendingPathComponent(hash.finalize().map { String(format: "%02x", $0) }.joined(), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: manifest), let saved = try? JSONDecoder().decode([String: CachedPassage].self, from: data) { passages = saved }
    }
    func cached(_ name: String) -> CachedPassage? {
        guard let saved = passages[name], saved.duration.isFinite, saved.duration > 0,
              let data = try? Data(contentsOf: directory.appendingPathComponent(name), options: .mappedIfSafe), Self.digest(data) == saved.hash else { return nil }
        return saved
    }
    func commit(_ name: String, from source: URL, duration: Double) throws {
        guard duration.isFinite, duration > 0 else { throw AudiobookError.conversion("Invalid passage duration.") }
        let data = try Data(contentsOf: source, options: .mappedIfSafe)
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        passages[name] = CachedPassage(hash: Self.digest(data), duration: duration)
        try JSONEncoder().encode(passages).write(to: manifest, options: .atomic)
    }
    func discardCompleted() { try? FileManager.default.removeItem(at: directory) }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
