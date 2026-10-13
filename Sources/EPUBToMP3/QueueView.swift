import SwiftUI
import AppKit
import AudiobookCore

struct QueueView: View {
    @ObservedObject var queue: AudiobookQueue
    let addBooks: () -> Void
    let addCurrent: (() -> Void)?
    let start: () -> Void
    let encoderAvailable: Bool
    let preset: NarrationPreset
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            HStack {
                Text("Audiobook queue").font(.headline)
                Spacer()
                Button("Add EPUBs…", action: addBooks).disabled(queue.isRunning)
                if let addCurrent { Button("Add Current Book", action: addCurrent).disabled(queue.isRunning) }
            }
            if let error = queue.persistenceError { Text(error).foregroundStyle(.red).font(.caption) }
            ForEach(queue.jobs) { job in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.title).font(.callout.weight(.medium)).lineLimit(1)
                        Text(job.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        if let preset = job.narration { Text("\(preset.voice) · \(preset.wordsPerMinute) wpm · \(preset.mode.rawValue)").font(.caption2).foregroundStyle(.secondary) }
                        if job.state == .running || job.state == .paused { ProgressView(value: job.progress) }
                        if job.state == .running, let seconds = job.remainingSeconds, seconds.isFinite, seconds > 1 {
                            Text("About \(Int((seconds / 60).rounded(.up))) min remaining").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 12)
                    Text(job.state.rawValue).font(.caption)
                    if job.state == .done, let output = job.output {
                        Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([output]) }
                    } else if job.state == .failed || job.state == .cancelled {
                        Button("Retry") { queue.retry(job.id) }.disabled(queue.isRunning)
                    }
                    Menu {
                        Button("Move Up") { queue.move(job.id, by: -1) }.disabled(!queue.canMove(job.id, by: -1))
                        Button("Move Down") { queue.move(job.id, by: 1) }.disabled(!queue.canMove(job.id, by: 1))
                        Button("Use Current Narration Settings") { queue.updateNarration(job.id, preset: preset) }.disabled(job.state == .done)
                        Button("Remove", role: .destructive) { queue.remove(job.id) }
                    } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 24).disabled(queue.isRunning)
                }.padding(10).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Text(queue.summary).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if queue.isRunning { Button("Pause Queue") { queue.cancelAndPause() } }
                else {
                    Button("Clear Finished") { queue.clearFinished() }.disabled(!queue.jobs.contains { $0.state == .done })
                    Button("Start / Resume Queue", action: start).buttonStyle(.borderedProminent)
                        .disabled(queue.queuedCount == 0 || !encoderAvailable || queue.persistenceError != nil)
                }
            }
            Text("The queue and completed passages are saved locally. Settings are captured when a book is added. Pause or quit safely, then resume.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
