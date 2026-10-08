import SwiftUI

public struct SanctuaryView: View {
    @StateObject private var bridge = SutraIOSBridge.shared
    @State private var searchText = ""
    @State private var isTodayExpanded = true

    @State private var isArchiveMode = false

    public init() {}

    private var currentThreads: [SutraThread] {
        isArchiveMode ? bridge.doneThreads : bridge.waitingThreads
    }

    public var body: some View {
        List {
            if !isArchiveMode {
                Section {
                    DisclosureGroup(isExpanded: $isTodayExpanded) {
                        if bridge.todayThreads.isEmpty {
                            Text("No threads scheduled for today")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(bridge.todayThreads) { thread in
                                ThreadRowView(thread: thread)
                            }
                        }
                    } label: {
                        HStack {
                            Text("Scheduled for Today")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(Color(red: 179/255, green: 86/255, blue: 42/255))
                            Spacer()
                            Text("(\(bridge.todayThreads.count))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Main Working Memory or Archive Section
            Section(isArchiveMode ? "Completed Archive (\(currentThreads.count))" : "Active Working Memory (\(currentThreads.count))") {
                if currentThreads.isEmpty {
                    Text(isArchiveMode ? "No archived threads." : "All caught up. No active threads.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(currentThreads) { thread in
                        ThreadRowView(thread: thread)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search threads...")
        .navigationTitle("Sutra Sanctuary")
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Text("Sutra Sanctuary")
                        .font(.headline)
                    Text("\(currentThreads.count)")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(white: 0.18)))
                }
            }
            ToolbarItem(placement: .bottomBar) {
                Button(action: { isArchiveMode.toggle() }) {
                    Text(isArchiveMode ? "← Active" : "Archive")
                        .font(.caption.weight(.medium))
                }
            }
        }
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
