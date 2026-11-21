# 19 · Plan: Zwift und weitere Indoor-Plattformen anbinden

Stand: 21.11.2026 · **Entwurf zur Freigabe, noch nicht umgesetzt.** Recherche durch einen Agent mit Websuche; **[B]** = belegt, **[V]** = vermutet. Quellen am Ende.

## 1. Ausgangslage

Heute gilt:
- **Pläne gehen nur an MyWhoosh**, über die inoffizielle API. Rückfallweg ist die `.zwo`-Datei.
- **Fahrten kommen aus vier Quellen:** Strava (Zusammenfassung), MyWhoosh (Liste plus FIT), FIT-Import und die Mac-Brücke (Sekundendaten aus dem MyWhoosh-Ordner).
- Mit dem neuen Profil (docs/18) ist jeder Dienst ein `ConnectionDescriptor`. Eine neue Anbindung braucht deshalb eine Zeile, eine Detailseite und eine Statusregel, aber keinen Umbau.

## 2. Was die Recherche ergeben hat

| Plattform | Zugang für Einzelentwickler | Workouts hinein | Fahrten heraus | Aufwand | Nutzen |
|---|---|---|---|---|---|
| **intervals.icu** | **ja**: API-Key (privat) oder OAuth (App Store); kommerzielle Nutzung erlaubt [B] | ja: `.zwo` unverändert hochladbar, leitet 7 Tage im Voraus weiter an **Zwift, Garmin, Wahoo ELEMNT, Rouvy** [B] und evtl. MyWhoosh [V] | ja, Liste plus Original-FIT; **aber keine Daten, die über Strava kamen** [B], Garmin-Daten bald gesperrt [V] | M | sehr hoch |
| **Zwift über den Mac-Ordner** | ja, über das Dateisystem, offiziell dokumentiert [B] | `.zwo` nach `~/Documents/Zwift/Workouts/<Zwift-ID>/`; nach Neustart auf allen Geräten [B] | FIT-Dateien unter `~/Documents/Zwift/Activities` [B] | S | hoch, wenn Zwift auf dem Mac läuft |
| Zwift-API | **nein**: nur für Partner, Anträge bleiben unbeantwortet [B] | – | – | – | – |
| Garmin Personal (seit 21.10.2026) | ja, **nur Privatnutzung**, nur lesen [B] | nein | FIT | S–M | mittel |
| Garmin Starter | Antrag, Website, Server für Push nötig [B/V] | ja | ja | L | mittel |
| TrainingPeaks | **nein**: Partner-API nur für Firmen, gehört jetzt Garmin [B] | – | – | – | – |
| Wahoo Cloud | Antrag nötig, kein SYSTM [B] | eingeschränkt | ja | M–L | gering, über intervals.icu abgedeckt |
| Rouvy, TrainerRoad | keine öffentliche API [B] | Rouvy über intervals.icu | Rouvy über intervals.icu | – | gering |

**Kernaussage:** Den direkten offiziellen Weg zu Zwift gibt es für uns nicht. Zwei offizielle Umwege decken Zwift trotzdem vollständig ab:
1. **Die Mac-Brücke**: lokal, ohne Konto, aber nur Zwift auf dem Mac.
2. **intervals.icu als Drehscheibe**: Zwift auf jedem Gerät, dazu Garmin, Wahoo und Rouvy, aber mit einem weiteren Konto.

## 3. Vorgeschlagene Reihenfolge

### Stufe 1 · Zwift über die Mac-Brücke (S, ca. 1–2 Tage)

