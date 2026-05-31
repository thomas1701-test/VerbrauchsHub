# VerbrauchsHub — Design Spec

**Datum:** 2026-05-31
**Plattform:** iOS 18+
**Stack:** SwiftUI · SwiftData · Swift Charts
**Distribution:** Lokal (Single-User, lokaler Speicher), Mehrgebäude-fähig

## 1 Zweck

Eine iOS-App zur Erfassung und Auswertung von Verbrauchsdaten verschiedener Hausanschlüsse (Strom, PV-Einspeisung, Wasser, Gas, Wärme, frei definierbare Zähler) mit:

- Zählerstand-basierter Eingabe
- Periodenauswertung Tag / Woche / Monat / Quartal / Jahr
- Charts, Vergleichen, Trends, Jahreshochrechnung, Kostenrechnung, PV-Energiebilanz
- Unterstützung mehrerer Gebäude (z. B. zwei Häuser)
- Vollständig lokal, mit manuellem Export/Import zusätzlich zum iOS-Backup

## 2 App-Navigation

`TabView` mit vier Tabs. In der Toolbar oben rechts: **Gebäude-Switcher** (Menu), Auswahl „Alle Gebäude" oder ein einzelnes. Bei nur einem Gebäude ist der Switcher ausgeblendet.

| Tab | Inhalt |
|---|---|
| Übersicht | Dashboard mit einer Karte pro Zähler: aktuelle Periode, Verbrauch, Trend zur Vorperiode, Mini-Sparkline |
| Zähler | Liste aller Zähler; Detailansicht mit Ablesungs-Historie und FAB für neue Ablesung |
| Statistik | Großer Chart mit Periodenwähler, Vergleichsmodus, Zähler-Filter |
| Einstellungen | Gebäude, Tarife, Erinnerungen, Export/Import, App-Info |

## 3 Datenmodell (SwiftData)

```
Building
  id: UUID
  name: String
  address: String?
  iconName: String
  colorHex: String
  notes: String?
  createdAt: Date
  meters: [Meter] (cascade)

Meter
  id: UUID
  building: Building
  type: MeterType (enum, raw string)
  customName: String?
  unit: Unit (enum, raw string)
  unitCustomLabel: String?
  iconName: String
  colorHex: String
  reminderEnabled: Bool
  reminderDayOfMonth: Int? (1..28)
  createdAt: Date
  readings: [Reading] (cascade)
  tariffs: [Tariff] (cascade)

Reading
  id: UUID
  meter: Meter
  date: Date (auf Tagesgenauigkeit, Uhrzeit Default 12:00)
  value: Decimal (kumulierter Zählerstand)
  note: String?
  photoData: Data? (optional, JPEG)
  createdAt: Date

Tariff
  id: UUID
  meter: Meter
  pricePerUnit: Decimal              // €/kWh, €/m³, ...
  baseFeePerMonth: Decimal           // €/Monat Grundgebühr
  feedInPricePerUnit: Decimal?       // für Einspeise-Zähler
  validFrom: Date
  validTo: Date?                     // nil = aktuell gültig
  createdAt: Date
```

**Enums:**

```swift
enum MeterType: String, Codable, CaseIterable {
  case electricity, electricityFeedIn, electricitySelfConsumption,
       water, gas, heating, custom
}

enum Unit: String, Codable, CaseIterable {
  case kWh, cubicMeter, liter, custom
}
```

**Defaults pro `MeterType`:** Standardname, Icon (SF Symbol), Farbe, Default-Unit. Bei `custom` setzt der User alles selbst.

## 4 Berechnungslogik

Verbräuche werden **nicht persistiert**, sondern bei Bedarf in `ConsumptionCalculator` berechnet. Vorteil: bei nachträglich eingefügten / korrigierten Ablesungen bleiben alle Werte automatisch konsistent.

### 4.1 Verbrauch zwischen zwei Ablesungen

```
delta = reading_b.value - reading_a.value     // muss ≥ 0 sein
days  = numberOfDays(reading_a.date, reading_b.date)
perDay = delta / Decimal(days)
```

