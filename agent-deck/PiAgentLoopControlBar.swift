import SwiftUI
import AppKit

struct PiAgentLoopControlBar: View {
    let run: LoopRun
    let onOpenDetails: () -> Void
    let onStop: () -> Void
    let onRevealArtifacts: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "infinity")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.brandAccent)
                .frame(width: 28, height: 28)
                .background(Circle().fill(AppTheme.brandAccent.opacity(0.14)))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Loop running — use loop controls")
                        .font(AppTheme.Font.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(run.status.displayName)
                        .font(AppTheme.Font.caption.weight(.semibold))
                        .foregroundStyle(run.isActive ? AppTheme.brandAccent : AppTheme.mutedText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule(style: .continuous).fill((run.isActive ? AppTheme.brandAccent : AppTheme.mutedText).opacity(0.12)))
                }
                Text(detailText)
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button("Open Details", action: onOpenDetails)
                .appSmallSecondaryButton()
            if let onRevealArtifacts {
                Button("Reveal Artifacts", action: onRevealArtifacts)
                    .appSmallSecondaryButton()
            }
            if run.isActive {
                Button("Stop", role: .destructive, action: onStop)
                    .appDestructiveButton()
                    .controlSize(.small)
            }
        }
        .padding(12)
        .appContentSurface(cornerRadius: AppTheme.Chat.composerCornerRadius)
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Chat.composerCornerRadius, style: .continuous)
                .strokeBorder(AppTheme.brandAccent.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var detailText: String {
        var parts = [run.structure.displayName, "Iteration \(run.currentIteration)/\(run.maxIterations)"]
        if let stopReason = run.stopReason, !run.isActive {
            parts.append("Stop reason: \(stopReason.displayName)")
        } else if let latest = run.iterations.last?.summary, !latest.isEmpty {
            parts.append(latest)
        }
        return parts.joined(separator: " · ")
    }
}

struct PiAgentLoopDetailsSheet: View {
    let run: LoopRun
    let onRevealArtifacts: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Loop Details")
                        .font(.title2.weight(.bold))
                    Text("\(run.structure.displayName) · \(run.status.displayName) · Iteration \(run.currentIteration)/\(run.maxIterations)")
                        .font(AppTheme.Font.footnote)
                        .foregroundStyle(AppTheme.mutedText)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(run.goal)
                        .font(AppTheme.Font.body)
                        .foregroundStyle(.primary)
                    if let stopReason = run.stopReason {
                        detailRow("Stop reason", stopReason.displayName)
                    }
                    ForEach(run.iterations) { iteration in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Iteration \(iteration.index)")
                                .font(AppTheme.Font.body.weight(.semibold))
                            Text(iteration.summary)
                                .font(AppTheme.Font.footnote)
                                .foregroundStyle(.secondary)
                            if let checkerResult = iteration.checkerResult {
                                detailRow("Checker", checkerResult.displayName)
                            }
                            if let validation = iteration.validationResult {
                                detailRow("Validation", validation.didPass ? "Passed" : "Failed")
                            }
                            if !iteration.artifacts.isEmpty {
                                detailRow("Artifacts", iteration.artifacts.map(\.filename).joined(separator: ", "))
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.panelFill.opacity(0.5)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                if let onRevealArtifacts {
                    Button("Reveal Artifacts", action: onRevealArtifacts)
                }
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 560, height: 460)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label + ":")
                .font(AppTheme.Font.caption.weight(.semibold))
                .foregroundStyle(AppTheme.mutedText)
            Text(value)
                .font(AppTheme.Font.caption)
                .foregroundStyle(.secondary)
        }
    }
}

