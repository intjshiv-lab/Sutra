import AppKit

public final class ActivationWindow {
    public static let shared = ActivationWindow()

    private var panel: NSPanel?
    private var onActivationSuccess: (() -> Void)?
    private var emailField: NSTextField?
    private var codeField: NSTextField?
    private var statusLabel: NSTextField?
    private var onlineSpinner: NSProgressIndicator?

    private init() {}

    public func show(completion: @escaping () -> Void) {
        self.onActivationSuccess = completion

        if let existing = panel {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let w: CGFloat = 500
        let h: CGFloat = 430

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.backgroundColor = .clear
        p.hasShadow = true
        p.appearance = NSAppearance(named: .darkAqua)

        let card = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.08, alpha: 0.98).cgColor
        card.layer?.cornerRadius = 16
        card.layer?.masksToBounds = true
        card.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor
        card.layer?.borderWidth = 1.0

        // 1. Terracotta Header Label
        let subLabel = NSTextField(labelWithString: "SUTRA SOVEREIGN LICENSE")
        subLabel.frame = NSRect(x: 28, y: h - 40, width: w - 56, height: 16)
        subLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        subLabel.textColor = NSColor(calibratedRed: 0.85, green: 0.42, blue: 0.18, alpha: 1.0)
        card.addSubview(subLabel)

        // 2. Title
        let titleLabel = NSTextField(labelWithString: "Device Activation Gate")
        titleLabel.frame = NSRect(x: 28, y: h - 70, width: w - 56, height: 26)
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .white
        card.addSubview(titleLabel)

        // 3. Subtitle / Explanatory text
        let desc = NSTextField(wrappingLabelWithString: "Sutra is cryptographically bound to your hardware. Whitelist your registered email via Cloudflare, or enter your offline unlock code.")
        desc.frame = NSRect(x: 28, y: h - 120, width: w - 56, height: 38)
        desc.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        desc.textColor = NSColor(calibratedWhite: 0.70, alpha: 1.0)
        card.addSubview(desc)

        // 4. Device ID Display Box
        let idBox = NSView(frame: NSRect(x: 28, y: h - 168, width: w - 56, height: 36))
        idBox.wantsLayer = true
        idBox.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.9).cgColor
        idBox.layer?.cornerRadius = 8
        idBox.layer?.borderWidth = 1.0
        idBox.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.10).cgColor

        let devID = LicenseManager.shared.getDeviceID()
        let idLabel = NSTextField(labelWithString: "Device ID:  \(devID)")
        idLabel.frame = NSRect(x: 12, y: 8, width: 280, height: 20)
        idLabel.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .medium)
        idLabel.textColor = NSColor(calibratedWhite: 0.95, alpha: 1.0)
        idBox.addSubview(idLabel)

        let copyBtn = NSButton(frame: NSRect(x: idBox.bounds.width - 95, y: 4, width: 85, height: 28))
        copyBtn.title = "Copy ID"
        copyBtn.bezelStyle = .inline
        copyBtn.isBordered = false
        copyBtn.wantsLayer = true
        copyBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.20, alpha: 1.0).cgColor
        copyBtn.layer?.cornerRadius = 5
        copyBtn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        copyBtn.contentTintColor = .white
        copyBtn.target = self
        copyBtn.action = #selector(copyDeviceIDClicked(_:))
        idBox.addSubview(copyBtn)

        card.addSubview(idBox)

        // 5. Method 1: Email for Online Cloudflare Activation
        let emailLbl = NSTextField(labelWithString: "Method A — Online Cloudflare Activation:")
        emailLbl.frame = NSRect(x: 28, y: h - 204, width: w - 56, height: 16)
        emailLbl.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        emailLbl.textColor = NSColor(calibratedWhite: 0.85, alpha: 1.0)
        card.addSubview(emailLbl)

        let emailTf = NSTextField(frame: NSRect(x: 28, y: h - 240, width: w - 190, height: 32))
        emailTf.font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
        emailTf.placeholderString = "Registered buyer email"
        emailTf.textColor = .white
        emailTf.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.9)
        emailTf.isBezeled = false
        emailTf.wantsLayer = true
        emailTf.layer?.cornerRadius = 6
        emailTf.layer?.borderWidth = 1.0
        emailTf.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor
        card.addSubview(emailTf)
        self.emailField = emailTf

        let onlineBtn = NSButton(frame: NSRect(x: w - 150, y: h - 240, width: 122, height: 32))
        onlineBtn.title = "Verify Online →"
        onlineBtn.bezelStyle = .regularSquare
        onlineBtn.isBordered = false
        onlineBtn.wantsLayer = true
        onlineBtn.layer?.backgroundColor = NSColor(calibratedRed: 0.85, green: 0.42, blue: 0.18, alpha: 1.0).cgColor
        onlineBtn.layer?.cornerRadius = 6
        onlineBtn.font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        onlineBtn.contentTintColor = .white
        onlineBtn.target = self
        onlineBtn.action = #selector(verifyOnlineClicked(_:))
        card.addSubview(onlineBtn)

        // 6. Method 2: Offline Code Entry
        let codeLbl = NSTextField(labelWithString: "Method B — Offline Hardware Unlock Code:")
        codeLbl.frame = NSRect(x: 28, y: h - 286, width: w - 56, height: 16)
        codeLbl.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        codeLbl.textColor = NSColor(calibratedWhite: 0.85, alpha: 1.0)
        card.addSubview(codeLbl)

        let codeTf = NSTextField(frame: NSRect(x: 28, y: h - 322, width: w - 190, height: 32))
        codeTf.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
        codeTf.placeholderString = "8-digit code (e.g. 228A-F11C)"
        codeTf.textColor = .white
        codeTf.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.9)
        codeTf.isBezeled = false
        codeTf.wantsLayer = true
        codeTf.layer?.cornerRadius = 6
        codeTf.layer?.borderWidth = 1.0
        codeTf.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor
        card.addSubview(codeTf)
        self.codeField = codeTf

        let offlineBtn = NSButton(frame: NSRect(x: w - 150, y: h - 322, width: 122, height: 32))
        offlineBtn.title = "Activate Offline"
        offlineBtn.bezelStyle = .regularSquare
        offlineBtn.isBordered = false
        offlineBtn.wantsLayer = true
        offlineBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.22, alpha: 1.0).cgColor
        offlineBtn.layer?.cornerRadius = 6
        offlineBtn.font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        offlineBtn.contentTintColor = .white
        offlineBtn.target = self
        offlineBtn.action = #selector(activateOfflineClicked(_:))
        card.addSubview(offlineBtn)

        // 7. Status Feedback Label & Spinner
        let status = NSTextField(labelWithString: "")
        status.frame = NSRect(x: 28, y: h - 365, width: w - 56, height: 18)
        status.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        status.textColor = NSColor(calibratedRed: 0.95, green: 0.35, blue: 0.35, alpha: 1.0)
        card.addSubview(status)
        self.statusLabel = status

        // 8. Quit Button
        let quitBtn = NSButton(frame: NSRect(x: 28, y: 20, width: 80, height: 30))
        quitBtn.title = "Quit"
        quitBtn.bezelStyle = .regularSquare
        quitBtn.isBordered = false
        quitBtn.wantsLayer = true
        quitBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1.0).cgColor
        quitBtn.layer?.cornerRadius = 6
        quitBtn.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        quitBtn.contentTintColor = NSColor(calibratedWhite: 0.75, alpha: 1.0)
        quitBtn.target = self
        quitBtn.action = #selector(quitAppClicked)
        card.addSubview(quitBtn)

        p.contentView = card
        p.center()
        self.panel = p

        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func copyDeviceIDClicked(_ sender: NSButton) {
        let devID = LicenseManager.shared.getDeviceID()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(devID, forType: .string)
        sender.title = "Copied ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            sender.title = "Copy ID"
        }
    }

    @objc private func quitAppClicked() {
        NSApp.terminate(nil)
    }

    @objc private func verifyOnlineClicked(_ sender: NSButton) {
        guard let email = emailField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty else {
            statusLabel?.textColor = NSColor(calibratedRed: 0.95, green: 0.35, blue: 0.35, alpha: 1.0)
            statusLabel?.stringValue = "Please enter your registered buyer email."
            shakeWindow()
            return
        }

        sender.isEnabled = false
        sender.title = "Verifying..."
        statusLabel?.textColor = NSColor(calibratedWhite: 0.75, alpha: 1.0)
        statusLabel?.stringValue = "Connecting to Cloudflare Licensing Gateway..."

        LicenseManager.shared.activateOnline(email: email) { [weak self] success, message in
            DispatchQueue.main.async {
                sender.isEnabled = true
                sender.title = "Verify Online →"
                if success {
                    self?.handleActivationSuccess()
                } else {
                    self?.statusLabel?.textColor = NSColor(calibratedRed: 0.95, green: 0.35, blue: 0.35, alpha: 1.0)
                    self?.statusLabel?.stringValue = message
                    self?.shakeWindow()
                }
            }
        }
    }

    @objc private func activateOfflineClicked(_ sender: NSButton) {
        guard let code = codeField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty else {
            statusLabel?.textColor = NSColor(calibratedRed: 0.95, green: 0.35, blue: 0.35, alpha: 1.0)
            statusLabel?.stringValue = "Please enter your 8-digit unlock code."
            shakeWindow()
            return
        }

        if LicenseManager.shared.activate(with: code) {
            handleActivationSuccess()
        } else {
            statusLabel?.textColor = NSColor(calibratedRed: 0.95, green: 0.35, blue: 0.35, alpha: 1.0)
            statusLabel?.stringValue = "✗ Invalid unlock code for this Device ID."
            shakeWindow()
        }
    }

    private func handleActivationSuccess() {
        statusLabel?.textColor = NSColor(calibratedRed: 0.25, green: 0.85, blue: 0.45, alpha: 1.0)
        statusLabel?.stringValue = "✓ Device verified and activated permanently!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel = nil
            self?.onActivationSuccess?()
        }
    }

    private func shakeWindow() {
        guard let p = panel else { return }
        let origin = p.frame.origin
        let anim = CAKeyframeAnimation(keyPath: "origin")
        anim.duration = 0.28
        anim.values = [
            NSValue(point: NSPoint(x: origin.x - 10, y: origin.y)),
            NSValue(point: NSPoint(x: origin.x + 10, y: origin.y)),
            NSValue(point: NSPoint(x: origin.x - 7, y: origin.y)),
            NSValue(point: NSPoint(x: origin.x + 7, y: origin.y)),
            NSValue(point: NSPoint(x: origin.x, y: origin.y))
        ]
        p.animations = ["origin": anim]
        p.animator().setFrameOrigin(origin)
    }
}
