import SwiftUI

/// Native standalone utility; the scene keeps one window and clears output when closed.
struct PasswordGeneratorWindow: View {
    @StateObject private var viewModel: PasswordGeneratorViewModel

    init(provider: RandomnessProvider) {
        _viewModel = StateObject(wrappedValue: PasswordGeneratorViewModel(provider: provider))
    }

    var body: some View {
        PasswordGeneratorView(viewModel: viewModel)
    }
}

/// Shared controls, with an optional target field for the editor's Use action.
struct PasswordGeneratorView: View {

    @ObservedObject var viewModel: PasswordGeneratorViewModel
    var targetValue: Binding<String?>? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.headerGap) {

            // Mode picker
            Picker("Mode", selection: $viewModel.mode) {
                Text("Password").tag(PasswordGeneratorConfig.Mode.password)
                Text("Passphrase").tag(PasswordGeneratorConfig.Mode.passphrase)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(AccessibilityID.Generator.modePicker)

            Divider()

            // Mode-specific controls
            switch viewModel.mode {
            case .password:
                passwordControls
            case .passphrase:
                passphraseControls
            }

            Divider()

            // Preview area
            previewArea

            Divider()

            // Action row
            actionRow
        }
        .padding(Spacing.pageMargin)
        .frame(width: 320)
        .onAppear {
            if viewModel.generatedValue.isEmpty { viewModel.generate() }
        }
        .onDisappear { viewModel.clearGeneratedValue() }
    }

    // MARK: - Password controls

    @ViewBuilder
    private var passwordControls: some View {
        VStack(alignment: .leading, spacing: Spacing.headerGap) {
            HStack {
                Text("Length: \(viewModel.length)")
                    .font(Typography.fieldLabel)
                Spacer()
            }
            Slider(
                value: Binding(
                    get: { Double(viewModel.length) },
                    set: { viewModel.length = Int($0) }
                ),
                in: Double(PasswordGeneratorConfig.passwordLengthRange.lowerBound)...Double(PasswordGeneratorConfig.passwordLengthRange.upperBound),
                step: 1
            )
            .accessibilityLabel("Password length")
            .accessibilityValue(String(viewModel.length))
            .accessibilityIdentifier(AccessibilityID.Generator.lengthSlider)

            Toggle("Uppercase (A–Z)", isOn: $viewModel.includeUppercase)
                .disabled(isLastEnabledSet(\.includeUppercase))
                .accessibilityIdentifier(AccessibilityID.Generator.uppercaseToggle)
            Toggle("Lowercase (a–z)", isOn: $viewModel.includeLowercase)
                .disabled(isLastEnabledSet(\.includeLowercase))
                .accessibilityIdentifier(AccessibilityID.Generator.lowercaseToggle)
            Toggle("Digits (0–9)", isOn: $viewModel.includeDigits)
                .disabled(isLastEnabledSet(\.includeDigits))
                .accessibilityIdentifier(AccessibilityID.Generator.digitsToggle)
            Toggle("Symbols (!@#$…)", isOn: $viewModel.includeSymbols)
                .disabled(isLastEnabledSet(\.includeSymbols))
                .accessibilityIdentifier(AccessibilityID.Generator.symbolsToggle)
            Toggle("Avoid ambiguous characters", isOn: $viewModel.avoidAmbiguous)
                .accessibilityIdentifier(AccessibilityID.Generator.avoidAmbiguousToggle)
        }
    }

    // MARK: - Passphrase controls

    @ViewBuilder
    private var passphraseControls: some View {
        VStack(alignment: .leading, spacing: Spacing.headerGap) {
            Stepper("Words: \(viewModel.wordCount)", value: $viewModel.wordCount, in: 3...10)
                .accessibilityIdentifier(AccessibilityID.Generator.wordCountStepper)
            HStack {
                Text("Separator")
                    .font(Typography.fieldLabel)
                TextField("Separator", text: $viewModel.separator)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .accessibilityIdentifier(AccessibilityID.Generator.separatorField)
            }
            Toggle("Capitalize each word", isOn: $viewModel.capitalize)
                .accessibilityIdentifier(AccessibilityID.Generator.capitalizeToggle)
            Toggle("Include number", isOn: $viewModel.includeNumber)
                .accessibilityIdentifier(AccessibilityID.Generator.includeNumberToggle)
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewArea: some View {
        HStack {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(Typography.fieldValue)
                    .foregroundStyle(.red)
            } else if viewModel.generatedValue.isEmpty {
                Text("Generate a new password to continue.")
                    .font(Typography.fieldValue)
                    .foregroundStyle(.secondary)
            } else {
                Text(viewModel.generatedValue)
                    .font(Typography.fieldValue.monospaced())
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    // Recreate the native selectable text so its accessibility value
                    // tracks regeneration and mode changes on macOS.
                    .id(viewModel.generatedValue)
                    .accessibilityIdentifier(AccessibilityID.Generator.preview)
            }
            Spacer()
            Button {
                viewModel.generate()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Generate new")
            .accessibilityLabel("Generate new password")
            .accessibilityIdentifier(AccessibilityID.Generator.refreshButton)
        }
        .frame(minHeight: 40)
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionRow: some View {
        HStack {
            Button(viewModel.hasCopied ? "Copied" : "Copy") {
                viewModel.copyToClipboard()
            }
            .disabled(viewModel.generatedValue.isEmpty || viewModel.errorMessage != nil)
            .accessibilityHint("Copies to clipboard")
            .accessibilityIdentifier(AccessibilityID.Generator.copyButton)

            Spacer()

            if let targetValue {
                Button(viewModel.mode == .password ? "Use Password" : "Use Passphrase") {
                    targetValue.wrappedValue = viewModel.generatedValue
                    dismiss()
                }
                .disabled(viewModel.generatedValue.isEmpty || viewModel.errorMessage != nil)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityID.Generator.useButton)
            } else {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    // MARK: - Helpers

    /// Returns `true` if the given toggle is the last enabled character set.
    private func isLastEnabledSet(_ keyPath: KeyPath<PasswordGeneratorViewModel, Bool>) -> Bool {
        let enabled = [
            viewModel.includeUppercase,
            viewModel.includeLowercase,
            viewModel.includeDigits,
            viewModel.includeSymbols
        ].filter { $0 }.count
        return enabled == 1 && viewModel[keyPath: keyPath]
    }
}
