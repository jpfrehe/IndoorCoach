# Winter-Paket 2: offene Punkte aus dem Brainstorming (ECC, 4 parallele Arbeitspakete)

Stand 17.11.2026 · Grundlage: [Brainstorming](09-BRAINSTORM-WINTER-MOTIVATION.md) §3 · Freigabe: Nutzer („setze offene Punkte daraus um“).
Leitplanken, Einstiege und Regeln für parallele Arbeit wie im [Konstanz-Paket](10-KONSTANZ-PAKET.md) §1 und §4. Zusätzlich gelten die Erkenntnisse aus [UX-Audit 2](ux-audit-2026-11-17-b.md):
- Keine Lazy-Grids in Karten.
- Container-Karten mit `.accessibilityElement(children: .contain)`, bevor sie eine Kennung bekommen.
- Chips mit `fixedSize`; Zeilen stapeln sich bei Accessibility-Größen.

## Stand der Brainstorming-Punkte

| ID | Status vorher | Dieses Paket |
|---|---|---|
| A1 Aerobe Effizienz, A2 Wochenrückblick, A3 Plan-Treue, G1 Serie mit Joker, G2 Challenges, G3 Trophäen | ✅ (Konstanz-Paket) | – |
| A5 Ziel-Prognose + Was-wäre-wenn, A8 Trainingsverteilung, A6 eFTP-Verlauf | offen | **P1** |
| A4 Fähigkeitslevel je Zone, A7 Ermüdungsresistenz | offen | **P2** |
| G6 Vorjahres-Schatten, G5 Saisonrückblick zum Teilen | offen | **P3** |
| G4 Winter-Reise, G7 Erinnerung vor geplanten Einheiten | offen | **P4** |
| G7 Widget „Heute“ | offen | später: braucht ein eigenes App-Extension-Target, App Group und Signierung |
| G8 Accountability-Gruppe | offen | später: braucht ein Backend |

## P1 · Prognose & Verteilung (Analyse)

- **A5 Ziel-Prognose:**
  - Aus aktueller CTL und geplantem Wochen-TSS (Profil-Wochenbudget × Ø-TSS/h der letzten 6 Wochen, sonst 50 TSS/h) wird die CTL per EWMA (42 Tage) bis zum Ziel-Tag fortgeschrieben.
  - Ergebnis: „Bei 5 h/Woche erreichst du am 21. März Fitness 41 (Ziel 44)“ bzw. „… schon am 2. März“.
  - Was-wäre-wenn-Regler für Stunden pro Woche (2–15 h, nur Ansicht, ändert das Profil nicht) mit sofortiger Neuberechnung.
  - Ort: Karte am `ANCHOR-P1-WINTERARC`.
- **A8 Trainingsverteilung:**
  - Anteil der Zeit in Zonen-Gruppen über 4 bzw. 12 Wochen: Grundlage (IF < 0,75), Tempo/Sweet Spot (0,75–0,95), Schwelle+ (≥ 0,95).
  - Je Fahrt aus IF (NP bzw. Ø × 1,05 ÷ FTP); Fahrten ohne Leistung zählen als „unbekannt“.
  - Darstellung als gestapelter Balken mit Text „81 % Grundlage – passt zum Winter“ oder „Viel Intensität: plane mehr lockere Einheiten“.
  - Ort: `ANCHOR-P1-LEISTUNG`.
- **A6 eFTP-Verlauf:**
  - eFTP je 4-Wochen-Fenster (95 % der gemessenen 20-min-Bestleistung des Fensters), Linie über 6 Monate, Profil-FTP als Referenzlinie.
  - Nur gemessene Werte.
  - Ort: `ANCHOR-P1-LEISTUNG`, unter der Verteilung.
- **Tests:**
  - Unit: Prognose gegen bekannte EWMA-Werte, Verteilung, eFTP-Fenster.
  - UI: test25.

## P2 · Fähigkeiten (Analyse)

- **A4 Fähigkeitslevel je Zone:** Level 1–10 für Ausdauer (60 min), Schwelle (20 min), VO2 (5 min) und Anaerob (1 min) aus der Leistungskurve der letzten 90 Tage.
  - Skala: Watt/kg-Bänder je Dauer, an gängige Leistungsprofil-Tabellen angelehnt (z. B. 20 min: 2,0 W/kg → 1, 5,0 W/kg → 10, linear).
  - Gemessene Werte haben Vorrang; ist ein Wert nur ein Mindestwert, steht dabei „mindestens“.
  - Zusätzlich die Veränderung zum Vorquartal (±).
  - Ort: `ANCHOR-P2-LEISTUNG`, als 4 Zeilen mit Level-Balken.
- **A7 Ermüdungsresistenz:**
  - Nur FIT-Fahrten ≥ 60 min: beste 5-min-Leistung in der letzten Stunde gegen die beste 5-min-Leistung insgesamt, in %.
  - Beim FIT-Import berechnet, als optionales Attribut an `StoredRide` gespeichert (leichte Migration).
  - Fahrt-Detail: `ANCHOR-P2-FAHRT`.
  - Leistung: Durchschnitt der letzten 90 Tage, mit Erklärung.
- **Tests:**
  - Unit: Level-Skala, Grenzen, Ermüdungsresistenz aus konstruierten Reihen, Migration.
  - UI: test26.

## P3 · Vorjahr & Rückblick (Gamification)

