import AppKit
import SwiftUI
import Combine
import LimitBarCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: UsageStore
    var panel: GlassPanel!
    var panelSize = NSSize(width: 320, height: 380)
    var hostingView: NSHostingView<LimitBarView>!
    var eventMonitors: [Any] = []
    var statusItem: NSStatusItem!
    var subscriptions = Set<AnyCancellable>()
    let arguments = CommandLine.arguments
    var previewing: Bool { store.preview || arguments.contains("--snapshot") }

    override init() {
        store = UsageStore(preview: CommandLine.arguments.contains("--preview"))
        super.init()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if arguments.contains("--diagnose") {
            Task {
                for provider in store.providers {
                    do {
                        let snapshot = try await provider.fetch(allowInteraction: arguments.contains("--allow-keychain"))
                        // Diagnostics deliberately contain no tokens, account identifiers, or raw API responses.
                        let windows: [[String: Any]] = snapshot.windows.map { window in
                            ["title": window.title, "usedPercent": window.usedPercent as Any? ?? NSNull(),
                             "resetsAt": window.resetsAt.map { ISO8601DateFormatter().string(from: $0) } as Any? ?? NSNull()]
                        }
                        let json = try JSONSerialization.data(withJSONObject: ["provider": snapshot.provider.rawValue, "plan": snapshot.plan, "windows": windows], options: [.sortedKeys])
                        print(String(decoding: json, as: UTF8.self))
                    } catch { print("\(provider.id.rawValue): \(error.localizedDescription)") }
                }
                NSApp.terminate(nil)
            }
            return
        }
        panel = GlassPanel(contentRect: NSRect(origin: .zero, size: panelSize),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)
        let hosting = NSHostingView(rootView: LimitBarView(store: store))
        hostingView = hosting
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: hosting, queue: .main) { [weak self, weak hosting] _ in
            DispatchQueue.main.async {
                guard let self, let hosting else { return }
                self.resizePanel(hosting.fittingSize)
            }
        }
        hosting.frame = NSRect(origin: .zero, size: panelSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = GlassSurface.make(content: hosting)
        DispatchQueue.main.async { self.resizePanel(hosting.fittingSize) }
        installEventMonitors()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatus() }
        }.store(in: &subscriptions)
        updateStatus()
        store.start()
        if arguments.contains("--preview") || arguments.contains("--snapshot") {
            showPreviewWindow()
        } else if arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.togglePanel() }
        }
    }
    func updateStatus() {
        let image = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent", accessibilityDescription: "LimitBar")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.title = ""
        DispatchQueue.main.async { self.resizePanel(self.hostingView.fittingSize) }
        statusItem.button?.toolTip = "LimitBar — Claude \(store.menuText(for: .claude)), Codex \(store.menuText(for: .codex))\nEach percentage is the most used quota window\(store.showRemaining ? " (shown as remaining)" : "")."
        statusItem.button?.setAccessibilityLabel("LimitBar. Claude \(store.menuText(for: .claude)), Codex \(store.menuText(for: .codex)).")
    }
    @objc func togglePanel() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "r").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit LimitBar", action: #selector(quit), keyEquivalent: "q").target = self
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        if panel.isVisible { panel.orderOut(nil) }
        else {
            store.now = Date()
            positionPanel()
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }
    func resizePanel(_ size: CGSize) {
        guard size.width > 0, size.height > 0, abs(size.height - panelSize.height) > 0.5 else { return }
        panelSize = NSSize(width: size.width, height: ceil(size.height))
        let top = panel.frame.maxY
        panel.setFrame(NSRect(x: panel.frame.minX, y: top - panelSize.height, width: panelSize.width, height: panelSize.height), display: true)
        if !previewing { positionPanel() }
    }
    func positionPanel() {
        guard let button = statusItem.button, let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? anchor
        let x = max(visible.minX + 8, min(anchor.maxX - panelSize.width, visible.maxX - panelSize.width - 8))
        let y = max(visible.minY + 8, anchor.minY - panelSize.height - 9)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
    func installEventMonitors() {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            guard let self, !self.store.pinned, !self.previewing else { return }
            self.panel.orderOut(nil)
        }) { eventMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown && event.keyCode == 53 && self.panel.isVisible {
                self.panel.orderOut(nil)
                return nil
            }
            if event.type != .keyDown && event.window !== self.panel && event.window !== self.statusItem.button?.window && !self.store.pinned && !self.previewing {
                self.panel.orderOut(nil)
            }
            return event
        }) { eventMonitors.append(monitor) }
    }
    func applicationWillTerminate(_ notification: Notification) {
        eventMonitors.forEach(NSEvent.removeMonitor)
    }
    @objc func refresh() { store.refresh(allowInteraction: true) }
    @objc func quit() { NSApp.terminate(nil) }

    func showPreviewWindow() {
        if arguments.contains("--preview-settings") { store.settingsOpen = true }
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
            let path = arguments[index + 1]
            Task {
                // Wait for both bounded providers to settle before taking a live snapshot.
                for _ in 0..<65 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if !store.refreshing { break }
                }
                guard let view = panel.contentView else { NSApp.terminate(nil); return }
                try? await Task.sleep(nanoseconds: 500_000_000)
                view.layoutSubtreeIfNeeded()
                print("Surface: \(type(of: view)); size: \(panelSize); OpenAI logo: \(BrandAssets.openAI.isValid)")
                resizePanel(hostingView.fittingSize)
                // A separate app-owned view renders the same foreground on a neutral
                // surface. Native compositor filters cannot be captured by cacheDisplay.
                let renderView = NSHostingView(rootView: LimitBarView(store: store)
                    .background(Color(red: 0.14, green: 0.16, blue: 0.19)))
                let renderWindow = NSWindow(contentRect: NSRect(origin: .zero, size: panelSize), styleMask: .borderless, backing: .buffered, defer: false)
                renderWindow.contentView = renderView
                renderWindow.appearance = NSAppearance(named: .darkAqua)
                renderWindow.setContentSize(renderView.fittingSize)
                renderWindow.displayIfNeeded()
                renderView.layoutSubtreeIfNeeded()
                print("Layout: \(renderView.fittingSize); no screen capture")
                if let bitmap = renderView.bitmapImageRepForCachingDisplay(in: renderView.bounds) {
                    renderView.cacheDisplay(in: renderView.bounds, to: bitmap)
                    if let png = bitmap.representation(using: .png, properties: [:]) {
                        do { try png.write(to: URL(fileURLWithPath: path)); print("Snapshot saved: \(path)") }
                        catch { print("Could not save snapshot: \(error.localizedDescription)") }
                    }
                }
                NSApp.terminate(nil)
            }
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
