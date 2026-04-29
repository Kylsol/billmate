import SwiftUI

struct JoinGroupView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var groupsVM = GroupsViewModel()
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

                if let err = groupsVM.errorMessage {
                    Section {
                        Text(err).foregroundStyle(.red)
                    }
                }

                Section {
                    Button(groupsVM.isBusy ? "Joining..." : "Join Group") {
                        Task {
                            let ok = await groupsVM.joinGroup(appState: appState, inviteCode: inviteCode)
                            if ok {
                                onJoined()
                                dismiss()
                            }
                        }
                    }
                    .disabled(groupsVM.isBusy)
                }
            }
            .navigationTitle("Join Group")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
