// hook-me-up-setup doctor [--settings <path>] [--app <path>] [--socket <path>] [--home <path>]
//
// Checks the app, its LaunchAgent, the running agent, the hooks in the settings and the
// notification settings; prints PASS / WARN / FAIL / SKIP / INFO lines with a fix for
// each problem. Exits 1 when a check failed (warnings don't). Changes nothing.
import DoctorKit
import Foundation
import HookMeUpCore

func runDoctor(_ arguments: [String]) -> Never {
    var arguments = arguments
    var values: [String: String] = [:]
    while let argument = arguments.first {
        arguments.removeFirst()
        switch argument {
        case "--settings", "--app", "--socket", "--home", "--codex-hooks":
            guard let value = arguments.first, !value.isEmpty else { fail("\(argument) needs a value\n\(usage)") }
            arguments.removeFirst()
            values[argument] = absolutePath(value)
        default:
            fail("unknown argument \(argument)\n\(usage)")
        }
    }
    let probe = SystemDoctorProbe()
    // An explicit --home always isolates both clients from this process's environment.
    let codexHooks = values["--codex-hooks"] ?? (values["--home"] == nil ? HookMeUpPaths.codexHooksURL().path : nil)
    let options = Doctor.Options.resolve(
        home: values["--home"], app: values["--app"], settings: values["--settings"], socket: values["--socket"],
        codexHooks: codexHooks,
        executablePath: Bundle.main.executablePath, realHome: HookMeUpPaths.homeDirectory.path, uid: getuid(),
        probe: probe)
    print("Hook Me Up doctor: \(options.app)\n")
    let report = Doctor.run(options, probe: probe)
    print(report.rendered())
    exit(report.exitCode)
}
