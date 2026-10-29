import AppKit
import Carbon

public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    public static var shared: AppDelegate?

    private var statusItem: NSStatusItem!
    private var sanctuaryMenu: NSMenu!
    private var refreshTimer: Timer?
    private var lastActiveBundleId: String?
    private var hotKeyRefSpace: EventHotKeyRef?
    private var hotKeyRefRestart: EventHotKeyRef?
    private var hotKeyRefSanctuary: EventHotKeyRef?
    private var hotKeyRefWake: EventHotKeyRef?
    private var rightOptionDownTime: TimeInterval = 0
    private var rightOptionAlone: Bool = false

    // Interruption Prediction Cue Nudge tracking (PLAN-029 Gap 6)
    private var lastDeepWorkBundleId: String?
    private var lastDeepWorkAppName: String?
    private var lastDeepWorkTime: TimeInterval = 0

    private let deepWorkBundles: Set<String> = [
        "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.apple.dt.Xcode",
        "com.apple.Terminal", "com.googlecode.iterm2", "com.sublimetext.4",
        "md.obsidian", "com.jetbrains.intellij", "com.apple.Safari",
        "com.google.Chrome", "company.thebrowser.Browser"
    ]
    private let commBundles: Set<String> = [
        "com.tinyspeck.slackmacgap", "com.apple.MobileSMS", "com.microsoft.teams2",
        "com.hnc.Discord", "com.apple.mail", "ru.keepcoder.Telegram",
        "net.whatsapp.WhatsApp", "com.superhuman.electron"
    ]

    public func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        setupMainMenu()

        if LicenseManager.shared.isActivated() {
            startActivatedServices()
        } else {
            ActivationWindow.shared.show { [weak self] in
                self?.startActivatedServices()
            }
        }
    }

    private func startActivatedServices() {
        setupStatusItem()
        setupAppSwitchListener()
        startPeriodicRefresh()
        updateBadge()

        // Background non-blocking telemetry sync
        DispatchQueue.global(qos: .utility).async {
            LicenseManager.shared.sendHeartbeatIfNeeded()
        }

        // Background non-blocking anti-hoarding decay & 6-day auto-dock
        DispatchQueue.global(qos: .utility).async {
            let decayEnabled = UserDefaults.standard.object(forKey: "SutraEnableDecay") as? Bool ?? true
            if decayEnabled {
                _ = SutraBridge.shared.autoDockStale(days: 6)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("SutraThreadsUpdated"), object: nil)
                }
            }
        }

        PermissionManager.shared.verifyOrPrompt { [weak self] in
            self?.setupGlobalHotkeys()
        }
    }

    public func setupMainMenu() {
        let mainMenu = NSMenu()
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(onStatusButtonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        renderStatusButton(count: 0)

        NotificationCenter.default.addObserver(forName: NSNotification.Name("SutraThreadsUpdated"), object: nil, queue: .main) { [weak self] _ in
            self?.updateBadge()
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("RestartSutraApp"), object: nil, queue: .main) { [weak self] _ in
            self?.restartSutra()
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("SutraShortcutsChanged"), object: nil, queue: .main) { [weak self] _ in
            self?.registerProfileHotkeys()
        }
        SettingsWindow.shared.delegate = self
        FloatingWakeBar.shared.showPersistentIsland()
    }

    @objc private func onStatusButtonClicked() {
        guard let button = statusItem.button else { return }
        SanctuaryPopover.shared.toggle(relativeTo: button)
    }

    private func getLogo(size: NSSize) -> NSImage? {
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
        return nil
    }

    private func renderStatusButton(count: Int) {
        guard let button = statusItem.button else { return }
        if let logo = getLogo(size: NSSize(width: 17, height: 17)) {
            button.image = logo
            button.imagePosition = .imageLeft
        }
        button.title = count > 0 ? " \(count)" : ""
        button.font = NSFont.systemFont(ofSize: 11.5, weight: .bold)
    }

    private func populateSanctuaryMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // 1. Header with official logo
        let headerItem = NSMenuItem(title: "  Sutra Sanctuary", action: nil, keyEquivalent: "")
        if let logo = getLogo(size: NSSize(width: 15, height: 15)) {
            headerItem.image = logo
        }
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        // 2. Leave Quick Cue shortcut
        let cueItem = NSMenuItem(title: "Leave Quick Cue... (^⌥Space)", action: #selector(openHUD), keyEquivalent: "")
        cueItem.target = self
        menu.addItem(cueItem)

        // 2b. Preferences (⌘,)
        let prefItem = NSMenuItem(title: "Preferences... (⌘,)", action: #selector(openPreferences), keyEquivalent: ",")
        prefItem.target = self
        menu.addItem(prefItem)

        menu.addItem(.separator())

        // 3. Waiting Threads Header
        let waitingHeader = NSMenuItem(title: "Waiting Threads (Click title to resume):", action: nil, keyEquivalent: "")
        waitingHeader.isEnabled = false
        menu.addItem(waitingHeader)

        let waitingThreads = SutraBridge.shared.list(status: "waiting")
        if waitingThreads.isEmpty {
            let emptyItem = NSMenuItem(title: "  No waiting threads — Mind is clear", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            var groups: [String: [SutraThread]] = [:]
            for t in waitingThreads {
                let app = t.anchor?.app_name ?? "General"
                groups[app, default: []].append(t)
            }

            for (app, unsortedAppThreads) in groups.sorted(by: { $0.key < $1.key }) {
                let appThreads = unsortedAppThreads.sorted(by: { $0.created_at > $1.created_at })
                let appHeader = NSMenuItem(title: "\(app) (\(appThreads.count))", action: nil, keyEquivalent: "")
                appHeader.isEnabled = false
                menu.addItem(appHeader)

                for thread in appThreads.prefix(5) {
                    let displayTitle = "  • \(thread.title) · \(thread.timeAgo)"
                    let threadItem = NSMenuItem(title: displayTitle, action: #selector(onActionResume(_:)), keyEquivalent: "")
                    threadItem.representedObject = thread.id
                    threadItem.target = self

                    // Submenu actions
                    let sub = NSMenu()
                    let resumeItem = NSMenuItem(title: "⚡ Resume", action: #selector(onActionResume(_:)), keyEquivalent: "")
                    resumeItem.representedObject = thread.id
                    resumeItem.target = self
                    sub.addItem(resumeItem)

                    let snoozeItem = NSMenuItem(title: "⏳ Snooze 4h", action: #selector(onActionSnooze(_:)), keyEquivalent: "")
                    snoozeItem.representedObject = thread.id
                    snoozeItem.target = self
                    sub.addItem(snoozeItem)

                    let doneItem = NSMenuItem(title: "✓ Mark Done", action: #selector(onActionDone(_:)), keyEquivalent: "")
                    doneItem.representedObject = thread.id
                    doneItem.target = self
                    sub.addItem(doneItem)

                    threadItem.submenu = sub
                    menu.addItem(threadItem)
                }

                if appThreads.count > 5 {
                    let moreCount = appThreads.count - 5
                    let moreItem = NSMenuItem(title: "  +\(moreCount) more...", action: nil, keyEquivalent: "")
                    let moreMenu = NSMenu()
                    for thread in appThreads.dropFirst(5) {
                        let displayTitle = "  • \(thread.title) · \(thread.timeAgo)"
                        let item = NSMenuItem(title: displayTitle, action: #selector(onActionResume(_:)), keyEquivalent: "")
                        item.representedObject = thread.id
                        item.target = self

                        let sub = NSMenu()
                        let resumeItem = NSMenuItem(title: "⚡ Resume", action: #selector(onActionResume(_:)), keyEquivalent: "")
                        resumeItem.representedObject = thread.id
                        resumeItem.target = self
                        sub.addItem(resumeItem)

                        let snoozeItem = NSMenuItem(title: "⏳ Snooze 4h", action: #selector(onActionSnooze(_:)), keyEquivalent: "")
                        snoozeItem.representedObject = thread.id
                        snoozeItem.target = self
                        sub.addItem(snoozeItem)

                        let doneItem = NSMenuItem(title: "✓ Mark Done", action: #selector(onActionDone(_:)), keyEquivalent: "")
                        doneItem.representedObject = thread.id
                        doneItem.target = self
                        sub.addItem(doneItem)

                        item.submenu = sub
                        moreMenu.addItem(item)
                    }
                    moreItem.submenu = moreMenu
                    menu.addItem(moreItem)
                }
            }
        }

        // 4. Snoozed Threads Submenu
        let snoozedItem = NSMenuItem(title: "Snoozed Threads (Later)...", action: nil, keyEquivalent: "")
        let snoozedMenu = NSMenu()
        let snoozedThreads = SutraBridge.shared.list(status: "snoozed")
        if snoozedThreads.isEmpty {
            let emptySnoozed = NSMenuItem(title: "No snoozed threads", action: nil, keyEquivalent: "")
            emptySnoozed.isEnabled = false
            snoozedMenu.addItem(emptySnoozed)
        } else {
            for thread in snoozedThreads.prefix(10) {
                let item = NSMenuItem(title: "  • \(thread.title)", action: #selector(onActionResume(_:)), keyEquivalent: "")
                item.representedObject = thread.id
                item.target = self

                let sub = NSMenu()
                let wakeItem = NSMenuItem(title: "⚡ Wake Now", action: #selector(onActionResume(_:)), keyEquivalent: "")
                wakeItem.representedObject = thread.id
                wakeItem.target = self
                sub.addItem(wakeItem)

                let doneItem = NSMenuItem(title: "✓ Mark Done", action: #selector(onActionDone(_:)), keyEquivalent: "")
                doneItem.representedObject = thread.id
                doneItem.target = self
                sub.addItem(doneItem)

                item.submenu = sub
                snoozedMenu.addItem(item)
            }
        }
        snoozedItem.submenu = snoozedMenu
        menu.addItem(snoozedItem)

        // 5. Completed Threads Submenu
        let doneItem = NSMenuItem(title: "Completed Threads (Done)...", action: nil, keyEquivalent: "")
        let doneMenu = NSMenu()
        let doneThreads = SutraBridge.shared.list(status: "done")
        if doneThreads.isEmpty {
            let emptyDone = NSMenuItem(title: "No completed threads yet", action: nil, keyEquivalent: "")
            emptyDone.isEnabled = false
            doneMenu.addItem(emptyDone)
        } else {
            for thread in doneThreads.prefix(10) {
                let item = NSMenuItem(title: "  ✓ \(thread.title)", action: nil, keyEquivalent: "")
                let sub = NSMenu()
                let reopenItem = NSMenuItem(title: "↩ Reopen Thread", action: #selector(onActionUndo(_:)), keyEquivalent: "")
                reopenItem.representedObject = thread.id
                reopenItem.target = self
                sub.addItem(reopenItem)
                item.submenu = sub
                doneMenu.addItem(item)
            }
        }
        doneItem.submenu = doneMenu
        menu.addItem(doneItem)

        menu.addItem(.separator())

        // 6. Manuals & Blueprints
        let guideItem = NSMenuItem(title: "Open User Guide (USER_GUIDE.html)...", action: #selector(openUserGuide), keyEquivalent: "")
        guideItem.target = self
        menu.addItem(guideItem)

        let blueprintItem = NSMenuItem(title: "Open Developer Blueprint (Develop_Sutra.html)...", action: #selector(openDeveloperBlueprint), keyEquivalent: "")
        blueprintItem.target = self
        menu.addItem(blueprintItem)

        menu.addItem(.separator())

        // 7. System Controls
        let restartItem = NSMenuItem(title: "Restart Sutra", action: #selector(restartSutra), keyEquivalent: "r")
        restartItem.keyEquivalentModifierMask = [.control, .option]
        restartItem.target = self
        menu.addItem(restartItem)

        let quitItem = NSMenuItem(title: "Quit Sutra", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func onActionResume(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String {
            _ = SutraBridge.shared.resume(threadId: id)
            NSSound(named: "Glass")?.play()
            updateBadge()
        }
    }

    @objc private func onActionSnooze(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String {
            _ = SutraBridge.shared.snooze(threadId: id, hours: 4)
            updateBadge()
        }
    }

    @objc private func onActionDone(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String {
            _ = SutraBridge.shared.done(threadId: id)
            NSSound(named: "Glass")?.play()
            updateBadge()
        }
    }

    @objc private func onActionUndo(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String {
            _ = SutraBridge.shared.undo(threadId: id)
            updateBadge()
        }
    }

    @objc private func openUserGuide() {
        if let guideUrl = Bundle.main.url(forResource: "USER_GUIDE", withExtension: "html") {
            NSWorkspace.shared.open(guideUrl)
        } else if let guideUrl = Bundle.main.url(forResource: "USER_GUIDE", withExtension: "html", subdirectory: "docs") {
            NSWorkspace.shared.open(guideUrl)
        } else {
            let possiblePaths = [
                Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("docs/USER_GUIDE.html").path,
                Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs/USER_GUIDE.html").path,
                Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("USER_GUIDE.html").path
            ]
            for p in possiblePaths where FileManager.default.fileExists(atPath: p) {
                NSWorkspace.shared.open(URL(fileURLWithPath: p))
                break
            }
        }
    }

    @objc private func openDeveloperBlueprint() {
        if let bpUrl = Bundle.main.url(forResource: "Develop_Sutra", withExtension: "html") {
            NSWorkspace.shared.open(bpUrl)
        } else {
            let possiblePaths = [
                Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Develop_Sutra.html").path,
                Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Develop_Sutra.html").path
            ]
            for p in possiblePaths where FileManager.default.fileExists(atPath: p) {
                NSWorkspace.shared.open(URL(fileURLWithPath: p))
                break
            }
        }
    }

    @objc private func openHUD() {
        QuickCueHUD.shared.show()
    }

    @objc private func openPreferences() {
        SettingsWindow.shared.show()
    }

    @objc private func restartSutra() {
        let appPath = Bundle.main.bundleURL.path
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5 && open '\(appPath)'"]
        try? task.run()
        NSApp.terminate(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func setupGlobalHotkeys() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if hotKeyID.id == 1 {
                DispatchQueue.main.async {
                    QuickCueHUD.shared.show()
                }
            } else if hotKeyID.id == 2 {
                DispatchQueue.main.async {
                    AppDelegate.shared?.restartSutra()
                }
            } else if hotKeyID.id == 3 {
                DispatchQueue.main.async {
                    SanctuaryPopover.shared.toggle()
                }
            } else if hotKeyID.id == 4 {
                DispatchQueue.main.async {
                    FloatingWakeBar.shared.toggleForFrontmostApp()
                }
            }
            return noErr
        }, 1, &eventType, nil, nil)

        registerProfileHotkeys()

        // Dedicated Right Option Tap Detector (Global Monitor)
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event: event)
        }
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            self?.rightOptionAlone = false
        }

        // Local event monitor fallback (when Sutra windows are focused)
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event: event)
            return event
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.rightOptionAlone = false
            let profile = UserDefaults.standard.string(forKey: "SutraShortcutProfile") ?? "standard"
            let wakeKey = (profile == "ergonomic") ? UInt16(kVK_ANSI_W) : UInt16(kVK_ANSI_A)
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .option {
                if event.keyCode == UInt16(kVK_ANSI_S) {
                    if let btn = self?.statusItem.button {
                        SanctuaryPopover.shared.toggle(relativeTo: btn)
                    }
                    return nil
                } else if event.keyCode == wakeKey {
                    FloatingWakeBar.shared.toggleForFrontmostApp()
                    return nil
                }
            } else if flags == [.control, .option] && event.keyCode == UInt16(kVK_ANSI_R) {
                self?.restartSutra()
                return nil
            }
            return event
        }
    }

    private func registerProfileHotkeys() {
        if let ref = hotKeyRefRestart { UnregisterEventHotKey(ref); hotKeyRefRestart = nil }
        if let ref = hotKeyRefSanctuary { UnregisterEventHotKey(ref); hotKeyRefSanctuary = nil }
        if let ref = hotKeyRefWake { UnregisterEventHotKey(ref); hotKeyRefWake = nil }

        let profile = UserDefaults.standard.string(forKey: "SutraShortcutProfile") ?? "standard"
        let wakeKeyCode: UInt32 = (profile == "ergonomic") ? UInt32(kVK_ANSI_W) : UInt32(kVK_ANSI_A)

        // ⌃⌥R -> Restart Sutra (guarded)
        let hotKeyIDRestart = EventHotKeyID(signature: OSType(0x53545242), id: 2) // 'STRB'
        RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(controlKey | optionKey), hotKeyIDRestart, GetApplicationEventTarget(), 0, &hotKeyRefRestart)

        // ⌥S -> Toggle Sutra Sanctuary
        let hotKeyIDS = EventHotKeyID(signature: OSType(0x53545243), id: 3) // 'STRC'
        RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(optionKey), hotKeyIDS, GetApplicationEventTarget(), 0, &hotKeyRefSanctuary)

        // ⌥A or ⌥W -> Toggle Floating Wake Bar (Wake Alert)
        let hotKeyIDWake = EventHotKeyID(signature: OSType(0x53545244), id: 4) // 'STRD'
        RegisterEventHotKey(wakeKeyCode, UInt32(optionKey), hotKeyIDWake, GetApplicationEventTarget(), 0, &hotKeyRefWake)
    }

    private func handleFlagsChanged(event: NSEvent) {
        // macOS Right Option key code is 61 (kVK_RightOption)
        // NX_DEVICERALTKEYMASK is 0x00000040 in event.modifierFlags.rawValue
        let isRightOption = (event.keyCode == 61) || ((event.modifierFlags.rawValue & 0x40) != 0)
        let isOptionActive = event.modifierFlags.contains(.option)

        if isRightOption && isOptionActive {
            rightOptionDownTime = CACurrentMediaTime()
            rightOptionAlone = true
        } else if isRightOption && !isOptionActive {
            if rightOptionAlone {
                let duration = CACurrentMediaTime() - rightOptionDownTime
                if duration > 0.03 && duration < 0.40 {
                    DispatchQueue.main.async {
                        QuickCueHUD.shared.show()
                    }
                }
            }
            rightOptionAlone = false
        }
    }

    private func setupAppSwitchListener() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppActivation(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func handleAppActivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleId = app.bundleIdentifier,
              bundleId != "com.sutra.app",
              bundleId != lastActiveBundleId else { return }

        lastActiveBundleId = bundleId
        let appName = app.localizedName ?? ""

        // Interruption Prediction Cue Nudge (PLAN-029 Gap 6)
        let isNudgeEnabled = UserDefaults.standard.object(forKey: "SutraEnableNudge") as? Bool ?? true
        if isNudgeEnabled, commBundles.contains(bundleId), let prevName = lastDeepWorkAppName, CACurrentMediaTime() - lastDeepWorkTime >= 60.0 {
            DispatchQueue.main.async {
                FloatingWakeBar.shared.presentNudge(fromDeepWorkApp: prevName)
            }
        }

        if deepWorkBundles.contains(bundleId) {
            lastDeepWorkBundleId = bundleId
            lastDeepWorkAppName = appName
            lastDeepWorkTime = CACurrentMediaTime()
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let waiting = SutraBridge.shared.list(status: "waiting")
            let matching = waiting.filter { thread in
                if let b = thread.anchor?.bundle_id, !b.isEmpty, b == bundleId { return true }
                if let a = thread.anchor?.app_name, !a.isEmpty, a.lowercased() == appName.lowercased() { return true }
                return false
            }

            if !matching.isEmpty {
                var orderedThreads: [SutraThread] = []
                let matchingIds = Set(matching.map { $0.id })
                orderedThreads.append(contentsOf: matching.sorted(by: { $0.created_at > $1.created_at }))
                let remaining = waiting.filter { !matchingIds.contains($0.id) }.sorted(by: { $0.created_at > $1.created_at })
                orderedThreads.append(contentsOf: remaining)

                DispatchQueue.main.async {
                    FloatingWakeBar.shared.presentMultiple(threads: orderedThreads, preserveOrder: true)
                }
            }
        }
    }

    private func startPeriodicRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateBadge()
        }
    }

    private func updateBadge() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let threads = SutraBridge.shared.list(status: "waiting")
            let count = threads.count
            DispatchQueue.main.async {
                self?.renderStatusButton(count: count)
                SanctuaryPopover.shared.refreshIfVisible()
                FloatingWakeBar.shared.updateScheduledTodayCount()
            }
        }
    }
}

extension AppDelegate: SettingsDelegate {
    public func didChangeFloatingBarPlacement(_ placement: String) {
        FloatingWakeBar.shared.relayout()
    }

    public func didChangeShortcutProfile(_ profile: String) {
        registerProfileHotkeys()
    }
}
