import AppKit

public final class FloatingWakeBar: NSObject {
    public static let shared = FloatingWakeBar()

    private var panel: NSPanel!
    private var visualEffect: NSView!
    private var containerView: HoverTrackingView!
    private var headerView: NSView!
    private var rowsContainerView: NSView!
    private var bottomDragBar: BottomResizeHandleView!

    // In-memory session preference: defaults to 3 on launch, persists across toggles
    public static var sessionPreferredVisibleRows: Int = 3

    private var activeThreads: [SutraThread] = []
    private var autoDismissTimer: Timer?

    public override init() {
        super.init()
        setupPanel()
    }

    private func setupPanel() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 152),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // Precedence over macOS menu bar (mainMenu=24, statusBar=25, popUpMenu=101)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .darkAqua)

        visualEffect = NSView(frame: panel.contentView!.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.wantsLayer = true
        visualEffect.layer?.backgroundColor = NSColor(calibratedWhite: 0.05, alpha: 0.98).cgColor
        visualEffect.layer?.cornerRadius = 14
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.10).cgColor
        visualEffect.layer?.borderWidth = 1.0

        containerView = HoverTrackingView(frame: visualEffect.bounds)
        containerView.autoresizingMask = [.width, .height]
        containerView.onMouseEnter = { [weak self] in
            // Pause timer while user is interacting / inspecting threads
            self?.autoDismissTimer?.invalidate()
        }
        containerView.onMouseExit = { [weak self] in
            // Resume dismiss timer when cursor departs
            self?.resetTimer()
        }
        visualEffect.addSubview(containerView)
        panel.contentView?.addSubview(visualEffect)

        setupSubviews()
    }

    private func setupSubviews() {
        let headerHeight: CGFloat = 36
        headerView = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: headerHeight))

        // Center Logo (26x26)
        let logoSize: CGFloat = 26
        let logoView = NSImageView(frame: NSRect(x: (480 - logoSize) / 2, y: (headerHeight - logoSize) / 2, width: logoSize, height: logoSize))
        logoView.image = loadSutraLogo(size: NSSize(width: logoSize, height: logoSize))
        headerView.addSubview(logoView)

        // Close Button (top-right)
        let closeBtn = ClosureButton(frame: NSRect(x: 448, y: (headerHeight - 20) / 2, width: 20, height: 20)) { [weak self] in
            self?.panel.orderOut(nil)
            self?.autoDismissTimer?.invalidate()
        }
        closeBtn.isBordered = false
        closeBtn.title = "✕"
        closeBtn.font = NSFont.systemFont(ofSize: 11.5, weight: .bold)
        closeBtn.contentTintColor = NSColor(calibratedWhite: 0.6, alpha: 1.0)
        headerView.addSubview(closeBtn)

        containerView.addSubview(headerView)

        // Rows container view
        rowsContainerView = NSView(frame: NSRect(x: 0, y: 14, width: 480, height: 102))
        containerView.addSubview(rowsContainerView)

        // Bottom Resize Handle Bar (14pt height)
        bottomDragBar = BottomResizeHandleView(frame: NSRect(x: 0, y: 0, width: 480, height: 14))
        bottomDragBar.onDragStart = { [weak self] in
            self?.autoDismissTimer?.invalidate()
        }
        bottomDragBar.onDragDelta = { [weak self] targetRows in
            guard let self = self else { return }
            if FloatingWakeBar.sessionPreferredVisibleRows != targetRows {
                FloatingWakeBar.sessionPreferredVisibleRows = targetRows
                self.render()
            }
        }
        bottomDragBar.onDragEnd = { [weak self] in
            self?.resetTimer()
        }
        bottomDragBar.onDoubleClick = { [weak self] in
            guard let self = self else { return }
            if FloatingWakeBar.sessionPreferredVisibleRows > 3 {
                FloatingWakeBar.sessionPreferredVisibleRows = 3
            } else {
                FloatingWakeBar.sessionPreferredVisibleRows = max(3, min(8, self.activeThreads.count))
            }
            self.render()
        }
        containerView.addSubview(bottomDragBar)
    }

    public func presentMultiple(threads: [SutraThread]) {
        guard !threads.isEmpty else {
            panel.orderOut(nil)
            autoDismissTimer?.invalidate()
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

        let threadsToDisplay = matching.isEmpty ? Array(allWaiting.prefix(8)) : matching
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

    private func getTopY(for screen: NSScreen) -> CGFloat {
        if screen.safeAreaInsets.top > 25 {
            // Hardware camera notch cutout clearance
            return screen.frame.maxY - screen.safeAreaInsets.top - 4
        } else {
            // Top of physical screen, sitting cleanly over the empty menu bar center
            return screen.frame.maxY - 20
        }
    }

    private func render() {
        let rowHeight: CGFloat = 34
        let headerHeight: CGFloat = 36
        let footerHeight: CGFloat = 14

        let maxAllowed = 8
        let targetRows = min(maxAllowed, FloatingWakeBar.sessionPreferredVisibleRows)
        let visibleRows = max(1, targetRows)
        let rowsAreaHeight = CGFloat(visibleRows) * rowHeight
        let totalHeight = headerHeight + rowsAreaHeight + footerHeight

        // Anchor top edge strictly at top of display (takes precedence above menu bar)
        if let screen = NSScreen.main {
            let topY = getTopY(for: screen)
            let x = screen.frame.midX - 240
            let y = topY - totalHeight
            panel.setFrame(NSRect(x: x, y: y, width: 480, height: totalHeight), display: true)
        }

        containerView.frame = visualEffect.bounds

        // Position fixed subviews
        headerView.frame = NSRect(x: 0, y: totalHeight - headerHeight, width: 480, height: headerHeight)
        bottomDragBar.frame = NSRect(x: 0, y: 0, width: 480, height: footerHeight)
        rowsContainerView.frame = NSRect(x: 0, y: footerHeight, width: 480, height: rowsAreaHeight)

        // Re-render rows content
        rowsContainerView.subviews.forEach { $0.removeFromSuperview() }

        if activeThreads.count > visibleRows {
            let scrollView = NSScrollView(frame: rowsContainerView.bounds)
            scrollView.autoresizingMask = [.width, .height]
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
            rowsContainerView.addSubview(scrollView)
        } else {
            var currentY = rowsAreaHeight - rowHeight
            for thread in activeThreads {
                let row = makeThreadRow(thread: thread, frame: NSRect(x: 12, y: currentY, width: 456, height: rowHeight))
                rowsContainerView.addSubview(row)
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

        // Time ago (Zinc)
        let timeLabel = NSTextField(labelWithString: thread.timeAgo)
        timeLabel.frame = NSRect(x: 230, y: 7, width: 44, height: 18)
        timeLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        timeLabel.textColor = NSColor(calibratedWhite: 0.70, alpha: 1.0)
        timeLabel.alignment = .right
        row.addSubview(timeLabel)

        // [+ Resume] Pill
        let resumeBtn = ClosureButton(frame: NSRect(x: 282, y: 7, width: 78, height: 20)) { [weak self] in
            _ = SutraBridge.shared.resume(threadId: thread.id)
            NSSound(named: "Glass")?.play()
            self?.panel.orderOut(nil)
            self?.autoDismissTimer?.invalidate()
        }
        resumeBtn.isBordered = false
        resumeBtn.wantsLayer = true
        resumeBtn.layer?.cornerRadius = 10
        resumeBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.95, alpha: 1.0).cgColor
        resumeBtn.attributedTitle = NSAttributedString(string: "+ Resume", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.05, alpha: 1.0),
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
                self?.autoDismissTimer?.invalidate()
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
                self?.autoDismissTimer?.invalidate()
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
        NSColor(calibratedWhite: 0.95, alpha: 1.0).setFill()
        let path = NSBezierPath(ovalIn: NSRect(origin: .zero, size: size))
        path.fill()
        fallback.unlockFocus()
        return fallback
    }
}

final class HoverTrackingView: NSView {
    var onMouseEnter: (() -> Void)?
    var onMouseExit: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExit?()
    }
}

final class BottomResizeHandleView: NSView {
    var onDragStart: (() -> Void)?
    var onDragDelta: ((Int) -> Void)?
    var onPixelDragDelta: ((CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    private let pillLayer = CALayer()
    private var isDragging = false
    private var startMouseScreenY: CGFloat = 0
    private var startRows: Int = 3
    private var currentTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupPill()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupPill() {
        let pillW: CGFloat = 36
        let pillH: CGFloat = 4
        pillLayer.frame = CGRect(x: (bounds.width - pillW) / 2, y: (bounds.height - pillH) / 2, width: pillW, height: pillH)
        pillLayer.cornerRadius = 2
        pillLayer.backgroundColor = NSColor(calibratedWhite: 0.35, alpha: 0.7).cgColor
        layer?.addSublayer(pillLayer)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = currentTrackingArea {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        currentTrackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.resizeUpDown.set()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseEntered(with event: NSEvent) {
        pillLayer.backgroundColor = NSColor(calibratedWhite: 0.85, alpha: 0.95).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        if !isDragging {
            pillLayer.backgroundColor = NSColor(calibratedWhite: 0.35, alpha: 0.7).cgColor
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        isDragging = true
        startMouseScreenY = NSEvent.mouseLocation.y
        startRows = FloatingWakeBar.sessionPreferredVisibleRows
        pillLayer.backgroundColor = NSColor(calibratedWhite: 0.85, alpha: 0.95).cgColor
        onDragStart?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let currentScreenY = NSEvent.mouseLocation.y
        // Dragging downwards decreases screen Y, so deltaY (downward movement) is positive
        let deltaY = startMouseScreenY - currentScreenY
        let rowsDelta = Int(round(deltaY / 34.0))
        let maxAllowed = 8
        let targetRows = max(1, min(maxAllowed, startRows + rowsDelta))
        onDragDelta?(targetRows)
        onPixelDragDelta?(deltaY)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        pillLayer.backgroundColor = NSColor(calibratedWhite: 0.35, alpha: 0.7).cgColor
        onDragEnd?()
    }

    override func layout() {
        super.layout()
        let pillW: CGFloat = 36
        let pillH: CGFloat = 4
        pillLayer.frame = CGRect(x: (bounds.width - pillW) / 2, y: (bounds.height - pillH) / 2, width: pillW, height: pillH)
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
        NSColor(calibratedWhite: 0.80, alpha: 0.85).setFill()
        path.fill()
    }
}
