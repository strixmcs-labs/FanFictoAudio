import AppKit
import SwiftUI
import DownloadCore
import UniformTypeIdentifiers

enum StoryState: String, Codable {
    case queued = "Queued", running = "Running", done = "Done", upToDate = "Up to date", failed = "Failed", cancelled = "Cancelled"
    var isFinished: Bool { self != .queued && self != .running }
    var canRetry: Bool { self == .failed || self == .cancelled }
}

struct StoryJob: Identifiable, Codable {
    var id = UUID()
    var request: DownloadRequest
    var title: String
    var author = ""
    var wordCount = ""
    var state = StoryState.queued
    var message = ""
    var progress: Double?
    var path: URL?
    var backup: String?
}

@MainActor
final class DownloadModel: ObservableObject {
    @Published var links = ""
    @Published var output = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "epubDestination")
        ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FanFic to Audio/EPUBs").path) {
        didSet { UserDefaults.standard.set(output.path, forKey: "epubDestination") }
    }
    @Published var ini = UserDefaults.standard.string(forKey: "personalINI") {
        didSet { UserDefaults.standard.set(ini, forKey: "personalINI") }
    }
    @Published var adult = false
    @Published var jobs: [StoryJob] = [] { didSet { persist() } }
    @Published var selected: UUID?
    @Published var isRunning = false
    @Published var isFinalizing = false
    @Published var readyURL: URL?
    @Published var readyURLs: [URL] = []
    @Published var errorMessage: String?
    @Published var selectedOperation = "download"
    @Published var sourceKind = "auto"
    private var runner: DownloadRunner?
    private var task: Task<Void, Never>?
    private var pauseRequested = false
    private let storage: URL?
    private struct Snapshot: Codable { let version: Int; let jobs: [StoryJob] }

    /// Restores the story list from the last session. Interrupted downloads wait to be started again.
    init(storage: URL? = AppData.directory.appendingPathComponent("downloads.json")) {
        self.storage = storage
        guard let storage, let data = try? Data(contentsOf: storage),
              let saved = try? JSONDecoder().decode(Snapshot.self, from: data), saved.version == 1 else { return }
        jobs = saved.jobs.map { job in
            var restored = job
            if restored.state == .running {
                restored.state = .queued; restored.progress = nil
                restored.message = "Interrupted when the app quit. Start the queue to download it again."
            }
            return restored
        }
        selected = jobs.last?.id
    }

    private func persist() {
        guard let storage else { return }
        try? FileManager.default.createDirectory(at: storage.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(Snapshot(version: 1, jobs: jobs)).write(to: storage, options: .atomic)
    }

    var selectedJob: StoryJob? { jobs.first { $0.id == selected } }
    var hasQueued: Bool { jobs.contains { $0.state == .queued } }
    var helper: URL? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Downloader/fanfic-download")
        if let bundled, FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        // Supports running from this checkout after Scripts/build-worker.py.
        let built = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/worker/fanfic-download/fanfic-download")
        return FileManager.default.isExecutableFile(atPath: built.path) ? built : nil
    }

    func chooseOutput() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.directoryURL = output; panel.prompt = "Save EPUBs Here"
        if panel.runModal() == .OK, let url = panel.url { output = url }
    }

    func chooseINI() {
        let panel = NSOpenPanel()
        panel.message = "Choose your personal.ini for site login, cookies, and download preferences."
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { ini = url.path }
    }

    func addLinks(startImmediately: Bool = false) {
        do {
            let sources = try StoryLinks.parse(links)
            for source in sources {
                var request = DownloadRequest(operation: selectedOperation, source: source, output: output.path, ini: ini, adult: adult)
                request.source_kind = selectedOperation == "download" ? sourceKind : "story"
                let job = StoryJob(request: request, title: source)
                jobs.append(job); selected = job.id
            }
            links = ""
            if startImmediately { start() }
        } catch { errorMessage = error.localizedDescription }
    }

    func updateEPUBs() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "epub") ?? .data]
        panel.allowsMultipleSelection = true
        panel.message = "Update FanFicFare EPUBs. Originals are backed up before replacement."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let job = StoryJob(request: DownloadRequest(operation: "update", source: url.path, output: url.deletingLastPathComponent().path, ini: ini, adult: adult), title: url.deletingPathExtension().lastPathComponent)
            jobs.append(job); selected = job.id
        }
        start()
    }

    func start() {
        guard !isRunning, hasQueued else { return }
        guard let helper else { errorMessage = "The FanFicFare download helper is missing. Build the complete app with Scripts/build-app.sh."; return }
        isRunning = true; pauseRequested = false; readyURL = nil; readyURLs = []
        task = Task { [self] in
            var completedBooks: [URL] = []
            while !pauseRequested, let index = jobs.firstIndex(where: { $0.state == .queued }) {
                let id = jobs[index].id
                jobs[index].state = .running
                jobs[index].message = "Reading story information…"
                selected = id; isFinalizing = false
                let jobRunner = DownloadRunner()
                runner = jobRunner
                do {
                    let result = try await jobRunner.run(jobs[index].request, executable: helper) { [weak self] event in
                        Task { @MainActor [weak self] in self?.receive(event, for: id) }
                    }
                    if let current = jobs.firstIndex(where: { $0.id == id }) {
                        jobs[current].state = result.status == "unchanged" ? .upToDate : .done
                        jobs[current].message = result.status == "unchanged" ? "No new chapters. Your EPUB is unchanged." : "Completed."
                        jobs[current].progress = 100
                        if let path = result.path {
                            let url = URL(fileURLWithPath: path)
                            jobs[current].path = url; completedBooks.append(url)
                        }
                        jobs[current].backup = result.backup
                        if let metadata = result.metadata { apply(metadata, at: current) }
                        if let urls = result.urls {
                            links = urls.joined(separator: "\n")
                            jobs[current].message = "Found \(urls.count) links. Review them above, then choose Download EPUB."
                        }
                    }
                } catch is CancellationError {
                    if let current = jobs.firstIndex(where: { $0.id == id }) {
                        jobs[current].state = .cancelled; jobs[current].message = "Download cancelled."
                    }
                } catch {
                    if let current = jobs.firstIndex(where: { $0.id == id }) {
                        jobs[current].state = .failed; jobs[current].message = error.localizedDescription
                    }
                }
                runner = nil; isFinalizing = false
            }
            isRunning = false; task = nil
            readyURL = completedBooks.last
            readyURLs = completedBooks
        }
    }

    private func receive(_ event: DownloadEvent, for id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].state == .running else { return }
        if let metadata = event.metadata { apply(metadata, at: index) }
        if let message = event.message { jobs[index].message = message }
        if let percent = event.percent { jobs[index].progress = percent }
        if event.finalizing == true { isFinalizing = true }
    }

    private func apply(_ metadata: [String: String], at index: Int) {
        if let title = metadata["title"], !title.isEmpty { jobs[index].title = title }
        jobs[index].author = metadata["author"] ?? ""
        let count = metadata["numWords"] ?? ""
        jobs[index].wordCount = count.isEmpty ? "" : "\(count) words (\(metadata["wordCountSource"] ?? "site"))"
    }

    func cancel() {
        pauseRequested = true
        if runner?.cancel() == true { isFinalizing = false }
    }

    func retrySelected() {
        guard !isRunning, let index = jobs.firstIndex(where: { $0.id == selected }), jobs[index].state.canRetry else { return }
        jobs[index].request.ini = ini; jobs[index].request.adult = adult
        jobs[index].request.source_kind = jobs[index].request.operation == "download" ? sourceKind : "story"
        jobs[index].state = .queued; jobs[index].progress = nil; jobs[index].message = ""
        start()
    }

    func revealSelected() {
        guard let path = selectedJob?.path else { return }
        NSWorkspace.shared.activateFileViewerSelecting([path])
    }

    func shutdown() async {
        cancel()
        await task?.value
    }
}
