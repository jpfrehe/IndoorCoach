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
5. Die App lädt automatisch die letzten 120 Tage. Danach synchronisiert sie bei jedem App-Start inkrementell
   (oder per Pull-to-Refresh).

> Seit Juni 2026 setzt Strava für neue Standard-API-Apps ein Strava-Abo voraus.

## 3. Claude verbinden

1. Auf <https://console.anthropic.com/settings/keys> einen API-Key erzeugen
   (Billing in der Console einrichten; ein claude.ai-Abo enthält keinen API-Zugang).
2. In der App: **Profil → Coach · Claude** → Key einfügen → **API-Key speichern**.
3. Modell wählen: *Opus 5.5* (beste Qualität, ca. 0,10 $ pro Plan) oder *Sonnet 5.5* (etwa halb so teuer).

## 4. Profil ausfüllen

FTP, Gewicht, Ziel (+ Datum), Trainingstage, Wochenbudget, maximale Einheitendauer und Startzeit.
Die Startzeit wird für Kalendereinträge verwendet.

## 5. Planen → Kalender → MyWhoosh

1. **Plan** → **✨ Planen** → Zeitraum (7/14 Tage), optional Wunsch eingeben → **Mit Claude planen**.
2. Vorschlag prüfen → **Übernehmen & in Kalender** (legt den Kalender „Indoor Training“ an).
3. Einheit öffnen → **Für MyWhoosh exportieren (.zwo)** → per AirDrop an den Mac.
4. Am Mac <https://workout.mywhoosh.com> öffnen → mit MyWhoosh-Account anmelden →
   **Create New / Upload** → `.zwo`-Datei wählen → **Export to MyWhoosh**.
5. In MyWhoosh am Mac: Workouts → **My Workouts** → Einheit starten (ERG-Modus auf der Wahoo).

## Entwicklung

```bash
cd IndoorCoachKit
swift test                                   # 37 Unit-Tests der Kernlogik (macOS, kein Simulator nötig)
swift run SnapshotTool ../snapshots          # rendert die Haupt-Screens als PNG
```

Für Live-Vorschau/Simulator in Xcode die iOS-Simulator-Laufzeit installieren
(Xcode → Settings → Components → iOS 27.2 Simulator, ca. 8 GB).
