import Foundation

enum ModelState { case unloaded, loading, ready, inUse, unloading }
enum MemoryPressure { case normal, warning, critical }

/// Owns the rewriter's life in memory: one warm-up at a time, no unloading during use, and no
/// unloading of a model another client has touched. Ollama holds the weights; this only decides
/// when to ask for a load or an unload.
@MainActor
final class ModelLifecycle {
    private let rewriter: TextRewriter
    private(set) var state: ModelState = .unloaded
    private(set) var pressure: MemoryPressure = .normal

    private var uses = 0
    private var warmTask: Task<Void, Never>?
    private var unloadTask: Task<Void, Never>?
    /// True while the bar is open and wants the model.
    private var wanted = false
    private var unloadWhenFree = false
    /// When Ollama should drop the model if nobody else touches it, going by what we last asked for.
    private var ourExpiry: Date?

    init(rewriter: TextRewriter) {
        self.rewriter = rewriter
    }

    /// Bar opened. Deduplicated, and skipped under memory pressure.
    func warm() {
        wanted = true
        guard ModelConfig.warmOnOpen, pressure == .normal, warmTask == nil else { return }
        let startedCold = state == .unloaded
        warmTask = Task {
            await unloadTask?.value
            if state == .unloaded { state = .loading }
            do {
                try await rewriter.warm()
                markKept()
                if state == .loading { state = uses > 0 ? .inUse : .ready }
            } catch {
                if state == .loading { state = .unloaded }
            }
            warmTask = nil
            // The bar closed while this load was in flight. A late finish must not leave an unwanted model.
            if !wanted, startedCold, uses == 0 { unloadIfIdle() }
        }
    }

    /// Lets Fix wait for an in-flight warm-up so the UI can say "Getting ready…".
    func waitUntilWarm() async {
        await warmTask?.value
    }

    /// Bar closed. A load in flight is not cancelled, since the server may finish it anyway.
    /// It is unloaded when it completes, and a model that was already warm just idles out.
    func barClosed() {
        wanted = false
    }

    /// Runs one request. Queues behind an unload, and blocks unloading until it finishes.
    func use<T>(_ body: () async throws -> T) async throws -> T {
        await unloadTask?.value
        uses += 1
        state = .inUse
        do {
            let value = try await body()
            markKept()
            await release()
            return value
        } catch {
            await release()
            throw error
        }
    }

    func pressureChanged(_ level: MemoryPressure) {
        pressure = level
        guard level != .normal else { return }
        wanted = false
        guard ModelConfig.unloadOnPressure else { return }
        if uses > 0 || warmTask != nil {
            if level == .critical { unloadWhenFree = true }
            return
        }
        unloadIfIdle()
    }

    /// Quit. Synchronous on purpose: the main queue is not serviced during termination.
    /// A load still in flight is cancelled here, and the unload request queues behind it on the server.
    func shutdown() {
        wanted = false
        warmTask?.cancel()
        if state != .unloaded, ModelConfig.unloadOnQuit { rewriter.unloadAtQuit(ourExpiry: ourExpiry) }
    }

    private func release() async {
        uses -= 1
        guard uses == 0 else { return }
        state = .ready
        if unloadWhenFree {
            unloadWhenFree = false
            unloadIfIdle()
            await unloadTask?.value
        }
    }

    private func markKept() {
        ourExpiry = Date().addingTimeInterval(ModelConfig.idleSeconds)
    }

    private func unloadIfIdle(force: Bool = false) {
        guard unloadTask == nil, state != .unloaded, force || uses == 0 else { return }
        unloadTask = Task {
            state = .unloading
            if await othersUsing() {
                state = uses > 0 ? .inUse : .ready
            } else {
                await rewriter.unload()
                state = .unloaded
                ourExpiry = nil
            }
            unloadTask = nil
        }
    }

    /// Best effort only. A server expiry later than ours means another client used the model since,
    /// but a client with the same or a shorter keep-alive, or one active within the tolerance, is invisible.
    /// Ollama finishes in-flight requests before it unloads, so the worst case is a reload for them.
    private func othersUsing() async -> Bool {
        guard let server = await rewriter.expiresAt(), let ours = ourExpiry else { return false }
        return server > ours.addingTimeInterval(5)
    }
}
