# Verträge, Abschläge, Zählerwechsel, Tarif bearbeiten – Design

Stand: 26.11.2026 · Branch `feature/testphase`

## Warum

Ein Nutzer kennt seinen Stromvertrag ab 01.01.27 schon heute und will ihn eintragen. Seit `733c4fe` zeigt die App ihn als „geplant“ an und berücksichtigt ihn in der Prognose. Drei Dinge rechnen trotzdem noch falsch oder fehlen:

- **Zählerwechsel:** Der Netzbetreiber tauscht den Zähler, der neue beginnt bei 0. `ConsumptionCalculator` überspringt fallende Stände (`delta <= 0`). Damit fehlt der Verbrauch zwischen der letzten Ablesung am alten und der ersten am neuen Zähler. Die Plausibilitätsprüfung meldet einen Tippfehler.
- **Abschlag:** Der Abschlag ist ein einzelner Wert am Zähler (`Meter.advancePaymentPerMonth`). Der Versorger ändert ihn nach jeder Jahresabrechnung und bei einem neuen Vertrag. Die Prognose vergleicht künftige Kosten deshalb mit dem heutigen Abschlag × 12.
- **Vertragsdaten:** Anbieter, Laufzeit, Kündigungsfrist und Preisgarantie fehlen. Der Nutzer verpasst Kündigungsfristen.
- **Tarif bearbeiten:** Ein Tippfehler im Preis heißt löschen und neu anlegen.

Erfolg: Die Abschlagsprognose stimmt auch über Zählerwechsel, Abschlagsänderungen und Vertragswechsel hinweg. Der Nutzer wird vor dem Ende der Kündigungsfrist und der Preisgarantie erinnert.

## Ziele

1. Eine Ablesung kann als Zählerwechsel markiert werden. Der Verbrauch läuft dann über den Wechsel hinweg richtig weiter.
2. Abschläge haben eine Historie mit „gültig ab“. Die Prognose summiert die Abschläge, die im Abrechnungsjahr tatsächlich fällig sind.
3. Es gibt eigene Verträge pro Zähler mit Anbieter, Nummern, Laufzeit, Kündigungsfrist und Preisgarantie. Ein Vertrag enthält einen oder mehrere Preise (Tarife).
4. Erinnerungen vor dem Kündigungsstichtag und vor dem Ende der Preisgarantie.
5. Tarife (Preise) lassen sich bearbeiten.

## Nicht-Ziele

- Datensatz pro physischem Zähler (Zählernummer, Ein- und Ausbau-Historie).
- Angebotsvergleich, Jahresabrechnung erfassen (Ideen 5 und 6, später).
- Zählerwechsel per Siri oder Kurzbefehl erfassen. Der Intent legt weiter nur normale Ablesungen an.
- Kündigung aus der App heraus, Anbieterdatenbank, Online-Abfragen.

## Anti-Ziele (wäre ein Fehlschlag, auch wenn es technisch läuft)

- Bestehende Daten (Ablesungen, Tarife, Abschlag) gehen beim Update verloren oder rechnen anders als vorher.
- Alte JSON-Backups (1.0, 1.1) lassen sich nicht mehr importieren.
- Tarife ohne Vertrag (alle Bestandsdaten) werden zu Nutzern zweiter Klasse oder verschwinden aus der Oberfläche.
- Daten verlassen das Gerät. Die Erinnerungen sind lokale Benachrichtigungen.

## Rahmenbedingungen

- SwiftData ohne `VersionedSchema`. Erlaubt sind nur leichtgewichtige Änderungen: neue Entitäten, neue optionale Felder und neue Beziehungen mit Standardwert. Bestehende Felder werden nicht entfernt oder umbenannt.
- Export-Format bleibt `schemaVersion = 1`. Alle neuen Felder und Listen sind optional, damit alte Backups weiter importiert werden.
- Die App ist nur auf Deutsch. Texte stehen direkt im Code wie bisher.
- Swift/SwiftUI, iOS-Ziel wie im Projekt. Keine neuen Abhängigkeiten.

## Ansätze (besprochen)

**Vertragsmodell**
- *Eigene Entität `Contract` mit Preisen darin (gewählt).* Eine Preisanpassung ist ein neuer Preis im selben Vertrag. Kündigungsfrist und Erinnerung hängen an genau einer Stelle. Mehr Aufwand: neuer Screen „Verträge“.
- *Vertragsfelder direkt am Tarif.* Weniger Aufwand, aber die Vertragsdaten stehen mehrfach in der Datenbank, und die Erinnerung muss raten, welcher Eintrag gilt. Später nur mühsam umbaubar. Verworfen.

