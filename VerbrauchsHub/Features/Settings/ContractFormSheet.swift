import SwiftUI
import SwiftData

/// Creates a contract with its first price (and optionally an advance payment), or edits one.
struct ContractFormSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let meter: Meter
    /// The contract to edit; `nil` creates a new one.
    var contract: Contract?

    private enum Renewal: Hashable { case indefinite, automatic }

    @State private var provider = ""
    @State private var customerNumber = ""
    @State private var contractNumber = ""
    @State private var startDate: Date = .now
    @State private var hasMinimumTerm = false
    @State private var minimumTermEnd: Date = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var renewal: Renewal = .indefinite
    @State private var renewalMonths = 12
    @State private var hasNotice = false
    @State private var noticeValue = 1
    @State private var noticeUnit: NoticeUnit = .months
    @State private var hasGuarantee = false
    @State private var guaranteeUntil: Date = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var reminderEnabled = true
    @State private var reminderLeadDays = 30
    @State private var notes = ""
    // New contract only.
    @State private var priceText = ""
    @State private var baseFeeText = ""
    @State private var feedInText = ""
    @State private var advanceText = ""

    @State private var didLoad = false
    @State private var showDeleteConfirm = false
    @State private var showNewTariff = false
    @State private var editingTariff: Tariff?

    private var isNew: Bool { contract == nil }

    private var canSave: Bool {
        !provider.trimmingCharacters(in: .whitespaces).isEmpty
            && (!isNew || Formatting.parseDecimal(priceText) != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Anbieter") {
                    TextField("Anbieter", text: $provider)
                    TextField("Kundennummer (optional)", text: $customerNumber)
                    TextField("Vertragsnummer (optional)", text: $contractNumber)
                }
                Section {
                    DatePicker("Vertragsbeginn", selection: $startDate, displayedComponents: .date)
                    Toggle("Mindestlaufzeit", isOn: $hasMinimumTerm.animation())
                    if hasMinimumTerm {
                        DatePicker("Läuft mindestens bis", selection: $minimumTermEnd, displayedComponents: .date)
                        Picker("Danach", selection: $renewal) {
                            Text("Unbefristet, kündbar mit Frist").tag(Renewal.indefinite)
                            Text("Verlängert sich automatisch").tag(Renewal.automatic)
                        }
                        if renewal == .automatic {
                            Stepper("Um \(renewalMonths) Monate", value: $renewalMonths, in: 1...36)
                        }
                    }
                } header: {
                    Text("Laufzeit")
                }
                Section {
                    Toggle("Kündigungsfrist", isOn: $hasNotice.animation())
                    if hasNotice {
                        Stepper("\(noticeValue) \(noticeUnit.label(noticeValue))", value: $noticeValue, in: 1...52)
                        Picker("Einheit", selection: $noticeUnit) {
                            Text("Wochen").tag(NoticeUnit.weeks)
                            Text("Monate").tag(NoticeUnit.months)
                        }
                        .pickerStyle(.segmented)
                    }
                    Toggle("Preisgarantie", isOn: $hasGuarantee.animation())
                    if hasGuarantee {
                        DatePicker("Bis", selection: $guaranteeUntil, displayedComponents: .date)
                    }
                } header: {
                    Text("Kündigung & Preisgarantie")
                }
                Section {
                    Toggle("Erinnern", isOn: $reminderEnabled)
                    if reminderEnabled {
                        Stepper("\(reminderLeadDays) Tage vorher", value: $reminderLeadDays, in: 1...90)
                    }
                } header: {
                    Text("Erinnerung")
                } footer: {
                    Text("VerbrauchsHub erinnert dich vor dem letzten Kündigungstag und vor dem Ende der Preisgarantie.")
                }

                if isNew {
                    Section {
                        PriceFields(meter: meter, priceText: $priceText, baseFeeText: $baseFeeText, feedInText: $feedInText)
                    } header: {
                        Text("Preis ab Vertragsbeginn")
                    } footer: {
                        Text("Spätere Preisanpassungen fügst du dem Vertrag als neuen Preis hinzu.")
                    }
                    if !meter.type.isFeedIn {
                        Section {
                            HStack {
                                TextField("Abschlag pro Monat (optional)", text: $advanceText)
                                    .keyboardType(.decimalPad)
                                Text("€").foregroundStyle(.secondary)
                            }
                        } header: {
                            Text("Abschlag")
                        }
                    }
                } else if let contract {
                    Section("Preise") {
                        ForEach(contract.tariffs.sorted { $0.validFrom > $1.validFrom }) { tariff in
                            Button { editingTariff = tariff } label: {
                                TariffRow(tariff: tariff, unitLabel: meter.unitLabel)
                            }
                            .buttonStyle(.plain)
                        }
                        Button { showNewTariff = true } label: {
                            Label("Preis hinzufügen", systemImage: "plus")
                        }
                    }
                }

                Section("Notiz") {
                    TextField("Notiz (optional)", text: $notes, axis: .vertical)
                }
                if !isNew {
                    Section {
                        Button("Vertrag löschen", role: .destructive) { showDeleteConfirm = true }
                    }
                }
            }
            .navigationTitle(isNew ? "Neuer Vertrag" : "Vertrag bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }.disabled(!canSave)
                }
            }
            .confirmationDialog("Vertrag löschen?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) { delete() }
            } message: {
                Text("Der Vertrag und seine \(contract?.tariffs.count ?? 0) Preise werden gelöscht.")
            }
            .sheet(isPresented: $showNewTariff) { TariffFormSheet(meter: meter, contract: contract) }
            .sheet(item: $editingTariff) { TariffFormSheet(meter: meter, contract: contract, tariff: $0) }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let contract else { return }
        provider = contract.provider
        customerNumber = contract.customerNumber ?? ""
        contractNumber = contract.contractNumber ?? ""
        startDate = contract.startDate
        if let end = contract.minimumTermEnd {
            hasMinimumTerm = true
            minimumTermEnd = end
        }
        if let months = contract.renewalMonths {
            renewal = .automatic
            renewalMonths = months
        }
        if let value = contract.noticePeriodValue, let unit = contract.noticeUnit {
            hasNotice = true
            noticeValue = value
            noticeUnit = unit
        }
        if let guarantee = contract.priceGuaranteeUntil {
            hasGuarantee = true
            guaranteeUntil = guarantee
        }
        reminderEnabled = contract.reminderEnabled
        reminderLeadDays = contract.reminderLeadDays
        notes = contract.notes ?? ""
    }

    private func save() {
        let target: Contract
        if let contract {
            target = contract
        } else {
            target = Contract(meter: meter, provider: "", startDate: startDate)
            context.insert(target)
        }
        apply(to: target)

        if isNew, let price = Formatting.parseDecimal(priceText) {
            let tariff = Tariff(
                meter: meter,
                pricePerUnit: price,
                baseFeePerMonth: Formatting.parseDecimal(baseFeeText) ?? 0,
                feedInPricePerUnit: Formatting.parseDecimal(feedInText),
                validFrom: startDate
            )
            tariff.contract = target
            context.insert(tariff)
            ValidityChain.relink(meter.tariffs.filter { $0.id != tariff.id } + [tariff])

            if let advance = Formatting.parseDecimal(advanceText), advance > 0 {
                let payment = AdvancePayment(meter: meter, amountPerMonth: advance, validFrom: startDate)
                context.insert(payment)
                ValidityChain.relink(meter.advancePayments.filter { $0.id != payment.id } + [payment])
                meter.advancePaymentPerMonth = nil
            }
        }
        try? context.save()

        let wantsReminder = target.reminderEnabled
        Task {
            if wantsReminder { _ = await NotificationService.shared.requestPermissionIfNeeded() }
            NotificationService.shared.scheduleContractReminders(for: target)
        }
        dismiss()
    }

    private func apply(to contract: Contract) {
        contract.provider = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        contract.customerNumber = trimmedOrNil(customerNumber)
        contract.contractNumber = trimmedOrNil(contractNumber)
        contract.startDate = startDate
        contract.minimumTermEnd = hasMinimumTerm ? minimumTermEnd : nil
        contract.renewalMonths = hasMinimumTerm && renewal == .automatic ? renewalMonths : nil
        contract.noticePeriodValue = hasNotice ? noticeValue : nil
        contract.noticeUnit = hasNotice ? noticeUnit : nil
        contract.priceGuaranteeUntil = hasGuarantee ? guaranteeUntil : nil
        contract.reminderEnabled = reminderEnabled
        contract.reminderLeadDays = reminderLeadDays
        contract.notes = trimmedOrNil(notes)
    }

    private func trimmedOrNil(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func delete() {
        guard let contract else { return }
        NotificationService.shared.cancelContractReminders(for: contract)
        let removedIDs = Set(contract.tariffs.map(\.id))
        context.delete(contract)
        ValidityChain.relink(meter.tariffs.filter { !removedIDs.contains($0.id) })
        try? context.save()
        dismiss()
    }
}
