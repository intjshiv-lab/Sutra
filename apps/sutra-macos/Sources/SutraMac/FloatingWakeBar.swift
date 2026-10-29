import AppKit

public final class FloatingWakeBar: NSObject {
    public static let shared = FloatingWakeBar()

    public var frame: NSRect { panel?.frame ?? .zero }
    public var isPanelVisible: Bool { panel?.isVisible ?? false }

    private var panel: NSPanel!
    private var visualEffect: NSView!
    private var containerView: HoverTrackingView!
    private var headerView: NSView!
    private var rowsContainerView: NSView!
    private var bottomDragBar: BottomResizeHandleView!

    // Dynamic Island State Machine
    public var isExpanded: Bool = false
    public var isPinned: Bool = false
    public var showsRemainingItems: Bool = false
    private var collapseDebounceTimer: Timer?
    private var collapsedView: NSView!
    private var todayCountLabel: NSTextField!
    private var collapsedPinBtn: ClosureButton?
    private var pinBtn: ClosureButton!
    private var pinToastLabel: NSTextField?
    private var pinToastTimer: Timer?

    // In-memory session preference: defaults to 3 on launch, persists across toggles
    public static var sessionPreferredVisibleRows: Int = 3

    private var activeThreads: [SutraThread] = []
    private var autoDismissTimer: Timer?
    public var nudgeAppName: String?
    private var nudgeDismissTimer: Timer?

    private enum IslandRowItem {
        case nudge(String)
        case thread(SutraThread)
        case separator
        case emptyToday

        var height: CGFloat {
            switch self {
            case .nudge: return 34
            case .thread: return 34
            case .separator: return 10
            case .emptyToday: return 34
            }
        }
    }

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
        visualEffect.layer?.cornerRadius = 17
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor
        visualEffect.layer?.borderWidth = 1.0

