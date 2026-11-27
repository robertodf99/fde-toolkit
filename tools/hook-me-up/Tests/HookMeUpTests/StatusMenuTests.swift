import AppKit
import Testing

@testable import HookMeUp

@Suite struct StatusMenuTests {
    @Test func titleContainsOnlyTheCountAndPauseIndicator() {
        for (count, isPaused, expected) in [(0, false, ""), (3, false, "3"), (0, true, "⏸"), (12, true, "12 ⏸")] {
            #expect(StatusMenu.buttonTitle(count: count, isPaused: isPaused) == expected)
        }
    }

    @Test func hookImageIsATemplateAtMenuBarSize() {
        let image = MenuBarIcon.makeImage()
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 14, height: 18))
    }
}
