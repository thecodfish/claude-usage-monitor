import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var scraper: UsageScraper!
    private let usageModel = UsageModel()
    private var refreshTimer: Timer?
    private var titleTimer: Timer?
    private var loginWindowController: LoginWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        scraper = UsageScraper(model: usageModel)

        setupStatusItem()
        setupPopover()
        startAutoRefresh()
        startTitlePolling()

        Task { @MainActor in
            await self.scraper.refresh()
        }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.title = "–%"
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.action = #selector(togglePopover(_:))
        button.target = self
    }

    private func startTitlePolling() {
        titleTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let title = self.usageModel.statusBarTitle
            if self.statusItem.button?.title != title {
                self.statusItem.button?.title = title
            }
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        let contentView = PopoverView(
            model: usageModel,
            onRefresh: { [weak self] in
                await self?.scraper.refresh()
            },
            onLogin: { [weak self] in
                self?.showLoginWindow()
            }
        )
        let hosting = NSHostingController(rootView: contentView)
        hosting.sizingOptions = .preferredContentSize

        popover = NSPopover()
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            guard let button = statusItem.button else { return }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    // MARK: - Login

    private func showLoginWindow() {
        popover.performClose(nil)

        if loginWindowController == nil {
            let controller = LoginWindowController()
            controller.onLoginComplete = { [weak self] in
                guard let self else { return }
                self.loginWindowController = nil
                self.usageModel.isLoggedOut = false
                Task { @MainActor in
                    await self.scraper.refresh()
                }
            }
            loginWindowController = controller
        }
        loginWindowController?.showWindow(nil)
        loginWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Auto-Refresh

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.scraper.refresh()
            }
        }
    }
}
