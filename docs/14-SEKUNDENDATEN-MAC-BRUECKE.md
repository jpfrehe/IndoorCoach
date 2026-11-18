# Sekundendaten aus MyWhoosh: Analyse, Alternativen, Entscheidung „Mac-Brücke“ (ECC, 3 parallele Pakete)

Stand 18.11.2026 · Größe: **groß** (neues Mac-Target, Netzwerkprotokoll, Import-Anreicherung) · Gate 1: vom Nutzer mit dem Auftrag freigegeben („Reflektiere … brainstorme … wähle die beste und einfachste Nutzererfahrung … schreibe eine User Journey und baue die Umsetzung nach ECC“).

## 1. Wie kommen die Daten heute in die App?

Die detaillierten Analysen brauchen **1-Hz-Daten** (Leistung, Herzfrequenz je Sekunde): Leistungskurve und Bestleistungen, VO2max aus der 5-min-Leistung, NP/TSS, Pw:HR-Entkopplung, Ermüdungsresistenz (Durability). Dafür gibt es heute diese Wege:

| Weg | Was ankommt | Sekundendaten? | Problem |
|---|---|---|---|
| Strava-Summary | Ø-Leistung, gew. Leistung, max_watts, HF | ❌ | Streams-API seit 06/2026 nur mit Abo (B16, B08) |
| MyWhoosh-Fahrtenliste (`service14…/v2/rider/profile/activities`) | Datum, Dauer, Ø-Leistung, Ø-HF | ❌ | Liste ohne Rohdaten |
| MyWhoosh-FIT aus der Cloud (`mywhooshprod.s3…/ride/<id>/<key>`) | volle FIT-Datei | ✅ theoretisch | **S3 „Access Denied“** (B23). Die Community-Tools (z. B. *mywhoosh-to-garmin*) bauen dieselbe unsignierte URL und haben dasselbe Problem. |
| FIT-Import über die Dateien-App | volle FIT-Datei | ✅ | MyWhoosh hat **keinen Export-Knopf**. Auf dem Mac liegt die Datei in einem geschützten App-Container (s. u.). Der Nutzer müsste sie bei jeder Fahrt manuell aufs iPhone bringen. |

**Zusätzlicher Fehler im Ist-Zustand:** `storeImportedRides` verwirft jede Fahrt, die innerhalb von ±5 min einer vorhandenen beginnt. Wer eine Fahrt erst über die MyWhoosh-Liste und danach dieselbe Fahrt als FIT importiert, bekommt deshalb **keine Sekundendaten**: Die FIT-Fahrt gilt als Dublette und wird weggeworfen.

**Wo liegen die Daten wirklich?** MyWhoosh für macOS ist eine Mac-App-Store-App (`com.whoosh.whooshgame`). Sie schreibt nach jeder Fahrt eine FIT-Datei nach
`~/Library/Containers/com.whoosh.whooshgame/Data/Library/Application Support/Epic/MyWhoosh/Content/Data/`
(Dateiname im Stil `MyNewActivity-<Version>.fit`, Pfad wie bei *Fit File Faker* und *MyWhoosh2Garmin*). Geprüft auf diesem Mac: Der Container existiert. Ein Zugriff aus dem Terminal endet mit „Operation not permitted“, weil macOS seit Version 14 App-Daten anderer Apps schützt. Zugriff gibt es nur, wenn **der Nutzer den Ordner einmal ausdrücklich freigibt** (Öffnen-Dialog bzw. Abfrage „… möchte auf Daten anderer Apps zugreifen“).

## 2. Alternativen (alle technisch geprüft)

