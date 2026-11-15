import Foundation
import Testing

@testable import TidyFixer

final class FakeRewriter: TextRewriter, @unchecked Sendable {
    var warmCalls = 0
    var unloadCalls = 0
    var warmDelay: UInt64 = 0
    var serverExpiry: Date?

    func rewrite(_ text: String, context: String?, profile: Profile) async throws -> String { text }
    func warm() async throws {
        warmCalls += 1
        try? await Task.sleep(nanoseconds: warmDelay)
    }
    func unload() async { unloadCalls += 1 }
    func expiresAt() async -> Date? { serverExpiry }
    func unloadAtQuit(ourExpiry: Date?) { quitUnloads += 1 }
    var quitUnloads = 0
}

@MainActor
struct ModelLifecycleTests {
    @Test func warmUpIsDeduplicated() async {
        let fake = FakeRewriter()
        fake.warmDelay = 50_000_000
        let life = ModelLifecycle(rewriter: fake)
        life.warm()
        life.warm()
        await life.waitUntilWarm()
        #expect(fake.warmCalls == 1)
        #expect(life.state == .ready)
    }

    @Test func barClosedDuringColdLoadUnloadsWhenItFinishes() async {
        let fake = FakeRewriter()
        fake.warmDelay = 50_000_000
        let life = ModelLifecycle(rewriter: fake)
        life.warm()
        life.barClosed()
        await life.waitUntilWarm()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(fake.unloadCalls == 1)
        #expect(life.state == .unloaded)
    }

    @Test func criticalPressureWaitsForActiveRequest() async throws {
        let fake = FakeRewriter()
        let life = ModelLifecycle(rewriter: fake)
        try await life.use {
            life.pressureChanged(.critical)
            #expect(fake.unloadCalls == 0)
        }
        #expect(fake.unloadCalls == 1)
    }

    @Test func modelUsedByAnotherClientIsNotUnloaded() async throws {
        let fake = FakeRewriter()
        let life = ModelLifecycle(rewriter: fake)
        try await life.use {}
        fake.serverExpiry = Date().addingTimeInterval(3600)
        life.pressureChanged(.warning)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(fake.unloadCalls == 0)
    }

    @Test func quitUnloadsOnlyWhenTheSettingIsOnAndTheModelIsWarm() async throws {
        let defaults = UserDefaults.standard
        defer { defaults.removeObject(forKey: "unloadOnQuit") }
        let fake = FakeRewriter()
        let life = ModelLifecycle(rewriter: fake)
        try await life.use {}
        life.shutdown()
        #expect(fake.quitUnloads == 0)  // default is off
        defaults.set(true, forKey: "unloadOnQuit")
        life.shutdown()
        #expect(fake.quitUnloads == 1)
        let cold = FakeRewriter()
        ModelLifecycle(rewriter: cold).shutdown()
        #expect(cold.quitUnloads == 0)
    }

    @Test func noWarmUpUnderPressure() async {
        let fake = FakeRewriter()
        let life = ModelLifecycle(rewriter: fake)
        life.pressureChanged(.warning)
        life.warm()
        await life.waitUntilWarm()
        #expect(fake.warmCalls == 0)
    }
}
