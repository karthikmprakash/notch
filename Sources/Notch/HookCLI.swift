import Foundation

/// Runs when the binary is invoked as `Notch --hook` from a Claude Code hook.
/// Reads the hook JSON on stdin, tells the app what Claude is doing, and — for
/// PermissionRequest — waits for the Allow/Deny decision and prints it back.
///
/// Nothing is printed unless you actually decided something, so Claude Code
/// falls back to its normal prompt when the island is not there.
enum HookCLI {
    static func run() -> Never {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard let root = try? JSONSerialization.jsonObject(with: input) as? [String: Any] else {
            exit(0)
        }

        let event = root["hook_event_name"] as? String ?? ""
        var message: [String: Any] = [
            "v": 1,
            "event": event,
            "session": root["session_id"] as? String ?? "",
            "ts": Date().timeIntervalSince1970
        ]
        if let tool = root["tool_name"] as? String { message["tool"] = tool }
        if let text = root["message"] as? String { message["message"] = text }
        if let type = root["notification_type"] as? String { message["notificationType"] = type }
        if let cwd = root["cwd"] as? String { message["cwd"] = cwd }

        let input2 = root["tool_input"] as? [String: Any] ?? [:]
        if let detail = detail(from: input2) { message["detail"] = detail }
        if let summary = summary(of: input2) { message["summary"] = summary }

        // Only a permission request needs an answer, and only that one waits.
        let waits = event == "PermissionRequest"
        if waits { message["id"] = UUID().uuidString }

        let line = (try? JSONSerialization.data(withJSONObject: message))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        let reply = UnixSocketServer.send(line,
                                         to: AppPaths.socket.path,
                                         waitForReply: waits ? 110 : 0)
        guard waits,
              let replyData = reply?.data(using: .utf8),
              let answer = try? JSONSerialization.jsonObject(with: replyData) as? [String: Any],
              let decision = answer["decision"] as? String else {
            exit(0)
        }

        // PermissionRequest decision schema (Claude Code 2.x).
        let output: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": [
                    "behavior": decision,
                    "message": decision == "deny" ? "Denied from the notch" : "Approved from the notch"
                ]
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: output),
           let text = String(data: data, encoding: .utf8) {
            print(text)
        }
        exit(0)
    }

    /// The whole command, never a shortened version: the island shows every
    /// character before you can approve it.
    private static func detail(from input: [String: Any]) -> String? {
        let preferred = ["command", "file_path", "path", "pattern", "query", "url", "prompt", "notebook_path"]
        for key in preferred {
            if let value = input[key] as? String, !value.isEmpty { return value }
        }
        if let edits = input["edits"] as? [[String: Any]], let first = edits.first,
           let path = first["file_path"] as? String {
            return path + "\n" + (first["new_string"] as? String ?? "")
        }
        if let content = input["content"] as? String, !content.isEmpty { return content }
        return nil
    }

    private static func summary(of input: [String: Any]) -> String? {
        if let description = input["description"] as? String, !description.isEmpty { return description }
        if let command = input["command"] as? String {
            return command.split(separator: "\n").first.map(String.init)
        }
        return nil
    }
}
