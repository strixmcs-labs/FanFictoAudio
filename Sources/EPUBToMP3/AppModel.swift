import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers
import AudiobookCore

@MainActor
final class AppModel: ObservableObject {
    @Published var book: EPUBBook?
    @Published var selectedChapters: Set<String> = []
    @Published var focusedChapter: String?
    @Published var voices: [SystemVoice] = []
    @Published var voice = UserDefaults.standard.string(forKey: "selectedVoice") ?? "" {
        didSet { UserDefaults.standard.set(voice, forKey: "selectedVoice") }
    }
    @Published private var storedRate = SpeechRate.normalized(UserDefaults.standard.object(forKey: "speakingRate") as? Double ?? 175)
    var rate: Double {
        get { storedRate }
        set {
            storedRate = SpeechRate.normalized(newValue)
            UserDefaults.standard.set(storedRate, forKey: "speakingRate")
        }
    }
    @Published var bitrate = UserDefaults.standard.object(forKey: "mp3Bitrate") as? Int ?? 128 {
        didSet { UserDefaults.standard.set(bitrate, forKey: "mp3Bitrate") }
    }
    @Published var mode: ExportMode = .single
    @Published var narration = NarrationPreferences()
    @Published var presetName = ""
    @Published var savedPresets: [NarrationPreset] = []
    @Published var selectedPreset: UUID?
    let queue: AudiobookQueue
    private var queueObserver: AnyCancellable?
    static var dataDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("EPUBToMP3", isDirectory: true)
    }
    init() {
        queue = AudiobookQueue(storage: Self.dataDirectory.appendingPathComponent("queue.json"),
            checkpointRoot: Self.dataDirectory.appendingPathComponent("Checkpoints", isDirectory: true))
        if let data = UserDefaults.standard.data(forKey: "narrationPresets"),
           let presets = try? JSONDecoder().decode([NarrationPreset].self, from: data) { savedPresets = presets }
        queueObserver = queue.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.progress = self.queue.batchProgress
                self.status = self.queue.summary
                self.objectWillChange.send()
            }
        }
        queue.onCompletion = { [weak self] message in
            self?.status = message
            self?.exportedURL = self?.queue.jobs.last(where: { $0.state == .done })?.output
        }
    }
    var currentPreset: NarrationPreset {
        NarrationPreset(voice: voice, wordsPerMinute: Int(rate), bitrate: bitrate, mode: mode, narration: narration)
    }
    var remainingTime: String? {
        guard let seconds = queue.currentJob?.remainingSeconds, seconds > 1 else { return nil }
        let minutes = Int((seconds / 60).rounded(.up))
        return minutes >= 60 ? "About \(minutes / 60)h \(minutes % 60)m remaining" : "About \(minutes)m remaining"
    }
    func savePreset() {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var preset = currentPreset; preset.name = name
        savedPresets.append(preset)
        if let data = try? JSONEncoder().encode(savedPresets) { UserDefaults.standard.set(data, forKey: "narrationPresets") }
        presetName = ""
    }
    func applyPreset(_ id: UUID) {
        guard let preset = savedPresets.first(where: { $0.id == id }) else { return }
        voice = preset.voice; rate = Double(preset.wordsPerMinute); bitrate = preset.bitrate
        mode = preset.mode; narration = preset.narration
    }
    func addBooksToQueue() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "epub") ?? .data]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        queue.add(panel.urls, narration: currentPreset)
    }
    func addCurrentToQueue() {
        guard let book, !busy else { return }
        queue.add([book.source], chapterIDs: selectedChapters, narration: currentPreset)
    }
    func startQueue(folder: URL? = nil) {
        guard !busy, let ffmpeg else { return }
        let chosenFolder: URL
        if let folder { chosenFolder = folder }
        else {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
            panel.prompt = "Start Queue Here"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            chosenFolder = url
        }
        stopPreview()
        do { try queue.start(settings: BatchNarrationSettings(preset: currentPreset, ffmpeg: ffmpeg), folder: chosenFolder) }
        catch { errorMessage = error.localizedDescription }
    }

    @Published var ffmpeg = SpeechTools.findFFmpeg()
    @Published var isLoading = false
    var isExporting: Bool { queue.isRunning }
    @Published var isPreviewing = false
    @Published var progress = 0.0
    @Published var status = "Choose an EPUB to begin."
    @Published var errorMessage: String?
    @Published var exportedURL: URL?
    @Published var voiceSearch = ""
    @Published var isDropTarget = false
    private var previewTask: Task<Void, Never>?
    private var previewRunner: ProcessRunner?

    var busy: Bool { isLoading || isExporting }
    var selectedWordCount: Int {
        book?.chapters.filter { selectedChapters.contains($0.id) && !(narration.skipFrontMatter && $0.isFrontMatter) }.reduce(0) { $0 + narration.text(for: $1).split(whereSeparator: { $0.isWhitespace }).count } ?? 0
    }
    var estimatedDuration: String {
        let minutes = Int((Double(selectedWordCount) / max(1, rate)).rounded(.up))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
    var currentChapter: BookChapter? {
        book?.chapters.first(where: { $0.id == focusedChapter }) ?? book?.chapters.first
    }
    var filteredVoices: [SystemVoice] {
        voices.filter { $0.id == voice || voiceSearch.isEmpty || $0.label.localizedCaseInsensitiveContains(voiceSearch) }
    }
    var canExport: Bool { book != nil && !selectedChapters.isEmpty && !voice.isEmpty && ffmpeg != nil && !busy && rate.isFinite && SpeechRate.sliderRange.contains(rate) }

    func loadVoices() async {
        do {
            voices = try await SpeechTools.voices()
            if !voices.contains(where: { $0.name == voice }) {
                voice = voices.first(where: { $0.name == "Samantha" })?.name ?? voices.first?.name ?? ""
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func chooseEPUB() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "epub") ?? .data]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open EPUB"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadBook(url)
    }

    func loadBook(_ url: URL) {
        guard !busy else { return }
        stopPreview()
        isLoading = true
        exportedURL = nil
        status = "Reading EPUB…"
        Task {
            do {
                let loaded = try await Task.detached(priority: .userInitiated) { try EPUBReader.read(url) }.value
                book = loaded
                selectedChapters = Set(loaded.chapters.filter(\.includedByDefault).map(\.id))
                focusedChapter = loaded.chapters.first?.id
                status = "Ready to narrate."
            } catch {
                errorMessage = error.localizedDescription
                status = book == nil ? "Choose an EPUB to begin." : "Ready to narrate."
            }
            isLoading = false
        }
    }

    func toggleChapter(_ id: String, included: Bool) {
        if included { selectedChapters.insert(id) } else { selectedChapters.remove(id) }
        exportedURL = nil
    }

    func chooseFFmpeg() {
        let panel = NSOpenPanel()
        panel.message = "Select the FFmpeg executable used to encode MP3 files."
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await SpeechTools.verifyFFmpeg(url, runner: ProcessRunner())
                ffmpeg = url
                UserDefaults.standard.set(url.path, forKey: "ffmpegPath")
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func preview() {
        if isPreviewing { stopPreview(); return }
        guard !voice.isEmpty, !busy else { return }
        let text = currentChapter.map { narration.text(for: $0) } ?? "Welcome. This is a preview of the voice for your audiobook. Choose a speaking speed that feels comfortable to you."
        // Use a short sample, preferring a complete sentence near the cutoff.
        let prefix = String(text.prefix(550))
        let sample: String
        if let end = prefix.range(of: #"[.!?](?:\s|$)"#, options: [.regularExpression, .backwards]) {
            sample = String(prefix[..<end.upperBound])
        } else { sample = prefix }
        let runner = ProcessRunner()
        previewRunner = runner
        isPreviewing = true
        let chosenVoice = voice
        let chosenRate = Int(rate)
        previewTask = Task {
            do {
                // -- terminates options, so text beginning with a dash is spoken safely.
                _ = try await runner.run(SpeechTools.say, arguments: ["-v", chosenVoice, "-r", String(chosenRate), "--", sample])
            } catch is CancellationError {} catch { errorMessage = error.localizedDescription }
            isPreviewing = false
            previewRunner = nil
            previewTask = nil
        }
    }

    func stopPreview() {
        previewRunner?.cancel()
        previewTask?.cancel()
        // Keep isPreviewing set until the process exits; this prevents overlapping previews.
    }

    func chooseDestinationAndExport() {
        guard canExport, let book else { return }
        let destination: URL
        if mode != .chapters {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [mode == .m4b ? UTType(filenameExtension: "m4b") ?? .audio : .mp3]
            panel.nameFieldStringValue = FileNames.safe(book.title) + "." + mode.fileExtension
            panel.prompt = "Create Audiobook"
            panel.message = "Choose a new filename for your audiobook."
            guard panel.runModal() == .OK, let url = panel.url else { return }
            destination = url
        } else {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Export Here"
            panel.message = "A new audiobook folder will be created here, containing numbered chapter MP3s."
            guard panel.runModal() == .OK, let folder = panel.url else { return }
            let name = FileNames.safe(book.title)
            var candidate = folder.appendingPathComponent(name, isDirectory: true)
            var suffix = 2
            while FileManager.default.fileExists(atPath: candidate.path) {
                candidate = folder.appendingPathComponent("\(name) (\(suffix))", isDirectory: true)
                suffix += 1
            }
            destination = candidate
        }
        stopPreview()
        if queue.add([book.source], chapterIDs: selectedChapters, narration: currentPreset, destination: destination) == 0 {
            errorMessage = "This book is already waiting in the queue. Use Start / Resume Queue to continue it."
            return
        }
        exportedURL = nil
        startQueue(folder: destination.deletingLastPathComponent())
    }

    func cancelExport() { queue.cancelAndPause() }

    func revealExport() {
        guard let exportedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([exportedURL])
    }

    func shutdown() async {
        stopPreview()
        cancelExport()
        await queue.shutdown()
        await previewTask?.value
    }
}
