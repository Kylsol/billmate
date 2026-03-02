import SwiftUI
import FirebaseFirestore

struct BillsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = BillsViewModel()
    @StateObject private var dashVM = DashboardViewModel()

    @State private var showAdd = false

    // MARK: - Soft Delete UI State

    /// Holds the bill the user is about to delete (used for confirmation dialog).
    @State private var billPendingDelete: BillDoc?

    /// Local error display for delete/restore actions (optional; vm.errorMessage still shows too).
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Errors
                if let err = localError ?? vm.errorMessage {
                    Text(err).foregroundStyle(.red)
                }

                // MARK: - Bills
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

                    // MARK: - Swipe to Soft Delete (Admin only)
                    // This doesn't permanently delete the doc — it moves it to the recycle bin for 30 days.
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if appState.activeRole == .admin {
                            Button(role: .destructive) {
                                billPendingDelete = bill
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Bills")

            // MARK: - Toolbar
            .toolbar {
                // Add bill (Admin only)
                if appState.activeRole == .admin {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showAdd = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }

            // MARK: - Confirm Soft Delete
            .confirmationDialog(
                "Delete Bill?",
                isPresented: .constant(billPendingDelete != nil),
                titleVisibility: .visible
            ) {
                Button("Move to Recycle Bin (30 days)", role: .destructive) {
                    guard let bill = billPendingDelete,
                          let billId = bill.id,
                          let homeId = appState.activeHome?.id else { return }

                    billPendingDelete = nil

                    Task {
                        await softDeleteBill(homeId: homeId, billId: billId)
                        await reload()
                    }
                }

                Button("Cancel", role: .cancel) { billPendingDelete = nil }
            } message: {
                Text("This bill will be recoverable for 30 days. It will expire automatically after that.")
            }

            // MARK: - Add Bill Sheet
            .sheet(isPresented: $showAdd) {
                AddBillView { didAdd in
                    if didAdd {
                        Task { await reload() }
                    }
                }
            }

            // MARK: - Initial Load
            .task {
                await reload()
            }
        }
    }

    // MARK: - Reload

    private func reload() async {
        guard let homeId = appState.activeHome?.id else { return }

        // BillsViewModel.load should ideally only return active bills.
        // If your current query loads everything, we can filter out deleted bills in the VM.
        await vm.load(homeId: homeId)

        // Load members so we can show display names
        await dashVM.loadAll(homeId: homeId)
    }

    // MARK: - Soft Delete Bill (Firestore update)

    /// Soft deletes a bill by marking it deleted and setting an expiration date.
    /// NOTE: This does NOT permanently delete the doc.
    private func softDeleteBill(homeId: String, billId: String) async {
        localError = nil

        guard let user = appState.authUser else {
            localError = "Not signed in."
            return
        }

        let now = Date()
        let expires = Calendar.current.date(byAdding: .day, value: 30, to: now)
            ?? now.addingTimeInterval(30 * 24 * 3600)

        do {
            try await FirestoreService.billsCol(homeId)
                .document(billId)
                .setData([
                    "isDeleted": true,
                    "deletedAt": Timestamp(date: now),
                    "deleteExpiresAt": Timestamp(date: expires),
                    "deletedByUid": user.uid,
                    "deletedByName": user.name as Any
                ], merge: true)

        } catch {
            localError = error.localizedDescription
        }
    }

    // MARK: - Helpers

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
