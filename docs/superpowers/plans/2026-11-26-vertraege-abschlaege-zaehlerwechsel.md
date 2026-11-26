# Verträge, Abschläge, Zählerwechsel – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Zählerwechsel an Ablesungen, Abschlagshistorie pro Zähler, eigene Verträge mit Kündigungs- und Preisgarantie-Erinnerung, Tarife bearbeiten.

**Architecture:** Drei neue SwiftData-Bausteine: das Feld `Reading.previousMeterFinalValue` und die Entitäten `AdvancePayment` und `Contract`. Alle sind leichtgewichtig migrierbar. Gültigkeitszeiträume von Tarifen und Abschlägen laufen über eine gemeinsame Verkettung. Die Rechnung bleibt in `Calculation/` als reine Funktionen und ist unit-getestet. Die Views rufen sie nur auf.

**Tech Stack:** Swift 5.10 (strict concurrency complete), SwiftUI, SwiftData, UserNotifications, XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-11-26-vertraege-abschlaege-zaehlerwechsel-design.md`

## Global Constraints

- iOS-Deployment-Target 18.0, keine neuen Abhängigkeiten.
- SwiftData ohne `VersionedSchema`: nur neue Entitäten, neue optionale Felder oder Felder mit Standardwert. Kein bestehendes Feld entfernen oder umbenennen (`Meter.advancePaymentPerMonth` bleibt).
- Export bleibt `schemaVersion = 1`. Jedes neue DTO-Feld und jede neue Liste ist optional (`var … : T?`).
- Texte deutsch, du-Form, direkt im Code.
- Monatslänge für anteilige Beträge: `86_400 * 30.4375` Sekunden (wie `CostCalculator`).
- Erinnerungen: Standard an, `reminderLeadDays = 30`, Uhrzeit 9:00. Kennungen `contract-cancel-<uuid>` und `contract-guarantee-<uuid>`.
- Neue Dateien: danach `xcodegen generate` ausführen, sonst fehlen sie im Projekt.
- Tests: `xcodebuild test -project VerbrauchsHub.xcodeproj -scheme VerbrauchsHub -destination 'id=D86B4B7C-0B7E-4032-B6A7-9140ABBB8222' -only-testing:VerbrauchsHubTests -test-timeouts-enabled YES -maximum-test-execution-time-allowance 60`. Ohne das Zeitlimit kann der Lauf hängen. `LicenseStoreTests.testRefundLocksAgain` scheitert schon vorher und ist nicht Teil dieser Arbeit.
- Tests rechnen mit dem UTC-Kalender aus `PlanningTests` (`calendar`, `date(y,m,d)`). Neue Logik nimmt `calendar: Calendar = .current` als Parameter.

## Review Focus

1. Zählerwechsel als allererste Ablesung (kein Vorgänger): Das Feld wird ignoriert, kein Absturz, Verbrauch 0. Test in Task 1.
2. Zeitraumgrenze genau am Wechseltag: Der Verbrauch bis zum Wechsel fällt vollständig in den Zeitraum davor, danach zählt nur der neue Zähler. Test in Task 1.
3. Migration läuft mehrfach (Start und Import): Es entsteht genau ein `AdvancePayment` pro Altabschlag. Test in Task 3.
4. Altes Backup ohne `contracts`, `advancePayments` und `contractID` lässt sich importieren. Der Altabschlag landet in der Historie. Test in Task 9.
5. Mindestlaufzeit endet am Monatsende, Kündigungsfrist in Monaten: 31.01.27 minus 1 Monat ergibt den 31.12.26, 31.03.27 minus 1 Monat den 28.02.27. Test in Task 6.

---

### Task 1: Zählerwechsel in Rechnung und Prüfung

**Files:**
- Modify: `VerbrauchsHub/Models/Reading.swift`
- Modify: `VerbrauchsHub/Calculation/ConsumptionCalculator.swift` (Paar-Schleife in `consumption(in:)`)
- Modify: `VerbrauchsHub/Calculation/ReadingCheck.swift`
- Test: `VerbrauchsHubTests/PlanningTests.swift`

**Interfaces:**
- Produces: `Reading.previousMeterFinalValue: Decimal?`, `Reading.isMeterChange: Bool`. `Reading.init` bekommt den Parameter `previousMeterFinalValue: Decimal? = nil` am Ende.
- Produces: `ReadingCheck.evaluate(value:date:readings:editing:previousMeterFinalValue: Decimal? = nil)`.

- [ ] **Step 1: Write the failing tests**

```swift
func testConsumptionContinuesAcrossMeterChange() {
    let meter = Meter(type: .electricity)
    meter.readings = [
        Reading(meter: meter, date: date(2025, 1, 1), value: 1000),
        Reading(meter: meter, date: date(2025, 1, 11), value: 0, previousMeterFinalValue: 1100), // 100 on old meter
        Reading(meter: meter, date: date(2025, 1, 21), value: 50),                               // 50 on new meter
    ]
    let calc = ConsumptionCalculator(meter: meter)
    XCTAssertEqual(calc.totalConsumption(from: date(2025, 1, 1), to: date(2025, 1, 21), calendar: calendar).amount.doubleValue, 150, accuracy: 0.01)
    // Boundary exactly on the change day.
    XCTAssertEqual(calc.totalConsumption(from: date(2025, 1, 1), to: date(2025, 1, 11), calendar: calendar).amount.doubleValue, 100, accuracy: 0.01)
    XCTAssertEqual(calc.totalConsumption(from: date(2025, 1, 11), to: date(2025, 1, 21), calendar: calendar).amount.doubleValue, 50, accuracy: 0.01)
}

