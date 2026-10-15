import Cocoa
@preconcurrency import WebKit

// MARK: - Görünüm modu

enum ViewMode: Int {
    case read = 0, split = 1, edit = 2
}

// MARK: - Belge

@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    var text = ""

    override class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        let vc = DocViewController(document: self)
        let window = NSWindow(contentViewController: vc)
        window.setContentSize(NSSize(width: 1000, height: 780))
        window.toolbarStyle = .unified
        window.tabbingMode = .preferred
        let wc = NSWindowController(window: window)
        wc.shouldCascadeWindows = true
        addWindowController(wc)
        vc.installToolbar(in: window)
        window.center()
    }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let s = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        text = s
        for wc in windowControllers {
            (wc.contentViewController as? DocViewController)?.reloadFromDocument()
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        if let vc = windowControllers.first?.contentViewController as? DocViewController {
            text = vc.currentText
        }
        return Data(text.utf8)
    }

    override func fileNameExtension(forType typeName: String, saveOperation: NSDocument.SaveOperationType) -> String? {
        "md"
    }
}

// MARK: - Pencere içeriği (düzenleyici + önizleme)

final class DocViewController: NSViewController, NSTextViewDelegate, WKNavigationDelegate, NSToolbarDelegate {
    private weak var doc: MarkdownDocument?
    private let split = NSSplitView()
    private let editorScroll = NSTextView.scrollableTextView()
    private var textView: NSTextView { editorScroll.documentView as! NSTextView }
    private let web: WKWebView
    private var pageLoaded = false
    private var renderPending = false
    private var renderWork: DispatchWorkItem?
    private var segmented: NSSegmentedControl?

    private static let modeKey = "lastMode"
    private static let zoomKey = "zoom"

    private var mode: ViewMode = .read {
        didSet { applyMode() }
    }

    var currentText: String { textView.string }

