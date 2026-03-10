//
//  PaymentDetailView.swift
//  BillMate
//
//  Created by Kyle Solomons on 3/10/26.
//

import SwiftUI
import FirebaseFirestore

struct PaymentDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var dashVM = DashboardViewModel()
    @StateObject private var paymentsVM = PaymentsViewModel()

    let payment: PaymentDoc
    var isRecycleBinItem: Bool = false
    var onChanged: (() -> Void)? = nil
    var onRestore: ((PaymentDoc) async -> Void)? = nil

    @State private var isEditMode = false
    @State private var showUnsavedChangesDialog = false
    @State private var showDiscardChangesDialog = false
    @State private var showRestoreConfirm = false

    @State private var amountText: String = ""
    @State private var noteText: String = ""
    @State private var date: Date = Date()
    @State private var paidByUid: String = ""
    @State private var paidToUid: String = ""

    @State private var localError: String?

    private var canEdit: Bool {
        appState.activeRole == .admin && !isRecycleBinItem
    }

    private var hasUnsavedChanges: Bool {
        parsedAmount != payment.amount
        || noteText.trimmingCharacters(in: .whitespacesAndNewlines) != payment.note.trimmingCharacters(in: .whitespacesAndNewlines)
        || !Calendar.current.isDate(date, inSameDayAs: payment.date)
        || paidByUid != payment.paidByUid
        || paidToUid != (payment.paidToUid ?? "")
    }

    private var parsedAmount: Double {
        Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var body: some View {
        Form {
            if let err = localError ?? paymentsVM.errorMessage {
                Section {
                    Text(err)
                        .foregroundStyle(.red)
                }
            }

            Section("Payment Details") {
                if isEditMode {
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)

                    TextField("Note", text: $noteText)

                    DatePicker("Date", selection: $date, displayedComponents: .date)
                } else {
                    detailRow("Amount", value: payment.amount.formatted(.currency(code: currencyCode())))
                    detailRow(
                        "Note",
                        value: payment.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Payment" : payment.note
                    )
                    detailRow("Date", value: payment.date.formatted(date: .abbreviated, time: .omitted))
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
                    .onChange(of: paidByUid) { _, newPaidBy in
                        if paidToUid == newPaidBy {
                            paidToUid = dashVM.members.first(where: { $0.uid != newPaidBy })?.uid ?? ""
                        }
                    }
                } else {
                    detailRow("Member", value: displayName(for: payment.paidByUid, members: dashVM.members))
                }
            }

            Section("Paid To") {
                if isEditMode {
                    Picker("Member", selection: $paidToUid) {
                        ForEach(dashVM.members, id: \.uid) { member in
                            Text(displayName(for: member.uid, members: dashVM.members))
                                .tag(member.uid)
                        }
                    }
                } else {
                    let paidToValue = (payment.paidToUid?.isEmpty == false)
                        ? displayName(for: payment.paidToUid ?? "", members: dashVM.members)
                        : "Not set"
                    detailRow("Member", value: paidToValue)
                }
            }

            Section("Audit") {
                detailRow("Created", value: payment.createdAt.formatted(date: .abbreviated, time: .shortened))
                detailRow("Created By", value: displayName(for: payment.createdByUid, members: dashVM.members))

                if let updatedAt = payment.updatedAt {
                    detailRow("Updated", value: updatedAt.formatted(date: .abbreviated, time: .shortened))
                }

                if let updatedByUid = payment.updatedByUid {
                    detailRow("Updated By", value: displayName(for: updatedByUid, members: dashVM.members))
                }

                if isRecycleBinItem {
                    if let deletedByName = payment.deletedByName,
                       !deletedByName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        detailRow("Deleted By", value: deletedByName)
                    } else if let deletedByUid = payment.deletedByUid {
                        detailRow("Deleted By", value: displayName(for: deletedByUid, members: dashVM.members))
                    }

                    if let deletedAt = payment.deletedAt {
                        detailRow("Deleted At", value: deletedAt.formatted(date: .abbreviated, time: .shortened))
                    }

                    if let deleteExpiresAt = payment.deleteExpiresAt {
                        detailRow("Expires", value: deleteExpiresAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }

            if isRecycleBinItem {
                Section {
                    Button("Restore Payment") {
                        showRestoreConfirm = true
                    }
                    .foregroundStyle(.green)
                }
            } else if isEditMode && canEdit {
                Section {
                    Button(paymentsVM.isBusy ? "Saving..." : "Save Changes") {
                        Task { await saveChanges() }
                    }
                    .disabled(paymentsVM.isBusy)
                }
            }
        }
        .navigationTitle(isRecycleBinItem ? "Payment Details" : (isEditMode ? "Edit Payment" : "Payment Details"))
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
                                loadDraftFromPayment()
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
                loadDraftFromPayment()
                isEditMode = false
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your unsaved changes will be lost.")
        }
        .confirmationDialog(
            "Restore Payment?",
            isPresented: $showRestoreConfirm,
            titleVisibility: .visible
        ) {
            Button("Restore") {
                Task {
                    await onRestore?(payment)
                    onChanged?()
                    dismiss()
                }
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This payment will be moved back to the active payments list.")
        }
        .task {
            await loadMembers()
            loadDraftFromPayment()
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

    private func loadDraftFromPayment() {
        amountText = payment.amount == 0 ? "" : String(format: "%.2f", payment.amount)
        noteText = payment.note
        date = payment.date
        paidByUid = payment.paidByUid
        paidToUid = payment.paidToUid ?? ""

        if paidByUid.isEmpty, let first = dashVM.members.first?.uid {
            paidByUid = first
        }

        if paidToUid.isEmpty {
            paidToUid = dashVM.members.first(where: { $0.uid != paidByUid })?.uid ?? ""
        }
    }

    @discardableResult
    private func saveChanges() async -> Bool {
        localError = nil

        guard canEdit else {
            localError = "You do not have permission to edit this payment."
            return false
        }

        guard let user = appState.authUser,
              let homeId = appState.activeHome?.id,
              let paymentId = payment.id else {
            localError = "Missing required payment information."
            return false
        }

        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) else {
            localError = "Amount must be a valid number."
            return false
        }

        let trimmedNote = noteText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !paidByUid.isEmpty else {
            localError = "Select who paid."
            return false
        }

        guard !paidToUid.isEmpty else {
            localError = "Select who received the payment."
            return false
        }

        guard paidByUid != paidToUid else {
            localError = "Paid By and Paid To cannot be the same."
            return false
        }

        let actorName = displayActorName(user: user)

        let success = await paymentsVM.updatePayment(
            homeId: homeId,
            originalPayment: payment,
            amount: amount,
            note: trimmedNote,
            date: date,
            paidByUid: paidByUid,
            paidToUid: paidToUid,
            actorUid: user.uid,
            actorName: actorName
        )

        if success {
            isEditMode = false
            onChanged?()
            return true
        } else {
            localError = paymentsVM.errorMessage
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
