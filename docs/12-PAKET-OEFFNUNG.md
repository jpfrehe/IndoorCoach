# Paket „Öffnung“: IndoorCoach für eine breitere Zielgruppe (ECC, 4 parallele Arbeitspakete)

Stand 18.11.2026 · Größe: **groß**, deshalb in 4 unabhängige Pakete geteilt · Gate 1: vom Nutzer mit dem Auftrag freigegeben („Erweitere die App … nach dem ECC-Prozess, implementiere verteilt mit Sonnet-Subagenten, teste die UX ausführlich“).

## Ziele

1. Bessere User Journey beim ersten Start.
2. Zugangsdaten (MyWhoosh-Login, Claude-API-Key) schon im Onboarding hinterlegen, nicht nur im Profil.
3. Anleitung und Einführung in die App-Funktionen mit ansprechenden Animationen.
4. Feedback und Wünsche in der App erfassen und direkt als GitHub-Issue anlegen.
5. CI/CD-Pipeline in GitHub Actions für die Auslieferung in den App Store vorbereiten.

**Nicht-Ziele:**
- Kein eigenes Backend, kein Nutzerkonto bei IndoorCoach.
- Keine Secrets in der App oder im Repository (auch kein GitHub-Token).
- Kein eigener Strava-Zugang für alle: Strava bleibt der Weg für Fortgeschrittene (eigene API-App, seit Juni 2026 mit Abo).
- Keine echte App-Store-Einreichung in diesem Paket (braucht Apple-Konto, Secrets und die Prüfung durch Apple).

## 1. UX-Bewertung heute (Persona: Hobby-Rennradfahrerin, fährt MyWhoosh, kein Entwickler-Hintergrund)

| # | Befund | Folge |
|---|---|---|
| U1 | Das Onboarding hat 3 Schritte (Willkommen, Profil, Daten), endet aber mit „Mit Strava verbinden“. Strava braucht eine eigene API-App plus Abo – für neue Nutzer die schwerste Hürde. | MyWhoosh wird der Hauptweg, Strava ein Link „für Fortgeschrittene“. |
| U2 | MyWhoosh-Login und Claude-Key liegen nur weit unten im Profil-Formular. Nach dem Onboarding sieht man Demo-Daten und weiß nicht, was fehlt. | Eigene Onboarding-Schritte „Trainings-App“ und „Coach“, jeweils überspringbar, mit Status am Ende. |
| U3 | Den Claude-Key muss man abtippen oder einfügen, ohne Rückmeldung, ob er gilt. Fehler zeigen sich erst beim ersten Planen. | Einfügen per `PasteButton` (ohne Einfügen-Abfrage), Prüfen über `GET /v1/models` (kostenlos), klare Fehlertexte. |
| U4 | Die App erklärt ihre Funktionen nirgends. Winter Arc, Konstanz-Serie, Leistungskurve erschließen sich erst beim Herumtippen. | Animierte Feature-Tour (nach dem Onboarding und jederzeit unter Hilfe), dazu wenige kontextuelle Tipps (TipKit). |
| U5 | Feedback geht nur über einen nackten GitHub-Link („Feedback: “). Nutzer wissen nicht, was sie schreiben sollen, und die Issues haben keine Struktur. | Feedback-Formular in der App (Fehler, Wunsch, Lob/Frage) → vorausgefülltes GitHub-Issue-Formular mit Labels. |
| U6 | Release läuft nur lokal über `scripts/archive.sh` mit Xcode-Anmeldung. | GitHub Actions: CI für jeden Push, Release-Workflow für TestFlight/App Store mit App-Store-Connect-API-Key. |

## 2. Entscheidungen

- **Feedback ohne Token:** Die App öffnet ein vorausgefülltes GitHub-**Issue-Formular** (`issues/new?template=…&title=…&<feld-id>=…`). Labels kommen aus dem Template, weil URL-Parameter für Labels nur mit Schreibrechten wirken. Der Nutzer braucht ein kostenloses GitHub-Konto und tippt auf GitHub „Create“. Ohne Konto: „Text kopieren“ (und E-Mail, sobald `AppConfig.feedbackEmail` gesetzt ist).
  - Verworfen: GitHub-Token in der App (wäre ein öffentliches Secret) und ein Proxy (braucht ein Backend). Ein späterer Ausbau wäre eine GitHub App hinter einem kleinen Worker.