    init(document: MarkdownDocument) {
        doc = document
        let cfg = WKWebViewConfiguration()
        web = WKWebView(frame: .zero, configuration: cfg)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        split.isVertical = true
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false

        // Düzenleyici
        let tv = textView
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.textContainerInset = NSSize(width: 16, height: 16)
        tv.delegate = self

        // Önizleme
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")

        split.addArrangedSubview(editorScroll)
        split.addArrangedSubview(web)

        let root = NSView()
        root.addSubview(split)
        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            split.topAnchor.constraint(equalTo: root.topAnchor),
            split.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root

        NotificationCenter.default.addObserver(
            self, selector: #selector(editorScrolled),
            name: NSView.boundsDidChangeNotification, object: editorScroll.contentView)
        editorScroll.contentView.postsBoundsChangedNotifications = true

        tv.string = doc?.text ?? ""
        setZoom(CGFloat(UserDefaults.standard.object(forKey: Self.zoomKey) as? Double ?? 1.0))

        let isNew = doc?.fileURL == nil
        let saved = ViewMode(rawValue: UserDefaults.standard.integer(forKey: Self.modeKey)) ?? .read
        mode = isNew ? .split : saved
        applyMode()

        if let html = Bundle.main.url(forResource: "index", withExtension: "html") {
            web.loadFileURL(html, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        let w = split.bounds.width
        if w > 0 { split.setPosition(w / 2, ofDividerAt: 0) }
    }

    func reloadFromDocument() {
        guard isViewLoaded else { return }
        textView.string = doc?.text ?? ""
        render()
    }

    // MARK: Mod

    private func applyMode() {
        editorScroll.isHidden = (mode == .read)
        web.isHidden = (mode == .edit)
        split.adjustSubviews()
        if mode == .split, split.bounds.width > 0 {
            split.setPosition(split.bounds.width / 2, ofDividerAt: 0)
        }
        segmented?.selectedSegment = mode.rawValue
        if mode != .read { view.window?.makeFirstResponder(textView) }
        if mode != .edit { render() }
    }

    private func setMode(_ m: ViewMode) {
        mode = m
        if doc?.fileURL != nil { UserDefaults.standard.set(m.rawValue, forKey: Self.modeKey) }
    }

    @objc func modeRead(_ sender: Any?) { setMode(.read) }
    @objc func modeSplit(_ sender: Any?) { setMode(.split) }
    @objc func modeEdit(_ sender: Any?) { setMode(.edit) }
    @objc func toggleEdit(_ sender: Any?) { setMode(mode == .read ? .split : .read) }
    @objc func segmentChanged(_ sender: NSSegmentedControl) {
        setMode(ViewMode(rawValue: sender.selectedSegment) ?? .read)
    }

    // MARK: Yakınlaştırma

    private func setZoom(_ z: CGFloat) {
        let v = min(max(z, 0.5), 3.0)
        web.pageZoom = v
        let size = 13 * v
        textView.font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        UserDefaults.standard.set(Double(v), forKey: Self.zoomKey)
    }
    @objc func zoomIn(_ sender: Any?) { setZoom(web.pageZoom + 0.1) }
    @objc func zoomOut(_ sender: Any?) { setZoom(web.pageZoom - 0.1) }
    @objc func zoomReset(_ sender: Any?) { setZoom(1.0) }

    @objc func revealInFinder(_ sender: Any?) {
        if let url = doc?.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    // MARK: Önizleme

    func textDidChange(_ notification: Notification) {
        renderWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.render() }
        renderWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func render() {
        guard pageLoaded else { renderPending = true; return }
        guard mode != .edit else { return }
        let base = doc?.fileURL?.deletingLastPathComponent().absoluteString ?? ""
        guard let data = try? JSONEncoder().encode([textView.string, base]),
              let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("render(...\(json))", completionHandler: nil)
    }

    @objc private func editorScrolled() {
        guard mode == .split, pageLoaded, let docView = editorScroll.documentView else { return }
        let max = docView.bounds.height - editorScroll.contentView.bounds.height
        guard max > 0 else { return }
        let r = editorScroll.contentView.bounds.origin.y / max
        web.evaluateJavaScript("scrollToRatio(\(r))", completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageLoaded = true
        if renderPending || mode != .edit { renderPending = false; render() }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        // Yalnızca önizleme sayfasının kendisi yüklenebilir.
        guard action.navigationType == .linkActivated else {
            let page = Bundle.main.url(forResource: "index", withExtension: "html")
            decisionHandler(url.standardizedFileURL == page?.standardizedFileURL ? .allow : .cancel)
            return
        }
        decisionHandler(.cancel)
        if url.isFileURL {
            if ["md", "markdown", "mdown", "mkd"].contains(url.pathExtension.lowercased()) {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            } else {
                // Diğer yerel dosyaları çalıştırmak yerine Finder'da göster.
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        } else if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Araç çubuğu

    private static let modeItem = NSToolbarItem.Identifier("mode")

    func installToolbar(in window: NSWindow) {
        let tb = NSToolbar(identifier: "main")
        tb.delegate = self
        tb.displayMode = .iconOnly
        window.toolbar = tb
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.modeItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.modeItem]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard id == Self.modeItem else { return nil }
        let seg = NSSegmentedControl(labels: ["Oku", "Böl", "Düzenle"],
                                     trackingMode: .selectOne, target: self,
                                     action: #selector(segmentChanged(_:)))
        seg.selectedSegment = mode.rawValue
        segmented = seg
        let item = NSToolbarItem(itemIdentifier: id)
        item.view = seg
        item.label = "Mod"
        return item
    }
}

// MARK: - Uygulama

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMenu()
        // Dosyasız açıldıysa "Aç" penceresini göster.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if NSDocumentController.shared.documents.isEmpty {
                NSDocumentController.shared.openDocument(nil)
            }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSDocumentController.shared.openDocument(nil) }
        return false
    }

    private func buildMenu() -> NSMenu {
        let main = NSMenu()
        let appName = "Markdown Okuyucu"

        func add(_ menu: NSMenu, _ title: String, _ sel: Selector?, _ key: String = "",
                 _ mods: NSEvent.ModifierFlags = .command) {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            menu.addItem(item)
        }
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem()
            let m = NSMenu(title: title)
            item.submenu = m
            main.addItem(item)
            return m
        }

        let app = submenu(appName)
        add(app, "\(appName) Hakkında", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        app.addItem(.separator())
        add(app, "\(appName) Uygulamasını Gizle", #selector(NSApplication.hide(_:)), "h")
        add(app, "Diğerlerini Gizle", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        app.addItem(.separator())
        add(app, "\(appName) Uygulamasından Çık", #selector(NSApplication.terminate(_:)), "q")

        let file = submenu("Dosya")
        add(file, "Yeni", #selector(NSDocumentController.newDocument(_:)), "n")
        add(file, "Aç…", #selector(NSDocumentController.openDocument(_:)), "o")
        file.addItem(.separator())
        add(file, "Kapat", #selector(NSWindow.performClose(_:)), "w")
        add(file, "Kaydet", #selector(NSDocument.save(_:)), "s")
        add(file, "Çoğalt", #selector(NSDocument.duplicate(_:)), "s", [.command, .shift])
        add(file, "Farklı Kaydet…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift, .option])
        add(file, "Son Kaydedilene Döndür", #selector(NSDocument.revertToSaved(_:)))
        file.addItem(.separator())
        add(file, "Finder'da Göster", #selector(DocViewController.revealInFinder(_:)), "r", [.command, .shift])

        let edit = submenu("Düzen")
        add(edit, "Geri Al", Selector(("undo:")), "z")
        add(edit, "Yinele", Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        add(edit, "Kes", #selector(NSText.cut(_:)), "x")
        add(edit, "Kopyala", #selector(NSText.copy(_:)), "c")
        add(edit, "Yapıştır", #selector(NSText.paste(_:)), "v")
        add(edit, "Tümünü Seç", #selector(NSText.selectAll(_:)), "a")
        edit.addItem(.separator())
        let find = NSMenuItem(title: "Bul…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        find.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        edit.addItem(find)
        let next = NSMenuItem(title: "Sonrakini Bul", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "g")
        next.tag = Int(NSFindPanelAction.next.rawValue)
        edit.addItem(next)

        let view = submenu("Görünüm")
        add(view, "Okuma Modu", #selector(DocViewController.modeRead(_:)), "1")
        add(view, "Bölünmüş (Düzenle + Önizle)", #selector(DocViewController.modeSplit(_:)), "2")
        add(view, "Sadece Düzenleyici", #selector(DocViewController.modeEdit(_:)), "3")
        add(view, "Oku / Düzenle Geçiş", #selector(DocViewController.toggleEdit(_:)), "e")
        view.addItem(.separator())
        add(view, "Büyüt", #selector(DocViewController.zoomIn(_:)), "+")
        add(view, "Küçült", #selector(DocViewController.zoomOut(_:)), "-")
        add(view, "Gerçek Boyut", #selector(DocViewController.zoomReset(_:)), "0")
        view.addItem(.separator())
        add(view, "Tam Ekran", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])

        let window = submenu("Pencere")
        add(window, "Küçült", #selector(NSWindow.performMiniaturize(_:)), "m")
        add(window, "Büyüt/Küçült", #selector(NSWindow.performZoom(_:)))
        NSApp.windowsMenu = window

        return main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
