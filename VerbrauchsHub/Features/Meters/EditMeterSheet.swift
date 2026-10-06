import SwiftUI
import SwiftData

/// Name, advance payment, billing period and annual goal of a meter.
struct EditMeterSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var meter: Meter

    @State private var name = ""
    @State private var advanceText = ""
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
                        HStack {
                            TextField("Monatlicher Abschlag", text: $advanceText)
                                .keyboardType(.decimalPad)
                            Text("€").foregroundStyle(.secondary)
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
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        name = meter.customName ?? ""
        advanceText = meter.advancePaymentPerMonth.map(Formatting.inputString) ?? ""
        billingStart = meter.billingStartDate ?? Self.defaultBillingStart()
        targetText = meter.annualTarget.map(Formatting.inputString) ?? ""
    }

    private func save() {
        let advance = parseOptional(advanceText)
        let target = parseOptional(targetText)
        guard advance != .invalid, target != .invalid else {
            validationError = "Bitte gültige Zahlen eingeben."
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        meter.customName = trimmed.isEmpty ? nil : trimmed
        meter.advancePaymentPerMonth = advance.value
        meter.billingStartDate = advance.value == nil ? nil : billingStart
        meter.annualTarget = target.value
        try? context.save()
        dismiss()
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
