import SwiftUI

struct HomeListView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = HomesViewModel()

    @State private var showCreate = false
    @State private var showJoin = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {

                if let err = vm.errorMessage {
                    Text(err)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

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
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out") {
                        appState.signOut()
                        // If signOut is async, use:
                        // Task { await appState.signOut() }
                    }
                }
            }
        
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
            .task {
                await refreshAndAutoSelect()
           }
        }
    }

    // MARK: - Actions

    private func refreshAndAutoSelect() async {
        guard let uid = appState.authUser?.uid else { return }
        await vm.loadHomes(for: uid)
    }

    private func select(_ home: HomeDoc) async {
        guard let uid = appState.authUser?.uid,
              let homeId = home.id else { return }
        await vm.selectHome(appState: appState, uid: uid, homeId: homeId)
    }
}
