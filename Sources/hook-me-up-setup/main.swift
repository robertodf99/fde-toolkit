// hook-me-up-setup install|uninstall|doctor (see `usage`).
//
// install / uninstall add or remove Hook Me Up's hooks in a Claude Code settings file
// (SettingsCommand.swift); doctor checks an installation and says how to fix it
// (DoctorCommand.swift).
import Foundation

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail(usage) }
arguments.removeFirst()

switch command {
case "install", "uninstall": runSettingsCommand(command, arguments)
case "doctor": runDoctor(arguments)
case "help", "--help", "-h": print(usage)
default: fail(usage)
}