func testMeterChangeAsFirstReadingIsIgnored() {
    let meter = Meter(type: .electricity)
    meter.readings = [
        Reading(meter: meter, date: date(2025, 1, 1), value: 0, previousMeterFinalValue: 500),
        Reading(meter: meter, date: date(2025, 1, 11), value: 10),
    ]
    XCTAssertEqual(ConsumptionCalculator(meter: meter).totalConsumption(from: date(2025, 1, 1), to: date(2025, 1, 11), calendar: calendar).amount.doubleValue, 10, accuracy: 0.01)
}

func testMeterChangeIsNotFlaggedButLowFinalValueIs() {
    let readings = [Reading(date: date(2025, 1, 1), value: 1000)]
    XCTAssertNil(ReadingCheck.evaluate(value: 0, date: date(2025, 1, 11), readings: readings, previousMeterFinalValue: 1100))
    XCTAssertEqual(ReadingCheck.evaluate(value: 0, date: date(2025, 1, 11), readings: readings, previousMeterFinalValue: 900), .lowerThanPrevious(previous: 1000))
}

func testUsualRateIgnoresMeterChangeInHistory() {
    // 10/day before and after a change. Raw value differences would make the history negative
    // and silently skip the check; 70/day must still be flagged.
    let readings = [
        Reading(date: date(2025, 1, 1), value: 1000),
        Reading(date: date(2025, 1, 31), value: 0, previousMeterFinalValue: 1300),
        Reading(date: date(2025, 3, 2), value: 300),
    ]
    XCTAssertNil(ReadingCheck.evaluate(value: 400, date: date(2025, 3, 12), readings: readings))
    XCTAssertEqual(ReadingCheck.evaluate(value: 1000, date: date(2025, 3, 12), readings: readings), .unusuallyHigh(factor: 7))
}
```

- [ ] **Step 2: Run tests, expect compile failure** (`previousMeterFinalValue` unbekannt).

- [ ] **Step 3: Implement**
  - Feld und Init-Parameter an `Reading`. Dazu `var isMeterChange: Bool { previousMeterFinalValue != nil }`.
  - `ConsumptionCalculator`: `let delta = (b.previousMeterFinalValue ?? b.value) - a.value`.
  - `ReadingCheck`: Ist `previousMeterFinalValue` gesetzt, wird es statt `value` gegen `previous.value` verglichen, und die Prüfung „ungewöhnlich hoch“ entfällt. Die Tagesrate der Historie kommt aus `ConsumptionCalculator(readings: history).totalConsumption(from: oldest.date, to: previous.date)`. Die neue Rate kommt aus `(previousMeterFinalValue ?? value) − previous.value` über die Tage, wenn kein Wechsel vorliegt.

- [ ] **Step 4: Run tests, expect PASS** (alle bisherigen Tests ebenfalls grün).

- [ ] **Step 5: Commit** `feat: Zählerwechsel in Verbrauchsrechnung und Plausibilitätsprüfung`

### Task 2: Zählerwechsel erfassen und anzeigen

**Files:**
- Modify: `VerbrauchsHub/Features/Meters/AddReadingSheet.swift`
- Modify: `VerbrauchsHub/Features/Meters/MeterDetailView.swift` (`ReadingRow`)

**Interfaces:**
- Consumes: Task 1 (`previousMeterFinalValue`, neuer `ReadingCheck`-Parameter).

- [ ] **Step 1: AddReadingSheet**
  - `@State isMeterChange` und `oldFinalText`. Im Abschnitt „Ablesung“: `Toggle("Zählerwechsel", isOn:)`. Eingeschaltet erscheint ein Feld „Endstand alter Zähler“ (Dezimaltastatur, Einheit). Das Feld „Zählerstand“ heißt dann „Startstand neuer Zähler“. Footer: „Endstand vom alten Zähler und Startstand vom neuen, beide vom Wechseltag.“
  - Beim Bearbeiten werden beide aus `reading.previousMeterFinalValue` geladen.
  - Speichern: Bei aktivem Wechsel muss das Endstand-Feld eine gültige Zahl enthalten (`validationError` „Bitte den Endstand des alten Zählers eintragen.“). Es wird an `ReadingCheck.evaluate` übergeben und gespeichert. Bei ausgeschaltetem Wechsel wird es auf `nil` gesetzt.
  - Hinweis bei `.lowerThanPrevious`: Wo der Hinweis heute erscheint, kommt der Knopf „Das war ein Zählerwechsel“ dazu. Er setzt `isMeterChange = true` und `oldFinalText` leer und setzt den Fokus auf das Endstand-Feld. Die Warnung verschwindet, bis neu gespeichert wird.

- [ ] **Step 2: ReadingRow** – Bei `reading.isMeterChange` erscheint unter Datum/Notiz eine Zeile in `.caption` und `.secondary`: „Zählerwechsel · alter Zähler: \(Formatting.counter(final, unit:))“, mit Symbol `arrow.triangle.2.circlepath`.

- [ ] **Step 3: Build und Sichtprüfung im Simulator:** Wechsel erfassen, bearbeiten, wieder ausschalten. Den Knopf aus dem Hinweis bei einem zu niedrigen Wert ausprobieren.

- [ ] **Step 4: Commit** `feat: Zählerwechsel beim Ablesen erfassen`

### Task 3: Gültigkeitskette, Abschlagshistorie, Migration

**Files:**
- Create: `VerbrauchsHub/Models/Validity.swift`
- Create: `VerbrauchsHub/Models/AdvancePayment.swift`
- Create: `VerbrauchsHub/Services/DataMigration.swift`
- Modify: `VerbrauchsHub/Models/Tariff.swift` (`status`, `relink` und `TariffStatus` ziehen nach `Validity.swift` um)
- Modify: `VerbrauchsHub/Models/Meter.swift`, `VerbrauchsHub/App/AppDataStore.swift`, `VerbrauchsHub/App/VerbrauchsHubApp.swift`
- Modify: `VerbrauchsHub/Features/Settings/TariffListView.swift` (Aufrufe umstellen)
- Test: `VerbrauchsHubTests/PlanningTests.swift`, Create: `VerbrauchsHubTests/DataTests.swift`

**Interfaces:**
- Produces:
  ```swift
  protocol ValidityPeriod: AnyObject { var validFrom: Date { get }; var validTo: Date? { get set } }
  enum ValidityStatus { case planned, current, ended }
  extension ValidityPeriod { func status(on: Date) -> ValidityStatus; func isActive(on: Date) -> Bool }
  enum ValidityChain { static func relink<T: ValidityPeriod>(_ items: [T]) }
  @Model final class AdvancePayment: ValidityPeriod { id, meter: Meter?, amountPerMonth: Decimal, validFrom: Date, validTo: Date?, createdAt: Date }
  // Meter: @Relationship(deleteRule: .cascade, inverse: \AdvancePayment.meter) var advancePayments: [AdvancePayment] = []
  enum DataMigration { @MainActor static func run(_ context: ModelContext) }
  ```
- `Tariff` erfüllt `ValidityPeriod`. `TariffStatus` heißt jetzt `ValidityStatus`, `Tariff.relink` heißt jetzt `ValidityChain.relink`. Bestehende Tests werden umbenannt, ihre Aussagen bleiben gleich.

- [ ] **Step 1: Failing tests**

```swift
// PlanningTests
func testAdvancePaymentsChain() {
    let a = AdvancePayment(amountPerMonth: 90, validFrom: date(2025, 1, 1))
    let b = AdvancePayment(amountPerMonth: 105, validFrom: date(2027, 1, 1))
    ValidityChain.relink([b, a])
    XCTAssertEqual(a.validTo, date(2027, 1, 1))
    XCTAssertEqual(b.status(on: date(2026, 11, 26)), .planned)
}

