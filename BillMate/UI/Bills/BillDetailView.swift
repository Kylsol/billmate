//
//  BillDetailView.swift
//  BillMate
//
//  Created by Kyle Solomons on 3/10/26.
//

import SwiftUI
import FirebaseFirestore

struct BillDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var dashVM = DashboardViewModel()
    @StateObject private var billsVM = BillsViewModel()

    let bill: BillDoc
    var isRecycleBinItem: Bool = false
    var onChanged: (() -> Void)? = nil
    var onRestore: ((BillDoc) async -> Void)? = nil

    @State private var isEditMode = false
    @State private var showUnsavedChangesDialog = false
    @State private var showDiscardChangesDialog = false
    @State private var showRestoreConfirm = false

    @State private var descriptionText: String = ""
    @State private var amountText: String = ""
    @State private var date: Date = Date()
    @State private var category: String = BillCategory.allCases.first?.rawValue ?? "Other"
    @State private var paidByUid: String = ""
    @State private var selectedParticipants: Set<String> = []

    @State private var localError: String?

    private var canEdit: Bool {
        appState.activeRole == .admin && !isRecycleBinItem
    }

    private var hasUnsavedChanges: Bool {
        descriptionText.trimmingCharacters(in: .whitespacesAndNewlines) != bill.description.trimmingCharacters(in: .whitespacesAndNewlines)
        || parsedAmount != bill.amount
        || !Calendar.current.isDate(date, inSameDayAs: bill.date)
        || category != (bill.category ?? "Other")
        || paidByUid != bill.paidByUid
        || selectedParticipants != Set(bill.participantUids)
    }

    private var parsedAmount: Double {
        Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var body: some View {
        Form {
            if let err = localError ?? billsVM.errorMessage {
                Section {
                    Text(err)
                        .foregroundStyle(.red)
                }
            }

            Section("Bill") {
                if isEditMode {
                    TextField("Description", text: $descriptionText)

                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)

                    Picker("Category", selection: $category) {
                        ForEach(BillCategory.allCases, id: \.rawValue) { item in
                            Text(item.rawValue).tag(item.rawValue)
                        }
                    }

                    DatePicker("Date", selection: $date, displayedComponents: .date)
                } else {
                    detailRow("Description", value: bill.description)
                    detailRow("Amount", value: bill.amount.formatted(.currency(code: currencyCode())))
                    detailRow("Category", value: bill.category ?? "Other")
                    detailRow("Date", value: bill.date.formatted(date: .abbreviated, time: .omitted))
                }
            }

            Section("Paid By") {
                if isEditMode {
                    Picker("Member", selection: $paidByUid) {
                        ForEach(dashVM.members, id: \.uid) { member in
                            Text(displayName(for: member.uid, members: dashVM.members))
                                .tag(member.uid)
                        }
                    }
                } else {
                    detailRow("Member", value: displayName(for: bill.paidByUid, members: dashVM.members))
                }
            }

            Section("Split With") {
                if isEditMode {
                    if dashVM.members.isEmpty {
                        Text("No members found.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(dashVM.members, id: \.uid) { member in
                            Toggle(isOn: Binding(
                                get: { selectedParticipants.contains(member.uid) },
                                set: { on in
                                    if on {
                                        selectedParticipants.insert(member.uid)
                                    } else {
                                        selectedParticipants.remove(member.uid)
                                    }
                                }
                            )) {
                                Text(displayName(for: member.uid, members: dashVM.members))
                            }
                        }
                    }

                    Text("At least 1 participant is required.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    if bill.participantUids.isEmpty {
                        Text("No participants")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(bill.participantUids, id: \.self) { uid in
                            Text(displayName(for: uid, members: dashVM.members))
                        }
                    }
                }
            }

            Section("Audit") {
                detailRow("Created", value: bill.createdAt.formatted(date: .abbreviated, time: .shortened))
                detailRow("Created By", value: displayName(for: bill.createdByUid, members: dashVM.members))

                if let updatedAt = bill.updatedAt {
                    detailRow("Updated", value: updatedAt.formatted(date: .abbreviated, time: .shortened))
                }

                if let updatedByUid = bill.updatedByUid {
                    detailRow("Updated By", value: displayName(for: updatedByUid, members: dashVM.members))
                }

                if isRecycleBinItem {
                    if let deletedByName = bill.deletedByName,
                       !deletedByName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        detailRow("Deleted By", value: deletedByName)
                    } else if let deletedByUid = bill.deletedByUid {
                        detailRow("Deleted By", value: displayName(for: deletedByUid, members: dashVM.members))
                    }

                    if let deletedAt = bill.deletedAt {
                        detailRow("Deleted At", value: deletedAt.formatted(date: .abbreviated, time: .shortened))
                    }

                    if let deleteExpiresAt = bill.deleteExpiresAt {
                        detailRow("Expires", value: deleteExpiresAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }

            if isRecycleBinItem {
                Section {
                    Button("Restore Bill") {
                        showRestoreConfirm = true
                    }
                    .foregroundStyle(.green)
                }
            } else if isEditMode && canEdit {
                Section {
                    Button(billsVM.isBusy ? "Saving..." : "Save Changes") {
                        Task { await saveChanges() }
                    }
                    .disabled(billsVM.isBusy)
                }
            }
        }
        .navigationTitle(isRecycleBinItem ? "Bill Details" : (isEditMode ? "Edit Bill" : "Bill Details"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    handleBackTapped()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }

            if canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if isEditMode {
                            Button("Done Editing") {
                                isEditMode = false
                                loadDraftFromBill()
                            }

                            Button("Discard Changes", role: .destructive) {
                                showDiscardChangesDialog = true
                            }
                        } else {
                            Button("Edit") {
                                isEditMode = true
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .interactiveDismissDisabled(isEditMode && hasUnsavedChanges)
        .confirmationDialog(
            "Unsaved Changes",
            isPresented: $showUnsavedChangesDialog,
            titleVisibility: .visible
        ) {
            Button("Save") {
                Task {
                    let shouldDismiss = await saveChanges()
                    if shouldDismiss {
                        dismiss()
                    }
                }
            }

            Button("Discard Changes", role: .destructive) {
                dismiss()
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Do you want to save your changes before leaving?")
        }
        .confirmationDialog(
            "Discard Changes?",
            isPresented: $showDiscardChangesDialog,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                loadDraftFromBill()
                isEditMode = false
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your unsaved changes will be lost.")
        }
        .confirmationDialog(
            "Restore Bill?",
            isPresented: $showRestoreConfirm,
            titleVisibility: .visible
        ) {
            Button("Restore") {
                Task {
                    await onRestore?(bill)
                    onChanged?()
                    dismiss()
                }
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This bill will be moved back to the active bills list.")
        }
        .task {
            await loadMembers()
            loadDraftFromBill()
        }
    }

    // MARK: - Actions

    private func handleBackTapped() {
        if isEditMode && hasUnsavedChanges {
            showUnsavedChangesDialog = true
        } else {
            dismiss()
        }
    }

    private func loadMembers() async {
        guard let homeId = appState.activeHome?.id else { return }
        await dashVM.loadAll(homeId: homeId)
    }

    private func loadDraftFromBill() {
        descriptionText = bill.description
        amountText = bill.amount == 0 ? "" : String(format: "%.2f", bill.amount)
        date = bill.date
        category = bill.category ?? "Other"
        paidByUid = bill.paidByUid
        selectedParticipants = Set(bill.participantUids)

        if paidByUid.isEmpty, let first = dashVM.members.first?.uid {
            paidByUid = first
        }
    }

    @discardableResult
    private func saveChanges() async -> Bool {
        localError = nil

        guard canEdit else {
            localError = "You do not have permission to edit this bill."
            return false
        }

        guard let user = appState.authUser,
              let homeId = appState.activeHome?.id,
              let billId = bill.id else {
            localError = "Missing required bill information."
            return false
        }

        let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedDescription.isEmpty else {
            localError = "Description is required."
            return false
        }

        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) else {
            localError = "Amount must be a valid number."
            return false
        }

        guard !paidByUid.isEmpty else {
            localError = "Select who paid."
            return false
        }

        let participants = Array(selectedParticipants)
        guard !participants.isEmpty else {
            localError = "Select at least one participant."
            return false
        }

        let actorName = displayActorName(user: user)

        let success = await billsVM.updateBill(
            homeId: homeId,
            originalBill: bill,
            description: trimmedDescription,
            amount: amount,
            date: date,
            category: category,
            paidByUid: paidByUid,
            participantUids: participants,
            actorUid: user.uid,
            actorName: actorName
        )

        if success {
            isEditMode = false
            onChanged?()
            return true
        } else {
            localError = billsVM.errorMessage
            return false
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func displayName(for uid: String, members: [MemberDoc]) -> String {
        if let member = members.first(where: { $0.uid == uid }) {
            let trimmedName = (member.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty { return trimmedName }

            if let email = member.email, !email.isEmpty { return email }
        }
        return uid
    }

    private func displayActorName(user: AuthUser) -> String {
        let trimmedName = user.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedName.isEmpty { return trimmedName }
        if let email = user.email, !email.isEmpty { return email }
        return user.uid
    }

    private func currencyCode() -> String {
        Locale.current.currency?.identifier ?? "USD"
    }
}

// MARK: - Categories

private enum BillCategory: String, CaseIterable {
    case food = "Food"
    case transport = "Transport"
    case utilities = "Utilities"
    case entertainment = "Entertainment"
    case rent = "Rent"
    case groceries = "Groceries"
    case diningOut = "Dining Out"
    case household = "Household"
    case internet = "Internet"
    case phone = "Phone"
    case subscriptions = "Subscriptions"
    case health = "Health"
    case education = "Education"
    case travel = "Travel"
    case other = "Other"
}
