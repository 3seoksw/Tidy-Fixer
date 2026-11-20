import AppKit
import Foundation

struct FixResult {
    var original: String
    var revised: String
    var flags: [String]
    var unchanged: Bool
}

enum BarState {
    case idle
    case gettingReady
    case rewriting
    case failed(String)
    case done(FixResult)
}

@MainActor
final class BarViewModel: ObservableObject {
    static let auto = "auto"

    @Published var input = "" {
        didSet { if input != oldValue { scheduleClassify() } }
    }
    @Published var selection = BarViewModel.auto {
        didSet {
            if selection != oldValue {
                if selection != Self.auto { autoPick = nil }
                scheduleClassify()
            }
        }
    }
    /// Tev1's pick, stored by id so a rename in Settings shows up right away.
    @Published var autoPick: String?
    var autoLabel: String? { autoPick.flatMap { store.profile(id: $0)?.name } }
    /// True only while a Tev1 request is in flight. Drives the spinner.
    @Published private(set) var classifying = false
    private var classifyInFlight = 0
    @Published var state: BarState = .idle
    @Published var openCount = 0
    @Published var inputHeight: CGFloat = 17
    @Published var justCopied = false

    let store: ProfileStore
    private let rewriter: TextRewriter
    let lifecycle: ModelLifecycle
    private let classifier: StyleClassifier
    private var sourceApp: NSRunningApplication?
    private var task: Task<Void, Never>?
    private var classifyTask: Task<Void, Never>?
    private var livePick: (key: String, id: String)?
    private(set) var busy = false

    init(store: ProfileStore, rewriter: TextRewriter, classifier: StyleClassifier) {
        self.store = store
        self.rewriter = rewriter
        self.lifecycle = ModelLifecycle(rewriter: rewriter)
        self.classifier = classifier
    }

    var isWorking: Bool {
        switch state {
        case .gettingReady, .rewriting: return true
        default: return false
        }
    }

    func open(source: NSRunningApplication?) {
        if let source, source.bundleIdentifier != Bundle.main.bundleIdentifier {
            sourceApp = source
        }
        openCount += 1
        scheduleClassify()
        lifecycle.warm()
    }

    func barClosed() {
        classifyTask?.cancel()
        lifecycle.barClosed()
    }

    func shutdown() {
        task?.cancel()
        classifyTask?.cancel()
        lifecycle.shutdown()
    }

    /// Lines that start a quoted thread: a rule of dashes or underscores, "On … wrote:", "From: …".
    private static let threadStart = try! NSRegularExpression(
        pattern: #"^(-{3,}|_{3,}|On .+ wrote:|From:\s.+|-+\s*Original Message\s*-+)$"#)

    private static func startsThread(_ line: Substring) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return threadStart.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
    }

    /// Everything from the first thread-start line on is context for the model. Only the draft above
    /// it is edited, diffed, and classified.
    static func split(_ input: String) -> (draft: String, context: String?) {
        let whole = (draft: input.trimmingCharacters(in: .whitespacesAndNewlines), context: String?.none)
        let lines = input.split(separator: "\n", omittingEmptySubsequences: false)
        guard let at = lines.firstIndex(where: startsThread) else { return whole }
        let draft = lines[..<at].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let context = lines[at...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasContext = !context.drop(while: { "-_ \n\t".contains($0) }).isEmpty
        return draft.isEmpty ? whole : (draft, hasContext ? context : nil)
    }

    func fix() {
        let (text, context) = Self.split(input)
        guard !text.isEmpty, !isWorking else { return }
        let total = input.trimmingCharacters(in: .whitespacesAndNewlines).count
        guard total <= ModelConfig.maxInputCharacters else {
            state = .failed(
                "This is \(total) characters. The limit is \(ModelConfig.maxInputCharacters). Shorten it, or raise the context window in Settings.")
            return
        }
        busy = true
        state = .gettingReady
        classifyTask?.cancel()
        task = Task {
            defer { busy = false }
            do {
                await lifecycle.waitUntilWarm()
                try Task.checkCancellation()
                state = .rewriting
                let profile = try await resolveProfile(for: text)
                let revised = try await lifecycle.use { try await rewriter.rewrite(text, context: context, profile: profile) }
                try Task.checkCancellation()
                guard !revised.isEmpty else {
                    state = .failed("The model returned nothing. Your text is unchanged.")
                    return
                }
                state = .done(
                    FixResult(
                        original: text, revised: revised,
                        flags: Protected.flags(original: text, revised: revised),
                        unchanged: Self.sameText(revised, text)))
            } catch is CancellationError {
                state = .idle
            } catch let e as URLError where e.code == .cancelled {
                state = .idle
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Models often swap curly quotes or rewrap lines, which should not count as a change.
    private static func sameText(_ a: String, _ b: String) -> Bool {
        func norm(_ s: String) -> String {
            TextDiff.stripInvisible(s).replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
                .replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"")
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        return norm(a) == norm(b)
    }

    func cancel() {
        task?.cancel()
        state = .idle
    }

    func clear() {
        task?.cancel()
        input = ""
        state = .idle
    }

    func copyRevised() {
        guard case .done(let r) = state else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(r.revised, forType: .string)
        justCopied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            justCopied = false
        }
    }

    /// A manual choice never calls Tev1.
    private func resolveProfile(for text: String) async throws -> Profile {
        if selection != Self.auto, let chosen = store.profile(id: selection) { return chosen }
        if let live = livePick, live.key == pickKey(for: text), let p = store.profile(id: live.id) {
            return p
        }
        if lifecycle.pressure == .critical {
            throw OllamaError.bad("Memory is low, so Auto is paused. Pick a profile from the menu.")
        }
        return try await classify(text)
    }

    /// One Tev1 call, cached for the same text, source app, and profiles.
    private func classify(_ text: String) async throws -> Profile {
        let key = pickKey(for: text)
        // A counter, so a cancelled call finishing late cannot switch off a newer one's spinner.
        classifyInFlight += 1
        classifying = true
        defer {
            classifyInFlight -= 1
            classifying = classifyInFlight > 0
        }
        let p = try await classifier.classify(
            text: text, appName: sourceApp?.localizedName, options: store.profiles)
        try Task.checkCancellation()
        livePick = (key, p.id)
        autoPick = p.id
        return p
    }

    private func pickKey(for text: String) -> String {
        let profiles = store.profiles.map { "\($0.id)|\($0.name)|\($0.style)" }.joined(separator: ";")
        return "\(sourceApp?.localizedName ?? "")\n\(profiles)\n\(text)"
    }

    /// Live Tev1 pick after a short typing pause. Skipped when a profile is chosen by hand.
    private func scheduleClassify() {
        classifyTask?.cancel()
        let text = Self.split(input).draft
        guard selection == Self.auto, !busy, lifecycle.pressure != .critical else { return }
        guard text.count >= 8 else {
            livePick = nil
            autoPick = nil
            return
        }
        let key = pickKey(for: text)
        if livePick?.key == key { return }
        classifyTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            _ = try? await classify(text)
        }
    }
}
