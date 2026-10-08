import Foundation

public struct SutraAnchor: Codable {
    public var app_name: String?
    public var bundle_id: String?
    public var url: String?
    public var file_path: String?
    public var line_number: Int?
    public var window_title: String?
}

public struct SutraThread: Codable, Identifiable {
    public let id: String
    public let cue_type: String
    public let title: String
    public let notes: String?
    public let status: String
    public let created_at: Double
    public let updated_at: Double
    public let due_at: Double?
    public let snoozed_until: Double?
    public let anchor: SutraAnchor?
    public let device_origin: String?
    public let tags: [String]?

    public var dueDate: Date? {
        guard let due = due_at, due > 0 else { return nil }
        return Date(timeIntervalSince1970: due / 1000.0)
    }

    public var isScheduledForToday: Bool {
        guard let date = dueDate else { return false }
        return Calendar.current.isDateInToday(date)
    }

    public var formattedDueDate: String? {
        guard let date = dueDate else { return nil }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return df.string(from: date)
    }

    public var cueIcon: String {
        switch cue_type.lowercased() {
        case "checklist": return "✓"
        case "url", "link": return "↗"
        case "file": return "▤"
        case "link_file": return "↗"
        case "voice": return "●"
        default: return "—"
        }
    }

    public struct ChecklistItem {
        public var isDone: Bool
        public var text: String
    }

    public var checklistItems: [ChecklistItem] {
        guard cue_type.lowercased() == "checklist", let raw = notes, !raw.isEmpty else { return [] }
        var items: [ChecklistItem] = []
        let lines = raw.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("[x]") || trimmed.hasPrefix("[X]") {
                let text = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                items.append(ChecklistItem(isDone: true, text: text))
            } else if trimmed.hasPrefix("[ ]") {
                let text = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                items.append(ChecklistItem(isDone: false, text: text))
            } else {
                items.append(ChecklistItem(isDone: false, text: trimmed))
            }
        }
        return items
    }

    public var cueSummaryBadge: (label: String, count: String?) {
        switch cue_type.lowercased() {
        case "checklist":
            let items = checklistItems
            if items.isEmpty { return ("Checklist", nil) }
            let completed = items.filter { $0.isDone }.count
            return ("Checklist", "\(completed)/\(items.count)")
        case "url", "link":
            return ("Link", nil)
        case "file":
            return ("File", nil)
        case "link_file":
            return ("Link/File", nil)
        case "voice":
            return ("Voice", nil)
        default:
            return ("Note", nil)
        }
    }

    public var timeAgo: String {
        let createdSec = created_at > 1e11 ? created_at / 1000.0 : created_at
        let diff = max(0, Date().timeIntervalSince1970 - createdSec)
        if diff < 60 { return "now" }
        if diff < 3600 { return "\(Int(diff / 60))m" }
        if diff < 86400 { return "\(Int(diff / 3600))h" }
        let days = max(1, Int(ceil(diff / 86400.0)))
        return "\(days)d"
    }

    public var originDisplay: String {
        var parts: [String] = []
        if let app = anchor?.app_name, !app.isEmpty {
            parts.append(app)
        }
        if let url = anchor?.url, let host = URL(string: url)?.host {
            parts.append(host)
        } else if let title = anchor?.window_title, !title.isEmpty {
            parts.append(title.count > 25 ? String(title.prefix(22)) + "..." : title)
        }
        return parts.joined(separator: " • ")
    }
}
