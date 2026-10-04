import SwiftUI

public struct PlanTimelineView: View {
    let steps: [PlanStepItem]
    @State private var isExpanded: Bool = true

    public init(steps: [PlanStepItem]) {
        self.steps = steps
    }

    private var completedCount: Int {
        steps.filter { $0.status == .completed }.count
    }

    public var body: some View {
        guard !steps.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                // Header Bar
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checklist")
                            .font(.system(size: 14, weight: .semibold))            // Increased (was 13)
                            .foregroundColor(CodexTheme.accentBlue)

                        Text("Autonomous Plan")
                            .font(.system(size: 13.5, weight: .semibold))          // Increased (was 12.5)
                            .foregroundColor(CodexTheme.primaryText)

                        Spacer()

                        // Progress count pill
                        Text("\(completedCount)/\(steps.count) Done")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))        // Increased (was 11)
                            .foregroundColor(completedCount == steps.count ? CodexTheme.accentGreen : CodexTheme.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(CodexTheme.surfaceHighlight)
                            .cornerRadius(4)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))                // Increased (was 10)
                            .foregroundColor(CodexTheme.tertiaryText)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(CodexTheme.surface)
                }
                .buttonStyle(.plain)

                // Timeline List
                if isExpanded {
                    Divider().background(CodexTheme.border)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                            HStack(alignment: .top, spacing: 10) {
                                // Step indicator & connecting vertical line
                                VStack(spacing: 0) {
                                    stepIcon(step.status)
                                        .frame(width: 18, height: 18)

                                    if index < steps.count - 1 {
                                        Rectangle()
                                            .fill(CodexTheme.border)
                                            .frame(width: 1.5)
                                            .frame(minHeight: 16)
                                    }
                                }

                                // Step details
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(step.title)
                                        .font(.system(size: 13.5, weight: step.status == .running ? .semibold : .medium))      // Increased (was 12.5)
                                        .foregroundColor(step.status == .running ? CodexTheme.primaryText : CodexTheme.secondaryText)

                                    if let desc = step.description, !desc.isEmpty {
                                        Text(desc)
                                            .font(.system(size: 12.5))                // Increased (was 11.5)
                                            .foregroundColor(CodexTheme.tertiaryText)
                                    }
                                }
                                .padding(.bottom, index < steps.count - 1 ? 10 : 2)

                                Spacer()
                            }
                        }
                    }
                    .padding(12)
                    .background(CodexTheme.secondaryBackground.opacity(0.95))
                }
            }
            .cornerRadius(7)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(CodexTheme.border, lineWidth: 1)
            )
        )
    }

    @ViewBuilder
    private func stepIcon(_ status: PlanStepStatus) -> some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(CodexTheme.accentGreen)
                .font(.system(size: 14))

        case .running:
            PulsingDot(color: CodexTheme.accentBlue)

        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(CodexTheme.accentRed)
                .font(.system(size: 14))

        case .pending:
            Image(systemName: "circle")
                .foregroundColor(CodexTheme.tertiaryText)
                .font(.system(size: 12))
        }
    }
}
