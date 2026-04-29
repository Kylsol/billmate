import SwiftUI

struct GroupListView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = GroupsViewModel()

    // MARK: - Modal / Navigation State

    @State private var showCreate = false
    @State private var showJoin = false

    /// Shows the recycle bin screen (deleted groups + deleted transactions later)
    @State private var showRecycleBin = false

    /// When set, we show a confirmation dialog to soft-delete this group
    @State private var groupPendingDelete: GroupDoc?

    /// When set, we show a confirmation dialog to leave this group
    @State private var groupPendingLeave: GroupDoc?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {

                // MARK: - Error Banner

                if let err = vm.errorMessage {
                    Text(err)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // MARK: - Groups List

                List {
                    Section("Your Groups") {
                        if vm.groups.isEmpty {
                            Text("No groups yet. Create one or join with an invite code.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(vm.groups) { group in
                                Button {
                                    Task { await select(group) }
                                } label: {
                                    HStack {
                                        Text(group.name)
                                        Spacer()
                                        if appState.activeGroup?.id == group.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                }
                                // MARK: - Swipe Actions (Delete / Leave)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {

                                    // Leave group is available to everyone (resident + admin)
                                    Button(role: .destructive) {
                                        groupPendingLeave = group
                                    } label: {
                                        Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
                                    }

                                    // Only admins can delete the group (soft delete)
                                    if appState.activeRole == .admin {
                                        Button(role: .destructive) {
                                            groupPendingDelete = group
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)

                // MARK: - Bottom Actions (Create / Join)

                HStack(spacing: 12) {
                    Button("Create Group") { showCreate = true }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.borderedProminent)

                    Button("Join Group") { showJoin = true }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            .navigationTitle("Groups")

            // MARK: - Toolbar

            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showRecycleBin = true
                        } label: {
                            Label("Recycle Bin", systemImage: "trash")
                        }

                        Divider()

                        Button(role: .destructive) {
                            appState.signOut()
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showRecycleBin) {
                RecycleBinView()
                    .environmentObject(appState)
            }

            // MARK: - Confirmation: Soft Delete Group (Admin only)

            .confirmationDialog(
                "Delete Group?",
                isPresented: .constant(groupPendingDelete != nil),
                titleVisibility: .visible
            ) {
                Button("Move to Recycle Bin (30 days)", role: .destructive) {
                    guard let group = groupPendingDelete, let groupId = group.id else { return }
                    groupPendingDelete = nil

                    Task {
                        // Soft delete: hides from the groups list, recoverable for 30 days
                        _ = await vm.softDeleteGroup(appState: appState, groupId: groupId)
                    }
                }
                Button("Cancel", role: .cancel) {
                    groupPendingDelete = nil
                }
            } message: {
                Text("This group will be recoverable for 30 days. It will expire automatically after that.")
            }

            // MARK: - Confirmation: Leave Group (Everyone)

            .confirmationDialog(
                "Leave Group?",
                isPresented: .constant(groupPendingLeave != nil),
                titleVisibility: .visible
            ) {
                Button("Leave Group", role: .destructive) {
                    guard let group = groupPendingLeave, let groupId = group.id else { return }
                    groupPendingLeave = nil

                    Task {
                        // Leave: removes your membership only (group remains for others)
                        _ = await vm.leaveGroup(appState: appState, groupId: groupId)
                    }
                }
                Button("Cancel", role: .cancel) {
                    groupPendingLeave = nil
                }
            } message: {
                Text("You will lose access to this group unless someone invites you again.")
            }

            // MARK: - Sheets

            .sheet(isPresented: $showCreate) {
                CreateGroupView { inviteCode in
                    if inviteCode != nil {
                        Task { await refreshAndAutoSelect() }
                    }
                    showCreate = false
                }
                .environmentObject(appState)
            }
            .sheet(isPresented: $showJoin) {
                JoinGroupView {
                    Task { await refreshAndAutoSelect() }
                    showJoin = false
                }
                .environmentObject(appState)
            }

            // MARK: - Recycle Bin Screen

            .sheet(isPresented: $showRecycleBin) {
                RecycleBinView()
                    .environmentObject(appState)
            }

            // MARK: - Initial Load

            .task {
                await refreshAndAutoSelect()
            }
        }
    }

    // MARK: - Actions

    /// Reloads the user's active groups from Firestore.
    private func refreshAndAutoSelect() async {
        guard let uid = appState.authUser?.uid else { return }
        await vm.loadGroups(for: uid)
    }

    /// Selects a group and loads the user's role for that group into AppState.
    private func select(_ group: GroupDoc) async {
        guard let uid = appState.authUser?.uid,
              let groupId = group.id else { return }
        await vm.selectGroup(appState: appState, uid: uid, groupId: groupId)
    }
}
