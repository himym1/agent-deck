import SwiftUI
import AppKit

struct PiAgentLoopControlBar: View {
    let run: LoopRun
    let onOpenDetails: () -> Void
    let onStop: () -> Void
    let onRetry: (() -> Void)?
    let onSave: (() -> Void)?
    let onRevealArtifacts: (() -> Void)?
    let onRevealWorktree: (() -> Void)?
    let onApplyWorktree: (() -> Void)?
    let onDiscardWorktree: (() -> Void)?
    let onApproveHumanApproval: (() -> Void)?
    let onRejectHumanApproval: (() -> Void)?

    var body: some View {
        AppRowCard {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "infinity")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(AppTheme.brandAccent)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(AppTheme.brandAccent.opacity(0.14)))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(titleText)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(AppLocalization.string(run.displayStatusName, default: run.displayStatusName))
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

                actions
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 10) {
            if canResolveHumanApproval || run.isActive {
                HStack(spacing: 8) {
                    if canResolveHumanApproval {
                        Button(AppLocalization.string("Approve", default: "Approve"), action: { onApproveHumanApproval?() })
                            .appPrimaryButton()
                            .controlSize(.small)
                            .disabled(onApproveHumanApproval == nil)
                        Button(AppLocalization.string("Reject", default: "Reject"), role: .destructive, action: { onRejectHumanApproval?() })
                            .appDestructiveButton()
                            .controlSize(.small)
                            .disabled(onRejectHumanApproval == nil)
                    }
                    if run.isActive {
                        Button(AppLocalization.string("Stop", default: "Stop"), role: .destructive, action: onStop)
                            .appDestructiveButton()
                            .controlSize(.small)
                    }
                }
            }

            if canResolveHumanApproval || run.isActive {
                actionDivider
            }

            HStack(spacing: 8) {
                Button(AppLocalization.string("Details", default: "Details"), action: onOpenDetails)
                    .appSmallSecondaryButton()
                if canRetry {
                    Button(AppLocalization.string("Retry Failed Iteration", default: "Retry Failed Iteration"), action: { onRetry?() })
                        .appSmallSecondaryButton()
                        .disabled(onRetry == nil)
                }
                if canSave {
                    Button(AppLocalization.string("Save Loop", default: "Save Loop"), action: { onSave?() })
                        .appSmallSecondaryButton()
                        .disabled(onSave == nil)
                }
            }

            if canRevealArtifacts || canRevealWorktree || canApplyWorktree || canDiscardWorktree {
                actionDivider
                HStack(spacing: 8) {
                    if canRevealArtifacts {
                        Button(AppLocalization.string("Reveal Artifacts", default: "Reveal Artifacts"), action: { onRevealArtifacts?() })
                            .appSmallSecondaryButton()
                            .disabled(onRevealArtifacts == nil)
                    }
                    if canRevealWorktree {
                        Button(AppLocalization.string("Reveal Worktree", default: "Reveal Worktree"), action: { onRevealWorktree?() })
                            .appSmallSecondaryButton()
                            .disabled(onRevealWorktree == nil)
                    }
                    if canApplyWorktree {
                        Button(AppLocalization.string("Apply Worktree", default: "Apply Worktree"), action: { onApplyWorktree?() })
                            .appSmallSecondaryButton()
                            .disabled(onApplyWorktree == nil)
                    }
                    if canDiscardWorktree {
                        Button(AppLocalization.string("Discard Worktree", default: "Discard Worktree"), role: .destructive, action: { onDiscardWorktree?() })
                            .appDestructiveButton()
                            .controlSize(.small)
                            .disabled(onDiscardWorktree == nil)
                    }
                }
            }
        }
    }

    private var actionDivider: some View {
        Rectangle()
            .fill(AppTheme.hairlineStroke)
            .frame(width: 1, height: 20)
    }

    private var titleText: String {
        run.isActive ? AppLocalization.string("Loop running", default: "Loop running") : AppLocalization.format("Loop: %@", default: "Loop: %@", AppLocalization.string(run.structure.displayName, default: run.structure.displayName))
    }

    private var detailText: String {
        var parts = [AppLocalization.string(run.structure.displayName, default: run.structure.displayName), run.iterationProgressText]
        if let stopReason = run.stopReason, !run.isActive {
            parts.append(AppLocalization.format("Stop reason: %@", default: "Stop reason: %@", AppLocalization.string(stopReason.displayName, default: stopReason.displayName)))
        } else if let latest = run.iterations.last?.summary, !latest.isEmpty {
            parts.append(trimSummary(latest))
        }
        return parts.joined(separator: " · ")
    }

    private func trimSummary(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 140 else { return trimmed }
        return String(trimmed.prefix(140)) + "…"
    }

    private var canRetry: Bool { !run.isActive && run.status == .failed && !run.presentsGoalNotMetOutcome }
    private var canSave: Bool { !run.isActive }
    private var canRevealArtifacts: Bool { run.artifactDirectoryPath != nil }

    private var canRevealWorktree: Bool {
        run.writeTarget == .newWorktree && hasWorktree && !worktreeAlreadyHandled
    }

    private var canApplyWorktree: Bool {
        canOperateOnWorktree
    }

    private var canDiscardWorktree: Bool {
        canOperateOnWorktree
    }

    private var canResolveHumanApproval: Bool {
        run.structure == .humanApproval && run.status == .stopped && run.stopReason == .humanInputRequired
    }

    private var canOperateOnWorktree: Bool {
        run.writeTarget == .newWorktree && !run.isActive && hasWorktree && !worktreeAlreadyHandled
    }

    private var hasWorktree: Bool {
        guard let worktreeURL else { return false }
        return FileManager.default.fileExists(atPath: worktreeURL.path)
    }

    private var worktreeAlreadyHandled: Bool {
        run.worktreeState == .applied || run.worktreeState == .discarded || hasAppliedMarker || hasDiscardedMarker
    }

    private var worktreeURL: URL? {
        run.artifactDirectoryPath.map { URL(fileURLWithPath: $0).appendingPathComponent("worktree", isDirectory: true) }
    }

    private var hasAppliedMarker: Bool {
        guard let artifactDirectoryURL else { return false }
        return FileManager.default.fileExists(atPath: artifactDirectoryURL.appendingPathComponent("worktree.applied").path)
    }

    private var hasDiscardedMarker: Bool {
        guard let artifactDirectoryURL else { return false }
        return FileManager.default.fileExists(atPath: artifactDirectoryURL.appendingPathComponent("worktree.discarded").path)
    }

    private var artifactDirectoryURL: URL? {
        run.artifactDirectoryPath.map { URL(fileURLWithPath: $0) }
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
                    Text(AppLocalization.string("Loop Details", default: "Loop Details"))
                        .font(.title2.weight(.bold))
                    Text(AppLocalization.format("%@ · %@ · %@", default: "%@ · %@ · %@", AppLocalization.string(run.structure.displayName, default: run.structure.displayName), AppLocalization.string(run.displayStatusName, default: run.displayStatusName), run.iterationProgressText))
                        .font(AppTheme.Font.footnote)
                        .foregroundStyle(AppTheme.mutedText)
                }
                Spacer()
                Button(AppLocalization.string("Done", default: "Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(run.goal)
                        .font(AppTheme.Font.body)
                        .foregroundStyle(.primary)
                    if let stopReason = run.stopReason {
                        detailRow("Stop reason", AppLocalization.string(stopReason.displayName, default: stopReason.displayName))
                    }
                    ForEach(run.iterations) { iteration in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(AppLocalization.format("Iteration %lld", default: "Iteration %lld", Int64(iteration.index)))
                                .font(AppTheme.Font.body.weight(.semibold))
                            Text(iteration.summary)
                                .font(AppTheme.Font.footnote)
                                .foregroundStyle(.secondary)
                            if let checkerResult = iteration.checkerResult {
                                detailRow("Checker", AppLocalization.string(checkerResult.displayName, default: checkerResult.displayName))
                            }
                            if let validation = iteration.validationResult {
                                detailRow("Validation", AppLocalization.string(validation.didPass ? "Passed" : "Failed", default: validation.didPass ? "Passed" : "Failed"))
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
                    Button(AppLocalization.string("Reveal Artifacts", default: "Reveal Artifacts"), action: onRevealArtifacts)
                }
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 560, height: 460)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(AppLocalization.string(label, default: label) + ":")
                .font(AppTheme.Font.caption.weight(.semibold))
                .foregroundStyle(AppTheme.mutedText)
            Text(value)
                .font(AppTheme.Font.caption)
                .foregroundStyle(.secondary)
        }
    }
}
