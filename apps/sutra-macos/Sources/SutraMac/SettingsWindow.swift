import AppKit

public protocol SettingsDelegate: AnyObject {
    func didChangeFloatingBarPlacement(_ placement: String)
    func didChangeShortcutProfile(_ profile: String)
}

public final class SettingsWindow: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindow()

    public weak var delegate: SettingsDelegate?

    private var panel: NSPanel?
    private var placementButtons: [String: ClosureButton] = [:]
    private var profileButtons: [String: ClosureButton] = [:]
    private var featureToggleButtons: [String: ClosureButton] = [:]

    private let featureToggles: [(key: String, title: String, desc: String)] = [
        ("SutraEnableNudge", "Interruption Nudge", "Proactively prompt to leave a cue when switching from deep work to comms"),
        ("SutraEnableStalePrompt", "Stale Thread Prompts", "Context-aware prompt [Resume / Snooze 3d / Done] for cues > 24h old"),
        ("SutraEnableDecay", "Anti-Hoarding Decay", "Nightly auto-archive of waiting threads older than 7 days to Later"),
        ("SutraEnableNLPSnooze", "Natural Language Snooze", "Parse smart dates like 'in 2 hours', 'tomorrow at 9', '3d' in QuickCue"),
        ("SutraEnableTemplates", "Reusable Templates", "Enable quick checklist templates (Review, Triage, Wrap-up)")
    ]

    private override init() {
        super.init()
    }

    public func show() {
        if let p = panel {
            updateSelectionStates()
            p.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        buildWindow()
        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func close() {
        panel?.orderOut(nil)
    }

    private func buildWindow() {
        let w: CGFloat = 520
        let h: CGFloat = 740

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.delegate = self
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.backgroundColor = .clear
        p.hasShadow = true
        p.appearance = NSAppearance(named: .darkAqua)

        let rootCard = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        rootCard.wantsLayer = true
        rootCard.layer?.backgroundColor = NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.10, alpha: 0.98).cgColor
        rootCard.layer?.cornerRadius = 14
        rootCard.layer?.masksToBounds = true
        rootCard.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor
        rootCard.layer?.borderWidth = 1.0

        // 1. Header (Logo + Title + Close Button)
        let logoSize: CGFloat = 28
        let logoView = NSImageView(frame: NSRect(x: 24, y: h - 44, width: logoSize, height: logoSize))
        logoView.image = loadSutraLogo(size: NSSize(width: logoSize, height: logoSize))
        rootCard.addSubview(logoView)

        let titleLabel = NSTextField(labelWithString: "Sutra Preferences")
        titleLabel.frame = NSRect(x: 60, y: h - 42, width: 260, height: 22)
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        titleLabel.textColor = NSColor(calibratedWhite: 0.98, alpha: 1.0)
        rootCard.addSubview(titleLabel)

        let closeBtn = ClosureButton(frame: NSRect(x: w - 44, y: h - 42, width: 24, height: 24)) { [weak self] in
            self?.close()
        }
        closeBtn.isBordered = false
        closeBtn.wantsLayer = true
        closeBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1.0).cgColor
        closeBtn.layer?.cornerRadius = 12
        closeBtn.attributedTitle = NSAttributedString(string: "✕", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.85, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 11, weight: .medium)
        ])
        rootCard.addSubview(closeBtn)

        // 2. Section: Floating Bar Placement Card
        let cardW = w - 48
        let cardX: CGFloat = 24

        let card1H: CGFloat = 110
        let card1Y = h - 54 - card1H
        let placementCard = NSView(frame: NSRect(x: cardX, y: card1Y, width: cardW, height: card1H))
        placementCard.wantsLayer = true
        placementCard.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1.0).cgColor
        placementCard.layer?.cornerRadius = 10
        placementCard.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
        placementCard.layer?.borderWidth = 1.0

        let pHeader = NSTextField(labelWithString: "FLOATING BAR POSITION")
        pHeader.font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
        pHeader.textColor = NSColor(calibratedWhite: 0.75, alpha: 1.0)
        pHeader.frame = NSRect(x: 14, y: card1H - 24, width: 280, height: 16)
        placementCard.addSubview(pHeader)

        let pSub = NSTextField(labelWithString: "Choose desktop anchor to accommodate center floating HUDs and widgets.")
        pSub.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        pSub.textColor = NSColor(calibratedWhite: 0.60, alpha: 1.0)
        pSub.frame = NSRect(x: 14, y: card1H - 42, width: cardW - 28, height: 16)
        placementCard.addSubview(pSub)

        let btnH: CGFloat = 32
        let gap: CGFloat = 10
        let btnW = (cardW - 28 - gap * 2) / 3
        let pOptions = [
            ("top_left_30", "Top-Left (30pt)"),
            ("top_left_320", "Past Clock (320pt)"),
            ("top_center", "Top Center")
        ]

        placementButtons.removeAll()
        for (i, opt) in pOptions.enumerated() {
            let bx = 14 + CGFloat(i) * (btnW + gap)
            let btn = ClosureButton(frame: NSRect(x: bx, y: 16, width: btnW, height: btnH)) { [weak self] in
                UserDefaults.standard.set(opt.0, forKey: "SutraFloatingPlacement")
                self?.delegate?.didChangeFloatingBarPlacement(opt.0)
                FloatingWakeBar.shared.relayout()
                self?.updateSelectionStates()
            }
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 6
            btn.attributedTitle = NSAttributedString(string: opt.1, attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 11, weight: .regular)
            ])
            placementCard.addSubview(btn)
            placementButtons[opt.0] = btn
        }
        rootCard.addSubview(placementCard)

        // 3. Section: Global Shortcut Profile Card
        let card2H: CGFloat = 100
        let card2Y = card1Y - card2H - 12
        let shortcutCard = NSView(frame: NSRect(x: cardX, y: card2Y, width: cardW, height: card2H))
        shortcutCard.wantsLayer = true
        shortcutCard.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1.0).cgColor
        shortcutCard.layer?.cornerRadius = 10
        shortcutCard.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
        shortcutCard.layer?.borderWidth = 1.0

        let sHeader = NSTextField(labelWithString: "GLOBAL SHORTCUT PROFILE")
        sHeader.font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
        sHeader.textColor = NSColor(calibratedWhite: 0.75, alpha: 1.0)
        sHeader.frame = NSRect(x: 14, y: card2H - 24, width: 280, height: 16)
        shortcutCard.addSubview(sHeader)

        let sSub = NSTextField(labelWithString: "Switch shortcut layout to prevent conflict with frontmost system utilities.")
        sSub.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        sSub.textColor = NSColor(calibratedWhite: 0.60, alpha: 1.0)
        sSub.frame = NSRect(x: 14, y: card2H - 42, width: cardW - 28, height: 16)
        shortcutCard.addSubview(sSub)

        let sBtnW = (cardW - 28 - 12) / 2
        let sOptions = [
            ("standard", "Standard Studio\n⌥A Wake · ⌥S Sanctuary · ⌃⌥Space"),
            ("ergonomic", "Ergonomic Option\n⌥W Wake · Right-⌥ Tap · ⌥Space")
        ]

        profileButtons.removeAll()
        for (i, opt) in sOptions.enumerated() {
            let sx = 14 + CGFloat(i) * (sBtnW + 12)
            let sBtn = ClosureButton(frame: NSRect(x: sx, y: 12, width: sBtnW, height: 42)) { [weak self] in
                UserDefaults.standard.set(opt.0, forKey: "SutraShortcutProfile")
                self?.delegate?.didChangeShortcutProfile(opt.0)
                NotificationCenter.default.post(name: NSNotification.Name("SutraShortcutsChanged"), object: nil)
                self?.updateSelectionStates()
            }
            sBtn.isBordered = false
            sBtn.wantsLayer = true
            sBtn.layer?.cornerRadius = 6

            let pStyle = NSMutableParagraphStyle()
            pStyle.alignment = .center
            pStyle.lineSpacing = 2
            sBtn.attributedTitle = NSAttributedString(string: opt.1, attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 9.5, weight: .regular),
                .paragraphStyle: pStyle
            ])
            shortcutCard.addSubview(sBtn)
            profileButtons[opt.0] = sBtn
        }
        rootCard.addSubview(shortcutCard)

        // 4. Section: Feature Toggles Card (Vorssaint Modular Architecture)
        let card3H: CGFloat = 340
        let card3Y = card2Y - card3H - 12
        let toggleCard = NSView(frame: NSRect(x: cardX, y: card3Y, width: cardW, height: card3H))
        toggleCard.wantsLayer = true
        toggleCard.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1.0).cgColor
        toggleCard.layer?.cornerRadius = 10
        toggleCard.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
        toggleCard.layer?.borderWidth = 1.0

        let tHeader = NSTextField(labelWithString: "FEATURE TOGGLES & AUTOMATION")
        tHeader.font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
        tHeader.textColor = NSColor(calibratedWhite: 0.75, alpha: 1.0)
        tHeader.frame = NSRect(x: 14, y: card3H - 24, width: cardW - 28, height: 16)
        toggleCard.addSubview(tHeader)

        let tSub = NSTextField(labelWithString: "Toggle background modules. Deactivated modules halt completely to preserve CPU & RAM.")
        tSub.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        tSub.textColor = NSColor(calibratedWhite: 0.60, alpha: 1.0)
        tSub.frame = NSRect(x: 14, y: card3H - 42, width: cardW - 28, height: 16)
        toggleCard.addSubview(tSub)

        featureToggleButtons.removeAll()
        let rowH: CGFloat = 48
        for (idx, item) in featureToggles.enumerated() {
            let rowY = card3H - 52 - CGFloat(idx + 1) * (rowH + 4)
            let rowView = NSView(frame: NSRect(x: 14, y: rowY, width: cardW - 28, height: rowH))
            rowView.wantsLayer = true
            rowView.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.70).cgColor
            rowView.layer?.cornerRadius = 6
            rowView.layer?.borderWidth = 1.0
            rowView.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.04).cgColor

            let nameLbl = NSTextField(labelWithString: item.title)
            nameLbl.font = NSFont.systemFont(ofSize: 11, weight: .bold)
            nameLbl.textColor = NSColor(calibratedWhite: 0.95, alpha: 1.0)
            nameLbl.frame = NSRect(x: 10, y: rowH - 22, width: cardW - 100, height: 16)
            rowView.addSubview(nameLbl)

            let descLbl = NSTextField(labelWithString: item.desc)
            descLbl.font = NSFont.systemFont(ofSize: 9.5, weight: .regular)
            descLbl.textColor = NSColor(calibratedWhite: 0.55, alpha: 1.0)
            descLbl.frame = NSRect(x: 10, y: 5, width: cardW - 100, height: 18)
            descLbl.cell?.lineBreakMode = .byTruncatingTail
            rowView.addSubview(descLbl)

            let toggleBtn = ClosureButton(frame: NSRect(x: cardW - 28 - 62, y: (rowH - 24) / 2, width: 52, height: 24)) { [weak self] in
                guard let self = self else { return }
                let current = UserDefaults.standard.object(forKey: item.key) as? Bool ?? true
                UserDefaults.standard.set(!current, forKey: item.key)
                self.updateSelectionStates()
            }
            toggleBtn.isBordered = false
            toggleBtn.wantsLayer = true
            toggleBtn.layer?.cornerRadius = 12
            rowView.addSubview(toggleBtn)
            featureToggleButtons[item.key] = toggleBtn

            toggleCard.addSubview(rowView)
        }
        rootCard.addSubview(toggleCard)

        // 4. Action Row (Bottom)
        let actionsY: CGFloat = 20
        let actH: CGFloat = 30

        // Reset Defaults
        let resetBtn = ClosureButton(frame: NSRect(x: cardX, y: actionsY, width: 130, height: actH)) { [weak self] in
            UserDefaults.standard.set("top_left_30", forKey: "SutraFloatingPlacement")
            UserDefaults.standard.set("standard", forKey: "SutraShortcutProfile")
            for item in self?.featureToggles ?? [] {
                UserDefaults.standard.set(true, forKey: item.key)
            }
            self?.delegate?.didChangeFloatingBarPlacement("top_left_30")
            self?.delegate?.didChangeShortcutProfile("standard")
            FloatingWakeBar.shared.relayout()
            NotificationCenter.default.post(name: NSNotification.Name("SutraShortcutsChanged"), object: nil)
            self?.updateSelectionStates()
        }
        resetBtn.isBordered = false
        resetBtn.wantsLayer = true
        resetBtn.layer?.cornerRadius = 6
        resetBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1.0).cgColor
        resetBtn.attributedTitle = NSAttributedString(string: "Reset Defaults", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.80, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 11, weight: .regular)
        ])
        rootCard.addSubview(resetBtn)

        // Restart App Button
        let restartBtn = ClosureButton(frame: NSRect(x: cardX + 140, y: actionsY, width: 140, height: actH)) { [weak self] in
            self?.close()
            NotificationCenter.default.post(name: NSNotification.Name("RestartSutraApp"), object: nil)
        }
        restartBtn.isBordered = false
        restartBtn.wantsLayer = true
        restartBtn.layer?.cornerRadius = 6
        restartBtn.layer?.backgroundColor = NSColor(calibratedRed: 0.85, green: 0.40, blue: 0.18, alpha: 1.0).cgColor
        restartBtn.attributedTitle = NSAttributedString(string: "⌃⌥R Restart App", attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 11, weight: .bold)
        ])
        rootCard.addSubview(restartBtn)

        // Done Button (Right)
        let doneBtn = ClosureButton(frame: NSRect(x: w - 24 - 100, y: actionsY, width: 100, height: actH)) { [weak self] in
            self?.close()
        }
        doneBtn.isBordered = false
        doneBtn.wantsLayer = true
        doneBtn.layer?.cornerRadius = 6
        doneBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.22, alpha: 1.0).cgColor
        doneBtn.attributedTitle = NSAttributedString(string: "Done", attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
        ])
        rootCard.addSubview(doneBtn)

        p.contentView = rootCard
        self.panel = p
        updateSelectionStates()
    }

    private func updateSelectionStates() {
        let currentPlacement = UserDefaults.standard.string(forKey: "SutraFloatingPlacement") ?? "top_left_30"
        for (key, btn) in placementButtons {
            let isSel = (key == currentPlacement)
            btn.layer?.backgroundColor = isSel
                ? NSColor(calibratedRed: 0.702, green: 0.337, blue: 0.165, alpha: 0.25).cgColor
                : NSColor(calibratedWhite: 0.16, alpha: 1.0).cgColor
            btn.layer?.borderColor = isSel
                ? NSColor(calibratedRed: 0.702, green: 0.337, blue: 0.165, alpha: 0.75).cgColor
                : NSColor(calibratedWhite: 1.0, alpha: 0.10).cgColor
            btn.layer?.borderWidth = 1.0
        }

        let currentProfile = UserDefaults.standard.string(forKey: "SutraShortcutProfile") ?? "standard"
        for (key, btn) in profileButtons {
            let isSel = (key == currentProfile)
            btn.layer?.backgroundColor = isSel
                ? NSColor(calibratedRed: 0.702, green: 0.337, blue: 0.165, alpha: 0.25).cgColor
                : NSColor(calibratedWhite: 0.16, alpha: 1.0).cgColor
            btn.layer?.borderColor = isSel
                ? NSColor(calibratedRed: 0.702, green: 0.337, blue: 0.165, alpha: 0.75).cgColor
                : NSColor(calibratedWhite: 1.0, alpha: 0.10).cgColor
            btn.layer?.borderWidth = 1.0
        }

        for item in featureToggles {
            let isEnabled = UserDefaults.standard.object(forKey: item.key) as? Bool ?? true
            if let btn = featureToggleButtons[item.key] {
                btn.layer?.backgroundColor = isEnabled
                    ? NSColor(calibratedRed: 0.702, green: 0.337, blue: 0.165, alpha: 1.0).cgColor
                    : NSColor(calibratedWhite: 0.20, alpha: 1.0).cgColor
                btn.layer?.borderColor = isEnabled
                    ? NSColor(calibratedRed: 0.702, green: 0.337, blue: 0.165, alpha: 0.90).cgColor
                    : NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
                btn.layer?.borderWidth = 1.0
                btn.attributedTitle = NSAttributedString(string: isEnabled ? "ON" : "OFF", attributes: [
                    .foregroundColor: isEnabled ? NSColor.white : NSColor(calibratedWhite: 0.65, alpha: 1.0),
                    .font: NSFont.systemFont(ofSize: 10, weight: .bold)
                ])
            }
        }
    }

    public func windowWillClose(_ notification: Notification) {
        panel = nil
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
        NSColor(calibratedWhite: 0.95, alpha: 1.0).setFill()
        let path = NSBezierPath(ovalIn: NSRect(origin: .zero, size: size))
        path.fill()
        fallback.unlockFocus()
        return fallback
    }
}