Negative Differenz (z. B. Zählertausch) → eigene Markierung `MeterChange` (zukünftig), aktuell: ignoriert in Aggregaten, im Verlauf als Hinweis.

### 4.2 Periodenverbrauch (linear interpoliert)

Für eine Periode `[start, end)`:

1. Finde alle Reading-Paare, die ganz oder teilweise mit `[start, end)` überlappen.
2. Für jedes Paar: bestimme den überlappenden Tage-Anteil, multipliziere mit `perDay`.
3. Summe = Periodenverbrauch.

Wenn die Periode außerhalb jeder Reading-Spanne liegt → `nil` (kein Wert).
Wenn nur Teil-Abdeckung besteht (z. B. Periode endet in der Zukunft) → Wert wird als **partial** markiert und in Charts visuell gestrichelt.

### 4.3 Kosten

Pro Tag innerhalb einer Periode wird der gültige Tarif (`validFrom ≤ tag < validTo`) bestimmt. Tageskosten = `perDay * tarif.pricePerUnit`. Monatliche Grundgebühr wird tageweise verteilt: `tarif.baseFeePerMonth * Decimal(tageInMonat) / Decimal(tageImAktuellenMonat)` (vereinfacht: über alle Tage der Periode, jeden Tag der entsprechende Anteil).

