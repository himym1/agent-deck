import SwiftUI

struct LoopNumericStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    @State private var text: String
    @FocusState private var isTextFieldFocused: Bool

    init(value: Binding<Int>, range: ClosedRange<Int>) {
        _value = value
        self.range = range
        _text = State(initialValue: String(Self.clamped(value.wrappedValue, to: range)))
    }

    var body: some View {
        HStack(spacing: 0) {
            TextField("", text: $text)
                .font(AppTheme.Font.body.monospacedDigit())
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .frame(width: 34)
                .focused($isTextFieldFocused)
                .onSubmit(commitText)

            Divider()
                .frame(height: 24)

            VStack(spacing: 0) {
                stepButton(systemName: "chevron.up", delta: 1)
                Divider()
                    .frame(width: 18)
                stepButton(systemName: "chevron.down", delta: -1)
            }
            .frame(width: 24)
        }
        .frame(height: 28)
        .background(AppTheme.textContentFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(AppTheme.contentStroke, lineWidth: 1)
        }
        .onChange(of: text) { _, newValue in
            updateValue(from: newValue)
        }
        .onChange(of: value) { _, newValue in
            let clamped = Self.clamped(newValue, to: range)
            if clamped != newValue {
                value = clamped
            }
            let current = String(clamped)
            if text != current {
                text = current
            }
        }
        .onChange(of: isTextFieldFocused) { _, focused in
            if !focused {
                commitText()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Value")
        .accessibilityValue(String(value))
    }

    private func stepButton(systemName: String, delta: Int) -> some View {
        Button {
            setValue(value + delta)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 8, weight: .bold))
                .frame(width: 24, height: 13)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.mutedText)
        .disabled(delta > 0 ? value >= range.upperBound : value <= range.lowerBound)
    }

    private func updateValue(from newValue: String) {
        guard let parsed = Int(newValue.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        setValue(parsed, updateText: false)
    }

    private func commitText() {
        guard let parsed = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            text = String(value)
            return
        }
        setValue(parsed)
    }

    private func setValue(_ newValue: Int, updateText: Bool = true) {
        let clamped = Self.clamped(newValue, to: range)
        if value != clamped {
            value = clamped
        }
        if updateText || newValue != clamped {
            let current = String(clamped)
            if text != current {
                text = current
            }
        }
    }

    private static func clamped(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
