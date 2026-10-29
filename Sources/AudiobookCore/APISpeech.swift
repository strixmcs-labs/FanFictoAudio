import Foundation

public enum NarrationProvider: String, CaseIterable, Identifiable, Sendable, Codable {
    case system = "macOS voices", openAI = "OpenAI", elevenLabs = "ElevenLabs", openRouter = "OpenRouter"
    public var id: String { rawValue }
    /// Speeds offered for narration. Anything outside what the provider generates is
    /// reached by changing the tempo of the returned audio while encoding.
    public var speedRange: ClosedRange<Double> { (self == .openAI ? 0.25 : 0.5)...6 }
    /// Speeds the provider itself accepts. OpenRouter models differ in speed support, so
    /// their speech is always generated at normal speed and changed locally.
    public var nativeSpeedRange: ClosedRange<Double> {
        switch self { case .elevenLabs: 0.7...1.2; case .openRouter: 1...1; default: 0.25...4 }
    }
    /// The part of a narration speed sent to the provider.
    public func requestSpeed(_ speed: Double) -> Double {
        min(max(speed, nativeSpeedRange.lowerBound), nativeSpeedRange.upperBound)
    }
    /// Simultaneous speech requests during export. Low enough for entry-level rate and
    /// concurrency limits; failed requests are not retried, so they are never billed twice.
    public var concurrentRequests: Int {
        switch self { case .system: 1; case .openAI, .openRouter: 3; case .elevenLabs: 2 }
    }
    /// OpenAI limits speech input to 2000 bytes, and OpenRouter can route to OpenAI models.
    public var utf8Limit: Int? { self == .openAI || self == .openRouter ? 2000 : nil }
    /// The audio format each provider is asked to return.
    public var audioExtension: String { self == .openAI ? "wav" : "mp3" }
}

public struct APINarration: Sendable {
    public let provider: NarrationProvider
    public let model: String
    public let voice: String
    public let speed: Double
    public let instructions: String
    // Never persist this value to defaults, logs, filenames, or error messages.
    public let apiKey: String
    public init(provider: NarrationProvider, model: String, voice: String, speed: Double = 1,
                instructions: String = "", apiKey: String) {
        self.provider = provider; self.model = model; self.voice = voice
        self.speed = speed; self.instructions = instructions; self.apiKey = apiKey
    }
    /// The speed the provider generates at.
    public var requestSpeed: Double { provider.requestSpeed(speed) }
    /// The remaining speed change, applied to the returned audio without changing pitch.
    public var tempo: Double { speed / requestSpeed }
    public func validate() throws {
        guard provider != .system, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !model.isEmpty, !voice.isEmpty, provider.speedRange.contains(speed), instructions.count <= 4096 else {
            throw AudiobookError.conversion("Choose an API voice and model, save its API key, and choose a valid speed.")
        }
        // ElevenLabs voice IDs go in the URL path. OpenRouter voices are sent in the body
        // and some use periods and colons, such as "en-US-Harper:MAI-Voice-2".
        let allowed = provider == .openRouter ? #"^[A-Za-z0-9_.:-]+$"# : #"^[A-Za-z0-9_-]+$"#
        guard voice.range(of: allowed, options: .regularExpression) != nil else {
            throw AudiobookError.conversion(provider == .openRouter
                ? "The OpenRouter voice must contain only letters, numbers, periods, colons, underscores, or hyphens."
                : "The API voice ID must contain only letters, numbers, underscores, or hyphens.")
        }
    }
}

public struct APIVoice: Identifiable, Sendable, Decodable {
    public let id: String
    public let name: String
    enum CodingKeys: String, CodingKey { case id = "voice_id", name }
}

/// A speech model from OpenRouter's public catalog.
public struct OpenRouterSpeechModel: Identifiable, Sendable, Decodable {
    public let id: String
    public let name: String
    public let voices: [String]
    /// USD per million input characters, when the model is priced only by characters.
    public let pricePerMillionCharacters: Double?
    enum CodingKeys: String, CodingKey { case id, name, voices = "supported_voices", pricing }
    struct Pricing: Decodable { let prompt: String?; let completion: String? }
    public init(id: String, name: String, voices: [String], pricePerMillionCharacters: Double? = nil) {
        self.id = id; self.name = name; self.voices = voices; self.pricePerMillionCharacters = pricePerMillionCharacters
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? id
        voices = try container.decodeIfPresent([String].self, forKey: .voices) ?? []
        let pricing = try container.decodeIfPresent(Pricing.self, forKey: .pricing)
        // Models that also charge for audio output have no reliable per-character rate.
        if let prompt = pricing?.prompt.flatMap(Double.init), prompt.isFinite, prompt > 0,
           (pricing?.completion.flatMap(Double.init) ?? 0) == 0 {
            pricePerMillionCharacters = prompt * 1_000_000
        } else { pricePerMillionCharacters = nil }
    }
}

