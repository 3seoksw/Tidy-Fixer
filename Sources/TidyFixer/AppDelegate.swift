import AppKit
import SwiftUI

final class BarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    var onHide: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        onHide?()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ProfileStore()
    private lazy var vm = BarViewModel(
        store: store, rewriter: OllamaRewriter(), classifier: Tev1Classifier())
    private var statusItem: NSStatusItem!
    private var panel: BarPanel!
    private var host: NSHostingView<BarView>!
    private let modelSettings = ModelSettings()
    private let settingsSelection = ProfileSelection()
    private var settingsWindow: NSWindow?
    private var hotKey: HotKey?
    private var anchorBottom: CGFloat = 0
    private var pressure: DispatchSourceMemoryPressure?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        setUpPanel()
        setUpMemoryPressure()
        setUpMainMenu()
        hotKey = HotKey { [weak self] in self?.toggleBar() }
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.menuBarIcon()
        let menu = NSMenu()
        let open = menu.addItem(withTitle: "Open Bar", action: #selector(openBar), keyEquivalent: " ")
        open.keyEquivalentModifierMask = [.option]
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        menu.items.last?.target = NSApp
        statusItem.menu = menu
    }

    /// Loaded straight from the file at twice the size, then marked as a template so macOS draws
    /// it in the menu bar's own colour using its alpha. NSImage(named:) would also work, but it
    /// logs CoreUI noise when the app has no asset catalog.
    private static func menuBarIcon() -> NSImage? {
        if let url = Bundle.main.url(forResource: "menubarTemplate@2x", withExtension: "png"),
            let image = NSImage(contentsOf: url)
        {
            image.size = NSSize(width: 22, height: 22)
            image.isTemplate = true
            return image
        }
        return NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "Writing fixer")
    }

    private func setUpPanel() {
        host = NSHostingView(
            rootView: BarView(vm: vm, store: store, onEditProfiles: { [weak self] in self?.showSettings(profiles: true) }))
        panel = BarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 60),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.onHide = { [weak self] in self?.vm.barClosed() }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.pinBottom() } }
    }

    /// The hosting view resizes the window and keeps the top edge fixed, so pin the bottom edge
    /// back to the anchor. The bar then grows upward.
    private func pinBottom() {
        guard panel.frame.minY != anchorBottom else { return }
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: anchorBottom))
    }

    /// Without an Edit menu, a menu-bar-only app has no Cmd+A/C/V/X/Z in its text field.
    private func setUpMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let prefs = appMenu.addItem(
            withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func setUpMemoryPressure() {
        let src = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical], queue: .main)
        src.setEventHandler { [weak self, weak src] in
            MainActor.assumeIsolated {
                guard let data = src?.data else { return }
                let level: MemoryPressure =
                    data.contains(.critical) ? .critical : data.contains(.warning) ? .warning : .normal
                self?.vm.lifecycle.pressureChanged(level)
            }
        }
        src.resume()
        pressure = src
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        vm.shutdown()
        return .terminateNow
    }

    private func toggleBar() {
        if panel.isVisible { panel.orderOut(nil) } else { showBar() }
    }

    private func showBar() {
        vm.open(source: NSWorkspace.shared.frontmostApplication)
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            anchorBottom = f.minY + 16
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: anchorBottom))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func openBar() { showBar() }
    @objc private func openSettings() { showSettings(profiles: false) }

    func showSettings(profiles: Bool) {
        if settingsWindow == nil {
            let w = NSWindow(
                contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered, defer: false)
            w.title = "Settings"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.contentView = NSHostingView(
                rootView: SettingsView(
                    store: store, settings: modelSettings, selection: settingsSelection))
            w.isReleasedWhenClosed = false
            w.center()
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: w, queue: .main
            ) { _ in NSApp.setActivationPolicy(.accessory) }
            settingsWindow = w
        }
        settingsSelection.id = profiles ? store.profiles.first?.id : SettingsView.modelsPage
        // A menu-bar-only app is hidden from Cmd+Tab, so show up as a normal app while Settings is open.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