// DataTests (in-memory ModelContainer with all models)
@MainActor func testMigrationCopiesLegacyAdvanceOnce() throws {
    let context = try makeContext()
    let meter = Meter(type: .electricity)
    meter.advancePaymentPerMonth = 80
    meter.billingStartDate = date(2024, 3, 1)
    context.insert(meter)
    context.insert(Reading(meter: meter, date: date(2024, 1, 15), value: 0))
    DataMigration.run(context)
    DataMigration.run(context)
    XCTAssertEqual(meter.advancePayments.count, 1)
    XCTAssertEqual(meter.advancePayments.first?.amountPerMonth, 80)
    XCTAssertEqual(meter.advancePayments.first?.validFrom, date(2024, 1, 15)) // earliest of reading, billing start, createdAt
}
```

`makeContext()`: `ModelContainer(for: Schema([Building.self, Meter.self, Reading.self, Tariff.self, AdvancePayment.self]), configurations: ModelConfiguration(isStoredInMemoryOnly: true))` → `ModelContext(container)`. `Contract.self` kommt in Task 6 dazu. Für `createdAt` des Meters im Test `date(2025, 1, 1)` setzen, damit die Reihenfolge eindeutig ist.

- [ ] **Step 2: Run, expect compile failure.**
- [ ] **Step 3: Implement**
  - Protokoll, Kette und Modell wie oben. `AdvancePayment.self` kommt ins Schema in `AppDataStore`.
  - `DataMigration.run`: Zähler mit `advancePaymentPerMonth > 0` und leerer `advancePayments` bekommen einen Eintrag. `validFrom` ist das Minimum aus erster Ablesung, `billingStartDate` und `createdAt`. Danach `save`.
  - Aufruf in `VerbrauchsHubApp.init` nach `SeedData.seedIfRequested`.
- [ ] **Step 4: `xcodegen generate`, Tests, expect PASS.**
- [ ] **Step 5: Commit** `feat: Abschlagshistorie mit Übernahme des bisherigen Abschlags`

### Task 4: Prognose mit Abschlagshistorie

**Files:**
- Modify: `VerbrauchsHub/Calculation/Projection.swift`
- Modify: `VerbrauchsHub/Features/Meters/PlanningCards.swift`
- Test: `VerbrauchsHubTests/PlanningTests.swift`

**Interfaces:**
- Consumes: Task 3 (`meter.advancePayments`, `status(on:)`).
- Produces: `BillingForecaster.advanceTotal(for: Meter, from: Date, to: Date) -> Decimal` (internal static). `Meter.advance(on: Date) -> AdvancePayment?` und `Meter.nextPlannedAdvance(after: Date) -> AdvancePayment?` in einer Extension in `AdvancePayment.swift`.

- [ ] **Step 1: Failing tests.** Bestehende Billing-Tests auf `meter.advancePayments = [AdvancePayment(meter: meter, amountPerMonth: 50, validFrom: date(2024, 1, 1))]` umstellen, ihre Erwartungen bleiben. Neu:

```swift
func testAdvanceChangeMidYear() throws {
    let meter = linearMeter() // readings 2025-01-01: 0, 2025-07-01: 181 (helper extracted from existing test)
    meter.tariffs = [Tariff(meter: meter, pricePerUnit: Decimal(string: "0.30")!, baseFeePerMonth: 10, validFrom: date(2024, 1, 1))]
    meter.billingStartDate = date(2025, 1, 1)
    let a = AdvancePayment(meter: meter, amountPerMonth: 50, validFrom: date(2024, 1, 1))
    let b = AdvancePayment(meter: meter, amountPerMonth: 80, validFrom: date(2025, 10, 1))
    meter.advancePayments = [a, b]
    ValidityChain.relink(meter.advancePayments)
    let forecast = try XCTUnwrap(BillingForecaster.forecast(for: meter, asOf: date(2025, 7, 15), calendar: calendar))
    let month = 30.4375
    XCTAssertEqual(forecast.advancePayments.doubleValue, 273 / month * 50 + 92 / month * 80, accuracy: 0.5)
}