- **Fahrten:** Die Brücke beobachtet zusätzlich `~/Documents/Zwift/Activities/*.fit`. Den Ordner gibt der Nutzer einmal per Öffnen-Dialog frei (Security-Scoped Bookmark, wie beim MyWhoosh-Ordner). Danach läuft alles wie heute: gleiche Kopplung, gleiche Abholung, die Anreicherung vorhandener Fahrten bleibt.
- **Workouts:** Das iPhone schickt geplante Einheiten als `.zwo` über die bestehende Bonjour-Verbindung an die Brücke. Die Brücke schreibt sie nach `~/Documents/Zwift/Workouts/<Zwift-ID>/` und erkennt den ID-Ordner selbst. Die Dateinamen sind stabil (Datum plus Titel), damit ein neuer Plan alte Dateien ersetzt und nicht verdoppelt. Einheiten aus der Vergangenheit räumt die Brücke weg.
- **Profil:** Neue Zeile „Zwift (über den Mac)“ mit den Rollen Fahrten · Pläne · Sekundendaten. Auf der Detailseite: „Pläne an Zwift senden“ an/aus und ein Hinweis „Zwift neu starten, damit neue Workouts erscheinen“.
- **Tests:**
  - Unit-Tests für Ordnererkennung, Dateinamen, Aufräumen und Protokoll-Nachricht im Bridge-Target (`Bridge/Tests`) und in IndoorCoachKit;
  - Gerätetest mit Zwift auf dem Mac (docs/16 ergänzen).
- **Risiko:** Zwift verteilt Workouts manchmal erst nach einem Neustart [B]. Dateien über 64 KB bleiben auf dem Mac [B]; unsere `.zwo` haben wenige KB.

### Stufe 2 · intervals.icu als Drehscheibe (M, ca. 3–5 Tage)

- **Verbinden:**
  - privat: persönlicher API-Key aus intervals.icu → Einstellungen, im Schlüsselbund gespeichert, wie heute der Claude-Key;
  - App Store: eigene OAuth-App mit `CALENDAR:WRITE` und `ACTIVITY:READ` (ohne Refresh-Token).
- **Pläne hinein:** `POST /api/v1/athlete/0/events/bulk?upsert=true` mit `category: WORKOUT`, der vorhandenen `.zwo` als `file_contents` und unserer Workout-ID als `external_id`. Verschobene oder gelöschte Einheiten werden so aktualisiert bzw. über `bulk-delete` entfernt. Die Weiterleitung zu Zwift, Garmin, Wahoo oder Rouvy schaltet der Nutzer einmal in intervals.icu ein. Die App erklärt das auf der Detailseite.
- **Fahrten heraus:** Liste über `GET /athlete/0/activities`, Sekundendaten über `GET /activity/{id}/file`. Dubletten erkennt der vorhandene ±5-min-Abgleich (RideMerge). Eine FIT-Datei reichert eine vorhandene Fahrt an.
- **Plan-Ziele verallgemeinern:** Heute gibt es nur „Neue Pläne automatisch an MyWhoosh senden“. Neu ist ein kleines Protokoll `WorkoutDestination` (MyWhoosh, Zwift über den Mac, intervals.icu). Auf der Plan-Seite steht dazu „Senden an …“ mit den verbundenen Zielen. Das Gegenstück für Fahrtenquellen ist `RideSource` und ersetzt die heutigen Einzelpfade in AppModel+RideImport.
- **FTP-Abgleich:** Zwift rechnet in %FTP [B]. Weicht die FTP bei intervals.icu ab, zeigt die Detailseite einen Hinweis.
- **Tests:**
  - Unit-Tests mit `RoutingTransport`: Upsert-Body, external_id, 401, Rate-Limit 429, Fahrtenliste, FIT-Download, Dubletten;
  - Token darf nur an `intervals.icu` gehen, analog zum MyWhoosh-Host-Test.
- **Risiken:**
  - intervals.icu wird im Wesentlichen von einer Person betrieben [V].
  - Fahrten, die über Strava nach intervals.icu kamen, liefert die API nicht [B]. Wer Zwift nur mit Strava verbindet, muss Zwift zusätzlich direkt mit intervals.icu verbinden.
  - Garmin-Daten über intervals.icu fallen voraussichtlich weg [V].

### Stufe 3 · optional: Garmin Personal API (S–M), nur für die Privatnutzung

