import SwiftUI

struct AddPaymentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var dashboardVM = DashboardViewModel()
    @StateObject private var paymentsVM = PaymentsViewModel()

    @State private var amountText: String = ""
    @State private var note: String = ""
    @State private var date: Date = Date()
    @State private var paidByUid: String = ""
    @State private var paidToUid: String = ""

    let onDone: (Bool) -> Void

    var body: some View {
        NavigationStack {
            Form {

                if appState.activeRole != .admin {
                    Section {
                        Text("Residents cannot add payments.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Payment Details") {
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)

                    TextField("Note", text: $note)

                    DatePicker("Date",
                               selection: $date,
                               displayedComponents: .date)
                }

                Section("Paid By") {
                    Picker("Member", selection: $paidByUid) {
                        ForEach(dashboardVM.members, id: \.uid) { member in
                            Text(member.name ?? member.email ?? member.uid)
                                .tag(member.uid)
                        }
                    }
                    .onChange(of: paidByUid) { _, newPaidBy in
                        if paidToUid.isEmpty || paidToUid == newPaidBy {
                            paidToUid = dashboardVM.members.first(where: { $0.uid != newPaidBy })?.uid ?? ""
                        }
                    }
                }

                Section("Paid To") {
                    Picker("Member", selection: $paidToUid) {
                        ForEach(dashboardVM.members, id: \.uid) { member in
                            Text(member.name ?? member.email ?? member.uid)
                                .tag(member.uid)
                        }
                    }
                }

                if let error = paymentsVM.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(paymentsVM.isBusy ? "Saving..." : "Add Payment") {
                        Task { await savePayment() }
                    }
                    .disabled(paymentsVM.isBusy || appState.activeRole != .admin)
                }
            }
            .navigationTitle("Add Payment")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                Task { await loadMembers() }
            }
        }
    }

    // MARK: - Private

    private func loadMembers() async {
        guard let homeId = appState.activeHome?.id else { return }

        await dashboardVM.loadAll(homeId: homeId)

        if paidByUid.isEmpty, let first = dashboardVM.members.first?.uid {
            paidByUid = first
        }

        if paidToUid.isEmpty {
            paidToUid = dashboardVM.members.first(where: { $0.uid != paidByUid })?.uid ?? ""
        }
    }

    private func savePayment() async {
        guard let user = appState.authUser,
              let homeId = appState.activeHome?.id else { return }

        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) else {
            paymentsVM.errorMessage = "Amount must be a valid number."
            return
        }

        guard !paidByUid.isEmpty else {
            paymentsVM.errorMessage = "Select who paid."
            return
        }

        guard !paidToUid.isEmpty else {
            paymentsVM.errorMessage = "Select who received the payment."
            return
        }

        guard paidByUid != paidToUid else {
            paymentsVM.errorMessage = "Paid By and Paid To cannot be the same."
            return
        }

        let payment = PaymentDoc(
            id: nil,
            amount: amount,
            date: date,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            paidByUid: paidByUid,
            paidToUid: paidToUid,
            createdAt: Date(),
            createdByUid: user.uid,
            updatedAt: nil,
            updatedByUid: nil
        )

        await paymentsVM.addPayment(homeId: homeId, payment: payment)

        if paymentsVM.errorMessage == nil {
            onDone(true)
            dismiss()
        }
    }
}
