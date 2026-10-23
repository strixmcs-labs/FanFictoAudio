import SwiftUI
import AudiobookCore

struct PronunciationsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pronunciations").font(.headline)
                Spacer()
                Button { model.pronunciations.append(Pronunciation()) } label: { Label("Add Word", systemImage: "plus") }
            }
            if model.pronunciations.isEmpty {
                Text("Add names or invented words the narrator says wrong, with a spelling that sounds right, such as Hermione → Her-my-oh-nee.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach($model.pronunciations) { $entry in
                HStack {
                    TextField("Word in the book", text: $entry.word)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("Say it as", text: $entry.sayAs)
                    Button { model.pronunciations.removeAll { $0.id == entry.id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).accessibilityLabel("Remove \(entry.word)")
                }.textFieldStyle(.roundedBorder)
            }
            Text("Whole words are replaced in every book, ignoring capitalization, for all voices. Preview a section that uses the word to hear it.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .disabled(model.busy)
    }
}

extension NarrationPreset {
    /// One line describing the voice, output, and text choices.
    var displaySummary: String {
        var parts = provider == .system
            ? [voice.isEmpty ? "No voice selected" : voice, "\(wordsPerMinute) wpm"]
            : [provider.rawValue, apiVoice.isEmpty ? "no voice selected" : apiVoice, model, String(format: "%.2f×", speed)]
        parts += [mode.rawValue, "\(bitrate) kbps"]
        let text = textOptions
        if text.skipAuthorNotes { parts.append("skips author’s notes") }
        if text.announceChapterTitles { parts.append("reads titles") }
        if !text.pronunciations.isEmpty { parts.append(text.pronunciations.count == 1 ? "1 pronunciation" : "\(text.pronunciations.count) pronunciations") }
        return parts.joined(separator: " · ")
    }
}
