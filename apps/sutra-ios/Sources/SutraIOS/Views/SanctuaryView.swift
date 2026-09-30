import SwiftUI

public struct SanctuaryView: View {
    @StateObject private var bridge = SutraIOSBridge.shared
    @State private var searchText = ""
    @State private var isTodayExpanded = true

    public init() {}

    public var body: some View {
        List {
            // "Scheduled for Today" Collapsible Accordion
            Section(isExpanded: $isTodayExpanded) {
                if bridge.todayThreads.isEmpty {
                    Text("No threads scheduled for today")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(bridge.todayThreads) { thread in
                        ThreadRowView(thread: thread)
                    }
                }
            } header: {
                HStack {
                    Text("📅 Scheduled for Today")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(red: 179/255, green: 86/255, blue: 42/255))
                    Spacer()
                    Text("(\(bridge.todayThreads.count))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Active Waiting Threads Section
            Section("Active Working Memory (\(bridge.waitingThreads.count))") {
                if bridge.waitingThreads.isEmpty {
                    Text("All caught up. No waiting threads.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(bridge.waitingThreads) { thread in
                        ThreadRowView(thread: thread)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search threads...")
        .navigationTitle("Sutra Sanctuary")
    }
}

struct ThreadRowView: View {
    let thread: SutraThread

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(thread.title)
                .font(.body)
                .fontWeight(.medium)
            
            if let notes = thread.notes, !notes.isEmpty {
                Text(notes)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            
            if let app = thread.appName {
                HStack(spacing: 4) {
                    Text("📍 \(app)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(white: 0.2))
                        .cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
