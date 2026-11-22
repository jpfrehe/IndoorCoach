# Status & nächste Schritte

Stand: v0.2 (Pilot-Vorbereitung, „Die ganze Woche“) · 19.11.2026 · öffentlich auf [GitHub](https://github.com/jpfrehe/IndoorCoach)

## Was fertig ist

| Bereich | Status | Nachweis |
|---|---|---|
| S0–S6 MVP: Workouts, `.zwo`-Export, Verlauf/CTL, Strava-Sync, Claude-Coach, Kalender, Härtung | ✅ | [Konzept](02-KONZEPT.md), Unit-Tests |
| UX-Audit + Farbsystem „Sunset Jelly“ | ✅ | [Bericht](ux-audit-2026-11-17.md) |
| Winter Arc: Relative Effort, Fitness & Freshness, Level | ✅ | [Konzept](05-FEATURES-WINTER-ARC.md) |
| Pilot-Backlog WP1–WP4: Onboarding, Privacy-Manifest, „Alle Daten löschen“, Rate-Limits, Diagnose-Export | ✅ | [Backlog](06-BACKLOG-PILOT.md) |
| B21 MyWhoosh-Direktupload: Custom Workout + MyWhoosh-Kalender, Ersetzen/Löschen | ✅ **auf dem iPhone getestet** | Upload und Kalendereintrag mit echtem Konto bestätigt |
| B22 Fahrten ohne Strava: MyWhoosh-Fahrtenliste, FIT-Import | ✅ **auf dem iPhone getestet** | Import aus MyWhoosh mit echtem Konto bestätigt (3 Fahrten der letzten 210 Tage) |
| Leistung: Leistungskurve, Bestleistungen, eFTP, VO2max | ✅ | [Feature-Dokument](08-FEATURES-LEISTUNG.md) |
| Konstanz-Paket: Serie mit Joker, Plan-Treue, Wochenrückblick + Erinnerung, Saison-Challenges, Trophäen, aerobe Effizienz | ✅ | [Feature-Dokument](10-KONSTANZ-PAKET.md) |
| Winter-Paket 2: Ziel-Prognose mit Was-wäre-wenn, Trainingsverteilung, eFTP-Verlauf, Fähigkeitslevel, Ermüdungsresistenz, Vorjahres-Schatten, Saisonrückblick zum Teilen, Winter-Reise, Erinnerung vor Einheiten | ✅ | [Feature-Dokument](11-WINTER-PAKET-2.md) |
| Paket „Öffnung“: Onboarding mit MyWhoosh-Login und Claude-Key-Prüfung, animierte Feature-Tour + Tipps, Feedback als GitHub-Issue, CI/CD für den App Store | ✅ | [Paket-Dokument](12-PAKET-OEFFNUNG.md), [Release](13-APP-STORE-RELEASE.md) |
| Sekundendaten aus MyWhoosh: Mac-App „IndoorCoach Brücke“ (Menüleiste, liest den MyWhoosh-Ordner, WLAN-Übertragung mit TLS-PSK nach Kopplung per Code), iPhone-Kopplung und Auto-Abgleich, FIT-Import ergänzt vorhandene Fahrten, `.fit` öffnen | ✅ **live auf Mac + iPhone bestätigt (19.11.2026)**: Kopplung, echte MyWhoosh-FIT-Dateien, Sekundendaten der Einheit in der App | [Konzept & User Journey](14-SEKUNDENDATEN-MAC-BRUECKE.md), [Gerätetest](16-GERAETETEST.md); offen: Neustart/Anmeldeobjekt, Sonderfälle |
| Sekundendaten-Auswertung: Zeit in Leistungs- und Pulszonen je Fahrt, Relative Effort aus Pulssekunden, gemessene Trainingsverteilung, Soll/Ist je Intervall, „Einheit anpassen“ (kürzer/leichter, mit MyWhoosh und Kalender) | ✅ | [Paket-Dokument](15-PAKET-SEKUNDENDATEN-AUSWERTUNG.md), [Gerätetest](16-GERAETETEST.md) |
| UX-Audit 2 der erweiterten Version | ✅ 6 Befunde behoben | [Bericht](ux-audit-2026-11-17-b.md); formal offen: automatisch gemeldete Kontrast-Knoten (Gerät, B13) |
| Qualitätssprint (20.11.2026): CI-Release ohne Secrets grün, technische Schulden (AppModel aufgeteilt, Speicherfehler sichtbar, `Locale.de`), UX-Politur, UX-Audit 3 auf 402 pt + iPhone SE | ✅ 10 Befunde behoben | [Bericht](ux-audit-2026-11-20.md); formal offen wie in Audit 2: Kontrast-Knoten der Diagramme ohne Element |
| Profil neu geordnet (21.11.2026): Startseite „Ich · Verbindungen · App“, Hub „Dienste & Geräte“ mit Status je Dienst und Badge bei Problemen, einheitliche Detailseiten (Strava, MyWhoosh), Unterseiten für Coach, Erinnerungen, Hilfe, Daten; Pfad-Navigation statt Scroll-Sprung | ✅ | [Konzept](18-KONZEPT-PROFIL-VERBINDUNGEN.md); nächster Schritt: [Plan Plattform-Anbindungen](19-PLAN-PLATTFORM-ANBINDUNGEN.md) (Stufe 2 umgesetzt) |
| intervals.icu (21.11.2026): Pläne in den intervals.icu-Kalender (Weiterleitung an Zwift, Garmin, Wahoo, Rouvy), Fahrten samt FIT-Sekundendaten, OAuth mit PKCE ohne Client-Secret, Übergangsweg persönlicher API-Key | ✅ Simulator; Gerätetest mit echtem Konto offen | [Plan, Abschnitt 6](19-PLAN-PLATTFORM-ANBINDUNGEN.md), [Installation](03-INSTALLATION.md); OAuth-App freigegeben, Client-ID `1969` in `Config/Info.plist`; offen: erste Anmeldung mit echtem Konto |
| Einführung mit passenden Diensten (21.11.2026): 7 Schritte, Fragen in Alltagssprache, Empfehlung „Für dich passt“ (MyWhoosh, intervals.icu, Mac-Brücke, Apple Health, Brustgurt), Verbinden direkt im Intro, nichts Pflicht, Coach optional | ✅ Simulator (402 pt + SE) | [Konzept 20](20-KONZEPT-ONBOARDING-DIENSTE.md); offen: Bezugsweg Mac-Brücke (E1, `BridgeDownloadURL`), echte Anmeldungen am Gerät |
| Diagramme überarbeitet (21.11.2026): eigene Zonenpalette mit ≥ 3:1 Kontrast (hell/dunkel, farbfehlsicht-geprüft), Workout-Profil als scharfer Canvas-Renderer (abgerundete Blöcke, Lücken, Rampen als Trapeze, Mindestbreiten für 30/30 und Tabata), Detail mit Auswahl je Abschnitt, Analysen mit glatten monotonen Linien, Flächen, Halo am aktuellen Wert, Achsen rechts, Audio Graphs | ✅ Simulator (402 pt + SE, hell/dunkel, AX5) | [Konzept 21](21-KONZEPT-DIAGRAMME.md); offen: neue Screenshots in `docs/screenshots`, Auswahlgesten am Gerät prüfen |
| Begeisterung „Vom Frost zum Frühling“ (22.11.2026): Gipfelmoment nach der Fahrt (Level, Etappe, Bestleistung, eFTP, Woche, Comeback; Coach-Satz mit Quelle; Teilen 9:16 ohne Werte/Namen), Postkarten der Alpenüberquerung, Winterlicht seit der Sonnenwende, Willkommen zurück und „Dein Warum“ (nie an Claude) | ✅ Simulator (402 pt + SE, hell/dunkel, AX5) | [Marktanalyse 22](22-MARKTANALYSE-BEGEISTERUNG.md); offen: Gerätetest (Haptik, Teilen), Welle 2 (Adventsweg) |

**Tests:**
- 1493 Unit-Tests grün (`cd IndoorCoachKit && swift test`).
- 76 UI-Tests (Gipfelmoment, Postkarten, Winterlicht, Comeback, Diagramm-Galerie hell/dunkel/AX5, Walkthrough, Profil-Hub mit Fehler-Badge, intervals.icu-Detailseite, Einführung mit Dienste-Empfehlung für vier Personas, Fortsetzen und Fehlerfälle, Tour, Feedback, Mac-Brücke, Zonen, Soll/Ist, Anpassen, Kraft, Gurt, Aufzeichnung, Check-in, Morgenmessung, Größen- und Dark-Mode-Matrix inkl. v0.2-Oberflächen, Start-Performance) im iOS-Simulator (`IndoorCoachUITests`), auf iPhone 402 pt und iPhone SE.
- 7 Unit-Tests der Mac-App (`IndoorCoachBridgeTests`).
- GitHub Actions: `ci.yml` (Unit-Tests + Simulator-Build + Build der Mac-Brücke) bei jedem Push, `release.yml` für TestFlight.

## Live auf dem iPhone geprüft

- **Claude-Planung:** 14 Tage, 8 Einheiten in 33 s.
- **Kalender:** 8 von 8 Einheiten eingetragen.
- **MyWhoosh:**
  - Anmeldung.
  - Upload: Die numerische Workout-ID und `SportsModeType` waren nötig.
  - Kalender-Eintrag: Task-ID in `data.TaskId`.
  - Fahrten-Import über die Liste mit `page`/`sortDate`.
- **Diagnose:** dauerhaftes Protokoll, mit Kabel direkt vom iPhone lesbar.

## Bekannte Einschränkungen

- **Strava:** Neue Standard-API-Apps brauchen seit Juni 2026 ein Strava-Abo. Ohne Abo liefern MyWhoosh oder FIT-Dateien die Fahrten.
- **MyWhoosh:**
  - Die Schnittstelle ist inoffiziell (Community-Doku) und kann jederzeit brechen. Die `.zwo`-Datei bleibt als Rückfallweg.
  - Die FIT-Dateien der Fahrten verweigert MyWhoosh („Access Denied“). MyWhoosh-Fahrten haben daher nur Ø-Werte; die Leistungskurve zeigt dort Mindestwerte. Volle Kurve über den FIT-Import.
  - Das Ersetzen einer bereits gesendeten Einheit (Löschen mit `sportsModeType`) ist noch nicht live bestätigt.
- **TSS:** Ohne Sekundendaten wird der TSS aus NP oder Ø-Leistung geschätzt.
- **Free Provisioning:** Die App muss alle 7 Tage neu aus Xcode installiert werden.
- **Strava-API-Bedingungen** zu LLMs sind offiziell ungeklärt. Die App sendet nur Aggregate und nur auf Klick ([Konzept §7](02-KONZEPT.md)).

## Nächste Schritte

| Schritt | Wer |
|---|---|
| Ersetzen einer Einheit in MyWhoosh live prüfen | Nutzer + Hauptsession (Log direkt vom iPhone) |
| Widget „Heute“ (App-Extension-Target, App Group, Signierung) | Hauptsession + Nutzer (Signierung) |
| Apple Developer Program + TestFlight für den Pilot (B07) | Nutzer |
| Kontrast-Knoten auf 375 pt und VoiceOver-Durchlauf auf dem Gerät (B13, B14) | Nutzer |

## Ideen für später

| Idee | Status |
|---|---|
| „Einheit anpassen“ (kürzer/leichter) in der Detailansicht | ✅ ohne Claude, regelbasiert ([Paket](15-PAKET-SEKUNDENDATEN-AUSWERTUNG.md)) |
| FTP-Vorschlag aus den Daten | ✅ als eFTP in „Leistung“ |
| Apple Health als Datenquelle (B17) | ✅ umgesetzt (Gerätetest und Signierung offen): Roadmap R0–R5 mit Brustgurt in der App, Krafttraining (Muskel-Spur), Check-in, Aufwärm-Check, Apple Health und Erholungsdaten ([Brainstorming & Backlog B26–B60](17-BRAINSTORM-DATENQUELLEN-ALLTAG.md)); MyWhoosh schreibt nicht nach Apple Health (geprüft 19.11.2026) |
| Leistungsstreams (Strava) für echte NP und Soll/Ist je Intervall (B16) | offen, Strava-Abo nötig |
| intervals.icu-Brücke (B18) | nicht mehr nötig für den Upload (B21), evtl. für FIT-Dateien |
| Wöchentlicher Auto-Plan (Backend + Push) | offen |
| Widget „Heutige Einheit“ (B19) | offen, Teil von Brainstorming G7 |
