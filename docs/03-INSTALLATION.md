# Installation & Einrichtung

Ziel: IndoorCoach ohne App Store auf deinem iPhone, verbunden mit Strava und Claude.
Zeitbedarf: ca. 20 Minuten beim ersten Mal.

## 1. App aufs iPhone bringen (Xcode)

1. `IndoorCoach.xcodeproj` in Xcode öffnen.
2. Links das Projekt **IndoorCoach** → Target **IndoorCoach** → Tab **Signing & Capabilities**:
   - **Team**: deine Apple-ID wählen (Xcode → Settings → Accounts → „+“, falls noch nicht angemeldet).
     Ein kostenloser Account reicht.
   - Falls Xcode meldet, dass die Bundle-ID vergeben ist: `app.indoorcoach.personal` in z. B.
     `app.indoorcoach.<deinname>` ändern.
3. iPhone per Kabel anschließen (beim ersten Mal „Diesem Computer vertrauen“) und oben als Ziel auswählen.
4. Auf dem iPhone den **Entwicklermodus** aktivieren: Einstellungen → Datenschutz & Sicherheit → Entwicklermodus → an (Neustart).
5. In Xcode **▶ Run** (⌘R).
6. Beim ersten Start: Einstellungen → Allgemein → VPN & Geräteverwaltung → dein Entwicklerzertifikat → **Vertrauen**.

> **Hinweis kostenloser Account:** Das Profil gilt 7 Tage. Danach startet die App nicht mehr –
> einfach erneut aus Xcode starten (Daten bleiben erhalten). Mit dem Apple Developer Program (99 €/Jahr) gilt es 1 Jahr.

## 2. Strava verbinden

1. Auf <https://www.strava.com/settings/api> eine API-Anwendung anlegen:
   - **Application Name**: z. B. „IndoorCoach privat“
   - **Category**: Training
   - **Website**: beliebig, z. B. `http://localhost`
   - **Authorization Callback Domain**: `localhost`
2. **Client ID** und **Client Secret** notieren.
3. In der App: **Profil → Strava** → Client-ID und Client-Secret eintragen → **Mit Strava verbinden**.
4. Im Strava-Login „Alle Aktivitäten anzeigen“ (inkl. privater) erlauben.
5. Die App lädt automatisch die letzten 210 Tage. Danach synchronisiert sie bei jedem App-Start inkrementell
   (oder per Pull-to-Refresh).

> Seit Juni 2026 setzt Strava für neue Standard-API-Apps ein Strava-Abo voraus. Ohne Abo: Fahrten über MyWhoosh oder FIT-Dateien (§5).

## 3. Claude verbinden

1. Auf <https://console.anthropic.com/settings/keys> einen API-Key erzeugen
   (Billing in der Console einrichten; ein claude.ai-Abo enthält keinen API-Zugang).
2. In der App: **Profil → Coach · Claude** → Key einfügen → **API-Key speichern**.
3. Modell wählen: *Opus 5.5* (beste Qualität, ca. 0,10 $ pro Plan) oder *Sonnet 5.5* (etwa halb so teuer).

## 4. Profil ausfüllen

FTP, Gewicht, Ziel (+ Datum), Trainingstage, Wochenbudget, maximale Einheitendauer und Startzeit.
Die Startzeit wird für Kalendereinträge verwendet.

## 5. MyWhoosh verbinden (Upload und Fahrten)

1. **Profil → MyWhoosh** → E-Mail und Passwort → **Bei MyWhoosh anmelden**.
   - Gespeichert wird nur die Sitzung im Schlüsselbund, nie das Passwort.
   - Wer sich bei MyWhoosh mit Google oder Apple anmeldet, legt dort zuerst ein Passwort fest.
2. Nach der Anmeldung lädt die App deine Fahrten der letzten 210 Tage aus MyWhoosh. Danach holt sie bei jedem Start neue nach; „Fahrten aus MyWhoosh laden“ lädt das ganze Fenster neu.
   - MyWhoosh liefert Ø-Leistung, Dauer, Distanz und Ø-Puls, aber keine Sekundendaten.
3. **Volle Leistungskurve:** **FIT-Dateien importieren …** (Dateien-App, auch von Zwift oder Wahoo). Doppelte Fahrten werden übersprungen.

> Die MyWhoosh-Schnittstelle ist inoffiziell (Community-Dokumentation) und kann sich jederzeit ändern.
> Bitte die Nutzungsbedingungen von MyWhoosh beachten.

## 6. Planen → Kalender → MyWhoosh

