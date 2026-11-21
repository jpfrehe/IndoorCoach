# 20 · Konzept: Einführung mit passenden Diensten

Stand: 21.11.2026 · erarbeitet mit einem UX-Engineer-Agent · Status: **Konzept, noch nicht freigegeben** (Entscheidungen für den Produktinhaber in §12)

**Auftrag (Produktinhaber):** Die Einführung beim ersten Start soll zu den neuen Diensten passen. Der Nutzer wird dabei begleitet und kann die Dienste, die zu ihm passen, gleich verbinden. Kein Dienst ist Pflicht. Auch wer intervals.icu oder die Mac-Brücke nicht kennt, soll erkennen, was ihm nützt. Ziel ist, dass jeder im Winterloch die App gut nutzen kann, auch ohne Technikwissen.

**Ziel in einem Satz:** Zwei kurze Fragen in Alltagssprache, danach eine persönliche Liste „Für dich passt“ mit je einem Satz Nutzen und einem Knopf zum Verbinden. Alles lässt sich überspringen, und nichts sieht nach Formular aus.

**Nicht-Ziele:** kein Konto bei IndoorCoach und kein eigener Server. Keine neue Anbindung (Zwift über den Mac bleibt laut docs/19 zurückgestellt). Strava wird im Intro nicht eingerichtet. Kein Tracking der Antworten.

---

## 1. Ist-Stand und Probleme

Die Einführung hat heute 5 Schritte (`OnboardingStep`): Willkommen → Dein Training → Trainings-App → Coach → Fertig. Der Schritt wird in `onboarding.step.v2` gespeichert, das Ende liefert `OnboardingChoice` (`.strava`, `.tour`, `.start`, `.skipped`).

| # | Befund | Folge für Nicht-Techniker |
|---|---|---|
| I1 | „Trainings-App“ kennt nur MyWhoosh. Wer Zwift oder Rouvy fährt, sieht keinen eigenen Weg, nur den Link „Strava oder FIT-Dateien?“. | Zwift-Fahrer glauben, die App sei nichts für sie, oder landen bei Strava (Client-ID, Abo). |
| I2 | intervals.icu, Mac-Brücke, Apple Health und Brustgurt tauchen im Intro gar nicht auf. | Die besten Wege für Zwift (intervals.icu) und für die volle Leistungskurve (Mac-Brücke) bleiben unentdeckt. |
| I3 | Der Strava-Link beendet die Einführung mitten im Ablauf und öffnet eine Seite mit Client-ID und Client-Secret. | Die schwerste Hürde liegt direkt hinter dem freundlichsten Link. |
| I4 | Willkommen verspricht „Jede Einheit geht direkt zu MyWhoosh“. | Das stimmt für Zwift- oder Rouvy-Fahrer nicht. |
| I5 | Der Coach-Schritt beginnt mit „eigener API-Key“ und zeigt sofort die Anleitung samt Eingabefeld. | Fachwort und Kostenangst, bevor klar ist, dass es auch ohne geht. |
| I6 | „Überspringen“ oben beendet die ganze Einführung sofort, auf jedem Schritt. | Wer eine einzelne Frage überspringen will, verliert den ganzen Rest. Das wird mit Fragen häufiger passieren. |
| I7 | `connectIntervals` meldet Fehler nur über den Banner (`show`). Der liegt in `RootView` **hinter** dem Vollbild der Einführung. | Ein intervals.icu-Fehler im Intro wäre unsichtbar. MyWhoosh hat dafür schon `lastMyWhooshError`. |
| I8 | Die Mac-Brücke gibt es nur per Skript oder Xcode (docs/03 §5). | Für normale Nutzer gibt es heute keinen Weg, die Mac-App zu bekommen (siehe Entscheidung E1). |

---

## 2. Personas

Alle fünf trainieren im Winter drinnen. Die ersten vier sind die Zielgruppe, die fünfte ist der Randfall, der nicht ausgebremst werden darf.

| | **P1 Sabine, 52** | **P2 Tobias, 34** | **P3 Claudia, 41** | **P4 Murat, 29** | **P5 Jan (Entwickler)** |
|---|---|---|---|---|---|
| Kurzprofil | Sachbearbeiterin, fährt im Sommer Touren mit dem Rennradtreff | Projektleiter, Zwift-Gruppenfahrten, will mehr Struktur | Läuft und fährt draußen, im Winter 2× pro Woche auf der Rolle | Einsteiger, hat eine gebrauchte Rolle gekauft, Fitnessstudio | baut die App, ambitionierter Hobbyfahrer |
| Geräte | MacBook der Familie, Wahoo KICKR Core, iPhone 13 mini | Apple TV, Smart-Trainer, iPhone 16, Garmin Edge (Sommer) | Garmin Forerunner, Brustgurt HRM-Dual, Rolle ohne Steuerung, iPhone SE (3. Gen.) | iPhone 15, Brustgurt aus dem Studio, einfache Rolle | Mac, iPhone, Brustgurt, alles |
| Apps | MyWhoosh (auf dem Mac) | Zwift, Strava | Garmin Connect, Strava | keine | MyWhoosh, Strava (eigene API-App), Claude, intervals.icu |
| Ziel | im Frühjahr mit dem Treff mithalten, ohne zu grübeln, was heute dran ist | gezielte Einheiten statt nur Rennen, Plan soll in Zwift auftauchen | dranbleiben, nicht zu viel und nicht zu wenig | das Winterloch überstehen, Rad und Kraft kombinieren | alles verbinden, schnell durch |
| Ängste und Hürden | Passwort in eine fremde App tippen; „Ordner freigeben“ und „Code koppeln“ klingen nach IT; Angst, etwas kaputtzumachen | noch ein Konto; weiß nicht, was intervals.icu ist; Daten doppelt; Apple TV kann man nicht „verbinden“ | wenig Zeit; Fachbegriffe; hat schon Strava und fragt sich, warum das nicht reicht | fühlt sich nicht als „richtiger Radfahrer“; FTP sagt ihm nichts; jede Frage nach einer App, die er nicht hat, verunsichert ihn | lange Einführung; Fragen, deren Antwort er kennt |
| Dienste, die wirklich nützen | **MyWhoosh** (Pläne hin, Fahrten zurück), **Mac-Brücke** (volle Leistungskurve, sobald verteilbar), evtl. Apple Health | **intervals.icu** (Pläne landen in Zwift, Fahrten mit Sekundendaten kommen zurück) | **Apple Health** (Garmin Connect schreibt Workouts nach Health), **Brustgurt**, optional intervals.icu (Einheiten auf den Edge) | **Brustgurt** (Puls bei Kraft und Aufzeichnung), optional Apple Health | alle; er richtet sie lieber selbst unter Dienste & Geräte ein |
| Nützt nicht oder schadet | intervals.icu (zusätzliches Konto ohne Gewinn), Strava | MyWhoosh, Mac-Brücke (kein Mac, Zwift-über-Mac ist zurückgestellt), Strava im Intro | MyWhoosh, Mac-Brücke, Strava (Client-ID und Abo) | alles mit Konto; Claude-Key am ersten Tag | Pflichtfragen, Erklärtexte ohne Abkürzung |
| Was das Intro leisten muss | Mut machen: „Passwort wird nicht gespeichert“; Mac-Brücke ohne IT-Sprache erklären und einen Weg auf den Mac zeigen | intervals.icu in einem Satz erklären, OAuth direkt aus dem Intro, danach der eine Schritt in intervals.icu („Zwift verbinden“) | ehrlich sagen, warum Strava hier nicht der Weg ist; System-Dialog Health vorher erklären | „Noch keine App“ ist eine gute Antwort; die App funktioniert ohne jede Verbindung | „Alle Dienste zeigen“ und „Überspringen“ ohne Umweg |

**Varianten, die die Regeln abdecken müssen:** MyWhoosh auf iPad, Apple TV oder Windows-PC (keine Mac-Brücke). Rouvy statt Zwift (gleicher Weg über intervals.icu). Apple Watch statt Garmin (Apple Health als Empfehlung). „Andere App“ wie TrainerRoad oder Wahoo SYSTM (FIT-Import, intervals.icu optional).

---

## 3. Leitprinzipien

1. **Fragen nach dem Alltag, nicht nach Diensten.** Gefragt wird „Womit fährst du drinnen?“, nicht „Willst du intervals.icu?“. Den passenden Dienst leitet die App ab.
2. **Nur fragen, was die Empfehlung ändert.** Die Frage nach dem Gerät erscheint nur, wenn jemand MyWhoosh fährt und die Mac-Brücke verfügbar ist. Für Zwift spielt das Gerät heute keine Rolle, weil intervals.icu auf jedem Gerät funktioniert.
3. **Jede Antwort ist erlaubt.** „Weiß ich nicht“, „Noch keine App“, „Nichts davon“ und „keine Angabe“ führen alle zu einem sinnvollen Ergebnis.
4. **Ein Satz Nutzen pro Dienst**, in den Worten der Nutzerin: „Damit landen deine Einheiten automatisch in Zwift.“ Erst danach kommt, was es braucht.
5. **Verbinden ohne die Einführung zu verlassen:** MyWhoosh-Login und intervals.icu-Anmeldung inline, Health und Brustgurt mit Erklärung vor dem System-Dialog, Mac-Brücke und Brustgurt als Blatt über dem Intro.
6. **Ehrlich bei Hürden.** Strava braucht eine eigene API-App und ein Abo, die Mac-Brücke eine Mac-App, Claude Guthaben. Das steht da, kurz und ohne Schönfärberei.
7. **Nichts ist Pflicht, nichts verschwindet.** Alles Übersprungene steht am Ende in der Zusammenfassung mit dem genauen Ort: Profil → Dienste & Geräte.
8. **Schlank:** 7 Schritte mit fester Seitenanzeige. Zusätzliche Inhalte erscheinen innerhalb eines Schritts, es kommen keine Schritte dazu.

---

## 4. Erweiterte User Journey

### 4.1 Schritte im Überblick

