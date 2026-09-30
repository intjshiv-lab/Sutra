import AppKit

public final class FloatingWakeBar: NSObject {
    public static let shared = FloatingWakeBar()

    private var panel: NSPanel!
    private var visualEffect: NSView!
    private var containerView: NSView!
    private var activeThreads: [SutraThread] = []
    private var autoDismissTimer: Timer?

    public override init() {
        super.init()
        setupPanel()
    }

    private func setupPanel() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 120),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .darkAqua)

        visualEffect = NSView(frame: panel.contentView!.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.wantsLayer = true
        visualEffect.layer?.backgroundColor = NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.12, alpha: 1.0).cgColor
        visualEffect.layer?.cornerRadius = 14
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.14).cgColor
        visualEffect.layer?.borderWidth = 1.0

        containerView = NSView(frame: visualEffect.bounds)
        containerView.autoresizingMask = [.width, .height]
        visualEffect.addSubview(containerView)

        panel.contentView?.addSubview(visualEffect)
    }

    public func presentMultiple(threads: [SutraThread]) {
        guard !threads.isEmpty else {
            panel.orderOut(nil)
            return
        }
        activeThreads = threads.sorted(by: { $0.created_at > $1.created_at })
        render()
        show()
    }

    public func toggleForFrontmostApp() {
        if panel.isVisible {
            panel.orderOut(nil)
            autoDismissTimer?.invalidate()
            return
        }

        let frontApp = NSWorkspace.shared.frontmostApplication
        let appName = frontApp?.localizedName ?? ""
        let bundleId = frontApp?.bundleIdentifier ?? ""
        let allWaiting = SutraBridge.shared.list(status: "waiting")

        let matching = allWaiting.filter { t in
            if let a = t.anchor?.app_name, !a.isEmpty, !appName.isEmpty,
               a.localizedCaseInsensitiveContains(appName) || appName.localizedCaseInsensitiveContains(a) {
                return true
            }
            if let b = t.anchor?.bundle_id, !b.isEmpty, !bundleId.isEmpty,
               b.lowercased() == bundleId.lowercased() {
                return true
            }
            return false
        }

        let threadsToDisplay = matching.isEmpty ? Array(allWaiting.prefix(3)) : matching
        guard !threadsToDisplay.isEmpty else { return }
        presentMultiple(threads: threadsToDisplay)
    }

    private func show() {
        panel.orderFrontRegardless()
        resetTimer()
    }

    private func resetTimer() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: 14.0, repeats: false) { [weak self] _ in
            self?.panel.orderOut(nil)
        }
    }

    private func render() {
        containerView.subviews.forEach { $0.removeFromSuperview() }

        let rowHeight: CGFloat = 34
        let headerHeight: CGFloat = 36
        let footerHeight: CGFloat = 6
        let visibleRows = min(3, max(1, activeThreads.count))
        let rowsAreaHeight = CGFloat(visibleRows) * rowHeight
        let totalHeight = headerHeight + rowsAreaHeight + footerHeight

        // Anchor top edge to screen.visibleFrame.maxY - 20
        if let screen = NSScreen.main {
            let topY = screen.visibleFrame.maxY - 20
            let x = screen.visibleFrame.midX - 240
            let y = topY - totalHeight
            panel.setFrame(NSRect(x: x, y: y, width: 480, height: totalHeight), display: true)
        }
        containerView.frame = visualEffect.bounds

        // Top Header
        let headerView = NSView(frame: NSRect(x: 0, y: totalHeight - headerHeight, width: 480, height: headerHeight))
        
        // Center Logo (26x26)
        let logoSize: CGFloat = 26
        let logoView = NSImageView(frame: NSRect(x: (480 - logoSize) / 2, y: (headerHeight - logoSize) / 2, width: logoSize, height: logoSize))
        logoView.image = loadSutraLogo(size: NSSize(width: logoSize, height: logoSize))
        headerView.addSubview(logoView)

        // Close Button (top-right)
        let closeBtn = ClosureButton(frame: NSRect(x: 448, y: (headerHeight - 20) / 2, width: 20, height: 20)) { [weak self] in
            self?.panel.orderOut(nil)
        }
        closeBtn.isBordered = false
        closeBtn.title = "✕"
        closeBtn.font = NSFont.systemFont(ofSize: 11.5, weight: .bold)
        closeBtn.contentTintColor = NSColor(calibratedWhite: 0.6, alpha: 1.0)
        headerView.addSubview(closeBtn)
        containerView.addSubview(headerView)

        // Thread Rows Container: 3 visible rows, scrollable with TerracottaScroller if > 3
        if activeThreads.count > 3 {
            let scrollView = NSScrollView(frame: NSRect(x: 0, y: footerHeight, width: 480, height: rowsAreaHeight))
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            let scroller = TerracottaScroller()
            scrollView.verticalScroller = scroller
            scrollView.hasVerticalScroller = true
            scrollView.autohidesScrollers = false

            let docHeight = CGFloat(activeThreads.count) * rowHeight
            let docView = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: docHeight))
            var rowY = docHeight - rowHeight
            for thread in activeThreads {
                let row = makeThreadRow(thread: thread, frame: NSRect(x: 12, y: rowY, width: 456, height: rowHeight))
                docView.addSubview(row)
                rowY -= rowHeight
            }
            scrollView.documentView = docView
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: docHeight - rowsAreaHeight))
            containerView.addSubview(scrollView)
        } else {
            var currentY = totalHeight - headerHeight - rowHeight
            for thread in activeThreads {
                let row = makeThreadRow(thread: thread, frame: NSRect(x: 12, y: currentY, width: 456, height: rowHeight))
                containerView.addSubview(row)
                currentY -= rowHeight
            }
        }
    }

    private func makeThreadRow(thread: SutraThread, frame: NSRect) -> NSView {
        let row = NSView(frame: frame)

        // App Icon
        let appIcon = NSImageView(frame: NSRect(x: 0, y: 7, width: 20, height: 20))
        appIcon.image = iconForApp(appName: thread.anchor?.app_name)
        row.addSubview(appIcon)

        // Title Label
        let titleLabel = NSTextField(labelWithString: thread.title)
        titleLabel.frame = NSRect(x: 26, y: 7, width: 200, height: 18)
        titleLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.cell?.lineBreakMode = .byTruncatingTail
        row.addSubview(titleLabel)

        // Time ago (Amber / Orange)
        let timeLabel = NSTextField(labelWithString: thread.timeAgo)
        timeLabel.frame = NSRect(x: 230, y: 7, width: 44, height: 18)
        timeLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        timeLabel.textColor = NSColor(calibratedRed: 0.92, green: 0.55, blue: 0.28, alpha: 1.0)
        timeLabel.alignment = .right
        row.addSubview(timeLabel)

        // [+ Resume] Pill
        let resumeBtn = ClosureButton(frame: NSRect(x: 282, y: 7, width: 78, height: 20)) { [weak self] in
            _ = SutraBridge.shared.resume(threadId: thread.id)
            NSSound(named: "Glass")?.play()
            self?.panel.orderOut(nil)
        }
        resumeBtn.isBordered = false
        resumeBtn.wantsLayer = true
        resumeBtn.layer?.cornerRadius = 10
        resumeBtn.layer?.backgroundColor = NSColor(calibratedRed: 0.85, green: 0.42, blue: 0.15, alpha: 1.0).cgColor
        resumeBtn.attributedTitle = NSAttributedString(string: "+ Resume", attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 10.5, weight: .bold)
        ])
        row.addSubview(resumeBtn)

        // [4h] Dark Pill
        let snoozeBtn = ClosureButton(frame: NSRect(x: 366, y: 7, width: 44, height: 20)) { [weak self] in
            _ = SutraBridge.shared.snooze(threadId: thread.id, hours: 4)
            self?.activeThreads.removeAll(where: { $0.id == thread.id })
            if let active = self?.activeThreads, !active.isEmpty {
                self?.render()
            } else {
                self?.panel.orderOut(nil)
            }
        }
        snoozeBtn.isBordered = false
        snoozeBtn.wantsLayer = true
        snoozeBtn.layer?.cornerRadius = 10
        snoozeBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.25, alpha: 0.95).cgColor
        snoozeBtn.attributedTitle = NSAttributedString(string: "4h", attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 10.5, weight: .medium)
        ])
        row.addSubview(snoozeBtn)

        // [✓] Circle
        let doneBtn = ClosureButton(frame: NSRect(x: 418, y: 7, width: 20, height: 20)) { [weak self] in
            _ = SutraBridge.shared.done(threadId: thread.id)
            NSSound(named: "Glass")?.play()
            self?.activeThreads.removeAll(where: { $0.id == thread.id })
            if let active = self?.activeThreads, !active.isEmpty {
                self?.render()
            } else {
                self?.panel.orderOut(nil)
            }
        }
        doneBtn.isBordered = false
        doneBtn.wantsLayer = true
        doneBtn.layer?.cornerRadius = 10
        doneBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.25, alpha: 0.95).cgColor
        doneBtn.attributedTitle = NSAttributedString(string: "✓", attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 11, weight: .bold)
        ])
        row.addSubview(doneBtn)

        return row
    }

    private func iconForApp(appName: String?) -> NSImage {
        guard let name = appName, !name.isEmpty else {
            return NSWorkspace.shared.icon(forFileType: NSFileTypeForHFSTypeCode(OSType(kGenericApplicationIcon)))
        }
        if let path = NSWorkspace.shared.fullPath(forApplication: name) {
            let img = NSWorkspace.shared.icon(forFile: path)
            img.size = NSSize(width: 20, height: 20)
            return img
        }
        return NSWorkspace.shared.icon(forFileType: NSFileTypeForHFSTypeCode(OSType(kGenericApplicationIcon)))
    }

    private func loadSutraLogo(size: NSSize) -> NSImage {
        let possiblePaths = [
            "/Users/raman/Desktop/AI/Sutra/assets/logo.png",
            Bundle.main.path(forResource: "logo", ofType: "png") ?? ""
        ]
        for path in possiblePaths where !path.isEmpty {
            if let img = NSImage(contentsOfFile: path) {
                img.size = size
                return img
            }
        }
        let fallback = NSImage(size: size)
        fallback.lockFocus()
        NSColor(calibratedRed: 0.85, green: 0.42, blue: 0.15, alpha: 1.0).setFill()
        let path = NSBezierPath(ovalIn: NSRect(origin: .zero, size: size))
        path.fill()
        fallback.unlockFocus()
        return fallback
    }
}

