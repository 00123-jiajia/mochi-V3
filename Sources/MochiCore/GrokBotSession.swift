import CryptoKit
import Darwin
import Foundation

/// Grok Bot.app runs its agent off this Mac and does not execute `~/.grok/hooks`.
/// While Connect is on, the capsule follows the session store that app writes locally.
/// Only a short question and a capped answer are copied onto the card.
public enum GrokBotSession {
    public static let origin = "grok-session"

    public static func persistenceDirectory(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Grok Bot/sand-client-persistence", isDirectory: true)
    }

    public static func appIsInstalled(fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: "/Applications/Grok Bot.app/Contents/Info.plist")
    }

    /// Publishes recent Grok Bot turns into the shared task file. Other agents' tasks stay put.
    public static func sync(directory: URL, tasksURL: URL, now: Double, maxAge: Double = AppConfig.iconMaxAge) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return
        }
        let turns = readTurns(directory: directory, now: now, maxAge: maxAge)
        withLock(tasksURL) {
            var root = readRoot(tasksURL)
            var tasks = root["tasks"] as? [String: Any] ?? [:]
            let before = encode(tasks)
            let incoming = Set(turns.map(\.id))
            for key in Array(tasks.keys) {
                guard let record = tasks[key] as? [String: Any], record["origin"] as? String == origin else { continue }
                let id = (record["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? key
                if !incoming.contains(id) {
                    tasks.removeValue(forKey: key)
                }
            }
            for turn in turns {
                let previous = tasks[turn.id] as? [String: Any]
                tasks[turn.id] = record(turn, previous: previous, now: now)
            }
            guard encode(tasks) != before else { return }
            root["tasks"] = tasks
            try? AtomicFile.writeJSON(root, to: tasksURL)
        }
    }

    public static func remove(tasksURL: URL) {
        withLock(tasksURL) {
            var root = readRoot(tasksURL)
            var tasks = root["tasks"] as? [String: Any] ?? [:]
            let before = encode(tasks)
            for key in Array(tasks.keys) {
                guard let record = tasks[key] as? [String: Any], record["origin"] as? String == origin else { continue }
                tasks.removeValue(forKey: key)
            }
            guard encode(tasks) != before else { return }
            root["tasks"] = tasks
            try? AtomicFile.writeJSON(root, to: tasksURL)
        }
    }

    private struct Turn {
        var id: String
        var summary: String
        var answer: String
        var status: String
        var updated: Double
    }

    private static func readTurns(directory: URL, now: Double, maxAge: Double) -> [Turn] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        var turns: [Turn] = []
        for name in names where !name.hasPrefix(".") {
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let value = root["value"] as? [String: Any],
                  let entries = value["entries"] as? [Any],
                  let turn = turn(from: entries, id: stableID(name), now: now, maxAge: maxAge) else { continue }
            turns.append(turn)
        }
        return turns
    }

    /// The question is the latest text the user sent. The answer is the latest assistant message after it.
    private static func turn(from entries: [Any], id: String, now: Double, maxAge: Double) -> Turn? {
        var summary = ""
        var answer = ""
        var askedAt = 0.0
        var answeredAt = 0.0
        var lastSpeaker = ""
        var streaming = false
        for entry in entries {
            guard let item = entry as? [String: Any] else { continue }
            let at = seconds(item["timestampMs"])
            switch item["kind"] as? String {
            case "send-message":
                guard let message = item["message"] as? [String: Any],
                      message["type"] as? String == "text",
                      let text = trimmed(message["content"]), !text.isEmpty else { continue }
                summary = text
                askedAt = at
                lastSpeaker = "user"
                streaming = false
            case "message":
                guard item["role"] as? String == "assistant" else { continue }
                if let text = trimmed(item["content"]), !text.isEmpty {
                    answer = text
                    answeredAt = at
                }
                lastSpeaker = "assistant"
                streaming = (item["isStreaming"] as? Bool) == true
            default:
                continue
            }
        }
        guard !summary.isEmpty, !lastSpeaker.isEmpty else { return nil }
        let waiting = lastSpeaker == "user" || streaming
        let updated = waiting ? askedAt : max(askedAt, answeredAt)
        guard updated > 0 else { return nil }
        if waiting {
            guard now - updated <= AppConfig.liveKeep else { return nil }
        } else if now - updated > maxAge {
            return nil
        }
        let storedAnswer = waiting && lastSpeaker == "user" ? "" : PermissionCopy.cardAnswer(answer)
        return Turn(
            id: id,
            summary: PermissionCopy.abbreviate(summary),
            answer: storedAnswer,
            status: waiting ? "running" : "done",
            updated: waiting ? now : updated
        )
    }

    /// A running card stays in the working window. Leave its timestamp alone until that window is nearly over.
    private static func record(_ turn: Turn, previous: [String: Any]?, now: Double) -> [String: Any] {
        var updated = turn.updated
        if turn.status == "running",
           let previous,
           previous["status"] as? String == "running",
           previous["summary"] as? String == turn.summary,
           let prior = (previous["updated"] as? NSNumber)?.doubleValue,
           now - prior < AppConfig.activeTaskWindow - 30 {
            updated = prior
        }
        var record: [String: Any] = [
            "id": turn.id,
            "title": "Grok Bot",
            "status": turn.status,
            "source": "grok-bot",
            "updated": updated,
            "detail": "Chat",
            "origin": origin
        ]
        if !turn.summary.isEmpty { record["summary"] = turn.summary }
        if !turn.answer.isEmpty { record["answer"] = turn.answer }
        return record
    }

    private static func stableID(_ name: String) -> String {
        let digest = Array(SHA256.hash(data: Data(name.utf8)))
        let hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        let a = hex.prefix(8)
        let b = hex.dropFirst(8).prefix(4)
        let c = hex.dropFirst(12).prefix(4)
        let d = hex.dropFirst(16).prefix(4)
        let e = hex.dropFirst(20).prefix(12)
        return "\(a)-\(b)-\(c)-\(d)-\(e)"
    }

    private static func seconds(_ value: Any?) -> Double {
        guard let number = value as? NSNumber else { return 0 }
        let raw = number.doubleValue
        if raw > 1_000_000_000_000 { return raw / 1000 }
        return raw
    }

    private static func trimmed(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func readRoot(_ url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["tasks": [String: Any]()]
        }
        return root
    }

    private static func encode(_ tasks: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: tasks, options: [.sortedKeys])) ?? Data()
    }

    private static func withLock(_ url: URL, _ body: () -> Void) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(url.appendingPathExtension("lock").path, O_CREAT | O_RDWR, 0o644)
        if fd >= 0 { flock(fd, LOCK_EX) }
        body()
        if fd >= 0 {
            flock(fd, LOCK_UN)
            close(fd)
        }
    }
}