| # | Schritt (`OnboardingStep`) | Inhalt | immer sichtbar? | Neu/geändert |
|---|---|---|---|---|
| 0 | `welcome` · Willkommen | Hero, 3 Nutzenversprechen, „Kein Konto bei uns nötig“ | ja | Text geändert (I4) |
| 1 | `training` · Dein Training | FTP, Gewicht, Trainingstage, Wochenbudget | ja | unverändert |
| 2 | `rides` · Womit fährst du drinnen? | Frage 1 (Mehrfachauswahl); bei MyWhoosh die Folgefrage „Worauf läuft MyWhoosh?“ im selben Schritt; Link „Alle Dienste zeigen“ | ja, Folgefrage nur bei Bedarf | neu |
| 3 | `extras` · Was hast du sonst noch? | Frage 2 (Mehrfachauswahl): Apple Watch, Garmin/Wahoo, Brustgurt, Strava | ja | neu |
| 4 | `services` · Für dich passt | Empfehlungen als Karten mit Verbinden/Später; darunter „Auch möglich“, „Für Fortgeschrittene“ und eingeklappt „Alle Dienste“ | ja, Inhalt persönlich | ersetzt „Trainings-App“ |
| 5 | `coach` · Dein Coach | optional; zuerst der Unterschied mit/ohne Claude, die Einrichtung erst auf Wunsch | ja | neu geordnet (I5) |
| 6 | `done` · Alles bereit | Zusammenfassung mit gewählten Diensten und Orten für Übersprungenes, Tour/Start | ja | erweitert |

Die Seitenanzeige zeigt immer „Schritt n von 7“. Wer „Alle Dienste zeigen“ wählt, springt von 2 direkt zu 4. Die Anzeige springt dann mit.

### 4.2 Emotionskurve und Abbruchrisiken

Skala: −2 (frustriert) bis +2 (begeistert). Erwarteter Verlauf für P1/P2/P4 mit dem neuen Intro, in Klammern der heutige Verlauf.

| Schritt | Was die Nutzerin denkt | Emotion | Abbruchrisiko | Gegenmaßnahme |
|---|---|---|---|---|
| 0 Willkommen | „Sieht freundlich aus. Brauche ich ein Konto?“ | +1 (+1) | gering | „Kein Konto bei IndoorCoach nötig. Alles Weitere ist freiwillig.“ |
| 1 Dein Training | „FTP? Keine Ahnung.“ | 0 (0) | mittel bei P4 | „Weiß ich nicht“ schätzt den Wert (vorhanden); Hinweis „Alles lässt sich später ändern“ |
| 2 Womit fährst du? | „Ah, meine App ist dabei.“ / „Ich hab keine, ist das okay?“ | +1 (heute −1 bei Zwift) | gering | bekannte Namen als große Kacheln; „Noch keine App“ ist eine gleichwertige Kachel; kein Pflichtfeld |
| 2b Worauf läuft MyWhoosh? | „Einfach: Mac.“ | +1 | gering | erscheint nur bei MyWhoosh und Mac-Brücke verfügbar; „Weiß ich nicht“ möglich |
| 3 Was hast du sonst noch? | „Apple Watch, ja.“ | +1 | gering | „Nichts davon“ ist eine eigene Kachel |
| 4 Für dich passt | „Die App versteht mich.“, dann beim Verbinden: „Passwort? intervals.icu? Was ist das?“ | +2 → 0 | **hoch** (Passwort-Angst, unbekannter Dienst, Wechsel in den Browser, Mac-App fehlt) | je Karte ein Nutzen-Satz, Hürde ehrlich, „Später“ gleichwertig; MyWhoosh: „Passwort wird nicht gespeichert“; intervals.icu: „kostenlos“ und „Konto anlegen geht auf der Anmeldeseite“; Mac-Brücke: Link an den Mac schicken statt Sackgasse; Fortsetzen nach Neustart |
| 5 Dein Coach | „Kostet das was?“ | 0 (heute −1) | mittel | zuerst „Ohne Claude: Beispielplan, kostenlos“; Kosten in Cent; Einrichtung eingeklappt |
| 6 Alles bereit | „Geschafft, und ich weiß, wo der Rest ist.“ | +2 (+1) | gering | grüne Haken für Verbundenes, „Später unter …“ für den Rest, Tour als Hauptaktion |

**Kritische Momente im Detail:**

| Moment | Risiko | Lösung |
|---|---|---|
| Wechsel zur intervals.icu-Anmeldung (`ASWebAuthenticationSession`) | iOS zeigt „„IndoorCoach“ möchte „intervals.icu“ zum Anmelden verwenden“, die Nutzerin erschrickt; sie hat kein Konto | Satz vorher auf der Karte: „Gleich fragt iOS, ob die Anmeldeseite von intervals.icu öffnen darf. Tippe auf „Fortfahren“. Noch kein Konto? Das legst du dort kostenlos an.“ Abbruch durch die Nutzerin ist kein Fehler: Die Karte kehrt still in den Ausgangszustand zurück. |
| App wird während der Anmeldung beendet | Neustart von vorn wäre fatal | Schritt und Antworten sind gespeichert (§9). Die App startet wieder auf „Für dich passt“, die Karte ist im Ausgangszustand. |
| System-Dialog Health oder Bluetooth | Ablehnen aus Reflex | Erklärung auf der Karte bzw. im Gurt-Erklärblatt (`DevicesView`), Knopf „Weiter zur Freigabe“ statt „Erlauben“ |
| Mac-Brücke ohne Mac-App | Sackgasse auf dem iPhone | „Link an den Mac schicken“ (Teilen-Menü: AirDrop, Nachrichten, Mail). „Später“ verweist auf die vorhandene Karte unter Verlauf → Leistung. |
| Tastatur bei MyWhoosh-Login (iPhone SE) | Knopf unter der Tastatur | vorhandenes Muster: untere Leiste weicht der Tastatur, Scroll zu `MyWhooshLoginForm.loginButtonID` |

### 4.3 Pfade der Personas

| Persona | Schritt 2 | 2b | Schritt 3 | „Für dich passt“: empfohlen / auch möglich / Fortgeschrittene | Verbindet im Intro | Coach |
|---|---|---|---|---|---|---|
| P1 Sabine | MyWhoosh | Mac | Nichts davon | MyWhoosh, Fahrten im Detail vom Mac / – / – | MyWhoosh inline; Mac: „Link an den Mac schicken“ → später | ohne |
| P1-Variante (iPad) | MyWhoosh | iPad | Apple Watch | MyWhoosh, Apple Health / – / – | beide | ohne |
| P2 Tobias | Zwift | – | Strava | intervals.icu (mit Hinweis zu Strava) / – / Strava | intervals.icu per Anmeldung, danach Hinweis „Zwift in intervals.icu verbinden“ | evtl. |
| P3 Claudia | Noch keine App | – | Garmin/Wahoo, Brustgurt, Strava | Apple Health, Brustgurt / intervals.icu / Strava | Health (System-Dialog), Gurt im Blatt | ohne |
| P4 Murat | Noch keine App | – | Brustgurt | Brustgurt / – / – (dazu der Tipp „kostenlose Trainings-App“) | Gurt im Blatt oder später | ohne |
| P5 Jan | „Alle Dienste zeigen“ | – | (übersprungen) | – / alle verfügbaren / Strava | nichts oder MyWhoosh; Strava „nach der Einführung einrichten“ | Key einfügen |

---

## 5. Fragen und Empfehlungslogik (reine Kit-Funktion)

Die Logik liegt vollständig in `IndoorCoachKit/Sources/IndoorCoachKit/Domain/ServiceRecommender.swift`. Sie ist ohne SwiftUI, ohne `AppModel` und ohne Netzwerk testbar. Texte entstehen aus Reason-Codes, damit Tests die Codes prüfen und Texte änderbar bleiben.

### 5.1 Typen

```swift
public enum RideApp: String, Codable, CaseIterable, Sendable { case myWhoosh, zwift, rouvy, other, none }
public enum RideDevice: String, Codable, CaseIterable, Sendable { case mac, windows, tablet, appleTV, phone, unknown }
public enum ExtraGear: String, Codable, CaseIterable, Sendable { case appleWatch, garminWahoo, heartStrap, strava, none }

/// Antworten der Einführung. Leere Mengen = keine Angabe.
public struct ServiceAnswers: Codable, Equatable, Sendable {
    public var rideApps: Set<RideApp> = []
    public var myWhooshDevice: RideDevice? = nil     // nil = nicht gefragt oder nicht beantwortet
    public var extras: Set<ExtraGear> = []
    public var showAll = false                        // „Ich kenne mich aus – alle Dienste zeigen“
}

/// Was auf diesem Gerät/Build überhaupt angeboten werden kann (aus AppModel/AppConfig abgeleitet).
public struct ServiceAvailability: Equatable, Sendable {
    public var intervalsOAuth: Bool    // intervalsConfig.isOAuthAvailable
    public var bridgeDownload: Bool    // AppConfig.bridgeDownloadURL != nil (E1)
    public var health: Bool            // healthSource.isAvailable
}

public enum RecommendationTier: Int, Codable, Comparable, Sendable {
    case recommended = 0   // „Für dich passt“, oben, großer Verbinden-Knopf
    case optional = 1      // „Auch möglich“, sichtbar, kompakt
    case advanced = 2      // „Für Fortgeschrittene“, sichtbar, ohne Verbinden im Intro
    case more = 3          // eingeklappt unter „Alle Dienste“
}

public enum RecommendationReason: String, Codable, Sendable {
    case myWhooshPlansAndRides, bridgeMac, bridgeMaybeMac,
         intervalsZwift, intervalsRouvy, intervalsDevice, intervalsOther,
         healthWatch, healthGarmin, strapPulse, stravaAdvanced,
         fitOther, fitNoIntervals, catalog
}

public struct ServiceRecommendation: Identifiable, Equatable, Sendable {
    public let id: ConnectionID
    public let tier: RecommendationTier
    public let reasons: [RecommendationReason]   // in Regelreihenfolge, ohne Dubletten
    public let benefit: String                    // genau ein Satz (§5.5)
    public let note: String?                      // Zusatzhinweis, z. B. Strava-Lücke bei intervals.icu
}

public enum ServiceRecommender {
    public static func normalized(_ answers: ServiceAnswers) -> ServiceAnswers
    public static func asksDevice(_ answers: ServiceAnswers, _ availability: ServiceAvailability) -> Bool
    public static func recommend(_ answers: ServiceAnswers, _ availability: ServiceAvailability) -> [ServiceRecommendation]
    public static let maxRecommended = 4
}
```

