#if canImport(ActivityKit) && canImport(WidgetKit) && os(iOS)
import ActivityKit
import WidgetKit
import SwiftUI

public struct SutraActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var title: String
        public var appName: String?
        public var dueAt: Int64?

        public init(title: String, appName: String? = nil, dueAt: Int64? = nil) {
            self.title = title
            self.appName = appName
            self.dueAt = dueAt
        }
    }

    public var threadId: String

    public init(threadId: String) {
        self.threadId = threadId
    }
}

public struct SutraLiveActivityWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: SutraActivityAttributes.self) { context in
            // Lock Screen presentation
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(red: 179/255, green: 86/255, blue: 42/255))
                    .frame(width: 8, height: 8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    
                    if let app = context.state.appName {
                        Text("Resume in \(app)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                
                Button(action: {}) {
                    Text("Resume")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(red: 179/255, green: 86/255, blue: 42/255))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    Circle()
                        .fill(Color(red: 179/255, green: 86/255, blue: 42/255))
                        .frame(width: 8, height: 8)
                        .padding(.leading, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Sutra")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.title)
                        .font(.footnote)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
            } compactLeading: {
                Circle()
                    .fill(Color(red: 179/255, green: 86/255, blue: 42/255))
                    .frame(width: 6, height: 6)
            } compactTrailing: {
                Text(context.state.appName ?? "Task")
                    .font(.caption2)
                    .foregroundColor(Color(red: 179/255, green: 86/255, blue: 42/255))
            } minimal: {
                Circle()
                    .fill(Color(red: 179/255, green: 86/255, blue: 42/255))
                    .frame(width: 6, height: 6)
            }
        }
    }
}
#endif
