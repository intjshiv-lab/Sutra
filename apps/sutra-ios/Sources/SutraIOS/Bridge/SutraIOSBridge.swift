import Foundation

public struct SutraThread: Identifiable, Codable {
    public var id: String
    public var title: String
    public var notes: String?
    public var status: String
    public var dueAt: Int64?
    public var appName: String?
    public var createdAt: Int64

    public init(id: String = UUID().uuidString, title: String, notes: String? = nil, status: String = "waiting", dueAt: Int64? = nil, appName: String? = nil, createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.id = id
        self.title = title
        self.notes = notes
        self.status = status
        self.dueAt = dueAt
        self.appName = appName
        self.createdAt = createdAt
    }
}

public final class SutraIOSBridge: ObservableObject {
    public static let shared = SutraIOSBridge()

    @Published public var waitingThreads: [SutraThread] = []
    @Published public var todayThreads: [SutraThread] = []
    @Published public var doneThreads: [SutraThread] = []

    private init() {
        loadMockData()
    }

    public func addThread(title: String, notes: String?, dueAt: Int64?) {
        let thread = SutraThread(title: title, notes: notes, dueAt: dueAt)
        waitingThreads.insert(thread, at: 0)
        filterTodayThreads()
    }

    private func filterTodayThreads() {
        let startOfDay = Int64(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970 * 1000)
        let endOfDay = startOfDay + (24 * 60 * 60 * 1000)
        todayThreads = waitingThreads.filter { t in
            guard let due = t.dueAt else { return false }
            return due >= startOfDay && due < endOfDay
        }
    }

    private func loadMockData() {
        let sample = [
            SutraThread(title: "Review Rust FFI memory layout", notes: "Check 64-bit alignment across boundaries", appName: "Safari"),
            SutraThread(title: "Plan WinUI 3 Native AOT pipeline", notes: "Ensure zero runtime prerequisites on clean install", appName: "Notes")
        ]
        waitingThreads = sample
        filterTodayThreads()
    }
}