Für Einspeise-Zähler werden `feedInPricePerUnit` verwendet — Wert ist eine Einnahme (positives Vorzeichen, aber als „Ertrag" gekennzeichnet).

### 4.4 Jahreshochrechnung

Bei aktueller Year-To-Date-Sicht: `prognose = ytdVerbrauch * (365 / vergangeneTageImJahr)`. Visualisierung als gestrichelte Fortsetzungslinie.

### 4.5 PV-Energiebilanz

Wenn ein Gebäude einen `electricity`- **und** einen `electricityFeedIn`-Zähler hat, und optional `electricitySelfConsumption`:

- **Netzbezug** = electricity-Verbrauch
- **Einspeisung** = electricityFeedIn-Verbrauch
- **Eigenverbrauch** = electricitySelfConsumption-Verbrauch (falls vorhanden)
- **Erzeugung** = Einspeisung + Eigenverbrauch
- **Autarkiegrad** = Eigenverbrauch / (Eigenverbrauch + Netzbezug)

## 5 Statistik & Charts

Verwendet `Swift Charts`. Im Statistik-Tab:

| Element | Beschreibung |
|---|---|
| Period Picker | Segmented: Tag · Woche · Monat · Quartal · Jahr |
| Range Picker | „Aktuell", „Vorperiode", „Vorjahr", oder Datumsbereich |
| Compare Toggle | Overlay einer zweiten Linie (Vorperiode oder Vorjahr) |
| Meter Filter | Multi-Select-Sheet, Default = aktuelles Gebäude alle Zähler |

**Chart-Typen:**

- **Liniendiagramm:** Zeitverlauf des Verbrauchs (interpoliert dargestellt), eine Linie pro Zähler. Interpolierte Endbereiche gestrichelt.
- **Balkendiagramm:** Periodenvergleich (z. B. Monate 2026 vs. 2025).
- **Stacked Area:** PV-Bilanz (Eigenverbrauch + Einspeisung).
- **Trend-Karte:** Großzahl + Pfeil + % vs. Vorperiode.

## 6 Erinnerungen

Pro Zähler optional aktivierbar mit Tag-im-Monat (1..28). Implementierung via `UNUserNotificationCenter`, Trigger `UNCalendarNotificationTrigger` (monatlich). Bei erster Aktivierung wird Permission angefragt. Notification öffnet App direkt im Zähler-Detail.

## 7 Export / Import

**Export:** Sheet im Einstellungs-Tab. Auswahl Format:

- **JSON** (vollständig, inkl. Fotos als Base64) — für Backup und Re-Import
- **CSV** (eine Datei pro Zähler im ZIP) — für Excel/Numbers-Auswertung

Verwendet `ShareLink` / `UIActivityViewController` → in Files-App, iCloud Drive, Mail etc. teilbar.

**Import:** Document-Picker für JSON-Datei. Konflikt-Strategie als Sheet:

- **Zusammenführen** (Default): vorhandene IDs werden aktualisiert, neue hinzugefügt
- **Überschreiben**: bestehende Daten löschen, dann importieren
- **Abbrechen**

## 8 Datensicherheit & Persistence

- SwiftData lokal, Default-Container, KEIN CloudKit-Sync (User-Wunsch: alles lokal).
- iOS-Backup (iCloud Backup oder lokal via Mac) sichert App-Container automatisch.
- Fotos werden im SwiftData-Store gespeichert (Base64/Binary). Bei sehr großen Mengen später ggf. ins File-System auslagern.
- Keine Analytics, keine Netzwerkverbindungen, keine Third-Party SDKs.

## 9 Modulstruktur

```
VerbrauchsHub/
  App/
    VerbrauchsHubApp.swift              // @main, ModelContainer
    AppState.swift                      // @Observable: aktives Gebäude
  Models/
    Building.swift
    Meter.swift
    Reading.swift
    Tariff.swift
    Enums.swift
    SeedData.swift                      // Demo-Daten bei leerem Store
  Calculation/
    ConsumptionCalculator.swift         // Periodenberechnung, Interpolation
    CostCalculator.swift                // Tarif-basierte Kosten
    Forecaster.swift                    // Jahreshochrechnung
    PeriodGranularity.swift             // enum + Helpers (start/end of period)
  Features/
    Dashboard/
      DashboardView.swift
      MeterSummaryCard.swift
    Meters/
      MeterListView.swift
      MeterDetailView.swift
      ReadingListView.swift
      AddReadingSheet.swift
      AddMeterSheet.swift
    Statistics/
      StatisticsView.swift
      ChartContainer.swift
      LineChartView.swift
      BarComparisonChartView.swift
      EnergyBalanceChartView.swift
    Settings/
      SettingsView.swift
      BuildingsListView.swift
      AddBuildingSheet.swift
      TariffListView.swift
      AddTariffSheet.swift
      ReminderSettingsView.swift
      ExportImportView.swift
  Services/
    NotificationService.swift
    ExportService.swift                 // JSON + CSV ZIP
    ImportService.swift
    PhotoPicker.swift
  Shared/
    BuildingSwitcher.swift              // Toolbar component
    Formatting.swift                    // Number-, Date-Formatter
    Theme.swift                         // Farben, Icons
  Resources/
    Assets.xcassets
    Localizable.strings (de, en)
```

## 10 Lokalisierung

- Hauptsprache: **Deutsch** (`de`)
- Sekundär: **Englisch** (`en`)
- Alle UI-Strings in `Localizable.strings`. Datum/Zahlen via `Locale.current`.

## 11 Tests

- Unit-Tests für `ConsumptionCalculator`, `CostCalculator`, `Forecaster`, `PeriodGranularity`.
- Tests für Export → Import Roundtrip.
- Swift Testing (`@Test`) im `VerbrauchsHubTests`-Target.

## 12 Out of Scope (bewusst nicht enthalten)

- CO₂-Bilanz
- Vergleichsdiagramm zwischen Gebäuden (Datenmodell unterstützt es; UI später)
- iCloud-Sync zwischen Geräten
- Mehrbenutzer / geteilte Haushalte
- Auto-Erkennung von Smart-Meter-Daten / API-Anbindungen
- Apple Watch Companion

## 13 Akzeptanzkriterien

- App startet, zeigt Onboarding falls keine Gebäude vorhanden, sonst Dashboard.
- Anlegen Gebäude → Anlegen Zähler → Eintragen mindestens zwei Ablesungen.
- Statistik-Tab zeigt mindestens Linienchart mit korrektem Verbrauch in gewählter Periode.
- Tarif anlegen → Kosten erscheinen auf Dashboard-Karte und in Statistik.
- Export erstellt Datei, Import liest sie verlustfrei wieder ein.
- Alle Tests grün.
