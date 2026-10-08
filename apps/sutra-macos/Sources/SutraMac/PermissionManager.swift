import Cocoa
import ApplicationServices

public final class PermissionManager {
    public static let shared = PermissionManager()

    private var pollTimer: Timer?
    private var permissionPanel: NSPanel?
    private var appActiveObserver: Any?

    public static func isAccessibilityGranted() -> Bool {
        if AXIsProcessTrusted() { return true }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public func verifyOrPrompt(completion: @escaping () -> Void) {
        if PermissionManager.isAccessibilityGranted() {
            completion()
            return
        }

        showOnboardingWindow(completion: completion)
    }

    private func showOnboardingWindow(completion: @escaping () -> Void) {
        let w: CGFloat = 460
        let h: CGFloat = 280

        let panel = KeyFocusPanel(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .darkAqua)

        let card = NSView(frame: panel.contentView!.bounds)
        card.autoresizingMask = [.width, .height]
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.12, alpha: 1.0).cgColor
        card.layer?.cornerRadius = 16
        card.layer?.masksToBounds = true
        card.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.14).cgColor
        card.layer?.borderWidth = 1.0

        // Title
        let titleLabel = NSTextField(labelWithString: "Sutra Permissions Setup")
        titleLabel.frame = NSRect(x: 24, y: h - 52, width: w - 70, height: 26)
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = NSColor(calibratedRed: 0.85, green: 0.42, blue: 0.15, alpha: 1.0)
        card.addSubview(titleLabel)

        // Subtitle / Explanation
        let desc = NSTextField(wrappingLabelWithString: "Sutra requires macOS Accessibility permission to listen to global hotkeys (Right ⌥ Option, ⌥S, ⌥A) and anchor threads to your active apps.\n\nOnce enabled in System Settings, this screen will close automatically.")
        desc.frame = NSRect(x: 24, y: h - 146, width: w - 48, height: 86)
        desc.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        desc.textColor = NSColor(calibratedWhite: 0.85, alpha: 1.0)
        card.addSubview(desc)

        let closeAndFinish = { [weak self] in
            self?.pollTimer?.invalidate()
            self?.pollTimer = nil
            if let obs = self?.appActiveObserver {
                NotificationCenter.default.removeObserver(obs)
                self?.appActiveObserver = nil
            }
            panel.orderOut(nil)
            completion()
        }

        // Action Button 1: Open System Settings
        let settingsBtn = ClosureButton(frame: NSRect(x: 24, y: 32, width: 200, height: 32)) {
            PermissionManager.openAccessibilitySettings()
        }
        settingsBtn.title = "Open System Settings →"
        settingsBtn.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        settingsBtn.isBordered = false
        settingsBtn.wantsLayer = true
        settingsBtn.layer?.backgroundColor = NSColor(calibratedRed: 0.85, green: 0.42, blue: 0.15, alpha: 1.0).cgColor
        settingsBtn.layer?.cornerRadius = 8
        card.addSubview(settingsBtn)

        // Action Button 2: Verify Access Button
        let checkBtn = ClosureButton(frame: NSRect(x: 232, y: 32, width: 140, height: 32)) {
            if PermissionManager.isAccessibilityGranted() {
                NSSound(named: "Glass")?.play()
                closeAndFinish()
            } else {
                NSSound(named: "Basso")?.play()
                PermissionManager.openAccessibilitySettings()
            }
        }
        checkBtn.title = "Verify Access ✓"
        checkBtn.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        checkBtn.isBordered = false
        checkBtn.wantsLayer = true
        checkBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.22, alpha: 0.9).cgColor
        checkBtn.layer?.cornerRadius = 8
        card.addSubview(checkBtn)

        // Close button [✕] in top-right
        let skipBtn = ClosureButton(frame: NSRect(x: w - 38, y: h - 42, width: 22, height: 22)) {
            closeAndFinish()
        }
        skipBtn.title = "✕"
        skipBtn.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        skipBtn.isBordered = false
        skipBtn.wantsLayer = true
        skipBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.2, alpha: 0.6).cgColor
        skipBtn.layer?.cornerRadius = 11
        card.addSubview(skipBtn)

        panel.contentView?.addSubview(card)

        if let screen = NSScreen.main {
            let f = panel.frame
            let x = screen.visibleFrame.midX - (f.width / 2)
            let y = screen.visibleFrame.midY - (f.height / 2)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.permissionPanel = panel

        // 1. Polling timer running on .common runloop mode (doesn't pause when backgrounded)
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
            if PermissionManager.isAccessibilityGranted() {
                NSSound(named: "Glass")?.play()
                closeAndFinish()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.pollTimer = timer

        // 2. Immediate check when returning focus to app
        if let existing = appActiveObserver { NotificationCenter.default.removeObserver(existing) }
        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            if PermissionManager.isAccessibilityGranted() {
                NSSound(named: "Glass")?.play()
                closeAndFinish()
            }
        }
    }
}
