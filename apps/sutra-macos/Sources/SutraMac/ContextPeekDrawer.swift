import AppKit
import WebKit
import PDFKit

public final class ContextPeekDrawer: NSPanel, WKNavigationDelegate {
    public static let shared = ContextPeekDrawer()

    private var activeThread: SutraThread?
    public var activeThreadId: String? { activeThread?.id }

    private var containerView: NSView!
    private var headerView: HoverTrackingView!
    private var logoView: NSImageView!
    private var titleLabel: NSTextField!
    private var contentContainer: NSView!

    // Header Controls
    private var pinBtn: ClosureButton?
    private var openBtn: ClosureButton?
    private var closeBtn: ClosureButton?
    private var pinToastLabel: NSTextField?
    private var pinToastTimer: Timer?
    private var isHeaderHovered: Bool = false

    // Ephemeral preview views (Allocated strictly on demand, nil-ed on dismiss)
    private var webView: WKWebView?
    private var pdfView: PDFView?
    private var textView: NSTextView?
    private var textScrollView: NSScrollView?

    // Loading & Fallback Infrastructure
    private var loadingSpinner: NSProgressIndicator?
    private var loadingLabel: NSTextField?
    private var loadTimeoutTimer: Timer?

    private override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(
            contentRect: NSRect(x: 200, y: 200, width: 380, height: 480),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        appearance = NSAppearance(named: .darkAqua)

        buildUI()
    }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            dismiss()
            return
        }
        if event.keyCode == 36 { // Enter / Return: Resume
            if let thread = activeThread {
                _ = SutraBridge.shared.resume(threadId: thread.id)
                NSSound(named: "Glass")?.play()
                dismiss()
            }
            return
        }
        if event.charactersIgnoringModifiers?.lowercased() == "p" { // P: Pin to PiP
            togglePin()
            return
        }
        super.keyDown(with: event)
    }

    private func buildUI() {
        containerView = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 480))
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 14
        containerView.layer?.masksToBounds = true
        containerView.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.98).cgColor
        containerView.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.16).cgColor
        containerView.layer?.borderWidth = 1.0

        // 1. Header with Mouse Hover Tracking (y: 480 - 40 ... 480)
        let trackingHeader = HoverTrackingView(frame: NSRect(x: 0, y: 440, width: 380, height: 40))
        trackingHeader.wantsLayer = true
        trackingHeader.layer?.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1.0).cgColor
        trackingHeader.onMouseEnter = { [weak self] in
            self?.handleHeaderHover(entered: true)
        }
        trackingHeader.onMouseExit = { [weak self] in
            self?.handleHeaderHover(entered: false)
        }
        headerView = trackingHeader

        // Sutra Infinity Logo (left-aligned)
        logoView = NSImageView(frame: NSRect(x: 14, y: 10, width: 20, height: 20))
        logoView.image = SanctuaryPopover.loadSutraLogo(size: NSSize(width: 20, height: 20))
        headerView.addSubview(logoView)

        // Sentence-case Title: "Peek" in pure white
        titleLabel = NSTextField(labelWithString: "Peek")
        titleLabel.frame = NSRect(x: 40, y: 11, width: 140, height: 18)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = .white
        headerView.addSubview(titleLabel)

        // Ephemeral Pin Toast Pill ("PINNED" / "UNPINNED")
        let toast = NSTextField(labelWithString: "PINNED")
        toast.frame = NSRect(x: 196, y: 10, width: 78, height: 20)
        toast.font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
        toast.textColor = .white
        toast.alignment = .center
        toast.isBezeled = false
        toast.drawsBackground = true
        toast.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.16)
        toast.wantsLayer = true
        toast.layer?.cornerRadius = 10
        toast.layer?.masksToBounds = true
        toast.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.30).cgColor
        toast.layer?.borderWidth = 1.0
        toast.alphaValue = 0.0
        toast.isHidden = true
        headerView.addSubview(toast)
        self.pinToastLabel = toast

        // Floating Borderless White Pin Button (Zero Shadow, Zero Circle, Hover Gated)
        let pin = ClosureButton(frame: NSRect(x: 284, y: 9, width: 22, height: 22)) { [weak self] in
            self?.togglePin()
        }
        pin.isBordered = false
        pin.wantsLayer = true
        pin.shadow = nil
        pin.layer?.shadowOpacity = 0.0
        pin.layer?.backgroundColor = NSColor.clear.cgColor
        pin.layer?.borderColor = NSColor.clear.cgColor
        pin.layer?.borderWidth = 0
        pin.toolTip = "Pin to Dynamic Island Companion (P)"
        pin.alphaValue = 0.0
        headerView.addSubview(pin)
        self.pinBtn = pin

        // Open in Default Browser/App Button (Sleek Borderless Arrow)
        let open = ClosureButton(frame: NSRect(x: 314, y: 9, width: 22, height: 22)) { [weak self] in
            guard let self = self, let thread = self.activeThread else { return }
            self.openCurrentThreadExternal(thread)
        }
        open.isBordered = false
        open.wantsLayer = true
        open.shadow = nil
        open.layer?.shadowOpacity = 0.0
        open.layer?.backgroundColor = NSColor.clear.cgColor
        open.layer?.borderColor = NSColor.clear.cgColor
        open.layer?.borderWidth = 0
        open.toolTip = "Open in Default Browser"
        if let sym = NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: "Open") {
            let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            open.image = sym.withSymbolConfiguration(cfg)
            open.contentTintColor = NSColor(calibratedWhite: 0.90, alpha: 1.0)
            open.imagePosition = .imageOnly
        }
        headerView.addSubview(open)
        self.openBtn = open

        // Close Button
        let close = ClosureButton(frame: NSRect(x: 344, y: 9, width: 22, height: 22)) { [weak self] in
            self?.dismiss()
        }
        close.isBordered = false
        close.wantsLayer = true
        close.layer?.cornerRadius = 11
        close.layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1.0).cgColor
        close.attributedTitle = NSAttributedString(string: "✕", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.85, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 10, weight: .bold)
        ])
        headerView.addSubview(close)
        self.closeBtn = close

        containerView.addSubview(headerView)

        // 2. Content Container (y: 0 ... 440)
        contentContainer = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 440))
        containerView.addSubview(contentContainer)

        contentView = containerView
    }

    private func isCurrentThreadPinned() -> Bool {
        guard let thread = activeThread else { return false }
        return AmbientPiPWindow.shared.isVisible && AmbientPiPWindow.shared.activeThreadId == thread.id
    }

    private func togglePin() {
        guard let thread = activeThread else { return }
        let currentlyPinned = isCurrentThreadPinned()
        if currentlyPinned {
            AmbientPiPWindow.shared.dismiss()
            showPinToast(message: "UNPINNED")
        } else {
            AmbientPiPWindow.shared.pin(thread: thread)
            NSSound(named: "Tink")?.play()
            showPinToast(message: "PINNED")
        }
        applyPinBounceAnimation(to: pinBtn)
        updatePinAppearance(animated: true)
    }

    private func handleHeaderHover(entered: Bool) {
        isHeaderHovered = entered
        updatePinAppearance(animated: true)
    }

    private func updatePinAppearance(animated: Bool = false) {
        guard let pinBtn = pinBtn else { return }
        let isPinned = isCurrentThreadPinned()
        let symbolName = isPinned ? "pin.fill" : "pin"

        if let sym = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Pin") {
            let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            pinBtn.image = sym.withSymbolConfiguration(cfg)
        }
        pinBtn.contentTintColor = .white
        pinBtn.imagePosition = .imageOnly
        pinBtn.shadow = nil
        pinBtn.layer?.shadowOpacity = 0.0
        pinBtn.layer?.backgroundColor = NSColor.clear.cgColor
        pinBtn.layer?.borderColor = NSColor.clear.cgColor
        pinBtn.layer?.borderWidth = 0

        // Gated Visibility: permanently visible (1.0) when pinned; hover-only (0.85 vs 0.0) when unpinned
        let targetAlpha: CGFloat = isPinned ? 1.0 : (isHeaderHovered ? 0.85 : 0.0)

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                pinBtn.animator().alphaValue = targetAlpha
            }
        } else {
            pinBtn.alphaValue = targetAlpha
        }
    }

    private func showPinToast(message: String) {
        pinToastLabel?.stringValue = message
        pinToastLabel?.isHidden = false
        pinToastLabel?.alphaValue = 0.0

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.pinToastLabel?.animator().alphaValue = 1.0
        }

        pinToastTimer?.invalidate()
        pinToastTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
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

    private func applyPinBounceAnimation(to view: NSView?) {
        guard let layer = view?.layer else { return }
        let bounce = CAKeyframeAnimation(keyPath: "transform.scale")
        bounce.values = [1.0, 1.25, 0.95, 1.0]
        bounce.keyTimes = [0, 0.35, 0.7, 1.0]
        bounce.duration = 0.26
        bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(bounce, forKey: "pinBounce")
    }

    private func openCurrentThreadExternal(_ thread: SutraThread) {
        if let urlStr = thread.anchor?.url, let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        } else if let filePath = thread.anchor?.file_path {
            NSWorkspace.shared.open(URL(fileURLWithPath: filePath))
        } else {
            _ = SutraBridge.shared.resume(threadId: thread.id)
        }
    }

    // MARK: - Presentation & Strict Left-Flank Docking

    public func show(for thread: SutraThread) {
        self.activeThread = thread
        teardownPreviews()

        // Ensure Sutra Sanctuary is visible as the primary spatial anchor
        if !SanctuaryPopover.shared.isVisible {
            SanctuaryPopover.shared.present()
        }

        guard let sanctuaryPanel = SanctuaryPopover.shared.window else { return }
        reposition(relativeTo: sanctuaryPanel.frame)
        updatePinAppearance(animated: false)

        // Route to content preview
        if let urlStr = thread.anchor?.url, let url = URL(string: urlStr), !urlStr.isEmpty {
            loadWebPeek(url: url)
        } else if let filePath = thread.anchor?.file_path, filePath.lowercased().hasSuffix(".pdf"), FileManager.default.fileExists(atPath: filePath) {
            let pageNum = thread.anchor?.line_number ?? 1
            loadPDFPeek(path: filePath, targetPage: pageNum)
        } else if let filePath = thread.anchor?.file_path, FileManager.default.fileExists(atPath: filePath) {
            let lineNum = thread.anchor?.line_number ?? 1
            loadFilePeek(path: filePath, targetLine: lineNum)
        } else {
            loadNotesPeek(thread: thread)
        }

        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func reposition(relativeTo sanctuaryFrame: NSRect) {
        let screen = SanctuaryPopover.shared.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame
        let targetW: CGFloat = 380
        let targetH: CGFloat = sanctuaryFrame.height

        containerView.frame = NSRect(x: 0, y: 0, width: targetW, height: targetH)
        headerView.frame = NSRect(x: 0, y: targetH - 40, width: targetW, height: 40)
        contentContainer.frame = NSRect(x: 0, y: 0, width: targetW, height: targetH - 40)

        // Strict Sanctuary Left Flank Anchor
        var originX = sanctuaryFrame.minX - targetW - 6
        if originX < screenFrame.minX + 8 {
            // Screen edge fallback: if left is offscreen, anchor to right
            originX = sanctuaryFrame.maxX + 6
        }
        let originY = sanctuaryFrame.minY

        setFrame(NSRect(x: originX, y: originY, width: targetW, height: targetH), display: true)
    }

    // MARK: - Preview Engines

    private func loadWebPeek(url: URL) {
        showLoading(message: "Fetching live preview...")

        let config = WKWebViewConfiguration()
        // Enforce dark mode preferences
        let userScript = WKUserScript(
            source: """
            var meta = document.createElement('meta');
            meta.name = 'color-scheme';
            meta.content = 'dark light';
            document.head.appendChild(meta);
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(userScript)

        let wv = WKWebView(frame: contentContainer.bounds, configuration: config)
        wv.autoresizingMask = [.width, .height]
        wv.navigationDelegate = self
        // Eliminate white flash: dark transparent canvas
        wv.setValue(false, forKey: "drawsBackground")
        // Desktop Safari User Agent: prevents mobile app deep-link redirects (x-safari-https:)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

        contentContainer.addSubview(wv)
        self.webView = wv

        // 8-second safety fallback timeout: if site hangs, show reader card
        loadTimeoutTimer?.invalidate()
        loadTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            guard let self = self, self.webView?.isLoading == true else { return }
            self.showReaderFallback(url: url, notice: "Live preview took too long to respond.")
        }

        wv.load(URLRequest(url: url))
    }

    // WKNavigationDelegate
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        // Block external app breakout schemes (x-safari-https, twitter, etc.)
        if scheme.contains("safari") || scheme.starts(with: "x-") || scheme == "twitter" {
            if scheme.starts(with: "x-safari-") {
                let clean = url.absoluteString.replacingOccurrences(of: "x-safari-", with: "")
                if let cleanURL = URL(string: clean) {
                    webView.load(URLRequest(url: cleanURL))
                }
            }
            decisionHandler(.cancel)
            return
        }
        // Keep target="_blank" links inside the embedded Peek drawer
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadTimeoutTimer?.invalidate()
        hideLoading()
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadTimeoutTimer?.invalidate()
        if let url = webView.url ?? activeThread?.anchor?.url.flatMap({ URL(string: $0) }) {
            showReaderFallback(url: url, notice: "Site blocked embedding or is unreachable.")
        } else {
            hideLoading()
        }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadTimeoutTimer?.invalidate()
        hideLoading()
    }

    private func showReaderFallback(url: URL, notice: String) {
        hideLoading()
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil

        let card = NSView(frame: contentContainer.bounds)
        card.autoresizingMask = [.width, .height]

        let host = url.host ?? "Website"
        let hostLabel = NSTextField(labelWithString: host.uppercased())
        hostLabel.frame = NSRect(x: 20, y: contentContainer.bounds.height - 40, width: contentContainer.bounds.width - 40, height: 16)
        hostLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        hostLabel.textColor = NSColor(calibratedWhite: 0.50, alpha: 1.0)
        card.addSubview(hostLabel)

        let titleStr = activeThread?.title ?? "Web Cue"
        let cueTitle = NSTextField(wrappingLabelWithString: titleStr)
        cueTitle.frame = NSRect(x: 20, y: contentContainer.bounds.height - 110, width: contentContainer.bounds.width - 40, height: 60)
        cueTitle.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        cueTitle.textColor = .white
        card.addSubview(cueTitle)

        if let notes = activeThread?.notes, !notes.isEmpty {
            let notesField = NSTextField(wrappingLabelWithString: notes)
            notesField.frame = NSRect(x: 20, y: contentContainer.bounds.height - 220, width: contentContainer.bounds.width - 40, height: 100)
            notesField.font = NSFont.systemFont(ofSize: 12, weight: .regular)
            notesField.textColor = NSColor(calibratedWhite: 0.80, alpha: 1.0)
            card.addSubview(notesField)
        }

        let noticeLabel = NSTextField(labelWithString: notice)
        noticeLabel.frame = NSRect(x: 20, y: 70, width: contentContainer.bounds.width - 40, height: 16)
        noticeLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        noticeLabel.textColor = NSColor(calibratedRed: 0.95, green: 0.65, blue: 0.35, alpha: 1.0)
        card.addSubview(noticeLabel)

        let openExternalBtn = ClosureButton(frame: NSRect(x: 20, y: 24, width: contentContainer.bounds.width - 40, height: 34)) { [weak self] in
            guard let self = self, let thread = self.activeThread else { return }
            self.openCurrentThreadExternal(thread)
        }
        openExternalBtn.isBordered = false
        openExternalBtn.wantsLayer = true
        openExternalBtn.layer?.cornerRadius = 6
        openExternalBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.20, alpha: 1.0).cgColor
        openExternalBtn.attributedTitle = NSAttributedString(string: "Open in Browser ↗", attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
        ])
        card.addSubview(openExternalBtn)

        contentContainer.addSubview(card)
    }

    private func showLoading(message: String) {
        hideLoading()

        let spinner = NSProgressIndicator(frame: NSRect(x: (contentContainer.bounds.width - 24) / 2, y: (contentContainer.bounds.height / 2) + 6, width: 24, height: 24))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        contentContainer.addSubview(spinner)
        self.loadingSpinner = spinner

        let lbl = NSTextField(labelWithString: message)
        lbl.frame = NSRect(x: 20, y: (contentContainer.bounds.height / 2) - 26, width: contentContainer.bounds.width - 40, height: 18)
        lbl.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        lbl.textColor = NSColor(calibratedWhite: 0.60, alpha: 1.0)
        lbl.alignment = .center
        contentContainer.addSubview(lbl)
        self.loadingLabel = lbl
    }

    private func hideLoading() {
        loadingSpinner?.stopAnimation(nil)
        loadingSpinner?.removeFromSuperview()
        loadingSpinner = nil

        loadingLabel?.removeFromSuperview()
        loadingLabel = nil
    }

    private func loadPDFPeek(path: String, targetPage: Int) {
        let pv = PDFView(frame: contentContainer.bounds)
        pv.autoresizingMask = [.width, .height]
        pv.autoScales = true
        pv.displayMode = .singlePageContinuous
        if let doc = PDFDocument(url: URL(fileURLWithPath: path)) {
            pv.document = doc
            let pageIndex = max(0, min(targetPage - 1, doc.pageCount - 1))
            if let page = doc.page(at: pageIndex) {
                pv.go(to: page)
            }
        }
        contentContainer.addSubview(pv)
        self.pdfView = pv
    }

    private func loadFilePeek(path: String, targetLine: Int) {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            loadFallbackText("Unable to read file at:\n\(path)")
            return
        }

        let lines = content.components(separatedBy: .newlines)
        let totalLines = lines.count
        let start = max(0, targetLine - 15)
        let end = min(totalLines, targetLine + 25)

        let mutStr = NSMutableAttributedString()
        for idx in start..<end {
            let isTarget = (idx + 1 == targetLine)
            let prefix = String(format: "%4d  ", idx + 1)
            let lineContent = lines[idx] + "\n"

            let lineAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: isTarget ? .bold : .regular),
                .foregroundColor: isTarget ? NSColor(calibratedRed: 0.95, green: 0.70, blue: 0.40, alpha: 1.0) : NSColor(calibratedWhite: 0.75, alpha: 1.0),
                .backgroundColor: isTarget ? NSColor(calibratedWhite: 0.18, alpha: 1.0) : NSColor.clear
            ]
            let numAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor(calibratedWhite: 0.40, alpha: 1.0)
            ]

            mutStr.append(NSAttributedString(string: prefix, attributes: numAttr))
            mutStr.append(NSAttributedString(string: lineContent, attributes: lineAttr))
        }

        renderAttributedText(mutStr)
    }

    private func loadNotesPeek(thread: SutraThread) {
        let mutStr = NSMutableAttributedString()
        
        // Title
        mutStr.append(NSAttributedString(string: thread.title + "\n\n", attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: NSColor.white
        ]))

        // Origin details
        if let app = thread.anchor?.app_name {
            mutStr.append(NSAttributedString(string: "Application: \(app)\n", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor(calibratedWhite: 0.60, alpha: 1.0)
            ]))
        }
        if let win = thread.anchor?.window_title, !win.isEmpty {
            mutStr.append(NSAttributedString(string: "Window: \(win)\n", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor(calibratedWhite: 0.60, alpha: 1.0)
            ]))
        }
        mutStr.append(NSAttributedString(string: "\n", attributes: [:]))

        // Notes / Checklist
        if let notes = thread.notes, !notes.isEmpty {
            mutStr.append(NSAttributedString(string: notes, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor(calibratedWhite: 0.88, alpha: 1.0)
            ]))
        } else {
            mutStr.append(NSAttributedString(string: "No additional notes captured for this cue.", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor(calibratedWhite: 0.45, alpha: 1.0)
            ]))
        }

        renderAttributedText(mutStr)
    }

    private func loadFallbackText(_ text: String) {
        renderAttributedText(NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.65, alpha: 1.0)
        ]))
    }

    private func renderAttributedText(_ str: NSAttributedString) {
        let scroll = NSScrollView(frame: contentContainer.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false

        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: contentContainer.bounds.width - 24, height: contentContainer.bounds.height))
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 14, height: 14)
        tv.textStorage?.setAttributedString(str)

        scroll.documentView = tv
        contentContainer.addSubview(scroll)
        self.textScrollView = scroll
        self.textView = tv
    }

    public func dismiss() {
        teardownPreviews()
        orderOut(nil)
        activeThread = nil
    }

    private func teardownPreviews() {
        loadTimeoutTimer?.invalidate()
        loadTimeoutTimer = nil
        hideLoading()

        pinToastTimer?.invalidate()
        pinToastTimer = nil
        pinToastLabel?.isHidden = true
        pinToastLabel?.alphaValue = 0.0
        isHeaderHovered = false

        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil

        pdfView?.removeFromSuperview()
        pdfView = nil

        textScrollView?.removeFromSuperview()
        textScrollView = nil
        textView = nil

        contentContainer.subviews.forEach { $0.removeFromSuperview() }
    }
}
