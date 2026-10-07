import SwiftUI

public struct QuickCueSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var bridge = SutraIOSBridge.shared

    @State private var title = ""
    @State private var notes = ""
    @State private var scheduleMode: ScheduleOption = .none
    @State private var selectedDate = Date()
    @State private var showingDatePicker = false

    public enum ScheduleOption: String, CaseIterable {
        case none = "Schedule"
        case today = "Today"
        case pickDate = "Pick Date..."
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What's the immediate next action?", text: $title)
                        .font(.body)
                    
                    TextField("Context or implementation notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.callout)
                }

                Section("Schedule") {
                    Picker("When", selection: $scheduleMode) {
                        ForEach(ScheduleOption.allCases, id: \.self) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }

                    if scheduleMode == .pickDate {
                        DatePicker("Date", selection: $selectedDate, displayedComponents: [.date])
                    }
                }
            }
            .navigationTitle("Sutra Cue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Leave Thread") {
                        commitThread()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .foregroundColor(Color(red: 179/255, green: 86/255, blue: 42/255))
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func commitThread() {
        var dueAt: Int64? = nil
        if scheduleMode == .today {
            dueAt = Int64(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970 * 1000)
        } else if scheduleMode == .pickDate {
            dueAt = Int64(Calendar.current.startOfDay(for: selectedDate).timeIntervalSince1970 * 1000)
        }

        bridge.addThread(title: title, notes: notes, dueAt: dueAt)
        dismiss()
    }
}
