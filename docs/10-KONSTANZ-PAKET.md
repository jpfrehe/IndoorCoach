# Feature-Paket „Konstanz“ (ECC: orch-add-feature, 4 parallele Arbeitspakete)

Stand 17.11.2026 · Grundlage: `docs/09-BRAINSTORM-WINTER-MOTIVATION.md` · Größe: **groß**, deshalb in 4 unabhängige Pakete geteilt · Gate 1: vom Nutzer freigegeben („Lasse den Sonnet-Subagent … parallel implementieren“).

## 1. UX-Bewertung des aktuellen Konzepts

**Informationsarchitektur heute:** 4 Tabs.
- **Heute:** Demo-Hinweis → Nächste Einheit → Winter Arc → Form → Woche → Volumen → VO2max (bis zu 7 Karten untereinander).
- **Plan:** Wochen-Abschnitte mit Planen-Button.
- **Verlauf:** Leistung → Relative-Effort-Woche → Filter → Metrik → Fahrten.
- **Profil:** Einstellungen, Quellen, Hilfe, Daten.

| # | Befund | Folge für das Paket |
|---|---|---|
| U1 | Heute ist ein **wachsender Kartenstapel**. Was jetzt zu tun ist, steht oben, Motivation erst an Position 3. | **Keine neuen Dauerkarten.** Ein **Highlight-Slot** direkt unter „Nächste Einheit“ zeigt nur zeitlich relevante Hinweise (Wochenrückblick So–Di, aktive oder bald startende Challenge). |
| U2 | **Saison-Motivation** (Winter Arc: Level, Serie) hat eine eigene Detailseite, aber keine Ziele „für diese Woche“. | Winter-Arc-Detail wird der **Saison-Hub**: Konstanz-Serie mit Joker, Challenges, Trophäen. |
| U3 | **Analyse** liegt verteilt (Leistung im Verlauf, VO2max auf Heute und Leistung, Form auf Heute). | „Leistung“ bleibt der **Analyse-Hub**. Neue Analysen (Effizienz) kommen dorthin, Kurzwerte ins Fahrt-Detail. |
| U4 | Der **Plan-Tab** zeigt nur Soll, kein Ist. Ob die Woche „geschafft“ ist, sieht man nirgends. | Wochen-Kopf im Plan zeigt die **Plan-Treue** (Einheiten und TSS erledigt). |
| U5 | Die bisherige **Serie** (≥ 80 % Wochenbudget) bestraft Krankheit und geplante Erholungswochen. Das widerspricht der Leitplanke „Ruhe zählt“. | Serie mit **Joker** und **Erholungswochen-Regel**. |
| U6 | Es gibt **keine Rückmeldung zum Wochenabschluss**. Das Gefühl „Woche geschafft“ fehlt. | **Wochenrückblick** am Sonntag, auf Wunsch mit Mitteilung. |
| U7 | Fahrten ohne Sekundendaten (MyWhoosh-Liste) liefern **Ø-Watt + Ø-Puls**. Das bleibt für Analysen bisher ungenutzt. | **Aerobe Effizienz** nutzt genau diese Daten. |

**Leitplanken (für alle Pakete):**
- Ruhetage und Erholungswochen zählen als Erfolg.
- Keine Tages-Streaks, keine Ranglisten nach Watt.
- Jede Kennzahl nennt ihre Quelle.
- Texte: Deutsch, „du“, kurz.
- Kontrast ≥ 4,5:1, Dynamic Type, 44-pt-Ziele, VoiceOver-Zusammenfassungen für Charts.

## 2. Einstiege je Feature

| Paket | Heute | Plan | Verlauf / Leistung | Winter-Arc-Detail | Fahrt-Detail | Profil | System |
|---|---|---|---|---|---|---|---|
| K1 Konstanz-Serie + Plan-Treue | Chip in der Winter-Arc-Karte: „5 Wochen in Folge · 1 Joker“ | Wochen-Kopf: „3/4 Einheiten · 92 % TSS“ | – | Karte „Konstanz“: letzte 8 Wochen als Punkte | – | – | – |
| K2 Wochenrückblick | Highlight-Slot So 16 Uhr bis Di: „Deine Woche“ | – | – | – | – | Abschnitt „Erinnerungen“: Mitteilung So 18 Uhr | lokale Mitteilung |
| K3 Challenges + Trophäen | Highlight-Slot, wenn eine Challenge läuft oder in ≤ 7 Tagen startet | – | – | Karten „Challenges“ und „Trophäen“ → Trophäenschrank | Hinweis, wenn diese Fahrt eine Challenge abgeschlossen hat | – | – |
| K4 Aerobe Effizienz | – | – | Leistung: Karte „Aerobe Effizienz“ mit Trend | – | Werte „Effizienz“ und (mit FIT) „Entkopplung“ | – | – |

## 3. Arbeitspakete (Specs)

### K1 · Konstanz-Serie mit Joker + Plan-Treue

