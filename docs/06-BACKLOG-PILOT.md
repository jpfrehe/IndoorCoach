# Backlog bis zur Pilotphase (Test auf echten Endgeräten)

Stand 17.11.2026 (Abend): P0 bis auf Nutzer-Aufgaben (B07, B08 blockiert) erledigt; seither zusätzlich Leistung (docs/08) und Konstanz-Paket (docs/10). Aktueller Gesamtstand: [Status](04-STATUS.md).
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
| B08 | **Live-Test Strava-OAuth & Sync auf dem iPhone** (Callback `indoorcoach://`, Token-Refresh nach 6 h, 210-Tage-Sync) | Nutzer | – | ⏸ blockiert: Strava-API braucht seit 06/2026 ein Abo. Ersatz: B22 (MyWhoosh/FIT), live bestätigt. |
| B09 | **Live-Test Claude-Planung** (Key, Header/Beta, Fallback-Retry, Kosten pro Plan) | Nutzer | – | ✅ 17.11.2026: 14-Tage-Plan mit 8 Einheiten übernommen und in den Kalender eingetragen (Sonnet 5.5, 33 s). Kosten noch notieren. |
| B10 | **Robustheit Kalender & Demo**: extern gelöschter Kalendereintrag → `upsert` legt neu an; Demo-Daten verschwinden nach Strava-Verbindung, ohne echte Daten zu berühren | Agent | WP2 | Unit-Tests mit Fake-Kalender, Demo-Cleanup-Test |
| B21 | **MyWhoosh-Direktupload statt `.zwo`-Datei** über die inoffizielle API ([mywhoosh-community/mywhoosh-api](https://github.com/mywhoosh-community/mywhoosh-api), MIT): Login (`/http-service/api/login`) → Custom-Workout-Upload (`coaching…/client/custom-workout-upload`) → Termin im MyWhoosh-Kalender (`service14…/task/create`), Löschen/Aktualisieren. Passwort wird nicht gespeichert, nur die Sitzung im Schlüsselbund. `.zwo` bleibt als Rückfallweg. **Risiko:** inoffiziell, kann jederzeit brechen. Kein Token-Refresh dokumentiert, bei Ablauf neu anmelden. Nutzungsbedingungen von MyWhoosh vor dem Pilot prüfen. | Claude (Hauptsession) + Nutzer (Live-Test mit eigenem Konto) | – | Unit-Tests mit Mock-HTTP (Mapping, Login, Upload, 401/Ablauf, Löschen). Live-Upload durch den Nutzer bestätigt. |
| B22 | **Fahrten ohne Strava**: vergangene Fahrten aus MyWhoosh laden. Die Liste kommt über den undokumentierten Endpunkt `service14…/v2/rider/profile/activities` (von Community-Tools genutzt, Antwortformat wird tolerant gelesen), dazu je Fahrt die FIT-Datei mit eigenem FIT-Parser (Session-Werte, sonst NP aus den Sekundendaten). Rückfallweg: FIT-Dateien über die Dateien-App importieren (auch von Zwift/Wahoo). Doppelte Fahrten (gleicher Start ±5 min) werden übersprungen. Demo-Modus endet mit dem ersten Import. | Claude (Hauptsession) + Nutzer (Live-Test) | – | 14 Unit-Tests (FIT-Parser, Listenformate, Token nur an MyWhoosh-Hosts, Import, Dubletten, FIT-Import, Löschen). **Live-Test offen:** Feldnamen der echten Antwort stehen nach dem ersten Abruf im Diagnose-Export (nur Namen, keine Werte). |
| B11 | **SwiftData-Migrationstest**: Store mit altem Schema (ohne RE-Felder) öffnen → Daten bleiben | Agent | WP2 | Test legt alten Store an und öffnet ihn mit dem aktuellen Schema |

## P1 – im Pilot sehr hilfreich

| ID | Aufgabe | Wer | Paket |
|---|---|---|---|
| B12 | Pilot-Testplan [`docs/07-PILOT-TESTPLAN.md`](07-PILOT-TESTPLAN.md) (Gerätematrix, Szenarien, Feedback-Fragen) | Agent | WP4 |
| B13 | 7 offene Kontrast-Knoten auf 375 pt mit dem Accessibility Inspector auf echtem SE/mini prüfen | Nutzer | – |
| B14 | VoiceOver-Durchlauf der 5 Threads auf dem Gerät | Nutzer | – |
| B15 | Performance im Release-Build auf dem Gerät (Kaltstart, Scrollen im Verlauf mit 2 Jahren Daten) | Nutzer | – |

## P2 – nach dem Pilot

| ID | Aufgabe |
|---|---|
| B16 | ✅ **ohne Strava gelöst** über Sekundendaten aus Brücke/FIT ([Paket](15-PAKET-SEKUNDENDATEN-AUSWERTUNG.md)): Zeit in Zonen, Relative Effort aus Pulssekunden, Soll/Ist je Intervall. Offen bleibt nur der Strava-Weg selbst. Ursprünglich: Strava-Streams → Relative Effort aus HF-Zeit in Zonen, echte NP, Soll/Ist je Intervall. **Ergänzung (Leistung):** Streams würden auch die volle Leistungskurve für Strava-Fahrten liefern (Sekundenleistung statt Mindestwerte aus Ø-Leistung und `max_watts`). |
| B17 | Apple Health als zweite Datenquelle (MyWhoosh/Wahoo schreiben dorthin) |
| B18 | intervals.icu-Brücke für automatischen MyWhoosh-Upload |
| B23 | ✅ **gelöst über die IndoorCoach Brücke** ([Konzept](14-SEKUNDENDATEN-MAC-BRUECKE.md)): Die Mac-App liest die FIT-Dateien lokal aus dem MyWhoosh-Ordner und bietet sie im WLAN an, das iPhone ergänzt damit die Fahrten. Der Cloud-Download bleibt gesperrt. Ursprünglich: **MyWhoosh-FIT-Datei (S3 verweigert):** Der Download der FIT-Datei über MyWhoosh scheitert mit „Access Denied“ (S3). Deshalb haben MyWhoosh-Fahrten aus der Liste keine Sekundendaten und liefern der Leistungskurve nur Mindestwerte; die volle Kurve gibt es nur über den FIT-Import aus der Dateien-App. Zu klären: anderer Endpunkt/Signatur oder Export-Weg. |
| B24 | Brücke Phase 2: iCloud-Drive-Container als zweiter Transport (Abgleich auch außerhalb des Heim-WLANs), Verteilung der Mac-App (Mac App Store/TestFlight für macOS, eigener Release-Job) |
| B25 | ◐ **live bestätigt 19.11.2026:** signierter Build, Freigabe-Dialog des MyWhoosh-Containers, Kopplung im WLAN, echte MyWhoosh-FIT-Dateien (6 Dateien, alle mit Sekundendaten) und Abruf der heutigen Einheit auf dem iPhone. Offen: Anmeldeobjekt nach Neustart, Sonderfälle ([Gerätetest](16-GERAETETEST.md) Teil 4). |
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

## Abnahme (Prüfung durch die Hauptsession, 17.11.2026)

Vorgehen je Paket: Bericht gelesen, Diff der riskanten Stellen gelesen (AppModel, Services, Profil), Branch zusammengeführt, `swift test` und Build selbst ausgeführt, UI-Tests im Simulator selbst gefahren (die Agenten durften den Simulator nicht nutzen).

| Paket | Ergebnis | Erfüllt | Nacharbeit durch mich |
|---|---|---|---|
| WP1 Release & Compliance (B02, B03, B06) | ✅ angenommen | Privacy-Manifest im Bundle, „Alle Daten löschen“ mit Tests, „Powered by Strava“ (Kontrast ≥ 4,5:1), Archiv- und Build-Nummer-Skripte, Release-Build grün | Konflikt mit WP2 im Kalenderdienst gelöst (Löschfunktion ins Backend-Protokoll verschoben, Fake ergänzt). „Alle Daten löschen“ meldet jetzt auch von MyWhoosh ab. |
| WP2 Robustheit (B04, B10, B11) | ✅ angenommen | Rate-Limit/5xx mit Tests, Kalender heilt sich selbst (Fake-Backend), Demo-Bereinigung inkl. zweier gefundener Lücken, echter Migrationstest | Migrationstest war im parallelen Gesamtlauf instabil (Spaltenprüfung während WAL). Plausibilitätsprüfung entschärft, Kernaussage bleibt. |
| WP3 Onboarding (B01) | ✅ angenommen | 3 Schritte, überspringbar, bestehende Nutzer sehen es nicht, Unit-Tests der Entscheidungslogik, UI-Tests test15/test16 | Onboarding-Flag in die Löschliste aufgenommen (Hinweis aus WP1). Previews setzen das Flag. |
| WP4 Diagnose & Testplan (B05, B12) | ✅ angenommen mit Hinweis | Redigierter Diagnose-Export (Tests gegen Keys/Tokens/GPS), Feedback-Link, Pilot-Testplan | Konflikte mit WP2 gelöst. **Hinweis:** Die neuen Log-Zeilen im Kalenderdienst gingen beim Konflikt zugunsten von WP2s Umbau verloren. Die Fehler-Logs im AppModel blieben erhalten. UI-Test für das Teilen-Sheet fehlt (Accessibility-IDs vorhanden). `AppConfig.feedbackEmail` ist leer und vor dem Pilot zu setzen. |
| B21 MyWhoosh-Direktupload | ✅ umgesetzt (Hauptsession), **live bestätigt 17.11.2026** | Login, Upload, Ersetzen, Löschen, MyWhoosh-Kalender, Auto-Senden, 9 Unit-Tests, UI-Tests test17/test18 mit Debug-Stub | **Nicht live getestet**, weil kein MyWhoosh-Konto vorlag: Antwortformate und Platform-Wert stammen aus der Community-Doku. |

**Integrierter Lauf nach allen Merges** (113 Unit-Tests grün; UI-Tests 01, 02, 05, 06, 14–18 im Simulator, iPhone 18 Pro):

- Die vier Fehlschläge im ersten Lauf waren keine App-Fehler, sondern Testartefakte. Alle sind behoben:
  - Die Trainingstage liegen jetzt unter dem Winter-Arc-Abschnitt und müssen gescrollt werden.
  - Der Erfolgsbanner (3 s) war schon weg, als der Test danach suchte.
  - Der FTP-Wert im Onboarding steht im Stepper-Label.
  - Das Scrollen hat am Secret-Feld vorbeigeschossen.
- Offen bleibt: Das Audit meldet im Einheit-Detail nach dem MyWhoosh-Senden 8 bis 12 Mal „Contrast failed“. Auf demselben Screen ohne vorheriges Senden (test01) heißt es nur „nearly passed“. Der Screenshot zeigt keinen Überlagerer, die Farben sind identisch. Das wird bei B13 mit dem Accessibility Inspector auf dem Gerät mitgeprüft.

