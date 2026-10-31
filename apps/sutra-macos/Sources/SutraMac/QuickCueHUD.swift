import AppKit

public final class KeyFocusPanel: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }
    public var onKeyDown: ((NSEvent) -> Bool)?

    public override func keyDown(with event: NSEvent) {
        if let handler = onKeyDown, handler(event) {
            return
        }
        super.keyDown(with: event)
    }
}

public final class QuickCueHUD: NSObject, NSTextFieldDelegate {
    public static let shared = QuickCueHUD()

    private var panel: KeyFocusPanel!
    private var card: NSView!
    private var titleField: NSTextField!
    
    // Header & App Identity
    private var appIconView: NSImageView!
    private var appTitleLabel: NSTextField!
    private var contextSubtitleLabel: NSTextField!
    private var pillContainer: NSView!

    // Middle Deck
    private var middleDeck: NSView!

    // Tab buttons
    private var tabButtons: [String: NSButton] = [:]
    private var selectedCueType: String = "note"

    // Mode Views
    private var noteView: NSView!
    private var notesField: NSTextField!

    private var checklistView: NSView!
    private var checklistBoxes: [NSButton] = []
    private var checklistFields: [NSTextField] = []

    private var linkView: NSView!
    private var linkField: NSTextField!

    private var fileView: NSView!
    private var fileField: NSTextField!

    private var currentAnchor: SutraAnchor?
    private var selectedDueDate: Date? = nil
    private var datePickerBtn: NSButton!
    private var calendarPopover: NSPopover?
    private var stackBtn: NSButton!
    private var stackPopover: NSPopover?
    private var templatePopover: NSPopover?
    private var currentStack: String? = nil

    public override init() {
        super.init()
        setupHUD()
    }

