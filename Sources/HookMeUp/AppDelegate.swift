import AgentKit
import AppKit
import HookMeUpCore
import HookMeUpIPC

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AgentController?
    private var presenter: UserNotificationPresenter?
    private var statusMenu: StatusMenu?
    private var authorizationTimer: Timer?
    private var termSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // launchd stops agents with SIGTERM: quit cleanly so the socket file is removed
        // and waiting hooks see EOF (terminal dialog).
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
        source.resume()
        termSource = source

        let presenter = UserNotificationPresenter()
        let info = Bundle.main.infoDictionary
        let controller = AgentController(
            presenter: presenter, terminal: TerminalActivator(),
            version: info?["CFBundleShortVersionString"] as? String ?? "unknown",
            build: info?["CFBundleVersion"] as? String ?? "unknown")
        presenter.onResponse = { [weak controller] response, identifier, category in
            controller?.handle(response, identifier: identifier, categoryIdentifier: category)
        }
        do {
            try controller.start(socketPath: HookMeUpPaths.defaultSocketURL)
        } catch SocketError.alreadyRunning {
            AgentLog.info("another agent is already listening; exiting")
            NSApp.terminate(nil)
            return
        } catch {
            AgentLog.info("could not listen: \(error)")
            controller.reportStartError(String(describing: error))
        }
        statusMenu = StatusMenu(controller: controller)
        self.controller = controller
        self.presenter = presenter
        Task { await controller.prepareNotifications() }
        // Notices notifications turned off while requests wait (one settings query a
        // minute, only while something waits).
        let recheck = Timer(timeInterval: 60, repeats: true) { [weak controller] _ in
            MainActor.assumeIsolated { controller?.recheckAuthorization() }
        }
        RunLoop.main.add(recheck, forMode: .common)
        authorizationTimer = recheck
    }

    func applicationWillTerminate(_ notification: Notification) {
        authorizationTimer?.invalidate()
        controller?.stop()
        AgentLog.info("quit")
    }
}