| # | Idee | Technisch möglich? | Einmaliger Aufwand | Aufwand pro Fahrt | Zuverlässigkeit | Datenschutz |
|---|---|---|---|---|---|---|
| A | Cloud-FIT von MyWhoosh (signierte URL, anderer Endpunkt suchen) | **heute nicht** (S3 verweigert; kein dokumentierter Weg, Community ebenfalls blockiert) | – | 0 | – | Cloud |
| B | FIT manuell: im Finder in den Container navigieren, per AirDrop/iCloud aufs iPhone, „Öffnen in IndoorCoach“ | ja | gering | **hoch** (5–8 Klicks je Fahrt, versteckter Ordner) | hoch | lokal |
| C | iPhone zeichnet selbst mit: zweite Bluetooth-Verbindung zu Leistungsmesser/Rolle (Cycling Power 0x1818) und HF-Gurt | ja, aber viele Rollen erlauben nur **eine** BLE-Verbindung, ANT+ fehlt auf dem iPhone, die App muss die ganze Fahrt laufen | mittel | gering bis mittel (App vor der Fahrt öffnen) | **mittel–niedrig** | lokal |
| D | Umweg über eine Plattform: MyWhoosh → Strava / Garmin Connect / intervals.icu → App | Strava-Streams nur mit Abo; Garmin Connect ohne API für Privatnutzer; MyWhoosh → intervals.icu ist laut Forum nur für Workouts belegt | hoch (2–3 Konten) | 0 | mittel | Cloud, Dritte |
| E | Apple Health: MyWhoosh schreibt Workouts nach Health | auf dem Mac nein (kein Health-Speicher); auf iOS ohne Sekundenleistung | gering | 0 | niedrig | lokal |
| F | **Mac-Brücke + iCloud Drive:** Menüleisten-App liest den MyWhoosh-Ordner und legt FIT-Dateien in einen iCloud-Container, das iPhone importiert sie | ja; braucht iCloud-Capability und Container im Apple-Developer-Konto sowie dieselbe Apple-ID; Sync dauert teils Minuten; im Simulator kaum testbar | gering (Mac-App, 1 Freigabe) | **0** | hoch | Apple-Cloud |
| G | **Mac-Brücke + lokales Netz:** Menüleisten-App liest den Ordner und bietet die Fahrten per Bonjour im WLAN an (TLS mit Pre-Shared-Key nach einmaliger Kopplung per 6-stelligem Code). Das iPhone holt sie beim Öffnen ab. | ja; Network.framework auf beiden Seiten, kein Konto, keine Entitlements außer Sandbox/Netzwerk; komplett auf diesem Mac mit Simulator testbar | gering (Mac-App, 1 Freigabe, 1 Code) | **0** | hoch, solange Mac und iPhone im selben WLAN sind (Indoor-Training = zu Hause) | **bleibt im Heimnetz** |
| H | Kurzbefehle-/Ordneraktion auf dem Mac kopiert nach iCloud Drive | nur nach Freigabe des Containers für Kurzbefehle; Einrichtung für Laien schwer, bricht bei MyWhoosh-Updates | **hoch** | 0 | mittel | Apple-Cloud |
| + | Basis für alle Wege: FIT-Import **reichert vorhandene Fahrten an**, statt sie als Dublette zu verwerfen. Dazu `.fit` als Dokumenttyp („Öffnen in IndoorCoach“, Teilen-Menü). | ja | – | – | – | – |

## 3. Bewertung und Entscheidung

Die Kriterien folgen der Persona: Hobby-Rennradfahrerin, fährt MyWhoosh auf dem MacBook im Arbeitszimmer, das iPhone liegt daneben, wenig Technik-Geduld.

1. **Pro Fahrt null Handgriffe.** Das ist das wichtigste Kriterium. Alles, was bei jeder Fahrt Arbeit macht (B, C), wird nach zwei Wochen nicht mehr benutzt. Übrig bleiben F und G.
2. **Funktioniert sicher heute**, ohne fremde Konten und ohne Abo. Damit fallen A, D und E weg.
3. **Einfachste Einrichtung**: F und G sind gleichauf (Mac-App öffnen, Ordner freigeben). G braucht zusätzlich einen 6-stelligen Code, F dafür dieselbe Apple-ID mit aktivem iCloud Drive und einen iCloud-Container, den das Apple-Konto des Entwicklers erst anlegen muss.
4. **Testbarkeit und Risiko**: G lässt sich vollständig hier testen (Mac-App auf diesem Mac, iPhone-App im Simulator, gleiches Netz). F lässt sich ohne Portal-Zugang weder signieren noch testen.
5. **Datenschutz**: Bei G verlassen die Fahrten das Heimnetz nicht.