func testAdvanceStartingMidYearCountsOnlyFromStart() throws {
    // Single advance from 2025-07-01: only half a year of payments.
    ...
    XCTAssertEqual(forecast.advancePayments.doubleValue, 184 / 30.4375 * 50, accuracy: 0.5)
}

func testNoBillingWithoutAdvanceInPeriod() { /* advance list empty → forecast nil */ }
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement**
  - `forecast`: Die Bedingung ist jetzt `advanceTotal > 0` statt `meter.advancePaymentPerMonth`. `advancePayments` ist die Summe der Segmente über `[start, end)`, geschnitten mit den Gültigkeiten, × Monatsanteil.
  - `PlanningCards`: Die Bedingungen `meter.advancePaymentPerMonth != nil` werden zu `!meter.advancePayments.isEmpty`.
  - In der BillingCard heißt die Zeile „Abschläge (12 ×)“ jetzt „Abschläge“.
  - „Passender Abschlag“ vergleicht mit `meter.advance(on: .now)`. Bei `nextPlannedAdvance(after: .now)` folgt eine zusätzliche Zeile „Ab \(Datum): \(Betrag) pro Monat hinterlegt.“
- [ ] **Step 4: Tests PASS.**
- [ ] **Step 5: Commit** `feat: Prognose rechnet mit allen Abschlägen im Abrechnungsjahr`

