# 18 · Profil aufräumen: „Ich“, „Verbindungen“, „App“

Stand: 21.11.2026 · erarbeitet mit einem UX-Engineer-Agent, Entscheidungen durch die Hauptsession (unten).

## Problem

Der Profil-Tab ist ein einziges `Form` mit 15 Abschnitten. Athletenwerte, Dienste und App-Einstellungen wechseln sich ab:

- Strava und MyWhoosh stehen als ganze Formulare inline. Brustgurt, Kraft und Datenquellen sind dagegen einzeilige Unterseiten.
- Mac-Brücke und FIT-Import hängen unter „MyWhoosh“, obwohl sie nichts mit MyWhoosh zu tun haben. „Daten“ ist zweimal Überschrift.
- Häufig Genutztes liegt mitten zwischen Einmal-Einrichtung: Auf dem iPhone SE braucht es bis zu 14 Wischer bis zur Verfügbarkeit oder zur Mac-Brücke.
- Ein Sync-Fehler erscheint nur als Banner, der nach 6 s verschwindet. Es gibt keinen dauerhaften Status.
- „Bei MyWhoosh abmelden“ läuft ohne Rückfrage. „Alle Daten löschen“ steht im normalen Scrollfluss, und der Dialog verschweigt MyWhoosh, Mac-Kopplung und Brustgurt.
- Jeder neue Dienst (Zwift, Garmin, intervals.icu …) würde einen weiteren Inline-Abschnitt bringen.

## Varianten

| Variante | Vorteile | Nachteile |
|---|---|---|
| **A · Profil oben, darunter Unterseite „Dienste & Geräte“ und Gruppe „App“** | Häufiges bleibt einen Tap entfernt; Dienste skalieren auf einer eigenen Seite; „im Profil“-Texte bleiben richtig | Erinnerungen und Hilfe rücken einen Tap tiefer |
| B · fünfter Tab „Dienste“ | sofort sichtbar | Tabs sind für die tägliche Arbeit da, Dienste braucht man selten |
| C · reine Einstellungsliste nach iOS-Muster | sehr kurz | FTP und Ziel einen Tap tiefer, das Profil verliert seinen Charakter |

**Gewählt: A.** Der Tab heißt weiter **„Profil“**: Er beginnt mit den eigenen Werten, rund zehn Texte verweisen „im Profil“, und „Einstellungen“ würde mit der iOS-App verwechselt.

## Zielbild

### Startseite „Profil“

| # | Abschnitt | Inhalt | Identifier |
|---|---|---|---|
| 1 | Athlet | FTP, Gewicht, W/kg, Schwellen-, Ruhe- und Max-HF (inline) | – |
| 2 | Ziel | Ziel, Zieldatum, Hinweise, „Fertig“ im Kopf (inline) | `keyboard.done` |
| 3 | Verfügbarkeit | `WeekdayPicker` (bricht bei AX-Größen um), Wochenbudget, Max. pro Einheit, Startzeit | – |
| 4 | Saison & Training | Winter Arc › · Kraft › | `profile.winterArc`, `profile.strength` |
| 5 | Verbindungen | Dienste & Geräte › „n verbunden“, Badge bei Problemen; darunter je Problem eine Zeile direkt zur Detailseite | `profile.connections`, `profile.attention.<id>` |
| 6 | App | Coach · Claude › „Bereit“/„Key fehlt“ · Erinnerungen › · Hilfe & Feedback › · Daten auf diesem iPhone › | `profile.coach`, `profile.reminders`, `profile.help`, `profile.storage` |

Auf der Startseite steht keine destruktive Aktion mehr.

### „Dienste & Geräte“

- **Fahrten & Pläne:** Strava (`profile.strava`), MyWhoosh (`profile.mywhoosh`), Sekundendaten vom Mac (`profile.bridge`), FIT-Dateien importieren … (`profile.fitImport`, öffnet direkt die Dateiauswahl).
- **Gesundheit & Geräte:** Apple Health (`profile.dataSources`, Seitentitel bleibt „Datenquellen“), Brustgurt (`profile.strap`).
- **Footer:** „Fehlt dir ein Dienst?“ mit Link zum Feedback (`profile.requestService`). Keine Zeilen „bald verfügbar“, die etwas versprechen.

Jede Zeile hat Icon, Name, Rolle als Zweitzeile („Fahrten · Pläne“) und rechts den Status mit Symbol **und** Text („Verbunden“, „Nicht verbunden“, „Erneut verbinden“, „Fehler“). Für VoiceOver ist jede Zeile ein Element. Bei AX-Größen stehen Name, Rolle und Status untereinander.

