# App-Store-Release mit GitHub Actions (Paket O4)

Stand 18.11.2026. Diese Anleitung beschreibt, wie ein Build per Tag nach TestFlight/App Store Connect kommt. Die eigentliche Einreichung zur Prüfung machst du danach in App Store Connect.

## 1. Voraussetzungen

1. **Apple Developer Program** (99 USD/Jahr), Team-ID aus developer.apple.com → Account → Membership.
2. **Bundle-ID** registrieren (Certificates, Identifiers & Profiles → Identifiers). Im Projekt steht `app.indoorcoach.personal`. Für den Store eine eigene, dir gehörende ID wählen und als Repo-Variable `BUNDLE_ID` setzen (der Workflow überschreibt sie per `PRODUCT_BUNDLE_IDENTIFIER`; `project.pbxproj` bleibt unverändert). Die URL-Schemas in `Config/Info.plist` hängen nicht an der Bundle-ID.
3. **App-Eintrag** in App Store Connect anlegen (Meine Apps → +, gleiche Bundle-ID). Ohne Eintrag lehnt der Upload ab.
4. Repo auf GitHub (öffentlich: `jpfrehe/IndoorCoach`).

## 2. API-Key in App Store Connect anlegen

1. App Store Connect → Benutzer und Zugriff → Integrationen → App Store Connect API → Team-Schlüssel → +.
2. Rolle: **Admin** (sicher funktionierend). Für automatische Signierung mit cloudverwalteten Zertifikaten über `xcodebuild` melden Entwickler-Foren mit **App Manager** teils „Cloud signing permission error“. Einen Schlüssel mit App Manager kannst du probieren, wenn du die Rechte klein halten willst. Apple dokumentiert die Mindestrolle nicht eindeutig.
3. Die `.p8`-Datei **nur einmal** herunterladen und sicher aufbewahren (nie committen; `.gitignore` schließt `*.p8` aus). Notiere **Key-ID** und **Issuer-ID** (oben auf der Seite).
4. Base64 erzeugen: `base64 -i AuthKey_XXXX.p8 | pbcopy`.

## 3. GitHub einrichten

Settings → Environments → **New environment** `app-store`. Schutzregeln: *Required reviewers* (du selbst) und *Deployment branches and tags* auf Tags `v*` beschränken. Dann im Environment:

| Typ | Name | Inhalt |
|---|---|---|
| Secret | `APPLE_TEAM_ID` | 10-stellige Team-ID |
| Secret | `ASC_KEY_ID` | Key-ID des API-Keys |
| Secret | `ASC_ISSUER_ID` | Issuer-ID (UUID) |
| Secret | `ASC_KEY_P8_BASE64` | Base64 der `.p8`-Datei |
| Variable | `BUNDLE_ID` | optional; Standard `app.indoorcoach.personal` |
| Variable | `BUILD_NUMBER_OFFSET` | optional; wird auf `github.run_number` addiert (siehe Fehlersuche) |

## 4. Release auslösen

- **Tag:** `git tag v1.0.0 && git push origin v1.0.0`. Version = Tag ohne `v`.
- **Manuell:** Actions → Release → Run workflow. `version` angeben (z. B. `1.0.0`); `upload` aus = nur Archiv/Export ohne Upload.

Je nach Schutzregel wartet der Lauf auf deine Freigabe.

## 5. Was die CI macht

`ci.yml` (jeder Push auf `main`, jede Pull Request): `swift test` für IndoorCoachKit und ein App-Build für den Simulator ohne Signierung. Optional manuell: UI-Tests.

`release.yml`:
1. Secrets prüfen (klare Fehlermeldung, wenn eines fehlt).
2. Version aus dem Tag, Build-Nummer = `github.run_number` + `BUILD_NUMBER_OFFSET` (`scripts/bump-build.sh`).
3. API-Key nach `$RUNNER_TEMP` schreiben (nur für den Besitzer lesbar), `swift test`.
4. `scripts/archive.sh` mit `UPLOAD=1`: Archiv, Export mit `method app-store-connect`, `destination upload`, Signierung automatisch über `-allowProvisioningUpdates` und die API-Key-Parameter.
5. Log, Export und dSYMs als Artefakt (30 Tage); die Key-Datei wird immer gelöscht.

Der Build erscheint nach der Verarbeitung (ein paar Minuten) in TestFlight. Lokal bleibt `DEVELOPMENT_TEAM=… scripts/archive.sh` unverändert; mit `ASC_KEY_PATH`, `ASC_KEY_ID`, `ASC_ISSUER_ID` (alle drei) nutzt es den API-Key, `BUNDLE_ID` und `MARKETING_VERSION` sind optional.

