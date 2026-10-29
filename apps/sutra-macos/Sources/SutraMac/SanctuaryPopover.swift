import AppKit

final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let newRect = super.drawingRect(forBounds: rect)
        let textSize = cellSize(forBounds: rect)
        let deltaY = (rect.height - textSize.height) / 2.0
        return deltaY > 0 ? NSRect(x: newRect.origin.x, y: newRect.origin.y + deltaY, width: newRect.width, height: newRect.height - deltaY * 2) : newRect
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        return drawingRect(forBounds: rect)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        let aRect = drawingRect(forBounds: rect)
        super.select(withFrame: aRect, in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        let aRect = drawingRect(forBounds: rect)
        super.edit(withFrame: aRect, in: controlView, editor: textObj, delegate: delegate, event: event)
    }
}

public final class SanctuaryPopover: NSObject, NSTextFieldDelegate {
    public static let shared = SanctuaryPopover()

    public var isVisible: Bool { panel?.isVisible ?? false }
    public var window: NSPanel? { panel }

    private var panel: KeyFocusPanel!
    private var visualEffect: NSView!
    private var containerView: NSView!
    private var todayDockBtn: ClosureButton!
    private var searchPillContainer: NSView!
    private var searchField: NSTextField!
    private var stackFilterBtn: ClosureButton!
    private var selectedStackFilter: String? = nil
    private var scrollView: NSScrollView!
    private var threadListView: NSView!
    private var headerView: NSView!
    private var footerView: NSView!
    private var bottomDragBar: BottomResizeHandleView!
    public static var sessionPreferredHeight: CGFloat = 460
    
    private var currentStatusMode: String = "waiting" // "waiting" or "dock"
    private var allThreads: [SutraThread] = []
    private var filteredThreads: [SutraThread] = []
    private var searchQuery: String = ""
    private var expandedThreadIds: Set<String> = []
    private var editingThreadId: String? = nil
    private var editingDueDate: Date? = nil
    private var editCalendarPopover: NSPopover?
    private var stackSelectorPanel: KeyFocusPanel?
    private var isTodaySectionExpanded: Bool = true
    private var isWaitingSectionExpanded: Bool = false
    private var globalEventMonitor: Any?
    private weak var anchorButton: NSStatusBarButton?

