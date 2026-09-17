import Foundation
import Observation

/// State behind the Local Devices window: the latest network snapshot and the refresh in flight.
@Observable
final class LocalDevicesModel {
    private(set) var snapshot: LocalNetworkSnapshot = .empty
    private(set) var isRefreshing = false
    private(set) var refreshedAt: Date?

    @ObservationIgnored private let directory: LocalNetworkDirectory
    @ObservationIgnored private unowned let tabManager: TabManager
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(directory: LocalNetworkDirectory, tabManager: TabManager) {
        self.directory = directory
        self.tabManager = tabManager
    }

    /// Shows whatever the directory already knows, then browses the network for a fresh map.
    func refresh() {
        guard refreshTask == nil else { return }
        isRefreshing = true

        refreshTask = Task(name: "Local devices refresh") {
            snapshot = await directory.snapshot()
            snapshot = await directory.refresh()
            refreshedAt = .now
            isRefreshing = false
            refreshTask = nil
        }
    }

    /// Opens the device's web interface in a new tab and brings the browser window forward.
    func open(_ device: LocalNetworkDevice) {
        guard let url = device.url else { return }
        tabManager.createTab(url: url, makeActive: true, loadImmediately: true)
        tabManager.windowManager.activeWindowController?.window?.makeKeyAndOrderFront(nil)
    }
}
