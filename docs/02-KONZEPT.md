# Konzept & Architektur – IndoorCoach

Status: v1 · 16.11.2026 · ECC Phase 2 (Plan) · Grundlage: [01-PRD.md](01-PRD.md)

## 1. Größenklasse (ECC Step 0)

**large** – neue externe Abhängigkeiten (Strava, Claude API, EventKit), Spec-Dokument, mehrere offene Fragen.
→ Phasen 0 → 1 → 2 → 3 (Scaffold) → 4 → 5 → 6. Security-Review ist Pflicht (OAuth, Secrets, externe APIs).

## 2. Architektur-Überblick

```
┌──────────────────────────── iPhone (standalone) ────────────────────────────┐
│  IndoorCoach.app (dünne Hülle: App-Entry, Info.plist, Entitlements)         │
│        │                                                                    │
│        ▼                                                                    │
│  IndoorCoachKit (lokales Swift Package)                                     │
│   ├─ Domain     Workout, Segment, Zone, Activity, Profil, Kennzahlen        │
│   ├─ Logic      TrainingLoad (TSS/CTL/ATL/TSB), ZWOExporter, PlanPrompt     │
│   ├─ Services   StravaClient · ClaudeClient · CalendarService · Keychain    │
│   ├─ Store      SwiftData-Modelle + Repository                              │
│   └─ UI         SwiftUI-Screens (Übersicht · Verlauf · Plan · Profil)       │
└──────────┬───────────────────────────┬──────────────────────────────────────┘
           │ OAuth + REST              │ HTTPS (x-api-key)
           ▼                           ▼
     www.strava.com            api.anthropic.com/v1/messages
                                       
  MyWhoosh (seit B21/B22): Upload Custom Workout + Kalender, Fahrtenliste ──HTTPS──▶ *.mywhoosh.com
  Rückfallweg: .zwo ──AirDrop──▶ MacBook ──Upload──▶ workout.mywhoosh.com ──▶ MyWhoosh „My Workouts“
```

**Entscheidung: kein Backend.** Alles, was ein Server täte (Token-Refresh, Claude-Aufruf), kann die App selbst –
es gibt genau einen Nutzer, die Secrets bleiben im Keychain des eigenen Geräts. Das Docker-Setup bleibt Reserve
für Phase 2 (z. B. automatischer nächtlicher Sync/Planung oder Strava-Webhooks).

**Entscheidung: Logik in ein Swift Package.** Domain, Logik und Services sind plattformneutral und laufen auch auf
macOS → `swift test` ohne Simulator, schnelle TDD-Schleife, klare Grenzen. Die App ist nur die Hülle.

## 3. Technologie-Entscheidungen (ADR-Kurzform)

| ADR | Entscheidung | Alternativen | Begründung |
|-----|--------------|--------------|------------|
| 1 | SwiftUI + Swift Charts, iOS 18 | UIKit, Flutter | native Apple-Optik, Charts für Leistungsprofile, kein Fremdcode |
| 2 | SwiftData für Persistenz | Core Data, JSON-Dateien | modern, wenig Code, iCloud später möglich |
| 3 | Keychain für Secrets | UserDefaults | Tokens und API-Key dürfen nicht im Klartext liegen |
| 4 | Claude via REST (URLSession), Structured Output | Tool Use, Freitext parsen | kein offizielles Swift-SDK; `output_config.format` mit JSON Schema garantiert gültiges JSON |
| 5 | Modell `claude-opus-5-5`, Effort `medium` | Sonnet 5.5 (günstiger) | beste Planungsqualität; Kosten pro Plan ≈ 0,10 $. Im Profil umstellbar |
| 6 | Segmente in %FTP, nicht Watt | absolute Watt | identisch zu `.zwo`, bleibt gültig, wenn sich die FTP ändert |
| 7 | MyWhoosh über `.zwo`-Export (MVP); **seit 17.11.2026 zusätzlich direkt über die community-dokumentierte API** | intervals.icu-Umweg | `.zwo` bleibt der offizielle Rückfallweg (siehe §6) |
| 8 | Kalender über EventKit (Vollzugriff) | `.ics`-Export | Events lassen sich später aktualisieren/löschen; `.ics` als Fallback |
| 9 | TSS-Schätzung lokal | Strava „Relative Effort“ | Strava liefert keinen TSS; NP≈`weighted_average_watts` reicht für den Trend |