### 5.2 Normalisierung (`normalized`, läuft am Anfang von `recommend`)

| Regel | Eingabe | Ergebnis |
|---|---|---|
| N1 | `rideApps` enthält `.none` und weitere | `.none` fällt weg (konkrete Angaben gewinnen) |
| N2 | `extras` enthält `.none` und weitere | `.none` fällt weg |
| N3 | `myWhooshDevice != nil`, aber `rideApps` ohne `.myWhoosh` | `myWhooshDevice = nil` |
| N4 | `showAll == true` | Antworten bleiben gespeichert, werden für die Stufen aber ignoriert (R15) |

In der Oberfläche sind „Noch keine App“ und „Nichts davon“ exklusiv: Wer sie antippt, hebt die anderen Kacheln auf, und umgekehrt. N1 und N2 sichern die Funktion trotzdem gegen widersprüchliche gespeicherte Daten ab.

### 5.3 Wann wird die Gerätefrage gestellt? (`asksDevice`)

`asksDevice = rideApps.contains(.myWhoosh) && availability.bridgeDownload && !showAll`

Begründung: Die Antwort ändert heute nur die Empfehlung der Mac-Brücke. Kommt „Zwift über den Mac“ (docs/19 Stufe 1), wird die Bedingung um `.zwift` erweitert und die Frage heißt „Worauf fährst du?“.

### 5.4 Regeltabelle

Jede Regel ist unabhängig. Treffen mehrere Regeln denselben Dienst, gilt die **beste** Stufe, und die Gründe werden in Regelreihenfolge gesammelt.

| Regel | Bedingung (nach Normalisierung) | Dienst | Stufe | Reason | Nutzen-Satz bzw. Beitrag |
|---|---|---|---|---|---|
| R1 | `rideApps ∋ myWhoosh` | `myWhoosh` | recommended | `myWhooshPlansAndRides` | „Deine Einheiten landen automatisch in MyWhoosh, deine Fahrten kommen von dort zurück.“ |
| R2 | `rideApps ∋ myWhoosh` ∧ `device == mac` ∧ `bridgeDownload` | `macBridge` | recommended | `bridgeMac` | „Jede Fahrt im Detail: Watt und Puls für jede Sekunde, ohne dass du etwas tun musst.“ |
| R3 | `rideApps ∋ myWhoosh` ∧ `device ∈ {nil, unknown}` ∧ `bridgeDownload` | `macBridge` | optional | `bridgeMaybeMac` | „Falls MyWhoosh auf einem Mac läuft: jede Fahrt im Detail, ganz automatisch.“ |
| – | `device ∈ {windows, tablet, appleTV, phone}` | – | – | – | keine Empfehlung der Mac-Brücke (nur `more` über R16) |
| R4 | `rideApps ∋ zwift` ∧ `intervalsOAuth` | `intervalsICU` | recommended | `intervalsZwift` | Ziel „Zwift“ |
| R5 | `rideApps ∋ rouvy` ∧ `intervalsOAuth` | `intervalsICU` | recommended | `intervalsRouvy` | Ziel „Rouvy“ |
| R6 | `extras ∋ garminWahoo` ∧ `intervalsOAuth` | `intervalsICU` | optional | `intervalsDevice` | Ziel „deinen Garmin- oder Wahoo-Radcomputer“ |
| R7 | `rideApps ∋ other` ∧ `intervalsOAuth` | `intervalsICU` | optional | `intervalsOther` | „Viele Trainings-Apps schicken Fahrten an intervals.icu – dann kommen sie auch hierher.“ |
| R7b | `rideApps ∋ other` | `fitImport` | optional | `fitOther` | „Fahrten als Datei aus deiner App übernehmen.“ |
| R8 | `extras ∋ appleWatch` ∧ `health` | `appleHealth` | recommended | `healthWatch` | „Ruhepuls, Schlaf und Workouts deiner Apple Watch zeigen dem Coach, wie erholt du bist.“ |
| R9 | `extras ∋ garminWahoo` ∧ `health` | `appleHealth` | recommended | `healthGarmin` | „Workouts aus Garmin Connect kommen über Apple Health auch hierher.“ |
| R10 | `extras ∋ heartStrap` | `strap` | recommended | `strapPulse` | „Dein Puls bei Krafttraining und Morgenmessung, direkt in der App, auch ohne Uhr.“ |
| R11 | `extras ∋ strava` | `strava` | advanced | `stravaAdvanced` | „Braucht eine eigene Strava-Entwickler-App und seit Juni 2026 ein Strava-Abo. Einrichten kannst du es nach der Einführung.“ |
| R12 | `extras ∋ strava` ∧ intervals.icu durch R4–R7 empfohlen | `intervalsICU` | – | – | `note`: „Wichtig: Verbinde Zwift (bzw. Rouvy) in intervals.icu direkt. Fahrten, die nur über Strava ankommen, gibt intervals.icu nicht weiter.“ |
| R13 | `rideApps ∋ zwift ∨ rouvy` ∧ `!intervalsOAuth` | `fitImport` | optional | `fitNoIntervals` | „Fahrten als Datei aus Zwift oder Rouvy übernehmen.“ |
| R14 | `rideApps == {none}` | – | – | – | keine Dienst-Empfehlung; Screen zeigt den Tipp (§6.5, Leerzustand bzw. Tipp-Zeile) |
| R15 | `showAll` | alle verfügbaren außer Strava | optional | `catalog` | Standardsatz je Dienst (§5.5); Strava `advanced` (R11-Text) |
| R16 | jeder verfügbare Dienst ohne Treffer | Dienst | more | `catalog` | Standardsatz je Dienst |

**Verfügbarkeit:** Ist `health == false`, erscheint `appleHealth` in keiner Stufe. Bei `intervalsOAuth == false` fehlt `intervalsICU` im Intro ganz, denn der API-Schlüssel ist für Nicht-Techniker kein Weg. Er bleibt unter Dienste & Geräte. Bei `bridgeDownload == false` fehlt `macBridge` im Intro ganz.

### 5.5 Zusammenführen, Texte, Reihenfolge

- **Ein Eintrag pro `ConnectionID`.** Die Stufe ist das Minimum aller Treffer, die Gründe stehen in Regelreihenfolge (R1 … R16) ohne Dubletten.
- **intervals.icu-Satz aus Zielen:** Jedes Ziel aus R4, R5 und R6 bekommt seine Präposition („in Zwift“, „in Rouvy“, „auf deinem Garmin- oder Wahoo-Radcomputer“). Die Teile werden mit `Formatters.germanList` verbunden („A“, „A und B“, „A, B und C“): „Damit landen deine Einheiten automatisch in Zwift und auf deinem Garmin- oder Wahoo-Radcomputer.“ Kommt nur R7, gilt der R7-Satz.
- **Health-Satz:** Treffen R8 und R9 zu, gilt der R8-Satz, ergänzt um „… und auch Workouts aus Garmin Connect.“
- **Standardsätze (R15/R16):** MyWhoosh = R1-Satz; intervals.icu = „Kostenloser Trainingskalender: schickt deine Einheiten an Zwift, Rouvy, Garmin oder Wahoo.“; Mac = R2-Satz; Health = „Erholung und Workouts aus der Health-App.“; Brustgurt = R10-Satz; FIT = „Fahrten als Datei aus jeder Trainings-App übernehmen.“
- **Reihenfolge innerhalb einer Stufe:** `myWhoosh, intervalsICU, macBridge, appleHealth, strap, fitImport, strava` (Wichtigkeit für den Wochenplan: zuerst Pläne/Fahrten, dann Erholung, dann Geräte).
- **Obergrenze:** höchstens `maxRecommended = 4` Empfehlungen. Weitere rutschen in der obigen Reihenfolge nach `optional`. Beispiel: MyWhoosh+Mac+Zwift+Watch+Gurt → der Gurt wird `optional`.
- **Ausgabe:** sortiert nach `(tier, Reihenfolge)`. `fitImport` erscheint nie als `recommended`.

### 5.6 Randfälle (müssen Unit-Tests werden)

| Fall | Erwartung |
|---|---|
| alles leer (keine Angabe) | keine `recommended`, alle verfügbaren Dienste als `more`, Strava `more` |
| `rideApps = {none}`, `extras = {none}` | nur `more`; Screen zeigt den Leerzustand |
| `{none, zwift}` (inkonsistent gespeichert) | wie `{zwift}` (N1) |
| MyWhoosh, Gerät nicht beantwortet, Brücke verfügbar | Brücke `optional` (R3) |
| MyWhoosh, `device = .tablet` | keine Empfehlung der Brücke; sie steht nur unter „Alle Dienste“ (`more`, R16), damit Fortgeschrittene sie finden |
| Gerät gesetzt, aber MyWhoosh abgewählt | Gerät ignoriert (N3) |
| Zwift ohne OAuth-Client | kein intervals.icu, `fitImport` optional (R13) |
| Zwift + Rouvy + Garmin | ein intervals.icu-Eintrag `recommended`; Satz: „Damit landen deine Einheiten automatisch in Zwift, in Rouvy und auf deinem Garmin- oder Wahoo-Radcomputer.“ (jedes Ziel mit eigener Präposition, dann `germanList`) |
| Strava allein | Strava `advanced`, nie `recommended`, auch nicht mit `showAll` |
| Health nicht verfügbar + Apple Watch | kein Health-Eintrag; keine Fehlermeldung |
| 5 Treffer | 4 `recommended`, der fünfte `optional` |
| `showAll` mit Antworten | Antworten ignoriert, alle `optional`, Strava `advanced` |

---

## 6. Screen-für-Screen-Spezifikation

**Gemeinsam für alle Schritte (wie heute):** `ScrollView` mit `.frame(maxWidth: 560)`, `Theme.canvas`. Top-Bar: „Zurück“ (Chevron, bei AX nur Symbol, `onboarding.back`) und „Überspringen“ (`onboarding.skip`), höchstens bis AX2. Untere Leiste: `.jelly` für die Hauptaktion, `.soft` für „ohne …“, darunter `PageIndicator`, höchstens bis AX3. Die Leiste weicht der Tastatur. Der Titel bekommt bei jedem Schrittwechsel den VoiceOver-Fokus (`titleFocused`). Bei laufender Verbindung (`connectBusy`) sind Zurück und Überspringen deaktiviert.

