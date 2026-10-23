import SwiftUI
import DownloadCore

struct DownloadView: View {
    @ObservedObject var model: DownloadModel
    let openBook: (URL) -> Void
    private let accent = AppTheme.oxblood

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("FROM STORY LINK TO SPOKEN WORD").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(2).foregroundStyle(accent)
                    Text("Download by link").font(.system(size: 32, weight: .semibold, design: .serif))
                    Text("Paste a story page or an EPUB download link, then choose its voice and create your audiobook.").foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Story or EPUB links").font(.headline)
                        Text("Paste one URL per line. Story chapter ranges such as [1-5] are supported.").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $model.links)
                            .font(.system(.body, design: .monospaced)).scrollContentBackground(.hidden)
                            .padding(8).frame(minHeight: 125, maxHeight: 160)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel("Story or EPUB URLs, one per line")
                        HStack {
                            Picker("Action", selection: $model.selectedOperation) {
                                Text("Download by Link").tag("download")
                                Text("Preview story").tag("preview")
                                Text("Find links on a page").tag("extract")
                            }.frame(maxWidth: 290)
                            if model.selectedOperation == "download" {
                                Picker("Link type", selection: $model.sourceKind) {
                                    Text("Detect automatically").tag("auto")
                                    Text("Story page").tag("story")
                                    Text("Direct EPUB").tag("epub")
                                }
                            }
                            Spacer()
                        }
                        HStack {
                            Button("Add to Queue") { model.addLinks() }.disabled(model.links.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Spacer()
                            Button(model.selectedOperation == "download" ? "Download & Prepare Audiobook" : "Run Action") { model.addLinks(startImmediately: true) }
                                .buttonStyle(.borderedProminent).controlSize(.large)
                                .disabled(model.isRunning || model.links.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }.padding(20).frame(maxWidth: .infinity)
                        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Download preferences").font(.headline)
                        Text("Save EPUBs to").font(.caption).foregroundStyle(.secondary)
                        Text(model.output.path).font(.caption).textSelection(.enabled).lineLimit(3)
                        Button("Choose Folder…", action: model.chooseOutput)
                        Divider()
                        Text("Site settings and login").font(.subheadline.weight(.medium))
                        Text(model.ini.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Default site settings")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Choose personal.ini…", action: model.chooseINI)
                            if model.ini != nil { Button("Clear") { model.ini = nil } }
                        }
                        Toggle("Allow adult stories", isOn: $model.adult).font(.callout)
                        Text("Login details come from your selected INI. This choice applies to new and retried jobs.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(20).frame(width: 270, alignment: .leading)
                        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Story queue").font(.headline)
                        Spacer()
                        Button("Update Existing EPUBs…", action: model.updateEPUBs).disabled(model.isRunning)
                        if model.isRunning {
                            Button(model.isFinalizing ? "Saving EPUB…" : "Cancel & Pause Queue", action: model.cancel).disabled(model.isFinalizing)
                        } else {
                            Button("Start Queue", action: model.start).disabled(!model.hasQueued)
                        }
                    }
                    if model.jobs.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "arrow.down.document").font(.system(size: 32)).foregroundStyle(accent)
                            Text("Your stories will appear here.").font(.headline)
                            Text("Already have an EPUB? Open it from the toolbar to start narrating.")
                                .font(.callout).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(32)
                    } else {
                        ForEach(model.jobs) { job in
                            Button { model.selected = job.id } label: {
                                HStack(alignment: .top, spacing: 14) {
                                    Image(systemName: job.path != nil ? "book.closed.fill" : job.state == .failed ? "exclamationmark.circle" : "link")
                                        .font(.title2).foregroundStyle(accent).frame(width: 32).padding(.top, 4)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(job.title).font(.headline).lineLimit(2).textSelection(.enabled)
                                        if !job.author.isEmpty { Text(job.author).font(.callout).foregroundStyle(.secondary) }
                                        if !job.wordCount.isEmpty { Text(job.wordCount).font(.caption).foregroundStyle(.secondary) }
                                        Text(job.message.isEmpty ? job.request.operation.capitalized : job.message)
                                            .font(.caption).foregroundStyle(job.state == .failed ? .red : .secondary).lineLimit(4)
                                        if job.state == .running {
                                            if let progress = job.progress { ProgressView(value: progress, total: 100) }
                                            else { ProgressView().controlSize(.small) }
                                        }
                                    }
                                    Spacer()
                                    Text(job.state.rawValue).font(.caption.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(accent.opacity(0.1), in: Capsule())
                                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(model.selected == job.id ? accent.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.selected == job.id ? accent.opacity(0.45) : Color.secondary.opacity(0.15)))
                            }.buttonStyle(.plain)
                        }
                        if let selected = model.selectedJob {
                            HStack {
                                if let path = selected.path {
                                    Button("Make Audiobook") { openBook(path) }.buttonStyle(.borderedProminent).disabled(model.isRunning)
                                    Button("Show EPUB in Finder", action: model.revealSelected)
                                }
                                if selected.state.canRetry {
                                    Button("Retry Selected", action: model.retrySelected).disabled(model.isRunning)
                                }
                                Spacer()
                                Button("Clear Finished") { model.jobs.removeAll { $0.state.isFinished } }
                                    .disabled(model.isRunning)
                            }
                            if let backup = selected.backup {
                                Text("Original EPUB backed up to \(backup)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                    }
                }.padding(20).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
                Text("FanFicFare handles supported story sites and their access requirements. Direct EPUB links are downloaded and validated before saving. EPUBs stay in your chosen folder. Choose macOS voices or an AI speech provider in the audiobook section.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(32).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
        }
        .tint(accent)
        .alert("Unable to complete this action", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}