- **Claude-Key prüfen:** `GET https://api.anthropic.com/v1/models?limit=1` mit `x-api-key` und `anthropic-version`. Das kostet keine Tokens. 200 = gültig, 401 = falscher Key, 403 = keine Berechtigung, Netzfehler = „Konnte nicht prüfen – trotzdem speichern?“.
- **Animationen:** reine SwiftUI-Animationen (`PhaseAnimator`, `KeyframeAnimator`, `trim`, `symbolEffect`), keine Lottie-Abhängigkeit. Mit „Bewegung reduzieren“ zeigen alle Illustrationen ihren Endzustand ohne Bewegung.
- **Kontextuelle Tipps:** Apples TipKit, höchstens 4 Tipps, erst nach dem Onboarding. In UI-Tests ausgeschaltet, außer mit `-uiTips YES`.
- **CI/CD:** keine fastlane-Abhängigkeit. `xcodebuild archive/-exportArchive` mit automatischer Signierung über den App-Store-Connect-API-Key (`-authenticationKeyPath/-ID/-IssuerID`), Upload über `destination = upload`. Team-ID und Bundle-ID kommen aus Secrets bzw. Variablen. Das uncommittete `DEVELOPMENT_TEAM` in `project.pbxproj` bleibt lokal.

## 3. Arbeitspakete

### O1 · Onboarding-Journey & Verbindungen

- **Schritte (neu, 5):**
  1. **Willkommen:** animiertes Hero-Motiv, 3 Nutzenversprechen, „Los geht’s“.
  2. **Dein Training:** FTP („Weiß ich nicht“ setzt 2,5 W/kg × Gewicht), Gewicht, Trainingstage, Wochenbudget.
  3. **Trainings-App:** MyWhoosh-Anmeldung (E-Mail, Passwort „wird nicht gespeichert“) mit Ladezustand und Erfolg („Verbunden · 23 Fahrten geladen“). Darunter „Später“ und der Link „Strava oder FIT-Dateien? Im Profil einrichten“ (beendet mit `.strava`).
  4. **Coach:** kurze 3-Schritt-Anleitung zum Key (console.anthropic.com → API-Keys → Key erstellen), `PasteButton` und `SecureField`, „Prüfen & speichern“, Kostenhinweis (ca. 0,10 $ pro Plan), „Ohne Claude weiter“ (Demo-Plan).
  5. **Fertig:** Checkliste mit Status (Profil ✓, MyWhoosh ✓/–, Coach ✓/–), primär „Kurze Tour ansehen“, sekundär „Direkt starten“.
- **Fortschritt:** Der aktuelle Schritt wird gespeichert (UserDefaults, Key in `AppModel.Keys.all`). Wer die App mitten im Onboarding schließt, landet wieder dort.
- **Bestehende Installationen** (Onboarding v1 abgeschlossen) sehen das neue Onboarding nicht.
- **Wiederverwendung:** Claude-Key- und MyWhoosh-Formular werden eigene Views (`UI/ConnectionForms.swift`) und ersetzen die Abschnitte im Profil, damit beide Orte gleich aussehen und sich gleich verhalten.
- **Ende des Onboardings:** neue Wahl `OnboardingChoice.tour` → RootView zeigt `FeatureTourView(context: .onboarding)` als Vollbild und landet danach auf „Heute“.
- **Debug-Hooks für UI-Tests:**
  - `-uiMyWhooshStubLogin YES`: nicht angemeldet, Login mit beliebigen Testdaten gelingt (Stub-Transport).
  - `-uiClaudeStub YES`: `/v1/models` antwortet 200 für Keys mit `sk-ant-test`, sonst 401.
- **Barrierefreiheit:** Fokus auf dem Titel bei jedem Schritt, 44-pt-Ziele, Dynamic Type bis AX5, VoiceOver-Labels für Status.
- **Tests:**
  - Unit: Key-Prüfung (200/401/403/Netzfehler, Request-Header), Schritt-Persistenz, „Weiß ich nicht“-FTP, Abschluss-Status.
  - UI: test15/16 anpassen, neu test29 (komplette Journey mit Stub-Login und Test-Key), test30 (falscher Key, Abbruch und Wiederaufnahme).

