import SwiftUI

public struct SutraAppView: View {
    @StateObject private var bridge = SutraIOSBridge.shared
    @State private var showingQuickCue = false

    public init() {}

    public var body: some View {
        NavigationStack {
            SanctuaryView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingQuickCue = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(Color(red: 179/255, green: 86/255, blue: 42/255))
                        }
                        .keyboardShortcut(.space, modifiers: [.command, .option]) // Magic Keyboard support
                    }
                }
                .sheet(isPresented: $showingQuickCue) {
                    QuickCueSheet()
                        .presentationDetents([.medium, .large])
                }
        }
        .preferredColorScheme(.dark)
    }
}