**Abschlag**
- *Eigene Historie pro Zähler (gewählt).* Der Abschlag ändert sich unabhängig vom Preis, meist nach der Jahresabrechnung.
- *Abschlag am Tarif oder am Vertrag.* Verworfen. Eine Abschlagsänderung ohne Preisänderung müsste sonst als neuer Tarif angelegt werden.

**Zählerwechsel**
- *Optionales Feld „Endstand alter Zähler“ an der Ablesung (gewählt).* Kleinste Modelländerung, Rechnung bleibt eine Liste von Ablesungen.
- *Eigene Entität pro physischem Zähler.* Bringt für die Rechnung nichts. Verworfen.

## Datenmodell

### Reading (neues Feld)

```swift
/// Set on a meter exchange: final value of the old meter on `date`.
/// `value` is then the start value of the new meter.
var previousMeterFinalValue: Decimal?
var isMeterChange: Bool { previousMeterFinalValue != nil }
```

### AdvancePayment (neu)

```swift
@Model final class AdvancePayment {
    @Attribute(.unique) var id: UUID
    var meter: Meter?
    var amountPerMonth: Decimal
    var validFrom: Date
    var validTo: Date?      // per relink: start of the next entry, the latest stays open
    var createdAt: Date
}
```

`Meter.advancePayments` mit `.cascade`. `Meter.advancePaymentPerMonth` bleibt im Modell als Altfeld. Es wird nur noch beim Migrieren und beim Export gelesen, damit ältere App-Versionen ein neues Backup sinnvoll lesen.

### Contract (neu)

```swift
@Model final class Contract {
    @Attribute(.unique) var id: UUID
    var meter: Meter?
    var provider: String
    var customerNumber: String?
    var contractNumber: String?
    var startDate: Date
    /// End of the minimum term (Erstlaufzeit). nil = unknown or no minimum term.
    var minimumTermEnd: Date?
    /// Automatic renewal after the term in months (old contracts often 12). nil = runs on
    /// indefinitely and can be cancelled with the notice period at any time (common since 2022).
    var renewalMonths: Int?
    var noticePeriodValue: Int?
    var noticePeriodUnitRaw: String?   // "weeks" | "months"
    var priceGuaranteeUntil: Date?
    var notes: String?
    var reminderEnabled: Bool          // Standard true
    var reminderLeadDays: Int          // Standard 30
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Tariff.contract) var tariffs: [Tariff] = []
}
```

`Tariff` bekommt `var contract: Contract?`. Tarife ohne Vertrag bleiben gültig. `Meter.contracts` mit `.cascade`.

### Kündigungsstichtag

`Contract.cancellation(asOf now:) -> Cancellation?`:

- Ohne `minimumTermEnd` oder ohne Kündigungsfrist: kein Stichtag. Anzeige „Kündigungsfrist nicht hinterlegt“.
- `termEnd = minimumTermEnd`. Solange `termEnd − Frist < now`:
  - mit `renewalMonths`: `termEnd += renewalMonths`,
  - ohne `renewalMonths`: Ergebnis `.anytime(notice)`, also „monatlich kündbar mit Frist X“, ohne Erinnerung.
- Ergebnis `.deadline(date: termEnd − Frist, termEnd: termEnd)`.

Wochen und Monate werden mit `Calendar.date(byAdding:)` abgezogen.

## Berechnung

**Verbrauch:** Für das Paar `a → b` gilt `delta = (b.previousMeterFinalValue ?? b.value) − a.value`. Ab `b` rechnet die App mit `b.value` weiter. Alle Aufrufer (`CostCalculator`, `Projection`, Statistik, Dashboard) gehen schon über `ConsumptionCalculator` und profitieren automatisch.

**Plausibilität (`ReadingCheck`):**
- Normale Ablesung: Vergleich mit `previous.value` wie bisher. Nach einem Wechsel ist das der Startstand des neuen Zählers, also richtig.
- Zählerwechsel: Geprüft wird `previousMeterFinalValue ≥ previous.value`. Der Startstand des neuen Zählers wird nicht gegen den alten geprüft.
- Die übliche Tagesrate wird über `ConsumptionCalculator` statt über die Differenz der Rohwerte berechnet, damit ein Wechsel in der Historie sie nicht verfälscht.