### O2 · Feature-Tour & Tipps

- **`FeatureTourView(context:onFinish:)`** (die API ist als Stub in `UI/FeatureTour/FeatureTourView.swift` festgelegt). 5 Seiten mit je einer animierten SwiftUI-Illustration, Titel und 1–2 Sätzen:
  1. **Claude plant deine Woche:** Wochenraster, Einheiten-Balken wachsen nacheinander ein.
  2. **Direkt in MyWhoosh:** Einheit fliegt in den MyWhoosh-Kalender, Häkchen.
  3. **Dein Winter Arc:** Level-Ring füllt sich, Schneeflocke wird zur Sonne, Level-Zahl springt hoch.
  4. **Konstanz statt Streaks:** 8 Wochen-Punkte füllen sich, ein Joker-Schild fängt eine verpasste Woche ab.
  5. **Fortschritt sehen:** Leistungskurve zeichnet sich (`trim`), PR-Abzeichen ploppt.
- **Bedienung:** Seitenwechsel per Wischen und Weiter-Button, eigene Seitenanzeige (`PageIndicator`), „Überspringen“ oben. Die Animation startet beim Erscheinen jeder Seite neu.
- **Bewegung reduzieren:** Endzustand ohne Bewegung. VoiceOver: jede Illustration hat ein Label, das beschreibt, was sie zeigt.
- **TipKit** (`UI/FeatureTour/AppTips.swift`): `Tips.configure` beim App-Start (`App/IndoorCoachApp.swift`). Tipps:
  - Plan: „Woche planen“;
  - Heute: Winter-Arc-Karte („Tippe für Level, Serie und Reise“);
  - Einheit: „An MyWhoosh senden“;
  - Verlauf: Leistung.
  - Erst nach abgeschlossenem Onboarding, in UI-Tests aus (außer `-uiTips YES`).
- **Tests:**
  - Unit: Seiteninhalt (Anzahl, Texte, Labels), Tipp-Regeln.
  - UI: test31 (Tour durchblättern, Überspringen, Abschluss; Tipp sichtbar mit `-uiTips YES`).

### O3 · Feedback als GitHub-Issue

- **Domain `FeedbackDraft`:**
  - Art: Fehler / Wunsch / Lob & Frage. Daraus folgen Template-Datei, Titel-Präfix und Feld-IDs.
  - URL-Bau für `issues/new?template=…`.
  - Schwärzen von E-Mail-Adressen und Tokens (wie im Diagnose-Log).
  - Kürzen, damit die URL unter 8 000 Zeichen bleibt.
  - Prüfung: Titel ≥ 5 Zeichen, Beschreibung ≥ 10 Zeichen.
- **Issue-Formulare** in `.github/ISSUE_TEMPLATE/`:
  - `bug_report.yml` (Label `bug`), `feature_request.yml` (`enhancement`), `feedback.yml` (`feedback`), `config.yml`.
  - Die Feld-IDs stimmen mit der App überein; ein Unit-Test liest die YAML-Dateien und prüft das.
- **`FeedbackView`:**
  - Art als Segment mit Symbol, Titel, Beschreibung mit Leitfragen je Art.
  - Schalter „App-Version und Gerät anhängen“, standardmäßig an; zeigt genau, was angehängt wird.
  - Hinweis „Öffentlich auf GitHub, braucht ein kostenloses GitHub-Konto“.
  - Buttons: „Weiter zu GitHub“ (primär), „Text kopieren“ und E-Mail, falls konfiguriert.
  - Danach eine Bestätigung mit dem nächsten Schritt („Auf GitHub ‚Create‘ tippen“).
  - Der Entwurf überlebt den Wechsel zu Safari.
  - Link „Bestehende Wünsche ansehen“.
- **`HelpFeedbackSection`:**
  - Zeile „Feedback & Wünsche“ → `FeedbackView`;
  - Zeile „App-Einführung ansehen“ → `FeatureTourView(context: .help)`;
  - Diagnose-Export bleibt.
