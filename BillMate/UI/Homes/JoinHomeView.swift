import SwiftUI

struct JoinHomeView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var homesVM = HomesViewModel()
    @State private var inviteCode: String = ""

    let onJoined: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Invite") {
                    TextField("Invite code", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                if let err = homesVM.errorMessage {
                    Section {
                        Text(err).foregroundStyle(.red)
                    }
                }

                Section {
                    Button(homesVM.isBusy ? "Joining..." : "Join Home") {
                        Task {
                            let ok = await homesVM.joinHome(appState: appState, inviteCode: inviteCode)
                            if ok {
                                onJoined()
                                dismiss()
                            }
                        }
                    }
                    .disabled(homesVM.isBusy)
                }
            }
            .navigationTitle("Join Home")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
