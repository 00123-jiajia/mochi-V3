import Darwin
import Foundation
import MochiCore

let stateURL = AppConfig.cursorDirectory.appendingPathComponent("mochi-island-tasks.json")

func emit(_ object: Any) {
    let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func readStdin() -> [String: Any] {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard !data.isEmpty,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return [:]
    }
    return json
}

func argumentValue(_ name: String) -> String? {
    let args = Array(CommandLine.arguments.dropFirst())
    var index = 0
    while index < args.count {
        if args[index] == name, index + 1 < args.count {
            return args[index + 1]
        }
        index += 1
    }
    return nil
}

func withLock(_ body: () -> Void) {
    try? FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let lockURL = stateURL.appendingPathExtension("lock")
    let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
    if fd >= 0 {
        flock(fd, LOCK_EX)
        body()
        flock(fd, LOCK_UN)
        close(fd)
    } else {
        body()
    }
}

func run() {
    let payload = readStdin()
    let outcome = HookEvents.interpret(
        sourceFlag: argumentValue("--source"),
        payload: payload,
        environment: ProcessInfo.processInfo.environment,
        eventFlag: argumentValue("--event")
    )
    if let outcome {
        withLock {
            HookEvents.commit(outcome, tasksURL: stateURL)
            // Shell and MCP continue at once. The card does not stay on Allow / Deny.
            if outcome.waitsForPermission {
                HookEvents.acknowledge(
                    id: outcome.id,
                    requestID: outcome.requestID,
                    tasksURL: stateURL
                )
            }
        }
        if outcome.waitsForPermission {
            emit(HookEvents.permissionStdout(style: outcome.permissionStyle, action: "allow"))
            return
        }
    }
    emit([:] as [String: Any])
}

run()
exit(0)
