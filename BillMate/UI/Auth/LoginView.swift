import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel

    private enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign In"
        case create = "Create Account"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .signIn
    @State private var didSubmitCreate = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { _, newMode in
                        // reset create-only validation when switching modes
                        didSubmitCreate = false
                        authVM.errorMessage = nil
                        if newMode == .signIn {
                            authVM.name = "" // don’t carry name into sign-in
                        }
                    }
                }

                Section("Account") {
                    if mode == .create {
                        TextField("Name", text: $authVM.name)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }

                    TextField("Email", text: $authVM.email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $authVM.password)
                }

                // only show "Name is required" after user taps Create Account
                if mode == .create, didSubmitCreate,
                   authVM.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        Text("Name is required.")
                            .foregroundStyle(.red)
                    }
                } else if let err = authVM.errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(authVM.isBusy ? "Working..." : mode.rawValue) {
                        Task {
                            switch mode {
                            case .signIn:
                                await authVM.signIn(appState: appState)
                                if authVM.errorMessage == nil {
                                    clearFields()
                                    hideKeyboard()
                                }

                            case .create:
                                didSubmitCreate = true

                                // Don’t even call Firebase if name is empty
                                if authVM.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    return
                                }

                                await authVM.createAccount(appState: appState)
                                if authVM.errorMessage == nil {
                                    clearFields()
                                    hideKeyboard()
                                    didSubmitCreate = false
                                    mode = .signIn // optional: go back to sign in
                                }
                            }
                        }
                    }
                    .disabled(authVM.isBusy)
                }
            }
            .navigationTitle("Bill Mate")
        }
    }

    private func clearFields() {
        authVM.email = ""
        authVM.password = ""
        authVM.name = ""
    }

    private func hideKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        #endif
    }
}