- **Woche:** ISO-Woche, Montag bis Sonntag. Die laufende Woche bricht keine Serie, solange sie läuft.
- **Erfüllt**, wenn eine der Bedingungen gilt:
  - **(a)** ≥ 80 % des Wochenbudgets gefahren (bisherige Regel);
  - **(b)** alle geplanten Einheiten der Woche erledigt (mindestens 1 geplant);
  - **(c) Erholungswoche:** Plan-TSS < 70 % des Mittels der 3 Vorwochen-Pläne **und** ≥ 50 % davon gefahren.
- **Joker:** Pro 4 erfüllten Wochen in Folge gibt es 1 Joker, höchstens 2 gespeichert. Eine verpasste Woche verbraucht automatisch einen Joker; die Serie läuft dann weiter und zählt die Woche als „Joker“, nicht als erfüllt. Ohne Joker bricht die Serie.
- **Plan-Treue je Woche:**
  - geplant, erledigt (`WorkoutStatus.done` bzw. verknüpfte Fahrt) und offen;
  - TSS geplant gegen TSS gefahren (Fahrten der Woche, `TrainingLoad.estimateTSS`);
  - Quote in % und Text: „3 von 4 Einheiten · 92 % TSS“.
- **Integration:**
  - `WinterArc.Status.streakWeeks` bleibt erhalten, rechnet aber jetzt nach diesen Regeln; neu ist `jokers`. Beide Werte stellt das Paket bereit, damit K3 sie nutzen kann.
  - Chip in `WinterArcCard`, Wochen-Kopf in `PlanView.weekHeader`, Karte „Konstanz“ am `ANCHOR-K1-WINTERARC`.
  - Erklärtext „So funktioniert der Winter Arc“ wird aktualisiert.
- **Tests:**
  - Unit: Regeln a, b, c, Joker-Erwerb, Verbrauch, Maximum, laufende Woche.
  - UI: test20 (Winter-Arc-Detail zeigt „Konstanz“, Plan-Kopf zeigt Plan-Treue).

### K2 · Wochenrückblick

- **Domain `WeeklyReview`** für eine abgeschlossene oder laufende Woche:
  - Fahrten, Stunden, TSS (Ist gegen Plan);
  - Plan-Treue (eigene einfache Zählung, unabhängig von K1);
  - Fitness-Änderung (CTL Wochenanfang → Wochenende), Form am Wochenende;
  - Relative-Effort-Summe gegen den Bereich;
  - neue Bestleistungen der Woche (`PowerCurve.records`).
- **Texte:** Daraus entstehen 1 Überschrift und 2–3 regelbasierte Sätze, z. B. „Starke Woche: alle 4 Einheiten gefahren“ oder „Fitness +2,1 – Form jetzt frisch (+6)“.
- **Kein Claude-Aufruf** (Kosten); eine KI-Zusammenfassung ist ein späteres Backlog-Thema.
- **UI:**
  - Karte am `ANCHOR-K2-HEUTE`, sichtbar So ab 16 Uhr bis Di 23:59 für die gerade endende bzw. letzte Woche.
  - „Ausblenden“ pro Woche, gespeichert in UserDefaults; den Key in `AppModel.Keys.all` aufnehmen.
  - Tippen öffnet `WeeklyReviewView` mit dieser Woche und den letzten 8 Wochen.
- **Mitteilung:**
  - Opt-in-Schalter im Profil (`ANCHOR-K2-PROFIL`, eigener `ReminderSection`-View).
  - Beim Einschalten Berechtigung anfragen, dann wöchentliche lokale Mitteilung So 18:00 („Dein Wochenrückblick ist da“) über `UNUserNotificationCenter`; Ausschalten entfernt sie.
  - Profilfeld `weeklyReviewReminder: Bool`, migrationssicher via `decodeIfPresent`.
- **Tests:**
  - Unit: Texte für typische Wochen, Sichtbarkeitsfenster, Leer-Woche.
  - UI: test21 (Debug-Argument, um „Sonntag“ zu simulieren, z. B. `-uiNow 2026-11-22T17:00:00Z`, oder ein Sichtbarkeits-Override `-uiWeeklyReview YES`).

### K3 · Saison-Challenges + Trophäenschrank

- **Challenges** sind statisch je Saison (Jahr aus dem Datum abgeleitet) und zählen nur Indoor-Fahrten:
  - **„Indoor-500“**, 24.–31.12.: 500 Minuten;
  - **„Kalter Januar“**: 12 Einheiten im Januar;
  - **„Februar-Fundament“**: 10 h Grundlage im Februar (Fahrten mit IF < 0,75, IF aus NP bzw. Ø-Watt × 1,05 / FTP; ohne Leistung zählt die Fahrt nicht);
  - **„Monats-Konstanz“** für jeden Monat Nov–Mär: 8 Einheiten.
