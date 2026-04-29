import SwiftUI

struct CreateGroupView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var groupsVM = GroupsViewModel()

    @State private var groupName: String = ""
    @State private var createdInviteCode: String?

    let onDone: (String?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Group") {
                    TextField("Group name", text: $groupName)
                }

                if let code = createdInviteCode {
                    Section("Invite Code (auto-created)") {
                        Text(code)
                            .font(.system(.title2, design: .monospaced))
                        Text("Share this code so someone can join as a resident.")
                            .foregroundStyle(.secondary)
                    }
                }

                if let err = groupsVM.errorMessage {
                    Section {
                        Text(err).foregroundStyle(.red)
                    }
                }

                Section {
                    Button(groupsVM.isBusy ? "Creating..." : "Create") {
                        Task {
                            let code = await groupsVM.createGroup(appState: appState, name: groupName)
                            createdInviteCode = code
                            onDone(code)
                        }
                    }
                    .disabled(groupsVM.isBusy)
                }
            }
            .navigationTitle("Create Group")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