### Task 5: Abschläge bearbeiten

**Files:**
- Modify: `VerbrauchsHub/Features/Meters/EditMeterSheet.swift`
- Create: `VerbrauchsHub/Features/Meters/AdvancePaymentSheet.swift`

**Interfaces:**
- Consumes: Task 3. Produces: `AdvancePaymentSheet(meter: Meter, payment: AdvancePayment?)`.

- [ ] **Step 1:** In `EditMeterSheet` fallen das Feld „Monatlicher Abschlag“, `advanceText` und die Speicherlogik dazu weg. An ihre Stelle kommt im selben Abschnitt die Liste der Abschläge, neueste zuerst: Betrag, „ab Datum“ und das Statuslabel wie bei Tarifen („geplant“ orange, „aktuell“ grün). Dazu ein Knopf „Abschlag hinzufügen“, Tippen öffnet das Bearbeiten, Wischen löscht. Nach jedem Ändern laufen `ValidityChain.relink(meter.advancePayments …)` und `save`. Wie bei den Tarifen werden gelöschte Einträge vorher herausgefiltert. „Abrechnungszeitraum ab“ und der Footer bleiben.
- [ ] **Step 2:** `AdvancePaymentSheet`: Betrag (€, Dezimal, > 0) und „Gültig ab“. Beim Bearbeiten zusätzlich „Abschlag löschen“. Titel „Neuer Abschlag“ bzw. „Abschlag bearbeiten“.
- [ ] **Step 3:** `xcodegen generate`, Build, Sichtprüfung: Abschlag hinzufügen, ändern, löschen. Danach muss die Planungskarte stimmen.
- [ ] **Step 4: Commit** `feat: Abschläge mit Gültigkeit pflegen`

### Task 6: Vertragsmodell und Kündigungsstichtag

**Files:**
- Create: `VerbrauchsHub/Models/Contract.swift`
- Modify: `VerbrauchsHub/Models/Tariff.swift`, `VerbrauchsHub/Models/Meter.swift`, `VerbrauchsHub/App/AppDataStore.swift`
- Test: Create `VerbrauchsHubTests/ContractTests.swift`. `Contract.self` kommt in `DataTests.makeContext` dazu.

**Interfaces:**
- Produces:
  ```swift
  enum NoticeUnit: String, CaseIterable { case weeks, months }
  @Model final class Contract { /* Felder exakt wie im Spec-Abschnitt „Contract“ */ }
  // Tariff: var contract: Contract?   Meter: @Relationship(deleteRule: .cascade, inverse: \Contract.meter) var contracts: [Contract] = []
  enum Cancellation: Equatable { case deadline(date: Date, termEnd: Date); case anytime(value: Int, unit: NoticeUnit) }
  extension Contract {
      var noticeUnit: NoticeUnit? { get set }
      func cancellation(asOf now: Date, calendar: Calendar = .current) -> Cancellation?
      func status(on date: Date) -> ValidityStatus?   // from its tariffs: any current → .current; else earliest validFrom > date → .planned; else .ended; no tariffs → nil
  }
  ```
- `Contract.init(provider:startDate:)` mit Standardwerten `reminderEnabled = true`, `reminderLeadDays = 30`, alles Optionale `nil`.

- [ ] **Step 1: Failing tests**

