//
//  GroupSettingsView.swift
//  BillMate
//
//  Created by Kyle Solomons on 3/1/26.
//

import SwiftUI
import FirebaseFirestore

struct GroupSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var groupsVM: GroupsViewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - Local screen state (keep this view self-contained)

    @State private var members: [MemberDoc] = []
    @State private var isBusy: Bool = false
    @State private var localError: String?

    // Confirm dialogs / alerts
    @State private var confirmRemoveUid: String?
    @State private var confirmRemoveName: String = ""

    @State private var confirmLeave = false
    @State private var confirmDelete = false
    
    @State private var groupName: String = ""
    
    @State private var memberToRemove: MemberDoc?

    var body: some View {
        NavigationStack {
            List {

                // MARK: - Error Banner (nicer UI)
                if let err = localError ?? groupsVM.errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 4)
                    }
                }
                
                if appState.activeRole == .admin {
                    Section("Group Name") {
                        TextField("Group name", text: $groupName)

                        Button(isBusy ? "Saving..." : "Save Name") {
                            Task { await renameGroup() }
                        }
                        .disabled(
                            isBusy ||
                            groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            groupName.trimmingCharacters(in: .whitespacesAndNewlines) ==
                            (appState.activeGroup?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                        )
                    }
                }

                // MARK: - Members
                Section("Members") {
                    if members.isEmpty {
                        Text("No members found.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(members, id: \.uid) { m in
                            memberRow(m)
                        }
                    }
                }

                // MARK: - Danger Zone
                Section("Group") {

                    // Leave Group (everyone)
                    Button(role: .destructive) {
                        confirmLeave = true
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Leave Group")
                        }
                    }
                    .disabled(isBusy)

                    // Delete Group (admin only)
                    if appState.activeRole == .admin {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Group")
                            }
                        }
                        .disabled(isBusy)
                    }
                }
            }
            .navigationTitle("Group Settings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .disabled(isBusy)

            // Load members on open
            .task {
                await reloadMembers()
            }
            
            .onChange(of: appState.activeRole) { _, newRole in
                if newRole != .admin {
                    dismiss()
                }
            }

            // Confirm remove member alert
            .alert("Remove Member?", isPresented: Binding(
                get: { memberToRemove != nil },
                set: { if !$0 { memberToRemove = nil } }
            )) {
                Button("Cancel", role: .cancel) { memberToRemove = nil }
                Button("Remove", role: .destructive) {
                    guard let uid = memberToRemove?.uid else { return }
                    Task { await removeMember(uid: uid) }
                }
            } message: {
                if let member = memberToRemove {
                    Text("Remove \(displayName(for: member)) from this group?")
                }
            }

            // Confirm leave
            .confirmationDialog(
                "Leave Group?",
                isPresented: $confirmLeave,
                titleVisibility: .visible
            ) {
                Button("Leave Group", role: .destructive) {
                    Task { await leaveGroup() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You will lose access unless invited again. If you are the only admin, promote someone else first.")
            }

            // Confirm delete
            .confirmationDialog(
                "Delete Group?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Move to Recycle Bin (30 days)", role: .destructive) {
                    Task { await deleteGroup() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This group will be recoverable for 30 days. It will expire automatically after that.")
            }
        }
    }

    // MARK: - Member Row

    @ViewBuilder
    private func memberRow(_ m: MemberDoc) -> some View {
        let display = displayName(for: m)

        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(display)
                    .font(.headline)

                Text(m.role.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Only admins can manage users
            if appState.activeRole == .admin {
                Menu {
                    if m.role != .admin {
                        Button("Promote to Admin") {
                            Task { await setRole(uid: m.uid, role: .admin) }
                        }
                    } else {
                        Button("Revoke Admin") {
                            Task { await setRole(uid: m.uid, role: .resident) }
                        }
                    }

                    Divider()

                    Button("Remove from Group", role: .destructive) {
                        memberToRemove = m
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .padding(.leading, 8)
                }
            }
        }
    }

    // MARK: - Actions
    
    private func renameGroup() async {
        localError = nil

        guard appState.activeRole == .admin else {
            localError = "Only admins can rename a group."
            return
        }

        guard let groupId = appState.activeGroup?.id else { return }

        let trimmed = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            localError = "Group name is required."
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            try await FirestoreService.groupRef(groupId).updateData([
                "name": trimmed
            ])

            if var activeGroup = appState.activeGroup {
                activeGroup.name = trimmed
                appState.activeGroup = activeGroup
            }
        } catch {
            localError = error.localizedDescription
        }
    }

    private func reloadMembers() async {
        localError = nil
        guard let groupId = appState.activeGroup?.id else { return }

        if groupName.isEmpty {
            groupName = appState.activeGroup?.name ?? ""
        }
        
        isBusy = true
        defer { isBusy = false }

        // Everyone can view members; admin required only for actions
        let loaded = await groupsVM.loadMembers(groupId: groupId)
        members = loaded
    }

    private func setRole(uid: String, role: MemberRole) async {
        localError = nil
        guard appState.activeRole == .admin else {
            localError = "Only admins can change roles."
            return
        }
        guard let groupId = appState.activeGroup?.id else { return }

        isBusy = true
        defer { isBusy = false }

        do {
            try await groupsVM.setMemberRole(appState: appState, groupId: groupId, memberUid: uid, role: role)
            await reloadMembers()

            if appState.activeRole != .admin {
                dismiss()
            }
        } catch {
            localError = error.localizedDescription
        }
    }

    private func removeMember(uid: String) async {
        localError = nil
        guard appState.activeRole == .admin else {
            localError = "Only admins can remove members."
            confirmRemoveUid = nil
            return
        }
        guard let groupId = appState.activeGroup?.id else { return }

        isBusy = true
        defer { isBusy = false }

        do {
            try await groupsVM.removeMember(appState: appState, groupId: groupId, memberUid: uid)
            confirmRemoveUid = nil
            await reloadMembers()
        } catch {
            localError = error.localizedDescription
        }
    }

    private func leaveGroup() async {
        localError = nil
        guard let groupId = appState.activeGroup?.id else { return }

        isBusy = true
        defer { isBusy = false }

        let ok = await groupsVM.leaveGroupSafely(appState: appState, groupId: groupId)
        if ok {
            dismiss()
        } else {
            // groupsVM.errorMessage already set; keep this for consistency
            localError = groupsVM.errorMessage
        }
    }

    private func deleteGroup() async {
        localError = nil
        guard appState.activeRole == .admin else {
            localError = "Only admins can delete a group."
            return
        }
        guard let groupId = appState.activeGroup?.id else { return }

        isBusy = true
        defer { isBusy = false }

        let ok = await groupsVM.softDeleteGroup(appState: appState, groupId: groupId)
        if ok {
            dismiss()
        } else {
            localError = groupsVM.errorMessage
        }
    }

    // MARK: - Helpers

    private func displayName(for m: MemberDoc) -> String {
        let trimmed = (m.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let email = m.email, !email.isEmpty { return email }
        return m.uid
    }
}