## 4. Datenmodell

```
Activity (SwiftData)            PlannedWorkout (SwiftData)          AthleteProfile (Codable, UserDefaults)
- stravaID: Int (unique)        - id: UUID                          - ftp: Int, weightKg: Double
- name, sportType               - date: Date                        - goal: String, goalDate: Date?
- startDate                     - title, summary, rationale         - weeklyHours: Double
- movingTime (s), distance (m)  - type: WorkoutType                 - trainingDays: Set<Weekday>
- avgWatts, weightedAvgWatts    - segmentsJSON → [Segment]          - preferredStart: Stunde/Minute
- kilojoules, avgHR, maxHR      - status: planned/done/skipped      - notes (Verletzungen, Vorlieben)
- trainer: Bool                 - calendarEventID: String?          
- tss (berechnet)               - linkedActivityID: Int?            
                                - createdBy: claude/demo/manual     

Segment (Codable, = .zwo-Bausteine)
- kind: warmup | steady | ramp | intervals | cooldown | freeRide
- duration (s), power / powerLow / powerHigh (Anteil FTP, 0.0–2.0)
- repeat, onDuration, offDuration, onPower, offPower   (nur intervals)
- cadence: Int?, text: String? (Hinweis, wird in .zwo als textevent ausgegeben)
```

## 5. Claude-Integration (Prompt-Design)

- `POST https://api.anthropic.com/v1/messages`, Header `x-api-key`, `anthropic-version: 2026-10-21`.
- `model: claude-opus-5-5`, `output_config: { effort: "medium", format: { type: "json_schema", schema: PlanSchema } }`,
  `max_tokens: 16000`, nicht gestreamt (Antwort < 16k). Thinking läuft adaptiv (bei Opus 5.5 immer an).
- **System-Prompt** (statisch → cachebar): Rolle „erfahrener Radsport-Trainer für Indoor-Training auf Smart Trainer“,
  Regeln: Polarisierung/Progression, max. 2 harte Einheiten in Folge vermeiden, TSB-Grenzen, nur an verfügbaren Tagen,
  Zeitbudget einhalten, Segmente in %FTP, Warm-up/Cool-down Pflicht, deutsche Texte.
- **User-Message** (dynamisch): Profil, Ziel + Tage bis Ziel, CTL/ATL/TSB heute, Wochenübersicht der letzten 6 Wochen,
  letzte 14 Einheiten kompakt (Datum, Dauer, NP, TSS, Indoor?), bereits geplante Einheiten, Planungszeitraum, Freitext-Wunsch.
  **Nicht** gesendet: GPS, Namen, Orte, Streams.
- **Antwort** (Schema): `{ weekFocus, notes, workouts: [{ date, title, type, summary, rationale, segments: [...] }] }`.
  Die App validiert zusätzlich (Datum im Zeitraum, Dauer > 0, Leistung 0,3–2,0) und verwirft Ungültiges.
- Fehlerbehandlung: 401 → „API-Key prüfen“, 429/529 → Retry mit Backoff, `stop_reason == "refusal"` → Meldung.

## 6. MyWhoosh – Optionen

