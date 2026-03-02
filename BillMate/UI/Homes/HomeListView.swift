import SwiftUI

struct HomeListView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = HomesViewModel()

    // MARK: - Modal / Navigation State

    @State private var showCreate = false
    @State private var showJoin = false

    /// Shows the recycle bin screen (deleted homes + deleted transactions later)
    @State private var showRecycleBin = false

    /// When set, we show a confirmation dialog to soft-delete this home
    @State private var homePendingDelete: HomeDoc?

    /// When set, we show a confirmation dialog to leave this home
    @State private var homePendingLeave: HomeDoc?

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

                // MARK: - Homes List

                List {
                    Section("Your Homes") {
                        if vm.homes.isEmpty {
                            Text("No homes yet. Create one or join with an invite code.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(vm.homes) { home in
                                Button {
                                    Task { await select(home) }
                                } label: {
                                    HStack {
                                        Text(home.name)
                                        Spacer()
                                        if appState.activeHome?.id == home.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                }
                                // MARK: - Swipe Actions (Delete / Leave)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {

                                    // Leave home is available to everyone (resident + admin)
                                    Button(role: .destructive) {
                                        homePendingLeave = home
                                    } label: {
                                        Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
                                    }

                                    // Only admins can delete the home (soft delete)
                                    if appState.activeRole == .admin {
                                        Button(role: .destructive) {
                                            homePendingDelete = home
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
                    Button("Create Home") { showCreate = true }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.borderedProminent)

                    Button("Join Home") { showJoin = true }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            .navigationTitle("Homes")

            // MARK: - Toolbar

            .toolbar {
                // Recycle Bin button
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showRecycleBin = true
                    } label: {
                        Label("Recycle Bin", systemImage: "trash")
                    }
                }

                // Sign out
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out") {
                        appState.signOut()
                        // If signOut is async, use:
                        // Task { await appState.signOut() }
                    }
                }
            }

            // MARK: - Confirmation: Soft Delete Home (Admin only)

            .confirmationDialog(
                "Delete Home?",
                isPresented: .constant(homePendingDelete != nil),
                titleVisibility: .visible
            ) {
                Button("Move to Recycle Bin (30 days)", role: .destructive) {
                    guard let home = homePendingDelete, let homeId = home.id else { return }
                    homePendingDelete = nil

                    Task {
                        // Soft delete: hides from the homes list, recoverable for 30 days
                        _ = await vm.softDeleteHome(appState: appState, homeId: homeId)
                    }
                }
                Button("Cancel", role: .cancel) {
                    homePendingDelete = nil
                }
            } message: {
                Text("This home will be recoverable for 30 days. It will expire automatically after that.")
            }

            // MARK: - Confirmation: Leave Home (Everyone)

            .confirmationDialog(
                "Leave Home?",
                isPresented: .constant(homePendingLeave != nil),
                titleVisibility: .visible
            ) {
                Button("Leave Home", role: .destructive) {
                    guard let home = homePendingLeave, let homeId = home.id else { return }
                    homePendingLeave = nil

                    Task {
                        // Leave: removes your membership only (home remains for others)
                        _ = await vm.leaveHome(appState: appState, homeId: homeId)
                    }
                }
                Button("Cancel", role: .cancel) {
                    homePendingLeave = nil
                }
            } message: {
                Text("You will lose access to this home unless someone invites you again.")
            }

            // MARK: - Sheets

            .sheet(isPresented: $showCreate) {
                CreateHomeView { inviteCode in
                    if inviteCode != nil {
                        Task { await refreshAndAutoSelect() }
                    }
                    showCreate = false
                }
                .environmentObject(appState)
            }
            .sheet(isPresented: $showJoin) {
                JoinHomeView {
                    Task { await refreshAndAutoSelect() }
                    showJoin = false
                }
                .environmentObject(appState)
            }

            // MARK: - Recycle Bin Screen
            // NOTE: You'll create RecycleBinView next (UI/Homes/RecycleBinView.swift)

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

    /// Reloads the user's active homes from Firestore.
    private func refreshAndAutoSelect() async {
        guard let uid = appState.authUser?.uid else { return }
        await vm.loadHomes(for: uid)
    }

    /// Selects a home and loads the user's role for that home into AppState.
    private func select(_ home: HomeDoc) async {
        guard let uid = appState.authUser?.uid,
              let homeId = home.id else { return }
        await vm.selectHome(appState: appState, uid: uid, homeId: homeId)
    }
}
