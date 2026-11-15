import Foundation

protocol TextRewriter {
    func rewrite(_ text: String, context: String?, profile: Profile) async throws -> String
    func warm() async throws
    func unload() async
    func expiresAt() async -> Date?
    func unloadAtQuit(ourExpiry: Date?)
}

protocol StyleClassifier {
    func classify(text: String, appName: String?, options: [Profile]) async throws -> Profile
}

enum ModelConfig {
    static var rewriter: String {
        UserDefaults.standard.string(forKey: "rewriterModel") ?? "qwen3:14b"
    }
    static var classifier: String {
        UserDefaults.standard.string(forKey: "classifierModel") ?? "tev1:4b"
    }
    /// How long Ollama keeps the rewriter after its last use. Set in Settings, or with:
    /// defaults write com.wskim.local-writing-fixer idleTimeout 30m
    static var idleTimeout: String {
        UserDefaults.standard.string(forKey: "idleTimeout") ?? "5m"
    }
    static var idleSeconds: TimeInterval {
        let t = idleTimeout
        guard let n = Double(t.dropLast()) else { return 300 }
        switch t.last {
        case "s": return n
        case "h": return n * 3600
        default: return n * 60
        }
    }
    static var warmOnOpen: Bool { flag("warmOnOpen", default: true) }
    static var unloadOnPressure: Bool { flag("unloadOnPressure", default: true) }
    /// Off by default: the idle timeout already frees the model, and the app cannot prove that no
    /// other Ollama client is using it.
    static var unloadOnQuit: Bool { flag("unloadOnQuit", default: false) }

    private static func flag(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }

    /// Context window in tokens. The output and input limits follow from it: output gets half,
    /// and input about 1.5 characters per token, which leaves room for the prompt.
    static var numCtx: Int {
        let v = UserDefaults.standard.integer(forKey: "numCtx")
        return v > 0 ? v : 4096
    }
    static var numPredict: Int { numCtx / 2 }
    static var maxInputCharacters: Int { numCtx * 3 / 2 }
}

struct OllamaRewriter: TextRewriter {
    var client = OllamaClient()

    func rewrite(_ text: String, context: String?, profile: Profile) async throws -> String {
        var user = "Style: \(profile.style)\n\n"
        if let context {
            user += "<context>\n\(context)\n</context>\nThe <context> block is an earlier message in the thread, for reference only. Never edit, quote, or repeat it. Edit only the text below.\n\n"
        }
        user += "<text>\n\(text)\n</text>"
        let out = try await client.chat(
            model: ModelConfig.rewriter, system: profile.prompt, user: user,
            keepAlive: ModelConfig.idleTimeout, numCtx: ModelConfig.numCtx,
            numPredict: ModelConfig.numPredict)
        return Self.clean(out)
    }

    func warm() async throws {
        try await client.warm(
            model: ModelConfig.rewriter, keepAlive: ModelConfig.idleTimeout, numCtx: ModelConfig.numCtx)
    }

    func unload() async {
        await client.unload(model: ModelConfig.rewriter)
    }

    func expiresAt() async -> Date? {
        await client.expiresAt(model: ModelConfig.rewriter)
    }

    func unloadAtQuit(ourExpiry: Date?) {
        client.unloadAtQuit(model: ModelConfig.rewriter, ourExpiry: ourExpiry)
    }

    static func clean(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("<text>") { s.removeFirst(6) }
        if s.hasSuffix("</text>") { s.removeLast(7) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Tev1 is a decision model, so it goes through /v1/systemone instead of chat.
/// keep_alive is left at the server default because the OMP classifier shares this model.
struct Tev1Classifier: StyleClassifier {
    var client = OllamaClient()

    /// Always returns the option with the highest probability. The probabilities sum to 1, so the
    /// top one is a valid pick even when the margin is small.
    func classify(text: String, appName: String?, options: [Profile]) async throws -> Profile {
        let criteria = Dictionary(
            uniqueKeysWithValues: options.map { ($0.id, "\($0.name): \($0.style)") })
        let body: [String: Any] = [
            "model": ModelConfig.classifier,
            "state": ["app": appName ?? "unknown", "message": String(text.prefix(1500))],
            "questions": [
                "style": [
                    "type": "choice",
                    "instructions": "Which writing style fits the message in `message`?",
                    "criteria": criteria,
                ]
            ],
        ]
        let data = try await client.post("v1/systemone", body, model: ModelConfig.classifier)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let answers = obj["answers"] as? [String: Any],
            let style = answers["style"] as? [String: Any],
            let probs = style["probabilities"] as? [String: Double],
            let best = probs.max(by: { $0.value < $1.value })?.key,
            let profile = options.first(where: { $0.id == best })
        else { throw OllamaError.bad("Unexpected response from the style classifier.") }
        return profile
    }
}