public struct APISpeechClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let transport: Transport
    public init(transport: @escaping Transport = Self.download) { self.transport = transport }

    public func speechRequest(text: String, settings: APINarration) throws -> URLRequest {
        try settings.validate()
        guard !text.isEmpty, text.unicodeScalars.count <= 1500, text.utf8.count <= settings.provider.utf8Limit ?? .max else {
            throw AudiobookError.conversion("API speech passages must contain 1 to 1500 characters, with a 2000-byte limit for OpenAI and OpenRouter.")
        }
        let url: URL
        var body: [String: Any]
        if settings.provider == .openAI {
            url = URL(string: "https://api.openai.com/v1/audio/speech")!
            body = ["model": settings.model, "voice": settings.voice, "input": text,
                    "response_format": "wav", "speed": settings.requestSpeed]
            if !settings.instructions.isEmpty && !settings.model.hasPrefix("tts-1") {
                body["instructions"] = settings.instructions
            }
        } else if settings.provider == .openRouter {
            url = URL(string: "https://openrouter.ai/api/v1/audio/speech")!
            body = ["model": settings.model, "voice": settings.voice, "input": text, "response_format": "mp3"]
            // Speed is applied locally, since some routed models reject any speed but the default.
            // Models that don't support instructions ignore them.
            if !settings.instructions.isEmpty { body["instructions"] = settings.instructions }
        } else {
            url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(settings.voice)?output_format=mp3_44100_128")!
            body = ["model_id": settings.model, "text": text, "voice_settings": ["speed": settings.requestSpeed]]
        }
        var request = authorized(url: url, provider: settings.provider, key: settings.apiKey)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public func synthesize(text: String, settings: APINarration, destination: URL,
                           usage: APIUsageLedger? = nil, budget: APIBudget? = nil) async throws {
        let request = try speechRequest(text: text, settings: settings)
        try Task.checkCancellation()
        // Reserve before dispatch. Failed or cancelled requests may still be billed.
        if let usage { try await usage.reserve(text: text, settings: settings, budget: budget) }
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        try Self.check(response, provider: settings.provider)
        guard data.count > 44, data.count <= 64 * 1024 * 1024,
              !(response.value(forHTTPHeaderField: "Content-Type") ?? "").contains("json") else {
            throw AudiobookError.conversion("\(settings.provider.rawValue) returned no usable audio.")
        }
        try data.write(to: destination, options: .withoutOverwriting)
    }

    public func elevenLabsVoices(apiKey: String) async throws -> [APIVoice] {
        var voices: [APIVoice] = []
        var cursor: String?
        var seen = Set<String>()
        // A bounded page count prevents an unexpected pagination loop.
        for _ in 0..<20 {
            var components = URLComponents(string: "https://api.elevenlabs.io/v2/voices")!
            components.queryItems = [URLQueryItem(name: "page_size", value: "100"), URLQueryItem(name: "include_total_count", value: "false")]
            if let cursor { components.queryItems?.append(URLQueryItem(name: "next_page_token", value: cursor)) }
            let request = authorized(url: components.url!, provider: .elevenLabs, key: apiKey)
            let (data, response) = try await transport(request)
            try Task.checkCancellation()
            try Self.check(response, provider: .elevenLabs)
            struct Page: Decodable { let voices: [APIVoice]; let has_more: Bool?; let next_page_token: String? }
            let page = try JSONDecoder().decode(Page.self, from: data)
            voices += page.voices.filter { seen.insert($0.id).inserted }
            guard page.has_more == true, let next = page.next_page_token, next != cursor else { break }
            cursor = next
        }
        return voices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Lists OpenRouter's speech models from its public catalog; no API key is sent.
    /// Gemini TTS and HeyGen Voice return only raw PCM, which has no header to decode, so
    /// they are left out.
    public func openRouterSpeechModels() async throws -> [OpenRouterSpeechModel] {
        let url = URL(string: "https://openrouter.ai/api/v1/models?output_modalities=speech")!
        let (data, response) = try await transport(URLRequest(url: url, timeoutInterval: 60))
        try Task.checkCancellation()
        try Self.check(response, provider: .openRouter)
        struct Catalog: Decodable { let data: [OpenRouterSpeechModel] }
        return try JSONDecoder().decode(Catalog.self, from: data).data
            .filter { !$0.id.hasPrefix("google/") && !$0.id.hasPrefix("heygen/") }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func authorized(url: URL, provider: NarrationProvider, key: String) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 180)
        if provider == .elevenLabs { request.setValue(key, forHTTPHeaderField: "xi-api-key") }
        else { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        return request
    }
    private static func check(_ response: HTTPURLResponse, provider: NarrationProvider) throws {
        guard (200..<300).contains(response.statusCode) else {
            let hint: String
            switch response.statusCode {
            case 401, 403: hint = "Check the API key and its permissions."
            case 402: hint = "Add credits to your account, then retry when ready."
            case 429: hint = "Check your quota or rate limit, then retry when ready."
            default: hint = "Check the voice, model, and provider status, then retry when ready."
            }
            // Bodies can echo book text or credentials; never show them in errors.
            throw AudiobookError.conversion("\(provider.rawValue) API returned HTTP \(response.statusCode). \(hint)")
        }
    }
    public static func download(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let session = pooledSession
        let downloaded: (URL, URLResponse)
        do { downloaded = try await session.download(for: request) }
        catch { if Task.isCancelled { throw CancellationError() }; throw error }
        let (file, response) = downloaded
        defer { try? FileManager.default.removeItem(at: file) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse,
              (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 64 * 1024 * 1024 else {
            throw AudiobookError.conversion("The API response was invalid or too large.")
        }
        return (try Data(contentsOf: file), http)
    }
    // Reuse connections across passages. Authentication stays on each request;
    // cookies and credential storage are disabled for every provider.
    private static let pooledSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 300
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        return URLSession(configuration: config, delegate: NoSpeechRedirects(), delegateQueue: nil)
    }()
}

private final class NoSpeechRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
