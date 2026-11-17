# Backlog bis zur Pilotphase (Test auf echten Endgeräten)

Stand 17.11.2026, nach UX-Audit, Farbsystem und Winter-Arc-Features.
**Pilot-Definition**: 3–5 Fahrer installieren die App über TestFlight auf ihrem iPhone, verbinden Strava, planen mit Claude und fahren vier Wochen damit. Fehler und Feedback kommen ohne Entwickler-Mac zurück.

Legende: **Agent** = im Repo umsetzbar und an Subagenten vergeben · **Nutzer** = braucht deinen Account, deine Zugangsdaten oder ein echtes Gerät.

## P0 – ohne das kein Pilot

| ID | Aufgabe | Wer | Paket | Abnahme |
|---|---|---|---|---|
| B01 | **Onboarding beim ersten Start**: FTP, Trainingstage, Wochenbudget, dann „Mit Strava verbinden“ oder „Erst mit Demo-Daten ansehen“ | Agent | WP3 | UI-Test: frische Installation → 3 Schritte → Heute. Kein Onboarding beim zweiten Start. |
| B02 | **Privacy Manifest** (`PrivacyInfo.xcprivacy`: UserDefaults, Kalender, keine Tracking-Domains) und **„Alle Daten löschen“** (SwiftData, Keychain, UserDefaults, eigener Kalender) | Agent | WP1 | Manifest im App-Bundle. Unit-Test: Löschen leert Store, Keychain und Defaults. |
| B03 | **Strava-Markenrichtlinien**: „Powered by Strava“ an Strava-Daten, „Auf Strava ansehen“-Link in Strava-Orange, kein Strava-Logo als App-Icon | Agent | WP1 | Sichtprüfung Verlauf + Fahrt-Detail. Text nach den Strava Brand Guidelines. |
| B04 | **Strava-Rate-Limits**: 429 / `X-RateLimit-*` auswerten, Backoff, verständliche Meldung, kein Datenverlust beim Abbruch | Agent | WP2 | Unit-Tests mit Mock-Transport: 429 → Meldung, Retry-After respektiert. |
| B05 | **Diagnose & Feedback**: OSLog-Logger in Services (ohne Tokens/Keys), „Diagnose exportieren“ (letzte 24 h als Textdatei, redigiert) und „Feedback senden“ im Profil | Agent | WP4 | Unit-Test: Export enthält keine `sk-ant-`/Token-Muster. UI-Test: Share-Sheet öffnet. |
| B06 | **Release-Build & Archiv**: Release-Konfiguration prüfen, `scripts/archive.sh` (xcodebuild archive + exportOptions für TestFlight), Versions-/Build-Nummer-Skript | Agent | WP1 | `xcodebuild -configuration Release build` grün. Skript dokumentiert. Signieren ist ausgenommen (Nutzer). |
| B07 | **Apple Developer Program + TestFlight** einrichten (Team-ID, Bundle-ID, App Store Connect-Eintrag, Pilot-Tester einladen) | Nutzer | – | Erster TestFlight-Build installierbar |
| B08 | **Live-Test Strava-OAuth & Sync auf dem iPhone** (Callback `indoorcoach://`, Token-Refresh nach 6 h, 210-Tage-Sync) | Nutzer | – | Checkliste in `docs/07-PILOT-TESTPLAN.md` abgehakt |
| B09 | **Live-Test Claude-Planung** (Key, Header/Beta, Fallback-Retry, Kosten pro Plan) | Nutzer | – | Ein echter Plan übernommen. Kosten notiert. |
| B10 | **Robustheit Kalender & Demo**: extern gelöschter Kalendereintrag → `upsert` legt neu an; Demo-Daten verschwinden nach Strava-Verbindung, ohne echte Daten zu berühren | Agent | WP2 | Unit-Tests mit Fake-Kalender, Demo-Cleanup-Test |
| B11 | **SwiftData-Migrationstest**: Store mit altem Schema (ohne RE-Felder) öffnen → Daten bleiben | Agent | WP2 | Test legt alten Store an und öffnet ihn mit dem aktuellen Schema |

## P1 – im Pilot sehr hilfreich

| ID | Aufgabe | Wer | Paket |
|---|---|---|---|
| B12 | Pilot-Testplan `docs/07-PILOT-TESTPLAN.md` (Gerätematrix, Szenarien, Feedback-Fragen) | Agent | WP4 |
| B13 | 7 offene Kontrast-Knoten auf 375 pt mit dem Accessibility Inspector auf echtem SE/mini prüfen | Nutzer | – |
| B14 | VoiceOver-Durchlauf der 5 Threads auf dem Gerät | Nutzer | – |
| B15 | Performance im Release-Build auf dem Gerät (Kaltstart, Scrollen im Verlauf mit 2 Jahren Daten) | Nutzer | – |

## P2 – nach dem Pilot

| ID | Aufgabe |
|---|---|
| B16 | Strava-Streams → Relative Effort aus HF-Zeit in Zonen, echte NP, Soll/Ist je Intervall |
| B17 | Apple Health als zweite Datenquelle (MyWhoosh/Wahoo schreiben dorthin) |
| B18 | intervals.icu-Brücke für automatischen MyWhoosh-Upload |
| B19 | Widget „Heutige Einheit“ + Winter-Arc-Level |
| B20 | Wöchentlicher Auto-Plan (Docker-Backend + Push) |

## Vergabe an Subagenten

Vier Arbeitspakete, jedes in einem eigenen Git-Worktree. Ich prüfe jedes Ergebnis (Diff lesen, Tests/Build selbst ausführen, Abnahmekriterien) und führe es erst dann zusammen.

| Paket | Inhalt | Berührte Bereiche |
|---|---|---|
| WP1 Release & Compliance | B02, B03, B06 | Config, Projekt, Profil, Verlauf |
| WP2 Robustheit | B04, B10, B11 | StravaClient, CalendarService, AppModel, Tests |
| WP3 Onboarding | B01 | RootView, neue Onboarding-Views, AppModel-Flag, UI-Test |
| WP4 Diagnose & Testplan | B05, B12 | Logger, Profil, docs |

Ergebnis der Prüfung: siehe Abschnitt „Abnahme“ unten (wird nach der Umsetzung ergänzt).
