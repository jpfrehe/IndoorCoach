# PRD – IndoorCoach (Arbeitstitel)

> **Stand nach dem MVP (17.11.2026):** Dieses PRD beschreibt den MVP. Erweiterungen seither: MyWhoosh-Direktupload und Fahrten-Import, Winter Arc, Leistung/VO2max, Konstanz-Paket – siehe [Status](04-STATUS.md).

Status: Entwurf v1 · 16.11.2026 · Phase „Planung“ (ECC `orch-build-mvp`, Phase 0–2)

## 1. Problem

Indoor-Einheiten auf der Wahoo-Rolle (MyWhoosh am MacBook) werden heute ad hoc gewählt.
Die Daten liegen vollständig in Strava, aber es gibt keinen Ort, der

- die vergangenen Einheiten sinnvoll auswertet (Belastung, Form, Trend),
- daraus zusammen mit persönlichen Zielen die nächsten Einheiten plant,
- die Planung sichtbar macht (Kalender) und
- das Workout ohne Abtippen in MyWhoosh bringt.

## 2. Nutzer

Genau ein Nutzer (der Eigentümer der App). Keine Mandantenfähigkeit, kein Login-System,
keine Verteilung über den App Store. Installation per Xcode auf das eigene iPhone.

## 3. Ziele / Nicht-Ziele

**Ziele (MVP)**

| # | Ziel | Messbar, wenn … |
|---|------|-----------------|
| G1 | Workouts aus Strava sehen und verstehen | die letzten 90 Tage Rad-Aktivitäten erscheinen mit Wochenbelastung und Form-Kurve |
| G2 | Zukünftige Einheiten mit Claude planen | ein Klick erzeugt einen 1–2-Wochen-Plan aus Zielen + aktuellen Daten, strukturiert (Intervalle in %FTP) |
| G3 | Plan verständlich darstellen | jede Einheit zeigt Leistungsprofil-Grafik, Dauer, Zonen, Begründung |
| G4 | Plan in den Kalender | Einheit(en) mit einem Tipp in den iOS-Kalender (inkl. Workout-Beschreibung) |
| G5 | Workout nach MyWhoosh bringen | Export als `.zwo` (Zwift-Format), Import über den MyWhoosh Workout Builder |
| G6 | Standalone | kein eigener Server nötig; alle Daten lokal auf dem iPhone |

**Nicht-Ziele (MVP)**

- Live-Steuerung der Rolle (ERG) aus der App – macht MyWhoosh.
- Outdoor-Routenplanung, Ernährung, Social Features.
- Upload von Aktivitäten nach Strava.
- Android / Mac-App.

## 4. User Stories

| ID | Story | Prio |
|----|-------|------|
| US1 | Als Fahrer verbinde ich einmalig meinen Strava-Account (OAuth), damit die App meine Aktivitäten lesen kann. | Must |
| US2 | Als Fahrer sehe ich eine Übersicht: diese Woche (Zeit, TSS, kJ), Fitness/Ermüdung/Form, nächste geplante Einheit. | Must |
| US3 | Als Fahrer sehe ich vergangene Einheiten als Liste und Diagramme (Wochenvolumen, Leistung) und kann nach Indoor filtern. | Must |
| US4 | Als Fahrer hinterlege ich FTP, Gewicht, Ziel (Text + Zieldatum), verfügbare Tage und Zeitbudget. | Must |
| US5 | Als Fahrer lasse ich Claude einen Plan für die nächsten 7–14 Tage erzeugen und gebe optional einen Wunsch mit („diese Woche nur 3 Einheiten“). | Must |
| US6 | Als Fahrer sehe ich jede geplante Einheit als Intervall-Grafik nach Leistungszonen und lese die Begründung des Coaches. | Must |
| US7 | Als Fahrer übertrage ich eine oder alle Einheiten in meinen Kalender. | Must |
| US8 | Als Fahrer exportiere ich eine Einheit als `.zwo` (AirDrop an den Mac → MyWhoosh Workout Builder). | Must |
| US9 | Als Fahrer markiere ich Einheiten als erledigt/übersprungen; erledigte werden mit der Strava-Aktivität verknüpft. | Should |
| US10 | Als Fahrer kann ich die App ohne Zugangsdaten im Demo-Modus ausprobieren. | Should |
| US11 | Als Fahrer kann ich eine geplante Einheit von Claude anpassen lassen („kürzer“, „leichter“). | Could |
| US12 | Workouts direkt in MyWhoosh anlegen (ohne manuellen Upload). | Won’t (MVP) – keine öffentliche API, siehe Konzept §6. **Seit 17.11.2026 umgesetzt** über die inoffizielle Community-API (Backlog B21) |