    private func setupHUD() {
        let w: CGFloat = 520
        let h: CGFloat = 276
        panel = KeyFocusPanel(
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

        card = NSView(frame: panel.contentView!.bounds)
        card.autoresizingMask = [.width, .height]
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(calibratedWhite: 0.05, alpha: 0.98).cgColor
        card.layer?.cornerRadius = 16
        card.layer?.masksToBounds = true
        card.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.10).cgColor
        card.layer?.borderWidth = 1.0

        // ==========================================
        // 1. HEADER (y: h - 46 ... h)
        // ==========================================
        let headerY: CGFloat = h - 44

        // Sutra Silk Möbius Mark (Prominent 32x32)
        let logoImg = NSImageView(frame: NSRect(x: 14, y: headerY + 1, width: 32, height: 32))
        logoImg.image = loadSutraLogo(size: NSSize(width: 32, height: 32))
        card.addSubview(logoImg)

        // Dynamic Active App Identity Pill (Centered: half left, half right)
        let pillW: CGFloat = 300
        let pillX: CGFloat = (w - pillW) / 2
        pillContainer = NSView(frame: NSRect(x: pillX, y: headerY + 4, width: pillW, height: 26))
        pillContainer.wantsLayer = true
        pillContainer.layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 1.0).cgColor
        pillContainer.layer?.cornerRadius = 13
        pillContainer.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.10).cgColor
        pillContainer.layer?.borderWidth = 1.0

        // Active App Icon
        appIconView = NSImageView(frame: NSRect(x: 8, y: 4, width: 18, height: 18))
        pillContainer.addSubview(appIconView)

        // App Name Label
        appTitleLabel = NSTextField(labelWithString: "Desktop")
        appTitleLabel.frame = NSRect(x: 30, y: 4, width: 85, height: 17)
        appTitleLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .bold)
        appTitleLabel.textColor = NSColor(calibratedWhite: 0.95, alpha: 1.0)
        appTitleLabel.lineBreakMode = .byTruncatingTail
        pillContainer.addSubview(appTitleLabel)

        // Context Subtitle (Crisp Breadcrumb: concise host/page)
        contextSubtitleLabel = NSTextField(labelWithString: "• Active Workspace")
        contextSubtitleLabel.frame = NSRect(x: 120, y: 4, width: pillW - 126, height: 17)
        contextSubtitleLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        contextSubtitleLabel.textColor = NSColor(calibratedWhite: 0.65, alpha: 1.0)
        contextSubtitleLabel.lineBreakMode = .byTruncatingMiddle
        pillContainer.addSubview(contextSubtitleLabel)

        card.addSubview(pillContainer)

        // Dismiss Button [✕]
        let closeBtn = ClosureButton(frame: NSRect(x: w - 36, y: headerY + 6, width: 22, height: 22)) { [weak self] in
            self?.panel.orderOut(nil)
        }
        closeBtn.title = "✕"
        closeBtn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        closeBtn.isBordered = false
        closeBtn.wantsLayer = true
        closeBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 0.8).cgColor
        closeBtn.layer?.cornerRadius = 11
        card.addSubview(closeBtn)

        // ==========================================
        // 2. PRIMARY ACTION: IMMEDIATE NEXT ACTION
        // ==========================================
        let contentW: CGFloat = w - 40
        let contentX: CGFloat = (w - contentW) / 2

        let actionLabel = NSTextField(labelWithString: "Immediate Next Action")
        actionLabel.frame = NSRect(x: contentX, y: h - 76, width: contentW, height: 16)
        actionLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        actionLabel.textColor = NSColor(calibratedWhite: 0.85, alpha: 1.0)
        card.addSubview(actionLabel)

        titleField = createInputField(
            frame: NSRect(x: contentX, y: h - 116, width: contentW, height: 38),
            placeholder: "",
            fontSize: 13,
            weight: .medium
        )
        titleField.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor
        titleField.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.95).cgColor
        titleField.delegate = self
        card.addSubview(titleField)

        // ==========================================
        // 3. MIDDLE CONFIGURABLE DECK (y: 48 ... 148)
        // ==========================================
        middleDeck = NSView(frame: NSRect(x: contentX, y: 48, width: contentW, height: 100))
        card.addSubview(middleDeck)

        setupNoteView(width: contentW)
        setupChecklistView(width: contentW)
        setupLinkView(width: contentW)
        setupFileView(width: contentW)

        // Default to note mode
        switchMode(type: "note")

        // ==========================================
        // 4. BOTTOM UTILITY BAR: 4 SYMMETRIC 3D PILL GROUPS (y: 11 ... 37)
        // Group 1: [ Note | Task ] (104px)
        // Group 2: [ Link | File ] (104px)
        // Group 3: [ Schedule | Stack ] (140px)
        // Group 4: [ Esc | Leave ↩ ] (110px)
        // Total: 104 + 7 + 104 + 7 + 140 + 7 + 110 = 479px (fits inside contentW: 480px)
        // ==========================================
        let barY: CGFloat = 11
        let barH: CGFloat = 26
        let gap: CGFloat = 7

        // Helper closure to create the identical 3D capsule container
        func createPillContainer(frame: NSRect) -> NSView {
            let container = NSView(frame: frame)
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1.0).cgColor
            container.layer?.cornerRadius = 13
            container.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.14).cgColor
            container.layer?.borderWidth = 1.0
            // ponytail: 3D shadow for tactile pill elevation
            container.layer?.shadowColor = NSColor.black.cgColor
            container.layer?.shadowOpacity = 0.45
            container.layer?.shadowOffset = CGSize(width: 0, height: -1.5)
            container.layer?.shadowRadius = 2.0
            return container
        }

        func addBevelSeparator(to container: NSView, at x: CGFloat) {
            let sepGroove = NSView(frame: NSRect(x: x, y: 4, width: 1, height: barH - 8))
            sepGroove.wantsLayer = true
            sepGroove.layer?.backgroundColor = NSColor(calibratedWhite: 0.04, alpha: 0.9).cgColor
            container.addSubview(sepGroove)

            let sepHighlight = NSView(frame: NSRect(x: x + 1, y: 4, width: 1, height: barH - 8))
            sepHighlight.wantsLayer = true
            sepHighlight.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.18).cgColor
            container.addSubview(sepHighlight)
        }

        var curX = contentX

        // ------------------------------------------
        // GROUP 1: [ Note | Task ]
        // ------------------------------------------
        let g1W: CGFloat = 104
        let g1Container = createPillContainer(frame: NSRect(x: curX, y: barY, width: g1W, height: barH))
        
        let noteBtn = NSButton(frame: NSRect(x: 1, y: 1, width: 50, height: barH - 2))
        noteBtn.isBordered = false
        noteBtn.wantsLayer = true
        noteBtn.layer?.cornerRadius = 12
        noteBtn.target = self
        noteBtn.action = #selector(onTabClicked(_:))
        noteBtn.identifier = NSUserInterfaceItemIdentifier("note")
        noteBtn.title = "Note"
        tabButtons["note"] = noteBtn
        g1Container.addSubview(noteBtn)

        addBevelSeparator(to: g1Container, at: 51)

        let taskBtn = NSButton(frame: NSRect(x: 53, y: 1, width: 50, height: barH - 2))
        taskBtn.isBordered = false
        taskBtn.wantsLayer = true
        taskBtn.layer?.cornerRadius = 12
        taskBtn.target = self
        taskBtn.action = #selector(onTabClicked(_:))
        taskBtn.identifier = NSUserInterfaceItemIdentifier("checklist")
        taskBtn.title = "Task"
        tabButtons["checklist"] = taskBtn
        g1Container.addSubview(taskBtn)

        card.addSubview(g1Container)
        curX += g1W + gap

        // ------------------------------------------
        // GROUP 2: [ Link | File ]
        // ------------------------------------------
        let g2W: CGFloat = 104
        let g2Container = createPillContainer(frame: NSRect(x: curX, y: barY, width: g2W, height: barH))

        let linkBtn = NSButton(frame: NSRect(x: 1, y: 1, width: 50, height: barH - 2))
        linkBtn.isBordered = false
        linkBtn.wantsLayer = true
        linkBtn.layer?.cornerRadius = 12
        linkBtn.target = self
        linkBtn.action = #selector(onTabClicked(_:))
        linkBtn.identifier = NSUserInterfaceItemIdentifier("link")
        linkBtn.title = "Link"
        tabButtons["link"] = linkBtn
        g2Container.addSubview(linkBtn)

        addBevelSeparator(to: g2Container, at: 51)

        let fileBtn = NSButton(frame: NSRect(x: 53, y: 1, width: 50, height: barH - 2))
        fileBtn.isBordered = false
        fileBtn.wantsLayer = true
        fileBtn.layer?.cornerRadius = 12
        fileBtn.target = self
        fileBtn.action = #selector(onTabClicked(_:))
        fileBtn.identifier = NSUserInterfaceItemIdentifier("file")
        fileBtn.title = "File"
        tabButtons["file"] = fileBtn
        g2Container.addSubview(fileBtn)

        card.addSubview(g2Container)
        curX += g2W + gap

        // ------------------------------------------
        // GROUP 3: [ Schedule | Stack ]
        // ------------------------------------------
        let g3W: CGFloat = 144
        let g3Container = createPillContainer(frame: NSRect(x: curX, y: barY, width: g3W, height: barH))

        datePickerBtn = NSButton(frame: NSRect(x: 1, y: 1, width: 70, height: barH - 2))
        datePickerBtn.isBordered = false
        datePickerBtn.wantsLayer = true
        datePickerBtn.layer?.cornerRadius = 12
        datePickerBtn.target = self
        datePickerBtn.action = #selector(onDatePickerClicked(_:))
        g3Container.addSubview(datePickerBtn)

        addBevelSeparator(to: g3Container, at: 71)

        stackBtn = NSButton(frame: NSRect(x: 73, y: 1, width: 70, height: barH - 2))
        stackBtn.isBordered = false
        stackBtn.wantsLayer = true
        stackBtn.layer?.cornerRadius = 12
        stackBtn.target = self
        stackBtn.action = #selector(onStackButtonClicked(_:))
        g3Container.addSubview(stackBtn)

        updateDateButtonTitle()
        updateStackButtonTitle()

        card.addSubview(g3Container)
        curX += g3W + gap

        // ------------------------------------------
        // GROUP 4: [ Esc | Leave ↩ ]
        // ------------------------------------------
        let g4W: CGFloat = 112
        let g4Container = createPillContainer(frame: NSRect(x: curX, y: barY, width: g4W, height: barH))

        let escBtn = ClosureButton(frame: NSRect(x: 1, y: 1, width: 40, height: barH - 2)) { [weak self] in
            self?.panel.orderOut(nil)
        }
        escBtn.title = "Esc"
        escBtn.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        escBtn.isBordered = false
        escBtn.wantsLayer = true
        escBtn.layer?.cornerRadius = 12
        escBtn.attributedTitle = NSAttributedString(string: "Esc", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.7, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 10.5, weight: .medium)
        ])
        g4Container.addSubview(escBtn)

        addBevelSeparator(to: g4Container, at: 41)

        // Leave ↩ is ALWAYS prominently highlighted in clean bright ivory
        let submitBtn = ClosureButton(frame: NSRect(x: 43, y: 1, width: 68, height: barH - 2)) { [weak self] in
            self?.submit()
        }
        submitBtn.attributedTitle = NSAttributedString(string: "Leave ↩", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.05, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 10.5, weight: .bold)
        ])
        submitBtn.isBordered = false
        submitBtn.wantsLayer = true
        submitBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.95, alpha: 1.0).cgColor
        submitBtn.layer?.cornerRadius = 12
        g4Container.addSubview(submitBtn)

        card.addSubview(g4Container)

        updateTabStyles()

        panel.contentView?.addSubview(card)
    }

    // MARK: - Middle Deck Setup

    private func setupNoteView(width: CGFloat) {
        noteView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 100))

        let heading = NSTextField(labelWithString: "Context")
        heading.frame = NSRect(x: 0, y: 80, width: width, height: 16)
        heading.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        heading.textColor = NSColor(calibratedWhite: 0.85, alpha: 1.0)
        noteView.addSubview(heading)

        notesField = createInputField(
            frame: NSRect(x: 0, y: 4, width: width, height: 72),
            placeholder: "",
            fontSize: 12,
            weight: .regular
        )
        notesField.delegate = self
        noteView.addSubview(notesField)
    }

    private func setupChecklistView(width: CGFloat) {
        checklistView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        checklistBoxes.removeAll()
        checklistFields.removeAll()

        let heading = NSTextField(labelWithString: "Tasks")
        heading.frame = NSRect(x: 0, y: 80, width: 120, height: 16)
        heading.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        heading.textColor = NSColor(calibratedWhite: 0.85, alpha: 1.0)
        checklistView.addSubview(heading)

        let isTplEnabled = UserDefaults.standard.object(forKey: "SutraEnableTemplates") as? Bool ?? true
        if isTplEnabled {
            let tplBtn = ClosureButton(frame: NSRect(x: width - 96, y: 78, width: 96, height: 18)) { [weak self] in
                guard let self = self else { return }
                self.showTemplateSelector(relativeTo: self.checklistView)
            }
            tplBtn.isBordered = false
            tplBtn.wantsLayer = true
            tplBtn.layer?.cornerRadius = 9
            tplBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1.0).cgColor
            tplBtn.attributedTitle = NSAttributedString(string: "Templates ▾", attributes: [
                .foregroundColor: NSColor(calibratedRed: 0.90, green: 0.55, blue: 0.25, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 9.5, weight: .bold)
            ])
            checklistView.addSubview(tplBtn)
        }

        let rowH: CGFloat = 23
        for i in 0..<3 {
            let rowY = CGFloat(2 - i) * (rowH + 3)
            let row = NSView(frame: NSRect(x: 0, y: rowY, width: width, height: rowH))

            // Checkbox Button
            let box = NSButton(frame: NSRect(x: 2, y: 1, width: 20, height: 20))
            box.setButtonType(.switch)
            box.title = ""
            box.tag = i
            box.target = self
            box.action = #selector(onChecklistToggled(_:))
            row.addSubview(box)
            checklistBoxes.append(box)

            // Editable Item Field
            let field = createInputField(
                frame: NSRect(x: 26, y: 0, width: width - 26, height: rowH),
                placeholder: "",
                fontSize: 11.5,
                weight: .medium
            )
            field.tag = i
            field.delegate = self
            row.addSubview(field)
            checklistFields.append(field)

            checklistView.addSubview(row)
        }
    }

    private func setupLinkView(width: CGFloat) {
        linkView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 100))

        let label = NSTextField(labelWithString: "Reference Web Link")
        label.frame = NSRect(x: 0, y: 80, width: width, height: 16)
        label.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        label.textColor = NSColor(calibratedWhite: 0.85, alpha: 1.0)
        linkView.addSubview(label)

        linkField = createInputField(
            frame: NSRect(x: 0, y: 12, width: width, height: 58),
            placeholder: "https://...",
            fontSize: 12,
            weight: .regular
        )
        linkField.delegate = self
        linkView.addSubview(linkField)
    }

    private func setupFileView(width: CGFloat) {
        fileView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 100))

        let label = NSTextField(labelWithString: "File Path")
        label.frame = NSRect(x: 0, y: 80, width: width, height: 16)
        label.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        label.textColor = NSColor(calibratedWhite: 0.85, alpha: 1.0)
        fileView.addSubview(label)

        fileField = createInputField(
            frame: NSRect(x: 0, y: 18, width: width - 96, height: 52),
            placeholder: "/path/to/file or folder",
            fontSize: 12,
            weight: .regular
        )
        fileField.delegate = self
        fileView.addSubview(fileField)

        let browseBtn = ClosureButton(frame: NSRect(x: width - 88, y: 18, width: 88, height: 52)) { [weak self] in
            self?.onBrowseFile()
        }
        browseBtn.title = "Browse..."
        browseBtn.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        browseBtn.isBordered = false
        browseBtn.wantsLayer = true
        browseBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 0.9).cgColor
        browseBtn.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor
        browseBtn.layer?.borderWidth = 1.0
        browseBtn.layer?.cornerRadius = 8
        fileView.addSubview(browseBtn)
    }

    // MARK: - Tab Switching

    @objc private func onTabClicked(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        switchMode(type: key)
    }

    private func switchMode(type: String) {
        selectedCueType = type
        middleDeck.subviews.forEach { $0.removeFromSuperview() }

        switch type {
        case "checklist":
            middleDeck.addSubview(checklistView)
            if let first = checklistFields.first, first.stringValue.isEmpty {
                panel.makeFirstResponder(first)
            }
        case "link":
            middleDeck.addSubview(linkView)
            if linkField.stringValue.isEmpty {
                if let url = currentAnchor?.url, !url.isEmpty {
                    linkField.stringValue = url
                } else if let fp = currentAnchor?.file_path, !fp.isEmpty {
                    let fileUrl = URL(fileURLWithPath: fp)
                    if let page = currentAnchor?.line_number, page > 0 {
                        var comp = URLComponents(url: fileUrl, resolvingAgainstBaseURL: false)
                        comp?.fragment = "page=\(page)"
                        linkField.stringValue = comp?.url?.absoluteString ?? fileUrl.absoluteString
                    } else {
                        linkField.stringValue = fileUrl.absoluteString
                    }
                }
            }
            panel.makeFirstResponder(linkField)
        case "file":
            middleDeck.addSubview(fileView)
            if fileField.stringValue.isEmpty {
                if let fp = currentAnchor?.file_path, !fp.isEmpty {
                    fileField.stringValue = fp
                } else if let url = currentAnchor?.url, url.hasPrefix("file://") {
                    fileField.stringValue = URL(string: url)?.path ?? url
                }
            }
            panel.makeFirstResponder(fileField)
        default:
            middleDeck.addSubview(noteView)
        }
        updateTabStyles()
    }

    private func updateTabStyles() {
        for (key, btn) in tabButtons {
            let isSelected = (key == selectedCueType)
            if isSelected {
                btn.layer?.backgroundColor = NSColor(calibratedWhite: 0.95, alpha: 1.0).cgColor
                btn.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.25).cgColor
                btn.layer?.borderWidth = 1.0
                btn.attributedTitle = NSAttributedString(string: btn.title, attributes: [
                    .foregroundColor: NSColor(calibratedWhite: 0.05, alpha: 1.0),
                    .font: NSFont.systemFont(ofSize: 10, weight: .bold)
                ])
            } else {
                btn.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1.0).cgColor
                btn.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
                btn.layer?.borderWidth = 1.0
                btn.attributedTitle = NSAttributedString(string: btn.title, attributes: [
                    .foregroundColor: NSColor(calibratedWhite: 0.7, alpha: 1.0),
                    .font: NSFont.systemFont(ofSize: 10, weight: .medium)
                ])
            }
        }
    }

    // MARK: - Checklist Checkbox Action (Strikethrough & Dim)

    @objc private func onChecklistToggled(_ sender: NSButton) {
        let index = sender.tag
        guard index >= 0 && index < checklistFields.count else { return }
        let field = checklistFields[index]
        let isChecked = (sender.state == .on)
        let text = field.stringValue

        guard !text.isEmpty else { return }

        let attr = NSMutableAttributedString(string: text)
        if isChecked {
            attr.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: text.count))
            attr.addAttribute(.foregroundColor, value: NSColor(calibratedWhite: 0.45, alpha: 1.0), range: NSRange(location: 0, length: text.count))
            attr.addAttribute(.font, value: NSFont.systemFont(ofSize: 11.5, weight: .regular), range: NSRange(location: 0, length: text.count))
        } else {
            attr.addAttribute(.foregroundColor, value: NSColor.white, range: NSRange(location: 0, length: text.count))
            attr.addAttribute(.font, value: NSFont.systemFont(ofSize: 11.5, weight: .medium), range: NSRange(location: 0, length: text.count))
        }
        field.attributedStringValue = attr
    }

    @objc private func onBrowseFile() {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = true
        if openPanel.runModal() == .OK, let url = openPanel.url {
            fileField.stringValue = url.path
        }
    }

    // MARK: - Stack Selector Popover (List Stacks + + New Stack)

    @objc private func onStackButtonClicked(_ sender: NSButton) {
        if let existing = stackPopover, existing.isShown {
            existing.performClose(nil)
            stackPopover = nil
            return
        }

        let allThreads = SutraBridge.shared.list(status: "waiting") + SutraBridge.shared.list(status: "later") + SutraBridge.shared.list(status: "done")
        let customStacks = UserDefaults.standard.stringArray(forKey: "SutraCustomStacks") ?? []
        let existingStacks = Array(Set(allThreads.flatMap { $0.tags ?? [] } + customStacks)).sorted()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        let popW: CGFloat = 190
        let rowH: CGFloat = 28
        let totalH = max(CGFloat(existingStacks.count + 2) * rowH + 16, 90)
        let popH = min(totalH, 240)

        let popoverView = NSView(frame: NSRect(x: 0, y: 0, width: popW, height: popH))
        popoverView.wantsLayer = true
        popoverView.layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 0.98).cgColor

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 36, width: popW, height: popH - 36))
        scrollView.hasVerticalScroller = existingStacks.count > 5
        scrollView.drawsBackground = false

        let docViewH = CGFloat(max(existingStacks.count, 1)) * rowH
        let docView = NSView(frame: NSRect(x: 0, y: 0, width: popW, height: docViewH))

        if existingStacks.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "No stacks yet")
            emptyLabel.frame = NSRect(x: 12, y: 6, width: popW - 24, height: 20)
            emptyLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            emptyLabel.textColor = NSColor(calibratedWhite: 0.5, alpha: 1.0)
            docView.addSubview(emptyLabel)
        } else {
            for (idx, stack) in existingStacks.enumerated() {
                let rowY = docViewH - CGFloat(idx + 1) * rowH
                let itemBtn = ClosureButton(frame: NSRect(x: 6, y: rowY + 2, width: popW - 12, height: rowH - 4)) { [weak self, weak popover] in
                    self?.currentStack = stack
                    self?.updateStackButtonTitle()
                    popover?.performClose(nil)
                }
                itemBtn.title = stack
                itemBtn.font = NSFont.systemFont(ofSize: 11, weight: (self.currentStack == stack ? .bold : .medium))
                itemBtn.alignment = .left
                itemBtn.isBordered = false
                itemBtn.wantsLayer = true
                itemBtn.layer?.backgroundColor = (self.currentStack == stack ? NSColor(calibratedWhite: 0.24, alpha: 1.0).cgColor : NSColor.clear.cgColor)
                itemBtn.layer?.cornerRadius = 5
                docView.addSubview(itemBtn)
            }
        }
        scrollView.documentView = docView
        popoverView.addSubview(scrollView)

        // Bottom Action: + New Stack
        let addStackBtn = ClosureButton(frame: NSRect(x: 6, y: 6, width: popW - 12, height: 26)) { [weak self, weak popover] in
            popover?.performClose(nil)
            self?.promptNewStack()
        }
        addStackBtn.title = "+ New Stack"
        addStackBtn.font = NSFont.systemFont(ofSize: 10.5, weight: .bold)
        addStackBtn.isBordered = false
        addStackBtn.wantsLayer = true
        addStackBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.20, alpha: 1.0).cgColor
        addStackBtn.layer?.cornerRadius = 5
        popoverView.addSubview(addStackBtn)

        let controller = NSViewController()
        controller.view = popoverView
        popover.contentViewController = controller

        self.stackPopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    private func promptNewStack() {
        let alert = NSAlert()
        alert.messageText = "Create New Stack"
        alert.informativeText = "Enter stack tag name (e.g., Design, Infra, Reading):"
        alert.alertStyle = .informational
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = input
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            let val = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
            if !val.isEmpty {
                // Persist to custom stacks immediately
                var custom = UserDefaults.standard.stringArray(forKey: "SutraCustomStacks") ?? []
                if !custom.contains(where: { $0.caseInsensitiveCompare(val) == .orderedSame }) {
                    custom.append(val)
                    UserDefaults.standard.set(custom, forKey: "SutraCustomStacks")
                }
                self.currentStack = val
                self.updateStackButtonTitle()
                NotificationCenter.default.post(name: NSNotification.Name("SutraThreadsUpdated"), object: nil)
            }
        }
    }

    private func updateStackButtonTitle() {
        if let stack = currentStack, !stack.isEmpty {
            stackBtn.attributedTitle = NSAttributedString(string: stack, attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold)
            ])
            stackBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.95, alpha: 0.15).cgColor
            stackBtn.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.35).cgColor
        } else {
            stackBtn.attributedTitle = NSAttributedString(string: "Stack", attributes: [
                .foregroundColor: NSColor(calibratedWhite: 0.70, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 10, weight: .medium)
            ])
            stackBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1.0).cgColor
            stackBtn.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
        }
    }

    // MARK: - Direct Graphical Calendar Popover Scheduling

    @objc private func onDatePickerClicked(_ sender: NSButton) {
        if let existing = calendarPopover, existing.isShown {
            existing.performClose(nil)
            calendarPopover = nil
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
            initialDate: selectedDueDate ?? Date()
        )
        calendarView.selectedDate = selectedDueDate
        calendarView.onDateSelected = { [weak self, weak popover] chosenDate in
            guard let self = self else { return }
            self.selectedDueDate = chosenDate
            self.updateDateButtonTitle()
            popover?.performClose(nil)
            self.calendarPopover = nil
        }
        popoverView.addSubview(calendarView)

        // Clear button
        let clearBtn = ClosureButton(frame: NSRect(x: 14, y: 12, width: 110, height: 26)) { [weak self, weak popover] in
            guard let self = self else { return }
            self.selectedDueDate = nil
            self.updateDateButtonTitle()
            popover?.performClose(nil)
            self.calendarPopover = nil
        }
        clearBtn.title = "Clear"
        clearBtn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        clearBtn.isBordered = false
        clearBtn.wantsLayer = true
        clearBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1.0).cgColor
        clearBtn.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
        clearBtn.layer?.borderWidth = 1.0
        clearBtn.layer?.cornerRadius = 6
        popoverView.addSubview(clearBtn)

        // Today shortcut button (Studio neutral secondary — terracotta reserved for selected date)
        let todayBtn = ClosureButton(frame: NSRect(x: popWidth - 124, y: 12, width: 110, height: 26)) { [weak self, weak popover] in
            guard let self = self else { return }
            self.selectedDueDate = Calendar.current.startOfDay(for: Date())
            self.updateDateButtonTitle()
            popover?.performClose(nil)
            self.calendarPopover = nil
        }
        todayBtn.attributedTitle = NSAttributedString(string: "Today", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.95, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 11, weight: .bold)
        ])
        todayBtn.isBordered = false
        todayBtn.wantsLayer = true
        todayBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.22, alpha: 1.0).cgColor
        todayBtn.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.14).cgColor
        todayBtn.layer?.borderWidth = 1.0
        todayBtn.layer?.cornerRadius = 6
        popoverView.addSubview(todayBtn)

        let controller = NSViewController()
        controller.view = popoverView
        popover.contentViewController = controller

        self.calendarPopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    private func updateDateButtonTitle() {
        if let date = selectedDueDate {
            let cal = Calendar.current
            let title: String
            if cal.isDateInToday(date) {
                title = "Today"
            } else {
                let df = DateFormatter()
                df.dateFormat = "MMM d"
                title = df.string(from: date)
            }
            datePickerBtn.attributedTitle = NSAttributedString(string: title, attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold)
            ])
            datePickerBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.95, alpha: 0.15).cgColor
            datePickerBtn.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.35).cgColor
        } else {
            datePickerBtn.attributedTitle = NSAttributedString(string: "Schedule", attributes: [
                .foregroundColor: NSColor(calibratedWhite: 0.70, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 10, weight: .medium)
            ])
            datePickerBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1.0).cgColor
            datePickerBtn.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
        }
    }

    // MARK: - Natural Language Snooze Parser (PLAN-029 Gap 1, inspired by Cuewake)

    public static func parseNaturalLanguageDate(from text: String) -> (cleanTitle: String, date: Date?) {
        let isNLPEnabled = UserDefaults.standard.object(forKey: "SutraEnableNLPSnooze") as? Bool ?? true
        guard isNLPEnabled else { return (text, nil) }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let cal = Calendar.current

        // Pattern 1: "in X h/hrs/hours" or "in X m/mins/minutes" or "in X d/days"
        let relPattern = #"(?i)\b(?:in\s+)?(\d+)\s*(m|min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days)\b"#
        if let regex = try? NSRegularExpression(pattern: relPattern),
           let match = regex.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)).last {
            if let numRange = Range(match.range(at: 1), in: trimmed),
               let unitRange = Range(match.range(at: 2), in: trimmed),
               let num = Double(trimmed[numRange]) {
                let unit = trimmed[unitRange].lowercased()
                var seconds: TimeInterval = 0
                if unit.hasPrefix("m") { seconds = num * 60 }
                else if unit.hasPrefix("h") { seconds = num * 3600 }
                else if unit.hasPrefix("d") { seconds = num * 86400 }

                if seconds > 0 {
                    let date = now.addingTimeInterval(seconds)
                    let clean = trimmed.replacingCharacters(in: Range(match.range, in: trimmed)!, with: "").trimmingCharacters(in: .whitespaces)
                    return (clean.isEmpty ? trimmed : clean, date)
                }
            }
        }

        // Pattern 2: "tomorrow at X(am|pm)?" or just "tomorrow"
        let tomorrowPattern = #"(?i)\btomorrow(?:\s+at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?)?\b"#
        if let regex = try? NSRegularExpression(pattern: tomorrowPattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
            var targetHour = 9
            var targetMinute = 0
            if match.range(at: 1).location != NSNotFound, let hRange = Range(match.range(at: 1), in: trimmed), let h = Int(trimmed[hRange]) {
                targetHour = h
                if match.range(at: 3).location != NSNotFound, let ampmRange = Range(match.range(at: 3), in: trimmed) {
                    let ampm = trimmed[ampmRange].lowercased()
                    if ampm == "pm" && targetHour < 12 { targetHour += 12 }
                    if ampm == "am" && targetHour == 12 { targetHour = 0 }
                }
            }
            if match.range(at: 2).location != NSNotFound, let mRange = Range(match.range(at: 2), in: trimmed), let m = Int(trimmed[mRange]) {
                targetMinute = m
            }

            if let tomorrow = cal.date(byAdding: .day, value: 1, to: now) {
                var comps = cal.dateComponents([.year, .month, .day], from: tomorrow)
                comps.hour = targetHour
                comps.minute = targetMinute
                comps.second = 0
                if let date = cal.date(from: comps) {
                    let clean = trimmed.replacingCharacters(in: Range(match.range, in: trimmed)!, with: "").trimmingCharacters(in: .whitespaces)
                    return (clean.isEmpty ? trimmed : clean, date)
                }
            }
        }

        // Pattern 3: "today at X(am|pm)?" or "tonight"
        let todayPattern = #"(?i)\b(?:today\s+at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?|tonight)\b"#
        if let regex = try? NSRegularExpression(pattern: todayPattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
            var targetHour = 20
            var targetMinute = 0
            if match.range(at: 1).location != NSNotFound, let hRange = Range(match.range(at: 1), in: trimmed), let h = Int(trimmed[hRange]) {
                targetHour = h
                if match.range(at: 3).location != NSNotFound, let ampmRange = Range(match.range(at: 3), in: trimmed) {
                    let ampm = trimmed[ampmRange].lowercased()
                    if ampm == "pm" && targetHour < 12 { targetHour += 12 }
                    if ampm == "am" && targetHour == 12 { targetHour = 0 }
                }
            }
            if match.range(at: 2).location != NSNotFound, let mRange = Range(match.range(at: 2), in: trimmed), let m = Int(trimmed[mRange]) {
                targetMinute = m
            }
            var comps = cal.dateComponents([.year, .month, .day], from: now)
            comps.hour = targetHour
            comps.minute = targetMinute
            comps.second = 0
            if let date = cal.date(from: comps), date > now {
                let clean = trimmed.replacingCharacters(in: Range(match.range, in: trimmed)!, with: "").trimmingCharacters(in: .whitespaces)
                return (clean.isEmpty ? trimmed : clean, date)
            }
        }

        return (trimmed, nil)
    }

    // MARK: - Reusable Checklist Templates (PLAN-029 Gap 2, inspired by Cuewake)

    private func showTemplateSelector(relativeTo view: NSView) {
        if let existing = templatePopover, existing.isShown {
            existing.performClose(nil)
            templatePopover = nil
            return
        }

        let templates = SutraBridge.shared.getTemplates()
        let popWidth: CGFloat = 260
        let rowH: CGFloat = 36
        let headerH: CGFloat = 36
        let footerH: CGFloat = 38
        let popHeight: CGFloat = headerH + CGFloat(templates.count) * rowH + footerH

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        let popView = NSView(frame: NSRect(x: 0, y: 0, width: popWidth, height: popHeight))
        popView.wantsLayer = true
        popView.layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 0.98).cgColor

        // Header
        let titleLbl = NSTextField(labelWithString: "CHECKLIST TEMPLATES")
        titleLbl.font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
        titleLbl.textColor = NSColor(calibratedWhite: 0.75, alpha: 1.0)
        titleLbl.frame = NSRect(x: 14, y: popHeight - 26, width: 230, height: 16)
        popView.addSubview(titleLbl)

        // Template rows
        for (i, tpl) in templates.enumerated() {
            let rowY = popHeight - headerH - CGFloat(i + 1) * rowH
            let rowView = NSView(frame: NSRect(x: 10, y: rowY, width: popWidth - 20, height: rowH - 4))
            rowView.wantsLayer = true
            rowView.layer?.cornerRadius = 6
            rowView.layer?.backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 1.0).cgColor

            let tName = NSTextField(labelWithString: tpl.name)
            tName.isBezeled = false
            tName.drawsBackground = false
            tName.isEditable = false
            tName.isSelectable = false
            tName.font = NSFont.systemFont(ofSize: 11, weight: .bold)
            tName.textColor = .white
            tName.frame = NSRect(x: 10, y: 16, width: popWidth - 40, height: 14)
            rowView.addSubview(tName)

            let tItems = NSTextField(labelWithString: "\(tpl.items.count) steps: " + tpl.items.prefix(2).joined(separator: ", ") + "…")
            tItems.isBezeled = false
            tItems.drawsBackground = false
            tItems.isEditable = false
            tItems.isSelectable = false
            tItems.font = NSFont.systemFont(ofSize: 9.5, weight: .regular)
            tItems.textColor = NSColor(calibratedWhite: 0.60, alpha: 1.0)
            tItems.frame = NSRect(x: 10, y: 2, width: popWidth - 40, height: 14)
            tItems.cell?.lineBreakMode = .byTruncatingTail
            rowView.addSubview(tItems)

            let rowBtn = ClosureButton(frame: NSRect(x: 0, y: 0, width: popWidth - 20, height: rowH - 4)) { [weak self, weak popover] in
                self?.applyTemplate(tpl)
                popover?.performClose(nil)
                self?.templatePopover = nil
            }
            rowBtn.title = ""
            rowBtn.attributedTitle = NSAttributedString(string: "")
            rowBtn.isBordered = false
            rowBtn.wantsLayer = true
            rowBtn.layer?.backgroundColor = NSColor.clear.cgColor
            rowView.addSubview(rowBtn)

            popView.addSubview(rowView)
        }

        // Footer: Save Current Checklist Button
        let saveCurrentBtn = ClosureButton(frame: NSRect(x: 10, y: 8, width: popWidth - 20, height: 24)) { [weak self, weak popover] in
            guard let self = self else { return }
            let items = self.checklistFields.map { $0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if !items.isEmpty {
                let name = self.titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let templateName = name.isEmpty ? "Custom Checklist" : name
                _ = SutraBridge.shared.saveTemplate(name: templateName, items: items)
                NSSound(named: "Tink")?.play()
            }
            popover?.performClose(nil)
            self.templatePopover = nil
        }
        saveCurrentBtn.isBordered = false
        saveCurrentBtn.wantsLayer = true
        saveCurrentBtn.layer?.cornerRadius = 4
        saveCurrentBtn.layer?.backgroundColor = NSColor(calibratedRed: 0.85, green: 0.40, blue: 0.18, alpha: 1.0).cgColor
        saveCurrentBtn.attributedTitle = NSAttributedString(string: "+ Save Current as Template", attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 10, weight: .bold)
        ])
        popView.addSubview(saveCurrentBtn)

        let vc = NSViewController()
        vc.view = popView
        popover.contentViewController = vc
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
        self.templatePopover = popover
    }

    private func applyTemplate(_ template: (id: String, name: String, items: [String])) {
        for (i, field) in checklistFields.enumerated() {
            if i < template.items.count {
                field.stringValue = template.items[i]
                checklistBoxes[i].state = .off
            } else {
                field.stringValue = ""
                checklistBoxes[i].state = .off
            }
        }
        if titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            titleField.stringValue = template.name
        }
    }

    private func createInputField(frame: NSRect, placeholder: String, fontSize: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let field = NSTextField(frame: frame)
        field.font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        field.textColor = .white
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor(calibratedWhite: 0.58, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: fontSize, weight: weight)
            ]
        )
        field.backgroundColor = NSColor(calibratedWhite: 0.15, alpha: 1.0)
        field.isBezeled = false
        field.focusRingType = .none
        field.wantsLayer = true
        field.layer?.cornerRadius = 8
        field.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.1).cgColor
        field.layer?.borderWidth = 1.0
        return field
    }

    // MARK: - Presentation & Sniffing

    public func toggle() {
        if panel.isVisible { panel.orderOut(nil) } else { show() }
    }

    public func show() {
        currentAnchor = SutraBridge.shared.sniff()

        linkField.stringValue = ""
        fileField.stringValue = ""

        if let anchor = currentAnchor {
            let appName = anchor.app_name ?? "Desktop"
            let icon = IconResolver.resolveIcon(forApp: appName, bundleId: anchor.bundle_id, size: 18)
            appIconView.image = icon
            appTitleLabel.stringValue = appName

            var subtitle = ""
            var tooltipText = ""
            if let urlStr = anchor.url, let parsed = URL(string: urlStr), let host = parsed.host, !host.isEmpty {
                let cleanHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
                let path = parsed.path
                if path.count > 1 && path != "/" {
                    let firstSeg = path.split(separator: "/").first.map { String($0) } ?? ""
                    let concisePath = firstSeg.isEmpty ? "" : "/\(firstSeg)"
                    subtitle = "• \(cleanHost)\(concisePath)"
                } else {
                    subtitle = "• \(cleanHost)"
                }
                tooltipText = urlStr
            } else if let fp = anchor.file_path, !fp.isEmpty {
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let displayPath = fp.hasPrefix(home) ? "~" + fp.dropFirst(home.count) : fp
                let components = displayPath.split(separator: "/")
                let fileName = components.last.map { String($0) } ?? displayPath
                if let page = anchor.line_number, page > 0 {
                    subtitle = "• \(fileName) (Page \(page))"
                } else if components.count > 2 {
                    subtitle = "• \(components.suffix(2).joined(separator: "/"))"
                } else {
                    subtitle = "• \(displayPath)"
                }
                tooltipText = fp
            } else if let urlStr = anchor.url, urlStr.hasPrefix("file://") {
                let path = URL(string: urlStr)?.path ?? urlStr
                if let page = anchor.line_number, page > 0 {
                    subtitle = "• \(URL(fileURLWithPath: path).lastPathComponent) (Page \(page))"
                } else {
                    subtitle = "• \(URL(fileURLWithPath: path).lastPathComponent)"
                }
                tooltipText = path
            } else if let title = anchor.window_title, !title.isEmpty {
                subtitle = "• \(title.count > 30 ? String(title.prefix(28)) + "…" : title)"
                tooltipText = title
            } else {
                subtitle = "• Active Window"
                tooltipText = appName
            }
            contextSubtitleLabel.stringValue = subtitle
            contextSubtitleLabel.toolTip = tooltipText
            pillContainer.toolTip = tooltipText

            // Calculate label width dynamically
            let nameW = min(max(CGFloat(appName.count * 8), 45), 90)
            appTitleLabel.frame = NSRect(x: 30, y: 4, width: nameW, height: 17)
            contextSubtitleLabel.frame = NSRect(x: 34 + nameW, y: 4, width: pillContainer.bounds.width - (38 + nameW), height: 17)

            if let url = anchor.url, (url.hasPrefix("http://") || url.hasPrefix("https://")) {
                linkField.stringValue = url
                fileField.stringValue = ""
            } else if let fp = anchor.file_path, !fp.isEmpty {
                fileField.stringValue = fp
                // Populate link field with browser deep-link if file URL exists or construct file://#page=N
                if let url = anchor.url, !url.isEmpty {
                    linkField.stringValue = url
                } else if let page = anchor.line_number, page > 0 {
                    let fileUrl = URL(fileURLWithPath: fp)
                    var comp = URLComponents(url: fileUrl, resolvingAgainstBaseURL: false)
                    comp?.fragment = "page=\(page)"
                    linkField.stringValue = comp?.url?.absoluteString ?? fileUrl.absoluteString
                } else {
                    linkField.stringValue = URL(fileURLWithPath: fp).absoluteString
                }
            } else if let url = anchor.url, url.hasPrefix("file://") {
                fileField.stringValue = URL(string: url)?.path ?? url
                linkField.stringValue = url
            }
        } else {
            appIconView.image = IconResolver.resolveIcon(forApp: "Finder", size: 18)
            appTitleLabel.stringValue = "Desktop"
            contextSubtitleLabel.stringValue = "• Active Workspace"
            contextSubtitleLabel.toolTip = "Desktop Workspace"
            pillContainer.toolTip = "Desktop Workspace"
        }

        titleField.stringValue = ""
        notesField.stringValue = ""
        for field in checklistFields { field.stringValue = "" }
        for box in checklistBoxes { box.state = .off }

        selectedDueDate = nil
        currentStack = nil
        updateDateButtonTitle()
        updateStackButtonTitle()

        switchMode(type: "note")

        if let screen = NSScreen.main {
            let f = panel.frame
            // Default position: center of the left side of the screen, ~25px from left edge
            let x = screen.visibleFrame.minX + 25
            let y = screen.visibleFrame.midY - (f.height / 2)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(titleField)
    }

    public func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field == titleField else { return }
        let (_, detectedDate) = QuickCueHUD.parseNaturalLanguageDate(from: field.stringValue)
        if let date = detectedDate {
            selectedDueDate = date
            updateDateButtonTitle()
        }
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            submit()
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            panel.orderOut(nil)
            return true
        }
        return false
    }

    private func submit() {
        var t = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }

        let (clean, detectedDate) = QuickCueHUD.parseNaturalLanguageDate(from: t)
        if selectedDueDate == nil, let date = detectedDate {
            selectedDueDate = date
            t = clean
        } else if selectedDueDate != nil && !clean.isEmpty {
            t = clean
        }
        guard !t.isEmpty else { return }

        var finalNotes: String? = nil

        switch selectedCueType {
        case "checklist":
            var items: [String] = []
            for i in 0..<checklistFields.count {
                let text = checklistFields[i].stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    let mark = checklistBoxes[i].state == .on ? "[x]" : "[ ]"
                    items.append("\(mark) \(text)")
                }
            }
            if !items.isEmpty {
                finalNotes = items.joined(separator: "\n")
            }
        case "link":
            let val = linkField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !val.isEmpty { finalNotes = val }
        case "file":
            let val = fileField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !val.isEmpty { finalNotes = val }
        default:
            let n = notesField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !n.isEmpty { finalNotes = n }
        }

        var tags: [String] = []
        if let stack = currentStack, !stack.isEmpty {
            tags.append(stack)
        }

        let resolvedCueType = selectedCueType

        // Synchronize anchor with user-specified link or file overrides
        if var anchor = currentAnchor {
            if resolvedCueType == "link", let linkVal = finalNotes, !linkVal.isEmpty {
                anchor.url = linkVal
            } else if resolvedCueType == "file", let fileVal = finalNotes, !fileVal.isEmpty {
                anchor.file_path = fileVal
                if fileVal.lowercased().hasSuffix(".pdf"), anchor.line_number == nil {
                    let fileUrl = URL(fileURLWithPath: fileVal)
                    anchor.url = fileUrl.absoluteString
                }
            }
            currentAnchor = anchor
        } else if resolvedCueType == "link", let linkVal = finalNotes, !linkVal.isEmpty {
            currentAnchor = SutraAnchor(app_name: "Browser", bundle_id: nil, url: linkVal, file_path: nil, line_number: nil, window_title: linkVal)
        } else if resolvedCueType == "file", let fileVal = finalNotes, !fileVal.isEmpty {
            currentAnchor = SutraAnchor(app_name: "Finder", bundle_id: nil, url: nil, file_path: fileVal, line_number: nil, window_title: URL(fileURLWithPath: fileVal).lastPathComponent)
        }

        _ = SutraBridge.shared.capture(title: t, notes: finalNotes, cueType: resolvedCueType, dueAt: selectedDueDate, tags: tags.isEmpty ? nil : tags, anchor: currentAnchor)
        NSSound(named: "Tink")?.play()
        NotificationCenter.default.post(name: NSNotification.Name("SutraThreadsUpdated"), object: nil)
        panel.orderOut(nil)
    }

    private func loadSutraLogo(size: NSSize) -> NSImage {
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
        NSColor(calibratedRed: 0.85, green: 0.42, blue: 0.15, alpha: 1.0).setFill()
        let path = NSBezierPath(ovalIn: NSRect(origin: .zero, size: size))
        path.fill()
        fallback.unlockFocus()
        return fallback
    }
}
