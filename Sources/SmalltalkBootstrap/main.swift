import Foundation
import SmalltalkCore

let arguments = CommandLine.arguments.dropFirst()
let positional = arguments.filter { $0 != "--check" }
guard positional.count == 1, let directory = positional.first else {
    FileHandle.standardError.write(Data("Aufruf: st80-bootstrap [--check] <Library-Ordner>\n".utf8))
    exit(2)
}
do {
    try SmalltalkBootstrap.rebuild(
        in: URL(fileURLWithPath: directory, isDirectory: true),
        checkOnly: arguments.contains("--check")
    ) { message in
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
    print("Smalltalk-Selbstbau erfolgreich.")
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
