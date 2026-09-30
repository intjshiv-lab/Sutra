import Foundation

public final class SutraBridge {
    public static let shared = SutraBridge()

    public var sutraBinPath: String {
        // 1. App Bundle Resources/Helpers
        if let bundleHelper = Bundle.main.path(forResource: "sutra", ofType: nil) {
            return bundleHelper
        }
        // 2. Sibling directory to Sutra.app (e.g. dev environment)
        let sibling = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("sutra").path
        if FileManager.default.fileExists(atPath: sibling) {
            return sibling
        }
        // 3. /usr/local/bin
        if FileManager.default.fileExists(atPath: "/usr/local/bin/sutra") {
            return "/usr/local/bin/sutra"
        }
        // 4. Default fallback
        return "/Users/raman/Desktop/AI/Sutra/bin/sutra"
    }

    public var dbPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.sutra/sutra.db"
    }

    private func runCLI(args: [String]) -> (output: String, exitCode: Int32) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: sutraBinPath)
        task.arguments = args

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (output, task.terminationStatus)
        } catch {
            return ("", -1)
        }
    }

    public func list(status: String = "waiting") -> [SutraThread] {
        let res = runCLI(args: ["list", "--status", status, "--json"])
        guard res.exitCode == 0, let data = res.output.data(using: .utf8) else {
            return []
        }
        return (try? JSONDecoder().decode([SutraThread].self, from: data)) ?? []
    }

    public func capture(title: String, notes: String? = nil, cueType: String? = nil, dueAt: Date? = nil) -> Bool {
        var args = ["capture", "--title", title]
        if let notes = notes, !notes.isEmpty {
            args.append(contentsOf: ["--notes", notes])
        }
        if let cueType = cueType, !cueType.isEmpty {
            args.append(contentsOf: ["-c", cueType])
        }
        let res = runCLI(args: args)
        guard res.exitCode == 0 else { return false }
        if let dueAt = dueAt {
            let lines = res.output.components(separatedBy: .newlines)
            if let idLine = lines.first(where: { $0.contains("ID:") }) {
                let id = idLine.replacingOccurrences(of: "ID:", with: "").trimmingCharacters(in: .whitespaces)
                let epochMs = Int64(dueAt.timeIntervalSince1970 * 1000)
                _ = setDueAt(threadId: id, dueAt: epochMs)
            }
        }
        return true
    }

    public func setDueAt(threadId: String, dueAt: Int64?) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        let val = dueAt != nil ? "\(dueAt!)" : "NULL"
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let sql = "UPDATE threads SET due_at = \(val), updated_at = \(now) WHERE id = '\(threadId)';"
        task.arguments = [dbPath, sql]
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    public func resume(threadId: String) -> Bool {
        return runCLI(args: ["resume", threadId]).exitCode == 0
    }

    public func snooze(threadId: String, hours: Int = 4) -> Bool {
        return runCLI(args: ["snooze", threadId, "--hours", "\(hours)"]).exitCode == 0
    }

    public func done(threadId: String) -> Bool {
        return runCLI(args: ["done", threadId]).exitCode == 0
    }

    public func undo(threadId: String) -> Bool {
        return runCLI(args: ["undo", threadId]).exitCode == 0
    }

    public func updateNotes(threadId: String, notes: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        let escapedNotes = notes.replacingOccurrences(of: "'", with: "''")
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let sql = "UPDATE threads SET notes = '\(escapedNotes)', updated_at = \(now) WHERE id = '\(threadId)';"
        task.arguments = [dbPath, sql]
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    public func sniff() -> SutraAnchor? {
        let res = runCLI(args: ["sniff"])
        guard res.exitCode == 0, let data = res.output.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SutraAnchor.self, from: data)
    }
}
