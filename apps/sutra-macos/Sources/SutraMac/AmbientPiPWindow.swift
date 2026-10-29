import AppKit

public final class AmbientPiPWindow: NSPanel {
    public static let shared = AmbientPiPWindow()

    private var activeThread: SutraThread?
    private var containerView: NSView!
    private var appIconView: NSImageView!
    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!
    private var resumeBtn: ClosureButton!
    private var closeBtn: ClosureButton!
    private var peekBtn: ClosureButton!

    private override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(
            contentRect: NSRect(x: 100, y: 100, width: 280, height: 76),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false

        buildUI()
    }

    private func buildUI() {
        containerView = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 76))
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 14
        containerView.layer?.masksToBounds = true
        containerView.layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 0.94).cgColor
        containerView.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.16).cgColor
        containerView.layer?.borderWidth = 1.0

        // App Icon
        appIconView = NSImageView(frame: NSRect(x: 14, y: 38, width: 22, height: 22))
        containerView.addSubview(appIconView)

        // Title Label
        titleLabel = NSTextField(labelWithString: "Thread Title")
        titleLabel.frame = NSRect(x: 42, y: 40, width: 170, height: 18)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.cell?.lineBreakMode = .byTruncatingTail
        containerView.addSubview(titleLabel)

        // Subtitle (Next Action / Origin)
        subtitleLabel = NSTextField(labelWithString: "Next Action")
        subtitleLabel.frame = NSRect(x: 14, y: 12, width: 180, height: 16)
        subtitleLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        subtitleLabel.textColor = NSColor(calibratedWhite: 0.70, alpha: 1.0)
        subtitleLabel.cell?.lineBreakMode = .byTruncatingTail
        containerView.addSubview(subtitleLabel)

        // Close Button
        closeBtn = ClosureButton(frame: NSRect(x: 254, y: 50, width: 18, height: 18)) { [weak self] in
            self?.dismiss()
        }
        closeBtn.isBordered = false
        closeBtn.wantsLayer = true
        closeBtn.layer?.cornerRadius = 9
        closeBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.20, alpha: 1.0).cgColor
        closeBtn.attributedTitle = NSAttributedString(string: "✕", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.85, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 9, weight: .bold)
        ])
        containerView.addSubview(closeBtn)

        // Resume Hero Button
        resumeBtn = ClosureButton(frame: NSRect(x: 202, y: 10, width: 68, height: 22)) { [weak self] in
            guard let self = self, let thread = self.activeThread else { return }
            _ = SutraBridge.shared.resume(threadId: thread.id)
            NSSound(named: "Glass")?.play()
            self.dismiss()
        }
        resumeBtn.isBordered = false
        resumeBtn.wantsLayer = true
        resumeBtn.layer?.cornerRadius = 4
        resumeBtn.layer?.backgroundColor = NSColor.white.cgColor
        resumeBtn.attributedTitle = NSAttributedString(string: "Resume", attributes: [
            .foregroundColor: NSColor.black,
            .font: NSFont.systemFont(ofSize: 10, weight: .bold)
        ])
        containerView.addSubview(resumeBtn)

        // Context Peek Quick Button
        peekBtn = ClosureButton(frame: NSRect(x: 228, y: 48, width: 22, height: 20)) { [weak self] in
            guard let self = self, let thread = self.activeThread else { return }
            if ContextPeekDrawer.shared.isVisible && ContextPeekDrawer.shared.activeThreadId == thread.id {
                ContextPeekDrawer.shared.dismiss()
            } else {
                ContextPeekDrawer.shared.show(for: thread)
            }
        }
        peekBtn.isBordered = false
        peekBtn.wantsLayer = true
        peekBtn.toolTip = "Peek Context (Space)"
        if let sym = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: "Peek") {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            peekBtn.image = sym.withSymbolConfiguration(config)
            peekBtn.contentTintColor = NSColor(calibratedWhite: 0.85, alpha: 1.0)
            peekBtn.imagePosition = .imageOnly
        }
        containerView.addSubview(peekBtn)

        contentView = containerView
    }

    public func pin(thread: SutraThread) {
        self.activeThread = thread
        titleLabel.stringValue = thread.title
        subtitleLabel.stringValue = thread.notes?.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first ?? thread.originDisplay

        if let appName = thread.anchor?.app_name, let path = NSWorkspace.shared.fullPath(forApplication: appName) {
            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.size = NSSize(width: 22, height: 22)
            appIconView.image = icon
        } else {
            appIconView.image = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
        }

        if !isVisible {
            if let screen = NSScreen.main {
                let rect = screen.visibleFrame
                let x = rect.maxX - 300
                let y = rect.maxY - 110
                setFrameOrigin(NSPoint(x: x, y: y))
            }
            orderFront(nil)
        }
    }

    public func dismiss() {
        orderOut(nil)
        activeThread = nil
    }
}
