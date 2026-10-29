import AppKit

public final class AmbientPiPWindow: NSPanel {
    public static let shared = AmbientPiPWindow()

    private var activeThread: SutraThread?
    public var activeThreadId: String? { activeThread?.id }
    private var containerView: NSView!
    private var appIconView: NSImageView!
    private var titleLabel: NSTextField!
    private var resumeBtn: ClosureButton!
    private var closeBtn: ClosureButton!
    private var peekBtn: ClosureButton!

    private override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(
            contentRect: NSRect(x: 100, y: 100, width: 292, height: 40),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        appearance = NSAppearance(named: .darkAqua)

        buildUI()
    }

    private func buildUI() {
        containerView = NSView(frame: NSRect(x: 0, y: 0, width: 292, height: 40))
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 20
        containerView.layer?.masksToBounds = true
        containerView.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.96).cgColor
        containerView.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.14).cgColor
        containerView.layer?.borderWidth = 1.0

        // App Icon (18x18)
        appIconView = NSImageView(frame: NSRect(x: 11, y: 11, width: 18, height: 18))
        containerView.addSubview(appIconView)

        // Title Label
        titleLabel = NSTextField(labelWithString: "Thread Title")
        titleLabel.frame = NSRect(x: 35, y: 11, width: 135, height: 18)
        titleLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.cell?.lineBreakMode = .byTruncatingTail
        containerView.addSubview(titleLabel)

        // Context Peek Quick Button (👁)
        peekBtn = ClosureButton(frame: NSRect(x: 176, y: 10, width: 22, height: 20)) { [weak self] in
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

        // Resume Hero Button (White Pill: 56x22)
        resumeBtn = ClosureButton(frame: NSRect(x: 204, y: 9, width: 56, height: 22)) { [weak self] in
            guard let self = self, let thread = self.activeThread else { return }
            _ = SutraBridge.shared.resume(threadId: thread.id)
            NSSound(named: "Glass")?.play()
            self.dismiss()
        }
        resumeBtn.isBordered = false
        resumeBtn.wantsLayer = true
        resumeBtn.layer?.cornerRadius = 11
        resumeBtn.layer?.backgroundColor = NSColor.white.cgColor
        resumeBtn.attributedTitle = NSAttributedString(string: "Resume", attributes: [
            .foregroundColor: NSColor.black,
            .font: NSFont.systemFont(ofSize: 10, weight: .bold)
        ])
        containerView.addSubview(resumeBtn)

        // Close / Unpin Button (✕)
        closeBtn = ClosureButton(frame: NSRect(x: 266, y: 12, width: 16, height: 16)) { [weak self] in
            self?.dismiss()
        }
        closeBtn.isBordered = false
        closeBtn.wantsLayer = true
        closeBtn.layer?.cornerRadius = 8
        closeBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.22, alpha: 1.0).cgColor
        closeBtn.attributedTitle = NSAttributedString(string: "✕", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.85, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 8.5, weight: .bold)
        ])
        containerView.addSubview(closeBtn)

        contentView = containerView
    }

    public func pin(thread: SutraThread) {
        self.activeThread = thread
        titleLabel.stringValue = thread.title
        titleLabel.toolTip = thread.title

        if let appName = thread.anchor?.app_name, let path = NSWorkspace.shared.fullPath(forApplication: appName) {
            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.size = NSSize(width: 18, height: 18)
            appIconView.image = icon
        } else {
            appIconView.image = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
        }

        repositionAdjacentToIsland(animated: isVisible)
        orderFront(nil)
    }

    public func repositionAdjacentToIsland(islandFrame: NSRect? = nil, animated: Bool = false) {
        guard isVisible || activeThread != nil, let screen = NSScreen.main else { return }
        let baseFrame = islandFrame ?? FloatingWakeBar.shared.frame
        let screenFrame = screen.visibleFrame
        let targetW: CGFloat = 292
        let targetH: CGFloat = 40

        var targetX = baseFrame.maxX + 10
        if targetX + targetW > screenFrame.maxX - 10 {
            targetX = screenFrame.maxX - targetW - 10
        }
        let targetY = baseFrame.maxY - targetH

        let targetFrame = NSRect(x: targetX, y: targetY, width: targetW, height: targetH)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().setFrame(targetFrame, display: true)
            }
        } else {
            setFrame(targetFrame, display: true)
        }
    }

    public func dismiss() {
        orderOut(nil)
        activeThread = nil
    }
}
