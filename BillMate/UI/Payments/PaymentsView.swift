import SwiftUI
import FirebaseFirestore

struct PaymentsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = PaymentsViewModel()
    @StateObject private var dashVM = DashboardViewModel()

    @State private var showAdd = false

    // MARK: - Soft Delete UI State

    /// Payment pending delete confirmation.
    @State private var paymentPendingDelete: PaymentDoc?

    /// Local error for delete action (vm.errorMessage still shows too).
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Errors
                if let err = localError ?? vm.errorMessage {
                    Text(err).foregroundStyle(.red)
                }

                // MARK: - Payments
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

                    // MARK: - Swipe to Soft Delete (Admin only)
                    // NOTE:
                    // This assumes your Payment docs support isDeleted/deletedAt/etc.
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if appState.activeRole == .admin {
                            Button(role: .destructive) {
                                paymentPendingDelete = p
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Payments")

            // MARK: - Toolbar
            .toolbar {
                // Add payment (Admin only)
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
                "Delete Payment?",
                isPresented: Binding(
                    get: { paymentPendingDelete != nil },
                    set: { if !$0 { paymentPendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Move to Recycle Bin (30 days)", role: .destructive) {
                    guard let p = paymentPendingDelete,
                          let paymentId = p.id,
                          let homeId = appState.activeHome?.id else { return }

                    paymentPendingDelete = nil

                    Task {
                        await softDeletePayment(homeId: homeId, paymentId: paymentId)

                        // ✅ Force refresh so the payment disappears immediately
                        await reload()
                    }
                }

                Button("Cancel", role: .cancel) { paymentPendingDelete = nil }
            } message: {
                Text("This payment will be recoverable for 30 days. It will expire automatically after that.")
            }

            // MARK: - Add Payment Sheet
            .sheet(isPresented: $showAdd) {
                AddPaymentView { didAdd in
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
        await vm.load(homeId: homeId)

        // ✅ load members so we can show names
        await dashVM.loadAll(homeId: homeId)
    }

    // MARK: - Soft Delete Payment (Firestore update)

    /// Soft deletes a payment by marking it deleted and setting an expiration date.
    /// IMPORTANT: This requires your Payment docs to have the soft-delete fields.
    private func softDeletePayment(homeId: String, paymentId: String) async {
        localError = nil

        guard let user = appState.authUser else {
            localError = "Not signed in."
            return
        }

        let now = Date()
        let expires = Calendar.current.date(byAdding: .day, value: 30, to: now)
            ?? now.addingTimeInterval(30 * 24 * 3600)

        do {
            // 1) Soft delete the payment
            try await FirestoreService.paymentsCol(homeId)
                .document(paymentId)
                .setData([
                    "isDeleted": true,
                    "deletedAt": Timestamp(date: now),
                    "deleteExpiresAt": Timestamp(date: expires),
                    "deletedByUid": user.uid,
                    "deletedByName": user.name as Any
                ], merge: true)

            // 2) Log event to feed (Deleted by...)
            let who = (user.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? user.name!
                : (user.email ?? user.uid)

            let event = EventDoc(
                id: nil,
                type: "payment_deleted",
                actorUid: user.uid,
                actorName: who,
                targetType: "payment",
                targetId: paymentId,
                message: "Deleted payment",
                createdAt: Date()
            )

            _ = try? FirestoreService.eventsCol(homeId).addDocument(from: event)

        } catch {
            localError = error.localizedDescription
        }
    }

    // MARK: - Helpers

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
