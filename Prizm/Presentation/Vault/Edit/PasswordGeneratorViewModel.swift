import Combine
import SwiftUI

/// Shared generator state for the editor popover and standalone window.
/// Only options persist; the generated value expires and is cleared on dismissal.
@MainActor
final class PasswordGeneratorViewModel: ObservableObject {

    // MARK: - Published config properties

    @Published var mode: PasswordGeneratorConfig.Mode = .password { didSet { generate() } }
    @Published var length: Int = 16 { didSet { generate() } }
    @Published var includeUppercase: Bool = true { didSet { generate() } }
    @Published var includeLowercase: Bool = true { didSet { generate() } }
    @Published var includeDigits: Bool = true { didSet { generate() } }
    @Published var includeSymbols: Bool = true { didSet { generate() } }
    @Published var avoidAmbiguous: Bool = false { didSet { generate() } }
    @Published var wordCount: Int = 6 { didSet { generate() } }
    @Published var separator: String = "-" { didSet { generate() } }
    @Published var capitalize: Bool = false { didSet { generate() } }
    @Published var includeNumber: Bool = false { didSet { generate() } }

    // MARK: - Output

    @Published private(set) var generatedValue: String = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasCopied = false

    // MARK: - Dependencies

    private let provider: RandomnessProvider
    private let generator = PasswordGenerator()
    private let defaults: UserDefaults
    private let pasteboard: NSPasteboard
    private let sensitiveValueTimeout: Duration
    private var previewClearTask: Task<Void, Never>?
    private var isInitializing = true

    // MARK: - Init

    init(
        provider: RandomnessProvider,
        defaults: UserDefaults = .standard,
        pasteboard: NSPasteboard = .general,
        sensitiveValueTimeout: Duration = .seconds(30)
    ) {
        self.provider = provider
        self.defaults = defaults
        self.pasteboard = pasteboard
        self.sensitiveValueTimeout = sensitiveValueTimeout
        let config = PasswordGeneratorConfig.load(from: defaults)
        self.mode = config.mode
        self.length = config.length
        self.includeUppercase = config.includeUppercase
        self.includeLowercase = config.includeLowercase
        self.includeDigits = config.includeDigits
        self.includeSymbols = config.includeSymbols
        self.avoidAmbiguous = config.avoidAmbiguous
        self.wordCount = config.wordCount
        self.separator = config.separator
        self.capitalize = config.capitalize
        self.includeNumber = config.includeNumber
        isInitializing = false
        generate()
    }

    deinit {
        previewClearTask?.cancel()
    }

    // MARK: - Actions

    func generate() {
        guard !isInitializing else { return }
        previewClearTask?.cancel()
        hasCopied = false
        do {
            let config = currentConfig()
            switch mode {
            case .password:
                generatedValue = try generator.generatePassword(config: config, provider: provider)
            case .passphrase:
                generatedValue = try generator.generatePassphrase(config: config, provider: provider)
            }
            errorMessage = nil
            config.save(to: defaults)
            previewClearTask = Task { [weak self, sensitiveValueTimeout] in
                do {
                    try await Task.sleep(for: sensitiveValueTimeout)
                    self?.clearGeneratedValue()
                } catch is CancellationError {
                    // A new value or dismissal replaces this preview's timeout.
                } catch {
                    self?.clearGeneratedValue()
                }
            }
        } catch {
            errorMessage = String(localized: "Generation failed: \(error.localizedDescription)")
            generatedValue = ""
        }
    }

    func clearGeneratedValue() {
        previewClearTask?.cancel()
        previewClearTask = nil
        generatedValue = ""
        hasCopied = false
    }

    func copyToClipboard() {
        guard !generatedValue.isEmpty, errorMessage == nil else { return }
        VaultBrowserViewModel.writeConcealed(generatedValue, to: pasteboard)
        hasCopied = true
        let changeCount = pasteboard.changeCount

        // Cleanup outlives the window without retaining plaintext or its model.
        // changeCount also protects newer clipboard contents, even identical text.
        Task { [pasteboard, changeCount, sensitiveValueTimeout] in
            do {
                try await Task.sleep(for: sensitiveValueTimeout)
                if pasteboard.changeCount == changeCount {
                    pasteboard.clearContents()
                }
            } catch is CancellationError {
                // This independent task is not cancelled when the generator closes.
            } catch {
                if pasteboard.changeCount == changeCount {
                    pasteboard.clearContents()
                }
            }
        }
    }

    // MARK: - Private

    private func currentConfig() -> PasswordGeneratorConfig {
        var config = PasswordGeneratorConfig()
        config.mode = mode
        config.length = length
        config.includeUppercase = includeUppercase
        config.includeLowercase = includeLowercase
        config.includeDigits = includeDigits
        config.includeSymbols = includeSymbols
        config.avoidAmbiguous = avoidAmbiguous
        config.wordCount = wordCount
        config.separator = separator
        config.capitalize = capitalize
        config.includeNumber = includeNumber
        return config
    }
}