Technische Grundlage: Runner `xcode-27` (macOS 27, nur arm64, Xcode 27.2 unter `/Applications/Xcode_27.2.app`, Standard dort 27.1) und `sudo xcode-select -s`. Aktions-Versionen: `actions/checkout@v7`, `actions/cache@v6`, `actions/upload-artifact@v7` (GitHub-eigene Actions, Major-Tag; Dependabot hält sie aktuell). Quellen: [GitHub Changelog: Xcode 27 Runner-Image GA](https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available), [Image-Inhalte](https://raw.githubusercontent.com/actions/runner-images/main/images/macos/xcode-27-arm64-Readme.md), [macos-26-Image (Xcode 26.6)](https://raw.githubusercontent.com/actions/runner-images/main/images/macos/macos-26-arm64-Readme.md), Release-Seiten von [checkout](https://github.com/actions/checkout/releases), [cache](https://github.com/actions/cache/releases), [upload-artifact](https://github.com/actions/upload-artifact/releases), [Apple Developer Forums zur API-Key-Signierung](https://developer.apple.com/forums/thread/698117). Hinweis: `macos-26` liefert nur Xcode 26.x und passt nicht, weil das Projekt Swift-tools 6.2 und Xcode 27 voraussetzt. Die Abrechnung der `xcode-27`-Runner für öffentliche Repositories steht nicht in der Ankündigung; die Minuten im Blick behalten.

## 6. Fehlersuche

| Meldung | Ursache und Abhilfe |
|---|---|
| „Secret fehlt“ | Secret im Environment `app-store` (nicht nur im Repo) anlegen; Name exakt. |
| „Cloud signing permission error“, „No signing certificate“ | API-Key-Rolle auf Admin; Bundle-ID existiert nicht oder gehört einem anderen Team; Team-ID falsch. |
| „Authentication failed“ | Key-ID/Issuer-ID vertauscht, Key widerrufen oder Base64 beschädigt (Prüfung auf `BEGIN PRIVATE KEY` schlägt vorher an). |
| „bundle version must be higher“ / „already used“ | App Store Connect verlangt pro Version eine wachsende Build-Nummer. `run_number` wächst immer; wenn zuvor lokal mit Zeitstempel (`202611171045`) hochgeladen wurde, ist dieser Wert größer: `BUILD_NUMBER_OFFSET` so setzen, dass die Summe darüber liegt. Beim Anlegen einer neuen Version ist die Zählung wieder frei. |
| „No app found“ | App-Eintrag in App Store Connect mit gleicher Bundle-ID fehlt. |
| Export meldet fehlende Compliance | `ITSAppUsesNonExemptEncryption = NO` steht bereits in `Config/Info.plist`. |

## 7. Review-Risiken für eine breitere Zielgruppe

1. **Inoffizielle MyWhoosh-Schnittstelle** (Richtlinien 5.2.2 und 5.2.3): Apps dürfen Dienste Dritter nur mit deren Erlaubnis einbinden. Es gibt keine offizielle Freigabe. Risiken: Ablehnung, spätere Sperrung, Schnittstellenänderung. Gegenmaßnahmen: bei MyWhoosh um schriftliche Erlaubnis bitten, in den Review-Hinweisen offen schreiben, dass Nutzer ihr eigenes Konto verwenden, Passwort wird nicht gespeichert; die App ist ohne MyWhoosh nutzbar (Demo-Modus, FIT-Import, `.zwo`-Export).
2. **Strava:** API-Vereinbarung beachten (Branding „Powered by Strava“, keine Weitergabe von Daten, Nutzerdaten nur für den Nutzer). Jede Nutzerin braucht eine eigene API-App (seit Juni 2026 mit Abo); deshalb nur als Weg für Fortgeschrittene beschreiben. Ohne Strava-Genehmigung für mehr Nutzer gilt das Limit eines einzelnen Athleten.
3. **Eigener Claude-Key (BYOK) und KI-Inhalte:** Der Key gehört dem Nutzer und liegt im Schlüsselbund. Trainingsvorschläge sind KI-generiert: Hinweis „kein medizinischer Rat“ in App und Beschreibung; Datenweitergabe an Anthropic in der Datenschutzerklärung nennen (Richtlinie 5.1.2 zur Weitergabe an KI von Dritten braucht eine ausdrückliche Zustimmung; der Nutzer löst sie durch Eingabe des Keys und das Planen selbst aus – im Onboarding klar benennen).
4. **Mindestfunktionalität (4.2):** unkritisch, die App hat eigene Logik (Plan, Fitness, Winter Arc, Auswertungen).
5. **Gesundheit (1.4):** Trainingsempfehlungen vorsichtig formulieren.
6. **Demo-Modus für Prüfer:** Kein Testkonto nötig. Vorschlag für die Review-Hinweise:
   > Die App läuft ohne Anmeldung mit Demo-Daten (Onboarding → „Später“ bei Trainings-App und Coach). Alle Anzeigen (Heute, Plan, Leistung) sind ohne Konto sichtbar. MyWhoosh, Strava und Claude sind optional und nutzen jeweils das eigene Konto bzw. den eigenen API-Key der Nutzerin; es gibt keinen Server und kein IndoorCoach-Konto.

## 8. App-Datenschutz („App Privacy“) in App Store Connect

Empfohlene Antwort bis Stand Paket O4: **„Daten werden nicht erfasst“ (Data Not Collected)**. Mit Health, Kraft, Check-ins und dem Claude-Erholungskontext gilt stattdessen die Tabelle im Unterabschnitt „App-Datenschutzangaben (Gesundheit & Fitness)“ weiter unten.

Begründung: Der Entwickler betreibt keine Server und erhält keine Daten. Apple definiert „Erfassen“ als Übertragung an den Entwickler oder Dritte in dessen Auftrag. Anfragen an Anthropic, Strava und MyWhoosh gehen direkt vom Gerät mit den eigenen Zugangsdaten des Nutzers; keine SDKs, kein Tracking (`NSPrivacyTracking = false`). Apple kann dennoch Rückfragen stellen; halte die Begründung bereit. Das Privacy-Manifest `App/PrivacyInfo.xcprivacy` deklariert `UserDefaults` mit Grund `CA92.1`. Prüfung am Code: keine Datei-Zeitstempel-, Systemstart- oder Speicherplatz-APIs im Kit (Stand 18.11.2026). Bei neuem Code neu prüfen.

Weiter: Datenschutz-URL = `https://github.com/jpfrehe/IndoorCoach/blob/main/docs/PRIVACY.md` (Entwurf erst prüfen, Impressumsdaten ergänzen; die URL muss ohne Anmeldung erreichbar sein).

### App-Datenschutzangaben (Gesundheit & Fitness)

Seit den Paketen Brustgurt, Apple Health, Kraft, Check-ins und Claude-Erholungskontext (W4-C) gilt für App Store Connect: Weil Gesundheits- und Fitnessdaten (mit Einwilligung) an Anthropic gehen, ist „Data Not Collected“ nicht mehr haltbar. Empfohlene Angaben unter „App-Datenschutz“:

| Datentyp | Erfasst? | Mit Identität verknüpft | Tracking | Zweck |
|---|---|---|---|---|
| Gesundheit (Health) | Ja (relativer Erholungskontext, nur mit Einwilligung) | Nein | Nein | App-Funktionalität |
| Fitness (Fitness) | Ja (Trainings- und Kraftdaten für die Planung) | Nein | Nein | App-Funktionalität |
| Alle übrigen Typen (Kontakte, Standort, Kennungen, Nutzungsdaten, Diagnosedaten …) | Nein | | | |

- Das Manifest `App/PrivacyInfo.xcprivacy` deklariert dieselben Typen (`NSPrivacyCollectedDataTypeHealth`, `NSPrivacyCollectedDataTypeFitness`, nicht verknüpft, kein Tracking, `AppFunctionality`). Beides muss übereinstimmen.
- Datenschutz-URL unverändert (`docs/PRIVACY.md`, vor der Veröffentlichung juristisch prüfen, Offene Frage O3).
- Review-Hinweis (5.1.2(i), 5.1.3): Erholungsdaten gehen nur nach ausdrücklicher Einwilligung (Sheet vor dem ersten Planen, widerrufbar unter Profil → Datenschutz) und nur relativ und gerundet an Claude; keine Werbung, kein Data-Mining, keine Weitergabe an Dritte. Health-Daten werden nicht in iCloud gespeichert.
- `NSHealthShareUsageDescription` und `NSHealthUpdateUsageDescription` müssen den Lese- und Schreibzweck konkret nennen (Info.plist).
- Bei jeder Änderung, was an Claude geht, `ClaudeConsent.currentVersion` erhöhen (erneute Einwilligung) und diese Tabelle prüfen.

## 9. Export-Compliance

`ITSAppUsesNonExemptEncryption = NO` ist in `Config/Info.plist` gesetzt: Die App nutzt nur HTTPS (Betriebssystem-Verschlüsselung) und den Schlüsselbund. Damit entfallen die Compliance-Fragen bei jedem Upload. Wird eigene Kryptografie ergänzt, neu bewerten.

## 10. Metadaten-Checkliste

- [ ] Name, Untertitel, Beschreibung, Schlüsselwörter (Deutsch, ggf. Englisch)
- [ ] Datenschutz-URL: `docs/PRIVACY.md` auf GitHub (siehe oben)
- [ ] Support-URL: `https://github.com/jpfrehe/IndoorCoach/issues`
- [ ] Screenshots aus `docs/screenshots` (6,9"-iPhone Pflicht; Größen im App Store Connect prüfen), ohne echte Konten- oder Gesundheitsdaten (Demo-Daten)
- [ ] Kategorie **Gesundheit & Fitness**
- [ ] Altersfreigabe-Fragebogen (keine bedenklichen Inhalte; Hinweis auf KI-Texte ehrlich beantworten)
- [ ] Hinweis „kein Medizinprodukt, kein medizinischer Rat“ in der Beschreibung
- [ ] Markenhinweis (MyWhoosh, Strava, Zwift: keine Verbindung, Namen nur beschreibend)
- [ ] Review-Hinweise mit Demo-Anleitung (Abschnitt 7)
- [ ] App-Datenschutz ausgefüllt (Abschnitt 8), Export-Compliance bestätigt
- [ ] Build aus TestFlight der Version zugeordnet, zur Prüfung einreichen
