import AppKit
import WebKit
import PDFKit

public final class ContextPeekDrawer: NSPanel, WKNavigationDelegate {
    public static let shared = ContextPeekDrawer()

    private var activeThread: SutraThread?
    public var activeThreadId: String? { activeThread?.id }

    private var containerView: NSView!
    private var headerView: NSView!
    private var logoView: NSImageView!
    private var titleLabel: NSTextField!
    private var contentContainer: NSView!

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
            if let thread = activeThread {
                AmbientPiPWindow.shared.pin(thread: thread)
            }
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

        // 1. Header (y: 480 - 40 ... 480)
        headerView = NSView(frame: NSRect(x: 0, y: 440, width: 380, height: 40))
        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1.0).cgColor

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

        // Pin Button
        let pinBtn = ClosureButton(frame: NSRect(x: 284, y: 9, width: 22, height: 22)) { [weak self] in
            guard let self = self, let thread = self.activeThread else { return }
            AmbientPiPWindow.shared.pin(thread: thread)
        }
        pinBtn.isBordered = false
        pinBtn.wantsLayer = true
        pinBtn.toolTip = "Pin to Ambient Floating PiP (P)"
        if let sym = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pin") {
            let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            pinBtn.image = sym.withSymbolConfiguration(cfg)
            pinBtn.contentTintColor = NSColor(calibratedWhite: 0.85, alpha: 1.0)
            pinBtn.imagePosition = .imageOnly
        }
        headerView.addSubview(pinBtn)

        // Open in Browser/App Button
        let openBtn = ClosureButton(frame: NSRect(x: 314, y: 9, width: 22, height: 22)) { [weak self] in
            guard let self = self, let thread = self.activeThread else { return }
            self.openCurrentThreadExternal(thread)
        }
        openBtn.isBordered = false
        openBtn.wantsLayer = true
        openBtn.toolTip = "Open in Default App / Browser"
        if let sym = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: "Open") {
            let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            openBtn.image = sym.withSymbolConfiguration(cfg)
            openBtn.contentTintColor = NSColor(calibratedWhite: 0.85, alpha: 1.0)
            openBtn.imagePosition = .imageOnly
        }
        headerView.addSubview(openBtn)

        // Close Button
        let closeBtn = ClosureButton(frame: NSRect(x: 344, y: 9, width: 22, height: 22)) { [weak self] in
            self?.dismiss()
        }
        closeBtn.isBordered = false
        closeBtn.wantsLayer = true
        closeBtn.layer?.cornerRadius = 11
        closeBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1.0).cgColor
        closeBtn.attributedTitle = NSAttributedString(string: "✕", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.85, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 10, weight: .bold)
        ])
        headerView.addSubview(closeBtn)

        containerView.addSubview(headerView)

        // 2. Content Container (y: 0 ... 440)
        contentContainer = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 440))
        containerView.addSubview(contentContainer)

        contentView = containerView
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
        // Enforce dark mode preferences and responsive viewport
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
        // Responsive mobile viewport: loads Twitter/X, GitHub, Docs 3x faster without truncation
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"

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
