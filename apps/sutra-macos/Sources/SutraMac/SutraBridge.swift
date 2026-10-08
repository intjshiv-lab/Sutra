import Foundation
import AppKit

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
        // 3. Standard system locations
        let searchPaths = [
            "/usr/local/bin/sutra",
            "/opt/homebrew/bin/sutra",
            NSHomeDirectory() + "/.cargo/bin/sutra"
        ]
        for p in searchPaths where FileManager.default.fileExists(atPath: p) {
            return p
        }
        // 4. Default fallback
        return sibling
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

    public func capture(title: String, notes: String? = nil, cueType: String? = nil, dueAt: Date? = nil, tags: [String]? = nil, anchor: SutraAnchor? = nil) -> Bool {
        var args = ["capture", "--title", title]
        if let notes = notes, !notes.isEmpty {
            args.append(contentsOf: ["--notes", notes])
        }
        if let cueType = cueType, !cueType.isEmpty {
            args.append(contentsOf: ["-c", cueType])
        }
        if let tags = tags {
            for tag in tags {
                let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    args.append(contentsOf: ["--tag", trimmed])
                }
            }
        }
        if let anchor = anchor {
            // Forward anchor captured at HUD show time directly to CLI
            args.append("--no-sniff")
            if let app = anchor.app_name, !app.isEmpty {
                args.append(contentsOf: ["--app", app])
            }
            if let file = anchor.file_path, !file.isEmpty {
                args.append(contentsOf: ["--file", file])
            }
            if let line = anchor.line_number, line > 0 {
                args.append(contentsOf: ["--line", "\(line)"])
            }
            if let url = anchor.url, !url.isEmpty {
                args.append(contentsOf: ["--url", url])
            }
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

    public func updateThread(id: String, title: String, notes: String?, tags: [String]?, dueAt: Date? = nil) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        let escapedTitle = title.replacingOccurrences(of: "'", with: "''")
        let escapedNotes = (notes ?? "").replacingOccurrences(of: "'", with: "''")
        let tagsData = (try? JSONSerialization.data(withJSONObject: tags ?? [])) ?? Data("[]".utf8)
        let tagsJson = (String(data: tagsData, encoding: .utf8) ?? "[]").replacingOccurrences(of: "'", with: "''")
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let dueSql = (dueAt != nil) ? "\(Int64(dueAt!.timeIntervalSince1970 * 1000))" : "NULL"
        let sql = "UPDATE threads SET title = '\(escapedTitle)', notes = '\(escapedNotes)', tags_json = '\(tagsJson)', due_at = \(dueSql), updated_at = \(now) WHERE id = '\(id)';"
        task.arguments = [dbPath, sql]
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    public func setDueAt(threadId: String, dueAt: Int64?) -> Bool {
        let safeId = threadId.replacingOccurrences(of: "'", with: "''")
        guard safeId.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil else { return false }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        let val = dueAt != nil ? "\(dueAt!)" : "NULL"
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let sql = "UPDATE threads SET due_at = \(val), updated_at = \(now) WHERE id = '\(safeId)';"
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
        // Deep navigation check for Preview PDF files
        let allThreads = list(status: "waiting") + list(status: "later") + list(status: "done")
        if let target = allThreads.first(where: { $0.id == threadId }),
           let anchor = target.anchor,
           let filePath = anchor.file_path,
           filePath.lowercased().hasSuffix(".pdf"),
           let pageNum = anchor.line_number,
           pageNum > 0 {
            
            // Strategy 1: If browser URL with #page=N exists, open in default browser
            if let urlStr = anchor.url, urlStr.contains("#page="), let url = URL(string: urlStr) {
                if let browserUrl = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://apple.com")!) {
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = true
                    NSWorkspace.shared.open([url], withApplicationAt: browserUrl, configuration: config, completionHandler: nil)
                    _ = runCLI(args: ["resume", threadId])
                    return true
                }
            }

            // Strategy 2: Native Preview with robust activation retry loop
            let script = """
                set targetFile to "\(filePath)"
                set targetPage to "\(pageNum)"

                tell application "Preview"
                    activate
                    open POSIX file targetFile
                end tell

                repeat 30 times
                    delay 0.15
                    tell application "System Events"
                        if exists (process "Preview") then
                            tell process "Preview"
                                if not frontmost then
                                    set frontmost to true
                                end if
                                try
                                    if enabled of (menu item "Go to Page…" of menu "Go" of menu bar 1) then
                                        click menu item "Go to Page…" of menu "Go" of menu bar 1
                                        delay 0.15
                                        keystroke targetPage
                                        key code 36
                                        return "SUCCESS"
                                    end if
                                end try
                            end tell
                        end if
                    end tell
                end repeat
            """
            _ = runAppleScript(script)
            _ = runCLI(args: ["resume", threadId])
            return true
        }

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
        let safeId = threadId.replacingOccurrences(of: "'", with: "''")
        guard safeId.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil else { return false }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        let escapedNotes = notes.replacingOccurrences(of: "'", with: "''")
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let sql = "UPDATE threads SET notes = '\(escapedNotes)', updated_at = \(now) WHERE id = '\(safeId)';"
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
        // Native in-process macOS context sniffer (instant, zero-subprocess overhead)
        if let nativeAnchor = sniffFrontmostNative() {
            return nativeAnchor
        }
        let res = runCLI(args: ["sniff"])
        guard res.exitCode == 0, let data = res.output.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SutraAnchor.self, from: data)
    }

    private func sniffFrontmostNative() -> SutraAnchor? {
        // 1. Identify frontmost process name and window title
        let appScript = """
            tell application "System Events"
                set frontApp to first application process whose frontmost is true
                set pName to name of frontApp
                set winTitle to ""
                try
                    set winTitle to name of front window of frontApp
                end try
                return pName & "|||" & winTitle
            end tell
        """
        guard let appOut = runAppleScript(appScript), !appOut.isEmpty else { return nil }
        let parts = appOut.components(separatedBy: "|||")
        var appName = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        var winTitle = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""

        var anchor = SutraAnchor(
            app_name: appName,
            bundle_id: nil,
            url: nil,
            file_path: nil,
            line_number: nil,
            window_title: winTitle.isEmpty ? nil : winTitle
        )

        // 2. Browser Tab Extraction with Headless/Helper Filtering
        switch appName {
        case "Google Chrome", "Brave Browser", "Arc", "Chromium", "Microsoft Edge":
            let browserScript = """
                tell application "\(appName)"
                    -- 1. Try front window first
                    try
                        if (count of windows) > 0 then
                            set u to URL of active tab of front window
                            set t to title of active tab of front window
                            if u is not "" and u is not "about:blank" and u does not contain "mermaid-cli" then
                                return u & "|||" & t
                            end if
                        end if
                    end try

                    -- 2. Fallback: find topmost interactive user window
                    repeat with w in windows
                        try
                            set u to URL of active tab of w
                            set t to title of active tab of w
                            if u is not "" and u is not "about:blank" and u does not contain "mermaid-cli" then
                                return u & "|||" & t
                            end if
                        end try
                    end repeat

                    -- 3. Ultimate fallback: front window active tab
                    try
                        if (count of windows) > 0 then
                            return (URL of active tab of front window) & "|||" & (title of active tab of front window)
                        end if
                    end try
                    return ""
                end tell
            """
            if let bOut = runAppleScript(browserScript), !bOut.isEmpty {
                let bParts = bOut.components(separatedBy: "|||")
                if bParts.count == 2 && !bParts[0].isEmpty {
                    anchor.url = bParts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    anchor.window_title = bParts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

        case "Safari":
            let safariScript = """
                tell application "Safari"
                    if (count of documents) > 0 then
                        return (URL of front document) & "|||" & (name of front document)
                    end if
                end tell
            """
            if let sOut = runAppleScript(safariScript), !sOut.isEmpty {
                let sParts = sOut.components(separatedBy: "|||")
                if sParts.count == 2 {
                    anchor.url = sParts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    anchor.window_title = sParts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

        case "Preview":
            let previewScript = """
                set docPath to ""
                set docName to ""
                try
                    tell application "Preview"
                        if (count of documents) > 0 then
                            set docPath to path of front document
                            set docName to name of front document
                        end if
                    end tell
                on error
                end try

                set pageInfo to ""
                try
                    tell application "System Events"
                        if exists (process "Preview") then
                            tell process "Preview"
                                set winMenuItems to name of menu items of menu "Window" of menu bar 1
                                repeat with itemStr in winMenuItems
                                    if itemStr is not missing value then
                                        set s to itemStr as text
                                        if s contains "Page " or s contains "page " or (docName is not "" and s contains docName) then
                                            set pageInfo to s
                                            if s contains "Page " or s contains "page " then exit repeat
                                        end if
                                    end if
                                end repeat
                            end tell
                        end if
                    end tell
                on error
                end try

                return docPath & "|||" & pageInfo
            """
            if let pOut = runAppleScript(previewScript), !pOut.isEmpty {
                let parts = pOut.components(separatedBy: "|||")
                if parts.count >= 2 {
                    let docPath = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let pageInfo = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !docPath.isEmpty {
                        anchor.file_path = docPath
                        // Parse page number: e.g. "Doc.pdf (Page 11 of 15)" or "Page 11"
                        if let match = pageInfo.range(of: #"(?i)page\s+(\d+)"#, options: .regularExpression) {
                            let matchStr = String(pageInfo[match])
                            let digits = matchStr.filter { $0.isNumber }
                            if let pageNum = Int(digits) {
                                anchor.line_number = pageNum
                            }
                        }
                        
                        let baseName = URL(fileURLWithPath: docPath).lastPathComponent
                        if let p = anchor.line_number {
                            anchor.window_title = "\(baseName) (Page \(p))"
                            let fileUrl = URL(fileURLWithPath: docPath)
                            var comp = URLComponents(url: fileUrl, resolvingAgainstBaseURL: false)
                            comp?.fragment = "page=\(p)"
                            anchor.url = comp?.url?.absoluteString
                        } else {
                            anchor.window_title = pageInfo.isEmpty ? baseName : pageInfo
                            anchor.url = URL(fileURLWithPath: docPath).absoluteString
                        }
                    }
                }
            }

        case "Finder":
            let finderScript = """
                tell application "Finder"
                    if (count of Finder windows) > 0 then
                        try
                            return POSIX path of (target of front Finder window as alias)
                        end try
                    end if
                end tell
            """
            if let path = runAppleScript(finderScript), !path.isEmpty {
                anchor.file_path = path
                anchor.window_title = path
            }

        default:
            if let title = anchor.window_title, title.contains("/") {
                let tokens = title.components(separatedBy: .whitespaces)
                for t in tokens where t.hasPrefix("/") && FileManager.default.fileExists(atPath: t) {
                    anchor.file_path = t
                    break
                }
            }
        }

        return anchor
    }

    private func runAppleScript(_ script: String) -> String? {
        var error: NSDictionary?
        if let scriptObj = NSAppleScript(source: script) {
            let output = scriptObj.executeAndReturnError(&error)
            if error == nil, let val = output.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty {
                return val
            }
        }

        // Fallback: execute via /usr/bin/osascript process
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            if p.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
                    return str
                }
            }
        } catch {}
        return nil
    }
}
