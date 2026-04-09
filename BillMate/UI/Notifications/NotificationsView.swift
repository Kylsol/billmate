//
//  NotificationsView.swift
//  BillMate
//
//  Created by Kyle Solomons on 2/23/26.
//

import SwiftUI
import FirebaseFirestore

struct NotificationsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = EventsViewModel()

    @State private var filter: ActivityFilter = .all

    var body: some View {
        List {
            Section {
                Picker("Filter", selection: $filter) {
                    ForEach(ActivityFilter.allCases, id: \.self) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }

            if let err = vm.errorMessage {
                Text(err)
                    .foregroundStyle(.red)
            }

            if filteredEvents.isEmpty {
                Text(emptyStateText)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredEvents) { event in
                    NavigationLink {
                        destinationView(for: event)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(vm.titleText(for: event))
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(vm.subtitleText(for: event))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text(vm.displayDate(for: event))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(!vm.hasDestination(for: event))
                }
            }
        }
        .navigationTitle("Activity")
        .task {
            guard let homeId = appState.activeHome?.id else { return }
            await vm.load(homeId: homeId)
        }
    }

    private var filteredEvents: [EventDoc] {
        switch filter {
        case .all:
            return vm.events
        case .bills:
            return vm.events.filter { vm.isBillEvent($0) }
        case .payments:
            return vm.events.filter { vm.isPaymentEvent($0) }
        case .updates:
            return vm.events.filter { vm.isUpdateEvent($0) }
        }
    }

    private var emptyStateText: String {
        switch filter {
        case .all:
            return "No activity yet."
        case .bills:
            return "No bill activity yet."
        case .payments:
            return "No payment activity yet."
        case .updates:
            return "No updates yet."
        }
    }

    @ViewBuilder
    private func destinationView(for event: EventDoc) -> some View {
        switch event.targetType {
        case "bill":
            if let bill = vm.bill(for: event) {
                BillDetailView(
                    bill: bill,
                    isRecycleBinItem: (bill.isDeleted ?? false),
                    onChanged: {
                        Task {
                            guard let homeId = appState.activeHome?.id else { return }
                            await vm.load(homeId: homeId)
                        }
                    },
                    onRestore: { restoredBill in
                        await restoreBillFromFeed(restoredBill)
                    }
                )
            } else {
                Text("Bill not found.")
                    .foregroundStyle(.secondary)
            }

        case "payment":
            if let payment = vm.payment(for: event) {
                PaymentDetailView(
                    payment: payment,
                    isRecycleBinItem: (payment.isDeleted ?? false),
                    onChanged: {
                        Task {
                            guard let homeId = appState.activeHome?.id else { return }
                            await vm.load(homeId: homeId)
                        }
                    },
                    onRestore: { restoredPayment in
                        await restorePaymentFromFeed(restoredPayment)
                    }
                )
            } else {
                Text("Payment not found.")
                    .foregroundStyle(.secondary)
            }

        default:
            Text("No detail available.")
                .foregroundStyle(.secondary)
        }
    }

    private func restoreBillFromFeed(_ bill: BillDoc) async {
        guard appState.activeRole == .admin,
              let homeId = appState.activeHome?.id,
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

            await vm.load(homeId: homeId)
        } catch {
            vm.errorMessage = error.localizedDescription
        }
    }

    private func restorePaymentFromFeed(_ payment: PaymentDoc) async {
        guard appState.activeRole == .admin,
              let homeId = appState.activeHome?.id,
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

            await vm.load(homeId: homeId)
        } catch {
            vm.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Filter

private enum ActivityFilter: String, CaseIterable {
    case all = "All"
    case bills = "Bills"
    case payments = "Payments"
    case updates = "Updates"
}
