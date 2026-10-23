import LocalAuthentication
import SwiftUI
import os.log

/// macOS Settings window (⌘,).
///
/// Always shows Security, with an explanation when biometric unlock is unavailable.
struct SettingsView: View {

    let authRepository: any AuthRepository
    @State private var lockPolicy: VaultLockPolicy
    @State private var isSavingLockPolicy = false
    @State private var lockPolicyError: String?

    init(authRepository: any AuthRepository) {
        self.authRepository = authRepository
        _lockPolicy = State(initialValue: authRepository.vaultLockPolicy)
    }

    private let logger = Logger(subsystem: "com.prizm", category: "SettingsView")

    private var deviceHasBiometrics: Bool {
        var error: NSError?
        let capable = LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        // Skip the routine device states (no hardware, no enrollment, no passcode set) —
        // those are normal, not failures, and would otherwise log on every render (#67).
        if let error, let laError = error as? LAError {
            switch laError.code {
            case .biometryNotAvailable, .biometryNotEnrolled, .passcodeNotSet:
                break
            default:
                logger.error("Biometric availability check failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return capable
    }

    var body: some View {
        Form {
            Section("Security") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Lock Vault", selection: Binding(
                        get: { lockPolicy },
                        set: { saveLockPolicy($0) }
                    )) {
                        Text("Never").tag(VaultLockPolicy.never)
                        Text("On restart").tag(VaultLockPolicy.onRestart)
                        Text("On reopen").tag(VaultLockPolicy.onReopen)
                    }
                    .disabled(isSavingLockPolicy)

                    Text(lockPolicyDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if deviceHasBiometrics {
                    BiometricUnlockToggle(authRepository: authRepository)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Biometric unlock unavailable", systemImage: "touchid")
                        Text("Biometric authentication is currently unavailable. If your Mac supports Touch ID, check that it is set up in System Settings and try again. You can still unlock your vault with your master password.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .padding()
        .alert("Could not save setting", isPresented: Binding(
            get: { lockPolicyError != nil },
            set: { if !$0 { lockPolicyError = nil } }
        )) {
            Button("OK") { lockPolicyError = nil }
        } message: {
            Text(lockPolicyError ?? "")
        }
    }

    private var lockPolicyDescription: String {
        switch lockPolicy {
        case .never:
            String(localized: "Keep the vault unlocked, even after restarting your Mac. You can still lock it manually.")
        case .onRestart:
            String(localized: "Lock after restarting your Mac. Restarting Bitvault keeps the vault unlocked.")
        case .onReopen:
            String(localized: "Lock after quitting and reopening Bitvault. Closing a window alone does not lock the vault.")
        }
    }

    private func saveLockPolicy(_ policy: VaultLockPolicy) {
        guard !isSavingLockPolicy, policy != lockPolicy else { return }
        isSavingLockPolicy = true
        Task {
            defer { isSavingLockPolicy = false }
            do {
                try await authRepository.setVaultLockPolicy(policy)
                lockPolicy = authRepository.vaultLockPolicy
            } catch {
                lockPolicyError = String(localized: "Could not save the vault lock setting. Please try again.")
            }
        }
    }
}
