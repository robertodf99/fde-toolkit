// hook-me-up-setup install|uninstall|doctor|notifications (see `usage`).
//
// install / uninstall add or remove Hook Me Up's hooks in a Claude Code settings file
// (SettingsCommand.swift); doctor checks an installation and says how to fix it
// (DoctorCommand.swift); notifications is the installer's notification check
// (NotificationsCommand.swift).
import Foundation

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail(usage) }
arguments.removeFirst()

switch command {
case "install", "uninstall": runSettingsCommand(command, arguments)
case "doctor": runDoctor(arguments)
case "notifications": runNotifications(arguments)
case "help", "--help", "-h": print(usage)
default: fail(usage)
}
