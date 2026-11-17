import CryptoKit
import Foundation

/// Codex runs a command hook only when `hooks.state` stores the hash of that hook.
/// A file on disk is not enough: a changed command stays installed and does not run.
public enum CodexHookTrust {
    /// Snake-case key Codex uses in `hooks.state` and in the trust hash.
    /// Events outside Codex's loader return nil.
    public static func eventKey(for pascalName: String) -> String? {
        switch pascalName {
        case "PreToolUse": return "pre_tool_use"
        case "PermissionRequest": return "permission_request"
        case "PostToolUse": return "post_tool_use"
        case "PreCompact": return "pre_compact"
        case "PostCompact": return "post_compact"
        case "PreModelRequest": return "pre_model_request"
        case "PostModelRequest": return "post_model_request"
        case "SessionStart": return "session_start"
        case "SessionEnd": return "session_end"
        case "UserPromptSubmit": return "user_prompt_submit"
        case "SubagentStart": return "subagent_start"
        case "SubagentStop": return "subagent_stop"
        case "Stop": return "stop"
        case "Interrupt": return "interrupt"
        default: return nil
        }
    }

    /// SessionEnd and Interrupt are clamped to 1...3 seconds. Every other event keeps its timeout, at least 1.
    public static func normalizedTimeout(eventKey: String, fileTimeout: Int) -> Int {
        if eventKey == "session_end" || eventKey == "interrupt" {
            return min(max(fileTimeout, 1), 3)
        }
        return max(fileTimeout, 1)
    }

    /// `sha256:` plus the hash Codex stores in `trusted_hash`.
    public static func identityHash(eventKey: String, command: String, fileTimeout: Int) -> String {
        let timeout = normalizedTimeout(eventKey: eventKey, fileTimeout: fileTimeout)
        let commandJSON = jsonString(command)
        let json = "{\"event_name\":\"\(eventKey)\",\"hooks\":[{\"async\":false,\"command\":\(commandJSON),\"timeout\":\(timeout),\"type\":\"command\"}]}"
        let digest = SHA256.hash(data: Data(json.utf8))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Rewrites only the listed hook-state tables. A document that already trusts them is returned unchanged.
    public static func configByTrusting(_ contents: String, entries: [(key: String, hash: String)]) -> String {
        if entries.isEmpty { return contents }
        if alreadyTrusts(contents, entries: entries) { return contents }
        let newline = contents.contains("\r\n") ? "\r\n" : "\n"
        let keys = Set(entries.map(\.key))
        var lines = contents.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        if contents.hasSuffix("\n") || contents.hasSuffix("\r\n"), lines.last == "" {
            lines.removeLast()
        }
        var kept: [String] = []
        var index = 0
        while index < lines.count {
            if let key = stateKey(in: lines[index]), keys.contains(key) {
                index += 1
                while index < lines.count, stateKey(in: lines[index]) == nil, !isTableHeader(lines[index]) {
                    index += 1
                }
                continue
            }
            kept.append(lines[index])
            index += 1
        }
        while kept.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            kept.removeLast()
        }
        var text = kept.joined(separator: newline)
        if !text.isEmpty { text += newline + newline }
        let sorted = entries.sorted { $0.key < $1.key }
        for entry in sorted {
            text += "[hooks.state.\"\(escaped(entry.key))\"]" + newline
            text += "enabled = true" + newline
            text += "trusted_hash = \"\(entry.hash)\"" + newline
            text += newline
        }
        return text
    }

    private static func alreadyTrusts(_ contents: String, entries: [(key: String, hash: String)]) -> Bool {
        for entry in entries {
            guard let body = sectionBody(contents, key: entry.key) else { return false }
            if !body.contains("trusted_hash = \"\(entry.hash)\"") { return false }
            if body.contains("enabled = false") { return false }
        }
        return true
    }

    private static func sectionBody(_ contents: String, key: String) -> String? {
        let lines = contents.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        guard let start = lines.firstIndex(where: { stateKey(in: $0) == key }) else { return nil }
        var body: [String] = []
        var index = start + 1
        while index < lines.count, stateKey(in: lines[index]) == nil, !isTableHeader(lines[index]) {
            body.append(lines[index])
            index += 1
        }
        return body.joined(separator: "\n")
    }

    private static func stateKey(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let prefix = "[hooks.state.\""
        guard trimmed.hasPrefix(prefix), trimmed.hasSuffix("\"]") else { return nil }
        let start = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
        let end = trimmed.index(trimmed.endIndex, offsetBy: -2)
        guard start <= end else { return nil }
        return String(trimmed[start..<end]).replacingOccurrences(of: "\\\"", with: "\"")
    }

    private static func isTableHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
    }

    private static func escaped(_ key: String) -> String {
        key.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Codex hashes the command with slashes left intact. Foundation's JSON writer escapes them.
    private static func jsonString(_ value: String) -> String {
        var encoded = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": encoded += "\\\\"
            case "\"": encoded += "\\\""
            case "\n": encoded += "\\n"
            case "\r": encoded += "\\r"
            case "\t": encoded += "\\t"
            default:
                if scalar.value < 0x20 {
                    encoded += String(format: "\\u%04x", scalar.value)
                } else {
                    encoded.unicodeScalars.append(scalar)
                }
            }
        }
        encoded += "\""
        return encoded
    }
}