**Entscheidung: G, „IndoorCoach Brücke“ für den Mac mit Übertragung im lokalen Netz.** Dazu kommt die Basis „+“ (Anreicherung, `.fit` öffnen), die auch Zwift-, Wahoo- und Garmin-Nutzern hilft. F bleibt als zweiter Transportweg derselben Mac-App vorgemerkt (Backlog B24), falls Nutzer auch unterwegs synchronisieren wollen.

## 4. User Journey

**Persona Lena, 38**, fährt dreimal pro Woche MyWhoosh auf dem MacBook Air. Sie nutzt IndoorCoach schon mit MyWhoosh-Login: Ihre Fahrten kommen aus der Liste, die Leistungskurve zeigt aber nur „Mindestwerte“.

| Schritt | Lena tut / sieht | App-Verhalten |
|---|---|---|
| 1 · Entdecken | In **Verlauf → Leistung** steht: „2 von 14 Fahrten mit Sekundendaten“. Darunter eine Karte: **„Volle Leistungskurve für jede Fahrt: Fährst du MyWhoosh auf dem Mac? IndoorCoach Brücke holt die Daten automatisch.“** [Einrichten]. Derselbe Einstieg steht im Profil unter MyWhoosh („Sekundendaten vom Mac“). | Die Karte erscheint nur, wenn Fahrten ohne Sekundendaten existieren und keine Brücke gekoppelt ist. |
| 2 · Anleitung (iPhone) | Ein Blatt **„Mac-Brücke einrichten“** mit 3 Schritten und Animation: ① „IndoorCoach Brücke auf dem Mac öffnen“ ② „MyWhoosh-Ordner freigeben“ ③ „Code eingeben“. Ganz unten: „Kein Mac? FIT-Datei importieren“. | Das iPhone sucht schon im Hintergrund nach Brücken im WLAN (einmalige iOS-Abfrage „Lokales Netzwerk“ mit erklärendem Text). |
| 3 · Mac einrichten | Erster Start der Brücke: ein Fenster „Hallo! Ich bringe deine MyWhoosh-Fahrten aufs iPhone.“ Sie klickt **„MyWhoosh-Ordner freigeben“**. Der Öffnen-Dialog steht schon im richtigen Ordner, sie klickt „Freigeben“. Ergebnis: **„✓ 23 Fahrten gefunden“**. | Die Brücke speichert ein Security-Scoped-Bookmark, liest alle FIT-Dateien und legt sie in ihren Ausgang (je Fahrt eine Datei, Schlüssel = Startzeit). Falscher Ordner → „In diesem Ordner liegen keine MyWhoosh-Fahrten“ mit Hilfetext. |
| 4 · Koppeln | Der Mac zeigt groß den Code **482 913**. Auf dem iPhone erscheint „Gefunden: Lenas MacBook Air“. Sie tippt darauf und gibt den Code ein. | Kopplung über TLS-PSK, abgeleitet aus dem Code (5 min gültig, einmalig). Danach schickt der Mac ein zufälliges 32-Byte-Geheimnis. Beide speichern es im Schlüsselbund. Weitere Verbindungen nutzen nur noch das Geheimnis. |
| 5 · Erster Abgleich | Das iPhone meldet: **„Mac-Brücke gekoppelt · 23 Fahrten übertragen, 12 bestehende ergänzt“**. In „Leistung“ steht jetzt „14 von 14 Fahrten mit Sekundendaten“. | Vorhandene Fahrten (Start ±5 min) bekommen Kurve, max. Leistung, NP, Entkopplung und Durability. Neue Fahrten werden angelegt. |
| 6 · Mac-Alltag | Auf dem Mac schlägt die Brücke vor: „Beim Anmelden starten“ (an). Danach lebt sie nur als Symbol in der Menüleiste: „Gekoppelt mit iPhone · 23 Fahrten bereit · zuletzt abgeholt 18:42“. | Login-Item über `SMAppService`. Der Ordner wird alle 20 s geprüft, eine Datei gilt erst als fertig, wenn Größe und Änderungszeit über zwei Prüfungen gleich bleiben und sie mindestens 15 s alt ist. |
| 7 · Nach jeder Fahrt | Lena beendet die Fahrt in MyWhoosh und öffnet IndoorCoach auf dem iPhone: Banner **„Neue Fahrt vom Mac: 52 min · NP 214 W“**. Die Fahrt hat das Abzeichen „Sekundendaten“. | Beim Wechsel in den Vordergrund (höchstens alle 2 min) und bei „Jetzt abholen“ verbindet sich das iPhone, fragt nach neuen Fahrten und lädt sie. |
| 8 · Sonderfälle | Mac zugeklappt oder anderes WLAN: Beim automatischen Abgleich kommt keine Meldung, bei „Jetzt abholen“ steht „Mac nicht erreichbar – ist die Brücke geöffnet und seid ihr im selben WLAN?“. Nach einem MyWhoosh-Update mit neuem Ordner zeigt die Brücke ein Warnsymbol und „Ordner neu freigeben“. Neues iPhone: „Weiteres iPhone koppeln“. Kopplung lösen geht auf beiden Seiten („Kopplung zurücksetzen“ auf dem Mac erneuert das Geheimnis). | Der Ausgang behält 180 Tage. Fahrten, die das iPhone schon hat, werden nicht doppelt geladen (Abgleich über die Fahrt-ID `fit-<Startzeit>`). |