**Geändert: „Überspringen“ (I6).** Der Knopf springt zu Schritt 6 „Alles bereit“, statt die Einführung sofort zu schließen. Dort steht, was fehlt und wo man es findet. Der Hinweis lautet neu: „Springt zur Zusammenfassung. Alles lässt sich später im Profil einrichten.“ `OnboardingChoice.skipped` entfällt. Für P5 kostet das einen Tipp mehr (Überspringen → Direkt starten), dafür verliert niemand versehentlich den ganzen Rest (Entscheidung E3).

### 6.1 Schritt 0 · Willkommen

- **Titel:** „Willkommen bei IndoorCoach“
- **Punkte (Label mit Symbol):**
  - `sparkles` „Dein Coach plant deine Woche – passend zu deinen Fahrten.“
  - `snowflake` „Im Winter Arc baust du Fitness auf bis zum Frühjahr.“
  - `square.and.arrow.up` „Deine Einheiten landen direkt in deiner Trainings-App, etwa MyWhoosh oder Zwift.“
- **Fußzeile (secondary):** „Kein Konto bei IndoorCoach nötig. Alles, was du gleich verbindest, ist freiwillig.“
- **Untere Leiste:** „Los geht’s“ (`.jelly`, `onboarding.next`)
- **AX:** Hero entfällt bei AX-Größen (wie heute).

### 6.2 Schritt 1 · Dein Training

Unverändert (Identifier `onboarding.ftp`, `onboarding.ftpUnknown`, `onboarding.weight`, `onboarding.weeklyHours`, Wochentage). „Weiter“ bleibt ohne Trainingstag deaktiviert.

### 6.3 Schritt 2 · Womit fährst du drinnen?

- **Titel:** „Womit fährst du drinnen?“
- **Lead:** „Tippe alles an, was passt. So zeigen wir dir nur, was dir wirklich hilft.“
- **Kachelraster** (`ChoiceChipGrid`, neu, wiederverwendbar): 2 Spalten, bei AX-Größen 1 Spalte. Jede Kachel ist mindestens 44 pt hoch und zeigt Symbol, Name und ggf. eine Zweitzeile. Gewählt: `Theme.sunset`-Fläche **und** Häkchen-Symbol, nie nur Farbe. Exklusive Kachel wie in §5.2.

| Kachel | Zweitzeile | Symbol | Identifier |
|---|---|---|---|
| MyWhoosh | – | `figure.indoor.cycle` | `onboarding.ride.myWhoosh` |
| Zwift | – | `figure.indoor.cycle` | `onboarding.ride.zwift` |
| Rouvy | – | `figure.indoor.cycle` | `onboarding.ride.rouvy` |
| Andere App | „z. B. TrainerRoad“ | `app.badge` | `onboarding.ride.other` |
| Noch keine App | „nur Rolle oder weiß nicht“ | `questionmark.circle` | `onboarding.ride.none` |

Keine App-Logos, denn das sind fremde Marken (Review-Guideline 5.2.1). Die Namen genügen und sind barrierefrei.

- **Folgefrage im selben Schritt** (nur wenn `asksDevice`): erscheint unter dem Raster mit kurzer Einblendung (ohne Bewegung bei „Bewegung reduzieren“). Die Ansicht scrollt zu ihr (`proxy.scrollTo("onboarding.deviceQuestion")`), und VoiceOver hört „Neue Frage: Worauf läuft MyWhoosh bei dir?“.
  - **Überschrift:** „Worauf läuft MyWhoosh bei dir?“
  - **Kacheln (Einfachauswahl, Radio-Verhalten):** Mac (`laptopcomputer`) · Windows-PC (`pc`) · iPad oder Tablet (`ipad`) · Apple TV (`appletv`) · Handy (`iphone`) · Weiß ich nicht (`questionmark.circle`). Identifier `onboarding.device.<rawValue>`.
  - **Hinweis unter „Mac“, wenn gewählt:** „Gut: Dann kann ein kleiner Helfer auf dem Mac jede Fahrt im Detail ans iPhone schicken. Mehr dazu gleich.“
- **Link unten (Theme.accent, 44 pt):** „Ich kenne mich aus – alle Dienste zeigen“ (`onboarding.showAll`). Setzt `showAll = true` und springt zu Schritt 4.
- **Tipp bei „Noch keine App“** (hint-Stil): „Kein Problem. IndoorCoach plant deine Woche auch so. Tipp: Mit einer kostenlosen App wie MyWhoosh stellt sich deine Rolle selbst auf die richtigen Watt ein, falls sie das kann.“
- **Untere Leiste:** mit Auswahl „Weiter“ (`.jelly`, `onboarding.next`), ohne Auswahl „Weiter ohne Angabe“ (`.soft`, `onboarding.next`).
- **VoiceOver:** Die Gruppe hat das Label „Womit fährst du drinnen? Mehrere Antworten möglich“. Jede Kachel ist ein Button mit `.isSelected` und dem Hinweis „Mehrfachauswahl“ bzw. „Hebt die anderen Antworten auf“ bei „Noch keine App“. Die Gerätekacheln haben den Hinweis „Eine Antwort“.
- **iPhone SE / AX5:** 1 Spalte, Zweitzeile umbrechend (`fixedSize(horizontal: false, vertical: true)`). Die letzte Kachel muss sich über die untere Leiste scrollen lassen (vgl. Harness-Funktion `lift`).

### 6.4 Schritt 3 · Was hast du sonst noch?

- **Titel:** „Was hast du sonst noch?“
- **Lead:** „Auch das hilft dem Coach. Mehrere Antworten möglich.“

| Kachel | Zweitzeile | Symbol | Identifier |
|---|---|---|---|
| Apple Watch | – | `applewatch` | `onboarding.extra.appleWatch` |
| Garmin oder Wahoo | „Uhr oder Radcomputer“ | `watch.analog` | `onboarding.extra.garminWahoo` |
| Brustgurt | „misst den Puls“ | `heart.circle` | `onboarding.extra.heartStrap` |
| Strava | – | `figure.outdoor.cycle` | `onboarding.extra.strava` |
| Nichts davon | – | `minus.circle` | `onboarding.extra.none` (exklusiv) |

- **Untere Leiste:** wie Schritt 2.
- **Wird übersprungen**, wenn `showAll` gesetzt ist (Zurück von Schritt 4 führt dann zu Schritt 2).

### 6.5 Schritt 4 · Für dich passt

- **Titel:** „Für dich passt“ (bei `showAll`: „Alle Dienste“)
- **Lead:** „Verbinde, was du möchtest. Nichts davon ist Pflicht, alles geht auch später.“
- **Abschnitte:**
  1. Empfohlene Karten (`recommended`), aufgeklappt mit großem Verbinden-Knopf.
  2. „Auch möglich“ (`optional`), Karten eingeklappt: Name, Nutzen-Satz, Knopf „Ansehen“ klappt sie auf.
  3. „Für Fortgeschrittene“ (`advanced`), nur Strava.
  4. „Alle Dienste anzeigen“ (`onboarding.moreServices`, DisclosureGroup) mit den `more`-Einträgen.
- **Leerzustand** (keine `recommended`/`optional`): Card mit `checkmark.seal` „Für den Start brauchst du nichts zu verbinden. IndoorCoach plant deine Woche auch so, und du hakst Einheiten einfach ab.“ Darunter „Alle Dienste anzeigen“.
- **Akkordeon:** Es ist höchstens eine Karte aufgeklappt, wenn sie ein Formular enthält (MyWhoosh). So bleibt die Seite auf dem SE und bei AX übersichtlich, und die Tastatur verdeckt nur ein Formular.
- **Untere Leiste:** mindestens ein Dienst verbunden → „Weiter“ (`.jelly`, `onboarding.next`), sonst „Ohne Verbindung weiter“ (`.soft`, `onboarding.later` – Identifier bleibt aus Kompatibilität).

#### Komponente `ServiceRecommendationCard`

Basis ist `Card(title:systemImage:)`. Kopf: Name und rechts `ConnectionStatusLabel` (vorhanden: Symbol und Text). Darunter der Nutzen-Satz (`benefit`), ggf. `note` im Hinweisstil mit `info.circle`, dann Dienst-Inhalt und Aktionen.

| Zustand | Anzeige | Aktionen |
|---|---|---|
| offen | Nutzen, „Was du brauchst“-Zeile | Hauptaktion (`.jelly` bei `recommended`, `.soft` sonst), „Später“ (Textknopf) |
| läuft | `ProgressView` im Knopf, Knopftext „Verbinde …“ | alles andere deaktiviert, `connectBusy = true` |
| verbunden | `checkmark.circle.fill` (Theme.done) und „Verbunden · <Detail>“; VoiceOver-Ansage „<Dienst> verbunden“ | ggf. Folge-Hinweis (intervals.icu) |
| Fehler | `FormError`-Stil (rot, Symbol) mit Text aus `lastMyWhooshError` bzw. neu `lastIntervalsError` | Hauptaktion erneut, „Später“ |
| später | Karte klappt zu, Status „Später“ (`clock`-Symbol), Eintrag in `deferred` | „Doch jetzt“ öffnet sie wieder |

**Identifier:** `onboarding.service.<rawValue>` (Karte), `….connect`, `….later`, `….status`. Bei MyWhoosh bleibt der Status zusätzlich `onboarding.myWhooshStatus` (test29).
**VoiceOver:** Kopf als ein Element mit `"Empfohlen: <Name>. <Nutzen>. <Status>."`, Knöpfe einzeln. Bei `optional` beginnt das Label mit „Auch möglich“, bei `advanced` mit „Für Fortgeschrittene“.

#### Verbinden je Dienst im Intro

