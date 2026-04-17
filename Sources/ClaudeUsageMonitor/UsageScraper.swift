import AppKit
import WebKit

// MARK: - Data Model

final class UsageModel: ObservableObject {
    @Published var sessionPercent: Int? = nil    // 0–100, from aria-valuenow
    @Published var sessionReset: String? = nil   // e.g. "Resets in 3 hr 20 min"
    @Published var weeklyPercent: Int? = nil
    @Published var weeklyReset: String? = nil
    @Published var designPercent: Int? = nil
    @Published var designReset: String? = nil
    @Published var lastUpdated: Date? = nil
    @Published var isLoading: Bool = false
    @Published var isLoggedOut: Bool = false
    @Published var errorMessage: String? = nil

    // Target reset Date derived from sessionReset text, used for live countdown.
    var sessionResetDate: Date? = nil

    var statusBarTitle: String {
        guard let p = sessionPercent else { return "–%" }
        if p >= 100, let resetDate = sessionResetDate {
            let remaining = resetDate.timeIntervalSinceNow
            if remaining > 0 {
                return formatCountdown(remaining)
            }
        }
        return "\(p)%"
    }

    private func formatCountdown(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Errors

enum ScraperError: LocalizedError {
    case notLoggedIn
    case timeout(url: String)
    case parseFailure
    case navigationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "Not logged in to claude.ai in Safari"
        case .timeout(let url):
            return "Timed out waiting for page to load (landed on: \(url))"
        case .parseFailure:
            return "Could not parse usage data from page"
        case .navigationFailed(let err):
            return "Navigation failed: \(err.localizedDescription)"
        }
    }
}

// MARK: - Scraper

final class UsageScraper: NSObject {

    private let model: UsageModel
    private var webView: WKWebView!
    // Strong ref keeps the window alive so WKWebView doesn't lose its rendering context
    private var hiddenWindow: NSWindow!
    private var navigationContinuation: CheckedContinuation<Void, Error>?

    init(model: UsageModel) {
        self.model = model
        super.init()
        setupWebView()
    }