```swift
func testDeadlineBeforeMinimumTermEnd() {
    let c = contract(termEnd: date(2027, 1, 31), notice: (1, .months), renewal: nil)
    XCTAssertEqual(c.cancellation(asOf: date(2026, 11, 26), calendar: calendar), .deadline(date: date(2026, 12, 31), termEnd: date(2027, 1, 31)))
}
func testDeadlineAtEndOfFebruary() {
    let c = contract(termEnd: date(2027, 3, 31), notice: (1, .months), renewal: nil)
    XCTAssertEqual(c.cancellation(asOf: date(2026, 11, 26), calendar: calendar), .deadline(date: date(2027, 2, 28), termEnd: date(2027, 3, 31)))
}
func testRenewalRollsForward() {
    let c = contract(termEnd: date(2025, 12, 31), notice: (6, .weeks), renewal: 12)
    XCTAssertEqual(c.cancellation(asOf: date(2026, 11, 26), calendar: calendar), .deadline(date: date(2027, 11, 19), termEnd: date(2027, 12, 31)))
}
func testRunsOnIndefinitely() {
    let c = contract(termEnd: date(2025, 12, 31), notice: (1, .months), renewal: nil)
    XCTAssertEqual(c.cancellation(asOf: date(2026, 11, 26), calendar: calendar), .anytime(value: 1, unit: .months))
}
func testMissingDataGivesNoCancellation() {
    XCTAssertNil(contract(termEnd: nil, notice: (1, .months), renewal: nil).cancellation(asOf: date(2026, 11, 26), calendar: calendar))
    XCTAssertNil(contract(termEnd: date(2027, 1, 31), notice: nil, renewal: nil).cancellation(asOf: date(2026, 11, 26), calendar: calendar))
}
func testContractStatusFromTariffs() { /* planned contract (tariff from 2027-01-01) → .planned on 2026-11-26; none → nil */ }
```

Die Hilfsfunktion `contract(termEnd:notice:renewal:)` baut einen `Contract(provider: "Test", startDate: date(2024, 1, 1))`. Ein Deadline-Datum, das genau auf `now` fällt, gilt noch als `.deadline` (Bedingung: `deadline < now` rollt weiter).

- [ ] **Step 2: Run, expect compile failure.**
- [ ] **Step 3: Implement** den Algorithmus wie im Spec unter „Kündigungsstichtag“ beschrieben, mit `calendar.date(byAdding: .weekOfYear / .month, value: -n, to: termEnd)`. Die Schleife bricht spätestens nach 100 Durchläufen ab und gibt `nil` zurück. Schema erweitern.
- [ ] **Step 4: `xcodegen generate`, Tests PASS.**
- [ ] **Step 5: Commit** `feat: Vertragsmodell mit Kündigungsstichtag`

### Task 7: Vertragserinnerungen

**Files:**
- Modify: `VerbrauchsHub/Models/Contract.swift`, `VerbrauchsHub/Services/NotificationService.swift`, `VerbrauchsHub/App/VerbrauchsHubApp.swift`
- Test: `VerbrauchsHubTests/ContractTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct ContractReminder: Equatable { enum Kind { case cancellation, priceGuarantee }; let kind: Kind; let fireDate: Date; let eventDate: Date }
  extension Contract { func reminders(asOf now: Date, calendar: Calendar = .current) -> [ContractReminder] }
  extension NotificationService { func scheduleContractReminders(for: Contract); func cancelContractReminders(for: Contract); func rescheduleAllContractReminders(_ context: ModelContext) }
  ```

- [ ] **Step 1: Failing tests:** `reminders` liefert für die Deadline 31.12.26 und die Preisgarantie bis 31.03.27 bei 30 Tagen Vorlauf die Auslösetage 01.12.26 und 01.03.27, jeweils um 9:00 im übergebenen Kalender. Ein Auslösetag in der Vergangenheit wird weggelassen. Bei `reminderEnabled == false` kommt `[]`, ebenso bei `.anytime`.
- [ ] **Step 2: Run, FAIL.**
- [ ] **Step 3: Implement**
  - `reminders` wie getestet.
  - `scheduleContractReminders`: zuerst `cancel`, dann je Reminder eine `UNNotificationRequest` mit `UNCalendarNotificationTrigger(dateMatching: year…minute, repeats: false)` und den Kennungen aus den Global Constraints. Texte: „Kündigungsfrist endet bald“ / „\(provider): noch bis \(Datum) kündbar.“ und „Preisgarantie endet“ / „\(provider): Preisgarantie bis \(Datum).“
  - `rescheduleAllContractReminders` holt alle Verträge und plant sie neu. Aufruf in `RootView` bei `scenePhase == .active`.
