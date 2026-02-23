import SwiftUI

struct BillsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = BillsViewModel()
    @StateObject private var dashVM = DashboardViewModel()

    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                if let err = vm.errorMessage {
                    Text(err).foregroundStyle(.red)
                }

                ForEach(vm.bills) { bill in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(bill.description)
                            .font(.headline)

                        HStack {
                            Text(bill.amount, format: .currency(code: currencyCode()))
                                .monospacedDigit()
                            Spacer()
                            Text(bill.date, style: .date)
                                .foregroundStyle(.secondary)
                        }

                        Text("Paid by: \(displayName(for: bill.paidByUid, members: dashVM.members))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Bills")
            .toolbar {
                if appState.activeRole == .admin {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showAdd = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddBillView { didAdd in
                    if didAdd {
                        Task { await reload() }
                    }
                }
            }
            .task {
                await reload()
            }
        }
    }

    private func reload() async {
        guard let homeId = appState.activeHome?.id else { return }
        await vm.load(homeId: homeId)

        // ✅ load members so we can show names
        await dashVM.loadAll(homeId: homeId)
    }

    private func displayName(for uid: String, members: [MemberDoc]) -> String {
        if let m = members.first(where: { $0.uid == uid }) {
            let trimmed = (m.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
            if let email = m.email, !email.isEmpty { return email }
        }
        return uid
    }

    private func currencyCode() -> String {
        Locale.current.currency?.identifier ?? "USD"
    }
}
