# Feature-Paket „Winter Arc“ – Relative Effort, Fitness & Freshness, Fortschritts-Level

ECC-Prozess `orch-build-mvp`: Intake → Research → Plan (Gate 1) → Scaffold → TDD → Review → Commit (Gate 2).
**Gate 1**: Die Freigabe ist die Nachricht des Nutzers vom 17.11.2026 („Arbeite diese Features wieder nach dem ecc mvp Prozess aus“). Wie im ersten Durchlauf nur lokale Commits, kein Push.

## 1. Intake

| # | Wunsch | Nutzen für die Persona (Indoor-Rennradfahrer, Ziel im Frühjahr) |
|---|---|---|
| F-RE | **Relative Effort**: kardiovaskuläre Arbeit je Aktivität aus Herzfrequenz oder Perceived Exertion | Belastung auch ohne Wattmessung vergleichbar (Outdoor ohne Powermeter, Rolle ohne HF-Gurt) |
| F-FF | **Fitness & Freshness**: Fitness, Ermüdung und Form über die Zeit | „Bin ich auf dem Weg nach oben oder grabe ich mich ein?“ |
| F-WA | **Fortschritts-Level „Winter Arc“** vom Saisonstart bis zum Ziel im Frühling | Motivation über die dunklen Monate, sichtbare Etappen statt nur Zahlen |

## 2. Research (Strava-Hilfeartikel, 17.11.2026)

- **Relative Effort**: Eingaben sind HF (persönliche Zonen) oder Perceived Exertion (PE). Dauer und Intensität zählen beide. Die Wochengrafik zeigt die kumulierte Woche und einen **Wochenbereich aus dem 3-Wochen-Schnitt** (unter / im / über dem Bereich). Eine Formel veröffentlicht Strava **nicht**.
- **Perceived Exertion**: Skala 1–10 („Easy“ … „Max Effort“), pro Aktivität setzbar. Ersetzt die HF, wenn diese fehlt oder falsch ist.
- **Fitness & Freshness**: Impulse-Response-Modell (Banister 1975, Coggan). Fitness wächst und fällt langsam, Fatigue schnell, **Form = Fitness − Fatigue**. Eingabe ist die Trainingslast aus Leistung und/oder Relative Effort. **Ab 10 Fahrten mit beiden Werten** schätzt ein persönlicher Best-Fit die Last für Fahrten ohne Leistung. Angezeigt werden ein Zeitraum-Wähler, Werte per Tap auf einen Tag und das Fitness-Delta der letzten 7 Tage. Zeitkonstanten und Form-Schwellen veröffentlicht Strava nicht.
- **Strava-API**: `suffer_score` (= Relative Effort) ist teils in Aktivitäten enthalten. Wird übernommen, wenn vorhanden, sonst berechnet.

## 3. Entscheidungen (ADR-10 … ADR-13)

- **ADR-10 Relative Effort = Banister-TRIMP** aus Ø-HF (Streams wären API-intensiv): `RE = min × HRr × 0,64 × e^(1,92 × HRr)` mit `HRr = (HFø − HFruhe)/(HFmax − HFruhe)`. Ruhe- und Max-HF stehen im Profil (Standard 50/190, Max-HF bei Bedarf aus der Schwellen-HF). Größenordnung: 1 h locker ≈ 60, 1 h Schwelle ≈ 150, also Strava-ähnlich.
- **ADR-11 PE-Fallback** auf derselben Skala: PE 1–10 → `HRr = 0,40 + 0,055 × PE`, dann TRIMP. So sind HF- und PE-Werte vergleichbar. Priorität: manuelle PE (wenn „PE bevorzugen“) > Strava `suffer_score` > HF-TRIMP > PE > keiner.
- **ADR-12 Einheitliche Tageslast für Fitness & Freshness**: Leistung → TSS. Ohne Leistung und mit ≥ 10 Fahrten, die beides haben → `TSS ≈ k × RE` (Kleinste Quadrate durch den Ursprung). Sonst wie bisher (HF-TSS bzw. Dauer). Zeitkonstanten 42/7 Tage (Coggan-Standard), dokumentiert. Form-Zonen wie bisher (Überlastet / Produktiv / Ausgewogen / Frisch / Formverlust).
- **ADR-13 Winter Arc** = Saison von `arcStart` (Standard 1. November) bis `goalDate` (Standard 21. März). Ziel-Fitness `targetCTL` ist im Profil einstellbar (Standard: CTL bei Arc-Start × 1,35, mindestens +15). 10 Level von „Erster Frost“ bis „Frühlingsform“. Level = Anteil des Wegs von Start-CTL zu Ziel-CTL, wobei nie wieder abgestiegen wird (bestes erreichtes Level). Dazu kommen eine **Kurslinie** (linear Start → Ziel), der Status „vor / auf / hinter Kurs“ (±3 CTL) und eine **Serie** (Wochen in Folge mit ≥ 80 % des Wochenbudgets). Alles lokal, ohne Backend.

## 4. Datenmodell (additiv, migrationssicher)

- `AthleteProfile`: `restingHeartRate`, `maxHeartRate`, `arcStart`, `targetCTL`. **Eigenes `init(from:)` mit `decodeIfPresent`**, damit bestehende Profile beim Update nicht verloren gehen (Befund aus dem Plan-Review).
- `RideSummary` / `StoredRide`: `perceivedExertion: Int?`, `preferPerceivedExertion: Bool`, `stravaRelativeEffort: Double?`. Optionale SwiftData-Attribute → leichte Migration.

## 5. Slices (dünn, vertikal)

| Slice | Inhalt | Nachweis |
|---|---|---|
| S7 | Domain: `RelativeEffort` (TRIMP, PE, Quelle, Wochenbereich), Profil-Migration | Unit-Tests |
| S8 | Domain: `FitnessFreshness` (Tageslast inkl. RE→TSS-Fit, Serie, Zeitraum, 7-Tage-Delta) | Unit-Tests |
| S9 | Domain: `WinterArc` (Saison, Kurslinie, Level, Status, Serie) | Unit-Tests |
| S10 | UI Relative Effort: Fahrt-Zeile + Detail mit PE-Auswahl, Wochenkarte mit Bereich im Verlauf | Simulator + XCUITest |
| S11 | UI Fitness & Freshness: Screen aus der Form-Karte, Zeitraum, Tap-Werte, Delta | Simulator + XCUITest |
| S12 | UI Winter Arc: Karte auf Heute, Detail mit Level-Pfad, Profil-Einstellungen, Coach-Kontext | Simulator + XCUITest |

## 6. Risiken
- RE-Werte weichen von Strava ab (Formel nicht öffentlich). Das wird in der App so benannt („IndoorCoach-Schätzung“), und der Strava-Wert wird bevorzugt, wenn ihn die API liefert.
- Ø-HF statt Zonen-Zeit unterschätzt Intervall-Einheiten leicht. Streams sind Phase 2 (Backlog).
- Level dürfen nicht demotivieren, darum kein Abstieg. Der Kursstatus ist ehrlich, aber freundlich formuliert.
