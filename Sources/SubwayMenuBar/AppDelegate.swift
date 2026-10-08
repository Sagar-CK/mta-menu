import AppKit

/// Owns the status item, the dropdown menu, and the refresh loop.
///
/// Data flow: `LocationService` + `Preferences` → `MTAFeeds.fetchTripUpdates`
/// → `BoardBuilder.snapshot` → `Snapshot` → menu bar title + menu items.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var gtfs: GTFSStatic!
    private let location = LocationService()
    private let prefs = Preferences.shared
    private var timer: Timer?

    private var snapshot: Snapshot?
    private var isRefreshing = false
    private var lastFailure: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            gtfs = try GTFSStatic.loadBundled()
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu
        menu.delegate = self
        menu.autoenablesItems = false
        showIdleTitle()

        location.onUpdate = { [weak self] _ in self?.refresh() }
        location.start()

        timer = Timer.scheduledTimer(withTimeInterval: prefs.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    // MARK: - Refresh

    private var origin: Coordinate? { prefs.manualLocation ?? location.current }

    func refresh() {
        guard !isRefreshing, let origin, let gtfs else { return }
        isRefreshing = true
        let selected = prefs.selectedRoutes
        let radius = prefs.nearbyRadiusMeters
        Task {
            let feeds = MTAFeeds.feeds(for: selected)
            let fetched = await MTAFeeds.fetchTripUpdates(feeds: feeds)
            let arrivals = BoardBuilder.arrivals(from: fetched.tripUpdates, gtfs: gtfs)
            let snap = BoardBuilder.snapshot(arrivals: arrivals, gtfs: gtfs, origin: origin,
                                             selectedRoutes: selected, nearbyRadiusMeters: radius,
                                             errors: fetched.errors)
            self.snapshot = snap
            self.lastFailure = fetched.errors.count == feeds.count ? "Couldn't reach the MTA feeds." : nil
            self.applyTitle()
            self.isRefreshing = false
        }
    }

    private func applyTitle() {
        guard let button = statusItem.button else { return }
        if let snapshot, !snapshot.menuBar.isEmpty {
            button.image = nil
            button.attributedTitle = Bullets.menuBarTitle(snapshot.menuBar, gtfs: gtfs)
        } else {
            showIdleTitle()
        }
    }

    private func showIdleTitle() {
        guard let button = statusItem.button else { return }
        button.attributedTitle = NSAttributedString(string: "")
        button.image = NSImage(systemSymbolName: "tram.fill", accessibilityDescription: "Subway")
        button.image?.isTemplate = true
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        if origin == nil {
            addInfo(location.statusText)
            menu.addItem(.separator())
        } else if let snapshot {
            if snapshot.boards.isEmpty {
                addInfo(lastFailure ?? "No upcoming trains for the selected lines.")
            }
            for (i, board) in snapshot.boards.enumerated() {
                if i > 0 { menu.addItem(.separator()) }
                addHeader("\(board.station.name)  ·  \(formatDistance(meters: board.distanceMeters))")
                addDirection(.north, arrivals: board.northbound, now: snapshot.updatedAt)
                addDirection(.south, arrivals: board.southbound, now: snapshot.updatedAt)
            }
            menu.addItem(.separator())
        } else {
            addInfo(isRefreshing ? "Loading arrivals…" : "Waiting for location…")
            menu.addItem(.separator())
        }

        let lines = NSMenuItem(title: "Lines", action: nil, keyEquivalent: "")
        lines.submenu = buildLinesMenu()
        menu.addItem(lines)

        let radius = NSMenuItem(title: "Nearby Radius", action: nil, keyEquivalent: "")
        radius.submenu = buildRadiusMenu()
        menu.addItem(radius)

        let loc = NSMenuItem(title: "Location", action: nil, keyEquivalent: "")
        loc.submenu = buildLocationMenu()
        menu.addItem(loc)

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        if let snapshot {
            let formatter = DateFormatter()
            formatter.timeStyle = .medium
            addInfo("Updated \(formatter.string(from: snapshot.updatedAt))")
            for error in snapshot.errors { addInfo("⚠︎ \(error)") }
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Subway Menu Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func addHeader(_ text: String) {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.menuFont(ofSize: 0).bold, .foregroundColor: NSColor.labelColor,
        ])
        item.isEnabled = false
        menu.addItem(item)
    }

    private func addInfo(_ text: String) {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func addDirection(_ direction: Direction, arrivals: [Arrival], now: Date) {
        guard !arrivals.isEmpty else { return }
        let header = NSMenuItem(title: direction.label, action: nil, keyEquivalent: "")
        header.attributedTitle = NSAttributedString(string: direction.label.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ])
        header.isEnabled = false
        header.indentationLevel = 1
        menu.addItem(header)

        for arrival in arrivals {
            let item = NSMenuItem(title: "\(arrival.route) \(arrival.minutes(from: now)) min", action: nil, keyEquivalent: "")
            item.attributedTitle = Bullets.menuLine(route: arrival.route, minutes: arrival.minutes(from: now),
                                                    destination: arrival.destination, gtfs: gtfs)
            item.indentationLevel = 1
            item.isEnabled = true
            menu.addItem(item)
        }
    }

    private func buildLinesMenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let selected = prefs.selectedRoutes

        let all = NSMenuItem(title: "All Lines (nearest station)", action: #selector(selectAllLines), keyEquivalent: "")
        all.target = self
        all.state = selected.isEmpty ? .on : .off
        submenu.addItem(all)
        submenu.addItem(.separator())

        for info in gtfs.routes {
            let item = NSMenuItem(title: info.id, action: #selector(toggleLine(_:)), keyEquivalent: "")
            item.attributedTitle = Bullets.routeMenuTitle(info, gtfs: gtfs)
            item.target = self
            item.representedObject = info.id
            item.state = selected.contains(info.id) ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    /// Radius options in meters; 0 means no limit.
    private static let radiusOptions: [(title: String, meters: Double)] = [
        ("¼ mile", 400), ("½ mile", 800), ("1 mile", 1600), ("2 miles", 3200), ("No limit", 0),
    ]

    private func buildRadiusMenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let current = prefs.nearbyRadiusMeters ?? 0
        for option in Self.radiusOptions {
            let item = NSMenuItem(title: option.title, action: #selector(setRadius(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.meters
            item.state = option.meters == current ? .on : .off
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let hint = NSMenuItem(title: "Followed lines only show when a station is this close. The nearest station always shows.", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        submenu.addItem(hint)
        return submenu
    }

    private func buildLocationMenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        let auto = NSMenuItem(title: "Use Mac Location", action: #selector(useMacLocation), keyEquivalent: "")
        auto.target = self
        auto.state = prefs.manualLocation == nil ? .on : .off
        submenu.addItem(auto)

        let manual = NSMenuItem(title: "Set Location Manually…", action: #selector(setManualLocation), keyEquivalent: "")
        manual.target = self
        manual.state = prefs.manualLocation == nil ? .off : .on
        submenu.addItem(manual)

        submenu.addItem(.separator())
        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        if let manualLocation = prefs.manualLocation {
            status.title = String(format: "Manual: %.4f, %.4f", manualLocation.latitude, manualLocation.longitude)
        } else {
            status.title = location.statusText
        }
        status.isEnabled = false
        submenu.addItem(status)
        return submenu
    }

    // MARK: - Actions

    @objc private func refreshNow() { refresh() }

    @objc private func selectAllLines() {
        prefs.selectedRoutes = []
        snapshot = nil
        refresh()
    }

    @objc private func toggleLine(_ sender: NSMenuItem) {
        guard let route = sender.representedObject as? String else { return }
        var selected = prefs.selectedRoutes
        if selected.contains(route) { selected.remove(route) } else { selected.insert(route) }
        prefs.selectedRoutes = selected
        snapshot = nil
        refresh()
    }

    @objc private func setRadius(_ sender: NSMenuItem) {
        guard let meters = sender.representedObject as? Double else { return }
        prefs.nearbyRadiusMeters = meters > 0 ? meters : nil
        snapshot = nil
        refresh()
    }

    @objc private func useMacLocation() {
        prefs.manualLocation = nil
        snapshot = nil
        refresh()
    }

    @objc private func setManualLocation() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Set Location"
        alert.informativeText = "Enter latitude and longitude, e.g. 40.7580, -73.9855 (Times Square)."
        alert.addButton(withTitle: "Use Location")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "40.7580, -73.9855"
        if let current = prefs.manualLocation {
            field.stringValue = String(format: "%.5f, %.5f", current.latitude, current.longitude)
        }
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let coordinate = Coordinate.parse(field.stringValue) else {
            let bad = NSAlert()
            bad.messageText = "Couldn't read that location"
            bad.informativeText = "Use the form \"latitude, longitude\"."
            bad.runModal()
            return
        }
        prefs.manualLocation = coordinate
        snapshot = nil
        refresh()
    }
}