| Dienst | Karte (Microcopy) | Hauptaktion | Wie verbunden wird | Wiederverwendung |
|---|---|---|---|---|
| **MyWhoosh** | Nutzen R1. „Was du brauchst: dein MyWhoosh-Konto. Dein Passwort wird nur zur Anmeldung gesendet und nicht gespeichert.“ Darunter klein: „Meldest du dich bei MyWhoosh mit Google oder Apple an? Lege dort zuerst ein Passwort fest.“ | „Anmelden“ klappt das Formular auf | inline `MyWhooshLoginForm(busy:onConnected:onEditing:)`; danach „Verbunden · 23 Fahrten geladen“ | `MyWhooshLoginForm` unverändert; Status-Text wie heute im Schritt „Trainings-App“ |
| **intervals.icu** | Nutzen aus R4–R6. „intervals.icu ist ein kostenloser Trainingskalender. IndoorCoach legt deine Einheiten dort ab, intervals.icu schickt sie weiter.“ Vor dem Knopf: „Gleich fragt iOS, ob die Anmeldeseite von intervals.icu öffnen darf. Tippe auf „Fortfahren“. Noch kein Konto? Das legst du dort kostenlos an.“ | „Mit intervals.icu verbinden“ | inline: `model.connectIntervals { url in try await webAuth.authenticate(…) }` wie in `IntervalsConnectionView.login`, Rückgabe neu `Bool`; Abbruch durch Nutzer = still zurück in „offen“ | Login-Teil aus `IntervalsConnectionView` in `IntervalsOAuthButton` auslagern und an beiden Orten nutzen |
| ↳ nach dem Verbinden | Folge-Hinweis, nur bei R4/R5: „Noch ein Schritt in intervals.icu: Öffne Einstellungen → Connections, verbinde Zwift und schalte „Upload planned workouts“ ein. Dann erscheinen deine Einheiten in Zwift.“ (Ziel je nach Antwort: Zwift/Rouvy/Garmin) | Link „intervals.icu-Einstellungen öffnen“ (`onboarding.intervals.settings`, `https://intervals.icu/settings`) | `Toggle` „Neue Pläne automatisch senden“ (vorhanden `profile.autoSendToIntervals`, Standard an) | Text aus `IntervalsConnectionView.forwardText` (eine Quelle) |
| **Fahrten im Detail vom Mac** (Mac-Brücke) | Nutzen R2. Erklärung: „MyWhoosh speichert jede Fahrt sekundengenau auf deinem Mac. Ein kleiner Gratis-Helfer, die IndoorCoach Brücke, schickt sie im WLAN ans iPhone. Nichts verlässt dein Zuhause.“ „Was du brauchst: die Mac-App „IndoorCoach Brücke“.“ | „Link an den Mac schicken“ (`ShareLink(item: AppConfig.bridgeDownloadURL)`, `onboarding.bridge.share`) | AirDrop, Nachrichten oder Mail an sich selbst. Zweiter Knopf „Mac-App läuft schon – jetzt koppeln“ (`onboarding.bridge.pair`) öffnet ein Blatt mit `NavigationStack { MacBridgeView() }` und „Fertig“ in der Leiste; das Blatt schließt nach erfolgreicher Kopplung (`onChange(of: model.isBridgePaired)`) nach 1,5 s selbst. | `MacBridgeView` unverändert (erklärt das lokale Netzwerk schon) |
| ↳ „Später“ bei der Brücke | „Kein Problem. Sobald du Fahrten hast, erinnert dich Verlauf → Leistung daran.“ | – | nutzt die vorhandene Karte in `PerformanceView` („Volle Leistungskurve für jede Fahrt …“), **keine** Mitteilungs-Berechtigung | – |
| **Apple Health** | Nutzen R8/R9. „Gleich fragt iOS, was IndoorCoach aus Health lesen darf: Workouts, Puls und Gewicht. Du kannst jedes einzeln erlauben. Die Werte bleiben auf deinem iPhone und gehen nicht an den Coach.“ | „Weiter zur Freigabe“ (bewusst nicht „Erlauben“) | `await model.setHealthEnabled(true)` → System-Blatt. Danach Status „Freigabe erteilt“. HealthKit verrät nicht, was erlaubt wurde, also Zusatz: „Ändern kannst du das jederzeit in der Health-App unter Teilen → Apps.“ | `HealthSettingsControlling` (vorhanden) |
| **Brustgurt** | Nutzen R10. „Lege den Gurt an und befeuchte ihn kurz, dann findet das iPhone ihn.“ | „Gurt koppeln“ | Blatt mit `NavigationStack { DevicesView() }`. Dessen Erklärblatt („Nur dein Pulsgurt …“, Bluetooth-Abfrage) erscheint zuerst; „Fertig“ schließt. Status = `strap.savedStrapID != nil`. | `DevicesView` unverändert |
| **FIT-Dateien** | „FIT ist das Dateiformat, das fast jede Trainings-App exportieren kann.“ | „Dateien auswählen“ | `.fileImporter` wie in `ConnectionsView`, danach „n Fahrten übernommen“ | `model.importFITFiles` |
| **Strava** (Fortgeschrittene) | Text R11. Kein Formular im Intro. | Schalter „Nach der Einführung einrichten“ (`onboarding.service.strava.afterwards`) | merkt `stravaAfterwards = true`; „Alles bereit“ bietet dann „Strava jetzt einrichten“ → `OnboardingChoice.connection(.strava)` | Sprung über `pendingProfileRoute` (vorhanden) |

**Tastatur:** Nur MyWhoosh hat im Schritt ein Textfeld. Es gilt das vorhandene Muster: `keyboardVisible` blendet die untere Leiste aus, `onEditing` scrollt zum Anmelden-Knopf, `.scrollDismissesKeyboard(.interactively)`.
**Rückkehr aus dem Browser:** `ASWebAuthenticationSession` läuft über dem Vollbild. Nach der Rückkehr bleibt die Ansicht auf derselben Karte. Der Fokus liegt auf dem Status (`AccessibilityFocusState` je Karte).

### 6.6 Schritt 5 · Dein Coach (optional)

- **Titel:** „Dein Coach“
- **Lead:** „Den Wochenplan kann ein KI-Coach für dich schreiben. Das ist freiwillig.“
- **Card „So oder so“** (zwei Zeilen mit Symbol):
  - `doc.text` **Ohne Claude:** „Du bekommst einen fertigen Beispielplan, der sich an deine Trainingstage hält. Kostenlos.“
  - `sparkles` **Mit Claude:** „Ein KI-Coach plant jede Woche neu, passend zu deinen Fahrten und deiner Form. Etwa 10 Cent pro Plan.“
- **Disclosure-Knopf** „Claude jetzt einrichten“ (`onboarding.coach.setup`, `.soft`). Aufgeklappt:
  - Card „Was du brauchst“: „Ein Konto bei Anthropic, dem Anbieter von Claude, mit etwas Guthaben. Ein claude.ai-Abo reicht dafür nicht. Abgerechnet wird direkt zwischen dir und Anthropic, wir verdienen daran nichts.“
  - Card „So kommst du an den Schlüssel“: die vorhandenen 3 Schritte, Link `onboarding.consoleLink`, dazu der Satz „Der Schlüssel (API-Key) ist wie ein Passwort nur für IndoorCoach. Er bleibt im Schlüsselbund dieses iPhones.“
  - Card „Schlüssel“: `ClaudeKeyForm()` (vorhanden, `claude.key.*`).
  - Hinweis Datenschutz: „Für einen Plan schickt IndoorCoach deine Trainingsdaten (Fahrten, FTP, Trainingstage) an Anthropic. Gesundheitswerte nur, wenn du es später ausdrücklich erlaubst.“ (passt zu `ClaudeConsentSheet`)
- **Ist schon ein Key gespeichert,** steht die Einrichtung aufgeklappt mit „API-Key gespeichert“ da.
- **Untere Leiste:** Key vorhanden → „Weiter“ (`.jelly`, `onboarding.next`), sonst „Ohne Claude weiter“ (`.soft`, `onboarding.noClaude`).
- **Tastatur:** wie heute (Leiste weicht, Feld schließt beim Absenden).

### 6.7 Schritt 6 · Alles bereit

- **Titel:** „Alles bereit“
- **Lead:** „Das hast du eingerichtet. Den Rest findest du jederzeit unter Profil → Dienste & Geräte.“
- **Card Checkliste** (`statusRow`, je Zeile ein VoiceOver-Element, Identifier `onboarding.status.<id>`):

| Zeile | Wann sichtbar | Detail verbunden | Detail sonst |
|---|---|---|---|
| Profil (`profil`) | immer | „FTP 200 W · 3 Trainingstage“ | „Trainingstag fehlt“ |
| je Dienst (`<rawValue.lowercased()>`, z. B. `mywhoosh`, `intervalsicu`, `macbridge`, `applehealth`, `strap`) | wenn `recommended`, oder `optional` und angefasst, oder verbunden | „Verbunden · 23 Fahrten geladen“ / „Verbunden als Tobias“ / „Gekoppelt mit Sabines MacBook“ / „Freigabe erteilt“ / „Polar H10“ | „Später unter Profil → Dienste & Geräte → <Name im Hub>“ |
| Strava (`strava`) | wenn „nach der Einführung einrichten“ | – | „Richtest du gleich als Nächstes ein“ |
| Coach (`coach`) | immer | „Claude-Key gespeichert“ | „Beispielplan · Claude später unter Profil → Coach · Claude“ |

Im Intro heißt die Mac-Brücke „Fahrten im Detail vom Mac“. Der „Später“-Text nennt den Namen im Hub („Sekundendaten vom Mac“), damit die Nutzerin die Zeile dort wiederfindet.

- **Folge-Hinweis** (nur wenn intervals.icu verbunden wurde und R4/R5 galt): Card mit `arrow.turn.down.right`, Text „Denk an den einen Schritt in intervals.icu: Zwift verbinden.“ und Link (`onboarding.intervals.settings`).
- **Aktionen (untere Leiste):**
  1. Strava gemerkt → „Strava jetzt einrichten“ (`.jelly`, `onboarding.strava`), dann „Kurze Tour ansehen“ als `.soft`.
  2. sonst „Kurze Tour ansehen“ (`.jelly`, `onboarding.tour`) und „Direkt starten“ (`.soft`, `onboarding.start`).