- **G6 Vorjahres-Schatten:**
  - Im Winter-Arc-Kurschart (`WinterArcView.courseChart`) und im Fitness-&-Freshness-Chart erscheint die CTL-Kurve desselben Zeitraums ein Jahr früher als gestrichelte, gedämpfte Linie „Vorjahr“, wenn Daten vorhanden sind.
  - Daten: Strava/MyWhoosh liefern bis 210 Tage, ein Vorjahr gibt es erst ab dem zweiten Winter oder mit FIT-Import.
  - Demo: plausible Vorjahreswerte, deterministisch.
  - Legende und VoiceOver: „Heute 34, Vorjahr 29“.
- **G5 Saisonrückblick zum Teilen:**
  - Am `ANCHOR-P3-WINTERARC` „Saisonrückblick teilen“.
  - Bild per `ImageRenderer`: Level, Fitness Start → heute, Serie, Challenges geschafft, beste 20-min-Leistung, Zeitraum; im Sunset-Jelly-Stil, 1080 × 1350.
  - `ShareLink` mit dem Bild; keine personenbezogenen Daten außer den Kennzahlen; der Name nur, wenn im Profil gesetzt.
- **Tests:**
  - Unit: Kennzahlen des Rückblicks, Vorjahres-Zeitraum.
  - UI: test27 (Teilen öffnet das Share-Sheet).

## P4 · Reise & Erinnerung (Gamification)

- **G4 Winter-Reise:**
  - Karte am `ANCHOR-P4-WINTERARC`: Fortschritt des Winter Arc als stilisierte Etappenroute (kein MapKit), z. B. „Alpenüberquerung“ in 10 Etappen = 10 Level.
  - Gezeichneter Pfad (SwiftUI-`Path`) mit Etappenpunkten, aktuellem Punkt und Ortsnamen je Level: Garmisch → Fernpass → Reschen → Stilfser Joch → … → Gardasee.
  - Fortschritt innerhalb einer Etappe = `levelProgress`.
  - VoiceOver: „Etappe 2 von 10: Fernpass, 40 % geschafft“.
  - Rein darstellend, keine neuen Daten.
- **G7 Erinnerung vor geplanten Einheiten:**
  - Opt-in-Schalter in `ReminderSection` (Profil): „Erinnerung 30 Minuten vor der Einheit“.
  - Plant lokale Mitteilungen für die nächsten 14 Tage geplanter Einheiten, über das bestehende `ReminderCenter`-Protokoll; Text: „Gleich: Sweet Spot 3×12 · 1:09 h · TSS 72“.
  - Neu planen beim Übernehmen eines Plans (`ANCHOR-P4-APPMODEL`), beim Löschen einer Einheit und beim App-Start.
  - Höchstens 20 ausstehende; „Alle Daten löschen“ entfernt sie.
- **Tests:**
  - Unit: Planungslogik mit Fake-`ReminderCenter`.
  - UI: test28 (Winter-Reise sichtbar, Schalter im Profil).

## Zuständigkeiten (exklusiv)

| Paket | Darf ändern |
|---|---|
| P1 | neue Dateien; `WinterArcView` nur am Anker |
| P2 | `FITParser`, `Models` (neues optionales Attribut), `TrainingLoad` (`RideSummary`-Feld) |
| P3 | `WinterArcView.courseChart`, `FitnessFreshnessView`, `Demo.swift` (Vorjahresdaten) |
| P4 | `ReminderSection.swift`, `WeeklyReviewReminder.swift` (gemeinsames Reminder-Protokoll erweitern), `AppModel` nur am Anker sowie `delete`/`deleteAllData` je eine Zeile |

UI-Tests je Paket nur am eigenen `ANCHOR-UITEST-P…`.

## Umsetzung und Prüfung (17.11.2026)

Vier Sonnet-Subagenten, parallel in eigenen Worktrees. Jeder Worktree wurde zuerst auf den lokalen `main` vorgespult. Die Hauptsession hat jedes Paket geprüft und zusammengeführt.

| Paket | Ergebnis | Nacharbeit der Hauptsession |
|---|---|---|
| P1 Prognose, Verteilung, eFTP-Verlauf | ✅ | Die Prognose rechnete ihre Last pro Stunde mit der einfachen TSS-Schätzung, setzt aber die Fitness-Kurve fort, die mit `FitnessFreshness.load` (inkl. Relative-Effort-Faktor) entsteht. Jetzt nutzen beide dieselbe Last. |
| P2 Fähigkeitslevel, Ermüdungsresistenz | ✅ | – (Demo-Fahrten haben keine Sekundendaten, daher dort ehrlich „keine Daten“) |
| P3 Vorjahres-Schatten, Saisonrückblick | ✅ | – (eigener Vorjahres-Demo-Block; die bestehenden Demo-Fahrten bleiben unverändert) |
| P4 Winter-Reise, Erinnerung vor Einheiten | ✅ | – |

**Ergebnis:**
- 322 Unit-Tests grün.
- UI-Tests test25–28 und die Regressionen test01, 04, 14, 19, 20, 22, 23 im Simulator grün.
- Konsole: 0 meldepflichtige Einträge.
- Vom Ablauf abweichend bleibt nur der bekannte Wackel-Check „Metrik zeigt TSS nach einem Tap“.
- Sichtprüfung im Simulator: Winter-Reise, Vorjahres-Linie (Winter Arc und Fitness & Form), Prognose mit Rechenweg und Saisonrückblick-Button sind lesbar und vollständig.

**Offen:**
- Widget (braucht ein App-Extension-Target und Signierung).
- Accountability-Gruppe (braucht ein Backend).
- Die Rechenweg-Zeile der Prognose zeigt die gerundete TSS/h („5 h × 54 TSS/h = 272 TSS“) – kosmetisch.