class ClosureButton: NSButton {
    let onClick: () -> Void
    init(frame: NSRect, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: frame)
        target = self
        action = #selector(trigger)
        sendAction(on: [.leftMouseUp])
        contentTintColor = .white
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc func trigger() { onClick() }

    public override var title: String {
        get { super.title }
        set {
            super.title = newValue
            let f = self.font ?? NSFont.systemFont(ofSize: 10, weight: .regular)
            self.attributedTitle = NSAttributedString(string: newValue, attributes: [
                .foregroundColor: NSColor.white,
                .font: f
            ])
        }
    }

    public override var font: NSFont? {
        get { super.font }
        set {
            super.font = newValue
            if let f = newValue, !self.title.isEmpty {
                let existingColor = (self.attributedTitle.length > 0)
                    ? (self.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor ?? .white)
                    : .white
                self.attributedTitle = NSAttributedString(string: self.title, attributes: [
                    .foregroundColor: existingColor,
                    .font: f
                ])
            }
        }
    }

    public override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        let pt = convert(event.locationInWindow, from: nil)
        if bounds.contains(pt) {
            onClick()
        }
    }
}

final class TerracottaScroller: NSScroller {
    public override func drawKnobSlot(in slotRect: NSRect, highlight: Bool) {
        NSColor(calibratedWhite: 0.15, alpha: 0.4).setFill()
        let path = NSBezierPath(roundedRect: slotRect.insetBy(dx: 1, dy: 2), xRadius: 4, yRadius: 4)
        path.fill()
    }

    public override func drawKnob() {
        var knobRect = rect(for: .knob).insetBy(dx: 2, dy: 1)
        if knobRect.width < 4 { knobRect.size.width = 4 }
        let path = NSBezierPath(roundedRect: knobRect, xRadius: knobRect.width / 2, yRadius: knobRect.width / 2)
        NSColor(calibratedRed: 0.85, green: 0.42, blue: 0.15, alpha: 0.95).setFill()
        path.fill()
    }
}