| Option | Machbarkeit | Aufwand | Empfehlung |
|--------|-------------|---------|------------|
| A. Offizielle MyWhoosh-API | existiert nicht (Stand 11/2026) | – | ✗ |
| B. `.zwo`-Export → Upload im MyWhoosh Workout Builder (`workout.mywhoosh.com`) → „Export to MyWhoosh“ | offiziell unterstützt | 2 Klicks am Mac | **✓ MVP** |
| C. intervals.icu als Drehscheibe (App legt Workouts per intervals.icu-API an; Drittanbieter wie mywhooshinfo.com oder TrainingPeaks-Kette schieben weiter) | möglich, Drittanbieter teils unzuverlässig | mittel, zusätzlicher Account | Phase 2 (optional) |
| D. Reverse-Engineering der MyWhoosh-App-API | technisch evtl. möglich, verletzt vermutlich Nutzungsbedingungen, bricht bei Updates | hoch | ✗ (selbst) |
| D′. Community-dokumentierte API ([mywhoosh-community/mywhoosh-api](https://github.com/mywhoosh-community/mywhoosh-api), MIT) | auf dem iPhone bestätigt (Upload, Kalender, Fahrtenliste); inoffiziell, kann brechen | mittel | **✓ seit 17.11.2026** (B21/B22), `.zwo` bleibt Rückfall |
| E. Kalender als „Fernbedienung“ (Event enthält Workout-Text) | trivial | – | ✓ ergänzend |

Komfort-Idee für B: In Phase 2 eine kleine Mac-Menüleisten-App/Kurzbefehl, der per iCloud Drive abgelegte `.zwo`-Dateien
automatisch im Browser-Upload öffnet.

## 7. Risiken

| Risiko | Wirkung | Gegenmaßnahme |
|--------|---------|---------------|
| Strava-API-Bedingungen (KI) | Strava könnte die API-App sperren | nur eigene Daten, nur Aggregate, nur auf Klick; Alternative: Apple Health (HealthKit) als Datenquelle für Phase 2; schriftliche Rückfrage bei Strava |
| Free-Provisioning läuft nach 7 Tagen ab | App startet nicht mehr | Neu-Deploy aus Xcode (1 Klick) oder Apple-Developer-Programm |
| LLM erzeugt unsinnige Pläne | Fehltraining | Schema + Plausibilitätsprüfung + Begründung sichtbar + jederzeit editier-/löschbar |
| Strava-Token abgelaufen/rotiert | Sync schlägt fehl | automatischer Refresh, neuen Refresh-Token immer speichern |
| Kein Simulator-Runtime auf dem Mac | UI nicht live prüfbar | Build gegen iOS-SDK + gerenderte View-Snapshots auf macOS; morgen Runtime installieren |

## 8. Vertikale Slices (task_list → Gate 1)

| Slice | Inhalt | Ergebnis |
|-------|--------|----------|
| S0 Scaffold | Xcode-Projekt, Swift Package, Tab-Navigation, Design-Tokens, Demo-Daten | App startet mit 4 Tabs |
| S1 Workout-Domain | Segment/Workout/Zonen, Dauer/TSS/IF, `.zwo`-Export (TDD) | Plan-Tab zeigt Demo-Workouts mit Leistungsprofil, Export funktioniert |
| S2 Verlauf | Activity-Modell, TrainingLoad (TSS/CTL/ATL/TSB, TDD), Charts | Übersicht + Verlauf mit Demo-Aktivitäten |
| S3 Strava | OAuth, Keychain, Sync (TDD für Mapping/Filter) | echte Aktivitäten erscheinen |
| S4 Coach | Profil-Screen, Prompt-Builder (TDD), ClaudeClient, Plan übernehmen | echter Plan von Claude |
| S5 Kalender | EventKit-Service, „In Kalender“ je Einheit / ganze Woche | Events im iOS-Kalender |
| S6 Review & Härtung | Swift-/Security-Review (ECC Agents), Fixes, Doku, Install-Guide | Prototyp-Übergabe |

Jede Slice endet mit Build + Tests + Review und einem `feat:`-Commit (lokal, kein Push).

## 9. Gate-Hinweis

Laut ECC-Prozess gibt es zwei menschliche Gates (Plan-Freigabe, Commit-Freigabe). Da du über Nacht ohne Rückfragen
einen Prototyp möchtest, habe ich deine Nachricht als Freigabe für Gate 1 gewertet und committe **nur lokal**
(kein Remote, kein Push). Alles ist morgen per Review/Änderungswunsch korrigierbar.
