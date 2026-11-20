import Testing

@testable import TidyFixer

struct ProtectedTests {
    @Test func testChangedNumberAndKeptUrlAreFlagged() {
        let flags = Protected.flags(
            original: "Meet at 3:30 on May 4, see https://a.com/x.",
            revised: "Meet at 4:30 on May 4, see https://a.com/x")
        #expect(flags.count == 2)
        #expect(flags[0].contains("3:30"))
        #expect(flags[1].contains("4:30"))
    }

    @Test func testUnchangedProtectedTokensGiveNoFlags() {
        let flags = Protected.flags(original: "run `make test` at 5", revised: "Run `make test` at 5.")
        #expect(flags.isEmpty)
    }

    @Test func testCleanStripsEchoedTags() {
        #expect(OllamaRewriter.clean("<text>\nHi there\n</text>") == "Hi there")
    }

    @Test func testDiffMarksChangedWordOnly() {
        let segs = TextDiff.segments(old: "I wont go", new: "I won't go")
        #expect(segs.contains(DiffSegment(text: "wont ", kind: .removed)))
        #expect(segs.contains(DiffSegment(text: "won't ", kind: .added)))
        #expect(!segs.contains { $0.kind != .same && $0.text.contains("go") })
    }

    @Test func testDiffIgnoresQuoteStyle() {
        let segs = TextDiff.segments(old: "don\u{2019}t go", new: "don't go")
        #expect(segs.allSatisfy { $0.kind == .same })
    }

    @Test @MainActor func testSplitKeepsOnlyTheDraftAboveTheThread() {
        let dashes = BarViewModel.split("Hi Stacie,\nthanks\n---\nHi Wooseok,\nSure.\n")
        #expect(dashes.draft == "Hi Stacie,\nthanks")
        #expect(dashes.context?.hasSuffix("Sure.") == true)

        let reply = BarViewModel.split("Hi Chi,\n\nDo you think you can did it?\n\nOn Nov 6, 2026, at 1:01 AM, Wooseok <w@x.ca> wrote:\n\nHi Chi, ok.")
        #expect(reply.draft == "Hi Chi,\n\nDo you think you can did it?")
        #expect(reply.context?.hasPrefix("On Nov 6") == true)

        #expect(BarViewModel.split("no separator here").context == nil)
        #expect(BarViewModel.split("a - b -- c").draft == "a - b -- c")
        #expect(BarViewModel.split("From: someone\nbody").context == nil)  // nothing above it to edit
    }

    @Test func testRemovedWordsKeepTheirSpaces() {
        let segs = TextDiff.segments(old: "ok that I can make it on the week", new: "ok my week")
        #expect(segs.contains(DiffSegment(text: "that I can make it on the ", kind: .removed)))
    }

    @Test func testInvisibleCharactersDoNotCountAsChanges() {
        let segs = TextDiff.segments(old: "\u{200B}Hi Sam", new: "Hi Sam")
        #expect(segs.allSatisfy { $0.kind == .same })
    }

    @Test func testRemovedWordKeepsTheSpaceBeforeIt() {
        let segs = TextDiff.segments(old: "defer using memory at this moment.", new: "defer using memory.")
        #expect(segs.map(\.text).joined().hasPrefix("defer using memory"))
        #expect(segs.first?.kind == .same)
    }

    @Test @MainActor func testLoneDashesAfterTheDraftAreNotContext() {
        let parts = BarViewModel.split("Hi Sam!\nSee you then.\n---\n")
        #expect(parts.draft == "Hi Sam!\nSee you then.")
        #expect(parts.context == nil)
    }
}
