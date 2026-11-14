// hook-me-up-setup notifications [--wait <seconds>] [--test]
//                                [--open-settings | --open-settings-if-off]
//                                [--socket <path>] [--result-file <path>]
//
// For the installer, right after it starts the agent: waits up to --wait seconds for the
// agent and for an answer to macOS's notification question, says what the notification
// settings are, shows a test notification (--test) and opens System Settings when they
// need changing (--open-settings: unless allowed with the style Alerts;
// --open-settings-if-off: only when not allowed). Never reads stdin. Writes how it ended
// to --result-file (ready, not-alerts, off, undecided, old-agent, no-agent). Exits 0
// except for a bad argument.
import DoctorKit
import Foundation
import HookMeUpCore

func runNotifications(_ arguments: [String]) -> Never {
    var arguments = arguments
    var wait: TimeInterval = 0
    var test = false
    var openSettings = NotificationOnboarding.OpenSettings.never
    var socket = HookMeUpPaths.defaultSocketURL
    var resultFile: String?
    while let argument = arguments.first {
        arguments.removeFirst()
        switch argument {
        case "--test": test = true
        case "--open-settings": openSettings = .unlessAlerts
        case "--open-settings-if-off": openSettings = .whenOff
        case "--wait", "--socket", "--result-file":
            guard let value = arguments.first, !value.isEmpty else { fail("\(argument) needs a value\n\(usage)") }
            arguments.removeFirst()
            switch argument {
            case "--wait":
                guard let seconds = Int(value), seconds >= 0 else { fail("--wait must be a number of seconds") }
                wait = TimeInterval(seconds)
            case "--socket": socket = URL(fileURLWithPath: absolutePath(value))
            default: resultFile = absolutePath(value)
            }
        default:
            fail("unknown argument \(argument)\n\(usage)")
        }
    }
    let outcome = NotificationOnboarding.run(
        NotificationOnboarding.Options(wait: wait, test: test, openSettings: openSettings),
        io: SystemOnboardingIO(socket: socket))
    if let resultFile {
        try? Data((outcome.rawValue + "\n").utf8).write(to: URL(fileURLWithPath: resultFile), options: .atomic)
    }
    exit(0)
}
