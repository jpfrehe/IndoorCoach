# Paket „Sekundendaten-Auswertung“: Zonen je Fahrt, Soll/Ist je Intervall, Einheit anpassen (ECC, 3 parallele Pakete)

Stand 18.11.2026 · Größe: **mittel–groß** · Gate 1: vom Nutzer freigegeben („Was sind noch weitere Features oder Todos, die nicht verpflichtend sind, aber Mehrwert bringen? Gehe sinnvolle Themen an, bis ich die konkreten Tests mit iPhone und Mac durchführen kann“).

## Auswahl aus dem Backlog

| Kandidat | Mehrwert | Ohne Gerät machbar? | Entscheidung |
|---|---|---|---|
| Sekundendaten nutzen (B16 ohne Strava): Zeit in Zonen, genauerer Relative Effort, echte Trainingsverteilung | hoch: Die Brücke liefert jetzt Sekundendaten, ausgewertet wird davon bisher nur die Kurve | ja | **Z** |
| Soll/Ist je Intervall (B16, Idee „Plan gegen Ist“) | hoch: beantwortet „Habe ich die Einheit getroffen?“ und motiviert konkret | ja | **S** |
| „Einheit anpassen“ (kürzer/leichter, Ideen für später) | hoch für die Konstanz: lieber 40 min statt gar nicht | ja | **A** |
| Gerätetest-Protokoll + Brückenstatus im Diagnose-Export | unterstützt die anstehenden Tests auf iPhone und Mac | ja | Hauptsession |
| Widget „Heute“ (B19) | mittel | braucht App Group und Signierung | nach den Gerätetests |
| iCloud-Transport, Verteilung der Mac-App (B24) | mittel | braucht das Apple-Konto | nach den Gerätetests |
| Apple Health (B17) | gering, seit die Brücke Sekundendaten liefert | ja | zurückgestellt |

## S0 · Grundbaustein (Hauptsession, vorab)

- `RideSeconds` (Domain): 1-Hz-Leistung (UInt16) und Puls (UInt8) im kompakten Binärformat, 1 h ≈ 11 KB.
- `FITParser.Summary.seconds` liefert die Daten beim Import mit.
- `StoredRide.secondsData` (`@Attribute(.externalStorage)`, optional, leichte Migration).
- `mergeImportedRides(_:seconds:)` speichert die Daten beim Einfügen, beim Ergänzen und bei schon vollständigen Fahrten, denen sie noch fehlen. Das gilt für den FIT-Import und für die Brücke.
- `AppModel.rideSeconds(id:)` liest sie.
- Demo-Fahrten (Indoor, aktuelles Fenster) haben strukturierte synthetische Sekundendaten (`DemoData.syntheticSeconds`). „Sweet Spot 2×20“ und „VO2max 5×3“ enthalten echte Intervalle.

## Pakete (Ownership exklusiv)

### Z · Zeit in Zonen je Fahrt

- **Domain** (`Domain/ZoneTime.swift`):
  - Zeit je Leistungszone aus `RideSeconds` und FTP, mit den Zonen der App (`PowerZone`).
  - Zeit je Pulszone aus HF-Profil oder Schwellenpuls.
  - Pausen (0 W) zählen nicht.
- **Relative Effort**: Fahrten mit Pulssekunden bekommen einen zonenbasierten TRIMP (Summe über die Sekunden statt Ø-Puls). Neue Quelle „Puls (Sekunden)“.
- **Trainingsverteilung**: Fahrten mit Sekundendaten tragen ihre echte Zeit je Band bei statt der ganzen Fahrt im Band ihres IF.
- **UI**:
  - In `RideDetailView` eine Karte „Zeit in Zonen“: Balken je Zone mit Minuten, Leistung und Puls umschaltbar.
  - In der Trainingsverteilung ein Hinweis, wie viele Fahrten gemessen und wie viele geschätzt sind.
- **Performance**: Zonenzeiten je Fahrt werden gecacht, Schlüssel aus Fahrt-ID, FTP und HF-Profil. Die Trainingsverteilung über 12 Wochen darf nicht spürbar langsamer werden (Messung im Test).
- **Tests**: Unit-Tests für Zonengrenzen, Pausen, TRIMP gegen den Ø-Puls-Wert und die Verteilung; UI-Test test36 in einer eigenen Datei.

