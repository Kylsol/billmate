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

    // Reuse your existing VM because it already has:
    // - loadDeletedHomes(for:)
    // - restoreHome(appState:homeId:)
    @StateObject private var homesVM = HomesViewModel()

    // MARK: - UI State

    @State private var tab: BinTab = .homes
    @State private var deletedHomes: [HomeDoc] = []
    @State private var deletedBills: [DeletedBillRow] = []

    @State private var isLoading: Bool = false
    @State private var localError: String?

    // Confirmation dialogs
    @State private var homePendingRestore: HomeDoc?
    @State private var billPendingRestore: DeletedBillRow?

    enum BinTab: String, CaseIterable, Identifiable {
        case homes = "Homes"
        case bills = "Bills"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {

                // MARK: - Segmented Tabs
                Picker("Recycle Bin", selection: $tab) {
                    ForEach(BinTab.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // MARK: - Errors
                if let err = localError ?? homesVM.errorMessage {
                    Text(err)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // MARK: - Content
                Group {
                    switch tab {
                    case .homes:
                        homesList
                    case .bills:
                        billsList
                    }
                }
            }
            .navigationTitle("Recycle Bin")
            .toolbar {
                // Manual refresh
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }

            // MARK: - Restore Confirmation (Home)
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

            // MARK: - Restore Confirmation (Bill)
            .confirmationDialog(
                "Restore Bill?",
                isPresented: .constant(billPendingRestore != nil),
                titleVisibility: .visible
            ) {
                Button("Restore") {
                    guard let bill = billPendingRestore else { return }
                    billPendingRestore = nil

                    Task {
                        await restoreBill(bill)
                        await refreshBillsOnly()
                    }
                }
                Button("Cancel", role: .cancel) { billPendingRestore = nil }
            } message: {
                Text("This bill will be restored to the active bills list.")
            }

            // MARK: - Initial Load
            .task {
                await refresh()
            }
        }
    }

    // MARK: - Homes List (Deleted)

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

    // MARK: - Bills List (Deleted)

    private var billsList: some View {
        List {
            // If no active home is selected, bills are ambiguous.
            // Bills belong to a specific home, so we use the currently selected home.
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
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(bill.description)
                                        .font(.headline)
                                    Spacer()
                                    Text(bill.amountString)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Text(bill.dateString)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Text(deletedByText(name: bill.deletedByName, uid: bill.deletedByUid))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Text(expiresText(expiresAt: bill.deleteExpiresAt))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { billPendingRestore = bill }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    billPendingRestore = bill
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.green)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .onChange(of: appState.activeHome?.id) { _, _ in
            // If the user switches homes while this sheet is open, refresh bills for the new home.
            Task { await refreshBillsOnly() }
        }
    }

    // MARK: - Refresh

    /// Refresh both tabs (deleted homes + deleted bills for active home).
    private func refresh() async {
        localError = nil
        guard let uid = appState.authUser?.uid else {
            localError = "Not signed in."
            return
        }

        isLoading = true
        defer { isLoading = false }

        // Deleted homes (across all homes the user belongs to)
        deletedHomes = await homesVM.loadDeletedHomes(for: uid)

        // Deleted bills (only for currently selected home)
        await refreshBillsOnly()
    }

    /// Refresh only the deleted bills list for the currently selected home.
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

                // Pull fields safely (handles your mixed Timestamp/ms encoding)
                let description = data["description"] as? String ?? "Bill"
                let amount = data["amount"] as? Double ?? 0.0
                let date = dateFromAny(data["date"]) ?? Date()

                let deletedByUid = data["deletedByUid"] as? String
                let deletedByName = data["deletedByName"] as? String
                let deleteExpiresAt = dateFromAny(data["deleteExpiresAt"])

                return DeletedBillRow(
                    id: doc.documentID,
                    description: description,
                    amount: amount,
                    date: date,
                    deletedByUid: deletedByUid,
                    deletedByName: deletedByName,
                    deleteExpiresAt: deleteExpiresAt
                )
            }
            .sorted { $0.date > $1.date }

        } catch {
            localError = error.localizedDescription
            deletedBills = []
        }
    }

    // MARK: - Restore Bill

    /// Restores a bill by clearing soft-delete fields.
    private func restoreBill(_ bill: DeletedBillRow) async {
        guard let homeId = appState.activeHome?.id else { return }

        do {
            try await FirestoreService.billsCol(homeId)
                .document(bill.id)
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

    // MARK: - Text Helpers

    private func deletedByText(name: String?, uid: String?) -> String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedName, !trimmedName.isEmpty {
            return "Deleted by \(trimmedName)"
        }
        if let uid, !uid.isEmpty {
            return "Deleted by \(uid)"
        }
        return "Deleted by unknown"
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

    // MARK: - Date Helper (matches your ViewModel’s behavior)

    /// Handles Firestore Timestamp OR millisecond numeric dates.
    private func dateFromAny(_ value: Any?) -> Date? {
        if let ts = value as? Timestamp { return ts.dateValue() }
        if let ms = value as? Double { return Date(timeIntervalSince1970: ms / 1000.0) }
        if let ms = value as? Int { return Date(timeIntervalSince1970: Double(ms) / 1000.0) }
        return nil
    }
}

// MARK: - Lightweight UI Model (Deleted Bill Row)

/// A small view-only model for the recycle bin bills list.
/// We do this instead of decoding BillDoc directly to avoid issues with mixed date formats.
private struct DeletedBillRow: Identifiable, Hashable {
    let id: String
    let description: String
    let amount: Double
    let date: Date

    let deletedByUid: String?
    let deletedByName: String?
    let deleteExpiresAt: Date?

    var amountString: String {
        // Simple formatting (you can swap in NumberFormatter later)
        String(format: "$%.2f", amount)
    }

    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
