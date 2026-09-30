import AppKit

public final class KeyFocusPanel: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }
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

    public override init() {
        super.init()
        setupHUD()
    }

    private func setupHUD() {
        let w: CGFloat = 504
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
        card.layer?.backgroundColor = NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.12, alpha: 1.0).cgColor
        card.layer?.cornerRadius = 16
        card.layer?.masksToBounds = true
        card.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.14).cgColor
        card.layer?.borderWidth = 1.0

        // ==========================================
        // 1. HEADER (y: h - 46 ... h)
        // ==========================================
        let headerY: CGFloat = h - 44

        // Sutra Silk Möbius Mark (Bigger 32x32)
        let logoImg = NSImageView(frame: NSRect(x: 18, y: headerY + 2, width: 32, height: 32))
        logoImg.image = loadSutraLogo(size: NSSize(width: 32, height: 32))
        card.addSubview(logoImg)

        // Sutra Cue Brand Typography
        let headerLabel = NSTextField(labelWithString: "Sutra Cue")
        headerLabel.frame = NSRect(x: 56, y: headerY + 8, width: 92, height: 20)
        headerLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        headerLabel.textColor = NSColor(calibratedRed: 0.85, green: 0.42, blue: 0.15, alpha: 1.0)
        card.addSubview(headerLabel)

        // Dynamic Active App Identity Pill (Center-Right)
        let pillW: CGFloat = w - 195
        pillContainer = NSView(frame: NSRect(x: 152, y: headerY + 6, width: pillW, height: 26))
        pillContainer.wantsLayer = true
        pillContainer.layer?.backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 1.0).cgColor
        pillContainer.layer?.cornerRadius = 13
        pillContainer.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor
        pillContainer.layer?.borderWidth = 1.0

        // Active App Icon
        appIconView = NSImageView(frame: NSRect(x: 6, y: 4, width: 18, height: 18))
        pillContainer.addSubview(appIconView)

        // App Name Label
        appTitleLabel = NSTextField(labelWithString: "Desktop")
        appTitleLabel.frame = NSRect(x: 28, y: 4, width: 90, height: 17)
        appTitleLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .bold)
        appTitleLabel.textColor = NSColor(calibratedWhite: 0.95, alpha: 1.0)
        appTitleLabel.lineBreakMode = .byTruncatingTail
        pillContainer.addSubview(appTitleLabel)

        // Context Subtitle (URL Host or Document Title)
        contextSubtitleLabel = NSTextField(labelWithString: "• Active Workspace")
        contextSubtitleLabel.frame = NSRect(x: 120, y: 4, width: pillW - 126, height: 17)
        contextSubtitleLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        contextSubtitleLabel.textColor = NSColor(calibratedWhite: 0.65, alpha: 1.0)
        contextSubtitleLabel.lineBreakMode = .byTruncatingTail
        pillContainer.addSubview(contextSubtitleLabel)

        card.addSubview(pillContainer)

        // Dismiss Button [✕]
        let closeBtn = ClosureButton(frame: NSRect(x: w - 34, y: headerY + 7, width: 22, height: 22)) { [weak self] in
            self?.panel.orderOut(nil)
        }
        closeBtn.title = "✕"
        closeBtn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        closeBtn.isBordered = false
        closeBtn.wantsLayer = true
        closeBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.2, alpha: 0.6).cgColor
        closeBtn.layer?.cornerRadius = 11
        card.addSubview(closeBtn)

        // ==========================================
        // 2. PRIMARY ACTION: IMMEDIATE NEXT ACTION
        // ==========================================
        let contentW: CGFloat = w - 44
        let contentX: CGFloat = (w - contentW) / 2

        let actionLabel = NSTextField(labelWithString: "Immediate Next Action")
        actionLabel.frame = NSRect(x: contentX, y: h - 76, width: contentW, height: 16)
        actionLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        actionLabel.textColor = NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.25, alpha: 1.0)
        card.addSubview(actionLabel)

        titleField = createInputField(
            frame: NSRect(x: contentX, y: h - 116, width: contentW, height: 38),
            placeholder: "",
            fontSize: 13,
            weight: .medium
        )
        titleField.layer?.borderColor = NSColor(calibratedRed: 0.85, green: 0.42, blue: 0.15, alpha: 0.4).cgColor
        titleField.layer?.backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 0.85).cgColor
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
        // 4. BOTTOM UTILITY & ACTION BAR (y: 12 ... 38)
        // ==========================================
        let tabsContainer = NSView(frame: NSRect(x: contentX, y: 11, width: 236, height: 26))

        let tabs = [
            ("note", "📝 Note"),
            ("checklist", "✅ Checklist"),
            ("link", "🔗 Link"),
            ("file", "📁 File")
        ]
        var tabX: CGFloat = 0
        for (key, title) in tabs {
            let btnWidth: CGFloat = key == "checklist" ? 72 : (key == "note" ? 52 : 48)
            let btn = NSButton(frame: NSRect(x: tabX, y: 1, width: btnWidth, height: 24))
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 12
            btn.target = self
            btn.action = #selector(onTabClicked(_:))
            btn.identifier = NSUserInterfaceItemIdentifier(key)
            btn.title = title
            tabButtons[key] = btn
            tabsContainer.addSubview(btn)
            tabX += btnWidth + 4
        }
        updateTabStyles()
        card.addSubview(tabsContainer)

        // Date Scheduler Pill Button
        datePickerBtn = NSButton(frame: NSRect(x: contentX + 242, y: 11, width: 90, height: 26))
        datePickerBtn.title = "Schedule"
        datePickerBtn.font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        datePickerBtn.isBordered = false
        datePickerBtn.wantsLayer = true
        datePickerBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1.0).cgColor
        datePickerBtn.layer?.cornerRadius = 13
        datePickerBtn.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor
        datePickerBtn.layer?.borderWidth = 1.0
        datePickerBtn.target = self
        datePickerBtn.action = #selector(onDatePickerClicked(_:))
        card.addSubview(datePickerBtn)

        // Esc Button (Compact)
        let escBtn = ClosureButton(frame: NSRect(x: w - 146, y: 11, width: 44, height: 26)) { [weak self] in
            self?.panel.orderOut(nil)
        }
        escBtn.title = "Esc"
        escBtn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        escBtn.isBordered = false
        escBtn.wantsLayer = true
        escBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1.0).cgColor
        escBtn.layer?.cornerRadius = 13
        escBtn.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor
        escBtn.layer?.borderWidth = 1.0
        card.addSubview(escBtn)

        // Submit Button [Leave Thread ↩]
        let submitBtn = ClosureButton(frame: NSRect(x: w - 96, y: 11, width: 86, height: 26)) { [weak self] in
            self?.submit()
        }
        submitBtn.title = "Leave Thread ↩"
        submitBtn.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        submitBtn.isBordered = false
        submitBtn.wantsLayer = true
        submitBtn.layer?.backgroundColor = NSColor(calibratedRed: 0.85, green: 0.42, blue: 0.15, alpha: 1.0).cgColor
        submitBtn.layer?.cornerRadius = 13
        card.addSubview(submitBtn)

        panel.contentView?.addSubview(card)
    }

    // MARK: - Middle Deck Setup

    private func setupNoteView(width: CGFloat) {
        noteView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 100))

        let heading = NSTextField(labelWithString: "Context / Reason")
        heading.frame = NSRect(x: 0, y: 80, width: width, height: 16)
        heading.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        heading.textColor = NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.25, alpha: 1.0)
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

        let heading = NSTextField(labelWithString: "Checklist")
        heading.frame = NSRect(x: 0, y: 80, width: width, height: 16)
        heading.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        heading.textColor = NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.25, alpha: 1.0)
        checklistView.addSubview(heading)

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
        label.textColor = NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.25, alpha: 1.0)
        linkView.addSubview(label)

        linkField = createInputField(
            frame: NSRect(x: 0, y: 22, width: width, height: 48),
            placeholder: "",
            fontSize: 12,
            weight: .regular
        )
        linkField.delegate = self
        linkView.addSubview(linkField)
    }

    private func setupFileView(width: CGFloat) {
        fileView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 100))

        let label = NSTextField(labelWithString: "Attached File / Directory")
        label.frame = NSRect(x: 0, y: 80, width: width, height: 16)
        label.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        label.textColor = NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.25, alpha: 1.0)
        fileView.addSubview(label)

        fileField = createInputField(
            frame: NSRect(x: 0, y: 22, width: width - 92, height: 48),
            placeholder: "",
            fontSize: 11.5,
            weight: .regular
        )
        fileField.delegate = self
        fileView.addSubview(fileField)

        let browseBtn = ClosureButton(frame: NSRect(x: width - 84, y: 22, width: 84, height: 48)) { [weak self] in
            self?.onBrowseFile()
        }
        browseBtn.title = "Browse..."
        browseBtn.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        browseBtn.isBordered = false
        browseBtn.wantsLayer = true
        browseBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.22, alpha: 0.9).cgColor
        browseBtn.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor
        browseBtn.layer?.borderWidth = 1.0
        browseBtn.layer?.cornerRadius = 8
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
            if linkField.stringValue.isEmpty, let url = currentAnchor?.url,
               (url.hasPrefix("http://") || url.hasPrefix("https://")) {
                linkField.stringValue = url
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
                btn.layer?.backgroundColor = NSColor(calibratedRed: 0.85, green: 0.42, blue: 0.15, alpha: 1.0).cgColor
                btn.layer?.borderColor = NSColor(calibratedRed: 0.98, green: 0.55, blue: 0.25, alpha: 1.0).cgColor
                btn.layer?.borderWidth = 1.0
                btn.attributedTitle = NSAttributedString(string: btn.title, attributes: [
                    .foregroundColor: NSColor.white,
                    .font: NSFont.systemFont(ofSize: 10.5, weight: .bold)
                ])
            } else {
                btn.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1.0).cgColor
                btn.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor
                btn.layer?.borderWidth = 1.0
                btn.attributedTitle = NSAttributedString(string: btn.title, attributes: [
                    .foregroundColor: NSColor(calibratedWhite: 0.7, alpha: 1.0),
                    .font: NSFont.systemFont(ofSize: 10.5, weight: .medium)
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

    // MARK: - Smart Date Scheduling

    @objc private func onDatePickerClicked(_ sender: NSButton) {
        let menu = NSMenu(title: "Schedule")

        let todayItem = NSMenuItem(title: "Today", action: #selector(onSelectDateToday), keyEquivalent: "")
        todayItem.target = self
        menu.addItem(todayItem)

        let customItem = NSMenuItem(title: "Pick Date...", action: #selector(onSelectCustomDate), keyEquivalent: "")
        customItem.target = self
        menu.addItem(customItem)

        if selectedDueDate != nil {
            menu.addItem(NSMenuItem.separator())
            let clearItem = NSMenuItem(title: "Clear Date", action: #selector(onClearDate), keyEquivalent: "")
            clearItem.target = self
            menu.addItem(clearItem)
        }

        let location = NSPoint(x: 0, y: sender.bounds.height + 4)
        menu.popUp(positioning: nil, at: location, in: sender)
    }

    @objc private func onSelectDateToday() {
        selectedDueDate = Calendar.current.startOfDay(for: Date())
        updateDateButtonTitle()
    }

    @objc private func onSelectCustomDate() {
        let alert = NSAlert()
        alert.messageText = "Schedule Thread"
        alert.informativeText = "Select the target date for this thread:"
        let picker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 140, height: 26))
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .yearMonthDay
        picker.dateValue = selectedDueDate ?? Date()
        alert.accessoryView = picker
        alert.addButton(withTitle: "Set Date")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            selectedDueDate = Calendar.current.startOfDay(for: picker.dateValue)
            updateDateButtonTitle()
        }
    }

    @objc private func onClearDate() {
        selectedDueDate = nil
        updateDateButtonTitle()
    }

    private func updateDateButtonTitle() {
        guard let date = selectedDueDate else {
            datePickerBtn.title = "Schedule"
            datePickerBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1.0).cgColor
            datePickerBtn.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor
            return
        }
        let cal = Calendar.current
        let title: String
        if cal.isDateInToday(date) {
            title = "Today"
        } else {
            let df = DateFormatter()
            df.dateFormat = "MMM d"
            title = df.string(from: date)
        }
        datePickerBtn.title = title
        datePickerBtn.layer?.backgroundColor = NSColor(calibratedRed: 0.85, green: 0.42, blue: 0.15, alpha: 0.25).cgColor
        datePickerBtn.layer?.borderColor = NSColor(calibratedRed: 0.85, green: 0.42, blue: 0.15, alpha: 0.8).cgColor
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
            if let urlStr = anchor.url, let host = URL(string: urlStr)?.host, !host.isEmpty {
                subtitle = "• \(host)"
            } else if let urlStr = anchor.url, urlStr.hasPrefix("file://") {
                let name = URL(string: urlStr)?.lastPathComponent ?? "Document"
                subtitle = "• \(name)"
            } else if let fp = anchor.file_path, !fp.isEmpty {
                let name = URL(fileURLWithPath: fp).lastPathComponent
                subtitle = "• \(name)"
            } else if let title = anchor.window_title, !title.isEmpty {
                subtitle = "• \(title.count > 25 ? String(title.prefix(22)) + "..." : title)"
            } else {
                subtitle = "• Active Window"
            }
            contextSubtitleLabel.stringValue = subtitle

            // Calculate label width dynamically
            let nameW = min(max(CGFloat(appName.count * 8), 60), 120)
            appTitleLabel.frame = NSRect(x: 28, y: 4, width: nameW, height: 17)
            contextSubtitleLabel.frame = NSRect(x: 32 + nameW, y: 4, width: pillContainer.bounds.width - (36 + nameW), height: 17)

            if let url = anchor.url, (url.hasPrefix("http://") || url.hasPrefix("https://")) {
                linkField.stringValue = url
            }
            if let fp = anchor.file_path, !fp.isEmpty {
                fileField.stringValue = fp
            } else if let url = anchor.url, url.hasPrefix("file://") {
                fileField.stringValue = URL(string: url)?.path ?? url
            }
        } else {
            appIconView.image = IconResolver.resolveIcon(forApp: "Finder", size: 18)
            appTitleLabel.stringValue = "Desktop"
            contextSubtitleLabel.stringValue = "• Active Workspace"
        }

        titleField.stringValue = ""
        notesField.stringValue = ""
        for field in checklistFields { field.stringValue = "" }
        for box in checklistBoxes { box.state = .off }

        selectedDueDate = nil
        updateDateButtonTitle()

        switchMode(type: "note")

        if let screen = NSScreen.main {
            let f = panel.frame
            let x = screen.visibleFrame.midX - (f.width / 2)
            let y = screen.visibleFrame.maxY - f.height - 100
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(titleField)
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
        let t = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
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
            let url = linkField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !url.isEmpty { finalNotes = url }
        case "file":
            let path = fileField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty { finalNotes = path }
        default:
            let n = notesField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !n.isEmpty { finalNotes = n }
        }

        _ = SutraBridge.shared.capture(title: t, notes: finalNotes, cueType: selectedCueType, dueAt: selectedDueDate)
        NSSound(named: "Tink")?.play()
        NotificationCenter.default.post(name: NSNotification.Name("SutraThreadsUpdated"), object: nil)
        panel.orderOut(nil)
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
        NSColor(calibratedRed: 0.85, green: 0.42, blue: 0.15, alpha: 1.0).setFill()
        let path = NSBezierPath(ovalIn: NSRect(origin: .zero, size: size))
        path.fill()
        fallback.unlockFocus()
        return fallback
    }
}