### Detailseite eines Dienstes (immer gleiche Reihenfolge)

1. Status-Kopf (verbunden als …, letzter Sync, ggf. Fehlertext)
2. Hauptaktion (Verbinden bzw. Jetzt synchronisieren)
3. Optionen
4. Hilfe-Footer mit Link (die bisherigen „Links“ wandern hierher)
5. Trennen ganz unten, immer mit Rückfrage

`ConnectionDetailScaffold` liefert dieses Gerüst. MacBridgeView, DevicesView und DataSourcesView behalten vorerst ihr Layout; Status oben und Trennen unten haben sie schon.

## Datenmodell

```swift
enum ConnectionID: String, CaseIterable { case strava, myWhoosh, macBridge, fitImport, appleHealth, strap }
enum ConnectionRole { case rides, plans, secondData, recovery, heartRate }
enum ConnectionStatus: Equatable {
    case connected(detail: String?, lastSync: Date?)
    case notConnected
    case needsSetup(String)    // „Erneut verbinden“, „Anmeldung abgelaufen“
    case error(String)
    case unavailable(String)
    var needsAttention: Bool    // nur needsSetup und error
}
struct ConnectionDescriptor: Identifiable { id, name, systemImage, roles, status }
extension AppModel { func connections(strap:) -> [ConnectionDescriptor]; var connectionsNeedingAttention: Int }
```

Der Status wird nur aus vorhandenen Werten abgeleitet. Neu ist lediglich `syncErrors: [ConnectionID: String]` (nur im Speicher): Die `catch`-Zweige von Strava-Sync, MyWhoosh-Import und Brücken-Abholung setzen ihn, ein Erfolg und „Alle Daten löschen“ leeren ihn. „Nicht verbunden“ zählt nie als Problem, sonst trüge jeder ohne Strava dauerhaft ein Badge.

**Ein neuer Dienst bedeutet:** ein `case`, ein Zweig im Status-Builder, eine Detailansicht und ein Navigationsziel. ProfileView bleibt unverändert.

## Navigation

`NavigationStack(path:)` mit `ProfileRoute` (`connections`, `connection(ConnectionID)`, `coach`, `winterArc`, `strength`, `reminders`, `help`, `storage`). Programmgesteuerte Sprünge laufen über eine einmal verbrauchte Eigenschaft `pendingProfileRoute`. Das Onboarding „Mit Strava verbinden“ landet damit direkt auf der Strava-Detailseite. Der alte Scroll-Sprung (`StravaSectionScroller`) fällt weg. Texte, die einen Ort nennen, heißen künftig „Profil → Dienste & Geräte → …“.

## Entscheidungen

| Frage | Entscheidung | Grund |
|---|---|---|
| Claude als Dienst oder unter „App“? | unter **App** als „Coach · Claude“, mit Datenschutz auf derselben Seite | Claude ist der Coach, keine Datenquelle |
| Badge am Profil-Tab? | **ja, nur für Fehler bzw. „Erneut verbinden“** | Wer Daten verliert, soll es sehen; „nicht verbunden“ ist kein Fehler |
| „Bald verfügbar“-Zeilen? | **nein**, nur „Fehlt dir ein Dienst?“ | kein Versprechen ohne Backlog |
| Erinnerungen und Hilfe einen Tap tiefer? | **ja** | selten genutzt, Startseite schrumpft von gut 50 auf rund 22 Zeilen |
| MyWhoosh abmelden | **mit Rückfrage** | gleichgezogen mit Strava |
| „Trend-Wächter Schattenmodus“ | bleibt unter Hilfe & Feedback | außerhalb dieses Umbaus |

## Umsetzung (ECC, Tests zuerst)

| AP | Inhalt | Tests |
|---|---|---|
| AP1 | Status-Logik `AppModel+Connections.swift`, `syncErrors` | neu `ConnectionStatusTests`, `DeleteAllData` leert `syncErrors` |
| AP4 | Startseite neu gruppieren: Winter Arc, Coach, Erinnerungen, Hilfe, Daten auf diesem iPhone als Unterseiten, `WeekdayPicker`, Löschdialog vollständig | UI-Tests auf neue Einstiege |
| AP2 + AP3 + AP5 | Hub „Dienste & Geräte“, Detailseiten Strava/MyWhoosh, Pfad-Navigation und Onboarding-Sprung, Badges, Texte | UI-Tests über `openConnections()`, Debug-Seed für einen Sync-Fehler |

Abschluss: Code-Review, alle Unit-Tests, volle UI-Tests auf 402 pt und iPhone SE.