**Abschlag in der Prognose:** `advancePayments = Σ amountPerMonth × Monatsanteil` über die Segmente im Abrechnungsjahr. Das ist dieselbe Monatslänge (30,4375 Tage) wie bei der Grundgebühr. Ohne Abschlagseintrag im Abrechnungsjahr gibt es keine Prognose, wie heute ohne Abschlag. Segmente vor dem ersten Eintrag zählen 0 €. `suggestedAdvance` bleibt `projectedCost / 12`. Die Karte vergleicht ihn mit dem Abschlag, der heute gilt. Gibt es schon einen geplanten, wird dieser genannt: „ab 01.01.27: 95 €“.

**Verkettung:** `Tariff.relink` wird zu einer generischen Verkettung für Tarife und Abschläge, z. B. ein Protokoll mit `validFrom` und `validTo`. Sie läuft nach jedem Anlegen, Bearbeiten und Löschen. Tarife werden pro Zähler verkettet, über alle Verträge hinweg.

## Migration beim Start

`DataMigration.run(context)` läuft beim App-Start und nach jedem Import. Sie muss beliebig oft laufen können, ohne etwas doppelt anzulegen:

- Zähler mit `advancePaymentPerMonth > 0` und ohne `advancePayments` bekommen einen Eintrag. `validFrom` ist der früheste Wert aus erster Ablesung, `billingStartDate` und `createdAt`. Ab dann rechnet die Prognose genau wie bisher.
- Bestehende Tarife bekommen keinen Vertrag.

## Oberfläche

**Einstellungen › Verträge** (bisher „Tarife“): Zählerliste wie bisher, Zahl rechts = Anzahl Verträge plus Preise ohne Vertrag.

**Verträge eines Zählers** (`ContractListView`):
- Je Vertrag eine Section. Kopf: Anbieter und Status („aktuell“, „geplant ab …“, „beendet“; abgeleitet aus seinen Preisen). Zeile: „Kündbar bis 30.11.26“ / „monatlich kündbar, 1 Monat Frist“ / „Preisgarantie bis …“. Darunter die Preise im Stil der heutigen Tarifliste.
- Section „Preise ohne Vertrag“ für Bestandstarife. Nur sichtbar, wenn welche da sind.
- „+“ öffnet ein Menü: „Neuer Vertrag“ / „Neuer Preis ohne Vertrag“.
- Tippen auf den Vertragskopf öffnet das Vertragsformular, Tippen auf einen Preis das Preisformular.
- Wischen zum Löschen: Ein Vertrag wird nach Rückfrage mit allen Preisen gelöscht, danach werden die Tarife neu verkettet.

**Vertragsformular** (Anlegen und Bearbeiten):
- Abschnitte: Anbieter und Nummern; Laufzeit (Beginn, Mindestlaufzeit bis, Verlängerung: „unbefristet, kündbar mit Frist“ oder „um 12 Monate“ mit Stepper); Kündigungsfrist (Zahl + Wochen/Monate); Preisgarantie bis (optional, Schalter); Erinnerung (Schalter + „Tage vorher“); Notiz.
- Nur beim Anlegen: erster Preis (Arbeitspreis, Grundgebühr, ggf. Einspeisevergütung, gültig ab = Vertragsbeginn) und optional „Abschlag ab Vertragsbeginn“. Daraus entsteht ein `AdvancePayment`.
- Beim Bearbeiten: Liste der Preise mit „Preis hinzufügen“ (Preisanpassung, Datum vorbelegt mit heute).

**Preisformular:** `AddTariffSheet` wird zu `TariffFormSheet(meter:, contract:, tariff:)` für Anlegen und Bearbeiten, mit „Preis löschen“ beim Bearbeiten.

**Abschläge:** In „Zähler bearbeiten“ ersetzt eine Liste das Feld „Monatlicher Abschlag“. Sie zeigt Betrag, „ab Datum“ und den Status (aktuell, geplant, beendet). Dazu „Abschlag hinzufügen“, Tippen zum Bearbeiten, Wischen zum Löschen. „Abrechnungszeitraum ab“ bleibt im selben Abschnitt.

**Zählerwechsel in der Ablesung:**
- Schalter „Zählerwechsel“ im Abschnitt „Ablesung“. Eingeschaltet erscheint das Feld „Endstand alter Zähler“, und „Zählerstand“ heißt „Startstand neuer Zähler“.
- Meldet die Prüfung `lowerThanPrevious`, bietet der Hinweis den Knopf „Das war ein Zählerwechsel“. Er schaltet den Schalter ein und füllt das Feld mit dem eingegebenen Wert als neuem Startstand.
- In der Ablesungsliste steht unter der Zeile „Zählerwechsel · alter Zähler: 12.345 kWh“.

