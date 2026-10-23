import SwiftUI
import UniformTypeIdentifiers
import AudiobookCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    private let accent = AppTheme.oxblood

    var body: some View {
        HStack(spacing: 0) {
            chapterSidebar.frame(width: 290)
            Divider()
            VStack(spacing: 0) {
                header
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch model.pane {
                        case .narration:
                            NarrationSettingsView(model: model)
                            PronunciationsView(model: model)
                            outputSettings
                            APIUsageView(model: model)
                        case .book:
                            bookPane
                        case .queue:
                            narrationSummary
                            AudiobookQueueView(model: model, queue: model.audiobookQueue)
                        }
                    }
                    .padding(32)
                    .frame(maxWidth: 900, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(AppTheme.background)
        }
        .tint(accent)
        .onDrop(of: [UTType.fileURL], isTargeted: $model.isDropTarget, perform: acceptDrop)
        .overlay {
            if model.isDropTarget {
                RoundedRectangle(cornerRadius: 16).stroke(accent, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(8).allowsHitTesting(false)
            }
        }
        .alert("Unable to complete this action", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .alert("Rename Section", isPresented: Binding(get: { model.renamingChapter != nil }, set: { if !$0 { model.renamingChapter = nil } })) {
            TextField("Section title", text: $model.renameDraft)
            Button("Rename") { if let id = model.renamingChapter { model.renameChapter(id, to: model.renameDraft) } }
            Button("Use Original Title") { if let id = model.renamingChapter { model.renameChapter(id, to: "") } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The title is used for M4B chapters, chapter file names, and read-aloud titles. Original: \(model.renamingChapter.map(model.originalTitle) ?? "")")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("YOUR STORY, OUT LOUD").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(2).foregroundStyle(accent)
                Text("Create your audiobooks").font(.system(size: 24, weight: .semibold, design: .serif))
            }
            Spacer()
            Picker("Section", selection: $model.pane) {
                ForEach(WorkspacePane.allCases) { pane in
                    Text(pane == .queue && model.audiobookQueue.queuedCount > 0 ? "Queue (\(model.audiobookQueue.queuedCount))" : pane.rawValue).tag(pane)
                }
            }.pickerStyle(.segmented).labelsHidden().frame(width: 360)
        }.padding(.horizontal, 32).padding(.vertical, 16)
    }

    /// The current narration settings, shown where books are exported so they are never hidden.
    private var narrationSummary: some View {
        HStack(spacing: 10) {
            Image(systemName: model.provider == .system ? "desktopcomputer" : "waveform").foregroundStyle(accent).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Narration").font(.caption.weight(.medium))
                Text(model.presetFromControls().displaySummary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button("Change…") { model.pane = .narration }
        }
        .padding(12).background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var bookPane: some View {
        if let book = model.book {
            narrationSummary
            bookSummary(book).id(book.source)
            chapterPreview.id(book.source.path + (model.focusedChapter ?? ""))
            exportSection
            if !book.warnings.isEmpty {
                Label(book.warnings.joined(separator: "\n"), systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        } else {
            VStack(spacing: 14) {
                Image(systemName: "book.and.wrench").font(.system(size: 36)).foregroundStyle(accent).accessibilityHidden(true)
                Text("Open a single EPUB to review its text, choose and arrange sections, and export it.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack {
                    Button("Open EPUB…", action: model.chooseEPUB).disabled(model.busy)
                    Button("Go to Queue") { model.pane = .queue }
                }
            }.frame(maxWidth: .infinity).padding(.vertical, 60)
        }
    }

    private var chapterSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Reading order").font(.headline)
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
            }.padding(20)
            if let book = model.book {
                HStack {
                    Text("\(model.selectedChapters.count) of \(book.chapters.count) sections").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        Button("Select All") { model.selectedChapters = Set(book.chapters.map(\.id)) }
                        Button("Select Reading Order") { model.selectedChapters = Set(book.chapters.filter(\.includedByDefault).map(\.id)) }
                        Button("Deselect All") { model.selectedChapters = [] }
                        Divider()
                        Button("Restore EPUB Order", action: model.restoreSpineOrder).disabled(model.customChapterOrder == nil)
                    } label: { Image(systemName: "checklist") }.menuStyle(.borderlessButton).frame(width: 28)
                }.padding(.horizontal, 20).padding(.bottom, 12).disabled(model.busy)
                List(selection: $model.focusedChapter) {
                    ForEach(Array(model.orderedChapters.enumerated()), id: \.element.id) { index, chapter in
                        HStack(alignment: .top, spacing: 10) {
                            Toggle("Include \(chapter.title)", isOn: Binding(
                                get: { model.selectedChapters.contains(chapter.id) },
                                set: { model.toggleChapter(chapter.id, included: $0) }))
                                .labelsHidden().toggleStyle(.checkbox).disabled(model.busy)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(chapter.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                Text("\(index + 1) · \(chapter.wordCount.formatted()) words" + (model.chapterTitles[chapter.id] == nil ? "" : " · renamed"))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 5)
                        .tag(chapter.id)
                        .contextMenu {
                            Button("Rename…") { model.renameDraft = chapter.title; model.renamingChapter = chapter.id }.disabled(model.busy)
                            Divider()
                            chapterMoveMenu(chapter.id, count: book.chapters.count)
                        }
                    }
                    .onMove(perform: moveAction)
                }.listStyle(.sidebar)
                orderFooter

            } else {
                VStack(spacing: 12) {
                    Image(systemName: "text.book.closed").font(.system(size: 35)).foregroundStyle(.tertiary)
                    Text("Your book’s sections\nwill appear here.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            Label(model.provider == .system ? "Narration on your Mac" : "AI narration via \(model.provider.rawValue)", systemImage: model.provider == .system ? "desktopcomputer" : "waveform").font(.caption).foregroundStyle(.secondary).padding(20)
        }
        .background(AppTheme.background)
    }

    private var moveAction: ((IndexSet, Int) -> Void)? {
        model.busy ? nil : { model.moveChapters(from: $0, to: $1) }
    }

    private var orderFooter: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.customChapterOrder == nil
                 ? "Sections follow the EPUB spine. Drag a section to change the reading order, or right-click to rename it. Navigation and non-linear extras start unchecked."
                 : "Custom reading order. Exports and saved queue settings use this order.")
                .font(.caption2).foregroundStyle(.secondary)
            if model.customChapterOrder != nil {
                Spacer(minLength: 4)
                Button("Restore", action: model.restoreSpineOrder).controlSize(.small).disabled(model.busy)
                    .help("Restore the EPUB’s original reading order")
            }
        }.padding(20)
    }

    @ViewBuilder private func chapterMoveMenu(_ id: String, count: Int) -> some View {
        Button("Move to Top") { model.moveChapter(id, by: -count) }.disabled(!model.canMoveChapter(id, by: -1))
        Button("Move Up") { model.moveChapter(id, by: -1) }.disabled(!model.canMoveChapter(id, by: -1))
        Button("Move Down") { model.moveChapter(id, by: 1) }.disabled(!model.canMoveChapter(id, by: 1))
        Button("Move to Bottom") { model.moveChapter(id, by: count) }.disabled(!model.canMoveChapter(id, by: 1))
    }

    private var outputSettings: some View {
        HStack(spacing: 24) {
            Text("Output").font(.headline)
            Picker("Format", selection: $model.mode) { ForEach(ExportMode.allCases) { Text($0.rawValue).tag($0) } }
            Picker("Quality", selection: $model.bitrate) {
                Text("64 kbps").tag(64)
                Text("96 kbps").tag(96)
                Text("128 kbps").tag(128)
                Text("192 kbps").tag(192)
            }.frame(width: 160)
        }.padding(20).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12)).disabled(model.busy)
    }

    private func bookSummary(_ book: EPUBBook) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Group {
                if let cover = model.coverImage {
                    Image(nsImage: cover).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        AppTheme.bookGradient
                        Image(systemName: "book.closed.fill").font(.system(size: 32)).foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .frame(width: 68, height: 88).clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2))).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(book.title).font(.title2.weight(.semibold)).textSelection(.enabled)
                if !book.author.isEmpty { Text(book.author).foregroundStyle(.secondary).textSelection(.enabled) }
                HStack(spacing: 16) {
                    Label("\(model.selectedWordCount.formatted()) words", systemImage: "text.alignleft")
                    Label("About \(model.estimatedDuration) of audio", systemImage: "clock")
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }


    @ViewBuilder private var chapterPreview: some View {
        if let chapter = model.currentChapter, let text = model.currentNarratedText {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Text preview").font(.headline)
                    Spacer()
                    Text(chapter.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                ScrollView {
                    Text(text.isEmpty ? "This section is only author’s notes, so it will be skipped." : String(text.prefix(8000)))
                        .font(.system(size: 14, design: .serif)).lineSpacing(5)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 125)
                if text != chapter.text {
                    Text("Showing the text as it will be narrated with your author’s note and title choices.").font(.caption2).foregroundStyle(.secondary)
                }
                if text.count > 8000 { Text("Showing the first part of this section. Export includes its full text.").font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
            Text("Export open book").font(.headline)
            if model.ffmpeg == nil {
                HStack {
                    Label("Select FFmpeg to enable MP3 export.", systemImage: "info.circle").font(.callout)
                    Spacer()
                    Button("Choose FFmpeg…", action: model.chooseFFmpeg)
                }
            }
            if model.isExporting {
                ProgressView(value: model.progress)
                HStack {
                    Text(model.status).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel", action: model.cancelExport)
                }
            } else {
                HStack {
                    if model.exportedURL != nil {
                        Label("Audiobook ready", systemImage: "checkmark.circle.fill").foregroundStyle(accent)
                        Button("Show in Finder", action: model.revealExport)
                    } else { Text(model.status).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Create Audiobook…", action: model.chooseDestinationAndExport)
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.canExport)
                }
            }
            Text("Estimated length is the listening time. Conversion time depends on the voice and book. Your Mac stays awake while exporting.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !model.busy, !providers.isEmpty else { return false }
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                let url: URL? = await withCheckedContinuation { continuation in
                    _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                        continuation.resume(returning: data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) })
                    }
                }
                if let url, url.pathExtension.lowercased() == "epub" { urls.append(url) }
            }
            if urls.isEmpty { model.errorMessage = "Choose files with the .epub extension." }
            else { model.addToAudiobookQueue(urls) }
        }
        return true
    }
}