- [ ] **Step 4: Tests PASS.**
- [ ] **Step 5: Commit** `feat: Erinnerung an Kündigungsfrist und Preisgarantie`

### Task 8: Verträge-Oberfläche und Tarif bearbeiten

**Files:**
- Modify: `VerbrauchsHub/Features/Settings/TariffListView.swift` → umbenennen in `ContractListView.swift` (enthält `ContractOverviewView`, `ContractListView`)
- Create: `VerbrauchsHub/Features/Settings/ContractFormSheet.swift`, `VerbrauchsHub/Features/Settings/TariffFormSheet.swift`
- Modify: `VerbrauchsHub/Features/Settings/SettingsView.swift`, `VerbrauchsHub/Features/Meters/PlanningCards.swift`

**Interfaces:**
- Consumes: Tasks 3, 6, 7. Produces: `TariffFormSheet(meter: Meter, contract: Contract?, tariff: Tariff?)`, `ContractFormSheet(meter: Meter, contract: Contract?)`.

- [ ] **Step 1: TariffFormSheet** ersetzt `AddTariffSheet`, mit denselben Feldern und demselben Footer. Beim Bearbeiten sind die Felder vorbelegt, dazu kommt „Preis löschen“. Bei neuem Preis mit `contract` wird `tariff.contract = contract` gesetzt, das Datum ist mit heute vorbelegt. Nach jedem Ändern laufen `ValidityChain.relink` über alle verbleibenden Tarife des Zählers und `save`.
- [ ] **Step 2: ContractFormSheet:**
  - Abschnitte wie im Spec unter „Vertragsformular“. Pflichtfeld ist nur der Anbieter.
  - Verlängerung als Picker: „Unbefristet, kündbar mit Frist“ / „Verlängert sich automatisch“ (dann Stepper Monate, Standard 12).
  - Beim Anlegen zusätzlich der erste Preis (Pflicht: Arbeitspreis; gültig ab = Vertragsbeginn) und optional der Abschlag. Der Abschlag wird als `AdvancePayment(validFrom: startDate)` mit Relink angelegt.
  - Beim Bearbeiten die Preisliste des Vertrags mit „Preis hinzufügen“ (öffnet `TariffFormSheet`) und „Vertrag löschen“ mit Bestätigungsdialog: „Der Vertrag und seine \(n) Preise werden gelöscht.“
  - Speichern und Löschen: Relink der Tarife, `save`. Nach dem Speichern `scheduleContractReminders`, nach dem Löschen `cancelContractReminders`. Beim Einschalten der Erinnerung `requestPermissionIfNeeded`.
- [ ] **Step 3: ContractListView:**
  - Je Vertrag eine Section. Kopf: Anbieter und Statuslabel aus `contract.status(on: .now)`. Darunter eine Zeile aus `cancellation`: „Kündbar bis \(Datum)“ / „Kündbar mit \(n) \(Wochen|Monate) Frist“ / „Kündigungsfrist nicht hinterlegt“. Dazu „Preisgarantie bis \(Datum)“ und die Preiszeilen im heutigen Stil.
  - Section „Preise ohne Vertrag“ nur, wenn es solche Tarife gibt.
  - „+“ öffnet ein `Menu` mit „Neuer Vertrag“ und „Neuer Preis ohne Vertrag“.
  - Sortierung: Verträge nach dem frühesten Preis, neueste zuerst.
- [ ] **Step 4: SettingsView:** Die Section heißt „Verträge“, das Label „Verträge & Preise“. Die Übersicht zeigt rechts `meter.contracts.count + Tarife ohne Vertrag`.
- [ ] **Step 5: PlanningCards:** Über den Karten steht eine kleine Zeile mit `doc.text` für den Vertrag, der heute gilt: „Vertrag: \(Anbieter) · kündbar bis \(Datum)“. Gibt es einen geplanten Vertrag, folgt „Neuer Vertrag ab \(Datum)“. Ohne Verträge erscheint nichts.
- [ ] **Step 6:** `xcodegen generate`, Build, Sichtprüfung des ganzen Ablaufs:
  - Vertrag mit Preis und Abschlag anlegen, Preisanpassung hinzufügen, Preis bearbeiten.
  - Geplanten Vertrag ab 01.01.27 anlegen, Vertrag löschen.
  - Die Bestandstarife müssen sichtbar bleiben.