- **Tests:**
  - Unit: URL, Feld-IDs, Schwärzung, Kürzung, Validierung, Template-Abgleich.
  - UI: test32 (Formular ausfüllen, Vorschau, „Weiter zu GitHub“ öffnet Safari mit der richtigen URL; „Text kopieren“).

### O4 · CI/CD für den App Store

- **`.github/workflows/ci.yml`** (Push auf `main`, Pull Requests):
  - `swift test` für IndoorCoachKit;
  - App-Build für den iOS-Simulator ohne Signierung;
  - Concurrency mit Abbruch älterer Läufe, SPM-Cache.
- **`.github/workflows/release.yml`** (Tag `v*` oder manuell, Environment `app-store`):
  - Xcode wählen;
  - API-Key aus Secret (Base64) in `$RUNNER_TEMP`;
  - Build-Nummer aus `github.run_number`, Version aus dem Tag;
  - `scripts/archive.sh` mit API-Key-Authentifizierung und Upload zu App Store Connect (TestFlight);
  - Archiv/dSYMs als Artefakt, Key-Datei immer löschen.
- **`scripts/archive.sh`:** optional App-Store-Connect-API-Key (`ASC_KEY_PATH`, `ASC_KEY_ID`, `ASC_ISSUER_ID`) und `BUNDLE_ID`. Lokal bleibt alles wie bisher.
- **App-Store-Bereitschaft:**
  - `ITSAppUsesNonExemptEncryption = NO` in `Config/Info.plist`;
  - Prüfung des Privacy-Manifests;
  - `.github/dependabot.yml` für Actions.
- **Doku:**
  - `docs/13-APP-STORE-RELEASE.md`: Secrets, Apple-Setup, Ablauf, Review-Risiken (inoffizielle MyWhoosh-API, Strava-Bedingungen, BYOK-Claude), Antworten für „App-Datenschutz“, Metadaten-Checkliste.
  - `docs/PRIVACY.md`: Datenschutzerklärung als Entwurf, für die Privacy-Policy-URL.
- **Prüfung:** YAML gültig (actionlint, falls verfügbar), die CI-Befehle laufen lokal, `archive.sh` ohne Team bricht verständlich ab.

## 4. Regeln für die parallele Umsetzung

Wie im [Konstanz-Paket](10-KONSTANZ-PAKET.md) §4: eigener Worktree und Branch je Paket (erst `git merge --ff-only main`), Sonnet-Subagent, TDD, neue Logik in eigenen Dateien, kein Simulator, `project.pbxproj` nicht anfassen. Die Hauptsession pflegt `docs/` (außer den in O4 genannten neuen Dateien).

**Exklusive Zuständigkeiten:**

| Paket | darf ändern |
|---|---|
| O1 | `UI/OnboardingView.swift`, neue `UI/ConnectionForms.swift`, `UI/ProfileView.swift` (Abschnitte Coach und MyWhoosh), `UI/RootView.swift`, `Store/AppModel*.swift`, `Services/ClaudeClient.swift`, `Tests/OnboardingTests.swift` und neue Tests, UI-Tests test15/16 und `ANCHOR-UITEST-O1` |
| O2 | `UI/FeatureTour/*` (Stub ersetzen), `App/IndoorCoachApp.swift`, je eine `.popoverTip`-Zeile in `PlanView`, `TodayView`/`WinterArcView`, `WorkoutDetailView`, `HistoryView`/`PerformanceView`, `ANCHOR-UITEST-O2` |
| O3 | `UI/HelpFeedbackSection.swift`, neue `UI/FeedbackView.swift`, neue `Domain/FeedbackDraft.swift`, `Store/AppConfig.swift`, `.github/ISSUE_TEMPLATE/*`, `ANCHOR-UITEST-O3` |
| O4 | `.github/workflows/*`, `.github/dependabot.yml`, `scripts/*`, `Config/Info.plist`, neue `docs/13-APP-STORE-RELEASE.md`, `docs/PRIVACY.md` |