## 5. Architektur

```
MyWhoosh (Mac) ──schreibt──▶ Container/…/Content/Data/*.fit
                                  │ Security-Scoped-Bookmark (einmalige Freigabe)
IndoorCoach Brücke (macOS, Menüleiste)
  RideFolderScanner ─▶ BridgeOutbox (App Support/Outbox/fit-<start>.fit) ─▶ BridgeServer (NWListener, Bonjour _indoorcoach._tcp, TLS-PSK)
                                                                                   ▲ Kopplung: _icpair._tcp, PSK = HKDF(Code)
IndoorCoach (iOS)                                                                  │
  AppModel.syncFromBridge() ─▶ BridgeClient (NWBrowser/NWConnection) ──────────────┘
      └▶ FITParser.summary ─▶ RideMerge (anreichern ±5 min oder neu) ─▶ StoredRide
```

**Protokoll v1:** Nachrichten mit 8-Byte-Header (Typ UInt32, Länge UInt32) über `NWProtocolFramer`, JSON-Nutzlast bzw. Rohbytes für FIT. Ablauf: `hello` → `welcome` → `listRides(since)` → `rides([…])` → je fehlende Fahrt `fetchRide(id)` → `rideData`. Kopplung: separater Listener nur während der Code angezeigt wird, `hello` → `pairingSecret`. Höchstens 20 MB pro Nachricht.

**Sicherheit:**
- Im Normalbetrieb nur TLS 1.3 mit 32-Byte-PSK. Der Kopplungs-Listener läuft nur, solange der Code sichtbar ist (höchstens 5 min, einmalig).
- Der Code hat 6 Ziffern. Ein Angreifer im selben WLAN, der den Handshake mitschneidet, könnte ihn offline erraten. Er bekäme dann nur Fahrtdaten, kein Konto. Gegenmaßnahmen: Kopplungsfenster kurz und einmalig, und das Geheimnis lässt sich auf dem Mac jederzeit erneuern. Apple verwendet dasselbe Muster im Beispielprojekt *TicTacToe – Building a custom peer-to-peer protocol*.
- Keine Ride-Namen oder Geheimnisse im Log, nur Zahlen.

