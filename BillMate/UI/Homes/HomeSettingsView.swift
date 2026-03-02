//
//  HomeSettingsView.swift
//  BillMate
//
//  Created by Kyle Solomons on 3/1/26.
//

import SwiftUI

struct HomeSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var homesVM: HomesViewModel
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

    var body: some View {
        NavigationStack {
            List {

                // MARK: - Error Banner (nicer UI)
                if let err = localError ?? homesVM.errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 4)
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
                Section("Home") {

                    // Leave Home (everyone)
                    Button(role: .destructive) {
                        confirmLeave = true
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Leave Home")
                        }
                    }
                    .disabled(isBusy)

                    // Delete Home (admin only)
                    if appState.activeRole == .admin {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Home")
                            }
                        }
                        .disabled(isBusy)
                    }
                }
            }
            .navigationTitle("Home Settings")
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

            // Confirm remove member alert
            .alert("Remove Member?", isPresented: Binding(
                get: { confirmRemoveUid != nil },
                set: { if !$0 { confirmRemoveUid = nil } }
            )) {
                Button("Cancel", role: .cancel) { confirmRemoveUid = nil }
                Button("Remove", role: .destructive) {
                    guard let uid = confirmRemoveUid else { return }
                    Task { await removeMember(uid: uid) }
                }
            } message: {
                Text("Remove \(confirmRemoveName) from this home?")
            }

            // Confirm leave
            .confirmationDialog(
                "Leave Home?",
                isPresented: $confirmLeave,
                titleVisibility: .visible
            ) {
                Button("Leave Home", role: .destructive) {
                    Task { await leaveHome() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You will lose access unless invited again. If you are the only admin, promote someone else first.")
            }

            // Confirm delete
            .confirmationDialog(
                "Delete Home?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Move to Recycle Bin (30 days)", role: .destructive) {
                    Task { await deleteHome() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This home will be recoverable for 30 days. It will expire automatically after that.")
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

                    Button("Remove from Home", role: .destructive) {
                        confirmRemoveUid = m.uid
                        confirmRemoveName = display
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .padding(.leading, 8)
                }
            }
        }
    }

    // MARK: - Actions

    private func reloadMembers() async {
        localError = nil
        guard let homeId = appState.activeHome?.id else { return }

        isBusy = true
        defer { isBusy = false }

        // Everyone can view members; admin required only for actions
        let loaded = await homesVM.loadMembers(homeId: homeId)
        members = loaded
    }

    private func setRole(uid: String, role: MemberRole) async {
        localError = nil
        guard appState.activeRole == .admin else {
            localError = "Only admins can change roles."
            return
        }
        guard let homeId = appState.activeHome?.id else { return }

        isBusy = true
        defer { isBusy = false }

        do {
            try await homesVM.setMemberRole(homeId: homeId, memberUid: uid, role: role)
            await reloadMembers()
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
        guard let homeId = appState.activeHome?.id else { return }

        isBusy = true
        defer { isBusy = false }

        do {
            try await homesVM.removeMember(homeId: homeId, memberUid: uid)
            confirmRemoveUid = nil
            await reloadMembers()
        } catch {
            localError = error.localizedDescription
        }
    }

    private func leaveHome() async {
        localError = nil
        guard let homeId = appState.activeHome?.id else { return }

        isBusy = true
        defer { isBusy = false }

        let ok = await homesVM.leaveHomeSafely(appState: appState, homeId: homeId)
        if ok {
            dismiss()
        } else {
            // homesVM.errorMessage already set; keep this for consistency
            localError = homesVM.errorMessage
        }
    }

    private func deleteHome() async {
        localError = nil
        guard appState.activeRole == .admin else {
            localError = "Only admins can delete a home."
            return
        }
        guard let homeId = appState.activeHome?.id else { return }

        isBusy = true
        defer { isBusy = false }

        let ok = await homesVM.softDeleteHome(appState: appState, homeId: homeId)
        if ok {
            dismiss()
        } else {
            localError = homesVM.errorMessage
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