    // Keyboard navigation (PLAN-029 Gap 5, Things 3 inspired)
    private var selectedThreadIndex: Int = 0
    private var selectedThreadId: String? = nil

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
        panel.onKeyDown = { [weak self] event in
            guard let self = self else { return false }
            return self.handleKeyDown(event: event)
        }
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
        isWaitingSectionExpanded = false
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
                if ContextPeekDrawer.shared.isVisible && ContextPeekDrawer.shared.frame.contains(mouseLoc) {
                    return
                }
                if let sp = self.stackSelectorPanel, sp.isVisible {
                    if sp.frame.contains(mouseLoc) { return }
                    sp.orderOut(nil)
                    self.stackSelectorPanel = nil
                }
                if !self.panel.frame.contains(mouseLoc) {
                    self.dismiss()
                }
            }
        }
    }

    public func dismiss() {
        ContextPeekDrawer.shared.dismiss()
        stackSelectorPanel?.orderOut(nil)
        stackSelectorPanel = nil
        panel.orderOut(nil)
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
    }

    public func refreshIfVisible() {
        guard panel.isVisible, editingThreadId == nil else { return }
        fetchData()
        applyFilters()
        renderThreadList()
    }

    private func fetchData() {
        _ = SutraBridge.shared.autoDockStale(days: 6)
        allThreads = SutraBridge.shared.list(status: currentStatusMode).sorted(by: { $0.created_at > $1.created_at })
        applyFilters()
        if selectedThreadIndex >= filteredThreads.count {
            selectedThreadIndex = max(0, filteredThreads.count - 1)
        }
        if selectedThreadIndex < filteredThreads.count {
            selectedThreadId = filteredThreads[selectedThreadIndex].id
        }
        updateTodayDockBtnTitle()
    }

    private func handleKeyDown(event: NSEvent) -> Bool {
        // Cmd+F: Focus search
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "f" {
            panel.makeFirstResponder(searchField)
            return true
        }

        // Escape: Dismiss or unfocus search
        if event.keyCode == 53 {
            if panel.firstResponder == searchField?.currentEditor() {
                panel.makeFirstResponder(panel.contentView)
                return true
            }
            dismiss()
            return true
        }

        // If search field is currently typing, let it handle standard keys
        if panel.firstResponder == searchField?.currentEditor() {
            if event.keyCode == 36 || event.keyCode == 125 {
                panel.makeFirstResponder(panel.contentView)
                return true
            }
            return false
        }

        guard !filteredThreads.isEmpty else { return false }

        switch event.keyCode {
        case 126: // Up Arrow
            selectedThreadIndex = max(0, selectedThreadIndex - 1)
            selectedThreadId = filteredThreads[selectedThreadIndex].id
            renderThreadList()
            return true

        case 125: // Down Arrow
            selectedThreadIndex = min(filteredThreads.count - 1, selectedThreadIndex + 1)
            selectedThreadId = filteredThreads[selectedThreadIndex].id
            renderThreadList()
            return true

        case 36: // Enter: Resume selected thread
            if selectedThreadIndex < filteredThreads.count {
                let target = filteredThreads[selectedThreadIndex]
                _ = SutraBridge.shared.resume(threadId: target.id)
                dismiss()
                return true
            }

        case 49: // Space: Context Peek
            if selectedThreadIndex < filteredThreads.count {
                let target = filteredThreads[selectedThreadIndex]
                if ContextPeekDrawer.shared.isVisible && ContextPeekDrawer.shared.activeThreadId == target.id {
                    ContextPeekDrawer.shared.dismiss()
                } else {
                    ContextPeekDrawer.shared.show(for: target)
                }
                return true
            }

        case 51: // Backspace / Delete: Mark Done (or Undo if Logbook)
            if selectedThreadIndex < filteredThreads.count {
                let target = filteredThreads[selectedThreadIndex]
                if currentStatusMode == "waiting" {
                    _ = SutraBridge.shared.done(threadId: target.id)
                } else {
                    _ = SutraBridge.shared.undo(threadId: target.id)
                }
                fetchData()
                renderThreadList()
                return true
            }

        default:
            break
        }

        return false
    }

    private func applyFilters() {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        filteredThreads = allThreads.filter { thread in
            if let sf = selectedStackFilter {
                let tags = thread.tags ?? []
                let hasStack = tags.contains(where: { $0.caseInsensitiveCompare(sf) == .orderedSame })
                if !hasStack { return false }
            }

            if q.isEmpty { return true }
            let titleMatch = thread.title.lowercased().contains(q)
            let notesMatch = (thread.notes ?? "").lowercased().contains(q)
            let tagMatch = (thread.tags ?? []).contains(where: { $0.lowercased().contains(q) })
            let appMatch = (thread.anchor?.app_name ?? "").lowercased().contains(q)
            return titleMatch || notesMatch || tagMatch || appMatch
        }
    }

    private func computeFittedHeight() -> CGFloat {
        let screen = anchorButton?.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let maxAllowed = min(800, screen.visibleFrame.height - 40)
        let minAllowed: CGFloat = 200

        let headerH: CGFloat = 48
        let dockRowH: CGFloat = 38
        let footerTotalH: CGFloat = 50
        let chromeH = headerH + dockRowH + footerTotalH

        let sectionGap: CGFloat = 14
        let bottomDockGap: CGFloat = 16
        let waitingBarH: CGFloat = 30

        let isSearching = !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isSearching {
            let searchContentH = filteredThreads.reduce(CGFloat(0)) { $0 + calculateRowHeight(for: $1) }
            let needed = chromeH + (searchContentH > 0 ? (searchContentH + bottomDockGap) : 40)
            return max(minAllowed, min(maxAllowed, needed))
        }

        if isWaitingSectionExpanded {
            let todayH = filteredThreads.filter { $0.isScheduledForToday }.reduce(CGFloat(0)) { $0 + calculateRowHeight(for: $1) }
            let backlogH = filteredThreads.filter { !$0.isScheduledForToday }.reduce(CGFloat(0)) { $0 + calculateRowHeight(for: $1) }
            let fullContentH = chromeH + todayH + (todayH > 0 ? sectionGap : 0) + waitingBarH + sectionGap + backlogH + bottomDockGap
            let targetExpanded = max(520, SanctuaryPopover.sessionPreferredHeight)
            return max(380, min(maxAllowed, min(targetExpanded, fullContentH)))
        } else {
            let todayThreads = filteredThreads.filter { $0.isScheduledForToday }
            let otherThreads = filteredThreads.filter { !$0.isScheduledForToday }

            let todayContentH = todayThreads.reduce(CGFloat(0)) { $0 + calculateRowHeight(for: $1) }
            var needed = chromeH + todayContentH
            if !otherThreads.isEmpty {
                if todayContentH > 0 { needed += sectionGap }
                needed += waitingBarH + bottomDockGap
            } else if todayContentH > 0 {
                needed += bottomDockGap
            } else {
                needed += 40
            }
            return max(minAllowed, min(maxAllowed, needed))
        }
    }

    private func positionPanel(relativeTo button: NSStatusBarButton?) {
        let fittedHeight = computeFittedHeight()
        applyDynamicHeight(fittedHeight, animated: false)
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
        logoView.image = Self.loadSutraLogo(size: NSSize(width: 32, height: 32))
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

        // Standardized 26x26 circular SF Symbol Buttons
        let btnSize: CGFloat = 26
        let btnY: CGFloat = (48 - btnSize) / 2

        // Settings Button (⚙) -> SF Symbol gearshape.fill
        let settingsBtn = ClosureButton(frame: NSRect(x: width - 70, y: btnY, width: btnSize, height: btnSize)) {
            SettingsWindow.shared.show()
        }
        settingsBtn.isBordered = false
        settingsBtn.wantsLayer = true
        settingsBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1.0).cgColor
        settingsBtn.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
        settingsBtn.layer?.borderWidth = 1.0
        settingsBtn.layer?.cornerRadius = btnSize / 2
        let gearConfig = NSImage.SymbolConfiguration(pointSize: 12.5, weight: .semibold)
        if let sym = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Settings")?.withSymbolConfiguration(gearConfig) {
            sym.isTemplate = true
            settingsBtn.image = sym
        } else {
            settingsBtn.attributedTitle = NSAttributedString(string: "⚙", attributes: [
                .foregroundColor: NSColor(calibratedWhite: 0.85, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 12)
            ])
        }
        settingsBtn.imageScaling = .scaleProportionallyDown
        settingsBtn.imagePosition = .imageOnly
        settingsBtn.contentTintColor = NSColor(calibratedWhite: 0.90, alpha: 1.0)
        settingsBtn.toolTip = "Sutra Preferences"
        headerView.addSubview(settingsBtn)

        // Dismiss Button (✕) -> SF Symbol xmark
        let closeBtn = ClosureButton(frame: NSRect(x: width - 38, y: btnY, width: btnSize, height: btnSize)) { [weak self] in
            self?.dismiss()
        }
        closeBtn.isBordered = false
        closeBtn.wantsLayer = true
        closeBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1.0).cgColor
        closeBtn.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
        closeBtn.layer?.borderWidth = 1.0
        closeBtn.layer?.cornerRadius = btnSize / 2
        let xConfig = NSImage.SymbolConfiguration(pointSize: 11.5, weight: .semibold)
        if let sym = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")?.withSymbolConfiguration(xConfig) {
            sym.isTemplate = true
            closeBtn.image = sym
        } else {
            closeBtn.attributedTitle = NSAttributedString(string: "✕", attributes: [
                .foregroundColor: NSColor(calibratedWhite: 0.85, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 11, weight: .medium)
            ])
        }
        closeBtn.imageScaling = .scaleProportionallyDown
        closeBtn.imagePosition = .imageOnly
        closeBtn.contentTintColor = NSColor(calibratedWhite: 0.90, alpha: 1.0)
        closeBtn.toolTip = "Close Sanctuary (Esc)"
        headerView.addSubview(closeBtn)

        containerView.addSubview(headerView)

        // 2. Three-Pill Unified Dock Row (y: height - 86, height: 28)
        let dockY = height - 86
        let dockH: CGFloat = 28

        // Pill 1: Today Pill Button (Left)
        let todayW: CGFloat = 106
        todayDockBtn = ClosureButton(frame: NSRect(x: 16, y: dockY, width: todayW, height: dockH)) { [weak self] in
            guard let self = self else { return }
            self.isTodaySectionExpanded.toggle()
            self.updateTodayDockBtnTitle()
            let newH = self.computeFittedHeight()
            self.applyDynamicHeight(newH, animated: true)
        }
        todayDockBtn.isBordered = false
        todayDockBtn.wantsLayer = true
        todayDockBtn.layer?.cornerRadius = 14
        todayDockBtn.layer?.backgroundColor = NSColor(calibratedRed: 0.18, green: 0.14, blue: 0.12, alpha: 1.0).cgColor
        todayDockBtn.layer?.borderColor = NSColor(calibratedRed: 0.90, green: 0.45, blue: 0.20, alpha: 0.40).cgColor
        todayDockBtn.layer?.borderWidth = 1.0
        todayDockBtn.layer?.shadowColor = NSColor.black.cgColor
        todayDockBtn.layer?.shadowOpacity = 0.40
        todayDockBtn.layer?.shadowOffset = CGSize(width: 0, height: -2)
        todayDockBtn.layer?.shadowRadius = 3
        containerView.addSubview(todayDockBtn)

        // Pill 3: Stacks Dropdown Button (Right)
        let stacksW: CGFloat = (selectedStackFilter != nil) ? 104 : 88
        let stacksX = width - 16 - stacksW
        stackFilterBtn = ClosureButton(frame: NSRect(x: stacksX, y: dockY, width: stacksW, height: dockH)) { [weak self] in
            self?.showSearchStackMenu()
        }
        stackFilterBtn.isBordered = false
        stackFilterBtn.wantsLayer = true
        stackFilterBtn.layer?.cornerRadius = 14
        stackFilterBtn.layer?.backgroundColor = (selectedStackFilter != nil)
            ? NSColor(calibratedRed: 0.20, green: 0.14, blue: 0.10, alpha: 1.0).cgColor
            : NSColor(calibratedWhite: 0.12, alpha: 1.0).cgColor
        stackFilterBtn.layer?.borderColor = (selectedStackFilter != nil)
            ? NSColor(calibratedRed: 0.90, green: 0.45, blue: 0.20, alpha: 0.40).cgColor
            : NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor
        stackFilterBtn.layer?.borderWidth = 1.0
        stackFilterBtn.layer?.shadowColor = NSColor.black.cgColor
        stackFilterBtn.layer?.shadowOpacity = 0.40
        stackFilterBtn.layer?.shadowOffset = CGSize(width: 0, height: -2)
        stackFilterBtn.layer?.shadowRadius = 3
        containerView.addSubview(stackFilterBtn)

        // Pill 2: Search Pill Container (Center)
        let searchX = 16 + todayW + 10
        let searchW = stacksX - searchX - 10
        searchPillContainer = NSView(frame: NSRect(x: searchX, y: dockY, width: searchW, height: dockH))
        searchPillContainer.wantsLayer = true
        searchPillContainer.layer?.cornerRadius = 14
        searchPillContainer.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1.0).cgColor
        searchPillContainer.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor
        searchPillContainer.layer?.borderWidth = 1.0
        searchPillContainer.layer?.shadowColor = NSColor.black.cgColor
        searchPillContainer.layer?.shadowOpacity = 0.40
        searchPillContainer.layer?.shadowOffset = CGSize(width: 0, height: -2)
        searchPillContainer.layer?.shadowRadius = 3

        let searchIcon = NSTextField(labelWithString: "🔍")
        searchIcon.frame = NSRect(x: 10, y: 6, width: 14, height: 14)
        searchIcon.font = NSFont.systemFont(ofSize: 10)
        searchPillContainer.addSubview(searchIcon)

        searchField = NSTextField(frame: NSRect(x: 28, y: 0, width: searchW - 36, height: 28))
        searchField.cell = VerticallyCenteredTextFieldCell(textCell: "")
        searchField.placeholderAttributedString = NSAttributedString(
            string: "Search",
            attributes: [
                .foregroundColor: NSColor(calibratedWhite: 0.55, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 11, weight: .medium)
            ]
        )
        searchField.font = NSFont.systemFont(ofSize: 11)
        searchField.textColor = .white
        searchField.drawsBackground = false
        searchField.isBezeled = false
        searchField.isEditable = true
        searchField.isSelectable = true
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(onSearchChanged)
        searchPillContainer.addSubview(searchField)

        containerView.addSubview(searchPillContainer)

        updateTodayDockBtnTitle()
        updateStackFilterBtnStyle()

        // 3. Thread List Scroll View (y: 50 ... height - 96)
        let footerTotalHeight: CGFloat = 38 + 12
        let listHeight = (height - 96) - footerTotalHeight
        scrollView = NSScrollView(frame: NSRect(x: 0, y: footerTotalHeight, width: width, height: listHeight))
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
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
            } else if let guideUrl = Bundle.main.url(forResource: "USER_GUIDE", withExtension: "html", subdirectory: "docs") {
                NSWorkspace.shared.open(guideUrl)
            } else {
                let candidates = [
                    Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("docs/USER_GUIDE.html").path,
                    Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs/USER_GUIDE.html").path,
                    Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("USER_GUIDE.html").path
                ]
                for p in candidates where FileManager.default.fileExists(atPath: p) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: p))
                    break
                }
            }
        }
        docsBtn.isBordered = false
        docsBtn.wantsLayer = true
        docsBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1.0).cgColor
        docsBtn.layer?.cornerRadius = 4
        docsBtn.attributedTitle = NSAttributedString(string: "Guide", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.88, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 10, weight: .regular)
        ])
        docsBtn.toolTip = "Sutra User Guide"
        footerView.addSubview(docsBtn)

        // Center Twin-Button: [ Active | Dock ] (Q-capture style with thin separator)
        let twinW: CGFloat = 118
        let twinH: CGFloat = 22
        let twinX: CGFloat = (width - twinW) / 2
        let twinContainer = NSView(frame: NSRect(x: twinX, y: 8, width: twinW, height: twinH))
        twinContainer.wantsLayer = true
        twinContainer.layer?.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1.0).cgColor
        twinContainer.layer?.cornerRadius = twinH / 2
        twinContainer.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.14).cgColor
        twinContainer.layer?.borderWidth = 1.0

        let isDock = (currentStatusMode == "dock")

        // Active Button (Left)
        let activeBtn = ClosureButton(frame: NSRect(x: 1, y: 1, width: 57, height: twinH - 2)) { [weak self] in
            guard let self = self, self.currentStatusMode != "waiting" else { return }
            self.currentStatusMode = "waiting"
            self.fetchData()
            self.buildUI()
        }
        activeBtn.isBordered = false
        activeBtn.wantsLayer = true
        activeBtn.layer?.cornerRadius = (twinH - 2) / 2
        activeBtn.layer?.backgroundColor = !isDock ? NSColor(calibratedWhite: 0.24, alpha: 1.0).cgColor : NSColor.clear.cgColor
        activeBtn.attributedTitle = NSAttributedString(string: "Active", attributes: [
            .foregroundColor: !isDock ? NSColor.white : NSColor(calibratedWhite: 0.60, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 10, weight: !isDock ? .bold : .medium)
        ])
        twinContainer.addSubview(activeBtn)

        // Thin Bevel Separator Line
        let sepLine = NSView(frame: NSRect(x: 58.5, y: 3, width: 1, height: twinH - 6))
        sepLine.wantsLayer = true
        sepLine.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor
        twinContainer.addSubview(sepLine)

        // Dock Button (Right)
        let dockBtn = ClosureButton(frame: NSRect(x: 60, y: 1, width: 57, height: twinH - 2)) { [weak self] in
            guard let self = self, self.currentStatusMode != "dock" else { return }
            self.currentStatusMode = "dock"
            self.fetchData()
            self.buildUI()
        }
        dockBtn.isBordered = false
        dockBtn.wantsLayer = true
        dockBtn.layer?.cornerRadius = (twinH - 2) / 2
        dockBtn.layer?.backgroundColor = isDock ? NSColor(calibratedRed: 0.26, green: 0.14, blue: 0.10, alpha: 1.0).cgColor : NSColor.clear.cgColor
        dockBtn.layer?.borderColor = isDock ? NSColor(calibratedRed: 0.90, green: 0.45, blue: 0.20, alpha: 0.50).cgColor : NSColor.clear.cgColor
        dockBtn.layer?.borderWidth = isDock ? 1.0 : 0
        dockBtn.attributedTitle = NSAttributedString(string: "Dock", attributes: [
            .foregroundColor: isDock ? NSColor(calibratedRed: 0.95, green: 0.70, blue: 0.50, alpha: 1.0) : NSColor(calibratedWhite: 0.60, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 10, weight: isDock ? .bold : .medium)
        ])
        twinContainer.addSubview(dockBtn)

        footerView.addSubview(twinContainer)

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

    private func applyDynamicHeight(_ newHeight: CGFloat, animated: Bool = false) {
        let screen = anchorButton?.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let maxAllowed = min(800, screen.visibleFrame.height - 40)
        let minAllowed: CGFloat = 200
        let clampedHeight = max(minAllowed, min(maxAllowed, newHeight))

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
        let targetFrame = NSRect(x: originX, y: originY, width: width, height: clampedHeight)

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.setFrame(targetFrame, display: true)
        }
        if ContextPeekDrawer.shared.isVisible {
            ContextPeekDrawer.shared.reposition(relativeTo: targetFrame)
        }
        if isWaitingSectionExpanded {
            SanctuaryPopover.sessionPreferredHeight = clampedHeight
        }

        // Update layout frames
        let h = clampedHeight
        headerView?.frame = NSRect(x: 0, y: h - 48, width: width, height: 48)

        let dockY = h - 86
        let dockH: CGFloat = 28
        let todayW: CGFloat = 106
        todayDockBtn?.frame = NSRect(x: 16, y: dockY, width: todayW, height: dockH)

        let stacksW: CGFloat = (selectedStackFilter != nil) ? 104 : 88
        let stacksX = width - 16 - stacksW
        stackFilterBtn?.frame = NSRect(x: stacksX, y: dockY, width: stacksW, height: dockH)

        let searchX = 16 + todayW + 10
        let searchW = stacksX - searchX - 10
        searchPillContainer?.frame = NSRect(x: searchX, y: dockY, width: searchW, height: dockH)
        searchField?.frame = NSRect(x: 28, y: 0, width: searchW - 36, height: 28)

        let footerTotalHeight: CGFloat = 50
        let listHeight = max(40, (h - 96) - footerTotalHeight)
        scrollView?.frame = NSRect(x: 0, y: footerTotalHeight, width: width, height: listHeight)
        footerView?.frame = NSRect(x: 0, y: 12, width: width, height: 38)
        bottomDragBar?.frame = NSRect(x: 0, y: 0, width: width, height: 12)

        renderThreadList()
    }

    // MARK: - Thread List Rendering

    private func calculateRowHeight(for thread: SutraThread) -> CGFloat {
        if editingThreadId == thread.id {
            return 148 // Height of inline editor card
        }
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
        let newH = computeFittedHeight()
        applyDynamicHeight(newH, animated: true)
    }

    private func createWaitingSectionBar(count: Int, width: CGFloat, height: CGFloat = 30) -> NSView {
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        // 1. Broad thin white line below the count pill
        let line = NSView(frame: NSRect(x: 16, y: 2, width: width - 32, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.16).cgColor
        bar.addSubview(line)

        // 2. White Outline Pill (No fill, white boundary, bold white number)
        let countStr = "\(count)"
        let textW: CGFloat = (countStr as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 10.5, weight: .bold)]).width
        let pillW: CGFloat = max(38, textW + 18)
        let pillH: CGFloat = 20
        let pillX: CGFloat = (width - pillW) / 2
        let pillY: CGFloat = 7

        let pillView = NSView(frame: NSRect(x: pillX, y: pillY, width: pillW, height: pillH))
        pillView.wantsLayer = true
        pillView.layer?.backgroundColor = NSColor.clear.cgColor
        pillView.layer?.borderColor = NSColor.white.cgColor
        pillView.layer?.borderWidth = 1.0
        pillView.layer?.cornerRadius = pillH / 2

        let countLabel = NSTextField(labelWithString: countStr)
        countLabel.isBezeled = false
        countLabel.drawsBackground = false
        countLabel.isEditable = false
        countLabel.isSelectable = false
        countLabel.frame = NSRect(x: 0, y: (pillH - 14) / 2, width: pillW, height: 14)
        countLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .bold)
        countLabel.textColor = .white
        countLabel.alignment = .center
        pillView.addSubview(countLabel)

        bar.addSubview(pillView)

        // 3. Interactive toggle overlay
        let btn = ClosureButton(frame: NSRect(x: pillX, y: 0, width: pillW, height: height)) { [weak self] in
            guard let self = self else { return }
            self.isWaitingSectionExpanded.toggle()
            let newH = self.computeFittedHeight()
            self.applyDynamicHeight(newH, animated: true)
        }
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.backgroundColor = NSColor.clear.cgColor
        bar.addSubview(btn)

        return bar
    }

    private func renderThreadList() {
        threadListView.subviews.forEach { $0.removeFromSuperview() }
        updateTodayDockBtnTitle()

        let width = containerView.bounds.width
        let isSearching = !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let todayThreads = filteredThreads.filter { $0.isScheduledForToday }
        let otherThreads = filteredThreads.filter { !$0.isScheduledForToday }

        let sectionGap: CGFloat = 14
        let bottomDockGap: CGFloat = 16
        let waitingBarH: CGFloat = 30

        var contentTotalHeight: CGFloat = 0

        if isSearching {
            for thread in filteredThreads {
                contentTotalHeight += calculateRowHeight(for: thread)
            }
            if contentTotalHeight > 0 {
                contentTotalHeight += bottomDockGap
            }
        } else {
            // 1. Scheduled for Today items
            if isTodaySectionExpanded {
                for thread in todayThreads {
                    contentTotalHeight += calculateRowHeight(for: thread)
                }
            }

            // 2. Waiting Section Bar & Backlog Threads
            if !otherThreads.isEmpty {
                if contentTotalHeight > 0 {
                    contentTotalHeight += sectionGap
                }
                contentTotalHeight += waitingBarH
                if isWaitingSectionExpanded {
                    contentTotalHeight += sectionGap
                    for thread in otherThreads {
                        contentTotalHeight += calculateRowHeight(for: thread)
                    }
                }
                contentTotalHeight += bottomDockGap
            } else if contentTotalHeight > 0 {
                contentTotalHeight += bottomDockGap
            }
        }

        let visibleListH = scrollView.bounds.height
        let totalHeight = max(contentTotalHeight, visibleListH)
        threadListView.frame = NSRect(x: 0, y: 0, width: width, height: totalHeight)

        // Only activate scrolling if backlog is expanded or content overflows visible height
        let canScroll = isWaitingSectionExpanded || (contentTotalHeight > visibleListH + 4)
        scrollView.hasVerticalScroller = canScroll

        if filteredThreads.isEmpty {
            let emptyLabel = NSTextField(labelWithString: allThreads.isEmpty ? (currentStatusMode == "dock" ? "No archived threads in Dock" : "No active threads — Mind is clear") : "No matching threads found")
            emptyLabel.frame = NSRect(x: 20, y: totalHeight / 2 - 10, width: width - 40, height: 20)
            emptyLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            emptyLabel.textColor = NSColor(calibratedWhite: 0.5, alpha: 1.0)
            emptyLabel.alignment = .center
            threadListView.addSubview(emptyLabel)
            return
        }

        var currentY = totalHeight

        if isSearching {
            for thread in filteredThreads {
                let rowH = calculateRowHeight(for: thread)
                currentY -= rowH
                let row = createThreadRow(thread: thread, frame: NSRect(x: 0, y: currentY, width: width, height: rowH), isTodayAccent: thread.isScheduledForToday)
                threadListView.addSubview(row)
            }
        } else {
            // 1. Scheduled for Today items
            if isTodaySectionExpanded {
                for thread in todayThreads {
                    let rowH = calculateRowHeight(for: thread)
                    currentY -= rowH
                    let row = createThreadRow(thread: thread, frame: NSRect(x: 0, y: currentY, width: width, height: rowH), isTodayAccent: true)
                    threadListView.addSubview(row)
                }
            }

            // 2. Waiting Collapsible Section Bar & Items
            if !otherThreads.isEmpty {
                if isTodaySectionExpanded && !todayThreads.isEmpty {
                    currentY -= sectionGap // 14pt gap below Today items
                }
                currentY -= waitingBarH // 34pt
                let waitingBar = createWaitingSectionBar(count: otherThreads.count, width: width, height: waitingBarH)
                waitingBar.frame.origin.y = currentY
                threadListView.addSubview(waitingBar)

                if isWaitingSectionExpanded {
                    currentY -= sectionGap // 14pt gap below Waiting bar to first backlog item
                    for thread in otherThreads {
                        let rowH = calculateRowHeight(for: thread)
                        currentY -= rowH
                        let row = createThreadRow(thread: thread, frame: NSRect(x: 0, y: currentY, width: width, height: rowH), isTodayAccent: false)
                        threadListView.addSubview(row)
                    }
                }
            }
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

        // Check if this thread is currently selected via keyboard navigation (PLAN-029 Gap 5)
        let isSelected = (thread.id == selectedThreadId)
        if isSelected {
            row.layer?.backgroundColor = NSColor(calibratedRed: 0.85, green: 0.40, blue: 0.18, alpha: 0.15).cgColor
            row.layer?.borderColor = NSColor(calibratedRed: 0.90, green: 0.45, blue: 0.20, alpha: 0.50).cgColor
            row.layer?.borderWidth = 1.0
            row.layer?.cornerRadius = 6
        }

        // Check if this thread is currently in inline editing mode
        if editingThreadId == thread.id {
            return createInlineEditRow(thread: thread, frame: frame)
        }

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

        // Text Container (expanded width to provide generous breathing room before actions)
        let textContainer = NSView(frame: NSRect(x: 44, y: h - 42, width: frame.width - 246, height: 36))

        // Title button takes full textContainer width; clicking title toggles accordion expand
        let titleBtn = ClosureButton(frame: NSRect(x: 0, y: 17, width: textContainer.bounds.width, height: 18)) { [weak self] in
            self?.toggleExpand(threadId: thread.id)
        }
        titleBtn.alignment = .left
        titleBtn.isBordered = false
        titleBtn.attributedTitle = NSAttributedString(string: thread.title, attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        ])
        textContainer.addSubview(titleBtn)

        // Subtitle (clean context without redundant cue-type prefixes)
        let dueTag = thread.formattedDueDate.map { " · \($0)" } ?? ""
        let cleanedTags = (thread.tags ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let stackBadge: String
        if !cleanedTags.isEmpty {
            let joined = cleanedTags.joined(separator: ", ")
                .replacingOccurrences(of: " , ", with: ", ")
                .replacingOccurrences(of: " ,", with: ",")
            stackBadge = " · \(joined)"
        } else {
            stackBadge = ""
        }

        let subtitleText: String
        switch thread.cue_type.lowercased() {
        case "checklist":
            let items = thread.checklistItems
            let done = items.filter { $0.isDone }.count
            subtitleText = "(\(done)/\(items.count) done)\(stackBadge)\(dueTag) · \(thread.timeAgo)"
        case "url", "link":
            let host = URL(string: thread.notes ?? "")?.host ?? "Web Link"
            subtitleText = "\(host)\(stackBadge)\(dueTag) · \(thread.timeAgo)"
        case "file":
            let name = URL(fileURLWithPath: thread.notes ?? "").lastPathComponent
            subtitleText = "\(name.isEmpty ? "File" : name)\(stackBadge)\(dueTag) · \(thread.timeAgo)"
        default:
            let n = thread.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let preview = n.isEmpty ? (thread.anchor?.app_name ?? "General") : n
            subtitleText = "\(preview)\(stackBadge)\(dueTag) · \(thread.timeAgo)"
        }

        let subLabel = NSTextField(labelWithString: subtitleText)
        subLabel.frame = NSRect(x: 0, y: 1, width: textContainer.bounds.width, height: 15)
        subLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .regular)
        subLabel.textColor = NSColor(calibratedWhite: 0.65, alpha: 1.0)
        subLabel.lineBreakMode = .byTruncatingTail
        textContainer.addSubview(subLabel)

        row.addSubview(textContainer)

        // Action Buttons: [👁] [✎] [Resume] [4h] [✓] (right-aligned with balanced 16px gutter)
        let doneX = frame.width - 44
        let snoozeX = doneX - 40
        let resumeX = snoozeX - 64
        let editX = resumeX - 30
        let peekX = editX - 30

        // Context Peek Button (👁) - Inspired by Peek (peek.zone)
        let peekBtn = ClosureButton(frame: NSRect(x: peekX, y: h - 35, width: 26, height: 22)) {
            if ContextPeekDrawer.shared.isVisible && ContextPeekDrawer.shared.activeThreadId == thread.id {
                ContextPeekDrawer.shared.dismiss()
            } else {
                ContextPeekDrawer.shared.show(for: thread)
            }
        }
        peekBtn.isBordered = false
        peekBtn.wantsLayer = true
        peekBtn.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.05).cgColor
        peekBtn.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
        peekBtn.layer?.borderWidth = 1.0
        peekBtn.layer?.cornerRadius = 4
        peekBtn.toolTip = "Peek Context (Space)"
        if let sym = NSImage(systemSymbolName: "eye", accessibilityDescription: "Peek") {
            let cfg = NSImage.SymbolConfiguration(pointSize: 10.5, weight: .semibold)
            peekBtn.image = sym.withSymbolConfiguration(cfg)
            peekBtn.contentTintColor = NSColor(calibratedWhite: 0.70, alpha: 1.0)
            peekBtn.imagePosition = .imageOnly
        } else {
            peekBtn.attributedTitle = NSAttributedString(string: "👁", attributes: [
                .foregroundColor: NSColor(calibratedWhite: 0.70, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 10)
            ])
        }
        row.addSubview(peekBtn)

        // Edit Button (✎) - Ghost Action
        let editBtn = ClosureButton(frame: NSRect(x: editX, y: h - 35, width: 26, height: 22)) { [weak self] in
            guard let self = self else { return }
            self.editingThreadId = thread.id
            self.editingDueDate = thread.dueDate
            self.renderThreadList()
        }
        editBtn.isBordered = false
        editBtn.wantsLayer = true
        editBtn.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.05).cgColor
        editBtn.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
        editBtn.layer?.borderWidth = 1.0
        editBtn.layer?.cornerRadius = 4
        editBtn.attributedTitle = NSAttributedString(string: "✎", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.55, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 11, weight: .regular)
        ])
        row.addSubview(editBtn)

        // Resume Button - High-Contrast Hero Action
        let resumeBtn = ClosureButton(frame: NSRect(x: resumeX, y: h - 35, width: 58, height: 22)) { [weak self] in
            self?.dismiss()
            _ = SutraBridge.shared.resume(threadId: thread.id)
            NotificationCenter.default.post(name: NSNotification.Name("SutraThreadsUpdated"), object: nil)
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
            .font: NSFont.systemFont(ofSize: 9.5, weight: .bold)
        ])
        row.addSubview(resumeBtn)

        // Snooze 4h - Subdued Secondary Action
        let snoozeBtn = ClosureButton(frame: NSRect(x: snoozeX, y: h - 35, width: 34, height: 22)) { [weak self] in
            _ = SutraBridge.shared.snooze(threadId: thread.id, hours: 4)
            self?.fetchData()
            self?.renderThreadList()
            NotificationCenter.default.post(name: NSNotification.Name("SutraThreadsUpdated"), object: nil)
        }
        snoozeBtn.isBordered = false
        snoozeBtn.wantsLayer = true
        snoozeBtn.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.06).cgColor
        snoozeBtn.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
        snoozeBtn.layer?.borderWidth = 1.0
        snoozeBtn.layer?.cornerRadius = 4
        snoozeBtn.attributedTitle = NSAttributedString(string: "4h", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.65, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 9, weight: .medium)
        ])
        row.addSubview(snoozeBtn)

        // Done Button (✓) or Undo (↩) in Dock mode
        let isArchive = (currentStatusMode == "dock")
        let doneBtnTitle = isArchive ? "↩" : "✓"
        let doneBtn = ClosureButton(frame: NSRect(x: doneX, y: h - 35, width: 28, height: 22)) { [weak self] in
            if isArchive {
                _ = SutraBridge.shared.undo(threadId: thread.id)
            } else {
                _ = SutraBridge.shared.done(threadId: thread.id)
            }
            self?.fetchData()
            self?.renderThreadList()
            NotificationCenter.default.post(name: NSNotification.Name("SutraThreadsUpdated"), object: nil)
        }
        doneBtn.isBordered = false
        doneBtn.wantsLayer = true
        doneBtn.layer?.backgroundColor = isArchive ? NSColor(calibratedRed: 0.22, green: 0.14, blue: 0.10, alpha: 1.0).cgColor : NSColor(calibratedWhite: 1.0, alpha: 0.06).cgColor
        doneBtn.layer?.borderColor = isArchive ? NSColor(calibratedRed: 0.90, green: 0.45, blue: 0.20, alpha: 0.45).cgColor : NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
        doneBtn.layer?.borderWidth = 1.0
        doneBtn.layer?.cornerRadius = 4
        doneBtn.attributedTitle = NSAttributedString(string: doneBtnTitle, attributes: [
            .foregroundColor: isArchive ? NSColor(calibratedRed: 0.95, green: 0.70, blue: 0.50, alpha: 1.0) : NSColor(calibratedWhite: 0.70, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 10, weight: .bold)
        ])
        doneBtn.toolTip = isArchive ? "Move back to Active" : "Mark Done"
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
            case "link_file":
                let raw = thread.notes?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
                    buildLinkDrawer(thread: thread, in: drawer)
                } else {
                    buildFileDrawer(thread: thread, in: drawer)
                }
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
        let newH = computeFittedHeight()
        applyDynamicHeight(newH, animated: true)
    }

    public func controlTextDidChange(_ obj: Notification) {
        if let tf = obj.object as? NSTextField, tf == searchField {
            searchQuery = tf.stringValue
            applyFilters()
            let newH = computeFittedHeight()
            applyDynamicHeight(newH, animated: true)
        }
    }

    private func showSearchStackMenu() {
        if let existing = stackSelectorPanel, existing.isVisible {
            existing.orderOut(nil)
            stackSelectorPanel = nil
            return
        }

        let customStacks = UserDefaults.standard.stringArray(forKey: "SutraCustomStacks") ?? []
        let allDefinedStacks = Array(Set(allThreads.flatMap { $0.tags ?? [] } + customStacks)).sorted()

        let popW: CGFloat = 200
        let rowH: CGFloat = 28
        let totalH = max(CGFloat(allDefinedStacks.count + 2) * rowH + 16, 90)
        let popH = min(totalH, 260)

        let popoverView = NSView(frame: NSRect(x: 0, y: 0, width: popW, height: popH))
        popoverView.wantsLayer = true
        popoverView.layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 0.98).cgColor
        popoverView.layer?.cornerRadius = 10
        popoverView.layer?.masksToBounds = true
        popoverView.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.14).cgColor
        popoverView.layer?.borderWidth = 1.0

        // Header Label
        let headerLabel = NSTextField(labelWithString: "Filter by Stack")
        headerLabel.frame = NSRect(x: 12, y: popH - 24, width: popW - 24, height: 16)
        headerLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        headerLabel.textColor = NSColor(calibratedWhite: 0.65, alpha: 1.0)
        popoverView.addSubview(headerLabel)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 8, width: popW, height: popH - 34))
        scrollView.hasVerticalScroller = allDefinedStacks.count > 6
        scrollView.drawsBackground = false

        let totalRows = allDefinedStacks.count + 1 // +1 for "All Stacks"
        let docViewH = CGFloat(totalRows) * rowH
        let docView = NSView(frame: NSRect(x: 0, y: 0, width: popW, height: docViewH))

        // Row 0: All Stacks
        var currentY = docViewH - rowH
        let allBtn = ClosureButton(frame: NSRect(x: 6, y: currentY + 2, width: popW - 12, height: rowH - 4)) { [weak self] in
            guard let self = self else { return }
            self.selectedStackFilter = nil
            self.updateStackFilterBtnStyle()
            self.applyFilters()
            let newH = self.computeFittedHeight()
            self.applyDynamicHeight(newH, animated: true)
            self.stackSelectorPanel?.orderOut(nil)
            self.stackSelectorPanel = nil
        }
        allBtn.title = "✦ All Stacks"
        allBtn.font = NSFont.systemFont(ofSize: 11, weight: (selectedStackFilter == nil ? .bold : .medium))
        allBtn.alignment = .left
        allBtn.isBordered = false
        allBtn.wantsLayer = true
        allBtn.layer?.backgroundColor = (selectedStackFilter == nil ? NSColor(calibratedWhite: 0.22, alpha: 1.0).cgColor : NSColor.clear.cgColor)
        allBtn.layer?.cornerRadius = 5
        docView.addSubview(allBtn)

        // Remaining Rows: Each defined stack
        for stack in allDefinedStacks {
            currentY -= rowH
            let isCurrent = (selectedStackFilter == stack)
            let itemBtn = ClosureButton(frame: NSRect(x: 6, y: currentY + 2, width: popW - 12, height: rowH - 4)) { [weak self] in
                guard let self = self else { return }
                self.selectedStackFilter = stack
                self.updateStackFilterBtnStyle()
                self.applyFilters()
                let newH = self.computeFittedHeight()
                self.applyDynamicHeight(newH, animated: true)
                self.stackSelectorPanel?.orderOut(nil)
                self.stackSelectorPanel = nil
            }
            itemBtn.title = stack
            itemBtn.font = NSFont.systemFont(ofSize: 11, weight: (isCurrent ? .bold : .medium))
            itemBtn.alignment = .left
            itemBtn.isBordered = false
            itemBtn.wantsLayer = true
            itemBtn.layer?.backgroundColor = (isCurrent ? NSColor(calibratedWhite: 0.22, alpha: 1.0).cgColor : NSColor.clear.cgColor)
            itemBtn.layer?.cornerRadius = 5
            docView.addSubview(itemBtn)
        }

        scrollView.documentView = docView
        popoverView.addSubview(scrollView)

        // Floating Panel: Positioned to the right of the Sanctuary window, with its TOP aligned with the "Stacks" button line and extending DOWNWARDS!
        let panelWindow = KeyFocusPanel(
            contentRect: NSRect(x: 0, y: 0, width: popW, height: popH),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panelWindow.isFloatingPanel = true
        panelWindow.level = .floating
        panelWindow.backgroundColor = .clear
        panelWindow.hasShadow = true
        panelWindow.appearance = NSAppearance(named: .darkAqua)
        panelWindow.contentView = popoverView

        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let btnScreenRect: NSRect
        if let btnWindow = stackFilterBtn.window {
            btnScreenRect = btnWindow.convertToScreen(stackFilterBtn.convert(stackFilterBtn.bounds, to: nil))
        } else {
            btnScreenRect = panel.frame
        }

        let panelOriginY = btnScreenRect.maxY - popH
        let panelOriginX: CGFloat
        if panel.frame.maxX + popW + 10 < screen.visibleFrame.maxX {
            panelOriginX = panel.frame.maxX + 4
        } else {
            panelOriginX = panel.frame.minX - popW - 4
        }

        panelWindow.setFrame(NSRect(x: panelOriginX, y: panelOriginY, width: popW, height: popH), display: true)
        panelWindow.makeKeyAndOrderFront(nil)
        self.stackSelectorPanel = panelWindow
    }

    private func updateTodayDockBtnTitle() {
        guard todayDockBtn != nil else { return }
        let todayCount = allThreads.filter { $0.isScheduledForToday }.count
        let chevron = isTodaySectionExpanded ? "▾" : "▸"
        let titleStr = NSMutableAttributedString(
            string: "Today  ",
            attributes: [
                .foregroundColor: todayCount > 0 ? NSColor(calibratedWhite: 0.98, alpha: 1.0) : NSColor(calibratedWhite: 0.70, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 10.5, weight: .bold)
            ]
        )
        let countBadgeStr = NSAttributedString(
            string: "(\(todayCount))  \(chevron)",
            attributes: [
                .foregroundColor: todayCount > 0 ? NSColor(calibratedWhite: 0.75, alpha: 1.0) : NSColor(calibratedWhite: 0.45, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold)
            ]
        )
        titleStr.append(countBadgeStr)
        todayDockBtn.attributedTitle = titleStr
    }

    private func updateStackFilterBtnStyle() {
        let title = selectedStackFilter ?? "Stacks"
        stackFilterBtn.attributedTitle = NSAttributedString(string: "\(title) ▾", attributes: [
            .foregroundColor: (selectedStackFilter != nil) ? NSColor(calibratedRed: 0.95, green: 0.60, blue: 0.35, alpha: 1.0) : NSColor(calibratedWhite: 0.65, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 10, weight: (selectedStackFilter != nil) ? .bold : .medium)
        ])
        stackFilterBtn.layer?.backgroundColor = (selectedStackFilter != nil)
            ? NSColor(calibratedRed: 0.20, green: 0.14, blue: 0.10, alpha: 1.0).cgColor
            : NSColor.clear.cgColor
    }

    @objc private func onSelectInlineStack(_ sender: NSMenuItem) {
        guard let stackName = sender.title as String?, let tf = sender.representedObject as? NSTextField else { return }
        let current = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty {
            tf.stringValue = stackName
        } else {
            let existing = current.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            if !existing.contains(stackName) {
                tf.stringValue = "\(current), \(stackName)"
            }
        }
    }

    private func showInlineCalendarPopover(for thread: SutraThread) {
        if let existing = editCalendarPopover, existing.isShown {
            existing.performClose(nil)
            editCalendarPopover = nil
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        let popWidth: CGFloat = 280
        let popHeight: CGFloat = 300
        let popoverView = NSView(frame: NSRect(x: 0, y: 0, width: popWidth, height: popHeight))
        popoverView.wantsLayer = true
        popoverView.layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 0.98).cgColor

        let calendarView = TerracottaCalendarView(
            frame: NSRect(x: 0, y: 46, width: popWidth, height: 250),
            initialDate: editingDueDate ?? thread.dueDate ?? Date()
        )
        calendarView.selectedDate = editingDueDate ?? thread.dueDate
        calendarView.onDateSelected = { [weak self, weak popover] chosenDate in
            guard let self = self else { return }
            self.editingDueDate = chosenDate
            self.renderThreadList()
            popover?.performClose(nil)
            self.editCalendarPopover = nil
        }
        popoverView.addSubview(calendarView)

        // Clear Date Button
        let clearBtn = ClosureButton(frame: NSRect(x: 14, y: 12, width: 110, height: 26)) { [weak self, weak popover] in
            guard let self = self else { return }
            self.editingDueDate = nil
            self.renderThreadList()
            popover?.performClose(nil)
            self.editCalendarPopover = nil
        }
        clearBtn.title = "Clear"
        clearBtn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        clearBtn.isBordered = false
        clearBtn.wantsLayer = true
        clearBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.20, alpha: 1.0).cgColor
        clearBtn.layer?.cornerRadius = 6
        popoverView.addSubview(clearBtn)

        // Today Button
        let todayBtn = ClosureButton(frame: NSRect(x: popWidth - 124, y: 12, width: 110, height: 26)) { [weak self, weak popover] in
            guard let self = self else { return }
            self.editingDueDate = Calendar.current.startOfDay(for: Date())
            self.renderThreadList()
            popover?.performClose(nil)
            self.editCalendarPopover = nil
        }
        todayBtn.attributedTitle = NSAttributedString(string: "Today", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.95, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 11, weight: .bold)
        ])
        todayBtn.isBordered = false
        todayBtn.wantsLayer = true
        todayBtn.layer?.backgroundColor = NSColor(calibratedRed: 0.92, green: 0.44, blue: 0.16, alpha: 0.85).cgColor
        todayBtn.layer?.cornerRadius = 6
        popoverView.addSubview(todayBtn)

        let controller = NSViewController()
        controller.view = popoverView
        popover.contentViewController = controller

        self.editCalendarPopover = popover

        // Pop out on the side (left or right) of the Sanctuary panel so it does not block the list!
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let panelFrame = panel.frame
        let edge: NSRectEdge = (panelFrame.maxX + 200 < screen.visibleFrame.maxX) ? .maxX : .minX

        // Anchor to the side of containerView
        popover.show(relativeTo: containerView.bounds, of: containerView, preferredEdge: edge)
    }

    private func createInlineEditRow(thread: SutraThread, frame: NSRect) -> NSView {
        let card = NSView(frame: frame)
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 1.0).cgColor
        card.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.18).cgColor
        card.layer?.borderWidth = 1.0
        card.layer?.cornerRadius = 8

        let w = frame.width - 32
        let startX: CGFloat = 16

        // Title Input Field
        let titleLabel = NSTextField(labelWithString: "Title")
        titleLabel.frame = NSRect(x: startX, y: 120, width: 40, height: 16)
        titleLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
        titleLabel.textColor = NSColor(calibratedWhite: 0.65, alpha: 1.0)
        card.addSubview(titleLabel)

        let titleInput = NSTextField(frame: NSRect(x: startX + 42, y: 118, width: w - 42, height: 22))
        titleInput.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleInput.textColor = .white
        titleInput.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1.0)
        titleInput.isBezeled = false
        titleInput.isEditable = true
        titleInput.isSelectable = true
        titleInput.focusRingType = .none
        titleInput.wantsLayer = true
        titleInput.layer?.cornerRadius = 4
        titleInput.stringValue = thread.title
        card.addSubview(titleInput)

        // Notes Input Field
        let notesLabel = NSTextField(labelWithString: "Notes")
        notesLabel.frame = NSRect(x: startX, y: 88, width: 40, height: 16)
        notesLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
        notesLabel.textColor = NSColor(calibratedWhite: 0.65, alpha: 1.0)
        card.addSubview(notesLabel)

        let notesInput = NSTextField(frame: NSRect(x: startX + 42, y: 78, width: w - 42, height: 34))
        notesInput.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        notesInput.textColor = .white
        notesInput.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1.0)
        notesInput.isBezeled = false
        notesInput.isEditable = true
        notesInput.isSelectable = true
        notesInput.focusRingType = .none
        notesInput.wantsLayer = true
        notesInput.layer?.cornerRadius = 4
        notesInput.stringValue = thread.notes ?? ""
        card.addSubview(notesInput)

        // Stack Tag Input Field
        let stackLabel = NSTextField(labelWithString: "Stack")
        stackLabel.frame = NSRect(x: startX, y: 46, width: 40, height: 16)
        stackLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
        stackLabel.textColor = NSColor(calibratedWhite: 0.65, alpha: 1.0)
        card.addSubview(stackLabel)

        let stackInputW: CGFloat = w - 210
        let stackInput = NSTextField(frame: NSRect(x: startX + 42, y: 44, width: stackInputW, height: 22))
        stackInput.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        stackInput.textColor = .white
        stackInput.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1.0)
        stackInput.isBezeled = false
        stackInput.isEditable = true
        stackInput.isSelectable = true
        stackInput.focusRingType = .none
        stackInput.wantsLayer = true
        stackInput.layer?.cornerRadius = 4
        stackInput.placeholderAttributedString = NSAttributedString(
            string: "e.g. Local AI, Architecture",
            attributes: [.foregroundColor: NSColor(calibratedWhite: 0.45, alpha: 1.0), .font: NSFont.systemFont(ofSize: 10)]
        )
        stackInput.stringValue = (thread.tags ?? []).joined(separator: ", ")
        card.addSubview(stackInput)

        // Existing Stacks Menu Button [▾ Stacks]
        let customStacks = UserDefaults.standard.stringArray(forKey: "SutraCustomStacks") ?? []
        let existingStacks = Array(Set(allThreads.flatMap { $0.tags ?? [] } + customStacks)).sorted()
        let stackMenuBtn = ClosureButton(frame: NSRect(x: startX + 46 + stackInputW, y: 44, width: 32, height: 22)) { [weak stackInput] in
            guard let stackInput = stackInput else { return }
            let menu = NSMenu(title: "Stacks")
            if existingStacks.isEmpty {
                let emptyItem = NSMenuItem(title: "No Stacks Created", action: nil, keyEquivalent: "")
                emptyItem.isEnabled = false
                menu.addItem(emptyItem)
            } else {
                for stack in existingStacks {
                    let item = NSMenuItem(title: stack, action: #selector(SanctuaryPopover.onSelectInlineStack(_:)), keyEquivalent: "")
                    item.target = SanctuaryPopover.shared
                    item.representedObject = stackInput
                    menu.addItem(item)
                }
            }
            if let event = NSApp.currentEvent {
                NSMenu.popUpContextMenu(menu, with: event, for: stackInput)
            }
        }
        stackMenuBtn.title = "▾"
        stackMenuBtn.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        stackMenuBtn.isBordered = false
        stackMenuBtn.wantsLayer = true
        stackMenuBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.20, alpha: 1.0).cgColor
        stackMenuBtn.layer?.cornerRadius = 4
        card.addSubview(stackMenuBtn)

        // Inline Date Scheduler Button [📅 Schedule]
        let scheduleBtn = ClosureButton(frame: NSRect(x: startX + 42, y: 12, width: 88, height: 24)) { [weak self] in
            guard let self = self else { return }
            self.showInlineCalendarPopover(for: thread)
        }
        scheduleBtn.isBordered = false
        scheduleBtn.wantsLayer = true
        scheduleBtn.layer?.cornerRadius = 4
        scheduleBtn.layer?.borderWidth = 1.0

        if let due = editingDueDate {
            let df = DateFormatter()
            df.dateFormat = "MMM d"
            let dateText = Calendar.current.isDateInToday(due) ? "Today" : df.string(from: due)
            scheduleBtn.attributedTitle = NSAttributedString(string: dateText, attributes: [
                .foregroundColor: NSColor(calibratedRed: 0.95, green: 0.60, blue: 0.35, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold)
            ])
            scheduleBtn.layer?.backgroundColor = NSColor(calibratedRed: 0.20, green: 0.14, blue: 0.10, alpha: 1.0).cgColor
            scheduleBtn.layer?.borderColor = NSColor(calibratedRed: 0.90, green: 0.45, blue: 0.20, alpha: 0.35).cgColor
        } else {
            scheduleBtn.attributedTitle = NSAttributedString(string: "Schedule", attributes: [
                .foregroundColor: NSColor(calibratedWhite: 0.70, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 10, weight: .medium)
            ])
            scheduleBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1.0).cgColor
            scheduleBtn.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.10).cgColor
        }
        card.addSubview(scheduleBtn)

        // Cancel Button
        let cancelBtn = ClosureButton(frame: NSRect(x: frame.width - 120, y: 12, width: 48, height: 24)) { [weak self] in
            guard let self = self else { return }
            self.editCalendarPopover?.performClose(nil)
            self.editCalendarPopover = nil
            self.editingThreadId = nil
            self.editingDueDate = nil
            self.renderThreadList()
        }
        cancelBtn.isBordered = false
        cancelBtn.wantsLayer = true
        cancelBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.20, alpha: 1.0).cgColor
        cancelBtn.layer?.cornerRadius = 4
        cancelBtn.attributedTitle = NSAttributedString(string: "Cancel", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.85, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 10, weight: .medium)
        ])
        card.addSubview(cancelBtn)

        // Save Button
        let saveBtn = ClosureButton(frame: NSRect(x: frame.width - 66, y: 12, width: 50, height: 24)) { [weak self] in
            guard let self = self else { return }
            self.editCalendarPopover?.performClose(nil)
            self.editCalendarPopover = nil
            let newTitle = titleInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newTitle.isEmpty else { return }
            let newNotes = notesInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

            let stackRaw = stackInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            var newTags: [String] = []
            if !stackRaw.isEmpty {
                newTags = stackRaw.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
                }.filter { !$0.isEmpty }
            }

            _ = SutraBridge.shared.updateThread(
                id: thread.id,
                title: newTitle,
                notes: newNotes.isEmpty ? nil : newNotes,
                tags: newTags.isEmpty ? nil : newTags,
                dueAt: self.editingDueDate
            )

            NSSound(named: "Tink")?.play()
            self.editingThreadId = nil
            self.editingDueDate = nil
            self.fetchData()
            self.renderThreadList()
            NotificationCenter.default.post(name: NSNotification.Name("SutraThreadsUpdated"), object: nil)
        }
        saveBtn.isBordered = false
        saveBtn.wantsLayer = true
        saveBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.95, alpha: 1.0).cgColor
        saveBtn.layer?.cornerRadius = 4
        saveBtn.attributedTitle = NSAttributedString(string: "Save", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.05, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 10, weight: .bold)
        ])
        card.addSubview(saveBtn)

        DispatchQueue.main.async { [weak self, weak titleInput] in
            guard let self = self, let titleInput = titleInput else { return }
            self.panel.makeFirstResponder(titleInput)
        }

        return card
    }

    static func loadSutraLogo(size: NSSize) -> NSImage {
        let paths = [
            Bundle.main.path(forResource: "logo", ofType: "png") ?? "",
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/logo.png").path,
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("assets/logo.png").path,
            Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("assets/logo.png").path
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
