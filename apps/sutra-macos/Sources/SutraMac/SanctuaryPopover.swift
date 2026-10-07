import AppKit

public final class SanctuaryPopover: NSObject, NSTextFieldDelegate {
    public static let shared = SanctuaryPopover()

    private var panel: KeyFocusPanel!
    private var visualEffect: NSView!
    private var containerView: NSView!
    private var searchField: NSTextField!
    private var chipsScrollView: NSScrollView!
    private var chipsContainer: NSView!
    private var scrollView: NSScrollView!
    private var threadListView: NSView!
    private var headerView: NSView!
    private var footerView: NSView!
    private var bottomDragBar: BottomResizeHandleView!
    public static var sessionPreferredHeight: CGFloat = 460
    
    private var allThreads: [SutraThread] = []
    private var filteredThreads: [SutraThread] = []
    private var selectedAppFilter: String = "All"
    private var searchQuery: String = ""
    private var expandedThreadIds: Set<String> = []
    private var isTodaySectionExpanded: Bool = true
    private var globalEventMonitor: Any?
    private weak var anchorButton: NSStatusBarButton?

    public override init() {
        super.init()
        setupPanel()
    }

    private func setupPanel() {
        panel = KeyFocusPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: SanctuaryPopover.sessionPreferredHeight),
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
        visualEffect.layer?.backgroundColor = NSColor(calibratedWhite: 0.05, alpha: 0.98).cgColor
        visualEffect.layer?.cornerRadius = 14
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.10).cgColor
        visualEffect.layer?.borderWidth = 1.0

        containerView = NSView(frame: visualEffect.bounds)
        containerView.autoresizingMask = [.width, .height]
        visualEffect.addSubview(containerView)

        panel.contentView?.addSubview(visualEffect)
    }

    public func toggle(relativeTo button: NSStatusBarButton? = nil) {
        if let btn = button { anchorButton = btn }
        if panel.isVisible {
            dismiss()
        } else {
            present(relativeTo: anchorButton)
        }
    }

    public func present(relativeTo button: NSStatusBarButton? = nil) {
        if let btn = button { anchorButton = btn }
        fetchData()
        if expandedThreadIds.isEmpty, let top = allThreads.first, top.cue_type.lowercased() == "checklist" || top.cue_type.lowercased() == "link" || top.cue_type.lowercased() == "file" {
            expandedThreadIds.insert(top.id)
        }
        buildUI()
        positionPanel(relativeTo: anchorButton)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Start monitoring clicks outside to dismiss
        if globalEventMonitor == nil {
            globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self = self, self.panel.isVisible else { return }
                let mouseLoc = NSEvent.mouseLocation
                if !self.panel.frame.contains(mouseLoc) {
                    self.dismiss()
                }
            }
        }
    }

    public func dismiss() {
        panel.orderOut(nil)
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
    }

    public func refreshIfVisible() {
        if panel.isVisible {
            fetchData()
            applyFilters()
            renderThreadList()
            renderChips()
        }
    }

    private func fetchData() {
        allThreads = SutraBridge.shared.list(status: "waiting").sorted(by: { $0.created_at > $1.created_at })
        applyFilters()
    }

    private func applyFilters() {
        filteredThreads = allThreads.filter { thread in
            let matchesApp: Bool
            if selectedAppFilter == "All" {
                matchesApp = true
            } else {
                matchesApp = (thread.anchor?.app_name ?? "General").lowercased() == selectedAppFilter.lowercased()
            }

            let matchesSearch: Bool
            if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                matchesSearch = true
            } else {
                let q = searchQuery.lowercased()
                let titleMatch = thread.title.lowercased().contains(q)
                let notesMatch = (thread.notes ?? "").lowercased().contains(q)
                let appMatch = (thread.anchor?.app_name ?? "").lowercased().contains(q)
                matchesSearch = titleMatch || notesMatch || appMatch
            }

            return matchesApp && matchesSearch
        }
    }

    private func positionPanel(relativeTo button: NSStatusBarButton?) {
        let screen = button?.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let panelWidth: CGFloat = 460
        let panelHeight: CGFloat = SanctuaryPopover.sessionPreferredHeight

        if let btnWindow = button?.window, let btnFrame = button?.frame {
            let btnScreenRect = btnWindow.convertToScreen(btnFrame)
            var originX = btnScreenRect.midX - (panelWidth / 2)
            if originX + panelWidth > screen.visibleFrame.maxX - 10 {
                originX = screen.visibleFrame.maxX - panelWidth - 10
            }
            if originX < screen.visibleFrame.minX + 10 {
                originX = screen.visibleFrame.minX + 10
            }
            let originY = btnScreenRect.minY - panelHeight - 8
            panel.setFrame(NSRect(x: originX, y: originY, width: panelWidth, height: panelHeight), display: true)
        } else {
            let originX = screen.visibleFrame.maxX - panelWidth - 20
            let originY = screen.visibleFrame.maxY - panelHeight - 10
            panel.setFrame(NSRect(x: originX, y: originY, width: panelWidth, height: panelHeight), display: true)
        }
    }

    // MARK: - UI Construction

    private func buildUI() {
        containerView.subviews.forEach { $0.removeFromSuperview() }

        let width = containerView.bounds.width
        let height = containerView.bounds.height

        // 1. Header (y: height - 48 ... height)
        headerView = NSView(frame: NSRect(x: 0, y: height - 48, width: width, height: 48))
        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 1.0).cgColor

        // Logo
        // Logo (Bigger 32x32)
        let logoView = NSImageView(frame: NSRect(x: 16, y: 8, width: 32, height: 32))
        logoView.image = loadSutraLogo(size: NSSize(width: 32, height: 32))
        headerView.addSubview(logoView)

        // Title
        let titleLabel = NSTextField()
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.attributedStringValue = NSAttributedString(string: "Sutra Sanctuary", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.98, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .kern: 0.3
        ])
        titleLabel.sizeToFit()
        let titleH = titleLabel.frame.height
        titleLabel.frame = NSRect(x: 56, y: (48 - titleH) / 2, width: titleLabel.frame.width, height: titleH)
        headerView.addSubview(titleLabel)

        // Integrated Brand Capsule (Option 1: ● 28 Waiting)
        let countText = NSMutableAttributedString()
        countText.append(NSAttributedString(string: "● ", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.95, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 7.5, weight: .bold)
        ]))
        countText.append(NSAttributedString(string: "\(allThreads.count) ", attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 10, weight: .bold)
        ]))
        countText.append(NSAttributedString(string: "Waiting", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.82, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 9.5, weight: .medium)
        ]))

        let pillX = titleLabel.frame.maxX + 10
        let pillH: CGFloat = 22
        let pillW: CGFloat = ceil(countText.size().width) + 18
        let pillY = (48 - pillH) / 2

        let countBadgeBtn = ClosureButton(frame: NSRect(x: pillX, y: pillY, width: pillW, height: pillH)) { }
        countBadgeBtn.isBordered = false
        countBadgeBtn.wantsLayer = true
        countBadgeBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1.0).cgColor
        countBadgeBtn.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor
        countBadgeBtn.layer?.borderWidth = 1.0
        countBadgeBtn.layer?.cornerRadius = pillH / 2
        countBadgeBtn.attributedTitle = countText
        countBadgeBtn.refusesFirstResponder = true
        headerView.addSubview(countBadgeBtn)

        // Quick Cue Button
        let cueBtn = ClosureButton(frame: NSRect(x: width - 142, y: 12, width: 96, height: 24)) { [weak self] in
            self?.dismiss()
            QuickCueHUD.shared.toggle()
        }
        cueBtn.isBordered = false
        cueBtn.wantsLayer = true
        cueBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1.0).cgColor
        cueBtn.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.15).cgColor
        cueBtn.layer?.borderWidth = 1.0
        cueBtn.layer?.cornerRadius = 6
        cueBtn.attributedTitle = NSAttributedString(string: "+ Cue (Right ⌥)", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.92, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        ])
        headerView.addSubview(cueBtn)

        // Dismiss Button
        let closeBtn = ClosureButton(frame: NSRect(x: width - 36, y: 12, width: 24, height: 24)) { [weak self] in
            self?.dismiss()
        }
        closeBtn.isBordered = false
        closeBtn.wantsLayer = true
        closeBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1.0).cgColor
        closeBtn.layer?.cornerRadius = 12
        closeBtn.attributedTitle = NSAttributedString(string: "✕", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.85, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 11, weight: .medium)
        ])
        headerView.addSubview(closeBtn)

        containerView.addSubview(headerView)

        // 2. Search Field (y: height - 84)
        searchField = NSTextField(frame: NSRect(x: 16, y: height - 82, width: width - 32, height: 26))
        searchField.placeholderAttributedString = NSAttributedString(
            string: "Search threads, hypotheses, or apps...",
            attributes: [
                .foregroundColor: NSColor(calibratedWhite: 0.65, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 11)
            ]
        )
        searchField.font = NSFont.systemFont(ofSize: 11)
        searchField.textColor = .white
        searchField.backgroundColor = NSColor(calibratedWhite: 0.15, alpha: 1.0)
        searchField.isBezeled = false
        searchField.isEditable = true
        searchField.isSelectable = true
        searchField.focusRingType = .none
        searchField.wantsLayer = true
        searchField.layer?.cornerRadius = 6
        searchField.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor
        searchField.layer?.borderWidth = 1.0
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(onSearchChanged)
        containerView.addSubview(searchField)

        // 3. Filter Chips Horizontal Carousel (y: height - 116, height: 26)
        chipsScrollView = NSScrollView(frame: NSRect(x: 16, y: height - 116, width: width - 32, height: 26))
        chipsScrollView.drawsBackground = false
        chipsScrollView.hasHorizontalScroller = false
        chipsScrollView.hasVerticalScroller = false
        chipsScrollView.autohidesScrollers = true

        chipsContainer = NSView(frame: NSRect(x: 0, y: 0, width: width - 32, height: 26))
        chipsScrollView.documentView = chipsContainer
        containerView.addSubview(chipsScrollView)
        renderChips()

        // 4. Thread List Scroll View (y: 50 ... height - 124)
        let footerTotalHeight: CGFloat = 38 + 12
        let listHeight = (height - 124) - footerTotalHeight
        scrollView = NSScrollView(frame: NSRect(x: 0, y: footerTotalHeight, width: width, height: listHeight))
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.verticalScroller = TerracottaScroller()

        threadListView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: listHeight))
        scrollView.documentView = threadListView
        containerView.addSubview(scrollView)

        renderThreadList()

        // 5. Footer (y: 12 ... 50)
        footerView = NSView(frame: NSRect(x: 0, y: 12, width: width, height: 38))
        footerView.wantsLayer = true
        footerView.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1.0).cgColor

        // Divider
        let divider = NSBox(frame: NSRect(x: 0, y: 37, width: width, height: 1))
        divider.boxType = .separator
        footerView.addSubview(divider)

        // Docs Button
        let docsBtn = ClosureButton(frame: NSRect(x: 14, y: 8, width: 80, height: 22)) {
            if let guideUrl = Bundle.main.url(forResource: "USER_GUIDE", withExtension: "html") {
                NSWorkspace.shared.open(guideUrl)
            } else {
                let guidePath = "/Users/raman/Desktop/AI/Sutra/docs/USER_GUIDE.html"
                if FileManager.default.fileExists(atPath: guidePath) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: guidePath))
                }
            }
        }
        docsBtn.isBordered = false
        docsBtn.wantsLayer = true
        docsBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1.0).cgColor
        docsBtn.layer?.cornerRadius = 4
        docsBtn.attributedTitle = NSAttributedString(string: "📖 Docs", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.88, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 10, weight: .regular)
        ])
        footerView.addSubview(docsBtn)

        // Restart Button
        let restartBtn = ClosureButton(frame: NSRect(x: width - 150, y: 8, width: 75, height: 22)) { [weak self] in
            self?.dismiss()
            NotificationCenter.default.post(name: NSNotification.Name("RestartSutraApp"), object: nil)
        }
        restartBtn.isBordered = false
        restartBtn.wantsLayer = true
        restartBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1.0).cgColor
        restartBtn.layer?.cornerRadius = 4
        restartBtn.attributedTitle = NSAttributedString(string: "⌃⌥R Restart", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.88, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 10, weight: .regular)
        ])
        footerView.addSubview(restartBtn)

        // Quit Button
        let quitBtn = ClosureButton(frame: NSRect(x: width - 68, y: 8, width: 54, height: 22)) {
            NSApp.terminate(nil)
        }
        quitBtn.isBordered = false
        quitBtn.wantsLayer = true
        quitBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1.0).cgColor
        quitBtn.layer?.cornerRadius = 4
        quitBtn.attributedTitle = NSAttributedString(string: "⌘Q Quit", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.88, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 10, weight: .regular)
        ])
        footerView.addSubview(quitBtn)

        containerView.addSubview(footerView)

        // 6. Bottom Resize Handle Bar (y: 0 ... 12)
        bottomDragBar = BottomResizeHandleView(frame: NSRect(x: 0, y: 0, width: width, height: 12))
        var dragStartHeight: CGFloat = SanctuaryPopover.sessionPreferredHeight
        bottomDragBar.onDragStart = { [weak self] in
            guard let self = self else { return }
            dragStartHeight = self.panel.frame.height
        }
        bottomDragBar.onPixelDragDelta = { [weak self] deltaY in
            guard let self = self else { return }
            self.applyDynamicHeight(dragStartHeight + deltaY)
        }
        bottomDragBar.onDragEnd = { [weak self] in
            guard let self = self else { return }
            SanctuaryPopover.sessionPreferredHeight = self.panel.frame.height
        }
        bottomDragBar.onDoubleClick = { [weak self] in
            guard let self = self else { return }
            let screen = self.anchorButton?.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
            let maxH = min(720, screen.visibleFrame.height - 40)
            if self.panel.frame.height > 520 {
                self.applyDynamicHeight(460)
            } else {
                self.applyDynamicHeight(maxH)
            }
        }
        containerView.addSubview(bottomDragBar)
    }

    private func applyDynamicHeight(_ newHeight: CGFloat) {
        let screen = anchorButton?.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let maxAllowed = min(800, max(460, screen.visibleFrame.height - 40))
        let clampedHeight = max(380, min(maxAllowed, newHeight))

        let width: CGFloat = 460
        let topY: CGFloat
        var originX: CGFloat
        if let btnWindow = anchorButton?.window, let btnFrame = anchorButton?.frame {
            let btnScreenRect = btnWindow.convertToScreen(btnFrame)
            originX = btnScreenRect.midX - (width / 2)
            if originX + width > screen.visibleFrame.maxX - 10 { originX = screen.visibleFrame.maxX - width - 10 }
            if originX < screen.visibleFrame.minX + 10 { originX = screen.visibleFrame.minX + 10 }
            topY = btnScreenRect.minY - 8
        } else {
            originX = screen.visibleFrame.maxX - width - 20
            topY = screen.visibleFrame.maxY - 10
        }

        let originY = topY - clampedHeight
        panel.setFrame(NSRect(x: originX, y: originY, width: width, height: clampedHeight), display: true)
        SanctuaryPopover.sessionPreferredHeight = clampedHeight

        // Update layout frames
        let h = clampedHeight
        headerView.frame = NSRect(x: 0, y: h - 48, width: width, height: 48)
        searchField.frame = NSRect(x: 16, y: h - 82, width: width - 32, height: 26)
        chipsScrollView.frame = NSRect(x: 16, y: h - 116, width: width - 32, height: 26)

        let footerTotalHeight: CGFloat = 50
        let listHeight = (h - 124) - footerTotalHeight
        scrollView.frame = NSRect(x: 0, y: footerTotalHeight, width: width, height: listHeight)
        footerView.frame = NSRect(x: 0, y: 12, width: width, height: 38)
        bottomDragBar.frame = NSRect(x: 0, y: 0, width: width, height: 12)

        renderThreadList()
    }

    // MARK: - Chips Rendering

    private func renderChips() {
        chipsContainer.subviews.forEach { $0.removeFromSuperview() }

        var appCounts: [String: Int] = ["All": allThreads.count]
        for t in allThreads {
            let app = t.anchor?.app_name ?? "General"
            appCounts[app, default: 0] += 1
        }

        var x: CGFloat = 0
        let sortedKeys = ["All"] + appCounts.keys.filter { $0 != "All" }.sorted()

        for key in sortedKeys {
            let count = appCounts[key] ?? 0
            let title = "\(key) (\(count))"
            let btnWidth: CGFloat = CGFloat(title.count * 7 + 18)

            let isSelected = key.lowercased() == selectedAppFilter.lowercased()
            let chip = ClosureButton(frame: NSRect(x: x, y: 1, width: btnWidth, height: 22)) { [weak self] in
                self?.selectedAppFilter = key
                self?.applyFilters()
                self?.renderChips()
                self?.renderThreadList()
            }
            chip.identifier = NSUserInterfaceItemIdentifier(key)
            chip.isBordered = false
            chip.wantsLayer = true
            chip.layer?.cornerRadius = 11

            if isSelected {
                chip.layer?.backgroundColor = NSColor(calibratedWhite: 0.95, alpha: 1.0).cgColor
                chip.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.25).cgColor
                chip.layer?.borderWidth = 1.0
                chip.attributedTitle = NSAttributedString(string: title, attributes: [
                    .foregroundColor: NSColor(calibratedWhite: 0.05, alpha: 1.0),
                    .font: NSFont.systemFont(ofSize: 9.5, weight: .bold)
                ])
            } else {
                chip.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1.0).cgColor
                chip.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
                chip.layer?.borderWidth = 1.0
                chip.attributedTitle = NSAttributedString(string: title, attributes: [
                    .foregroundColor: NSColor(calibratedWhite: 0.75, alpha: 1.0),
                    .font: NSFont.systemFont(ofSize: 9.5, weight: .medium)
                ])
            }

            chipsContainer.addSubview(chip)
            x += btnWidth + 6
        }

        let totalWidth = max(chipsScrollView.bounds.width, x)
        chipsContainer.frame = NSRect(x: 0, y: 0, width: totalWidth, height: 26)

        if let selectedView = chipsContainer.subviews.first(where: { ($0 as? NSButton)?.identifier?.rawValue.lowercased() == selectedAppFilter.lowercased() }) {
            _ = selectedView.scrollToVisible(selectedView.bounds.insetBy(dx: -10, dy: 0))
        }
    }

    // MARK: - Thread List Rendering

    private func calculateRowHeight(for thread: SutraThread) -> CGFloat {
        let baseHeight: CGFloat = 48
        guard expandedThreadIds.contains(thread.id) else { return baseHeight }

        switch thread.cue_type.lowercased() {
        case "checklist":
            let count = max(1, thread.checklistItems.count)
            return baseHeight + CGFloat(count * 24 + 16)
        case "url", "link":
            return baseHeight + 42
        case "file":
            return baseHeight + 42
        default:
            let lines = (thread.notes ?? "").components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let count = max(1, min(lines.count, 4))
            return baseHeight + CGFloat(count * 16 + 20)
        }
    }

    private func toggleExpand(threadId: String) {
        if expandedThreadIds.contains(threadId) {
            expandedThreadIds.remove(threadId)
        } else {
            expandedThreadIds.insert(threadId)
        }
        renderThreadList()
    }

    private func createTodaySectionBar(count: Int, width: CGFloat) -> NSView {
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 32))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = count > 0 
            ? NSColor(calibratedRed: 0.16, green: 0.12, blue: 0.10, alpha: 1.0).cgColor
            : NSColor(calibratedWhite: 0.12, alpha: 1.0).cgColor

        let border = CALayer()
        border.frame = CGRect(x: 0, y: 0, width: width, height: 1)
        border.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
        bar.layer?.addSublayer(border)

        let chevron = isTodaySectionExpanded ? "▾" : "▸"
        let btn = ClosureButton(frame: NSRect(x: 16, y: 3, width: width - 32, height: 26)) { [weak self] in
            guard let self = self else { return }
            self.isTodaySectionExpanded.toggle()
            self.renderThreadList()
        }
        btn.isBordered = false
        btn.alignment = .left

        let titleStr = NSMutableAttributedString(
            string: "Scheduled for Today ",
            attributes: [
                .foregroundColor: count > 0 ? NSColor(calibratedWhite: 0.98, alpha: 1.0) : NSColor(calibratedWhite: 0.6, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 11, weight: .bold)
            ]
        )
        let countBadgeStr = NSAttributedString(
            string: "(\(count))  \(chevron)",
            attributes: [
                .foregroundColor: count > 0 ? NSColor(calibratedWhite: 0.70, alpha: 1.0) : NSColor(calibratedWhite: 0.45, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 10.5, weight: .medium)
            ]
        )
        titleStr.append(countBadgeStr)
        btn.attributedTitle = titleStr
        bar.addSubview(btn)

        return bar
    }

    private func renderThreadList() {
        threadListView.subviews.forEach { $0.removeFromSuperview() }

        let width = containerView.bounds.width
        let todayThreads = filteredThreads.filter { $0.isScheduledForToday }
        let otherThreads = filteredThreads.filter { !$0.isScheduledForToday }

        let barHeight: CGFloat = 32
        var totalHeight: CGFloat = barHeight

        if isTodaySectionExpanded {
            for thread in todayThreads {
                totalHeight += calculateRowHeight(for: thread)
            }
        }

        if !otherThreads.isEmpty && !todayThreads.isEmpty && isTodaySectionExpanded {
            totalHeight += 24
        }

        for thread in otherThreads {
            totalHeight += calculateRowHeight(for: thread)
        }

        totalHeight = max(totalHeight, scrollView.bounds.height)
        threadListView.frame = NSRect(x: 0, y: 0, width: width, height: totalHeight)

        if filteredThreads.isEmpty {
            let emptyLabel = NSTextField(labelWithString: allThreads.isEmpty ? "No waiting threads — Mind is clear" : "No matching threads found")
            emptyLabel.frame = NSRect(x: 20, y: totalHeight / 2 - 10, width: width - 40, height: 20)
            emptyLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            emptyLabel.textColor = NSColor(calibratedWhite: 0.5, alpha: 1.0)
            emptyLabel.alignment = .center
            threadListView.addSubview(emptyLabel)
            return
        }

        var currentY = totalHeight

        // 1. Scheduled for Today Collapsible Header Bar
        currentY -= barHeight
        let todayBar = createTodaySectionBar(count: todayThreads.count, width: width)
        todayBar.frame.origin.y = currentY
        threadListView.addSubview(todayBar)

        // 2. Today's Threads (if expanded)
        if isTodaySectionExpanded {
            for thread in todayThreads {
                let rowH = calculateRowHeight(for: thread)
                currentY -= rowH
                let row = createThreadRow(thread: thread, frame: NSRect(x: 0, y: currentY, width: width, height: rowH), isTodayAccent: true)
                threadListView.addSubview(row)
            }
        }

        // 3. Section divider between Today and Other Threads
        if !otherThreads.isEmpty && !todayThreads.isEmpty && isTodaySectionExpanded {
            currentY -= 24
            let otherHeader = NSTextField(labelWithString: "Other Waiting Threads")
            otherHeader.frame = NSRect(x: 16, y: currentY + 4, width: width - 32, height: 16)
            otherHeader.font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
            otherHeader.textColor = NSColor(calibratedWhite: 0.45, alpha: 1.0)
            threadListView.addSubview(otherHeader)
        }

        // 4. Other Waiting Threads
        for thread in otherThreads {
            let rowH = calculateRowHeight(for: thread)
            currentY -= rowH
            let row = createThreadRow(thread: thread, frame: NSRect(x: 0, y: currentY, width: width, height: rowH), isTodayAccent: false)
            threadListView.addSubview(row)
        }

        // Scroll to top
        if let docView = scrollView.documentView {
            docView.scroll(NSPoint(x: 0, y: totalHeight - scrollView.bounds.height))
        }
    }

    private func createThreadRow(thread: SutraThread, frame: NSRect, isTodayAccent: Bool = false) -> NSView {
        let row = NSView(frame: frame)
        row.wantsLayer = true
        let h = frame.height
        let isExpanded = expandedThreadIds.contains(thread.id)

        if isTodayAccent {
            let accentBar = NSView(frame: NSRect(x: 0, y: 0, width: 3, height: h))
            accentBar.wantsLayer = true
            accentBar.layer?.backgroundColor = NSColor(calibratedWhite: 0.95, alpha: 0.9).cgColor
            row.addSubview(accentBar)
        }

        // Separator line
        let sep = NSBox(frame: NSRect(x: 16, y: 0, width: frame.width - 32, height: 1))
        sep.boxType = .separator
        row.addSubview(sep)

        // App Icon
        let iconView = NSImageView(frame: NSRect(x: 16, y: h - 34, width: 20, height: 20))
        iconView.image = IconResolver.resolveIcon(for: thread, size: 20)
        row.addSubview(iconView)

        // Text & Badge Container
        let textContainer = NSView(frame: NSRect(x: 44, y: h - 42, width: frame.width - 215, height: 36))

        // Cue badge button
        let badge = thread.cueSummaryBadge
        let chevron = isExpanded ? "▾" : "▸"
        let countSuffix = badge.count != nil ? " \(badge.count!)" : ""
        let badgeText = "\(badge.label)\(countSuffix) \(chevron)"
        let badgeWidth = CGFloat(badgeText.count * 6 + 14)

        let badgeBtn = ClosureButton(frame: NSRect(x: textContainer.bounds.width - badgeWidth - 4, y: 17, width: badgeWidth, height: 17)) { [weak self] in
            self?.toggleExpand(threadId: thread.id)
        }
        badgeBtn.isBordered = false
        badgeBtn.wantsLayer = true
        badgeBtn.layer?.cornerRadius = 4
        if isExpanded {
            badgeBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.25, alpha: 0.8).cgColor
            badgeBtn.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.25).cgColor
        } else {
            badgeBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.15, alpha: 0.6).cgColor
            badgeBtn.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.10).cgColor
        }
        badgeBtn.layer?.borderWidth = 1.0
        badgeBtn.attributedTitle = NSAttributedString(string: badgeText, attributes: [
            .foregroundColor: isExpanded ? NSColor(calibratedWhite: 0.98, alpha: 1.0) : NSColor(calibratedWhite: 0.85, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 8.5, weight: .semibold)
        ])
        textContainer.addSubview(badgeBtn)

        // Title button (clicking title also toggles expand)
        let titleBtn = ClosureButton(frame: NSRect(x: 0, y: 17, width: textContainer.bounds.width - badgeWidth - 8, height: 18)) { [weak self] in
            self?.toggleExpand(threadId: thread.id)
        }
        titleBtn.alignment = .left
        titleBtn.isBordered = false
        titleBtn.attributedTitle = NSAttributedString(string: thread.title, attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        ])
        textContainer.addSubview(titleBtn)

        // Subtitle
        let dueTag = thread.formattedDueDate.map { " · \($0)" } ?? ""
        let subtitleText: String
        switch thread.cue_type.lowercased() {
        case "checklist":
            let items = thread.checklistItems
            let done = items.filter { $0.isDone }.count
            subtitleText = "Checklist (\(done)/\(items.count) done)\(dueTag) · \(thread.timeAgo)"
        case "url", "link":
            let host = URL(string: thread.notes ?? "")?.host ?? "Web Link"
            subtitleText = "\(host)\(dueTag) · \(thread.timeAgo)"
        case "file":
            let name = URL(fileURLWithPath: thread.notes ?? "").lastPathComponent
            subtitleText = "\(name.isEmpty ? "File" : name)\(dueTag) · \(thread.timeAgo)"
        default:
            let n = thread.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let preview = n.isEmpty ? (thread.anchor?.app_name ?? "General") : n
            subtitleText = "\(preview)\(dueTag) · \(thread.timeAgo)"
        }

        let subLabel = NSTextField(labelWithString: subtitleText)
        subLabel.frame = NSRect(x: 0, y: 1, width: textContainer.bounds.width, height: 15)
        subLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .regular)
        subLabel.textColor = NSColor(calibratedWhite: 0.65, alpha: 1.0)
        subLabel.lineBreakMode = .byTruncatingTail
        textContainer.addSubview(subLabel)

        row.addSubview(textContainer)

        // Action Buttons: [Resume] [4h] [✓]
        let actionX = frame.width - 162

        // Resume Button
        let resumeBtn = ClosureButton(frame: NSRect(x: actionX, y: h - 35, width: 62, height: 22)) { [weak self] in
            self?.dismiss()
            _ = SutraBridge.shared.resume(threadId: thread.id)
            NotificationCenter.default.post(name: NSNotification.Name("SutraThreadsUpdated"), object: nil)
        }
        resumeBtn.isBordered = false
        resumeBtn.wantsLayer = true
        resumeBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.95, alpha: 1.0).cgColor
        resumeBtn.layer?.cornerRadius = 4
        resumeBtn.attributedTitle = NSAttributedString(string: "Resume", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.05, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 9, weight: .bold)
        ])
        row.addSubview(resumeBtn)

        // Snooze 4h
        let snoozeBtn = ClosureButton(frame: NSRect(x: actionX + 66, y: h - 35, width: 34, height: 22)) { [weak self] in
            _ = SutraBridge.shared.snooze(threadId: thread.id, hours: 4)
            self?.fetchData()
            self?.renderThreadList()
            NotificationCenter.default.post(name: NSNotification.Name("SutraThreadsUpdated"), object: nil)
        }
        snoozeBtn.isBordered = false
        snoozeBtn.wantsLayer = true
        snoozeBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1.0).cgColor
        snoozeBtn.layer?.cornerRadius = 4
        snoozeBtn.attributedTitle = NSAttributedString(string: "4h", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.9, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 9, weight: .medium)
        ])
        row.addSubview(snoozeBtn)

        // Done Button
        let doneBtn = ClosureButton(frame: NSRect(x: actionX + 104, y: h - 35, width: 28, height: 22)) { [weak self] in
            _ = SutraBridge.shared.done(threadId: thread.id)
            self?.fetchData()
            self?.renderThreadList()
            NotificationCenter.default.post(name: NSNotification.Name("SutraThreadsUpdated"), object: nil)
        }
        doneBtn.isBordered = false
        doneBtn.wantsLayer = true
        doneBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1.0).cgColor
        doneBtn.layer?.cornerRadius = 4
        doneBtn.attributedTitle = NSAttributedString(string: "✓", attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 10, weight: .bold)
        ])
        row.addSubview(doneBtn)

        // Accordion Drawer Content
        if isExpanded {
            let drawerHeight = h - 54
            let drawer = NSView(frame: NSRect(x: 44, y: 6, width: frame.width - 60, height: drawerHeight))
            drawer.wantsLayer = true
            drawer.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1.0).cgColor
            drawer.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.10).cgColor
            drawer.layer?.borderWidth = 1.0
            drawer.layer?.cornerRadius = 6

            switch thread.cue_type.lowercased() {
            case "checklist":
                buildChecklistDrawer(thread: thread, in: drawer)
            case "url", "link":
                buildLinkDrawer(thread: thread, in: drawer)
            case "file":
                buildFileDrawer(thread: thread, in: drawer)
            default:
                buildNoteDrawer(thread: thread, in: drawer)
            }

            row.addSubview(drawer)
        }

        return row
    }

    private func buildChecklistDrawer(thread: SutraThread, in drawerView: NSView) {
        let items = thread.checklistItems
        guard !items.isEmpty else {
            let empty = NSTextField(labelWithString: "No checklist items.")
            empty.frame = NSRect(x: 10, y: 8, width: drawerView.bounds.width - 20, height: 18)
            empty.font = NSFont.systemFont(ofSize: 10)
            empty.textColor = NSColor(calibratedWhite: 0.5, alpha: 1.0)
            drawerView.addSubview(empty)
            return
        }

        var itemY = drawerView.bounds.height - 24
        for (idx, item) in items.enumerated() {
            let itemRow = NSView(frame: NSRect(x: 8, y: itemY, width: drawerView.bounds.width - 16, height: 20))

            // Checkbox button
            let checkBtn = ClosureButton(frame: NSRect(x: 2, y: 2, width: 16, height: 16)) { [weak self] in
                self?.toggleChecklistItem(thread: thread, at: idx)
            }
            checkBtn.isBordered = false
            checkBtn.wantsLayer = true
            checkBtn.layer?.cornerRadius = 3
            checkBtn.layer?.borderWidth = 1.0
            if item.isDone {
                checkBtn.layer?.backgroundColor = NSColor(calibratedRed: 0.85, green: 0.42, blue: 0.15, alpha: 0.9).cgColor
                checkBtn.layer?.borderColor = NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.25, alpha: 1.0).cgColor
            } else {
                checkBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.2, alpha: 0.6).cgColor
                checkBtn.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.25).cgColor
            }
            checkBtn.attributedTitle = NSAttributedString(string: item.isDone ? "✓" : "", attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 10, weight: .bold)
            ])
            itemRow.addSubview(checkBtn)

            // Item text button (clicking text also toggles checkbox)
            let textBtn = ClosureButton(frame: NSRect(x: 24, y: 1, width: itemRow.bounds.width - 26, height: 18)) { [weak self] in
                self?.toggleChecklistItem(thread: thread, at: idx)
            }
            textBtn.alignment = .left
            textBtn.isBordered = false
            
            let attr = NSMutableAttributedString(string: item.text)
            if item.isDone {
                attr.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: attr.length))
                attr.addAttribute(.foregroundColor, value: NSColor(calibratedWhite: 0.48, alpha: 1.0), range: NSRange(location: 0, length: attr.length))
            } else {
                attr.addAttribute(.foregroundColor, value: NSColor(calibratedWhite: 0.92, alpha: 1.0), range: NSRange(location: 0, length: attr.length))
            }
            attr.addAttribute(.font, value: NSFont.systemFont(ofSize: 10.5, weight: .regular), range: NSRange(location: 0, length: attr.length))
            textBtn.attributedTitle = attr
            itemRow.addSubview(textBtn)

            drawerView.addSubview(itemRow)
            itemY -= 24
        }
    }

    private func toggleChecklistItem(thread: SutraThread, at index: Int) {
        let items = thread.checklistItems
        guard index < items.count else { return }
        var updatedLines: [String] = []
        for (i, it) in items.enumerated() {
            let isDone = (i == index) ? !it.isDone : it.isDone
            let mark = isDone ? "[x]" : "[ ]"
            updatedLines.append("\(mark) \(it.text)")
        }
        let newNotes = updatedLines.joined(separator: "\n")
        _ = SutraBridge.shared.updateNotes(threadId: thread.id, notes: newNotes)
        NSSound(named: "Tink")?.play()
        fetchData()
        renderThreadList()
        renderChips()
        NotificationCenter.default.post(name: NSNotification.Name("SutraThreadsUpdated"), object: nil)
    }

    private func buildLinkDrawer(thread: SutraThread, in drawerView: NSView) {
        let urlStr = thread.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let urlLabel = NSTextField(labelWithString: urlStr)
        urlLabel.frame = NSRect(x: 10, y: 10, width: drawerView.bounds.width - 170, height: 18)
        urlLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        urlLabel.textColor = NSColor(calibratedRed: 0.95, green: 0.6, blue: 0.35, alpha: 1.0)
        urlLabel.cell?.lineBreakMode = .byTruncatingMiddle
        drawerView.addSubview(urlLabel)

        let openBtn = ClosureButton(frame: NSRect(x: drawerView.bounds.width - 156, y: 8, width: 92, height: 22)) {
            if let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
            }
        }
        openBtn.isBordered = false
        openBtn.wantsLayer = true
        openBtn.layer?.backgroundColor = NSColor(calibratedRed: 0.85, green: 0.42, blue: 0.15, alpha: 0.85).cgColor
        openBtn.layer?.cornerRadius = 4
        openBtn.attributedTitle = NSAttributedString(string: "🔗 Open Link ↗", attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        ])
        drawerView.addSubview(openBtn)

        let copyBtn = ClosureButton(frame: NSRect(x: drawerView.bounds.width - 58, y: 8, width: 50, height: 22)) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(urlStr, forType: .string)
        }
        copyBtn.isBordered = false
        copyBtn.wantsLayer = true
        copyBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.2, alpha: 0.6).cgColor
        copyBtn.layer?.cornerRadius = 4
        copyBtn.attributedTitle = NSAttributedString(string: "📋 Copy", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.9, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 9.5, weight: .medium)
        ])
        drawerView.addSubview(copyBtn)
    }

    private func buildFileDrawer(thread: SutraThread, in drawerView: NSView) {
        let filePath = thread.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanPath = filePath.hasPrefix("file://") ? (URL(string: filePath)?.path ?? filePath) : filePath

        let pathLabel = NSTextField(labelWithString: cleanPath)
        pathLabel.frame = NSRect(x: 10, y: 10, width: drawerView.bounds.width - 176, height: 18)
        pathLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        pathLabel.textColor = NSColor(calibratedWhite: 0.88, alpha: 1.0)
        pathLabel.cell?.lineBreakMode = .byTruncatingMiddle
        drawerView.addSubview(pathLabel)

        let revealBtn = ClosureButton(frame: NSRect(x: drawerView.bounds.width - 162, y: 8, width: 104, height: 22)) {
            let url = URL(fileURLWithPath: cleanPath)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        revealBtn.isBordered = false
        revealBtn.wantsLayer = true
        revealBtn.layer?.backgroundColor = NSColor(calibratedRed: 0.85, green: 0.42, blue: 0.15, alpha: 0.85).cgColor
        revealBtn.layer?.cornerRadius = 4
        revealBtn.attributedTitle = NSAttributedString(string: "📁 In Finder ↗", attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        ])
        drawerView.addSubview(revealBtn)

        let openBtn = ClosureButton(frame: NSRect(x: drawerView.bounds.width - 54, y: 8, width: 46, height: 22)) {
            let url = URL(fileURLWithPath: cleanPath)
            NSWorkspace.shared.open(url)
        }
        openBtn.isBordered = false
        openBtn.wantsLayer = true
        openBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.2, alpha: 0.6).cgColor
        openBtn.layer?.cornerRadius = 4
        openBtn.attributedTitle = NSAttributedString(string: "Open", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.9, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 9.5, weight: .medium)
        ])
        drawerView.addSubview(openBtn)
    }

    private func buildNoteDrawer(thread: SutraThread, in drawerView: NSView) {
        let text = thread.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "No context note."
        let noteLabel = NSTextField(labelWithString: text)
        noteLabel.frame = NSRect(x: 10, y: 6, width: drawerView.bounds.width - 70, height: drawerView.bounds.height - 12)
        noteLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        noteLabel.textColor = NSColor(calibratedWhite: 0.9, alpha: 1.0)
        noteLabel.maximumNumberOfLines = 3
        noteLabel.cell?.lineBreakMode = .byTruncatingTail
        drawerView.addSubview(noteLabel)

        let copyBtn = ClosureButton(frame: NSRect(x: drawerView.bounds.width - 56, y: (drawerView.bounds.height - 22) / 2, width: 48, height: 22)) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        copyBtn.isBordered = false
        copyBtn.wantsLayer = true
        copyBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.2, alpha: 0.6).cgColor
        copyBtn.layer?.cornerRadius = 4
        copyBtn.attributedTitle = NSAttributedString(string: "Copy", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.9, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 9, weight: .medium)
        ])
        drawerView.addSubview(copyBtn)
    }

    // MARK: - Actions

    @objc private func onSearchChanged(_ sender: NSTextField) {
        searchQuery = sender.stringValue
        applyFilters()
        renderThreadList()
    }

    public func controlTextDidChange(_ obj: Notification) {
        if let tf = obj.object as? NSTextField, tf == searchField {
            searchQuery = tf.stringValue
            applyFilters()
            renderThreadList()
        }
    }


    private func loadSutraLogo(size: NSSize) -> NSImage {
        let paths = [
            Bundle.main.path(forResource: "logo", ofType: "png") ?? "",
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/logo.png").path,
            "/Users/raman/Desktop/AI/Sutra/assets/logo.png"
        ]
        for path in paths where !path.isEmpty {
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
