import AppKit

public enum IconResolver {
    public static func resolveIcon(for thread: SutraThread, size: CGFloat = 18) -> NSImage {
        return resolveIcon(forApp: thread.anchor?.app_name, bundleId: thread.anchor?.bundle_id, size: size)
    }

    public static func resolveIcon(forApp appName: String?, bundleId: String? = nil, size: CGFloat = 20) -> NSImage {
        if let name = appName, !name.isEmpty {
            let lower = name.lowercased()
            if lower.contains("antigravity") {
                let p = Bundle.main.path(forResource: "antigravity", ofType: "png") ?? "/Users/raman/Desktop/AI/Sutra/assets/antigravity.png"
                if let img = NSImage(contentsOfFile: p) {
                    img.size = NSSize(width: size, height: size)
                    return img
                }
            }
            if lower.contains("peepal") {
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let p = "\(home)/Applications/Chrome Apps.localized/peepal.app/Contents/Resources/app.icns"
                if let img = NSImage(contentsOfFile: p) {
                    img.size = NSSize(width: size, height: size)
                    return img
                }
            }
            if let bid = bundleId, !bid.isEmpty,
               let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                let icon = NSWorkspace.shared.icon(forFile: appUrl.path)
                icon.size = NSSize(width: size, height: size)
                return icon
            }
            if let appUrl = NSWorkspace.shared.urlForApplication(toOpen: URL(fileURLWithPath: "/Applications/\(name).app")) ??
                            NSWorkspace.shared.urlForApplication(toOpen: URL(fileURLWithPath: "/System/Applications/\(name).app")) {
                let icon = NSWorkspace.shared.icon(forFile: appUrl.path)
                icon.size = NSSize(width: size, height: size)
                return icon
            }
            if let path = NSWorkspace.shared.fullPath(forApplication: name) {
                let icon = NSWorkspace.shared.icon(forFile: path)
                icon.size = NSSize(width: size, height: size)
                return icon
            }
        }
        let fallback = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ??
                       NSImage(systemSymbolName: "doc.text.fill", accessibilityDescription: nil) ?? NSImage()
        fallback.size = NSSize(width: size, height: size)
        return fallback
    }
}
