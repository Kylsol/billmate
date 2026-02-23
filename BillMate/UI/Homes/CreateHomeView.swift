import SwiftUI

struct CreateHomeView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var homesVM = HomesViewModel()

    @State private var homeName: String = ""
    @State private var createdInviteCode: String?

    let onDone: (String?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Home") {
                    TextField("Home name", text: $homeName)
                }

                if let code = createdInviteCode {
                    Section("Invite Code (auto-created)") {
                        Text(code)
                            .font(.system(.title2, design: .monospaced))
                        Text("Share this code so someone can join as a resident.")
                            .foregroundStyle(.secondary)
                    }
                }

                if let err = homesVM.errorMessage {
                    Section {
                        Text(err).foregroundStyle(.red)
                    }
                }

                Section {
                    Button(homesVM.isBusy ? "Creating..." : "Create") {
                        Task {
                            let code = await homesVM.createHome(appState: appState, name: homeName)
                            createdInviteCode = code
                            onDone(code)
                        }
                    }
                    .disabled(homesVM.isBusy)
                }
            }
            .navigationTitle("Create Home")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
