# Feature-Paket „Leistung“: Bestleistungen & VO2max (ECC: orch-add-feature)

Stand 17.11.2026 · Größe: **mittel–groß** (2 Features + neuer Datenpfad für Sekundenwerte) · Status: **Gate 1 – Plan zur Freigabe**

## 1. Brainstorming (Orientierung an Strava-Premium)

| Strava-Premium-Feature | Nutzen für Indoor-Fahrer | Übernahme |
|---|---|---|
| **Leistungskurve** (Power Curve, Zeitraum-Vergleich) | Wo bin ich stark/schwach (Sprint, VO2, Schwelle, Ausdauer)? | ✅ Kern |
| **Bestleistungen / PRs** (Trophäen in der Aktivität) | Motivation, Fortschritt sichtbar | ✅ Kern (5 s, 15 s, 1 min, 5 min, 10 min, 20 min, 60 min) |
| Fitness & Freshness, Relative Effort | schon umgesetzt | – |
| Leistungszonen-Verteilung je Aktivität | Trainingsqualität | später (braucht Sekundendaten, P2) |
| Geschätzte FTP aus der Kurve (bei Strava nicht, bei intervals.icu) | FTP im Profil aktuell halten | ✅ klein, aus der Kurve „frei Haus“ |
| VO2max (Strava: nein, Garmin: ja) | Leistungsfähigkeit als eine Zahl, Trend im Winter Arc | ✅ Kern |

## 2. Daten: was gebraucht wird, was da ist, Lücken

| Bedarf | Strava-Summary | MyWhoosh-Liste | FIT-Import | Profil |
|---|---|---|---|---|
| Sekundenleistung (volle Kurve) | ❌ (nur über Streams-API, Abo-Problem) | ❌ (FIT-Datei: S3 „Access Denied“) | ✅ `record`-Nachrichten | – |
| Ø-Leistung über die ganze Fahrt | ✅ `average_watts` | ✅ `watt` | ✅ | – |
| Max-Leistung | ✅ `max_watts` (noch nicht gelesen) | ❌ | ✅ | – |
| Dauer | ✅ | ✅ `rideDuration` | ✅ | – |
| Gewicht | – | – | – | ✅ `weightKg` |
| Ruhe-/Max-HF | – | ❌ (heartrate 0 ohne Gurt) | ✅ | ✅ |

**Lücken und wie sie geschlossen werden:**
1. **Sekundendaten** fehlen bei Strava- und MyWhoosh-Fahrten → (a) FIT-Parser liefert künftig die Sekundenleistung, daraus wird die Kurve **beim Import einmal berechnet und kompakt gespeichert** (keine Rohdaten im Store); (b) für Fahrten ohne Sekundendaten zählt die **Ø-Leistung über die Fahrtdauer als gesicherter Mindestwert** der Kurve an dieser Dauer (eine 45-min-Fahrt mit 205 W beweist: 45-min-Bestleistung ≥ 205 W); (c) Strava `max_watts` als Mindestwert für 1 s.
2. **Transparenz statt Scheingenauigkeit:** jeder Kurvenpunkt trägt seine Quelle (gemessen / Mindestwert aus Ø). Die App zeigt „3 von 12 Fahrten mit Sekundendaten – importiere FIT-Dateien für die volle Kurve“.
3. **Strava-Streams** (für Pilot-Tester mit Strava-Zugang) und **MyWhoosh-FIT** bleiben Backlog (B16 / B23), weil gesperrt bzw. kostenpflichtig.

## 3. VO2max – Methode

- **Leistungsbasiert (bevorzugt):** ACSM-Gleichung für das Radergometer, VO2 (ml/kg/min) = 10,8 × W/kg + 7, angewendet auf die **5-min-Bestleistung** als Näherung der maximalen aeroben Leistung (MAP). Nur aus Sekundendaten oder einem Mindestwert ≥ 5 min.
- **HF-basiert (Rückfall):** Uth-Sørensen-Formel, VO2max = 15,3 × HFmax / HFruhe (Profilwerte).
- **Trend:** Wert je 6-Wochen-Fenster (aus der Kurve dieses Fensters), Anzeige mit Quelle und dem Hinweis „Schätzung, kein Labortest“.

## 4. Slices (Task-Liste)

| # | Slice | Test-first |
|---|---|---|
| T1 | `PowerCurve` (Domain): Bestleistung je Dauer aus 1-Hz-Werten (gleitende Summe), Zusammenführen mehrerer Fahrten, Mindestwerte aus Ø-Leistung, Quelle je Punkt, eFTP (95 % der 20-min) | Unit-Tests mit konstruierten Reihen |
| T2 | FIT-Parser liefert Sekundenleistung (inkl. Lücken/Pausen), Kurve wird beim FIT-Import berechnet; `StoredRide.powerCurve` (optional, leichte Migration); Strava `max_watts` lesen | Parser- und Migrationstests |
| T3 | `VO2max` (Domain): ACSM aus 5-min-Leistung, Uth aus HF, Trend je 6 Wochen, Quelle | Unit-Tests mit Literaturbeispielen |
| T4 | UI „Leistung“ im Verlauf: Kurve (Zeitraum 6 Wochen / 90 Tage / Jahr, Vergleich Vorperiode), Bestleistungsliste mit Datum/Fahrt, Datenabdeckung + FIT-Hinweis, eFTP-Vorschlag „Ins Profil übernehmen“ | UI-Test: Seite öffnet, Werte sichtbar |
| T5 | VO2max-Karte (Heute + Leistung) mit Trend; PR-Abzeichen im Fahrt-Detail („Neue 5-min-Bestleistung“) | UI-Test |
| T6 | Review (Swift-Reviewer), Kontrast/A11y der Kurve, Gerätetest, Backlog-/Statusdoku | – |

**Nicht im Umfang:** Leistungszonen je Fahrt, Strava-Streams-Abruf, Alters-/Geschlechtsnormen für die VO2max-Einordnung (bräuchte zusätzliche Profilangaben).
