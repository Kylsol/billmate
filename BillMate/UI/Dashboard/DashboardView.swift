import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var homesVM: HomesViewModel

    @StateObject private var dashVM = DashboardViewModel()

    @State private var showHomePicker = false
    @State private var showInviteAlert = false
    @State private var inviteCode: String = ""
    @State private var inviteError: String?

    var body: some View {
        NavigationStack {
            dashboardList
                .navigationTitle(appState.activeHome?.name ?? "Dashboard")
                .toolbar { dashboardToolbar }
                .safeAreaInset(edge: .bottom) {
                    NavigationLinksBar(isAdmin: appState.activeRole == .admin)
                }
                .sheet(isPresented: $showHomePicker) {
                    homePickerSheet
                }
                .alert("Invite Code", isPresented: $showInviteAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(inviteCode)
                }
                .alert(
                    "Invite Error",
                    isPresented: Binding(
                        get: { inviteError != nil },
                        set: { if !$0 { inviteError = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) { inviteError = nil }
                } message: {
                    Text(inviteError ?? "Unknown error")
                }
                .task {
                    await loadHomes()
                    await reload()
                }
        }
    }

    // MARK: - Subviews

    private var dashboardList: some View {
        List {
            balancesSection
            homeSection
        }
    }

    private var balancesSection: some View {
        Section("Balances") {
            if let err = dashVM.errorMessage {
                Text(err).foregroundStyle(.red)
            }

            if dashVM.balances.isEmpty {
                Text("No data yet. Add bills or payments.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dashVM.balances) { b in
                    NavigationLink {
                        MemberLedgerView(memberUid: b.id, memberName: b.displayName)
                    } label: {
                        HStack {
                            Text(b.displayName)
                                .lineLimit(1)

                            Spacer()

                            Text(b.amountOwed, format: .currency(code: currencyCode()))
                                .foregroundStyle(colorFor(owed: b.amountOwed))
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private var homeSection: some View {
        Section("Home") {
            HStack {
                Text("Active")
                Spacer()
                Text(appState.activeHome?.name ?? "—")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Role")
                Spacer()
                Text(appState.activeRole?.rawValue ?? "—")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ToolbarContentBuilder
    private var dashboardToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Homes") {
                appState.resetHomeSelection()
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Switch Home") { showHomePicker = true }

                if appState.activeRole == .admin {
                    Button("Create Invite Code") {
                        Task { await createInviteTapped() }
                    }
                }

                Button("Sign Out", role: .destructive) {
                    appState.signOut()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private var homePickerSheet: some View {
        HomePickerSheet(
            homes: homesVM.homes,
            onSelect: { home in
                Task {
                    guard let uid = appState.authUser?.uid,
                          let homeId = home.id else { return }

                    await homesVM.selectHome(appState: appState, uid: uid, homeId: homeId)
                    await reload()
                    showHomePicker = false
                }
            },
            onClose: {
                showHomePicker = false
            }
        )
    }

    // MARK: - Actions

    private func createInviteTapped() async {
        guard let homeId = appState.activeHome?.id else {
            inviteError = "No active home selected."
            return
        }

        do {
            let code = try await homesVM.createInvite(homeId: homeId)
            inviteCode = code
            showInviteAlert = true
        } catch {
            inviteError = error.localizedDescription
        }
    }

    private func loadHomes() async {
        guard let uid = appState.authUser?.uid else { return }
        await homesVM.loadHomes(for: uid)
    }

    private func reload() async {
        guard let homeId = appState.activeHome?.id else { return }
        await dashVM.loadAll(homeId: homeId)
    }

    private func colorFor(owed: Double) -> Color {
        if owed > 0 { return .red }
        if owed < 0 { return .green }
        return .primary
    }

    private func currencyCode() -> String {
        Locale.current.currency?.identifier ?? "USD"
    }
}

private struct NavigationLinksBar: View {
    let isAdmin: Bool

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink {
                BillsView()
            } label: {
                Label("Bills", systemImage: "doc.plaintext")
            }
            .buttonStyle(.borderedProminent)

            NavigationLink {
                PaymentsView()
            } label: {
                Label("Payments", systemImage: "arrow.left.arrow.right")
            }
            .buttonStyle(.bordered)

            NavigationLink {
                NotificationsView()
            } label: {
                Label("Feed", systemImage: "bell")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

private struct HomePickerSheet: View {
    let homes: [HomeDoc]
    let onSelect: (HomeDoc) -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List(homes) { h in
                Button(h.name) { onSelect(h) }
            }
            .navigationTitle("Switch Home")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { onClose() }
                }
            }
        }
    }
}