### S · Soll/Ist je Intervall

- **Domain** (`Domain/IntervalCompliance.swift`):
  - Die Segmente einer geplanten Einheit (Ziel in % FTP, Dauer, Wiederholungen) werden auf die Sekundendaten der verknüpften Fahrt gelegt.
  - Der Versatz ergibt sich aus der besten Ausrichtung in den ersten 10 min (Kreuzkorrelation über das Soll-Profil).
  - Ergebnis je Arbeitsintervall: Soll-Watt, Ist-Ø, Abweichung, Status (getroffen ±5 %, zu leicht, zu hart).
  - Dazu eine Gesamtquote („7 von 8 Intervallen getroffen“).
- **UI**: `IntervalComplianceCard(workout:)` (eigene Datei). Wird nur gezeigt, wenn die Einheit erledigt ist und die verknüpfte Fahrt Sekundendaten hat. Darin Soll/Ist-Diagramm (Soll als Stufen, Ist geglättet) und Liste der Intervalle. Die Hauptsession bindet die Karte in `WorkoutDetailView` ein.
- **Debug-Seed** `-uiComplianceSeed YES`: eine erledigte Einheit „Sweet Spot 2×20“, verknüpft mit einer Demo-Fahrt mit passenden Sekundendaten.
- **Tests**: Unit-Tests für Ausrichtung mit Versatz, getroffen, zu leicht, Wiederholungen und fehlende Daten; UI-Test test37 in einer eigenen Datei.

### A · Einheit anpassen

- **Domain** (`Domain/WorkoutAdjust.swift`):
  - **Kürzer** auf 30, 45 oder 60 min: Warm-up und Cool-down bleiben, gekürzt oder entfernt werden zuerst Grundlagen-Blöcke, dann Wiederholungen. Es gibt keine Hauptblöcke unter 50 % ihrer Länge.
  - **Leichter** −5 % oder −10 % Intensität.
  - **Zurücksetzen** auf das Original (gespeichert).
  - Das Ergebnis ist eine gültige `WorkoutDefinition`.
- **Store** (`Store/AppModel+Adjust.swift`): wendet die Anpassung auf `StoredWorkout` an. Ist die Einheit schon an MyWhoosh gesendet, wird sie dort ersetzt (vorhandener Ersetzen-Weg). Der Kalendereintrag wird aktualisiert.
- **UI** (`UI/WorkoutDetailView.swift`): Menü „Anpassen“ nur bei geplanten Einheiten, mit Vorschau (Dauer, TSS vorher/nachher) und „Übernehmen“. Danach steht ein Hinweis „angepasst (vorher 75 min)“ mit „Original wiederherstellen“.
- **Tests**: Unit-Tests für Kürzen, Leichter, Grenzen, Zurücksetzen und MyWhoosh-Ersetzen (Stub); UI-Test test35 in einer eigenen Datei.

| Paket | Dateien (nur diese) |
|---|---|
| Z | `Domain/ZoneTime.swift`, `Domain/TrainingDistribution.swift`, `Domain/RelativeEffort.swift`, `Store/AppModel+Zones.swift`, `Store/AppModel.swift` (nur `relativeEffort(for:)`), `UI/HistoryView.swift` (nur `RideDetailView`), `UI/TrainingDistributionCard.swift`, `UI/RelativeEffortViews.swift`, `UI/RideZonesCard.swift`, Tests, `IndoorCoachUITests/AuditZonesTests.swift` |
| S | `Domain/IntervalCompliance.swift`, `Store/AppModel+Compliance.swift`, `UI/IntervalComplianceCard.swift`, Tests, `IndoorCoachUITests/AuditComplianceTests.swift` |
| A | `Domain/WorkoutAdjust.swift`, `Store/AppModel+Adjust.swift`, `Store/Models.swift` (nur `StoredWorkout`: Feld für das Original), `UI/WorkoutDetailView.swift`, Tests, `IndoorCoachUITests/AuditAdjustTests.swift` |
| Hauptsession | Einbindung der Karte S in die Einheit und des Seeds in `RootView`, Gerätetest-Protokoll (`docs/16-GERAETETEST.md`), Brückenstatus im Diagnose-Export, Integration, UX-Prüfung, Doku |

