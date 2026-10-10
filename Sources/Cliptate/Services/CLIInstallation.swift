import Darwin
import Foundation

enum CLIInstallation {
  static var helperURL: URL {
    Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/cliptate")
  }

  static var installedURL: URL {
    let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
    return URL(fileURLWithPath: home).appendingPathComponent(".local/bin/cliptate")
  }

  static var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: helperURL.path) }
  static var isInstalled: Bool {
    installedURL.resolvingSymlinksInPath().standardizedFileURL == helperURL.standardizedFileURL
      && FileManager.default.isExecutableFile(atPath: installedURL.path)
  }

  static var installCommand: String {
    // ln without -f preserves any pre-existing command at this path.
    "mkdir -p \"$HOME/.local/bin\" && ln -s \(quote(helperURL.path)) \"$HOME/.local/bin/cliptate\""
  }

  static var uninstallCommand: String {
    "[ \"$(readlink \"$HOME/.local/bin/cliptate\")\" = \(quote(helperURL.path)) ] && rm \"$HOME/.local/bin/cliptate\""
  }

  static let pathCommand = "export PATH=\"$HOME/.local/bin:$PATH\""

  static func quote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }
}