## 5. Funktionale Anforderungen

- **F1 Strava-Sync**: OAuth 2 (mobile authorize, ASWebAuthenticationSession), Scope `activity:read_all`.
  Inkrementeller Sync über `GET /athlete/activities?after=…`, Paginierung 100/Seite. Token-Refresh automatisch.
  Gefiltert auf Rad-Sportarten (`Ride`, `VirtualRide`, `EBikeRide` optional); Indoor = `VirtualRide` oder `trainer == true`.
- **F2 Kennzahlen**: TSS pro Aktivität (aus gewichteter Leistung/NP und FTP; Fallback HR- bzw. Zeit-Schätzung),
  CTL (42 Tage), ATL (7 Tage), TSB = CTL − ATL. Wochenaggregation.
- **F3 Coach (Claude)**: Messages API, Modell `claude-opus-5-5`, Structured Output (JSON Schema) → garantiert parsbarer Plan.
  Input: Profil, Ziel, Verfügbarkeit, Kennzahlen, kompakte Liste der letzten 6 Wochen, bereits geplante Einheiten, Freitext-Wunsch.
  Output: Liste von Workouts (Datum, Titel, Typ, Ziel, Begründung, Segmente in %FTP).
- **F4 Darstellung**: Leistungsprofil (Swift Charts), Farben je Zone (Coggan Z1–Z7), Dauer, geschätzte TSS/IF.
- **F5 Kalender**: EventKit, Event mit Titel, Startzeit (Standard-Uhrzeit aus Profil), Dauer, Notizen (Segmente in Klartext).
- **F6 Export**: `.zwo`-Datei (XML) via Share Sheet; Hinweis-Text + Link auf `workout.mywhoosh.com`.
- **F7 Speicherung**: SwiftData lokal; Secrets (Strava Client Secret/Tokens, Claude API Key) im Keychain.

## 6. Nicht-funktionale Anforderungen

- iOS 18+, SwiftUI, Apple Human Interface Guidelines (Tab-Bar, Large Titles, SF Symbols, Dark Mode, Dynamic Type).
- Läuft ohne Backend. Netzwerk im MVP nur zu `strava.com` und `api.anthropic.com`; seit B21/B22 zusätzlich zu MyWhoosh (vom Nutzer verbunden).
- Keine Secrets im Code oder Repo.
- Kosten: ein Planungsaufruf ≈ 5–10k Input-/3–6k Output-Tokens → ca. 0,10 – 0,15 $ pro Plan (Opus 5.5: $4/$20 pro MTok).

## 7. Annahmen & offene Punkte (morgen klären)

| # | Thema | Annahme im Prototyp |
|---|-------|---------------------|
| A1 | Claude-Zugang | „Claude-Account“ = API-Key aus der Claude Console (console.anthropic.com). Ein claude.ai-Abo enthält **keinen** API-Zugang. |
| A2 | Strava-API-App | Du legst unter strava.com/settings/api eine eigene App an (Callback-Domain `localhost`). Seit 06/2026 braucht man dafür ein Strava-Abo. |
| A3 | Strava & KI | Die Strava-API-Bedingungen verbieten KI-*Training* mit API-Daten; ob *Inferenz* auf eigenen Daten erlaubt ist, ist offiziell ungeklärt. Prototyp sendet nur aggregierte Kennzahlen deiner eigenen Fahrten, nur auf deinen Klick. Risiko siehe Konzept §7. |
| A4 | FTP | manuell gepflegt (Default 250 W) |
| A5 | Signierung | Kostenloser Apple-Account → App läuft 7 Tage, dann neu aus Xcode installieren; mit Developer-Programm 1 Jahr. |

## 8. Erfolgskriterien Prototyp (morgen früh)

1. Projekt baut fehlerfrei für iOS; Kernlogik ist getestet (`swift test`).
2. Demo-Modus zeigt alle Screens mit realistischen Daten.
3. Mit eigenen Keys: Strava verbinden, synchronisieren, Plan von Claude erzeugen, Kalender-Eintrag, `.zwo`-Export.
