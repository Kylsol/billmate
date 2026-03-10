//
//  RecycleBinView.swift
//  BillMate
//
//  Created by Kyle Solomons on 3/1/26.
//

import SwiftUI
import FirebaseFirestore

/// Shows soft-deleted items that can be restored.
/// IMPORTANT:
/// - There is intentionally NO permanent delete action here.
/// - Items should expire automatically after 30 days (via backend TTL / scheduled cleanup).
struct RecycleBinView: View {
    @EnvironmentObject private var appState: AppState

    @StateObject private var homesVM = HomesViewModel()
    @StateObject private var dashVM = DashboardViewModel()

    // MARK: - UI State

    @State private var tab: BinTab = .homes
    @State private var deletedHomes: [HomeDoc] = []
    @State private var deletedBills: [DeletedBillRow] = []
    @State private var deletedPayments: [DeletedPaymentRow] = []
    @State private var memberNames: [String: String] = [:]

    @State private var isLoading: Bool = false
    @State private var localError: String?

    // Confirmation dialogs
    @State private var homePendingRestore: HomeDoc?

    enum BinTab: String, CaseIterable, Identifiable {
        case homes = "Homes"
        case bills = "Bills"
        case payments = "Payments"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Recycle Bin", selection: $tab) {
                    ForEach(BinTab.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if let err = localError ?? homesVM.errorMessage {
                    Text(err)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Group {
                    switch tab {
                    case .homes:
                        homesList
                    case .bills:
                        billsList
                    case .payments:
                        paymentsList
                    }
                }
            }
            .navigationTitle("Recycle Bin")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await loadMembers()
                            await refresh()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .confirmationDialog(
                "Restore Home?",
                isPresented: .constant(homePendingRestore != nil),
                titleVisibility: .visible
            ) {
                Button("Restore") {
                    guard let home = homePendingRestore, let homeId = home.id else { return }
                    homePendingRestore = nil

                    Task {
                        _ = await homesVM.restoreHome(appState: appState, homeId: homeId)
                        await refresh()
                    }
                }
                Button("Cancel", role: .cancel) { homePendingRestore = nil }
            } message: {
                Text("This home will be moved back to your active homes list.")
            }
            .task {
                await loadMembers()
                await refresh()
            }
        }
    }

    // MARK: - Homes List