        containerView = HoverTrackingView(frame: visualEffect.bounds)
        containerView.autoresizingMask = [.width, .height]
        containerView.onMouseEnter = { [weak self] in
            guard let self = self else { return }
            self.collapseDebounceTimer?.invalidate()
            self.collapseDebounceTimer = nil
            self.autoDismissTimer?.invalidate()
            self.autoDismissTimer = nil
            if !self.isExpanded {
                self.expand()
            }
        }
        containerView.onMouseExit = { [weak self] in
            guard let self = self else { return }
            // Constraint: If pinned, stays expanded permanently!
            if self.isPinned { return }
            // If not pinned, auto-collapses with 0.35s debounce
            self.collapseDebounceTimer?.invalidate()
            self.collapseDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
                self?.collapse()
            }
        }
        containerView.onClick = { [weak self] in
            guard let self = self else { return }
            if !self.isExpanded {
                self.expand()
            }
        }

        visualEffect.addSubview(containerView)
        panel.contentView?.addSubview(visualEffect)

        setupSubviews()
    }

    private func setupSubviews() {
        let headerHeight: CGFloat = 40

        // 1. Collapsed Ambient Dynamic Island View (Curved Button: 120x40, Radius 20)
        collapsedView = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 40))
        collapsedView.isHidden = true

        let cLogoSize: CGFloat = 30
        let cLogo = NSImageView(frame: NSRect(x: 12, y: (40 - cLogoSize) / 2, width: cLogoSize, height: cLogoSize))
        cLogo.imageScaling = .scaleProportionallyUpOrDown
        cLogo.image = loadSutraLogo(size: NSSize(width: cLogoSize, height: cLogoSize))
        collapsedView.addSubview(cLogo)

        // Right Daily Number (17pt bold monospace, exact 12pt right edge spacing matching left edge)
        todayCountLabel = NSTextField(labelWithString: "0")
        todayCountLabel.frame = NSRect(x: 82, y: 8, width: 26, height: 24)
        todayCountLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 17, weight: .bold)
        todayCountLabel.textColor = NSColor(calibratedWhite: 0.98, alpha: 1.0)
        todayCountLabel.alignment = .center
        todayCountLabel.isBezeled = false
        todayCountLabel.drawsBackground = false
        todayCountLabel.isEditable = false
        todayCountLabel.isSelectable = false
        collapsedView.addSubview(todayCountLabel)

        containerView.addSubview(collapsedView)

        // 2. Expanded Header View (480x40) - Minimalist Studio White
        let headerTrack = HoverTrackingView(frame: NSRect(x: 0, y: 0, width: 480, height: headerHeight))
        headerTrack.wantsLayer = true
        headerTrack.layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 0.60).cgColor

        let headerDivider = CALayer()
        headerDivider.frame = CGRect(x: 0, y: 0, width: 480, height: 1)
        headerDivider.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
        headerTrack.layer?.addSublayer(headerDivider)

        headerTrack.onClick = { [weak self] in
            self?.toggleRemainingItems()
        }
        headerView = headerTrack

        // Prominent Utra Logo (32x32)
        let logoSize: CGFloat = 32
        let logoView = NSImageView(frame: NSRect(x: 14, y: (headerHeight - logoSize) / 2, width: logoSize, height: logoSize))
        logoView.imageScaling = .scaleProportionallyUpOrDown
        logoView.image = loadSutraLogo(size: NSSize(width: logoSize, height: logoSize))
        headerView.addSubview(logoView)

        // Ephemeral Pin Toast Pill ("PINNED" / "UNPINNED")
        let toast = NSTextField(labelWithString: "PINNED")
        toast.frame = NSRect(x: 360, y: (headerHeight - 20) / 2, width: 76, height: 20)
        toast.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        toast.textColor = .white
        toast.alignment = .center
        toast.isBezeled = false
        toast.drawsBackground = true
        toast.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.18)
        toast.wantsLayer = true
        toast.layer?.cornerRadius = 10
        toast.layer?.masksToBounds = true
        toast.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.35).cgColor
        toast.layer?.borderWidth = 1.0
        toast.alphaValue = 0.0
        toast.isHidden = true
        headerView.addSubview(toast)
        self.pinToastLabel = toast

        // Borderless White Pin Button
        pinBtn = ClosureButton(frame: NSRect(x: 444, y: (headerHeight - 22) / 2, width: 22, height: 22)) { [weak self] in
            self?.togglePin()
        }
        pinBtn.isBordered = false
        headerView.addSubview(pinBtn)

        containerView.addSubview(headerView)

        // 3. Rows container view
        rowsContainerView = NSView(frame: NSRect(x: 0, y: 14, width: 480, height: 102))
        containerView.addSubview(rowsContainerView)

        // 4. Bottom Resize Handle Bar (14pt height)
        bottomDragBar = BottomResizeHandleView(frame: NSRect(x: 0, y: 0, width: 480, height: 14))
        bottomDragBar.onDragStart = { [weak self] in
            self?.autoDismissTimer?.invalidate()
            self?.collapseDebounceTimer?.invalidate()
        }
        bottomDragBar.onDragDelta = { [weak self] targetRows in
            guard let self = self else { return }
            if FloatingWakeBar.sessionPreferredVisibleRows != targetRows {
                FloatingWakeBar.sessionPreferredVisibleRows = targetRows
                self.render(animated: false)
            }
        }
        bottomDragBar.onDragEnd = { [weak self] in
            self?.resetTimer()
        }
        bottomDragBar.onDoubleClick = { [weak self] in
            self?.toggleRemainingItems()
        }
        containerView.addSubview(bottomDragBar)

        updatePinAppearance()
    }

    public func togglePin() {
        isPinned.toggle()
        updatePinAppearance()

        applyPinBounceAnimation(to: pinBtn)
        applyPinBounceAnimation(to: collapsedPinBtn)

        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)

        if isPinned {
            NSSound(named: "Tink")?.play()
            showPinToast(message: "PINNED")
            if !isExpanded {
                expand()
            }
        } else {
            NSSound(named: "Pop")?.play()
            showPinToast(message: "UNPINNED")
        }
    }

    private func applyPinBounceAnimation(to view: NSView?) {
        guard let layer = view?.layer else { return }
        let bounce = CAKeyframeAnimation(keyPath: "transform.scale")
        bounce.values = [1.0, 1.25, 0.95, 1.0]
        bounce.keyTimes = [0, 0.35, 0.7, 1.0]
        bounce.duration = 0.28
        bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(bounce, forKey: "pinBounce")
    }

    private func showPinToast(message: String) {
        pinToastLabel?.stringValue = message
        pinToastLabel?.isHidden = false
        pinToastLabel?.alphaValue = 0.0

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            pinToastLabel?.animator().alphaValue = 1.0
        }

        pinToastTimer?.invalidate()
        pinToastTimer = Timer.scheduledTimer(withTimeInterval: 1.1, repeats: false) { [weak self] _ in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.30
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self?.pinToastLabel?.animator().alphaValue = 0.0
            }, completionHandler: {
                if self?.pinToastLabel?.alphaValue == 0.0 {
                    self?.pinToastLabel?.isHidden = true
                }
            })
        }
    }

    private func makeWhitePinImage(pinned: Bool, size: NSSize = NSSize(width: 14, height: 14)) -> NSImage {
        let symbolName = pinned ? "pin.fill" : "pin"
        if let sym = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Pin") {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            if let configured = sym.withSymbolConfiguration(config) {
                configured.isTemplate = true
                return configured
            }
        }
        // Native AppKit vector drawing fallback — 100% pure white pushpin with white top
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.white.setFill()
        let head = NSBezierPath(ovalIn: NSRect(x: 3, y: 7, width: 8, height: 5.5))
        head.fill()
        let body = NSBezierPath(rect: NSRect(x: 5.5, y: 3.5, width: 3, height: 4))
        body.fill()
        let pinPoint = NSBezierPath()
        pinPoint.move(to: NSPoint(x: 7, y: 3.5))
        pinPoint.line(to: NSPoint(x: 7, y: 0.5))
        NSColor.white.setStroke()
        pinPoint.lineWidth = 1.2
        pinPoint.stroke()
        img.unlockFocus()
        img.isTemplate = true
        return img
    }

    private func updatePinAppearance() {
        let pinImg = makeWhitePinImage(pinned: isPinned)
        let alpha: CGFloat = isPinned ? 1.0 : 0.70

        if let pinBtn = pinBtn {
            pinBtn.isBordered = false
            pinBtn.wantsLayer = true
            pinBtn.layer?.cornerRadius = 0
            pinBtn.layer?.backgroundColor = NSColor.clear.cgColor
            pinBtn.layer?.borderColor = NSColor.clear.cgColor
            pinBtn.layer?.borderWidth = 0
            (pinBtn.cell as? NSButtonCell)?.highlightsBy = []
            pinBtn.focusRingType = .none
            pinBtn.image = pinImg
            pinBtn.imageScaling = .scaleProportionallyDown
            pinBtn.imagePosition = .imageOnly
            pinBtn.contentTintColor = NSColor(calibratedWhite: 1.0, alpha: alpha)
            pinBtn.title = ""
            pinBtn.attributedTitle = NSAttributedString()
        }

        if let collapsedPinBtn = collapsedPinBtn {
            collapsedPinBtn.isBordered = false
            collapsedPinBtn.wantsLayer = true
            collapsedPinBtn.layer?.cornerRadius = 0
            collapsedPinBtn.layer?.backgroundColor = NSColor.clear.cgColor
            collapsedPinBtn.layer?.borderColor = NSColor.clear.cgColor
            collapsedPinBtn.layer?.borderWidth = 0
            (collapsedPinBtn.cell as? NSButtonCell)?.highlightsBy = []
            collapsedPinBtn.focusRingType = .none
            collapsedPinBtn.image = pinImg
            collapsedPinBtn.imageScaling = .scaleProportionallyDown
            collapsedPinBtn.imagePosition = .imageOnly
            collapsedPinBtn.contentTintColor = NSColor(calibratedWhite: 1.0, alpha: alpha)
            collapsedPinBtn.title = ""
            collapsedPinBtn.attributedTitle = NSAttributedString()
        }
    }

    public func updateScheduledTodayCount() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let waiting = SutraBridge.shared.list(status: "waiting")
            let count = waiting.filter { $0.isScheduledForToday }.count
            DispatchQueue.main.async {
                self?.todayCountLabel?.stringValue = "\(count)"
            }
        }
    }

    public func expand() {
        collapseDebounceTimer?.invalidate()
        collapseDebounceTimer = nil
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil

        guard !isExpanded else { return }
        if activeThreads.isEmpty {
            refreshThreadsForFrontmostApp()
        }
        updateScheduledTodayCount()
        isExpanded = true
        render(animated: true)
    }

    public func collapse() {
        collapseDebounceTimer?.invalidate()
        collapseDebounceTimer = nil
        nudgeDismissTimer?.invalidate()
        nudgeDismissTimer = nil
        nudgeAppName = nil

        // If pinned, the bar stays expanded permanently!
        guard !isPinned else { return }
        guard isExpanded else { return }
        showsRemainingItems = false
        updateScheduledTodayCount()
        isExpanded = false
        render(animated: true)
    }

    public func presentNudge(fromDeepWorkApp appName: String) {
        let isNudgeEnabled = UserDefaults.standard.object(forKey: "SutraEnableNudge") as? Bool ?? true
        guard isNudgeEnabled else { return }
        nudgeDismissTimer?.invalidate()
        nudgeAppName = appName
        isExpanded = true
        render(animated: true)
        show()
        nudgeDismissTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            self?.dismissNudge()
        }
    }

    public func dismissNudge() {
        nudgeDismissTimer?.invalidate()
        nudgeDismissTimer = nil
        nudgeAppName = nil
        if activeThreads.isEmpty {
            collapse()
        } else {
            render(animated: true)
        }
    }

    public func toggleRemainingItems() {
        guard isExpanded else { return }
        showsRemainingItems.toggle()
        render(animated: true)
    }

    public func presentMultiple(threads: [SutraThread], preserveOrder: Bool = true) {
        guard !threads.isEmpty else {
            panel.orderOut(nil)
            autoDismissTimer?.invalidate()
            collapseDebounceTimer?.invalidate()
            return
        }
        activeThreads = preserveOrder ? threads : threads.sorted(by: { $0.created_at > $1.created_at })
        isExpanded = true
        render(animated: false)
        show()
    }

    public func relayout() {
        if panel != nil && panel.isVisible {
            render(animated: false)
        }
    }

    public func refreshThreadsForFrontmostApp() {
        let frontApp = NSWorkspace.shared.frontmostApplication
        let appName = frontApp?.localizedName ?? ""
        let bundleId = frontApp?.bundleIdentifier ?? ""
        let allWaiting = SutraBridge.shared.list(status: "waiting")
        guard !allWaiting.isEmpty else {
            activeThreads = []
            return
        }

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

        var orderedThreads: [SutraThread] = []
        let matchingIds = Set(matching.map { $0.id })
        orderedThreads.append(contentsOf: matching.sorted(by: { $0.created_at > $1.created_at }))
        let remaining = allWaiting.filter { !matchingIds.contains($0.id) }.sorted(by: { $0.created_at > $1.created_at })
        orderedThreads.append(contentsOf: remaining)

        activeThreads = orderedThreads
    }

    public func showPersistentIsland() {
        if !panel.isVisible {
            isExpanded = false
            render(animated: false)
            panel.orderFrontRegardless()
        }
    }

    public func toggleForFrontmostApp() {
        if isExpanded {
            isPinned = false
            updatePinAppearance()
            collapse()
            return
        }

        refreshThreadsForFrontmostApp()
        guard !activeThreads.isEmpty else { return }
        expand()
    }

    private func show() {
        panel.orderFrontRegardless()
        if !isPinned {
            resetTimer()
        }
    }

    private func resetTimer() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
        guard !isPinned else { return }
        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: 14.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.isPinned { return }
            self.collapse()
        }
    }

    private func getTopY(for screen: NSScreen) -> CGFloat {
        // True Dynamic Island: Flush to physical screen top (screen.frame.maxY).
        // Sits directly over the macOS menu bar with zero desktop window space consumption.
        return screen.frame.maxY
    }

    private func getOrigin(for screen: NSScreen, width: CGFloat, height: CGFloat) -> CGPoint {
        let topY = getTopY(for: screen)
        let placement = UserDefaults.standard.string(forKey: "SutraFloatingPlacement") ?? "top_left_30"
        let x: CGFloat
        switch placement {
        case "top_left_320":
            x = screen.frame.minX + 320
        case "top_center":
            x = screen.frame.midX - (width / 2)
        case "top_right":
            x = screen.frame.maxX - width - 30
        default: // "top_left_30" (around 30 pixels from top-left)
            x = screen.frame.minX + 30
        }
        let y = topY - height
        return CGPoint(x: x, y: y)
    }

    private func render(animated: Bool = false) {
        let rowHeight: CGFloat = 34
        let headerHeight: CGFloat = 40
        let footerHeight: CGFloat = 14

        let todayThreads = activeThreads.filter { $0.isScheduledForToday }
        let remainingThreads = activeThreads.filter { !$0.isScheduledForToday }

        var items: [IslandRowItem] = []
        if let nudge = nudgeAppName {
            items.append(.nudge(nudge))
        }

        if !showsRemainingItems {
            // Stage 1: Only items scheduled for today at top
            if todayThreads.isEmpty {
                items.append(.emptyToday)
            } else {
                for t in todayThreads {
                    items.append(.thread(t))
                }
            }
        } else {
            // Stage 2: Scheduled for today at top, thin white bar, then remaining items
            for t in todayThreads {
                items.append(.thread(t))
            }
            if !todayThreads.isEmpty && !remainingThreads.isEmpty {
                items.append(.separator)
            }
            for t in remainingThreads {
                items.append(.thread(t))
            }
            if items.isEmpty {
                items.append(.emptyToday)
            }
        }

        let totalContentHeight = items.reduce(CGFloat(0)) { $0 + $1.height }
        let maxAllowedRows = 8
        let maxAllowedHeight = CGFloat(maxAllowedRows) * rowHeight
        let isScrollable = totalContentHeight > maxAllowedHeight
        let rowsAreaHeight: CGFloat = isScrollable ? maxAllowedHeight : totalContentHeight
        let totalHeight = headerHeight + rowsAreaHeight + footerHeight

        let targetWidth: CGFloat = isExpanded ? 480 : 120
        let targetHeight: CGFloat = isExpanded ? totalHeight : 40
        let targetRadius: CGFloat = isExpanded ? 14 : 20

        updateScheduledTodayCount()

        // Anchor position
        if let screen = NSScreen.main {
            let origin = getOrigin(for: screen, width: targetWidth, height: targetHeight)
            let targetFrame = NSRect(origin: origin, size: CGSize(width: targetWidth, height: targetHeight))

            if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.22
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    self.panel.animator().setFrame(targetFrame, display: true)
                    self.visualEffect.animator().layer?.cornerRadius = targetRadius
                    AmbientPiPWindow.shared.repositionAdjacentToIsland(islandFrame: targetFrame, animated: true)
                }
            } else {
                panel.setFrame(targetFrame, display: true)
                visualEffect.layer?.cornerRadius = targetRadius
                AmbientPiPWindow.shared.repositionAdjacentToIsland(islandFrame: targetFrame, animated: false)
            }
        }

        containerView.frame = visualEffect.bounds

        // Toggle subview visibility based on state
        collapsedView.isHidden = isExpanded
        headerView.isHidden = !isExpanded
        rowsContainerView.isHidden = !isExpanded
        bottomDragBar.isHidden = !isExpanded

        if !isExpanded {
            updatePinAppearance()
            return
        }

        // Position fixed subviews for expanded state
        headerView.frame = NSRect(x: 0, y: totalHeight - headerHeight, width: 480, height: headerHeight)
        bottomDragBar.frame = NSRect(x: 0, y: 0, width: 480, height: footerHeight)
        rowsContainerView.frame = NSRect(x: 0, y: footerHeight, width: 480, height: rowsAreaHeight)

        updatePinAppearance()

        // Re-render rows content
        rowsContainerView.subviews.forEach { $0.removeFromSuperview() }

        if isScrollable {
            let scrollView = NSScrollView(frame: rowsContainerView.bounds)
            scrollView.autoresizingMask = [.width, .height]
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            let scroller = TerracottaScroller()
            scrollView.verticalScroller = scroller
            scrollView.hasVerticalScroller = true
            scrollView.autohidesScrollers = false

            let docView = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: totalContentHeight))
            var rowY = totalContentHeight
            for item in items {
                rowY -= item.height
                let frame = NSRect(x: 12, y: rowY, width: 456, height: item.height)
                let view = viewForItem(item, frame: frame)
                docView.addSubview(view)
            }
            scrollView.documentView = docView
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: totalContentHeight - rowsAreaHeight))
            rowsContainerView.addSubview(scrollView)
        } else {
            var currentY = rowsAreaHeight
            for item in items {
                currentY -= item.height
                let frame = NSRect(x: 12, y: currentY, width: 456, height: item.height)
                let view = viewForItem(item, frame: frame)
                rowsContainerView.addSubview(view)
            }
        }
    }

    private func viewForItem(_ item: IslandRowItem, frame: NSRect) -> NSView {
        switch item {
        case .nudge(let appName):
            return makeNudgeRow(fromApp: appName, frame: frame)
        case .thread(let thread):
            return makeThreadRow(thread: thread, frame: frame)
        case .separator:
            return makeSeparatorRow(frame: frame)
        case .emptyToday:
            return makeEmptyTodayRow(frame: frame)
        }
    }

    private func makeNudgeRow(fromApp appName: String, frame: NSRect) -> NSView {
        let row = NSView(frame: frame)
        row.wantsLayer = true
        row.layer?.backgroundColor = NSColor(calibratedRed: 0.22, green: 0.12, blue: 0.08, alpha: 0.90).cgColor
        row.layer?.cornerRadius = 6
        row.layer?.borderColor = NSColor(calibratedRed: 0.90, green: 0.45, blue: 0.20, alpha: 0.45).cgColor
        row.layer?.borderWidth = 1.0

        let bulb = NSTextField(labelWithString: "💡")
        bulb.font = NSFont.systemFont(ofSize: 12)
        bulb.frame = NSRect(x: 8, y: 7, width: 20, height: 18)
        row.addSubview(bulb)

        let label = NSTextField(labelWithString: "Switched from \(appName). Leave a thread cue?")
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = NSColor(calibratedWhite: 0.95, alpha: 1.0)
        label.frame = NSRect(x: 30, y: 8, width: 260, height: 18)
        label.cell?.lineBreakMode = .byTruncatingTail
        row.addSubview(label)

        let cueBtn = ClosureButton(frame: NSRect(x: 298, y: 6, width: 112, height: 22)) { [weak self] in
            self?.dismissNudge()
            QuickCueHUD.shared.show()
        }
        cueBtn.isBordered = false
        cueBtn.wantsLayer = true
        cueBtn.layer?.cornerRadius = 11
        cueBtn.layer?.backgroundColor = NSColor(calibratedRed: 0.90, green: 0.45, blue: 0.20, alpha: 1.0).cgColor
        cueBtn.attributedTitle = NSAttributedString(string: "Drop Cue ⌥Space", attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 9.5, weight: .bold)
        ])
        row.addSubview(cueBtn)

        let closeBtn = ClosureButton(frame: NSRect(x: 418, y: 7, width: 20, height: 20)) { [weak self] in
            self?.dismissNudge()
        }
        closeBtn.isBordered = false
        closeBtn.wantsLayer = true
        closeBtn.layer?.cornerRadius = 10
        closeBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.25, alpha: 0.8).cgColor
        closeBtn.attributedTitle = NSAttributedString(string: "✕", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.85, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 10, weight: .medium)
        ])
        row.addSubview(closeBtn)

        return row
    }

    private func makeSeparatorRow(frame: NSRect) -> NSView {
        let row = NSView(frame: frame)
        let line = CALayer()
        line.frame = CGRect(x: 4, y: (frame.height - 1) / 2, width: frame.width - 8, height: 1)
        line.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.22).cgColor
        row.wantsLayer = true
        row.layer?.addSublayer(line)
        return row
    }

    private func makeEmptyTodayRow(frame: NSRect) -> NSView {
        let row = HoverTrackingView(frame: frame)
        row.onClick = { [weak self] in
            self?.toggleRemainingItems()
        }

        let titleLabel = NSTextField(labelWithString: "No items scheduled for today")
        titleLabel.frame = NSRect(x: 26, y: 7, width: 230, height: 18)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = NSColor(calibratedWhite: 0.70, alpha: 1.0)
        row.addSubview(titleLabel)

        let hintLabel = NSTextField(labelWithString: "Click bar to view all ▾")
        hintLabel.frame = NSRect(x: 282, y: 7, width: 160, height: 18)
        hintLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        hintLabel.textColor = NSColor(calibratedWhite: 0.50, alpha: 1.0)
        hintLabel.alignment = .right
        row.addSubview(hintLabel)

        return row
    }

    private func makeThreadRow(thread: SutraThread, frame: NSRect) -> NSView {
        let row = NSView(frame: frame)

        let isStalePromptEnabled = UserDefaults.standard.object(forKey: "SutraEnableStalePrompt") as? Bool ?? true
        let isStale = isStalePromptEnabled && ((Date().timeIntervalSince1970 * 1000 - Double(thread.created_at)) > 24 * 3600 * 1000)

        // App Icon (Click to Pin to Ambient PiP)
        let appIcon = ClosureButton(frame: NSRect(x: 0, y: 7, width: 20, height: 20)) {
            AmbientPiPWindow.shared.pin(thread: thread)
        }
        appIcon.isBordered = false
        appIcon.image = iconForApp(appName: thread.anchor?.app_name)
        appIcon.toolTip = "Pin to Ambient Floating PiP card"
        row.addSubview(appIcon)

        // Title Label
        let titleLabel = NSTextField(labelWithString: thread.title)
        titleLabel.frame = NSRect(x: 26, y: 7, width: 200, height: 18)
        titleLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.cell?.lineBreakMode = .byTruncatingTail
        row.addSubview(titleLabel)

        // Time ago (Zinc, or Terracotta Amber if Stale)
        let timeLabel = NSTextField(labelWithString: thread.timeAgo)
        timeLabel.frame = NSRect(x: 230, y: 7, width: 44, height: 18)
        timeLabel.font = NSFont.systemFont(ofSize: 11.5, weight: isStale ? .bold : .medium)
        timeLabel.textColor = isStale ? NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.22, alpha: 1.0) : NSColor(calibratedWhite: 0.70, alpha: 1.0)
        timeLabel.alignment = .right
        if isStale {
            timeLabel.toolTip = "Stale thread (> 24h old)"
        }
        row.addSubview(timeLabel)

        // [Resume] Hero Action Pill - matches Sanctuary
        let resumeBtn = ClosureButton(frame: NSRect(x: 284, y: 7, width: 62, height: 20)) { [weak self] in
            _ = SutraBridge.shared.resume(threadId: thread.id)
            NSSound(named: "Glass")?.play()
            self?.isPinned = false
            self?.updatePinAppearance()
            self?.collapse()
        }
        resumeBtn.isBordered = false
        resumeBtn.wantsLayer = true
        resumeBtn.layer?.backgroundColor = NSColor.white.cgColor
        resumeBtn.layer?.cornerRadius = 4
        resumeBtn.layer?.shadowColor = NSColor.black.cgColor
        resumeBtn.layer?.shadowOpacity = 0.25
        resumeBtn.layer?.shadowOffset = CGSize(width: 0, height: -1)
        resumeBtn.layer?.shadowRadius = 1.5
        resumeBtn.attributedTitle = NSAttributedString(string: "Resume", attributes: [
            .foregroundColor: NSColor.black,
            .font: NSFont.systemFont(ofSize: 10, weight: .bold)
        ])
        row.addSubview(resumeBtn)

        // Snooze Pill (4h normal, 3d if Stale)
        let snoozeHours = isStale ? 72 : 4
        let snoozeTitle = isStale ? "3d" : "4h"
        let snoozeBtn = ClosureButton(frame: NSRect(x: 356, y: 7, width: 44, height: 20)) { [weak self] in
            _ = SutraBridge.shared.snooze(threadId: thread.id, hours: snoozeHours)
            self?.activeThreads.removeAll(where: { $0.id == thread.id })
            if let active = self?.activeThreads, !active.isEmpty {
                self?.render()
            } else {
                self?.isPinned = false
                self?.updatePinAppearance()
                self?.collapse()
            }
        }
        snoozeBtn.isBordered = false
        snoozeBtn.wantsLayer = true
        snoozeBtn.layer?.cornerRadius = 10
        snoozeBtn.layer?.backgroundColor = isStale
            ? NSColor(calibratedRed: 0.30, green: 0.16, blue: 0.10, alpha: 0.95).cgColor
            : NSColor(calibratedWhite: 0.25, alpha: 0.95).cgColor
        snoozeBtn.layer?.borderColor = isStale ? NSColor(calibratedRed: 0.90, green: 0.45, blue: 0.20, alpha: 0.50).cgColor : NSColor.clear.cgColor
        snoozeBtn.layer?.borderWidth = isStale ? 1.0 : 0
        snoozeBtn.attributedTitle = NSAttributedString(string: snoozeTitle, attributes: [
            .foregroundColor: isStale ? NSColor(calibratedRed: 0.95, green: 0.75, blue: 0.60, alpha: 1.0) : NSColor.white,
            .font: NSFont.systemFont(ofSize: 10.5, weight: .medium)
        ])
        snoozeBtn.toolTip = isStale ? "Snooze 3 days" : "Snooze 4 hours"
        row.addSubview(snoozeBtn)

        // [✓] Circle
        let doneBtn = ClosureButton(frame: NSRect(x: 418, y: 7, width: 20, height: 20)) { [weak self] in
            _ = SutraBridge.shared.done(threadId: thread.id)
            NSSound(named: "Glass")?.play()
            self?.activeThreads.removeAll(where: { $0.id == thread.id })
            if let active = self?.activeThreads, !active.isEmpty {
                self?.render()
            } else {
                self?.isPinned = false
                self?.updatePinAppearance()
                self?.collapse()
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
            Bundle.main.path(forResource: "logo", ofType: "png") ?? "",
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("assets/logo.png").path,
            Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("assets/logo.png").path
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
    var onClick: (() -> Void)?
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

    override func mouseDown(with event: NSEvent) {
        onClick?()
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
    var onMouseEnter: (() -> Void)?
    var onMouseExit: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    init(frame: NSRect, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: frame)
        super.title = ""
        attributedTitle = NSAttributedString(string: "")
        target = self
        action = #selector(trigger)
        sendAction(on: [.leftMouseUp])
        contentTintColor = .white
        (cell as? NSButtonCell)?.highlightsBy = []
        focusRingType = .none
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc func trigger() { onClick() }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let opts: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let ta = NSTrackingArea(rect: bounds, options: opts, owner: self, userInfo: nil)
        addTrackingArea(ta)
        self.trackingArea = ta
    }

    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onMouseEnter?()
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onMouseExit?()
    }

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
        // Modern overlay: no heavy slot background
    }

    public override func drawKnob() {
        let rawKnob = rect(for: .knob)
        guard rawKnob.height > 0 else { return }
        let thinW: CGFloat = 3.5
        let knobX = rawKnob.maxX - thinW - 3
        let knobRect = NSRect(x: knobX, y: rawKnob.minY + 2, width: thinW, height: max(16, rawKnob.height - 4))
        let path = NSBezierPath(roundedRect: knobRect, xRadius: thinW / 2, yRadius: thinW / 2)
        NSColor(calibratedWhite: 1.0, alpha: 0.28).setFill()
        path.fill()
    }
}