Nur sinnvoll, wenn Garmin-Fahrten über intervals.icu wegfallen und der Nutzer eine Garmin-Uhr bzw. einen Radcomputer nutzt. Für den App Store ist diese Stufe ausgeschlossen.

### Nicht weiterverfolgen

- inoffizielle Zwift-API: Passwort-Login, Datenschutzerklärung schließt Dritte aus, kann jederzeit brechen;
- TrainingPeaks: kein Zugang;
- TrainerRoad: keine API;
- Wahoo Cloud direkt: über intervals.icu abgedeckt;
- Garmin Starter: Server und Prüfung nötig.

## 4. Was sich im Profil ändert

Jede Stufe fügt in „Dienste & Geräte“ eine Zeile hinzu: `ConnectionID.zwift`, `.intervalsICU`, ggf. `.garmin`. Dazu kommt eine Detailseite auf dem `ConnectionDetailScaffold`. Weil mehrere Plan-Ziele möglich werden, bekommt „Fahrten & Pläne“ in der Übersicht eine kurze Zeile „Pläne gehen an: MyWhoosh, Zwift“. Die Startseite des Profils bleibt unverändert.

## 5. Entscheidungen für dich

1. **Welche Plattform fährst du selbst?** Für Zwift auf dem Mac wäre Stufe 1 der schnellste Gewinn. Fährst du Zwift auf iPad oder Apple TV, bringt erst Stufe 2 etwas.
2. **App Store oder privat?** Für den App Store braucht intervals.icu eine OAuth-App, Garmin Personal entfällt.
3. **MyWhoosh über intervals.icu statt über die inoffizielle API?** Erst an einem echten Konto prüfen [V]. Wenn das klappt, kann der inoffizielle Upload Rückfallweg werden.
4. **Reihenfolge:** Stufe 1 → Stufe 2, oder direkt Stufe 2?

## Quellen

- Zwift, Drittplattformen (06.11.2026): https://support.zwift.com/en_us/zwift-and-third-party-platforms-SypU0LdVr.md
- Zwift, Custom Workouts (28.09.2026): https://support.zwift.com/en_us/custom-workouts-ryGOTVEPs.md
- Zwift, Aktivitäts- und Workout-Dateien (15.10.2026): https://support.zwift.com/en_us/locating-your-activity-log-and-workout-files-BykKO63fr.md
- Zwift-Forum, Training-API-Antrag (23.09.2026): https://forums.zwift.com/t/training-connections-api-how-does-a-coaching-platform-actually-apply-in-2026/671308
- intervals.icu × Zwift: https://forum.intervals.icu/t/intervals-icu-and-zwift-integration-is-live/81764
- intervals.icu, Integration Cookbook: https://forum.intervals.icu/t/intervals-icu-api-integration-cookbook/80090
- intervals.icu, geplante Workouts hochladen: https://forum.intervals.icu/t/uploading-planned-workouts-to-intervals-icu/63624
- intervals.icu, API-Terms (22.10.2025): https://forum.intervals.icu/t/intervals-icu-api-terms-and-conditions/114087
- Rouvy × intervals.icu: https://support.rouvy.com/hc/en-us/articles/35523188955793-ROUVY-and-Intervals-icu
- Garmin Personal FAQ: https://developer.garmin.com/gc-developer-program/personal/personal-faq/
- the5krunner, Garmin Personal API (22.10.2026): https://the5krunner.com/2026/10/22/garmin-personal-api/
- the5krunner, Garmin vs. intervals.icu (14.10.2026): https://the5krunner.com/2026/10/14/garmin-api-intervals-third-party-apps/
- TrainingPeaks, Partner-API (12.09.2026): https://trainingpeaks.com/blog/an-update-on-trainingpeaks-partner-api
- Garmin kauft TrainingPeaks (22.07.2026): https://bicycleretailer.com/industry-news/2026/07/22/garmin-acquires-trainingpeaks-trainheroic-platforms
- Zwift kauft Rouvy (29.04.2026): https://zwiftinsider.com/zwift-acquires-rouvy/
- Wahoo Cloud API: https://developers.wahooligan.com/cloud