- **Fortschritt** rein aus Fahrten berechnet, keine Persistenz.
- **Trophäen** werden berechnet, nicht gespeichert, jeweils mit Datum:
  - Challenge geschafft;
  - Winter-Arc-Level erreicht (je Level, Datum = Tag des Erreichens aus der Fitness-Reihe);
  - Serie 4/8/12 Wochen (`WinterArc.Status.streakWeeks`, aktueller Stand);
  - neue Bestleistung (`PowerCurve.records`, je Dauer die jüngste);
  - erste Fahrt mit Sekundendaten (`powerCurve != nil`).
- **UI:**
  - Highlight-Karte am `ANCHOR-K3-HEUTE`, wenn eine Challenge läuft oder in ≤ 7 Tagen startet: Fortschrittsring, Rest, Tage übrig.
  - Am `ANCHOR-K3-WINTERARC` Karten „Challenges“ (laufend, demnächst, abgeschlossen) und „Trophäen“ (die letzten 6 plus „Alle anzeigen“ → `TrophyCaseView` als Raster; noch nicht erreichte Trophäen ausgegraut mit Bedingung).
  - Am `ANCHOR-K3-FAHRT` ein Hinweis „Mit dieser Fahrt: Monats-Konstanz November geschafft“.
- **Tests:**
  - Unit: Fenster, Zählung, Grenzen (Silvester, Jahreswechsel), Trophäen-Datum.
  - UI: test22 (Demo im November: Monats-Konstanz läuft → Highlight sichtbar → Winter Arc → Trophäenschrank).

### K4 · Aerobe Effizienz (+ Entkopplung)

- **Effizienzfaktor (EF)** je Fahrt = NP (oder Ø-Watt) ÷ Ø-Herzfrequenz.
  - Nur Fahrten mit beidem, Dauer ≥ 20 min und IF ≤ 0,85 (vergleichbare Ausdauerfahrten).
  - MyWhoosh liefert `heartrate` 0 ohne Gurt; das ist schon `nil`.
- **Trend:** Wochen-Median; Vergleich der letzten 6 Wochen mit den 6 davor in %. Text: „+4 %: gleiche Leistung mit weniger Puls“.
- **Entkopplung (Pw:HR)**, nur mit FIT (Sekunden-HF und -Leistung):
  - EF der ersten Hälfte gegen die zweite Hälfte in %;
  - beim FIT-Import berechnen, als optionales Attribut an `StoredRide` speichern (leichte Migration);
  - Bewertung: < 5 % = „stabil“.
- **UI:**
  - Karte „Aerobe Effizienz“ am `ANCHOR-K4-LEISTUNG`: Trend-Chart, Veränderung, Abdeckung „x Fahrten mit Leistung und Puls“, Erklärung, Hinweis „Puls-Gurt tragen“, wenn zu wenig Daten.
  - Am `ANCHOR-K4-FAHRT` Werte EF und ggf. Entkopplung.
- **Tests:**
  - Unit: EF-Filter, Median, Trend, Entkopplung aus konstruierten Reihen, Migration.
  - UI: test23 (Leistung → Effizienz-Karte sichtbar mit Demo-Daten).

## 4. Regeln für die parallele Umsetzung

- Jedes Paket in **eigenem Worktree und Branch**, Sonnet-Subagent, TDD.
- **Neue Logik und Views in eigenen Dateien** (`Domain/<Name>.swift`, `UI/<Name>View.swift`, `Tests/<Name>Tests.swift`).
- In geteilten Dateien **nur am eigenen `ANCHOR-…`-Kommentar** einfügen, den Kommentar stehen lassen.
- **Exklusive Zuständigkeiten:**

| Paket | darf ändern |
|---|---|
| K1 | `Domain/WinterArc.swift` (Serie), `WinterArcCard`-Chip und Erklärtext in `UI/WinterArcView.swift`, `PlanView.weekHeader` |
| K2 | `AthleteProfile`, `AppModel.Keys` |
| K3 | keine bestehenden Domain-Dateien |
| K4 | `Services/FITParser.swift`, `Store/Models.swift`, `Services/Demo.swift` |

- UI-Test je Paket nur am eigenen `ANCHOR-UITEST-K…`.
- Keine Doku-Dateien ändern, außer einem eigenen Abschnitt im Abschlussbericht. Die Hauptsession pflegt `docs/`.
- `project.pbxproj` nicht anfassen. Kein Simulator, kein Gerät.
- **Fertig heißt:**
  - `swift test` grün;
  - `xcodebuild build-for-testing` (generic iOS Simulator, eigener DerivedData-Pfad) grün;
  - Commits auf dem eigenen Branch (konventionell, mit Co-Authored-By-Zeile);
  - Bericht mit Abweichungen.
- **Danach die Hauptsession:** Review je Paket, Merge, Priorität im Highlight-Slot (höchstens eine Karte: K2 vor K3), UI-Tests im Simulator, Gerätetest, Commit.