- [ ] **Step 7: Commit** `feat: Verträge mit Preisen verwalten, Preise bearbeiten`

### Task 9: Export, Import, CSV

**Files:**
- Modify: `VerbrauchsHub/Services/ExportService.swift`, `VerbrauchsHub/Services/ImportService.swift`, `VerbrauchsHub/Features/Settings/ExportImportView.swift`
- Test: `VerbrauchsHubTests/DataTests.swift`

**Interfaces:**
- Produces: `ContractDTO` (alle Contract-Felder + `meterID`) und `AdvancePaymentDTO` (alle Felder + `meterID`). Neue Felder: `ExportSnapshot.contracts: [ContractDTO]?`, `ExportSnapshot.advancePayments: [AdvancePaymentDTO]?`, `TariffDTO.contractID: UUID?`, `ReadingDTO.previousMeterFinalValue: Decimal?`. Neue Signatur `makeSnapshot(buildings:meters:readings:tariffs:contracts:advancePayments:)`.

- [ ] **Step 1: Failing tests**
  - `testRoundtripKeepsContractsAdvancesAndMeterChange`: Zähler mit Vertrag, zwei Preisen (einer im Vertrag), zwei Abschlägen und einer Wechsel-Ablesung anlegen. Exportieren, mit `.replace` in einen frischen Context importieren. Danach müssen Anzahlen, `tariff.contract?.provider`, `previousMeterFinalValue` und `validTo` stimmen.
  - `testImportsLegacyBackup`: ein JSON-String im 1.1-Format ohne die neuen Schlüssel, mit `advancePaymentPerMonth: 70`. Erwartet: Import gelingt, und `meter.advancePayments.first?.amountPerMonth == 70` (über `DataMigration.run`).
- [ ] **Step 2: Run, FAIL.**
- [ ] **Step 3: Implement**
  - Export: `MeterDTO.advancePaymentPerMonth` = `meter.advance(on: .now)?.amountPerMonth`.
  - Import: Reihenfolge Gebäude → Zähler → Verträge → Ablesungen → Tarife → Abschläge, danach `DataMigration.run`. Relink pro Zähler für Tarife und Abschläge, `save`, `NotificationService.shared.rescheduleAllContractReminders`. Die Ergebnismeldung zählt Verträge und Abschläge mit.
  - `deleteAll` löscht zusätzlich `AdvancePayment` und `Contract` (vor `Meter`).
  - CSV-Kopfzeile `Datum;Zaehlerstand;Endstand_alter_Zaehler;Notiz`.
  - `ExportImportView` liefert die neuen Queries mit.
- [ ] **Step 4: Tests PASS.**
- [ ] **Step 5: Commit** `feat: Verträge, Abschläge und Zählerwechsel im Backup`

### Task 10: Beispieldaten und Abschluss

**Files:**
- Modify: `VerbrauchsHub/Models/SeedData.swift`

- [ ] **Step 1:** Strom bekommt einen Vertrag „Stadtwerke“. Er beginnt am bisherigen `tariffStart`, die Mindestlaufzeit ist abgelaufen, er ist unbefristet mit 1 Monat Frist und enthält den bestehenden Preis. Dazu ein geplanter Vertrag „Ökostrom Nord“ ab dem nächsten 1. Januar: 0,32 €/kWh, 13,90 € Grundgebühr, 12 Monate Mindestlaufzeit, 12 Monate Verlängerung, 4 Wochen Frist, Preisgarantie 12 Monate. Abschläge Strom: 105 € ab `tariffStart`, 110 € ab dem nächsten 1. Januar. Der Altwert `strom.advancePaymentPerMonth` entfällt, ebenso bei Gas (dort 30 € als `AdvancePayment`). Wasser bekommt einen Zählerwechsel bei der Ablesung, die etwa 12 Monate zurückliegt (neuer Startstand 0). Danach Relink.
- [ ] **Step 2:** Alle Unit-Tests ausführen, erwartet: alles grün außer `testRefundLocksAgain`. Danach `xcodebuild test … -only-testing:VerbrauchsHubUITests/FeatureTour` ausführen, erwartet: PASS.
- [ ] **Step 3:** Mit Beispieldaten in der App prüfen: Dashboard, Zählerdetail Strom (Vertragszeile, Prognose mit Abschlagsänderung), Verträge-Screen, Wasser-Statistik ohne Einbruch am Wechsel.
- [ ] **Step 4: Commit** `chore: Beispieldaten mit Verträgen, Abschlägen und Zählerwechsel`
