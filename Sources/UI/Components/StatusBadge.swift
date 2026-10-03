import SwiftUI

public struct StatusBadge: View {
    let status: ServerConnectionStatus
    let onReconnect: () -> Void

    public init(status: ServerConnectionStatus, onReconnect: @escaping () -> Void = {}) {
        self.status = status
        self.onReconnect = onReconnect
    }

    public var body: some View {
        HStack(spacing: 6) {
            dotView

            Text(statusTitle)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(statusTextColor)

            if case .error = status {
                Button(action: onReconnect) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundColor(CodexTheme.accentAmber)
                }
                .buttonStyle(.plain)
                .help("Retry connection")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusBackgroundColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(statusBorderColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var dotView: some View {
        switch status {
        case .connected:
            PulsingDot(color: CodexTheme.accentGreen)
        case .connecting:
            PulsingDot(color: CodexTheme.accentAmber)
        case .error:
            Circle().fill(CodexTheme.accentRed).frame(width: 7, height: 7)
        case .disconnected:
            Circle().fill(CodexTheme.tertiaryText).frame(width: 7, height: 7)
        }
    }

    private var statusTitle: String {
        switch status {
        case .connected(let desc):
            return desc
        case .connecting(let phase):
            return "Connecting (\(phase))"
        case .error:
            return "Offline / Error"
        case .disconnected:
            return "Disconnected"
        }
    }

    private var statusTextColor: Color {
        switch status {
        case .connected: return CodexTheme.accentGreen
        case .connecting: return CodexTheme.accentAmber
        case .error: return CodexTheme.accentRed
        case .disconnected: return CodexTheme.secondaryText
        }
    }

    private var statusBackgroundColor: Color {
        switch status {
        case .connected: return CodexTheme.accentGreen.opacity(0.12)
        case .connecting: return CodexTheme.accentAmber.opacity(0.12)
        case .error: return CodexTheme.accentRed.opacity(0.12)
        case .disconnected: return CodexTheme.surface.opacity(0.6)
        }
    }

    private var statusBorderColor: Color {
        switch status {
        case .connected: return CodexTheme.accentGreen.opacity(0.3)
        case .connecting: return CodexTheme.accentAmber.opacity(0.3)
        case .error: return CodexTheme.accentRed.opacity(0.3)
        case .disconnected: return CodexTheme.border
        }
    }
}
