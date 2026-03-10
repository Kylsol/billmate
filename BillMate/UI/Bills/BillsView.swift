//
//  BillsView.swift
//  BillMate
//
//  Created by Kyle Solomons on 3/1/26.
//

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

    /// Local error display for delete/restore actions.
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Errors
                if let err = localError ?? vm.errorMessage {
                    Text(err)
                        .foregroundStyle(.red)
                }

                // MARK: - Bills
                ForEach(vm.bills) { bill in
                    NavigationLink {
                        BillDetailView(
                            bill: bill,
                            isRecycleBinItem: false,
                            onChanged: {
                                Task { await reload() }
                            }
                        )
                    } label: {
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
                "Delete Bill?",
                isPresented: Binding(
                    get: { billPendingDelete != nil },
                    set: { if !$0 { billPendingDelete = nil } }
                ),
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

    // MARK: - Reload

    private func reload() async {
        guard let homeId = appState.activeHome?.id else { return }

        await vm.load(homeId: homeId)
        await dashVM.loadAll(homeId: homeId)
    }

    // MARK: - Soft Delete Bill

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

        let who = (user.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? user.name!
            : (user.email ?? user.uid)

        let event = EventDoc(
            id: nil,
            type: "bill_deleted",
            actorUid: user.uid,
            actorName: who,
            targetType: "bill",
            targetId: billId,
            message: "Deleted bill",
            createdAt: Date()
        )

        _ = try? FirestoreService.eventsCol(homeId).addDocument(from: event)
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
