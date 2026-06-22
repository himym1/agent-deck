import SwiftUI

struct LoopLaunchSheet: View {
    let session: PiAgentSessionRecord
    let activeRun: LoopRun?
    let onCancel: () -> Void
    let onLaunch: (LoopDraft, Bool) -> Void

    @State private var draft = LoopDraft()
    @State private var stopExistingActive = false

    private var trimmedGoal: String {
        draft.goal.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canLaunch: Bool {
        !trimmedGoal.isEmpty && (activeRun == nil || stopExistingActive)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Create Loop")
                    .font(.title2.bold())
                Text(session.title)
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(1)
            }

            if let activeRun {
                VStack(alignment: .leading, spacing: 8) {
                    Label("This transcript already has an active loop.", systemImage: "infinity")
                        .font(AppTheme.Font.body.weight(.semibold))
                    Text(activeRun.goal)
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(AppTheme.mutedText)
                        .lineLimit(2)
                    Toggle("Stop it and start this loop", isOn: $stopExistingActive)
                }
                .padding(12)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Form {
                Picker("Structure", selection: $draft.structure) {
                    ForEach(LoopStructureKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }

                Picker("Write Target", selection: $draft.writeTarget) {
                    ForEach(LoopWriteTarget.allCases) { target in
                        Text(target.displayName).tag(target)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Goal")
                    TextEditor(text: $draft.goal)
                        .font(AppTheme.Font.body)
                        .frame(minHeight: 96)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.secondary.opacity(0.25))
                        }
                }

                Stepper(value: $draft.maxIterations, in: 1...20) {
                    Text("Max iterations: \(draft.maxIterations)")
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Launch") {
                    onLaunch(draft, stopExistingActive)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canLaunch)
            }
        }
        .padding(22)
        .frame(width: 460)
    }
}