Regeln wie in den Paketen davor:
- Worktree und zuerst `git merge --ff-only main`.
- Zuerst die Tests.
- Keine fremden Dateien ändern. Fehlt etwas, kommt es additiv mit `// ANCHOR-SECONDS` dazu.
- Commits ohne Push.

## Umsetzung und Prüfung (18.11.2026)

| Paket | Ergebnis | Abweichungen und Nacharbeit |
|---|---|---|
| S0 | `RideSeconds`, Speicherung beim Import (FIT, Brücke), Demo-Sekundendaten; 5 Tests | – |
| Z | `ZoneTime` (Leistungszonen der App, neue Pulszonen: mit Schwellenpuls 81/89/94/100 %, sonst 60/70/80/90 % der Max-HF), Relative Effort „Puls (Sekunden)“ (TRIMP je Sekunde, nur wenn ≥ 50 % der Sekunden Puls haben), gemessene Trainingsverteilung („X von Y Fahrten mit Sekundendaten gemessen“), Karte „Zeit in Zonen“ im Fahrt-Detail; 10 Tests, test36 | Bänder der Verteilung direkt nach IF-Schwellen 0,75/0,95 je Sekunde, weil Zone 4 die Grenze 0,95 schneidet. **Nacharbeit:** Der Cache merkt sich jetzt auch „keine Sekundendaten“ (vorher eine Datenbankabfrage pro Fahrt und Darstellung) und wird bei jedem Import geleert. Die Zeitgrenze im Leistungstest liegt bei 1,5 s, weil der Test unter paralleler Last (Load > 900) gewackelt hat. |
| S | `IntervalCompliance` (Soll-Profil je Sekunde, Versatzsuche 0–600 s über 30-s-geglättete Ist-Leistung, Arbeitsintervalle ≥ 75 % FTP, getroffen ±5 %, verpasst bei < 50 % Abdeckung), Karte „Soll/Ist“ mit Diagramm und Intervallliste, Seed `-uiComplianceSeed`; 10 Tests, test37 | Die Ausrichtung nutzt die ersten 90 min des Plans statt 10 min, weil das Einfahren allein ein schwacher Anker ist |
| A | `WorkoutAdjust` (kürzer auf 30/45/60 min in fester Reihenfolge, leichter um −5/−10 %, Erholungen bleiben), Original wird einmal gespeichert und lässt sich wiederherstellen, Kalender und MyWhoosh ziehen nach; 13 Tests, test35/test35b | Auswahl „Unverändert“ zusätzlich. **Nacharbeit:** Erzeugt `upsert` einen extern gelöschten Termin neu, wird die neue Kalender-ID jetzt übernommen. Im Banner bricht „−5 %“ nicht mehr um. |
| Hauptsession | Karte S in der Einheit, Seed in `RootView`, Brückenstatus im Diagnose-Export (Mac-Name geschwärzt), [Gerätetest-Protokoll](16-GERAETETEST.md) | – |

**Tests:**
- 455 Unit-Tests grün.
- 13 UI-Tests gemeinsam auf einem Simulator grün: test35, test35b, test36, test37, Brücke test33/test34, Regression test01–04 und test19. Nur die drei bekannten Soft-Fails aus dem Stand davor (`.zwo`-Menü, Teilen-Sheet, TSS-Metrik).
- Screens visuell geprüft: Zeit in Zonen (Leistung/Puls), Soll/Ist „2 von 2 Intervallen getroffen · Ø 98 %“, Anpassen-Blatt mit Vorschau „69 → 45 min, TSS 72 → 43“, Hinweis „Angepasst · vorher 69 min“.

**Bekannt, bewusst so gelassen:** Eine gekürzte Einheit behält ihren Titel (z. B. „Sweet Spot 3×12“ mit zwei Blöcken). Die Zeile „Angepasst · vorher 69 min“ erklärt es, und der Titel bleibt so in MyWhoosh und im Kalender wiedererkennbar.