    private var homesList: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading...")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if deletedHomes.isEmpty && !isLoading {
                Section {
                    Text("Nothing in the recycle bin.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Deleted Homes") {
                    ForEach(deletedHomes) { home in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(home.name)
                                .font(.headline)

                            Text(deletedByText(name: home.deletedByName, uid: home.deletedByUid))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text(expiresText(expiresAt: home.deleteExpiresAt))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { homePendingRestore = home }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                homePendingRestore = home
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.green)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Bills List

    private var billsList: some View {
        List {
            if appState.activeHome?.id == nil {
                Section {
                    Text("Select a home first to view deleted bills.")
                        .foregroundStyle(.secondary)
                }
            } else {
                if isLoading {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Loading...")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if deletedBills.isEmpty && !isLoading {
                    Section {
                        Text("No deleted bills in this home.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Deleted Bills") {
                        ForEach(deletedBills) { bill in
                            NavigationLink {
                                BillDetailView(
                                    bill: bill.toBillDoc(),
                                    isRecycleBinItem: true,
                                    onChanged: {
                                        Task { await refresh() }
                                    },
                                    onRestore: { restoredBill in
                                        await restoreBill(restoredBill)
                                    }
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(bill.description)
                                        .font(.headline)

                                    HStack {
                                        Text(bill.amountString)
                                            .monospacedDigit()
                                        Spacer()
                                        Text(bill.dateString)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(deletedByText(name: bill.deletedByName, uid: bill.deletedByUid))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .onChange(of: appState.activeHome?.id) { _, _ in
            Task {
                await loadMembers()
                await refreshBillsOnly()
            }
        }
    }

    // MARK: - Payments List

    private var paymentsList: some View {
        List {
            if appState.activeHome?.id == nil {
                Section {
                    Text("Select a home first to view deleted payments.")
                        .foregroundStyle(.secondary)
                }
            } else {
                if isLoading {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Loading...")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if deletedPayments.isEmpty && !isLoading {
                    Section {
                        Text("No deleted payments in this home.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Deleted Payments") {
                        ForEach(deletedPayments) { payment in
                            NavigationLink {
                                PaymentDetailView(
                                    payment: payment.toPaymentDoc(),
                                    isRecycleBinItem: true,
                                    onChanged: {
                                        Task { await refresh() }
                                    },
                                    onRestore: { restoredPayment in
                                        await restorePayment(restoredPayment)
                                    }
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(payment.note)
                                        .font(.headline)

                                    HStack {
                                        Text(payment.amountString)
                                            .monospacedDigit()
                                        Spacer()
                                        Text(payment.dateString)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(deletedByText(name: payment.deletedByName, uid: payment.deletedByUid))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .onChange(of: appState.activeHome?.id) { _, _ in
            Task {
                await loadMembers()
                await refreshPaymentsOnly()
            }
        }
    }

    // MARK: - Refresh

    private func refresh() async {
        localError = nil
        guard let uid = appState.authUser?.uid else {
            localError = "Not signed in."
            return
        }

        isLoading = true
        defer { isLoading = false }

        deletedHomes = await homesVM.loadDeletedHomes(for: uid)
        await refreshBillsOnly()
        await refreshPaymentsOnly()
    }

    private func refreshBillsOnly() async {
        localError = nil

        guard let homeId = appState.activeHome?.id else {
            deletedBills = []
            return
        }

        do {
            let snap = try await FirestoreService.billsCol(homeId)
                .whereField("isDeleted", isEqualTo: true)
                .getDocuments()

            deletedBills = snap.documents.compactMap { doc in
                let data = doc.data()

                let description = data["description"] as? String ?? "Bill"
                let amount = doubleFromAny(data["amount"]) ?? 0.0
                let date = dateFromAny(data["date"]) ?? Date()
                let category = data["category"] as? String
                let paidByUid = data["paidByUid"] as? String ?? ""
                let participantUids = data["participantUids"] as? [String] ?? []
                let createdAt = dateFromAny(data["createdAt"]) ?? date
                let createdByUid = data["createdByUid"] as? String ?? ""
                let updatedAt = dateFromAny(data["updatedAt"])
                let updatedByUid = data["updatedByUid"] as? String

                let deletedByUid = data["deletedByUid"] as? String
                let deletedByName = data["deletedByName"] as? String
                let deletedAt = dateFromAny(data["deletedAt"])
                let deleteExpiresAt = dateFromAny(data["deleteExpiresAt"])

                return DeletedBillRow(
                    id: doc.documentID,
                    description: description,
                    amount: amount,
                    date: date,
                    category: category,
                    paidByUid: paidByUid,
                    participantUids: participantUids,
                    createdAt: createdAt,
                    createdByUid: createdByUid,
                    updatedAt: updatedAt,
                    updatedByUid: updatedByUid,
                    deletedByUid: deletedByUid,
                    deletedByName: deletedByName,
                    deletedAt: deletedAt,
                    deleteExpiresAt: deleteExpiresAt
                )
            }
            .sorted { $0.date > $1.date }

        } catch {
            localError = error.localizedDescription
            deletedBills = []
        }
    }

    private func refreshPaymentsOnly() async {
        localError = nil

        guard let homeId = appState.activeHome?.id else {
            deletedPayments = []
            return
        }

        do {
            let snap = try await FirestoreService.paymentsCol(homeId)
                .whereField("isDeleted", isEqualTo: true)
                .getDocuments()

            deletedPayments = snap.documents.compactMap { doc in
                let data = doc.data()

                let amount = doubleFromAny(data["amount"]) ?? 0.0
                let date = dateFromAny(data["date"]) ?? Date()
                let rawNote = (data["note"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let note = (rawNote?.isEmpty == false) ? rawNote! : "Payment"

                let paidByUid = data["paidByUid"] as? String ?? ""
                let paidToUid = data["paidToUid"] as? String
                let createdAt = dateFromAny(data["createdAt"]) ?? date
                let createdByUid = data["createdByUid"] as? String ?? ""
                let updatedAt = dateFromAny(data["updatedAt"])
                let updatedByUid = data["updatedByUid"] as? String

                let deletedByUid = data["deletedByUid"] as? String
                let deletedByName = data["deletedByName"] as? String
                let deletedAt = dateFromAny(data["deletedAt"])
                let deleteExpiresAt = dateFromAny(data["deleteExpiresAt"])

                return DeletedPaymentRow(
                    id: doc.documentID,
                    amount: amount,
                    date: date,
                    note: note,
                    paidByUid: paidByUid,
                    paidToUid: paidToUid,
                    createdAt: createdAt,
                    createdByUid: createdByUid,
                    updatedAt: updatedAt,
                    updatedByUid: updatedByUid,
                    deletedByUid: deletedByUid,
                    deletedByName: deletedByName,
                    deletedAt: deletedAt,
                    deleteExpiresAt: deleteExpiresAt
                )
            }
            .sorted { $0.date > $1.date }

        } catch {
            localError = error.localizedDescription
            deletedPayments = []
        }
    }

    // MARK: - Members

    private func loadMembers() async {
        guard let homeId = appState.activeHome?.id else {
            memberNames = [:]
            return
        }

        await dashVM.loadAll(homeId: homeId)

        var map: [String: String] = [:]
        for member in dashVM.members {
            let trimmedName = (member.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty {
                map[member.uid] = trimmedName
            } else if let email = member.email, !email.isEmpty {
                map[member.uid] = email
            }
        }
        memberNames = map
    }

    // MARK: - Restore

    private func restoreBill(_ bill: BillDoc) async {
        guard let homeId = appState.activeHome?.id,
              let billId = bill.id else { return }

        do {
            try await FirestoreService.billsCol(homeId)
                .document(billId)
                .updateData([
                    "isDeleted": false,
                    "deletedAt": FieldValue.delete(),
                    "deleteExpiresAt": FieldValue.delete(),
                    "deletedByUid": FieldValue.delete(),
                    "deletedByName": FieldValue.delete()
                ])
        } catch {
            localError = error.localizedDescription
        }
    }

    private func restorePayment(_ payment: PaymentDoc) async {
        guard let homeId = appState.activeHome?.id,
              let paymentId = payment.id else { return }

        do {
            try await FirestoreService.paymentsCol(homeId)
                .document(paymentId)
                .updateData([
                    "isDeleted": false,
                    "deletedAt": FieldValue.delete(),
                    "deleteExpiresAt": FieldValue.delete(),
                    "deletedByUid": FieldValue.delete(),
                    "deletedByName": FieldValue.delete()
                ])
        } catch {
            localError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func deletedByText(name: String?, uid: String?) -> String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedName, !trimmedName.isEmpty {
            return "Deleted by: \(trimmedName)"
        }
        if let uid, !uid.isEmpty {
            return "Deleted by: \(memberNames[uid] ?? uid)"
        }
        return "Deleted by: unknown"
    }

    private func expiresText(expiresAt: Date?) -> String {
        guard let expiresAt else {
            return "Expires in 30 days"
        }

        let now = Date()
        let days = Calendar.current.dateComponents([.day], from: now, to: expiresAt).day ?? 0

        if days <= 0 { return "Expires today" }
        if days == 1 { return "Expires in 1 day" }
        return "Expires in \(days) days"
    }

    private func dateFromAny(_ value: Any?) -> Date? {
        if let ts = value as? Timestamp { return ts.dateValue() }
        if let ms = value as? Double { return Date(timeIntervalSince1970: ms / 1000.0) }
        if let ms = value as? Int { return Date(timeIntervalSince1970: Double(ms) / 1000.0) }
        if let ms = value as? Int64 { return Date(timeIntervalSince1970: Double(ms) / 1000.0) }
        return nil
    }

    private func doubleFromAny(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let i64 = value as? Int64 { return Double(i64) }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }
}

// MARK: - Deleted Bill Row

private struct DeletedBillRow: Identifiable, Hashable {
    let id: String
    let description: String
    let amount: Double
    let date: Date
    let category: String?

    let paidByUid: String
    let participantUids: [String]

    let createdAt: Date
    let createdByUid: String
    let updatedAt: Date?
    let updatedByUid: String?

    let deletedByUid: String?
    let deletedByName: String?
    let deletedAt: Date?
    let deleteExpiresAt: Date?

    var amountString: String {
        String(format: "$%.2f", amount)
    }

    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    func toBillDoc() -> BillDoc {
        BillDoc(
            id: id,
            description: description,
            amount: amount,
            date: date,
            category: category,
            paidByUid: paidByUid,
            participantUids: participantUids,
            createdAt: createdAt,
            createdByUid: createdByUid,
            updatedAt: updatedAt,
            updatedByUid: updatedByUid,
            isDeleted: true,
            deletedAt: deletedAt,
            deleteExpiresAt: deleteExpiresAt,
            deletedByUid: deletedByUid,
            deletedByName: deletedByName
        )
    }
}

// MARK: - Deleted Payment Row

private struct DeletedPaymentRow: Identifiable, Hashable {
    let id: String
    let amount: Double
    let date: Date
    let note: String

    let paidByUid: String
    let paidToUid: String?

    let createdAt: Date
    let createdByUid: String
    let updatedAt: Date?
    let updatedByUid: String?

    let deletedByUid: String?
    let deletedByName: String?
    let deletedAt: Date?
    let deleteExpiresAt: Date?

    var amountString: String {
        String(format: "$%.2f", amount)
    }

    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    func toPaymentDoc() -> PaymentDoc {
        PaymentDoc(
            id: id,
            amount: amount,
            date: date,
            note: note,
            paidByUid: paidByUid,
            paidToUid: paidToUid,
            createdAt: createdAt,
            createdByUid: createdByUid,
            updatedAt: updatedAt,
            updatedByUid: updatedByUid,
            isDeleted: true,
            deletedAt: deletedAt,
            deleteExpiresAt: deleteExpiresAt,
            deletedByUid: deletedByUid,
            deletedByName: deletedByName
        )
    }
}
