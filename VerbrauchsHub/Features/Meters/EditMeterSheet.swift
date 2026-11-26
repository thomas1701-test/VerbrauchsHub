import SwiftUI
import SwiftData

/// Name, advance payment, billing period and annual goal of a meter.
struct EditMeterSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var meter: Meter

    @State private var name = ""
    @State private var showAddAdvance = false
    @State private var editingAdvance: AdvancePayment?
    @State private var billingStart = Date.now
    @State private var targetText = ""
    @State private var didLoad = false
    @State private var validationError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Bezeichnung") {
                    TextField(meter.type.localizedName, text: $name)
                }

                if !meter.type.isFeedIn {
                    Section {
                        ForEach(sortedAdvances) { payment in
                            Button {
                                editingAdvance = payment
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(Formatting.currency(payment.amountPerMonth)) pro Monat")
                                            .foregroundStyle(.primary)
                                        Text("ab \(Formatting.date.string(from: payment.validFrom))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    ValidityBadge(status: payment.status(on: .now))
                                }
                            }
                        }
                        .onDelete(perform: deleteAdvances)
                        Button {
                            showAddAdvance = true
                        } label: {
                            Label("Abschlag hinzufügen", systemImage: "plus")
                        }
                        DatePicker("Abrechnungszeitraum ab", selection: $billingStart, displayedComponents: .date)
                    } header: {
                        Text("Abschlag & Abrechnung")
                    } footer: {
                        Text("Mit Abschlag, Beginn des Abrechnungsjahres und einem Tarif zeigt VerbrauchsHub die voraussichtliche Nachzahlung oder Erstattung.")
                    }
                }

                Section {
                    HStack {
                        TextField("Jahresziel", text: $targetText)
                            .keyboardType(.decimalPad)
                        Text(meter.unitLabel).foregroundStyle(.secondary)
                    }
                } header: {
                    Text(meter.type.isFeedIn ? "Ziel pro Jahr" : "Verbrauchsziel pro Jahr")
                } footer: {
                    Text("Leer lassen, wenn du kein Ziel verfolgen möchtest.")
                }

                if let validationError {
                    Text(validationError).foregroundStyle(.red).font(.caption)
                }
            }
            .navigationTitle("Zähler bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                }
            }
            .onAppear(perform: load)
            .sheet(isPresented: $showAddAdvance) { AdvancePaymentSheet(meter: meter) }
            .sheet(item: $editingAdvance) { AdvancePaymentSheet(meter: meter, payment: $0) }
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        name = meter.customName ?? ""
        billingStart = meter.billingStartDate ?? Self.defaultBillingStart()
        targetText = meter.annualTarget.map(Formatting.inputString) ?? ""
    }

    private func save() {
        let target = parseOptional(targetText)
        guard target != .invalid else {
            validationError = "Bitte gültige Zahlen eingeben."
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        meter.customName = trimmed.isEmpty ? nil : trimmed
        meter.billingStartDate = meter.advancePayments.isEmpty ? nil : billingStart
        meter.annualTarget = target.value
        try? context.save()
        dismiss()
    }

    private var sortedAdvances: [AdvancePayment] {
        meter.advancePayments.sorted { $0.validFrom > $1.validFrom }
    }

    private func deleteAdvances(_ offsets: IndexSet) {
        let removed = offsets.map { sortedAdvances[$0] }
        let removedIDs = Set(removed.map(\.id))
        for payment in removed { context.delete(payment) }
        ValidityChain.relink(meter.advancePayments.filter { !removedIDs.contains($0.id) })
        meter.advancePaymentPerMonth = nil
        try? context.save()
    }

    private enum Parsed: Equatable {
        case empty, invalid, value(Decimal)
        var value: Decimal? { if case .value(let v) = self { v } else { nil } }
    }

    private func parseOptional(_ text: String) -> Parsed {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .empty }
        guard let value = Formatting.parseDecimal(trimmed), value > 0 else { return .invalid }
        return .value(value)
    }

    /// 1 January of the current year – the most common billing start.
    private static func defaultBillingStart() -> Date {
        Calendar.current.dateInterval(of: .year, for: .now)?.start ?? .now
    }
}
