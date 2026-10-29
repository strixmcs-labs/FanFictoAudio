import Foundation

/// Safe to save with the queue. API credentials are deliberately absent.
public struct NarrationPreset: Codable, Sendable, Equatable {
    public let provider: NarrationProvider
    public let model: String
    public let apiVoice: String
    public let speed: Double
    public let instructions: String
    public let voice: String
    public let wordsPerMinute: Int
    public let bitrate: Int
    public let mode: ExportMode
    /// Omitted when unchanged, so presets saved before this option still decode and
    /// checkpoint fingerprints for unchanged text stay the same.
    public let text: NarrationTextOptions?
    public var pricingID: String { provider.rawValue + "." + model }
    public var textOptions: NarrationTextOptions { text ?? .unchanged }
    public init(voice: String, wordsPerMinute: Int, bitrate: Int, mode: ExportMode, api: APINarration?, text: NarrationTextOptions = .unchanged) {
        provider = api?.provider ?? .system; model = api?.model ?? ""; apiVoice = api?.voice ?? ""
        speed = api?.speed ?? 1; instructions = api?.instructions ?? ""
        self.voice = voice; self.wordsPerMinute = wordsPerMinute; self.bitrate = bitrate; self.mode = mode
        self.text = text.isUnchanged ? nil : text
    }
    /// Compares only the settings that affect this provider's narration and output.
    public func isEquivalent(to other: NarrationPreset) -> Bool {
        guard provider == other.provider, bitrate == other.bitrate, mode == other.mode, textOptions == other.textOptions else { return false }
        if provider == .system { return voice == other.voice && wordsPerMinute == other.wordsPerMinute }
        return model == other.model && apiVoice == other.apiVoice && speed == other.speed
            && (provider == .elevenLabs || instructions == other.instructions)
    }
    public func api(key: String) -> APINarration? {
        provider == .system ? nil : APINarration(provider: provider, model: model, voice: apiVoice, speed: speed, instructions: instructions, apiKey: key)
    }
}