- **Textlink über der Leiste** (nur wenn etwas „Später“ ist): „Übersprungenes jetzt einrichten“ (`onboarding.openConnections`) → `OnboardingChoice.connection(nil)` → Profil → Dienste & Geräte.

---

### 6.8 Identifier-Vertrag (verbindlich für UI und UI-Tests)

`<raw>` ist der `rawValue` der `ConnectionID` (`myWhoosh`, `intervalsICU`, `macBridge`, `appleHealth`, `strap`, `strava`, `fitImport`), `<low>` derselbe Wert klein geschrieben.

| Element | Identifier |
|---|---|
| Kacheln Schritt 2 / Folgefrage / Schritt 3 | `onboarding.ride.<RideApp>`, `onboarding.device.<RideDevice>`, `onboarding.extra.<ExtraGear>` (Auswahl über Trait `.isSelected`) |
| „Alle Dienste zeigen“ (Schritt 2) | `onboarding.showAll` |
| Weiter (alle Schritte, Text wechselt z. B. „Weiter ohne Angabe“) | `onboarding.next`; auf Schritt 4 ohne Verbindung stattdessen `onboarding.later` („Ohne Verbindung weiter“) |
| Zurück / Überspringen | `onboarding.back` / `onboarding.skip` (springt zu Schritt 6) |
| Abschnitte Schritt 4 | `onboarding.section.recommended`, `.optional`, `.advanced`; Aufklapper „Alle Dienste“ `onboarding.moreServices` |
| Dienstkarte | `onboarding.service.<raw>` (Container), `….connect` (Hauptknopf, bei Health „Weiter zur Freigabe“, beim Gurt „Gurt koppeln“, bei der Brücke „Einrichten“), `….later`, `….status` (Statuszeile), `….error` (Fehlertext im Intro) |
| Strava „Nach der Einführung einrichten“ | `onboarding.service.strava.afterwards` (Schalter) |
| Brücken-Blatt | `onboarding.bridge.share` (Link an den Mac schicken), `onboarding.bridge.pair` (Koppeln), Schließen `onboarding.sheet.done` |
| Gurt-Blatt | `strap.explainer.continue`, Schließen `onboarding.sheet.done` |
| intervals.icu nach Verbindung | Hinweis zur Weiterleitung mit Link `onboarding.intervals.settings` |
| Coach | `onboarding.coach.setup` (Aufklapper, Key-Feld `claude.key.field` erst danach sichtbar), `onboarding.noClaude`, `onboarding.consoleLink` |
| Alles bereit | `onboarding.status.profil`, `onboarding.status.coach`, `onboarding.status.<low>` je gewähltem/verbundenem Dienst, `onboarding.openConnections`, `onboarding.strava` (nur bei `stravaAfterwards`), `onboarding.tour`, `onboarding.start` |
| Seitenanzeige | `onboarding.pageIndicator`, Label „Schritt n von 7“ |

## 7. Coach/Claude neu eingeordnet (Kurzfassung)

| Frage der Nutzerin | Antwort im Intro |
|---|---|
| Brauche ich das? | Nein. Ohne Claude gibt es einen Beispielplan, der Trainingstage und Wochenbudget beachtet. |
| Was kostet es? | etwa 10 Cent pro Plan, direkt bei Anthropic, mit Guthaben. Das claude.ai-Abo zählt nicht. |
| Was ist ein API-Key? | „wie ein Passwort nur für IndoorCoach“, bleibt im Schlüsselbund |
| Was wird gesendet? | Trainingsdaten für den Plan; Gesundheitswerte nur nach eigener Einwilligung (`ClaudeConsentSheet`) |
| Später? | Profil → Coach · Claude (Zusammenfassung nennt den Ort) |

Die Einrichtung ist eingeklappt. Wer sie aufklappt, sieht dieselben Bausteine wie heute (`ClaudeKeyForm`, Anleitung, Console-Link).

---

## 8. Ende der Einführung (`OnboardingChoice`)

```swift
public enum OnboardingChoice: Sendable, Equatable {
    case tour                       // „Kurze Tour ansehen“
    case start                      // „Direkt starten“
    case connection(ConnectionID?)  // nil = Dienste & Geräte, .strava = Strava-Detailseite
}
```

In `RootView.onboardingCover`: `.connection(id)` → `tab = .profile`, `pendingProfileRoute = id.map { [.connections, .connection($0)] } ?? [.connections]`. `.strava` und `.skipped` entfallen.

---

## 9. Datenmodell und Persistenz

| Was | Wo | Warum |
|---|---|---|
| aktueller Schritt | `onboarding.step.v3` (Int, 0…6), in `Keys.all` | Fortsetzen nach Neustart. Neuer Schlüssel, weil sich die Bedeutung der Zahlen ändert. |
| Antworten und Entscheidungen | `onboarding.services.v1` (JSON `OnboardingServicesState`), in `Keys.all` | Fortsetzen mitten im Intro; Zusammenfassung; spätere Wiederverwendung in „Passende Dienste finden“ |
| Empfehlungen | **nicht** gespeichert | werden aus Antworten + `ServiceAvailability` berechnet; so veralten sie nicht, z. B. wenn die Brücke später verfügbar wird |
| Verbindungsstatus | **nicht** gespeichert | wie heute aus `connection(_:)` abgeleitet |

```swift
public struct OnboardingServicesState: Codable, Equatable, Sendable {
    public var answers = ServiceAnswers()
    public var deferred: Set<ConnectionID> = []   // „Später“ getippt
    public var stravaAfterwards = false
}
```

`ConnectionID` braucht dafür `Codable` (ist schon `String`-RawValue).

**Migration v2 → v3** (einmalig in `init`, rein und testbar als `static func migratedStep(v2: Int?) -> Int?`):

| v2-Schritt | Bedeutung | v3-Schritt |
|---|---|---|
| 0 | welcome | 0 |
| 1 | training | 1 |
| 2 | trainingApp | 2 (rides) |
| 3 | coach | 5 |
| 4 | done | 6 |

Danach wird `onboarding.step.v2` entfernt. `onboardingStepCount = 7`.

**Bestehende Nutzer:** Die Entscheidung über `onboarding.completed.v1` und `isExistingInstall` bleibt unverändert. Wer die Einführung abgeschlossen hat oder die App schon nutzte, sieht sie nicht wieder. Für diese Nutzer gibt es optional (AP6) den Einstieg „Welche Dienste passen zu mir?“ in Dienste & Geräte.

**Abschluss:** `completeOnboarding()` setzt wie heute den Schritt zurück. `OnboardingServicesState` bleibt erhalten (für AP6 und als Vorbelegung), „Alle Daten löschen“ entfernt ihn über `Keys.all`.

**Neu in `AppModel`:**
- `onboardingServices: OnboardingServicesState` (didSet speichert)
- `serviceAvailability: ServiceAvailability`
- `serviceRecommendations: [ServiceRecommendation]`
- `lastIntervalsError: String?` (wie `lastMyWhooshError`, I7)
- `connectIntervals(authenticate:) -> Bool` (`@discardableResult`)
- `onboardingSummary` erweitert um `services: [OnboardingSummary.ServiceLine]` (id, Name, Zustand `.connected(detail)` / `.later` / `.notConnected`) und `stravaAfterwards`

**Neu in `AppConfig`:** `bridgeDownloadURL: URL?`, solange nil (E1).

**Debug-Hooks für UI-Tests** (`#if DEBUG`, in `AppEnvironment.makeModel` bzw. `applyUITestOnboardingOverride`):
- `-uiOnboarding YES` setzt zusätzlich `onboardingServices` zurück.
- `-uiOnboardingStep n` startet direkt bei Schritt n.
- `-uiOnboardingAnswers "rides=myWhoosh;device=mac;extras=appleWatch"` belegt die Antworten vor.
- `-uiIntervalsStubLogin YES`: Die Web-Anmeldung wird durch eine Stub-Funktion ersetzt, die `indoorcoach://localhost/intervals?code=stub&state=<state>` liefert. `JourneyStubTransport` beantwortet den Token-Endpunkt und `athlete/0`.
- `-uiHealthStub YES`: `healthSource` ist ein Stub mit `isAvailable = true`, der die Anfrage sofort bestätigt.
- `-uiBridgeAvailable YES`: `serviceAvailability.bridgeDownload = true` mit einer Platzhalter-URL.

---

## 10. App Store und Datenschutz

| Punkt | Umsetzung im Intro |
|---|---|
| **Keine Pflichtkonten** (Guideline 5.1.1(v)) | Jeder Schritt hat einen Weg ohne Konto: „Weiter ohne Angabe“, „Ohne Verbindung weiter“, „Ohne Claude weiter“, „Überspringen“. Die App funktioniert vollständig mit Demo- bzw. Beispielplan. |
| **Erklärung vor System-Berechtigungen** (5.1.1, HIG „Requesting permission“) | Health: Erklärtext auf der Karte, Knopf „Weiter zur Freigabe“. Bluetooth: vorhandenes Erklärblatt in `DevicesView`. Lokales Netzwerk: Erklärung in `MacBridgeView`. Web-Anmeldung: Satz vor dem Knopf. Keine eigene Attrappe des System-Dialogs, kein „Erlauben“-Knopf vor dem echten Dialog. |
| **Ablehnen jederzeit** | „Später“ auf jeder Karte; Trennen auf jeder Detailseite (mit Rückfrage, vorhanden); Health in der Health-App änderbar (wird genannt). |
| **Transparenz** | Pro Dienst steht, was gesendet bzw. gelesen wird: MyWhoosh-Passwort nicht gespeichert; intervals.icu direkt an das eigene Konto; Health bleibt auf dem Gerät; Brücke bleibt im WLAN; Claude bekommt Trainingsdaten. |
| **Antworten der Fragen** | bleiben lokal in UserDefaults, werden nie gesendet, nicht geloggt (kein `Log` mit Antworten). Kein neuer Eintrag im Privacy Manifest, Datenschutzangabe bleibt „Keine Daten erfasst“. |
| **HealthKit** (5.1.3) | nur lesen; Werte gehen nicht an Claude ohne Einwilligung (vorhanden). Im Intro wird nichts geschrieben. |
| **Fremde Marken** (5.2.1) | nur Namen von MyWhoosh, Zwift, Rouvy, Garmin, Wahoo, Strava, keine Logos; keine Aussage, die eine Partnerschaft nahelegt. |
| **Anmelden mit Apple** (4.8) | nicht nötig: IndoorCoach hat kein eigenes Konto; Anmeldungen gelten den jeweiligen Diensten. |
| **Inoffizielle MyWhoosh-Schnittstelle** (5.2.2) | bekanntes Risiko (docs/13). Das Intro verspricht nichts darüber hinaus. Fällt die Schnittstelle weg, bleibt der FIT-Import. |
| **Strava** | wird im Intro nicht eingerichtet, Hürde wird offen benannt; kein Hinweis, der wie Werbung für ein Abo wirkt. |

