//
//  PaymentsView.swift
//  BillMate
//
//  Created by Kyle Solomons on 3/1/26.
//

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

    /// Local error for delete action.
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Errors
                if let err = localError ?? vm.errorMessage {
                    Text(err)
                        .foregroundStyle(.red)
                }

                // MARK: - Payments
                ForEach(vm.payments) { payment in
                    NavigationLink {
                        PaymentDetailView(
                            payment: payment,
                            isRecycleBinItem: false,
                            onChanged: {
                                Task { await reload() }
                            }
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(payment.note.isEmpty ? "Payment" : payment.note)
                                .font(.headline)

                            HStack {
                                Text(payment.amount, format: .currency(code: currencyCode()))
                                    .monospacedDigit()
                                Spacer()
                                Text(payment.date, style: .date)
                                    .foregroundStyle(.secondary)
                            }

                            paymentWhoLine(payment)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if appState.activeRole == .admin {
                            Button(role: .destructive) {
                                paymentPendingDelete = payment
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
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
            .confirmationDialog(
                "Delete Payment?",
                isPresented: Binding(
                    get: { paymentPendingDelete != nil },
                    set: { if !$0 { paymentPendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Move to Recycle Bin (30 days)", role: .destructive) {
                    guard let payment = paymentPendingDelete,
                          let paymentId = payment.id,
                          let homeId = appState.activeHome?.id else { return }

                    paymentPendingDelete = nil

                    Task {
                        await softDeletePayment(homeId: homeId, paymentId: paymentId)
                        await reload()
                    }
                }

                Button("Cancel", role: .cancel) { paymentPendingDelete = nil }
            } message: {
                Text("This payment will be recoverable for 30 days. It will expire automatically after that.")
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

    // MARK: - Reload

    private func reload() async {
        guard let homeId = appState.activeHome?.id else { return }
        await vm.load(homeId: homeId)
        await dashVM.loadAll(homeId: homeId)
    }

    // MARK: - Soft Delete Payment

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
            try await FirestoreService.paymentsCol(homeId)
                .document(paymentId)
                .setData([
                    "isDeleted": true,
                    "deletedAt": Timestamp(date: now),
                    "deleteExpiresAt": Timestamp(date: expires),
                    "deletedByUid": user.uid,
                    "deletedByName": user.name as Any
                ], merge: true)

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

    private func paymentWhoLine(_ payment: PaymentDoc) -> Text {
        let from = displayName(for: payment.paidByUid, members: dashVM.members)

        if let toUid = payment.paidToUid, !toUid.isEmpty {
            let to = displayName(for: toUid, members: dashVM.members)
            return Text("\(from) → \(to)")
        } else {
            return Text("Paid by: \(from)")
        }
    }

    private func displayName(for uid: String, members: [MemberDoc]) -> String {
        if let member = members.first(where: { $0.uid == uid }) {
            let trimmed = (member.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
            if let email = member.email, !email.isEmpty { return email }
        }
        return uid
    }

    private func currencyCode() -> String {
        Locale.current.currency?.identifier ?? "USD"
    }
}
