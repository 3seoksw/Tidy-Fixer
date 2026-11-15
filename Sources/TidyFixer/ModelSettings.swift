import Foundation

/// Backs the Models page in Settings. Reads and writes the same defaults that ModelConfig reads.
final class ModelSettings: ObservableObject {
    static let idleChoices: [(title: String, value: String)] = [
        ("5 minutes", "5m"), ("10 minutes", "10m"), ("30 minutes", "30m"), ("1 hour", "1h"),
        ("3 hours", "3h"),
    ]

    static let contextChoices: [(title: String, value: Int)] = [
        ("2,048 tokens (about 3,000 characters)", 2048),
        ("4,096 tokens (about 6,000 characters)", 4096),
        ("8,192 tokens (about 12,000 characters)", 8192),
        ("16,384 tokens (about 24,000 characters)", 16384),
    ]

    @Published var rewriterModel: String {
        didSet {
            guard rewriterModel != oldValue else { return }
            UserDefaults.standard.set(rewriterModel, forKey: "rewriterModel")
            let old = oldValue
            Task { await OllamaClient().unload(model: old) }
        }
    }
    @Published var installedModels: [String] = []

    @MainActor func refreshModels() async {
        installedModels = await OllamaClient().chatModels()
    }

    /// Only meaningful once a list has loaded, so an Ollama that is down doesn't flag everything.
    func isMissing(_ model: String) -> Bool {
        !installedModels.isEmpty && !installedModels.contains(model)
    }

    /// The current choice stays listed even if Ollama is down or the model was removed.
    var modelOptions: [String] {
        installedModels.contains(rewriterModel) ? installedModels : [rewriterModel] + installedModels
    }

    @Published var numCtx: Int {
        didSet { UserDefaults.standard.set(numCtx, forKey: "numCtx") }
    }
    @Published var idleTimeout: String {
        didSet { UserDefaults.standard.set(idleTimeout, forKey: "idleTimeout") }
    }
    @Published var warmOnOpen: Bool {
        didSet { UserDefaults.standard.set(warmOnOpen, forKey: "warmOnOpen") }
    }
    @Published var unloadOnPressure: Bool {
        didSet { UserDefaults.standard.set(unloadOnPressure, forKey: "unloadOnPressure") }
    }
    @Published var unloadOnQuit: Bool {
        didSet { UserDefaults.standard.set(unloadOnQuit, forKey: "unloadOnQuit") }
    }

    init() {
        rewriterModel = ModelConfig.rewriter
        numCtx = ModelConfig.numCtx
        idleTimeout = ModelConfig.idleTimeout
        warmOnOpen = ModelConfig.warmOnOpen
        unloadOnPressure = ModelConfig.unloadOnPressure
        unloadOnQuit = ModelConfig.unloadOnQuit
    }

    /// A value set by hand with `defaults write` still shows up in the picker.
    var idleOptions: [(title: String, value: String)] {
        Self.idleChoices.contains { $0.value == idleTimeout }
            ? Self.idleChoices : Self.idleChoices + [(idleTimeout, idleTimeout)]
    }
}