    // MARK: - Setup

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        // Share Safari's persistent cookie/session store so existing login works.
        // Requires: no App Sandbox (sandboxed apps get an isolated store instead).
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.mediaTypesRequiringUserActionForPlayback = .all

        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                            configuration: config)
        webView.navigationDelegate = self

        // WKWebView requires a backing window with an active layer to make network
        // requests and run JavaScript. We create a real (tiny) off-screen window,
        // briefly bring it to the screen surface, then hide it.
        // This fully initialises the WebKit rendering engine.
        hiddenWindow = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hiddenWindow.contentView?.addSubview(webView)
        webView.frame = hiddenWindow.contentView?.bounds ?? CGRect(x: 0, y: 0, width: 800, height: 600)

        // Bring off-screen briefly to give WKWebView a real graphics context,
        // then immediately send it behind everything — it stays hidden from the user.
        hiddenWindow.orderFrontRegardless()
        hiddenWindow.orderBack(nil)
    }

    // MARK: - Public

    @MainActor
    func refresh() async {
        guard !model.isLoading else { return }
        model.isLoading = true
        model.errorMessage = nil
        defer { model.isLoading = false }

        do {
            try await loadPage()
            let finalURL = webView.url?.absoluteString ?? "unknown"
            try await waitForProgressBars(pageURL: finalURL)
            let data = try await extractData()
            applyData(data)
        } catch ScraperError.notLoggedIn {
            model.isLoggedOut = true
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Load Page

    private func loadPage() async throws {
        let url = URL(string: "https://claude.ai/settings/usage")!

        // Detect login redirect: if the page is already on a non-settings URL,
        // a previous load might have redirected. Always force a fresh load.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.navigationContinuation = continuation
            DispatchQueue.main.async {
                self.webView.load(URLRequest(url: url))
            }
        }

        // After navigation completes, check if we were redirected to a login page.
        let finalURL = await webView.url?.absoluteString ?? ""
        if finalURL.contains("login") || finalURL.contains("signin") ||
           (!finalURL.contains("claude.ai") && !finalURL.isEmpty) {
            throw ScraperError.notLoggedIn
        }
    }

    // MARK: - Wait for React Hydration

    private func waitForProgressBars(pageURL: String) async throws {
        // Poll every 300 ms for up to 20 seconds until ≥ 2 progress bars appear.
        let js = "document.querySelectorAll('[role=\"progressbar\"]').length"
        for _ in 0..<67 {
            try await Task.sleep(nanoseconds: 300_000_000)

            // Fast login-redirect detection: check URL on every tick.
            let currentURL = webView.url?.absoluteString ?? ""
            if currentURL.contains("/login") || currentURL.contains("/signin") {
                throw ScraperError.notLoggedIn
            }

            // evaluateJavaScript can throw if the page navigates mid-poll; just retry.
            if let result = try? await webView.evaluateJavaScript(js),
               let count = result as? Int, count >= 2 {
                return
            }
        }
        throw ScraperError.timeout(url: webView.url?.absoluteString ?? pageURL)
    }

    // MARK: - Extract Data

    private struct UsageData {
        var sessionPercent: Int
        var sessionReset: String
        var weeklyPercent: Int
        var weeklyReset: String
        var designPercent: Int?
        var designReset: String?
    }

    private func extractData() async throws -> UsageData {
        guard let result = try await webView.evaluateJavaScript(Self.extractionScript) as? [String: Any] else {
            throw ScraperError.parseFailure
        }

        if let err = result["error"] as? String {
            if err == "notLoggedIn" { throw ScraperError.notLoggedIn }
            throw ScraperError.parseFailure
        }

        // JS returns Double for numeric values; cast defensively
        let sp = (result["sessionPercent"] as? Int) ?? Int((result["sessionPercent"] as? Double) ?? 0)
        let sr = result["sessionReset"] as? String ?? ""
        let wp = (result["weeklyPercent"] as? Int) ?? Int((result["weeklyPercent"] as? Double) ?? 0)
        let wr = result["weeklyReset"] as? String ?? ""

        var data = UsageData(sessionPercent: sp, sessionReset: sr,
                             weeklyPercent: wp, weeklyReset: wr)

        if let dp = result["designPercent"] {
            data.designPercent = (dp as? Int) ?? Int((dp as? Double) ?? 0)
            data.designReset   = result["designReset"] as? String ?? ""
        }

        return data
    }

    // MARK: - Apply

    @MainActor
    private func applyData(_ data: UsageData) {
        model.sessionPercent = data.sessionPercent
        model.sessionReset   = data.sessionReset
        model.weeklyPercent  = data.weeklyPercent
        model.weeklyReset    = data.weeklyReset
        model.designPercent  = data.designPercent
        model.designReset    = data.designReset
        model.lastUpdated    = Date()
        model.isLoggedOut    = false

        // Compute the target reset Date so statusBarTitle can show a live countdown.
        if let interval = Self.parseResetInterval(data.sessionReset) {
            model.sessionResetDate = Date().addingTimeInterval(interval)
        } else {
            model.sessionResetDate = nil
        }
    }

    // Parse "Resets in X day(s) Y hr Z min" → TimeInterval.
    // Handles any subset of day/hr/min components in any order.
    static func parseResetInterval(_ text: String) -> TimeInterval? {
        guard !text.isEmpty else { return nil }
        var total: TimeInterval = 0
        var found = false

        let patterns: [(String, TimeInterval)] = [
            (#"(\d+)\s*day"#,  86400),
            (#"(\d+)\s*hr"#,    3600),
            (#"(\d+)\s*min"#,     60),
        ]

        for (pattern, multiplier) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsText = text as NSString
            let range = NSRange(location: 0, length: nsText.length)
            if let match = regex.firstMatch(in: text, range: range),
               let captureRange = Range(match.range(at: 1), in: text),
               let value = Double(text[captureRange]) {
                total += value * multiplier
                found = true
            }
        }

        return found ? total : nil
    }

    // MARK: - JavaScript

    // Confirmed against live claude.ai/settings/usage DOM (2026-04-08).
    // Strategy: find [role="progressbar"] → aria-valuenow for %, walk up DOM for "Resets" text.
    // Bars: [0] = Current session, [1] = Weekly/All models, then optional meters (Design, etc.)
    // API spend bar has no "Resets" text — that's how we distinguish usage meters from spend meters.
    static let extractionScript = """
    (function() {
        var bars = Array.from(document.querySelectorAll('[role="progressbar"]'));
        if (bars.length < 2) return { error: 'notReady' };

        var bodyText = document.body ? document.body.innerText : '';
        if (/\\bLog in\\b|\\bSign in\\b/i.test(bodyText.slice(0, 500))) {
            return { error: 'notLoggedIn' };
        }

        function parseBar(el) {
            var percent = parseInt(el.getAttribute('aria-valuenow') || '0', 10);
            var node = el;
            for (var i = 0; i < 8; i++) {
                if (!node.parentElement) break;
                node = node.parentElement;
                var text = node.innerText || '';
                var resetMatch = text.match(/Resets[^\\n]+/);
                if (resetMatch) {
                    return { percent: percent, reset: resetMatch[0].trim() };
                }
            }
            return { percent: percent, reset: '' };
        }

        function findHeading(el) {
            var node = el;
            for (var i = 0; i < 10; i++) {
                if (!node.parentElement) break;
                node = node.parentElement;
                var heading = node.querySelector('h1,h2,h3,h4,h5,h6,[class*="heading"],[class*="title"]');
                if (heading) return heading.innerText.trim();
            }
            return '';
        }

        var session = parseBar(bars[0]);
        var weekly  = parseBar(bars[1]);

        var out = {
            sessionPercent: session.percent,
            sessionReset:   session.reset,
            weeklyPercent:  weekly.percent,
            weeklyReset:    weekly.reset
        };

        // Check bars beyond the first two for additional usage meters (e.g. Design).
        // A usage meter always has "Resets" text; API spend does not.
        for (var i = 2; i < bars.length; i++) {
            var bar = parseBar(bars[i]);
            if (!bar.reset) continue;
            var heading = findHeading(bars[i]).toLowerCase();
            if (/design/.test(heading)) {
                out.designPercent = bar.percent;
                out.designReset   = bar.reset;
            }
        }

        return out;
    })()
    """
}

// MARK: - WKNavigationDelegate

extension UsageScraper: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationContinuation?.resume()
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: ScraperError.navigationFailed(error))
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        navigationContinuation?.resume(throwing: ScraperError.navigationFailed(error))
        navigationContinuation = nil
    }
}