## 6. Arbeitspakete (Ownership exklusiv)

| Paket | Inhalt | Dateien (nur diese ändern) |
|---|---|---|
| **S0 · Vertrag** (Hauptsession, vorab) | Öffentliche API-Stubs, auf die B2 und B3 bauen | `Sources/IndoorCoachKit/Bridge/BridgeContract.swift`, `Keychain.Key.bridgeSecret` |
| **B1 · Kit: Protokoll, Transport, Ordner** (Sonnet) | Framer, Nachrichten-Codec, PSK/TLS, `BridgeServer`, `BridgeClient`, `RideFolderScanner`, `BridgeOutbox`. TDD inkl. Loopback-Integrationstest Server↔Client auf 127.0.0.1. | `Sources/IndoorCoachKit/Bridge/*` (außer Vertragsdatei: nur Implementierung der Stubs, Signaturen bleiben), `Tests/…/Bridge*Tests.swift` |
| **B2 · iOS: Anreicherung, Abgleich, UI** (Sonnet) | `RideMerge` (Domain) und Umbau von `storeImportedRides`/`importFITFiles` auf Anreichern; `AppModel+Bridge.swift` (Kopplung, Geheimnis im Schlüsselbund, Auto-Abgleich im Vordergrund, Banner); `MacBridgeView` (Anleitung, Suche, Code, Status, Lösen); Einstiege in Leistung und Profil; Abzeichen „Sekundendaten“ in der Fahrtliste; `.fit`-Dokumenttyp + `onOpenURL`; Info.plist (`NSLocalNetworkUsageDescription`, `NSBonjourServices`); Debug-Stub `-uiBridgeStub YES`; Unit- und UI-Tests (test33, test34). | `Domain/RideMerge.swift`, `Store/AppModel+Bridge.swift`, `Store/AppModel.swift` (nur Import-Funktionen + Keys), `UI/MacBridgeView.swift`, `UI/PerformanceView.swift`, `UI/ProfileView.swift`, `UI/HistoryView.swift`, `UI/RootView.swift`, `App/IndoorCoachApp.swift`, `Config/Info.plist`, Tests |
| **B3 · macOS: IndoorCoach Brücke** (Sonnet) | Neues Target `IndoorCoachBridge` (macOS 15, `LSUIElement`, Sandbox: user-selected read-only, app-scope bookmarks, network server/client) per `xcodeproj`-Skript; `MenuBarExtra` + Einrichtungsfenster (Ordner freigeben mit vorbelegtem Pfad, Code anzeigen, Login-Item); Ordner-Abfrage alle 20 s; Statusanzeige; Debug-Argumente `-bridgeFolder <Pfad>`, `-bridgePairingCode <Code>`. | `Bridge/` (neuer Ordner auf Repo-Ebene), `IndoorCoach.xcodeproj/project.pbxproj` (nur neues Target), `scripts/add-bridge-target.rb` |
| **Integration** (Hauptsession) | Merge, End-to-End-Test Brücke auf diesem Mac ↔ App im Simulator mit echten FIT-Testdateien, UX-Prüfung, CI-Build für das Mac-Target, Doku, README | – |

**Nicht im Umfang:** iCloud-Transport (B24), Verteilung der Mac-App über den App Store (eigenes Release-Thema), Live-Aufzeichnung über Bluetooth (C), Windows-Brücke.

**Regeln wie im Paket „Öffnung“:**
- Jeder Subagent arbeitet in einem eigenen Worktree und beginnt mit `git merge --ff-only main`.
- Zuerst kommen die Tests.
- Signaturen aus `BridgeContract.swift` bleiben unverändert. Fehlt etwas, kommt es additiv in die eigene Datei, mit Kommentar `ANCHOR-BRIDGE`.
- Keine echten Zugangsdaten.
- Commits in Worktrees ohne Push.