---

## 11. Arbeitspakete (ECC, Tests zuerst)

Reihenfolge: AP1 → AP2 → (AP3 ∥ AP4) → AP5 → AP7. AP6 ist optional und folgt später. Geschätzter Umfang gesamt: M (3–4 Tage).

### AP1 · Empfehlungslogik im Kit (S)

- **Dateien:** neu `Domain/ServiceRecommender.swift` (Typen §5.1, `normalized`, `asksDevice`, `recommend`, Texte), `Formatters.germanList` in `Domain/Formatters.swift`, `ConnectionID: Codable`. Neu `Tests/IndoorCoachKitTests/ServiceRecommenderTests.swift`.
- **Abhängigkeiten:** keine.
- **Akzeptanz:** reine Funktionen ohne `AppModel`; jede Regel R1–R16 und jeder Randfall aus §5.6 durch mindestens einen Test abgedeckt; keine Texte in Tests außer den Grammatik-Tests.
- **Testfälle (Swift Testing, tabellengetrieben):**

| # | Eingabe (rides / device / extras / showAll · Verfügbarkeit) | Erwartung |
|---|---|---|
| T1 | `{}` / nil / `{}` · alles verfügbar | keine `recommended`; alle 5 Dienste + FIT `more`, Strava `more` |
| T2 | P1: `{myWhoosh}` / mac / `{none}` | `[myWhoosh(rec), macBridge(rec)]`, Reasons `myWhooshPlansAndRides`, `bridgeMac` |
| T3 | `{myWhoosh}` / mac / `{}` · `bridgeDownload = false` | keine Brücke in irgendeiner Stufe; `asksDevice == false` |
| T4 | `{myWhoosh}` / nil / `{}` | Brücke `optional`, `bridgeMaybeMac` |
| T5 | `{myWhoosh}` / tablet / `{appleWatch}` | `myWhoosh(rec)`, `appleHealth(rec)`; Brücke `more` |
| T6 | P2: `{zwift}` / nil / `{strava}` | `intervalsICU(rec)` mit `note` (R12); `strava(advanced)` |
| T7 | `{zwift}` · `intervalsOAuth = false` | kein intervals.icu; `fitImport(optional, fitNoIntervals)` |
| T8 | `{zwift, rouvy}` / – / `{garminWahoo}` | ein intervals.icu-Eintrag `rec`, Reasons `[intervalsZwift, intervalsRouvy, intervalsDevice]`, Satz enthält „Zwift“, „Rouvy“, „Garmin- oder Wahoo-Radcomputer“ |
| T9 | P3: `{none}` / – / `{garminWahoo, heartStrap, strava}` | `appleHealth(rec, healthGarmin)`, `strap(rec)`, `intervalsICU(optional, intervalsDevice)`, `strava(advanced)` |
| T10 | P4: `{none}` / – / `{heartStrap}` | `[strap(rec)]`, Rest `more` |
| T11 | P5: `showAll = true` mit beliebigen Antworten | alle verfügbaren `optional` (Reason `catalog`), Strava `advanced`, keine `recommended` |
| T12 | `{none, zwift}` | wie `{zwift}` (N1) |
| T13 | `{}` / mac / `{}` | `normalized().myWhooshDevice == nil` (N3) |
| T14 | `{myWhoosh, zwift}` / mac / `{appleWatch, heartStrap}` | 4 × `rec` (myWhoosh, intervalsICU, macBridge, appleHealth), `strap` `optional` (Obergrenze) |
| T15 | `{appleWatch}` · `health = false` | kein `appleHealth` in irgendeiner Stufe |
| T16 | `{other}` | `intervalsICU(optional, intervalsOther)`, `fitImport(optional, fitOther)` |
| T17 | Sortierung | Ausgabe ist nach `(tier, Reihenfolge)` sortiert, jede `ConnectionID` höchstens einmal |
| T18 | `germanList` | `["A"]` → „A“, `["A","B"]` → „A und B“, `["A","B","C"]` → „A, B und C“ |
| T19 | jeder `benefit` | genau ein Satz (endet mit „.“, kein weiterer Satzpunkt im Inneren außer in Abkürzungen), kein „API“, „OAuth“, „FIT“ außer im FIT-Eintrag mit Erklärung |
| T20 | `asksDevice` | true nur für `{myWhoosh}` ∧ `bridgeDownload` ∧ `!showAll` |

### AP2 · Modell, Persistenz, Migration (S)

- **Dateien:** `Store/AppModel+Onboarding.swift` (`OnboardingServicesState`, `onboardingServices`, `serviceAvailability`, `serviceRecommendations`, Summary v2, `migratedStep`), `Store/AppModel.swift` (Keys `onboardingStep` → `onboarding.step.v3`, neu `onboardingServices` in `Keys.all`, Migration in `init`, Debug-Hooks §9), `Store/AppModel+Intervals.swift` (`lastIntervalsError`, Rückgabe `Bool`), `Store/AppConfig.swift` (`bridgeDownloadURL`).
- **Abhängigkeiten:** AP1.
- **Akzeptanz:** Bestehende Tests in `OnboardingTests` und `OnboardingJourneyTests` bleiben grün (angepasst auf 7 Schritte). Kein bestehender Nutzer sieht die Einführung erneut. „Alle Daten löschen“ entfernt beide neuen Schlüssel.
- **Testfälle:**
  - `servicesStateIsPersistedAndResumed`: Antworten setzen, neues Modell mit denselben Defaults → gleiche Antworten.
  - `stepV2IsMigrated` (Tabelle §9) und `v2KeyIsRemovedAfterMigration`.
  - `storedStepIsClamped` mit `onboardingStepCount == 7`.
  - `existingInstallThatFinishedV1NeverSeesTheNewFlow` (vorhanden, bleibt).
  - `newKeysAreWipedWithAllData` (`DeleteAllDataTests`).
  - `recommendationsFollowAvailability`: `intervalsConfig` ohne Client-ID → kein intervals.icu.
  - `intervalsErrorIsKeptForTheForm`: Stub-Transport 401 beim Token → `lastIntervalsError != nil`, `connectIntervals` liefert `false`.
  - `summaryListsChosenServices`: MyWhoosh verbunden, Health „später“ → zwei Dienstzeilen mit richtigen Zuständen; nicht empfohlene, nicht verbundene Dienste fehlen.
  - `summaryLabelsAreSpokenGerman` erweitert um die neuen Zeilen.

### AP3 · UI: Fragen (S–M)

- **Dateien:** Ordner `UI/Onboarding/` anlegen: `OnboardingView.swift` (verschoben, Schritte neu), neu `ChoiceChipGrid.swift` (Kachelraster, Mehrfach- und Einfachauswahl, exklusive Kachel), `OnboardingQuestionSteps.swift` (Schritte 2 und 3, Folgefrage, „Alle Dienste zeigen“, Tipp). „Überspringen“ springt zu Schritt 6 (§6, E3). Willkommen-Texte (§6.1).
- **Abhängigkeiten:** AP2.
- **Akzeptanz:** Kacheln mindestens 44 pt, Auswahl mit Symbol und `.isSelected`, 1 Spalte ab AX1, Folgefrage nur bei `asksDevice`, Fokus/Ansage bei der Folgefrage, kein Konsolenfehler, `performAccessibilityAudit` ohne Critical/Serious auf 402 pt und SE.

### AP4 · UI: Für dich passt, Coach, Fertig (M)

- **Dateien:** neu `UI/Onboarding/ServiceRecommendationCard.swift`, `UI/Onboarding/OnboardingServicesStep.swift` (Abschnitte, Akkordeon, Leerzustand), `UI/Onboarding/OnboardingConnectSheets.swift` (Brücke und Gurt als Blatt), neu `UI/Connections/IntervalsOAuthButton.swift` (aus `IntervalsConnectionView` ausgelagert und dort genutzt), Coach- und Fertig-Schritt in `OnboardingView.swift`, `UI/RootView.swift` (`OnboardingChoice.connection`).
- **Wiederverwendung:** `MyWhooshLoginForm`, `ClaudeKeyForm`, `MacBridgeView`, `DevicesView`, `ConnectionStatusLabel`, `Card`, `.jelly`/`.soft`, `PageIndicator`.
- **Abhängigkeiten:** AP2; parallel zu AP3 möglich, weil die Schritte getrennte Dateien sind.
- **Akzeptanz:** jede Karte hat die Zustände offen/läuft/verbunden/Fehler/später; Fehler aus `lastMyWhooshError` bzw. `lastIntervalsError` sichtbar im Intro; Abbruch der Web-Anmeldung ohne Fehlertext; während „läuft“ sind Zurück und Überspringen deaktiviert; Tastatur verdeckt den Anmelden-Knopf auf dem SE nicht; Blätter schließen sauber und landen auf derselben Karte; Fertig zeigt nur gewählte bzw. verbundene Dienste mit Ort für Übersprungenes.

### AP5 · UI-Tests und Debug-Hooks (M)

- **Dateien:** `IndoorCoachUITests/AuditWalkthroughTests.swift` (test15, test16, test29, test30, testMatrixOpening anpassen; neue Tests), Stub-Erweiterungen in `UI/RootView.swift` (`JourneyStubTransport`: intervals.icu-Token und Athlet) und Health-Stub.
- **Abhängigkeiten:** AP3, AP4.
- **Bestehende Identifier:** bleiben `onboarding.next`, `.back`, `.skip`, `.pageIndicator`, `.ftp`, `.ftpUnknown`, `.weight`, `.weeklyHours`, `.later` (jetzt „Ohne Verbindung weiter“), `.noClaude`, `.consoleLink`, `.myWhooshStatus`, `.status.mywhoosh`, `.status.coach`, `.tour`, `.start`, `whoosh.*`, `claude.key.*`. Geändert: `onboarding.strava` (jetzt auf „Alles bereit“, nur nach „Nach der Einführung einrichten“). Neu: siehe §6.
- **XCUITest-Schritte:**