**Zählerdetail:** Bei einem aktiven oder geplanten Vertrag steht eine kleine Zeile in den Planungskarten: „Vertrag: Anbieter · kündbar bis 30.11.26“. Bei einem geplanten Vertrag: „Neuer Vertrag ab 01.01.27“.

## Erinnerungen

- Neu in `NotificationService`: `scheduleContractReminders(for: Contract)` und `cancelContractReminders(for:)`. Zwei einmalige Benachrichtigungen um 9:00 Uhr:
  - `Stichtag − reminderLeadDays`: „Kündigungsfrist endet bald“ / „{Anbieter}: noch bis {Datum} kündbar.“
  - `priceGuaranteeUntil − reminderLeadDays`: „Preisgarantie endet“ / „{Anbieter}: Preisgarantie bis {Datum}.“
  - Termine in der Vergangenheit werden ausgelassen.
- Neu geplant wird beim Speichern und Löschen eines Vertrags, beim App-Start (wegen automatischer Verlängerungen) und nach einem Import.
- Beim ersten Einschalten wird um Erlaubnis gefragt, wie bei der Ablese-Erinnerung.
- Kennungen: `contract-cancel-<id>`, `contract-guarantee-<id>`.

## Export und Import

- `ReadingDTO.previousMeterFinalValue: Decimal?`, `TariffDTO.contractID: UUID?`.
- `ExportSnapshot.contracts: [ContractDTO]?`, `ExportSnapshot.advancePayments: [AdvancePaymentDTO]?`.
- `MeterDTO.advancePaymentPerMonth` wird weiter geschrieben: der heute gültige Abschlag, für ältere App-Versionen.
- Import: Verträge vor den Tarifen anlegen, damit `contractID` sich auflösen lässt. Danach `DataMigration.run`, Tarife und Abschläge neu verketten und Erinnerungen neu planen. `deleteAll` löscht die neuen Entitäten mit.
- CSV: neue Spalte `previous_meter_final_value` in der Ablesungsdatei.

## Beispieldaten

Strom bekommt einen laufenden Vertrag (Mindestlaufzeit abgelaufen, monatlich kündbar) und einen geplanten ab dem nächsten 1. Januar mit höherem Preis. Dazu einen Abschlag mit Erhöhung zum Vertragswechsel. Wasser bekommt einen Zählerwechsel vor etwa einem Jahr. Die Screenshot-Tests prüfen danach, dass die Bilder weiter stimmen.

## Tests

Unit-Tests (`PlanningTests` oder neue `ContractTests`):
- Verbrauch über einen Zählerwechsel hinweg, auch wenn ein Zeitraum mitten im Wechselintervall liegt.
- `ReadingCheck`: Ein Wechsel wird nicht als Fehler gemeldet. Ein Endstand unter dem vorherigen Wert wird gemeldet.
- Prognose mit Abschlagsänderung mitten im Abrechnungsjahr, mit geplantem Abschlag und ohne Abschlag.
- Kündigungsstichtag: Mindestlaufzeit in der Zukunft, abgelaufen mit Verlängerung um 12 Monate, abgelaufen unbefristet, fehlende Angaben.
- Migration: Ein Altabschlag wird genau einmal übernommen. Die Prognose ist vorher und nachher gleich.
- Export und Import Roundtrip mit Vertrag, Abschlag und Zählerwechsel. Import eines alten Backups ohne die neuen Felder.

## Dem Umsetzer überlassen

- Aufteilung in Dateien und Views; die Benennung der Views im Text ist nur ein Vorschlag.
- Ob die generische Verkettung über ein Protokoll oder zwei kleine Funktionen läuft.
- Genaue Formulierungen der Texte im Rahmen des Tons der App (du-Form, kurz).
- Layoutdetails der Vertrags-Section.

## Eigene Entscheidungen von Claude (bitte prüfen)

- Ein gelöschter Vertrag löscht seine Preise mit (nach Rückfrage), statt sie zu „Preise ohne Vertrag“ zu machen.
- Erinnerung standardmäßig an, 30 Tage vorher, um 9:00 Uhr.
- Kein Zwang, dass die Preise eines Vertrags innerhalb von Beginn und Laufzeit liegen. Verkettet wird über alle Preise eines Zählers.
- `Meter.advancePaymentPerMonth` bleibt als Altfeld im Modell und im Export.
- Zählerwechsel nicht per Siri.