1. **Plan** → **✨ Planen** → Zeitraum (7/14 Tage), optional Wunsch eingeben → **Mit Claude planen**.
2. Vorschlag prüfen → **Übernehmen & in Kalender** (legt den Kalender „Indoor Training“ an).
   Mit MyWhoosh-Anmeldung und „Neue Pläne automatisch senden“ landen die Einheiten direkt in MyWhoosh
   (Custom Workouts + MyWhoosh-Kalender).
3. Einzelne Einheit: öffnen → **An MyWhoosh senden** bzw. **In MyWhoosh aktualisieren**.
4. **Rückfallweg ohne MyWhoosh-Anmeldung:** **Alternativ: .zwo-Datei** → per AirDrop an den Mac →
   <https://workout.mywhoosh.com> → **Create New / Upload** → **Export to MyWhoosh**.
5. In MyWhoosh: Workouts → **My Workouts** bzw. Kalender → Einheit starten (ERG-Modus auf der Rolle).

## TestFlight (Pilot)

Voraussetzung: Apple Developer Program, App-Eintrag in App Store Connect mit der Bundle-ID
`app.indoorcoach.personal` (oder deiner geänderten), in Xcode mit diesem Team angemeldet.

```bash
scripts/bump-build.sh                                   # Build-Nummer = Zeitstempel (z. B. 202611171045)
scripts/bump-build.sh 42                                # oder feste Build-Nummer
DEVELOPMENT_TEAM=ABCDE12345 scripts/archive.sh          # Archiv + Export nach build/export/
DEVELOPMENT_TEAM=ABCDE12345 UPLOAD=1 scripts/archive.sh # Archiv + direkter Upload zu App Store Connect
```

- **`scripts/bump-build.sh [nummer]`** setzt `CURRENT_PROJECT_VERSION` (CFBundleVersion) in allen
  Konfigurationen von `IndoorCoach.xcodeproj`. Jeder Upload derselben Version (`MARKETING_VERSION`, aktuell 0.1)
  braucht eine höhere Build-Nummer. Die Änderung danach committen.
- **`scripts/archive.sh`** baut mit `xcodebuild archive` ein Release-Archiv (`build/IndoorCoach.xcarchive`)
  und exportiert es mit `xcodebuild -exportArchive` und `scripts/ExportOptions.plist`
  (Methode `app-store-connect`, automatische Signierung). Die Team-ID kommt aus der Umgebungsvariable
  `DEVELOPMENT_TEAM` (developer.apple.com → Account → Membership). Fehlt sie, bricht das Skript mit einer
  Meldung ab. Ohne `UPLOAD=1` liegt die `.ipa` in `build/export/` und wird mit Transporter oder dem
  Xcode Organizer hochgeladen.
- Nach der Verarbeitung (ca. 10–30 min) erscheint der Build in App Store Connect unter **TestFlight**.
  Dort die Exportkonformität beantworten (die App nutzt nur HTTPS/Standardverschlüsselung) und die
  Pilot-Tester einladen.

**Datenschutz:** `App/PrivacyInfo.xcprivacy` wird automatisch ins App-Bundle übernommen. Es erklärt kein
Tracking, keine Tracking-Domains und keine erhobenen Datentypen: Alle Daten bleiben auf dem iPhone.
Netzwerkzugriffe gibt es nur zu Diensten, die der Nutzer selbst verbindet:
- an Strava mit seiner eigenen API-App;
- an Anthropic mit seinem eigenen API-Key;
- an MyWhoosh mit seinem eigenen Konto (Upload, Kalender, Fahrtenliste).

Der Entwickler erhält keine Daten. Der Wochenrückblick nutzt nur lokale Mitteilungen (opt-in im Profil). Als Grund-pflichtige API wird nur
`UserDefaults` (CA92.1, nur app-eigene Daten) genutzt. Für die App-Datenschutzangaben in App Store Connect
gilt daher „Keine Daten erfasst“. Unter **Profil → Daten → Alle Daten löschen** entfernt der Nutzer alles
Lokale: Fahrten, Einheiten, Kalender „Indoor Training“, Schlüsselbund und Einstellungen.

## Entwicklung

```bash
cd IndoorCoachKit
swift test                                   # Unit-Tests der Kernlogik (macOS, kein Simulator nötig)
swift run SnapshotTool ../snapshots          # rendert die Haupt-Screens als PNG
```

Für Live-Vorschau/Simulator in Xcode die iOS-Simulator-Laufzeit installieren
(Xcode → Settings → Components → iOS 27.2 Simulator, ca. 8 GB).
