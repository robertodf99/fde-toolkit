import Foundation
import Testing

@testable import HookMeUpCore

@Suite struct HerdrTests {
    @Test func sessionUnderCoreBelongsToHerdr() {
        let owner = TerminalMapping.owner(
            ancestors: [
                (30, "/test/claude"), (29, "/bin/zsh"),
                (20, "/test/Herdr Core.app/Contents/MacOS/herdr-core"), (10, "/test/herdr-core"),
            ], bundleID: { $0 == "/test/Herdr Core.app" ? "dev.herdr.core" : nil })
        #expect(owner == TerminalMapping.Owner(bundleID: "dev.herdr.core", appPath: "/test/Herdr Core.app", pid: 20))
    }

    @Test(arguments: ["dev.herdr.core", "dev.herdr.app"])
    func herdrIsAKnownTerminal(_ bundleID: String) {
        #expect(TerminalApp(bundleID: bundleID) == .herdr)
        #expect(TerminalApp(bundleID: bundleID)?.selectsTabByTTY == false)
    }

    @Test func terminalHintPreservesHerdrTerminal() throws {
        let data = Data(#"{"ancestorPIDs":[12,11],"tty":"ttys003","herdrTerminal":"test-pane_1"}"#.utf8)
        let hint = try JSONDecoder().decode(TerminalHint.self, from: data)
        let encoded = try JSONEncoder().encode(hint)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["herdrTerminal"] as? String == "test-pane_1")
    }

    @Test func olderTerminalHintsStillDecode() throws {
        let data = Data(#"{"ancestorPIDs":[12,11],"tty":"ttys003"}"#.utf8)
        let hint = try JSONDecoder().decode(TerminalHint.self, from: data)
        #expect(hint == TerminalHint(ancestorPIDs: [12, 11], tty: "ttys003"))
        #expect(hint.herdrTerminal == nil)
    }

    @Test(arguments: ["t", "test-pane_1", "AZaz09_-", String(repeating: "a", count: 64)])
    func acceptsOnlyPlainTerminalIDs(_ id: String) {
        #expect(HerdrTerminal.validID(id) == id)
    }

    @Test(arguments: [nil, "", "a b", "a\n", "a\r", "é", "a/b", "$(id)", "a;id", String(repeating: "a", count: 65)])
    func rejectsInvalidTerminalIDs(_ id: String?) {
        #expect(HerdrTerminal.validID(id) == nil)
    }
}
