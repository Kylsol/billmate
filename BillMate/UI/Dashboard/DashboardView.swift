//
//  DashboardView.swift
//  BillMate
//
//  Created by Kyle Solomons on 3/1/26.
//

import SwiftUI
import Charts
import FirebaseFirestore

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var homesVM: HomesViewModel

    @StateObject private var dashVM = DashboardViewModel()

    @State private var showHomePicker = false
    @State private var showInviteAlert = false
    @State private var inviteCode: String = ""
    @State private var inviteError: String?

    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []

    @State private var showCopiedAlert = false
    @State private var showRecycleBin = false
    @State private var showHomeSettings = false

    @State private var showFeedSheet = false
    @State private var showAddBillSheet = false
    @State private var showAddPaymentSheet = false
    @State private var showQuickAddOptions = false

    @State private var transactionFilter: DashboardTransactionFilter = .all
    @State private var visibleTransactionCount: Int = 10

    @State private var floatingButtonsVisible = true
    @State private var lastScrollOffset: CGFloat = 0

    @State private var billPendingDelete: BillDoc?
    @State private var paymentPendingDelete: PaymentDoc?
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            dashboardList
                .navigationTitle(appState.activeHome?.name ?? "Dashboard")
                .toolbar { dashboardToolbar }
                .overlay(alignment: .bottomTrailing) {
                    if floatingButtonsVisible {
                        floatingActionButtons
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .sheet(isPresented: $showHomeSettings) {
                    HomeSettingsView()
                        .environmentObject(appState)
                        .environmentObject(homesVM)
                }
                .sheet(isPresented: $showRecycleBin) {
                    RecycleBinView()
                        .environmentObject(appState)
                        .environmentObject(homesVM)
                }
                .sheet(isPresented: $showShareSheet) {
                    ShareSheet(items: shareItems)
                }
                .sheet(isPresented: $showFeedSheet) {
                    NavigationStack {
                        NotificationsView()
                    }
                }
                .sheet(isPresented: $showAddBillSheet) {
                    AddBillView { didAdd in
                        if didAdd {
                            Task { await reload() }
                        }
                    }
                    .environmentObject(appState)
                }
                .sheet(isPresented: $showAddPaymentSheet) {
                    AddPaymentView { didAdd in
                        if didAdd {
                            Task { await reload() }
                        }
                    }
                    .environmentObject(appState)
                }
                
                .alert("Invite Code", isPresented: $showInviteAlert) {
                    Button("Copy Code") {
                        UIPasteboard.general.string = inviteCode
                        showCopiedAlert = true
                    }

                    Button("Share…") {
                        let msg = inviteShareMessage(code: inviteCode)
                        shareItems = [msg]
                        showShareSheet = true
                    }

                    Button("OK", role: .cancel) { }
                } message: {
                    Text(inviteCode)
                }
                .alert("Copied", isPresented: $showCopiedAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("Invite code copied to clipboard.")
                }
                .task {
                    await loadHomes()
                    await reload()
                }
                .onChange(of: transactionFilter) { _, _ in
                    visibleTransactionCount = 10
                }
                .onChange(of: appState.activeHome?.id) { _, _ in
                    visibleTransactionCount = 10
                }
        }
    }

    // MARK: - Main List

    private var dashboardList: some View {
        List {
            if let err = localError {
                Section {
                    Text(err)
                        .foregroundStyle(.red)
                }
            }

            spendingChartSection
            balancesSection
            transactionsSection
        }
        .listStyle(.insetGrouped)
        .coordinateSpace(name: "dashboardScroll")
        .overlay(alignment: .top) {
            GeometryReader { geo in
                Color.clear
                    .preference(
                        key: DashboardScrollOffsetKey.self,
                        value: geo.frame(in: .named("dashboardScroll")).minY
                    )
            }
            .frame(height: 0)
        }
        .onPreferenceChange(DashboardScrollOffsetKey.self) { newValue in
            let delta = newValue - lastScrollOffset

            if delta < -8 {
                withAnimation(.easeInOut(duration: 0.2)) {
                    floatingButtonsVisible = false
                    showQuickAddOptions = false
                }
            } else if delta > 8 {
                withAnimation(.easeInOut(duration: 0.2)) {
                    floatingButtonsVisible = true
                }
            }

            lastScrollOffset = newValue
        }
    }

    // MARK: - Spending Chart

    private var spendingChartSection: some View {
        Section {
            if let uid = appState.authUser?.uid {
                let data = dashVM.monthlySpendingByCategory(for: uid)
                let total = dashVM.monthlyTotalSpent(for: uid)

                if data.isEmpty {
                    VStack(spacing: 10) {
                        Text(currentMonthTitle)
                            .font(.headline)

                        Text("No categorized spending yet.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .padding(.vertical, 8)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(currentMonthTitle)
                            .font(.headline)

                        ZStack {
                            Chart(data) { item in
                                SectorMark(
                                    angle: .value("Amount", item.amount),
                                    innerRadius: .ratio(0.62),
                                    angularInset: 2.0
                                )
                                .cornerRadius(6)
                                .foregroundStyle(colorForCategory(item.category))
                            }
                            .frame(height: 260)

                            VStack(spacing: 4) {
                                Text("Total Spent")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(total, format: .currency(code: currencyCode()))
                                    .font(.title2.bold())
                                    .multilineTextAlignment(.center)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(data) { item in
                                HStack {
                                    Circle()
                                        .fill(colorForCategory(item.category))
                                        .frame(width: 10, height: 10)

                                    Text(item.category)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(item.amount, format: .currency(code: currencyCode()))
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            } else {
                Text("Sign in to view spending.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Balances

    private var balancesSection: some View {
        Section("Balances") {
            if let err = dashVM.errorMessage {
                Text(err)
                    .foregroundStyle(.red)
            }

            if dashVM.balances.isEmpty {
                Text("No data yet. Add bills or payments.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dashVM.balances) { b in
                    NavigationLink {
                        MemberLedgerView(memberUid: b.id, memberName: b.displayName)
                    } label: {
                        HStack {
                            Text(b.displayName)
                                .lineLimit(1)

                            Spacer()

                            Text(b.amountOwed, format: .currency(code: currencyCode()))
                                .foregroundStyle(colorFor(owed: b.amountOwed))
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Transactions

    private var transactionsSection: some View {
        Section {
            Picker("Transaction Filter", selection: $transactionFilter) {
                ForEach(DashboardTransactionFilter.allCases, id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if filteredTransactions.isEmpty {
                Text(emptyTransactionText)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleTransactions) { row in
                    NavigationLink {
                        transactionDestination(for: row)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.title)
                                .font(.headline)

                            HStack {
                                Text(row.amount, format: .currency(code: currencyCode()))
                                    .monospacedDigit()
                                Spacer()
                                Text(row.date, style: .date)
                                    .foregroundStyle(.secondary)
                            }

                            Text(row.subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if appState.activeRole == .admin {

                            switch row.kind {

                            case .bill:
                                if let bill = row.bill,
                                   let billId = bill.id,
                                   let homeId = appState.activeHome?.id {

                                    Button(role: .destructive) {
                                        Task {
                                            await softDeleteBill(homeId: homeId, billId: billId)
                                            await reload()
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }

                            case .payment:
                                if let payment = row.payment,
                                   let paymentId = payment.id,
                                   let homeId = appState.activeHome?.id {

                                    Button(role: .destructive) {
                                        Task {
                                            await softDeletePayment(homeId: homeId, paymentId: paymentId)
                                            await reload()
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }

                if visibleTransactionCount < filteredTransactions.count {
                    Button("Load More") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            visibleTransactionCount += 10
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        } header: {
            Text("Last Transactions")
        }
    }

    private var allTransactions: [DashboardTransactionRow] {
        var rows: [DashboardTransactionRow] = []

        for bill in dashVM.bills {
            let payer = displayName(for: bill.paidByUid)
            let title = bill.description
            let subtitle = "Bill • Paid by \(payer)"

            rows.append(
                DashboardTransactionRow(
                    kind: .bill,
                    id: "bill-\(bill.id ?? UUID().uuidString)",
                    title: title,
                    subtitle: subtitle,
                    amount: bill.amount,
                    date: bill.date,
                    bill: bill,
                    payment: nil
                )
            )
        }

        for payment in dashVM.payments {
            let fromName = displayName(for: payment.paidByUid)
            let subtitle: String

            if let toUid = payment.paidToUid, !toUid.isEmpty {
                let toName = displayName(for: toUid)
                subtitle = "Payment • \(fromName) → \(toName)"
            } else {
                subtitle = "Payment • Paid by \(fromName)"
            }

            let title = payment.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Payment"
                : payment.note

            rows.append(
                DashboardTransactionRow(
                    kind: .payment,
                    id: "payment-\(payment.id ?? UUID().uuidString)",
                    title: title,
                    subtitle: subtitle,
                    amount: payment.amount,
                    date: payment.date,
                    bill: nil,
                    payment: payment
                )
            )
        }

        return rows.sorted { $0.date > $1.date }
    }

    private var filteredTransactions: [DashboardTransactionRow] {
        switch transactionFilter {
        case .all:
            return allTransactions
        case .bills:
            return allTransactions.filter { $0.kind == .bill }
        case .payments:
            return allTransactions.filter { $0.kind == .payment }
        }
    }

    private var visibleTransactions: [DashboardTransactionRow] {
        Array(filteredTransactions.prefix(visibleTransactionCount))
    }

    private var emptyTransactionText: String {
        switch transactionFilter {
        case .all:
            return "No transactions yet."
        case .bills:
            return "No bills yet."
        case .payments:
            return "No payments yet."
        }
    }

    @ViewBuilder
    private func transactionDestination(for row: DashboardTransactionRow) -> some View {
        switch row.kind {
        case .bill:
            if let bill = row.bill {
                BillDetailView(
                    bill: bill,
                    isRecycleBinItem: false,
                    onChanged: {
                        Task { await reload() }
                    }
                )
            } else {
                Text("Bill not found.")
                    .foregroundStyle(.secondary)
            }

        case .payment:
            if let payment = row.payment {
                PaymentDetailView(
                    payment: payment,
                    isRecycleBinItem: false,
                    onChanged: {
                        Task { await reload() }
                    }
                )
            } else {
                Text("Payment not found.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Floating Buttons

    private var floatingActionButtons: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if showQuickAddOptions {
                VStack(alignment: .trailing, spacing: 10) {
                    if appState.activeRole == .admin {
                        Button {
                            showQuickAddOptions = false
                            showAddPaymentSheet = true
                        } label: {
                            floatingLabelButton(
                                icon: "arrow.left.arrow.right",
                                text: "Add Payment"
                            )
                        }

                        Button {
                            showQuickAddOptions = false
                            showAddBillSheet = true
                        } label: {
                            floatingLabelButton(
                                icon: "doc.plaintext",
                                text: "Add Bill"
                            )
                        }
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            VStack(alignment: .trailing, spacing: 12) {
                Button {
                    showFeedSheet = true
                } label: {
                    floatingIconButton(systemImage: "bell")
                }

                if appState.activeRole == .admin {
                    Button {
                        withAnimation(.spring(duration: 0.25)) {
                            showQuickAddOptions.toggle()
                        }
                    } label: {
                        floatingIconButton(systemImage: showQuickAddOptions ? "xmark" : "plus")
                    }
                }
            }
        }
        .padding(.trailing, 20)
        .padding(.bottom, 28)
    }

    private func floatingIconButton(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 54, height: 54)
            .background(Circle().fill(Color.accentColor))
            .shadow(radius: 8, y: 4)
    }

    private func floatingLabelButton(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Text(text)
                .font(.subheadline.weight(.semibold))

            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Capsule().fill(Color.accentColor))
        .shadow(radius: 8, y: 4)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var dashboardToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Homes") {
                appState.resetHomeSelection()
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if appState.activeRole == .admin {
                    Button("Home Settings") {
                        showHomeSettings = true
                    }
                }

                if appState.activeRole == .admin {
                    Button("Create Invite Code") {
                        Task { await createInviteTapped() }
                    }
                }

                Divider()

                Button {
                    showRecycleBin = true
                } label: {
                    Label("Recycle Bin", systemImage: "trash")
                }

                Divider()

                Button("Sign Out", role: .destructive) {
                    appState.signOut()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Actions

    private func createInviteTapped() async {
        guard let homeId = appState.activeHome?.id else {
            inviteError = "No active home selected."
            return
        }

        if let code = await homesVM.createInvite(appState: appState, homeId: homeId) {
            inviteCode = code
            let msg = inviteShareMessage(code: code)
            shareItems = [msg]
            showShareSheet = true
        } else {
            inviteError = homesVM.errorMessage ?? "Failed to create invite."
        }
    }

    private func loadHomes() async {
        guard let uid = appState.authUser?.uid else { return }
        await homesVM.loadHomes(for: uid)
    }

    private func reload() async {
        guard let homeId = appState.activeHome?.id else { return }
        await dashVM.loadAll(homeId: homeId)
        visibleTransactionCount = 10
    }

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
                changedField: nil,
                oldValue: nil,
                newValue: nil,
                changeCount: nil,
                createdAt: Date()
            )

            _ = try? FirestoreService.eventsCol(homeId).addDocument(from: event)

        } catch {
            localError = error.localizedDescription
        }
    }

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
                changedField: nil,
                oldValue: nil,
                newValue: nil,
                changeCount: nil,
                createdAt: Date()
            )

            _ = try? FirestoreService.eventsCol(homeId).addDocument(from: event)

        } catch {
            localError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func colorForCategory(_ category: String) -> Color {
        switch category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "food":
            return .orange
        case "transport":
            return .blue
        case "utilities":
            return .yellow
        case "entertainment":
            return .purple
        case "rent":
            return .red
        case "groceries":
            return .green
        case "dining out":
            return .mint
        case "household":
            return .brown
        case "internet":
            return .indigo
        case "phone":
            return .cyan
        case "subscriptions":
            return .pink
        case "health":
            return .teal
        case "education":
            return .gray
        case "travel":
            return .accentColor
        default:
            return .secondary
        }
    }

    private var currentMonthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL"
        return formatter.string(from: Date())
    }

    private func displayName(for uid: String) -> String {
        if let member = dashVM.members.first(where: { $0.uid == uid }) {
            let trimmed = (member.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
            if let email = member.email, !email.isEmpty { return email }
        }
        return uid
    }

    private func colorFor(owed: Double) -> Color {
        if owed > 0 { return .red }
        if owed < 0 { return .green }
        return .primary
    }

    private func currencyCode() -> String {
        Locale.current.currency?.identifier ?? "USD"
    }

    private func inviteShareMessage(code: String) -> String {
        let homeName = appState.activeHome?.name ?? "my home"
        return """
        Join \(homeName) on BillMate.

        Invite code: \(code)
        """
    }
}

// MARK: - Filters

private enum DashboardTransactionFilter: String, CaseIterable {
    case all = "All"
    case bills = "Bills"
    case payments = "Payments"
}

// MARK: - Transactions

private struct DashboardTransactionRow: Identifiable {
    enum Kind {
        case bill
        case payment
    }

    let kind: Kind
    let id: String
    let title: String
    let subtitle: String
    let amount: Double
    let date: Date
    let bill: BillDoc?
    let payment: PaymentDoc?
}

// MARK: - Scroll Tracking

private struct DashboardScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct HomePickerSheet: View {
    let homes: [HomeDoc]
    let onSelect: (HomeDoc) -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List(homes) { h in
                Button(h.name) { onSelect(h) }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { onClose() }
                }
            }
        }
    }
}
