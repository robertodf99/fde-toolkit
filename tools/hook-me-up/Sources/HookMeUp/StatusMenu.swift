import AgentKit
import AppKit
import Combine
import HookMeUpCore

/// Minimal menu-bar item: count of pending entries, Pause 30 min / Resume, Quit.
/// Everything else is native notifications.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let controller: AgentController
    private let menu = NSMenu()
    private var cancellables = Set<AnyCancellable>()

    init(controller: AgentController) {
        self.controller = controller
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.image = MenuBarIcon.makeImage()
        statusItem.button?.imagePosition = .imageLeading
        controller.$store
            .receive(on: RunLoop.main)
            .sink { [weak self] store in self?.updateButton(store) }
            .store(in: &cancellables)
    }

    private func updateButton(_ store: PendingStore) {
        guard let button = statusItem.button else { return }
        let count = store.entries.count
        button.title = Self.buttonTitle(count: count, isPaused: controller.isPaused)
        button.toolTip = count == 0 ? "Hook Me Up: nothing waiting" : "Hook Me Up: \(count) waiting"
    }

    nonisolated static func buttonTitle(count: Int, isPaused: Bool) -> String {
        [count > 0 ? String(count) : nil, isPaused ? "⏸" : nil].compactMap { $0 }.joined(separator: " ")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let error = controller.startError {
            let item = NSMenuItem(title: "Not listening: \(error)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        }
        let pause =
            controller.isPaused
            ? NSMenuItem(title: "Resume", action: #selector(resume), keyEquivalent: "")
            : NSMenuItem(title: "Pause for 30 minutes", action: #selector(pauseNow), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Hook Me Up", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func pauseNow() { controller.pause(minutes: 30) }
    @objc private func resume() { controller.resume() }
    @objc private func quit() { NSApp.terminate(nil) }
}
