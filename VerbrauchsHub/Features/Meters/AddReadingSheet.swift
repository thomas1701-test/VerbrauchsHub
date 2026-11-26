import SwiftUI
import SwiftData
import PhotosUI

/// Adds a new reading or edits an existing one.
struct AddReadingSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let meter: Meter
    /// The reading to edit; `nil` adds a new one.
    var reading: Reading?

    @State private var date: Date = .now
    @State private var valueText: String = ""
    @State private var note: String = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var validationError: String?
    @State private var pendingCheck: ReadingCheck?
    @State private var showCamera = false
    @State private var showPhoto = false
    @State private var showDeleteConfirm = false
    @State private var isRecognizing = false
    @State private var suggestions: [Decimal] = []
    @State private var didLoad = false
    @State private var isMeterChange = false
    @State private var oldFinalText = ""
    @FocusState private var oldFinalFocused: Bool

    private var isEditing: Bool { reading != nil }

    private var previousValue: Decimal? {
        meter.readings.filter { $0.date < date && $0 !== reading }.sorted { $0.date > $1.date }.first?.value
    }

    private var parsedValue: Decimal? {
        Formatting.parseDecimal(valueText)
    }

    private var parsedOldFinal: Decimal? {
        Formatting.parseDecimal(oldFinalText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                    Toggle("Zählerwechsel", isOn: $isMeterChange.animation())
                    if isMeterChange {
                        HStack {
                            TextField("Endstand alter Zähler", text: $oldFinalText)
                                .keyboardType(.decimalPad)
                                .monospacedDigit()
                                .focused($oldFinalFocused)
                            Text(meter.unitLabel).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        TextField(isMeterChange ? "Startstand neuer Zähler" : "Zählerstand", text: $valueText)
                            .keyboardType(.decimalPad)
                            .monospacedDigit()
                        Text(meter.unitLabel).foregroundStyle(.secondary)
                    }
                    if let prev = previousValue {
                        Text("Vorheriger Wert: \(Formatting.counter(prev, unit: meter.unitLabel))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if isRecognizing {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Zählerstand wird erkannt …").font(.caption).foregroundStyle(.secondary)
                        }
                    } else if !suggestions.isEmpty {
                        suggestionRow
                    }
                } header: {
                    Text("Ablesung")
                } footer: {
                    if isMeterChange {
                        Text("Endstand vom alten Zähler und Startstand vom neuen, beide vom Wechseltag.")
                    }
                }
                Section {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Zähler fotografieren", systemImage: "camera.fill")
                        }
                    }
                    let pickerTitle = photoData == nil ? "Foto aus Mediathek" : "Anderes Foto wählen"
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(pickerTitle, systemImage: "photo.on.rectangle")
                    }
                    if let data = photoData, let ui = UIImage(data: data) {
                        Button {
                            showPhoto = true
                        } label: {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Foto vergrößern")
                        Button("Foto entfernen", role: .destructive) {
                            photoData = nil
                            photoItem = nil
                            suggestions = []
                        }
                    }
                } header: {
                    Text("Foto")
                } footer: {
                    Text("VerbrauchsHub liest den Zählerstand aus dem Foto und schlägt ihn vor. Bitte prüfe den Wert vor dem Speichern.")
                }
                Section("Notiz") {
                    TextField("Notiz (optional)", text: $note, axis: .vertical)
                }
                if let err = validationError {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
                if isEditing {
                    Section {
                        Button("Ablesung löschen", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Ablesung bearbeiten" : "Neue Ablesung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                }
            }
            .alert(checkTitle, isPresented: Binding(
                get: { pendingCheck != nil },
                set: { if !$0 { pendingCheck = nil } }
            )) {
                if case .lowerThanPrevious = pendingCheck, !isMeterChange {
                    Button("Das war ein Zählerwechsel") {
                        isMeterChange = true
                        oldFinalText = ""
                        oldFinalFocused = true
                    }
                }
                Button("Trotzdem speichern") { store() }
                Button("Korrigieren", role: .cancel) {}
            } message: {
                Text(checkMessage)
            }
            .confirmationDialog("Ablesung löschen?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) { deleteReading() }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { data in
                    setPhoto(data)
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showPhoto) {
                if let data = photoData, let ui = UIImage(data: data) {
                    PhotoViewer(image: ui)
                }
            }
            .task(id: photoItem) {
                if let item = photoItem,
                   let data = try? await item.loadTransferable(type: Data.self) {
                    setPhoto(data)
                }
            }
            .onAppear(perform: loadReading)
        }
    }

    private var suggestionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Erkannt – zum Übernehmen tippen:")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(suggestions, id: \.self) { value in
                        Button(Formatting.counter(value, unit: meter.unitLabel)) {
                            valueText = Formatting.inputString(value)
                        }
                        .buttonStyle(.bordered)
                        .monospacedDigit()
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func loadReading() {
        guard !didLoad else { return }
        didLoad = true
        guard let reading else { return }
        date = reading.date
        valueText = Formatting.inputString(reading.value)
        note = reading.note ?? ""
        photoData = reading.photoData
        if let finalValue = reading.previousMeterFinalValue {
            isMeterChange = true
            oldFinalText = Formatting.inputString(finalValue)
        }
    }

    private func setPhoto(_ data: Data) {
        photoData = data
        suggestions = []
        isRecognizing = true
        let previous = previousValue
        Task {
            let values = await MeterValueRecognizer.recognize(imageData: data, previous: previous)
            isRecognizing = false
            suggestions = values
            if valueText.isEmpty, let best = values.first {
                valueText = Formatting.inputString(best)
            }
        }
    }

    private func save() {
        guard parsedValue != nil else {
            validationError = "Bitte gültigen Zahlenwert eingeben."
            return
        }
        if isMeterChange && parsedOldFinal == nil {
            validationError = "Bitte den Endstand des alten Zählers eintragen."
            return
        }
        validationError = nil
        if let check = ReadingCheck.evaluate(value: parsedValue!, date: date, readings: meter.readings, editing: reading, previousMeterFinalValue: isMeterChange ? parsedOldFinal : nil) {
            pendingCheck = check
            return
        }
        store()
    }

    private func store() {
        guard let value = parsedValue else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldFinal = isMeterChange ? parsedOldFinal : nil
        if let reading {
            reading.date = date
            reading.value = value
            reading.note = trimmedNote.isEmpty ? nil : trimmedNote
            reading.photoData = photoData
            reading.previousMeterFinalValue = oldFinal
        } else {
            let newReading = Reading(meter: meter, date: date, value: value, note: trimmedNote.isEmpty ? nil : trimmedNote, photoData: photoData, previousMeterFinalValue: oldFinal)
            context.insert(newReading)
        }
        try? context.save()
        dismiss()
    }

    private func deleteReading() {
        guard let reading else { return }
        context.delete(reading)
        try? context.save()
        dismiss()
    }

    private var checkTitle: String {
        switch pendingCheck {
        case .lowerThanPrevious: "Zählerstand niedriger als zuvor"
        case .unusuallyHigh: "Ungewöhnlich hoher Verbrauch"
        case nil: ""
        }
    }

    private var checkMessage: String {
        switch pendingCheck {
        case .lowerThanPrevious(let previous):
            "Der Wert ist kleiner als die vorherige Ablesung (\(Formatting.counter(previous, unit: meter.unitLabel))). War es ein Zählerwechsel, trag den Endstand des alten Zählers ein, damit kein Verbrauch verloren geht."
        case .unusuallyHigh(let factor):
            factor > 20
                ? "Seit der letzten Ablesung wäre der Verbrauch ein Vielfaches des üblichen Werts. Bitte prüfe, ob du dich vertippt hast."
                : "Seit der letzten Ablesung wäre der Verbrauch etwa \(factor)-mal so hoch wie üblich. Bitte prüfe, ob du dich vertippt hast."
        case nil:
            ""
        }
    }
}

/// Full-screen photo with pinch to zoom.
struct PhotoViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        NavigationStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(MagnifyGesture().onChanged { scale = max(1, $0.magnification) }.onEnded { _ in
                    withAnimation { scale = 1 }
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { dismiss() }
                    }
                }
        }
    }
}

/// System camera; returns the photo as JPEG.
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.8) {
                parent.onCapture(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
