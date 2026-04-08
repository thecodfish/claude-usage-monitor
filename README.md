# Claude Usage Monitor

A native macOS menubar app that shows your [Claude.ai](https://claude.ai) usage stats at a glance.

![menubar showing 9%](https://img.shields.io/badge/menubar-9%25-brightgreen)

## What it does

- Lives in the menubar as a compact percentage label (e.g. `9%`)
- Click to open a dark popover showing:
  - **Current session** usage + time until reset
  - **Weekly (All models)** usage + time until reset
- Auto-refreshes every 5 minutes
- Manual refresh button

## Privacy — all data stays local

**No data leaves your Mac** except the request to `claude.ai` itself.

| What | Where it lives |
|------|---------------|
| Session cookies | `~/Library/WebKit/com.local.ClaudeUsageMonitor/` (on your Mac only) |
| Usage numbers | In memory only, never written to disk |
| Passwords | Never seen by the app — login uses Claude's own web UI |

- No API keys, tokens, or passwords are stored
- No analytics, telemetry, or third-party requests
- The only network call is `https://claude.ai/settings/usage`
- Uninstall cleanly: `rm -rf ClaudeUsageMonitor.app ~/Library/WebKit/com.local.ClaudeUsageMonitor`

## Requirements

- macOS 13 (Ventura) or later
- Xcode Command Line Tools (`xcode-select --install`)
- A Claude.ai account

## Build & run

```bash
git clone https://github.com/thecodfish/claude-usage-monitor
cd claude-usage-monitor
make run
```

On first launch, click the menubar icon and sign in through the in-app browser. The window closes automatically once you're logged in and your stats appear.

## How it works

The app uses a `WKWebView` to load `claude.ai/settings/usage` and extracts usage data by querying `[role="progressbar"]` elements via JavaScript. It reuses your login session through `WKWebsiteDataStore.default()`, which persists cookies between launches.

## Development

```bash
make build   # compile only
make bundle  # compile + create .app
make run     # compile + bundle + launch
make clean   # remove build artifacts
```

> **Note:** Swift Package Manager's manifest linking is broken on Command Line Tools without Xcode installed, so the Makefile compiles with `swiftc` directly. The `Package.swift` is included for editor tooling only.

## License

MIT
