import SwiftUI

struct PaymentsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = PaymentsViewModel()
    @StateObject private var dashVM = DashboardViewModel()

    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                if let err = vm.errorMessage {
                    Text(err).foregroundStyle(.red)
                }

                ForEach(vm.payments) { p in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(p.note.isEmpty ? "Payment" : p.note)
                            .font(.headline)

                        HStack {
                            Text(p.amount, format: .currency(code: currencyCode()))
                                .monospacedDigit()
                            Spacer()
                            Text(p.date, style: .date)
                                .foregroundStyle(.secondary)
                        }

                        paymentWhoLine(p)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Payments")
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
                AddPaymentView { didAdd in
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

    private func paymentWhoLine(_ p: PaymentDoc) -> Text {
        let from = displayName(for: p.paidByUid, members: dashVM.members)

        if let toUid = p.paidToUid, !toUid.isEmpty {
            let to = displayName(for: toUid, members: dashVM.members)
            return Text("\(from) → \(to)")
        } else {
            // Backward compatible with old Payment docs
            return Text("Paid by: \(from)")
        }
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
