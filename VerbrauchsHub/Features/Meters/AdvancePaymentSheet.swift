import SwiftUI
import SwiftData

/// Adds or edits one advance payment (Abschlag) of a meter.
struct AdvancePaymentSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let meter: Meter
    /// The entry to edit; `nil` adds a new one.
    var payment: AdvancePayment?

    @State private var amountText = ""
    @State private var validFrom: Date = .now
    @State private var didLoad = false
    @State private var showDeleteConfirm = false

    private var parsedAmount: Decimal? {
        guard let value = Formatting.parseDecimal(amountText), value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Betrag pro Monat", text: $amountText)
                            .keyboardType(.decimalPad)
                        Text("€").foregroundStyle(.secondary)
                    }
                    DatePicker("Gültig ab", selection: $validFrom, displayedComponents: .date)
                } footer: {
                    Text("Der vorherige Abschlag endet automatisch an diesem Tag. Ein Datum in der Zukunft legt den Abschlag als geplant an.")
                }
                if payment != nil {
                    Section {
                        Button("Abschlag löschen", role: .destructive) { showDeleteConfirm = true }
                    }
                }
            }
            .navigationTitle(payment == nil ? "Neuer Abschlag" : "Abschlag bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }.disabled(parsedAmount == nil)
                }
            }
            .confirmationDialog("Abschlag löschen?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) { delete() }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let payment else { return }
        amountText = Formatting.inputString(payment.amountPerMonth)
        validFrom = payment.validFrom
    }

    private func save() {
        guard let amount = parsedAmount else { return }
        let entry: AdvancePayment
        if let payment {
            payment.amountPerMonth = amount
            payment.validFrom = validFrom
            entry = payment
        } else {
            entry = AdvancePayment(meter: meter, amountPerMonth: amount, validFrom: validFrom)
            context.insert(entry)
        }
        finish(remaining: meter.advancePayments.filter { $0.id != entry.id } + [entry])
    }

    private func delete() {
        guard let payment else { return }
        let id = payment.id
        context.delete(payment)
        finish(remaining: meter.advancePayments.filter { $0.id != id })
    }

    private func finish(remaining: [AdvancePayment]) {
        ValidityChain.relink(remaining)
        // The history replaces the single 1.1 value; clear it so the migration never brings it back.
        meter.advancePaymentPerMonth = nil
        try? context.save()
        dismiss()
    }
}