| Test | Start | Schritte und Prüfungen |
|---|---|---|
| test15_Onboarding (angepasst) | `-uiSeed empty -uiOnboarding YES` | „Schritt 1 von 7“ → Training wie heute → Schritt 2: ohne Auswahl Knopf „Weiter ohne Angabe“ → Schritt 3 ebenso → Schritt 4: Leerzustand oder nur „Alle Dienste anzeigen“, `onboarding.later` → Schritt 5: `onboarding.coach.setup` vorhanden, `claude.key.field` **nicht** sichtbar, `onboarding.noClaude` → Schritt 6 „Schritt 7 von 7“, `onboarding.status.profil` und `.coach` → `onboarding.start` → Heute; zweiter Start ohne Einführung |
| test15b_SkipJumpsToSummary (neu) | wie oben | auf Schritt 2 `onboarding.skip` → „Alles bereit“ sichtbar (nicht Heute), `onboarding.start` → Heute |
| test16_OnboardingStravaChoice (angepasst) | wie oben | Schritt 3: `onboarding.extra.strava` → Schritt 4: Karte `onboarding.service.strava` im Abschnitt „Für Fortgeschrittene“, kein Feld „Client-ID“ im Intro → Schalter `….strava.afterwards` → bis Schritt 6 → `onboarding.strava` → Navigationsleiste „Strava“, Feld Client-ID tippbar |
| test29_OnboardingJourneyWithConnections (angepasst, P1) | `journeyArguments + -uiBridgeAvailable YES -uiHealthStub YES` | Schritt 2: `ride.myWhoosh` → Folgefrage erscheint → `device.mac` → Schritt 3: `extra.appleWatch` → Schritt 4: Reihenfolge der Karten MyWhoosh, Mac, Apple Health; MyWhoosh „Anmelden“ → Stub-Login → `onboarding.myWhooshStatus` „Verbunden · … Fahrten geladen“; Health „Weiter zur Freigabe“ → Status „Freigabe erteilt“; Mac „Später“ → Status „Später“; `onboarding.next` → Coach: `coach.setup` → Test-Key → gespeichert → Fertig: `status.mywhoosh` „verbunden“, `status.applehealth` „Freigabe erteilt“, `status.macbridge` enthält „Sekundendaten vom Mac“, `onboarding.openConnections` vorhanden → Tour → Heute |
| test29b_OnboardingZwiftIntervals (neu, P2) | `-uiOnboarding YES -uiIntervalsStubLogin YES` | `ride.zwift` → keine Folgefrage → `extra.strava` → Karte intervals.icu mit Hinweis „nur über Strava“ → `….intervalsICU.connect` → Status „Verbunden als …“ → Folge-Hinweis und `onboarding.intervals.settings` sichtbar → Fertig: `status.intervalsicu` verbunden, Folge-Hinweis erneut |
| test29c_OnboardingBeginner (neu, P4) | `-uiOnboarding YES` | `ride.none` → Tipp „kostenlose App“ sichtbar; `ride.zwift` antippen → `ride.none` abgewählt; wieder `ride.none` → Zwift abgewählt → `extra.heartStrap` → Karte Brustgurt → „Gurt koppeln“ → Blatt mit `strap.explainer.continue` → „Fertig“ → `….strap.later` → Fertig: `status.strap` „Später unter Profil → Dienste & Geräte → Brustgurt“ |
| test29d_OnboardingShowAll (neu, P5) | `-uiOnboarding YES` | Schritt 2 `onboarding.showAll` → direkt „Alle Dienste“, „Schritt 5 von 7“, keine Empfehlungs-Überschrift, Strava unter „Für Fortgeschrittene“; Zurück → Schritt 2 (nicht 3) |
| test30_OnboardingWrongKeyAndResume (angepasst) | `journeyArguments` | bis Coach → `coach.setup` → falscher Key → Fehler; Seitenanzeige „Schritt 6 von 7“ → Abbruch → Neustart → wieder Coach, „Schritt 6 von 7“ |
| test30b_ResumeKeepsAnswers (neu) | `-uiOnboarding YES` | Schritt 2 `ride.myWhoosh`, Schritt 3 `extra.appleWatch`, auf Schritt 4 beenden → Neustart ohne `-uiOnboarding` → Schritt 4 mit denselben Karten |
| test30c_IntervalsLoginError (neu) | `-uiIntervalsStubLogin YES` + Stub-Fehler 401 | Karte zeigt Fehler im Intro (nicht nur Banner), „Ohne Verbindung weiter“ bleibt möglich |
| testMatrixOpening (angepasst) | L/Dark und AX5/Light, je 402 pt und SE | Schritte 0–6 mit Vorbelegung `-uiOnboardingAnswers rides=myWhoosh,zwift;device=mac;extras=appleWatch,heartStrap` und `-uiBridgeAvailable YES`: Screenshot, Wischen, `accessibilityAudit` je Schritt; bei AX5 Kacheln einspaltig, untere Leiste verdeckt keine Kachel dauerhaft |

- **Akzeptanz:** alle UI-Tests auf 402 pt und iPhone SE grün; Konsole 0 meldepflichtige Fehler; keine Secrets im Schlüsselbund nach Testläufen (In-Memory-Stores wie bei den vorhandenen Hooks).

### AP6 · optional: „Welche Dienste passen zu mir?“ in Dienste & Geräte (S)

- **Dateien:** `UI/Connections/ConnectionsView.swift` (erste Zeile über „Fahrten & Pläne“, `profile.findServices`), neues Blatt `ServiceFinderSheet` mit `ChoiceChipGrid`-Schritten und `ServiceRecommendationCard` (gleiche Komponenten). Die Antworten sind aus `onboardingServices` vorbelegt.
- **Nutzen:** Bestandsnutzer und alle, die im Intro übersprungen haben, bekommen dieselbe Hilfe, ohne die Einführung erneut zu durchlaufen.
- **Test:** UI-Test öffnet das Blatt aus dem Profil, wählt Zwift und sieht die intervals.icu-Karte.

### AP7 · Doku (S)

- `docs/03-INSTALLATION.md`: Abschnitt „Erster Start“ mit den 7 Schritten.
- `docs/04-STATUS.md`: Zeile Onboarding v3.
- `docs/12-PAKET-OEFFNUNG.md`: Verweis auf dieses Dokument.
- Abschluss nach ECC: Code-Review, alle Unit-Tests (`swift test`), volle UI-Tests auf 402 pt und SE, UX-Walk mit P1 und P4 als Persona.

---

## 12. Entscheidungen für den Produktinhaber

| # | Frage | Empfehlung | Grund |
|---|---|---|---|
| **E1** | Wie kommt die Mac-Brücke zu normalen Nutzern? Heute nur Skript oder Xcode. | **notarisierte DMG über GitHub Releases** (kurzfristig) oder Mac App Store (später); URL in `AppConfig.bridgeDownloadURL`. Bis dahin blendet das Intro die Brücke aus (Regeln R2/R3 sind daran gebunden). | Ohne Bezugsweg wäre die Empfehlung eine Sackgasse. Für das Ziel „Mac-Brücke auch für Nicht-Techniker“ ist das die eigentliche Voraussetzung. |
| E2 | Die Gerätefrage nur bei MyWhoosh oder immer stellen? | **nur bei MyWhoosh** und verfügbarer Brücke | ändert heute sonst keine Empfehlung; erweitern, sobald „Zwift über den Mac“ kommt |
| E3 | „Überspringen“ springt zur Zusammenfassung statt sofort zu schließen? | **ja** | Fragen erhöhen das Risiko, versehentlich alles zu überspringen; die Zusammenfassung zeigt den Ort für den Rest. Kostet P5 einen Tipp. |
| E4 | Antworten nach Abschluss behalten? | **ja, lokal**, gelöscht mit „Alle Daten löschen“ | Vorbelegung für AP6; nichts verlässt das Gerät |
| E5 | Strava im Intro einrichten? | **nein**, nur „nach der Einführung einrichten“ | Client-ID, Secret und Abo sind die größte Hürde; der Weg bleibt erhalten |
| E6 | Höchstzahl Empfehlungen | **4** | mehr wirkt wieder wie eine Liste aller Dienste |
| E7 | AP6 („Welche Dienste passen zu mir?“ im Profil) gleich mitbauen? | **danach**, als eigenes kleines Paket | Intro zuerst schlank fertig machen |

**Offene Prüfpunkte vor der Umsetzung:**
- Den intervals.icu-Weiterleitungstext („Einstellungen → Connections … Upload planned workouts“) an einem echten Konto prüfen und genau so benennen, wie er bei intervals.icu heißt.
- Den Satz zu Garmin Connect → Apple Health prüfen: Garmin schreibt Workouts nur nach Health, wenn die Nutzerin das in Garmin Connect eingeschaltet hat. Der Kartentext sagt deshalb „kommen über Apple Health“. Bei Bedarf ergänzen: „wenn Garmin Connect mit Health verbunden ist“.
- Den Mindestbetrag für Guthaben bei Anthropic nicht im Text nennen (ändert sich); nur „etwas Guthaben“.

### Entschieden (21.11.2026)

- **E1:** `AppConfig.bridgeDownloadURL` liest den Info.plist-Schlüssel `BridgeDownloadURL` (vorerst leer → Brücke im Intro ausgeblendet). Sobald eine notarisierte DMG über GitHub Releases bereitsteht, genügt das Eintragen der URL. In UI-Tests schaltet `-uiBridgeAvailable YES` die Brücke frei.
- **E2–E7:** wie empfohlen (Gerätefrage nur bei MyWhoosh; „Überspringen“ springt zur Zusammenfassung; Antworten lokal behalten und mit „Alle Daten löschen“ entfernen; Strava nicht im Intro einrichten; höchstens 4 Empfehlungen; AP6 als eigenes Paket danach).
