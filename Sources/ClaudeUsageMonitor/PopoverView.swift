import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: UsageModel
    let onRefresh: () async -> Void
    let onLogin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.isLoggedOut {
                LoggedOutView(onLogin: onLogin)
            } else {
                // Header
                HStack {
                    Text("Claude Usage")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    RefreshButton(isLoading: model.isLoading, onRefresh: onRefresh)
                }
                .padding(.bottom, 14)

                // Current Session
                UsageRow(
                    label: "Current session",
                    percent: model.sessionPercent,
                    resetText: model.sessionReset
                )

                Divider()
                    .opacity(0.15)
                    .padding(.vertical, 12)

                // Weekly
                UsageRow(
                    label: "Weekly · All models",
                    percent: model.weeklyPercent,
                    resetText: model.weeklyReset
                )

                if model.designPercent != nil {
                    Divider()
                        .opacity(0.15)
                        .padding(.vertical, 12)

                    // Design
                    UsageRow(
                        label: "Design",
                        percent: model.designPercent,
                        resetText: model.designReset
                    )
                }

                Divider()
                    .opacity(0.15)
                    .padding(.vertical, 12)

                // Footer
                FooterRow(lastUpdated: model.lastUpdated, errorMessage: model.errorMessage, onLogin: onLogin)
            }
        }
        .padding(18)
        .frame(width: 300)
        .background(Color(nsColor: NSColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1)))
        .preferredColorScheme(.dark)
    }
}

// MARK: - Usage Row

private struct UsageRow: View {
    let label: String
    let percent: Int?
    let resetText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.3)

            if let p = percent {
                ProgressBar(percent: p)

                HStack(alignment: .firstTextBaseline) {
                    Text("\(p)%")
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.primary)

                    Spacer()

                    if let reset = resetText, !reset.isEmpty {
                        Text(reset)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                // Loading placeholder
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 6)
                HStack {
                    Text("–%")
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Progress Bar

private struct ProgressBar: View {
    let percent: Int

    private var fraction: Double { min(max(Double(percent) / 100.0, 0), 1) }

    private var barColor: Color {
        switch percent {
        case ..<70:  return Color(red: 0.2, green: 0.78, blue: 0.48)   // green
        case ..<90:  return Color(red: 0.96, green: 0.62, blue: 0.24)  // orange
        default:     return Color(red: 0.95, green: 0.35, blue: 0.35)  // red
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 6)

                // Fill
                RoundedRectangle(cornerRadius: 3)
                    .fill(barColor)
                    .frame(width: geo.size.width * fraction, height: 6)
                    .animation(.easeOut(duration: 0.5), value: fraction)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Refresh Button

private struct RefreshButton: View {
    let isLoading: Bool
    let onRefresh: () async -> Void

    var body: some View {
        Button {
            Task { await onRefresh() }
        } label: {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.55)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .frame(width: 24, height: 24)
    }
}

// MARK: - Footer

private struct FooterRow: View {
    let lastUpdated: Date?
    let errorMessage: String?
    let onLogin: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if let err = errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if err.contains("login") || err.contains("signed in") || err.contains("Timed out") {
                    Button("Sign in…", action: onLogin)
                        .font(.system(size: 10))
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                }
                }
            } else if let updated = lastUpdated {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text("Updated \(updated, style: .relative) ago")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else {
                Text("Fetching...")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }
}

// MARK: - Logged Out

private struct LoggedOutView: View {
    let onLogin: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("Not signed in")
                .font(.system(size: 14, weight: .semibold))

            Text("Sign in to Claude to see your usage stats.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: onLogin) {
                Text("Sign in to Claude…")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}
