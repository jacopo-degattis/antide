import SwiftUI

public struct PermissionRequestCardView: View {
    let request: PendingACPApproval
    let onSelect: (String) -> Void

    public init(request: PendingACPApproval, onSelect: @escaping (String) -> Void) {
        self.request = request
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CodexTheme.accentAmber)
                    .frame(width: 29, height: 29)
                    .background(CodexTheme.accentAmber.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Approval required")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(CodexTheme.primaryText)
                    Text(request.title)
                        .font(.system(size: 12))
                        .foregroundStyle(CodexTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if request.options.isEmpty {
                Text("The agent is waiting for an approval choice, but the server did not provide any options. Check the ACP server logs.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(CodexTheme.accentAmber)
            } else {
                HStack(spacing: 8) {
                    ForEach(request.options) { option in
                        Button {
                            onSelect(option.optionId)
                        } label: {
                            Text(option.name)
                                .font(.system(size: 11.5, weight: .medium))
                                .frame(minWidth: 68)
                        }
                        .buttonStyle(.bordered)
                        .tint(option.isApproval ? CodexTheme.accentBlue : CodexTheme.accentRed)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CodexTheme.surface, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(CodexTheme.accentAmber.opacity(0.32)))
    }
}

private extension ACPPermissionOption {
    var isApproval: Bool {
        let normalized = "\(optionId) \(name) \(kind ?? "")".lowercased()
        return normalized.contains("allow") || normalized.contains("approve") || normalized.contains("accept")
    }
}
