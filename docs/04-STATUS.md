# Status & nächste Schritte

Stand: v0.1 (Pilot-Vorbereitung) · 18.11.2026 · öffentlich auf [GitHub](https://github.com/jpfrehe/IndoorCoach)

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
| UX-Audit 2 der erweiterten Version | ✅ 6 Befunde behoben | [Bericht](ux-audit-2026-11-17-b.md); formal offen: automatisch gemeldete Kontrast-Knoten (Gerät, B13) |

**Tests:**
- 365 Unit-Tests grün (`cd IndoorCoachKit && swift test`).
- 37 UI-Tests (Walkthrough, Onboarding-Journey, Tour, Feedback, Größen- und Dark-Mode-Matrix, Start-Performance) im iOS-Simulator (`IndoorCoachUITests`).
- GitHub Actions: `ci.yml` (Unit-Tests + Simulator-Build) bei jedem Push, `release.yml` für TestFlight.

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
| „Einheit anpassen“ (kürzer/leichter) per Claude in der Detailansicht | offen |
| FTP-Vorschlag aus den Daten | ✅ als eFTP in „Leistung“ |
| Apple Health als Datenquelle (B17) | offen |
| Leistungsstreams (Strava) für echte NP und Soll/Ist je Intervall (B16) | offen, Strava-Abo nötig |
| intervals.icu-Brücke (B18) | nicht mehr nötig für den Upload (B21), evtl. für FIT-Dateien |
| Wöchentlicher Auto-Plan (Backend + Push) | offen |
| Widget „Heutige Einheit“ (B19) | offen, Teil von Brainstorming G7 |