**Fertig heißt:**
- `swift test` grün;
- `xcodebuild build-for-testing` (generic iOS Simulator, eigener DerivedData-Pfad) grün;
- Commits auf dem eigenen Branch;
- Bericht mit Abweichungen.

**Danach die Hauptsession:**
- Review je Paket, Merge, Verdrahtung Onboarding → Tour;
- alle UI-Tests im Simulator;
- ausführlicher UX-Test: Journey, Fehlerfälle, Unterbrechung, Dark Mode, AX-Schriftgrößen, iPhone SE, „Bewegung reduzieren“, VoiceOver-Audit;
- Commit.

## 5. Umsetzung und Prüfung (18.11.2026)

Vier Sonnet-Subagenten, parallel in eigenen Worktrees (vorher auf `main` vorgespult). Die Hauptsession hat jedes Paket geprüft, zusammengeführt und die UX im Simulator getestet.

| Paket | Ergebnis | Nacharbeit der Hauptsession |
|---|---|---|
| O1 Onboarding-Journey | ✅ 5 Schritte, Key-Prüfung über `/v1/models`, Schritt-Persistenz, gemeinsame Formulare in Onboarding und Profil | Untere Leiste weicht der Tastatur (sie verdeckte „Bei MyWhoosh anmelden“). Formulare schließen die Tastatur beim Absenden. Bei AX5 nur Chevron statt „Zu-rück“, Leisten bei AX2/AX3 gedeckelt, Nummern der Key-Anleitung skalieren mit. |
| O2 Feature-Tour & Tipps | ✅ 5 animierte Seiten, 4 TipKit-Tipps nach dem Onboarding | Die Animationen liefen im Paging-`TabView` nicht (`TimelineView` tickte nicht) → eigene Frame-Schleife. MyWhoosh-Illustration bekam eine Quelle (IndoorCoach) statt einer leeren linken Hälfte. |
| O3 Feedback als GitHub-Issue | ✅ Formular, Issue-Formulare mit Labels, Schwärzung, Kürzung unter 8 000 Zeichen | Tour aus „Hilfe“ öffnete nicht (Sheet an der `Section`) → Vollbild aus der Zeile. Nach der Rückkehr von GitHub scrollt die Ansicht zur Bestätigung. „Alle Daten löschen“ entfernt auch den Entwurf. |
| O4 CI/CD | ✅ `ci.yml`, `release.yml` (Runner `xcode-27`, Xcode 27.2), `archive.sh` mit API-Key, Release-Doku, Datenschutz-Entwurf | – |

**Ergebnis:**
- 365 Unit-Tests grün (322 vorher).
- UI-Tests test29–32 und die UX-Matrix (`testMatrixOpening`: L/Dark und AX5/Light, iPhone 18 Pro und iPhone SE) grün.
- Regression: test01–28 laufen durch.
  - Abweichende weiche Checks in test03 (`.zwo`-Menüpunkt) und test22 (Challenge-Highlight) gibt es genauso auf dem Stand vor dem Paket (Gegenprobe auf `874ccca`). Sie sind nicht durch das Paket entstanden.
  - Der bekannte Wackel-Check „Metrik zeigt TSS nach einem Tap“ bleibt.
- Sichtprüfung im Simulator: Onboarding in Hell/Dunkel, iPhone SE bei AX5, alle 5 Tour-Seiten mit Animation, Feedback mit Safari-Übergabe.
- iOS bietet nach dem MyWhoosh-Login „Passwort sichern?“ an. Das ist gewollt: Das Passwort landet im iOS-Passwörter-Schlüsselbund des Nutzers, nicht in der App.

**Offen:**
- Label `feedback` im GitHub-Repo anlegen, sonst bleibt Feedback ohne Label.
- Secrets und das Environment `app-store` für den Release-Workflow anlegen ([docs/13](13-APP-STORE-RELEASE.md)); der erste echte Release-Lauf ist ungetestet.
- `docs/PRIVACY.md` vor der Store-Einreichung rechtlich prüfen und den Verantwortlichen eintragen.
- Die Automatik-Kontrastmeldungen auf unbenannten Knoten wie im UX-Audit 2 auf dem Gerät prüfen (B13).
- test03 und test22 an die heutige Oberfläche anpassen (vorbestehend).
