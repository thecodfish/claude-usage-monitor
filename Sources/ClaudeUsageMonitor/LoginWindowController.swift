import AppKit
import WebKit

/// A small floating browser window that lets the user sign in to claude.ai.
/// Shares WKWebsiteDataStore.default() with the scraper's WKWebView, so
/// cookies set here are immediately available for scraping.
final class LoginWindowController: NSWindowController {

    private var webView: WKWebView!
    private var urlCheckTimer: Timer?
    var onLoginComplete: (() -> Void)?

    init() {
        let windowRect = NSRect(x: 0, y: 0, width: 480, height: 680)
        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in to Claude"
        window.center()
        window.isReleasedWhenClosed = false
        // Don't use .floating — it can interfere with keyboard focus
        window.level = .normal

        super.init(window: window)

        let config = WKWebViewConfiguration()
        // Same persistent store as the scraper — cookies are shared.
        config.websiteDataStore = WKWebsiteDataStore.default()
        // Allow all media types (needed for some auth flows)
        config.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: windowRect, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self

        // Allow back/forward gestures — helpful during login flow
        webView.allowsBackForwardNavigationGestures = true

        window.contentView = webView
        window.initialFirstResponder = webView

        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        // Ensure the window and webview receive keyboard events for copy/paste
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(webView)

        startURLPolling()
    }

    // MARK: - URL Polling
    // Claude's login is a React SPA — it uses pushState/replaceState after login,
    // which does NOT trigger WKNavigationDelegate. A timer catches these changes.

    private func startURLPolling() {
        urlCheckTimer?.invalidate()
        urlCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkLoginState()
        }
    }

    private func checkLoginState() {
        guard let url = webView.url?.absoluteString, !url.isEmpty else { return }
        // Consider login complete when we navigate away from /login to the main app
        let isLoginPage = url.contains("/login") || url.contains("/signin")
        if !isLoginPage && url.contains("claude.ai") {
            loginDidComplete()
        }
    }

    private func loginDidComplete() {
        urlCheckTimer?.invalidate()
        urlCheckTimer = nil
        NSLog("LoginWindowController: login complete, closing window")
        close()
        onLoginComplete?()
    }

    deinit {
        urlCheckTimer?.invalidate()
    }
}

// MARK: - WKNavigationDelegate
// Also handle full-page navigations (e.g. if the flow does a real redirect).
extension LoginWindowController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        checkLoginState()
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
        // Also check after every navigation decision in case URL changed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.checkLoginState()
        }
    }
}
