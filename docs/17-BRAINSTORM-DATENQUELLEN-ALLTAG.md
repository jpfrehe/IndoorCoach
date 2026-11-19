# Brainstorming, Roadmap & Lösungskonzept: Daten über das Workout hinaus

Stand 19.11.2026, **Version 2, mit Umsetzungsstand (§11)** · Rollen: Product Owner (Hauptsession) und Business Analyst (Subagent, drei Runden) · Grundlage: [PRD](01-PRD.md), [Konzept](02-KONZEPT.md), [Status](04-STATUS.md), [Brainstorming Winter-Motivation](09-BRAINSTORM-WINTER-MOTIVATION.md), [Mac-Brücke](14-SEKUNDENDATEN-MAC-BRUECKE.md), [Sekundendaten-Auswertung](15-PAKET-SEKUNDENDATEN-AUSWERTUNG.md) sowie eine Web-Recherche (Quellen in §12).

Kennzeichnung: **[nv]** = nicht verifiziert bzw. nur aus Sekundärquellen, **[EUR?]** = Europreis nicht bestätigt, **⚠** = Fallstrick. Geräte- und API-Angaben ändern sich mit App-Updates und werden vor der Umsetzung auf echten Geräten geprüft (Technik-Spike B26, offene Punkte §10.1).

**Ergebnis in einem Satz:** IndoorCoach erweitert seine Datenbasis lokal und geräteunabhängig über vier Bausteine:
- einen **Bluetooth-Brustgurt direkt in der App** (Rollenfahrt ohne Mac-Brücke, Kraft und andere Einheiten, später Morgen-HRV),
- die **Erfassung von Krafttraining** mit Gurt und schlanker Übungsangabe in einer eigenen **Muskel-Spur**,
- **Apple Health** (lesend, Schreiben optional),
- gerätefreie Bausteine: **Check-in** und **Aufwärm-Check**.

Es gibt kein Backend, keine Kaufempfehlung und keinen Readiness-Score. Ziel ist ein Rad-Plan, der die ganze Woche kennt, und Fortschritt, der auch ohne Wearable sichtbar wird.

### Änderungen gegenüber Version 1

| Thema | Version 1 | Version 2 | Auslöser |
|---|---|---|---|
| Brustgurt | nur „Morgen-HRV, später Opt-in“ | **eigenes Modul mit Menüs:** Geräte, Aufzeichnung, Live Activity; Einsatz bei Rolle ohne Brücke, Kraft, anderen Einheiten, Morgen-HRV | Nutzer-Input |
| Krafttraining | Fremdsport aus Health mit geschätztem TSS | **eigene Erfassung** (Gurt + Übungen + RPE + Beinanteil) und **eigene Muskel-Spur**, nicht in CTL/ATL | Nutzer-Input, BA-Runde 3 |
| O1 MyWhoosh → Health | offen | **geklärt: nein.** Die Fahrt vom 19.11. (Mac) ist nicht in Health angekommen. | Prüfung des Nutzers |
| Apple Health | nur lesend | lesend, **Schreiben eigener Einheiten optional** (Standard aus) | BA-Runde 3 |
| Roadmap | R1–R4 | **R0–R5** mit Technik-Spike und eigenen Phasen für Gurt und Kraft | – |
| Backlog | B26–B46 | **B26–B60**, neu nummeriert | – |

---

## 1. Ausgangsfrage

Die Idee des POs war, die Datenquellen zu erweitern, damit Analysen motivierender werden und künftige Workouts besser geplant sind. Dabei sollen auch Daten **außerhalb der Workout-Zeit** einfließen. Der Nutzer hat ergänzt:
- **Brustgurt:** Er soll direkt in IndoorCoach nutzbar sein, mit eigenen Menüs und User Journeys, auch für die anderen Einheiten.
- **Krafttraining:** Viele Fahrer trainieren parallel im Fitnessstudio. IndoorCoach soll diese Einheiten erfassen, mit Brustgurt und manuell unterstützter Angabe der Übungen.

**Ist-Zustand (aus dem Code):**

- `AthleteProfile` pflegt `restingHeartRate` (Standard 50), `weightKg` (75) und `maxHeartRate` **von Hand und statisch**.
- `PlanContext` übergibt Claude Last (CTL/ATL/TSB), Wochen, Fahrten und Wunsch, aber **nichts über Erholung, Kraft oder andere Sportarten**.
- Es gibt **keinen Bluetooth-Code** und keinen Hintergrundmodus. `RelativeEffort` kennt bereits eine Skala für empfundene Anstrengung (`perceivedExertionLabels`) und den Puls-TRIMP aus Sekundendaten. Beides lässt sich wiederverwenden.
- Indoor-Fahrten kommen über die MyWhoosh-Liste (nur Ø-Werte), die Mac-Brücke oder FIT-Dateien. **MyWhoosh schreibt nicht nach Apple Health** (O1, Prüfung 19.11.2026). Wer die Brücke nicht einrichtet, hat also keine Pulssekunden seiner Rollenfahrten.

**Folgerungen aus O1:**
1. Health liefert keine Indoor-Fahrten. Dubletten in Health entstehen nur durch parallele Uhr-Aufzeichnungen (Apple Watch „Indoor Cycling“, Garmin) oder durch unseren eigenen Export.
2. Für Fahrer ohne Mac-Brücke ist der **Gurt am iPhone der einzige Weg zu Pulssekunden** auf der Rolle. Das stärkt das Gurt-Modul.

## 2. Brainstorming: Mehrwert hinterfragen

### 2.1 Wo zusätzliche Daten echten Mehrwert bringen

| Datenart | Planung | Motivation | Messqualität | Urteil | Begründung |
|---|---|---|---|---|---|
| **Krafttraining** (Dauer, Härte, Beinanteil) | **hoch** | mittel | sRPE reliabel (ICC 0,88) | **hoch** | „Schwere Kniebeugen gestern → keine VO₂-Intervalle heute“. Krafttraining verbessert die Radleistung nachweislich (Rønnestad/Vikmoen). Puls-TRIMP unterschätzt Kraft, deshalb Session-RPE (Foster). |
| **Pulssekunden der Rolle ohne Brücke** (Gurt am iPhone) | mittel | **hoch** | hoch (Gurt) | **hoch** | Zeit in Pulszonen, TRIMP und Aufwärm-Check auch ohne Mac. Im ERG-Modus ist die Leistung ≈ Soll, das wird als „angenommen (ERG)“ gekennzeichnet. |
| **Andere Sportarten & Outdoor-Workouts** (aus Health) | hoch | mittel | hoch (Dauer), mittel (Puls am Handgelenk) | **hoch** | Belastung ist Belastung. Ohne sie plant Claude „VO₂max nach Skitag“. |
| **Subjektiver Check-in** (Beine, Schlafgefühl, Laune) | hoch | mittel | subjektiv | **hoch** | Saw et al. 2016: Subjektive Maße reagieren sensitiver als die meisten objektiven Marker. Funktioniert ohne Gerät. |
| **Puls bei fester Leistung im Aufwärmen** | mittel | **hoch** | hoch mit Gurt | **hoch** | Buchheit 2014: Die Belastungs-HF reagiert schon nach etwa 1 Woche. Das ist eine gemessene Fortschrittskurve ohne Wearable. |
| **Ruhepuls nachts (Trend)** | mittel | mittel | hoch (Apple Watch, Ring, Whoop) | **hoch** | Infekt- und Überlastungssignal als mehrtägige Abweichung von der eigenen Basis (Mishra 2020). |
| **Gewicht** | mittel | heikel | hoch | **mittel** | Ersetzt die Pflege von Hand. Gewicht ist **nie** ein Spielziel. |
| **Schlafdauer** | mittel | gering | mittel | **mittel** | Nur als Trend und Kontext für Claude. |
| **HRV** (7-Tage-Mittel) | mittel | gering | geräteabhängig | **mittel**, nur mit fester Quelle | Kleiner Effekt (Granero-Gallegos 2020). In Health liefert nur die Apple Watch verlässlich HRV. Mit Gurt in der App (RR-Intervalle) gibt es eine herstellerunabhängige Quelle als Opt-in. |
| **Atemfrequenz / Temperatur nachts** | gering–mittel | – | relativ | **mittel**, nur im Verbund | Unterstützt den Ruhepuls als Infektsignal. |

### 2.2 Wo es nicht sinnvoll ist

| Idee | Warum nicht |
|---|---|
| **Eigener Readiness-/Recovery-Score**, der automatisch umplant | Pseudo-Präzision, Nocebo, sägt an der Plan-Treue. Verstößt gegen „jede Kennzahl nennt ihre Quelle“. |
| **Herstellerscores** (Body Battery, Whoop Recovery, Oura/Apple Readiness) | Proprietär, nicht vergleichbar, meist nicht in HealthKit |
| **Schlafphasen, Schlaf-Score, Schlaf-Serien, tägliche HRV-Ampel per Push** | Ungenau, Nocebo (Gavriloff 2018), ein Tages-Streak durch die Hintertür |
| **Ernährung, Kalorien, Körperfett, Gewichtsziele** | Pflegeaufwand, Datenqualität, RED-S-Risiko |
| **Kraft in CTL/ATL umrechnen** (sRPE → „TSS“) | AU und TSS sind verschiedene Einheiten; jeder Faktor wäre erfunden. Nur in die ATL gebucht, sinkt die Form bei jedem Krafttag, ohne dass die Fitness je steigt. Wer regelmäßig hebt, sähe dauerhaft müde aus (BA-Einwand T1). |
| **Kraft-Coach werden** (1RM-Rechner, Progressionsanalyse, Videos, Kraftplan-Generator) | Das können Hevy, Strong und TrainingPeaks. Unsere Lücke ist schmal: ein Rad-Plan, der deine Beine kennt. |
| **„Satz fertig“-Marker bei jedem Satz** | Kein Planungsnutzen, der Puls im Kraftsatz sagt wenig, und im Studio ist jeder Tipp Reibung |
| **Generischer Puls-Rekorder als Hauptfunktion, Outdoor-Lauf mit GPS** | Das können Apple Fitness (mit Gurt seit iOS 26) und die Uhren. Wir lesen deren Ergebnis über Health. „Andere Einheit“ gibt es nur als schlanke Variante unserer Aufzeichnung. |
| **Angenommene ERG-Watt nach Apple Health schreiben** | Keine Messung; Apple untersagt falsche Daten in HealthKit |
| **„Krankheitsfrüherkennung“ als Versprechen** | Mögliche Medizinprodukt-Einstufung [nv, juristisch prüfen]. Formulierung immer: „Werte weichen von deiner Basis ab. Wie fühlst du dich?“ |
| **Muster-Analysen im ersten Winter** | n zu klein, Scheinkausalität. Frühestens Saison 2. |

### 2.3 Querschnittsrisiken

- **Quellen-Chaos:** Eine Quelle pro Kennzahl (Quellen-Pinning).
- **Datenfrische:** Garmin und Oura synchronisieren nur bei geöffneter Hersteller-App.
- **Datenschutz und App Store:** Puls und HRV aus dem Gurt sind **ebenfalls Gesundheitsdaten** (Art. 9 DSGVO). Für die Weitergabe an Claude gilt Apple 5.1.2(i): aggregiert, Opt-in, eigene Einwilligung. Für HealthKit gilt 5.1.3.
- **Dubletten:** Nach O1 gibt es **keine MyWhoosh-Dublette in Health**. Bleiben drei Fälle:
  - Uhr zeichnet parallel auf (Rolle oder Studio),
  - Garmin-Workouts,
  - unser eigener Health-Export.

  Die ±5-min-Logik reicht nicht, nötig ist eine Überlappungsregel (§9.6).
- **Bluetooth-Gurt:** Viele Gurte erlauben nur eine Verbindung, und der Gurt ist auf der Rolle schon mit MyWhoosh am Mac verbunden. iOS-Hintergrundbetrieb und Live Activity haben Grenzen bei ausgeschaltetem Display [nv]. Das klärt der Technik-Spike.

## 3. Markt: Datenquellen, Preis-Leistung, Kompatibilität

### 3.1 Wearables und Dienste (Stand Ende 2026)

| Quelle | Gerät + Abo | → Apple HealthKit | Öffentliche API ohne Backend? | Einschätzung |
|---|---|---|---|---|
| **Apple Watch** SE 3 / S11 / S12 | SE 3 ab 269 € UVP (Handel ca. 240–260 €), S11 ab 449 €; kein Abo | **vollständig:** Workouts, Ruhepuls, HRV (SDNN), Schlaf, Atemfrequenz, Temperatur [nv je Modell]; RMSSD ab iOS 27 [nv] | HealthKit lokal | Beste Abdeckung |
| **Google Fitbit Air** | 99,99 $ [EUR?] | seit 08/2026 Workouts, Schlaf, Vitalwerte; HRV [nv] | „restricted“ Scopes → unrealistisch | Nutzen nur über Health |
| **Garmin** | FR 170 ca. 250 €, FR 970 ca. 600 € | Workouts (inkl. Kraft), Schlaf, Gewicht; **kein HRV**, Ruhepuls [nv] | Personal API Key seit 21.10.2026 [nv für iPhone] | Kraft-Workouts kommen über Health und werden annotiert |
| **Whoop** | 199–399 €/Jahr [EUR?] | Ruhepuls, Atemfrequenz, Schlaf; **kein HRV** | OAuth + Secret → Backend | Teuer, wenig Mehrwert |
| **Oura Ring** | ca. 399 € + 69,99 €/Jahr | Schlaf, Atemfrequenz; HRV/Ruhepuls nicht gelistet | **KI-Weitergabe in den API-Bedingungen verboten** | Unvereinbar mit der Claude-Planung |
| **Polar Loop** | 179,90 €, kein Abo | Schlaf, Workouts; kein HRV | OAuth + Secret | gering |
| **Amazfit Helio Strap**, **Withings**, **Coros**, **Ultrahuman** | ca. 100–480 € | teils | teils | nur über Health |
| **Samsung** | – | nicht iPhone-kompatibel | – | raus |
| **Apple Fitness (iOS 26+)** | im iPhone enthalten | zeichnet **ohne Watch mit BLE-Gurt** Indoor Cycling und Krafttraining auf, schreibt nach Health | – | Konkurrenz zum generischen Rekorder, Quelle für Annotation |
| **Hevy / Strong** (Kraft-Apps) | Freemium | schreiben Workouts nach Health [nv] | – | Wer dort protokolliert, bleibt dort; wir annotieren |
| **intervals.icu** | kostenlos | – | persönlicher API-Key | später (B59) |
| **Aggregatoren** (Terra & Co.) | ab 99 $/Monat | – | immer Backend | nein |

### 3.2 Brustgurte (BLE Heart Rate Service 0x180D)

| Gurt | Preis ca. | Gleichzeitige BLE-Verbindungen | RR-Intervalle über BLE | Eignung Rolle + iPhone parallel |
|---|---|---|---|---|
| **Wahoo TICKR / TICKR X** (ab Gen. 2, 2020) | 50–83 € | **3** + ANT+ | ja [nv je Kanal] | ✅ |
| **Wahoo TRACKR HR** | 89,99 € | [nv], vermutlich mehrere | ja | ◐ prüfen |
| **Polar H10** | 60–90 € [EUR?] | **2**, muss in Polar Beat aktiviert werden (Firmware ≥ 2.1.9) | ja (HRV-Referenz) | ✅ nach Aktivierung |
| **Polar H9** | ca. 50 € | **1** | vermutlich ja [nv] | ❌ nur Mac oder iPhone |
| **Garmin HRM-Pro Plus / HRM 600** | 130–170 € | **3** + ANT+ | ⚠ laut Forum nur auf einem Kanal [nv] | ✅ (HRV ◐) |
| **Coospo H9Z** | ca. 35 € | **2** | [nv] | ✅ |
| **Coospo H808S, Magene H303** | 30–45 € | [nv] | [nv] | ◐ prüfen |
| TICKR der ersten Generation, ältere Gurte | – | 1 | – | ❌ |

⚠ Macs haben kein ANT+. Auf der Rolle zählt also nur die Zahl der BLE-Verbindungen. Die App muss das beim Koppeln erkennen und erklären (J-A).

### 3.3 Preis-Leistung nur für den IndoorCoach-Use-Case

| Stufe | Ausstattung | Mehrkosten | Was IndoorCoach damit kann | Bewertung |
|---|---|---|---|---|
| **S0 · Nichts kaufen** | iPhone + vorhandener Gurt mit ≥ 2 BLE-Verbindungen | **0 €** | Gurt in der App: Rolle ohne Brücke, Kraft und andere Einheiten mit Puls, Aufwärm-Check, Morgen-HRV (Opt-in); Check-in; Health-Workouts | **Standardpfad**, deckt den Großteil des Nutzens |
| **S1 · Unter 100 €** | Gurt mit Mehrfachverbindung und RR: TICKR (ca. 50–80 €), H10 (ca. 60–90 €) oder günstig Coospo H9Z (ca. 35 €) | 35–90 € | wie S0, auch für Fahrer mit H9 oder altem Gurt | **Die beste Investition für diese App** |
| **S2 · Wearable vorhanden** | Apple Watch / Garmin / Whoop / Oura | 0 € | zusätzlich Ruhepuls, Schlaf, Fremd-Workouts aus Health; HRV nur mit Apple Watch | ehrlich anzeigen, was fehlt |
| **S3 · Neukauf, falls gewünscht** | Apple Watch SE 3 + Gurt | ca. 300 € | volle Health-Abdeckung ohne Abo | nur für Fahrer, die sowieso eine Uhr wollen |

**Kaum Mehrwert:** Whoop und Oura (Abo, HRV nicht in Health, Oura-KI-Klausel), Polar Loop und Coros (HRV nicht in Health), Körperfettwaagen. IndoorCoach empfiehlt kein Gerät, erklärt aber beim Koppeln, warum ein Gurt mit zwei Verbindungen auf der Rolle praktisch ist.

### 3.4 Wettbewerb bei Rad + Kraft

| App | Kraft | Rad-Planung | Lücke für IndoorCoach |
|---|---|---|---|
| TrainingPeaks | Strength Builder, Videos, Kalender (Premium) | Pläne ohne KI-Abwägung „Beine gegen Intervalle“ | |
| Wahoo SYSTM | Kraft- und Yoga-Inhalte zum Mitmachen | ja | keine Kraft-Protokollierung mit Rückwirkung |
| TrainerRoad | keine Kraftpläne [nv] | adaptiv | |
| Whoop | Muskel-Last per Sensor | keine | |
| Hevy / Strong / Garmin | Protokoll, Rep-Zählung | keine | |
| **IndoorCoach** | schlank: Dauer, Härte, Beine, Übungen optional | **KI-Wochenplan, der deine Beine kennt**, lokal, ohne Abo | **schmal, aber echt** |

### 3.5 Integrationswege

| Weg | Backend? | Abdeckung | Datenschutz | Entscheidung |
|---|---|---|---|---|
| **A · Lokal:** CoreBluetooth-Gurt + HealthKit (lesend, Schreiben optional) + Check-in/Aufwärm-Check | nein | alle hoch bewerteten Datenarten, auch ohne Wearable | lokal | **✓ gewählt** |
| B · Direkt-APIs (Whoop, Polar, Withings, Wahoo, Oura) | ja | Herstellerscores, HRV | Server | ✗ |
| C · Aggregator | ja + Kosten | alles | Drittanbieter-Cloud | ✗ |
| D · intervals.icu mit persönlichem Key | nein | Wellness von Garmin, Polar, Oura | Drittanbieter | später (B59) |

## 4. Personas

### P1 · Markus, 44: „Hauptsache, ich komme überhaupt aufs Rad“ (Stufe S0)

| | |
|---|---|
| **Alltag** | Projektleiter, zwei Kinder. 3× pro Woche 45–60 min ab 21 Uhr im Keller, sonntags manchmal 90 min. **1× pro Woche 40 min Firmenstudio in der Mittagspause.** |
| **Ziel** | Im Mai die 150-km-RTF mit Freunden fahren. |
| **Geräte** | Wahoo KICKR Core, **TICKR (3 Verbindungen)**, iPhone, MacBook mit MyWhoosh. **Die Mac-Brücke hat er nie eingerichtet.** Keine Uhr. |
| **Haltung zu Daten** | **datenmüde, score-skeptisch** (Whoop nach 2 Monaten zurückgegeben). |
| **Frust heute** | Ausfälle durch kranke Kinder und Spätmeetings; seine Rollenfahrten haben nur Ø-Werte; das Studio taucht nirgends auf. |
| **IndoorCoach muss** | wenig Pflege verlangen, in 10 s bei der Entscheidung helfen, Ruhe ohne Schuldgefühl erlauben und das Studio mit zwei Tipps erfassen. |
| **Schreckt ab** | Tägliche Scores, Morgenrituale, Satz-für-Satz-Protokolle, ein weiteres Gerät. |

### P2 · Sabine, 52: „Ich will verstehen, nicht nur gesagt bekommen“ (Stufe S2, Garmin)

| | |
|---|---|
| **Alltag** | Teilzeit-Ärztin, Masters-Lizenz, Rennen ab April. Im Winter 5 h Rolle und **2× Kraft pro Woche** (Kniebeugen, Kreuzheben, Rumpf), aufgezeichnet mit der Garmin (Rep-Zählung). |
| **Ziel** | Ab März über 4 W/kg über 20 min, Frühform zum 12. April. |
| **Geräte** | Garmin Forerunner 970 + HRM-Pro Plus, Index-S2-Waage, Tacx; Mac-Brücke eingerichtet; nutzt intervals.icu. |
| **Haltung zu Daten** | **datenhungrig, aber methodenkritisch.** |
| **Frust heute** | Ihre Daten liegen in vier Apps. Der Rad-Plan legt VO₂-Intervalle auf den Tag nach schweren Beinen. Garmins HRV kommt nicht nach Health. |
| **IndoorCoach muss** | die ganze Woche kennen, Quelle und Methode offenlegen, ihr die Kontrolle lassen und ihre Garmin-Krafteinheiten **annotieren statt doppelt aufzeichnen**. |
| **Schreckt ab** | Vermischte Quellen, erfundene Umrechnungen, eine KI, die ungefragt umplant. |

### P3 · Jonas, 31: „Rad ist eine von vier Sportarten“ (Stufe S2/S3, Apple Watch)

| | |
|---|---|
| **Alltag** | Wiedereinsteiger. Läuft 2× pro Woche, **bouldert 1×**, Skiurlaub in KW 7, 2× Rolle mit MyWhoosh. |
| **Ziel** | Im Juli das Stilfser Joch fahren. |
| **Geräte** | Apple Watch Series 11 (zeichnet alles auf, auch die Rolle parallel), iPhone, Mac; überlegt, einen Gurt zu kaufen. |
| **Haltung zu Daten** | **Gamification-affin, aber vom Streak-Burnout geprägt.** |
| **Frust heute** | Der Rad-Plan weiß nichts vom Lauf und vom Bouldern. Nach dem Skiurlaub ist „alles rot“. Fahrten tauchen doppelt auf. |
| **IndoorCoach muss** | alle Sportarten zählen, Bouldern sinnvoll einordnen, Pausen ohne Absturz erlauben, keine Dubletten erzeugen. |
| **Schreckt ab** | Doppelte Fahrten, Strafe für Pausen, Pflicht-Kauf eines Gurts. |

**Gurt und Kraft je Persona:**

| Persona | Gurt in IndoorCoach | Kraft |
|---|---|---|
| Markus | **Hauptnutzer:** TICKR parallel an Mac und iPhone, Rolle ohne Brücke, Studio-Aufzeichnung | Aufzeichnung mit Gurt, Vorlage „wie letzte Woche“, danach 2 Fragen (Härte, Beine) |
| Sabine | nicht nötig (Brücke + Garmin). Morgen-HRV ◐, weil ihr HRM-Pro RR womöglich nur auf einem Kanal sendet [nv] | **annotieren:** Garmin-Kraft kommt über Health, IndoorCoach fragt Härte und Beine; Claude verlegt Kraft weg vom Tag vor VO₂ |
| Jonas | optional nach Kauf (Aufwärm-Check, Morgen-HRV) | Bouldern = Muskel-Spur (Beine „leicht“), aufgezeichnet von der Watch, annotiert in IndoorCoach |

## 5. Neue Menüs (Informationsarchitektur)

```
Heute
 ├─ Karte „Check-in“ (vor geplanter Einheit)                         R1
 ├─ Schnellstart: [Kraft] [Andere Einheit] [Morgenmessung*]           R3 / R4*
 └─ Karte „Kraft von Garmin/Watch erkannt – wie hart? Beine?“          R3
Plan
 └─ Einheit-Detail (Rad)
     ├─ „Puls am iPhone mitschreiben“ (nur mit Gurt, ohne Brücke)      R2
     └─ Banner „Schwere Beine gestern – tauschen?“                      R3
Aufzeichnung (Vollbild + Live Activity / Dynamic Island)               R2
 ├─ Rad: Plan-Zeitleiste, Puls, aktueller Block, Start-Sync
 ├─ Kraft: Zeit, Puls, Übungsliste der Vorlage (abhaken)                R3
 ├─ Andere Einheit: Sportart, Zeit, Puls                                R3
 └─ Abschluss: Härte (CR-10), Beine (keine/leicht/schwer), Notiz
Verlauf
 ├─ Filter: Rad · Kraft · Andere
 └─ Kraft-Detail: Dauer, Pulsverlauf, Übungen, Härte × min, Beine
Profil
 ├─ Geräte → Brustgurt: koppeln, Status, Akku, Fähigkeiten (RR),
 │           Mehrfachverbindungs-Test, vergessen                        R2
 ├─ Kraft: Vorlagen, Übungskatalog, feste Studio-Tage                   R3
 ├─ Datenquellen: Apple Health je Typ, Quellen-Pinning,
 │                Export nach Health (opt-in)                           R3/R4
 └─ Datenschutz: Einwilligung „Erholung & Kraft an Claude“               R4
```

## 6. User Journeys

### 6.1 Persona-Journeys (Winter im Überblick)

#### P1 Markus (S0: TICKR + iPhone, ohne Brücke)

| Phase | Touchpoint | Daten | Gefühl | Feature |
|---|---|---|---|---|
| **Entdecken** | Plan-Karte „Puls auch ohne Mac-Brücke: Gurt mit dem iPhone verbinden“ | – | neugierig | Einstieg dort, wo der Nutzen ist (J-A) |
| **Einrichten** | Gurt koppeln, Test „MyWhoosh zeigt weiter Puls?“ ✓ | BLE | „funktioniert einfach“ | Mehrfachverbindungs-Test |
| **Alltag Rolle** | Check-in (3 Tipps) → „Puls mitschreiben“ → Live Activity während der Fahrt | Check-in, Pulssekunden | im Flow | J-C |
| **Nach der Fahrt** | „Zeit in Pulszonen“ (gemessen), „Puls bei 150 W: 118 (angenommen, ERG) · stabil“ | Puls + Plan-Soll | ehrlich informiert | Quellenetiketten |
| **Studio** | Mittags „Kraft“ → Vorlage „wie letzte Woche“ → nach 40 min „Wie hart? 7 · Beine schwer“ | Puls, sRPE, Beine | erledigt in 2 Tipps | J-B |
| **Wirkung** | Abends Banner: „Schwere Beine heute. Morgen VO₂ 5×4 mit Donnerstag-Grundlage tauschen?“ | Muskel-Spur | ernst genommen | Vorschlag statt Automatik |
| **Kritischer Moment** | Kind krank: Check-in „Beine schwer, Schlaf schlecht“ → „45 statt 75 min, 5 % leichter?“; Freitag Joker | Check-in | entlastet | Einheit anpassen, Joker |
| **Wochenrückblick** | „Rad 3 h · Kraft 1× · 1 Einheit angepasst, Serie hält“ | Gesamtwoche | zufrieden | ohne Umrechnung |
| **Saisonende** | „Puls bei 150 W: 124 → 113 · Kraft-Winter: 14 Einheiten“ | Aufwärm-Verlauf | stolz, teilt | Herz im Winter Arc |

#### P2 Sabine (S2: Garmin, Brücke, datenhungrig)

| Phase | Touchpoint | Daten | Gefühl | Feature |
|---|---|---|---|---|
| **Entdecken** | Profil → Datenquellen: „Ganze Woche: Kraft, Laufen, Langlauf aus Apple Health“ | – | skeptisch | Methodenseite |
| **Einrichten** | Health-Freigabe für Workouts, Ruhepuls, Gewicht; Hinweis „Garmin schreibt kein HRV nach Health“; Ruhepuls-Quelle gepinnt | HealthKit | ernst genommen | Quellen-Pinning |
| **Kraft annotieren** | Nach dem Studio: Karte „Krafttraining von Garmin (52 min) erkannt – wie hart? Beine?“ → 8 / schwer | Health-Workout + sRPE | „endlich zählt das“ | annotieren statt aufzeichnen |
| **Planung** | Studio-Tage Mo/Do im Profil; Claude legt VO₂ auf Mi und Sa, Begründung „≥ 24 h nach schweren Beinen (Faustregel)“ | Muskel-Spur, Kraft-Tage | Kontrolle | Claude-Regeln Kraft/Rad |
| **Kritischer Moment** | Ruhepuls 3 Tage +7, Check-in „Hals kratzt“ → „VO₂ morgen tauschen oder Joker?“ | Ruhepuls, Check-in | dankbar | Trend-Wächter, keine Diagnose |
| **Wochenrückblick** | „Rad 5 h · Kraft 2× (Beine schwer 2×) · Aufwärm-Puls −4 seit Dezember“ | alles | motiviert | Gesamtwoche |
| **Saisonende** | CTL am 12.04. auf Kurs, jede Zahl mit Methodenlink | alles | Stolz | Transparenz |

#### P3 Jonas (S2/S3: Apple Watch, Multisport)

| Phase | Touchpoint | Daten | Gefühl | Feature |
|---|---|---|---|---|
| **Entdecken** | Feature-Tour „Dein Laufen und Bouldern zählen“ | – | begeistert | Ganze Woche |
| **Dubletten** | „Uhr-Aufzeichnung mit MyWhoosh-Fahrt zusammengeführt“ | Health + Liste | „nicht doppelt“ | Überlappungsregel |
| **Bouldern** | Karte „Klettern 90 min erkannt – wie hart? Beine?“ → 6 / leicht | sRPE | „zählt, aber nicht als Rad“ | Muskel-Spur |
| **Planung** | Lauf Do → Claude schlägt Fr Sweet Spot statt VO₂ vor („Laufbelastung gestern“) | Fremd-PMC | verstanden | Claude-Kontext |
| **Gurt gekauft** | Koppeln, Aufwärm-Check wird freigeschaltet, Health-Export bleibt aus (Watch zeichnet auf) | BLE | „mehr gemessen“ | keine Kaufpflicht, aber Mehrwert |
| **Kritischer Moment** | Skiurlaub KW 7: Ruhewoche, Skitage zählen im Winter Arc; danach Ruhepuls erhöht → „Erste Woche leichter?“ | Health, Ruhepuls | erwartet Strafe, bekommt Lob | Joker, Trend-Wächter |
| **Saisonende** | Winter-Reise am Gardasee, „Ruhepuls 58 → 53“ | Trends | will Saison 2 | Herz im Winter Arc |

### 6.2 Journeys der neuen Menüs

#### J-A · Brustgurt koppeln und verwalten (Markus, TICKR, MyWhoosh am Mac)

| Schritt | Touchpoint | Daten | Gefühl | Feature · ⚠ Fallstrick |
|---|---|---|---|---|
| 1 Einstieg | Profil → Geräte → „Brustgurt verbinden“ oder Plan-Karte „Puls auch ohne Mac-Brücke“ | – | neugierig | Einstieg beim Nutzen, nicht nur in den Einstellungen |
| 2 Berechtigung | Erklärseite, dann iOS-Abfrage Bluetooth | – | kurz skeptisch | „Nur dein Pulsgurt. Nichts verlässt das iPhone.“ |
| 3 Suche | Liste gefundener Gurte mit Signalstärke, Tipp „Gurt anfeuchten und anlegen“ | BLE-Scan 0x180D | „da ist er“ | ⚠ Gurt schläft ohne Hautkontakt |
| 4 Verbinden | „TICKR 4A2F · 62 bpm · RR ✓ · Akku 80 %“ | HR, RR-Flag, Battery Service 0x180F | Vertrauen | Fähigkeiten anzeigen: Mit RR geht Morgen-HRV |
| 5 Mehrfach-Test | „MyWhoosh am Mac öffnen: Siehst du hier weiter Puls?“ | Live-HR | erleichtert | ⚠ Gurt erlaubt nur eine Verbindung (H9, alter TICKR) oder H10 ohne Aktivierung: konkrete Anleitung je Modell |
| 6 Verwalten | Gerätekarte: letzte Verbindung, Akku, „vergessen“ | – | Kontrolle | ⚠ Akku < 20 % → Hinweis vor der Einheit, nicht mittendrin |
| 7 Später | Automatisch neu verbinden beim Start einer Aufzeichnung | gespeicherte Geräte-ID | „funktioniert einfach“ | ⚠ Zwei Gurte im Haushalt: gespeicherte ID statt stärkstem Signal |

#### J-B · Krafteinheit im Studio aufzeichnen und Wirkung auf den Rad-Plan (Markus; Sabine als Annotations-Variante)

| Schritt | Touchpoint | Daten | Gefühl | Feature · ⚠ Fallstrick |
|---|---|---|---|---|
| 1 Start | Heute → „Kraft“ → Vorlage „Wie letzte Woche: Beine + Rumpf“ oder „Ohne Vorlage“ | Vorlage | zügig | Ein Tipp. ⚠ Läuft schon eine Uhr-Aufzeichnung? Dann „Nur annotieren?“ anbieten |
| 2 Aufzeichnung | Live Activity auf Sperrbildschirm und Dynamic Island: Zeit, Puls, Stopp | Pulssekunden | Handy kann weg | ⚠ Hintergrund: verbunden bleiben, nach Abbruch automatisch neu verbinden, Lücke markieren |
| 3 Übungen (optional) | Einhand-Liste aus der Vorlage, Häkchen je Übung; Sätze × Wdh × Gewicht nur auf Wunsch, Vorwerte vorausgefüllt | Katalog (ca. 40 Übungen mit Muskelgruppen) | keine Pflicht | Kein Satz-Marker. Der Beinanteil ergibt sich aus den Häkchen. |
| 4 Abschluss | „Wie hart? (0–10)“ und „Beine: keine / leicht / schwer“ (vorbelegt) | sRPE, Beinanteil, Dauer | erledigt | Muskel-Last = Härte × min, Quelle *angegeben* |
| 4b Nachtragen | Ohne Gurt: Verlauf → „+“ → Kraft, Dauer, Härte, Beine | manuell | 15 s | auch ohne Aufzeichnung |
| 4c Annotieren | Garmin/Watch/Hevy-Workout aus Health → Karte „Wie hart? Beine?“ | Health + sRPE | „nicht doppelt“ | Sabine, Jonas |
| 5 Health (opt-in) | „In Apple Health sichern“, nur wenn eingeschaltet und keine Überlappung | HKWorkout (Puls, Dauer, Typ) | Ringe schließen sich | ⚠ Dublette mit Watch prüfen; eigene Quelle beim Import ausfiltern |
| 6 Wirkung | Plan-Banner: „Schwere Beine heute. Morgen VO₂ 5×4 → mit Donnerstag-Grundlage tauschen?“, Begründung mit „Faustregel“ | Muskel-Spur 72 h, Plan | ernst genommen | Vorschlag; „Einheit anpassen“ als Alternative |
| 7 Woche | „Rad 4,5 h · Kraft 2× (Beine schwer 1×) · gesamt 6 h“ | Gesamtwoche | stolz | keine Umrechnung in TSS |
| 8 Saison | Trophäe „Kraft-Winter: 16 Einheiten“, Satz zum Nutzen fürs Rad | Zählung | sinnstiftend | Kraft belohnt, Rad-Fitness bleibt ehrlich |

#### J-C · Rollenfahrt ohne Mac-Brücke, Gurt am iPhone (Markus)

| Schritt | Touchpoint | Daten | Gefühl | Feature · ⚠ Fallstrick |
|---|---|---|---|---|
| 1 Vor der Fahrt | Check-in → „Puls am iPhone mitschreiben?“ | Check-in | kein Extraaufwand | Nur mit gekoppeltem Gurt und ohne aktive Brücke |
| 2 Verbinden | iPhone verbindet den TICKR, dann MyWhoosh am Mac starten | HR | „beide zeigen Puls“ | ⚠ Gurt mit nur einer Verbindung: klare Meldung, Option „nur Mac“ |
| 3 Start-Sync | Großer Knopf „Los, wenn MyWhoosh startet“; Plan-Zeitleiste läuft mit | Zeitstempel | im Flow | ⚠ Zeitversatz: nachträglich am Ende des Aufwärmens bzw. am Pulsanstieg ausrichten, manuell schiebbar |
| 4 Während | iPhone gesperrt am Lenker, Live Activity: Block, Puls, Restzeit | Pulssekunden | ruhig | ⚠ Akku-Hinweis < 20 %; Abbruch → neu verbinden, Lücke markieren |
| 5 Danach | MyWhoosh-Fahrt aus der Liste (Ø-Watt, Dauer) wird mit der Pulsspur zusammengeführt | Liste + HR | „vollständig“ | Pulsspur hängt an der Fahrt, keine neue Aktivität |
| 6 Auswertung | Zeit in Pulszonen und TRIMP (**gemessen**), Aufwärm-Check „118 bei 150 W (**angenommen, ERG**)“ | HR + Plan-Soll | ehrlich informiert | ⚠ Nur stationäre Blöcke ≥ 2 min; Rampen und Sprints „nicht auswertbar“ |
| 7 Grenzen | „Leistungskurve und Soll/Ist brauchen echte Watt: Mac-Brücke einrichten?“ | – | kein Frust | Hinweis auf die Brücke statt Scheingenauigkeit |
| 8 Health (opt-in) | Als „Indoor Cycling“ nach Health, **ohne Leistung** | HKWorkout | Ringe | ⚠ Keine angenommenen Watt nach HealthKit |

#### J-D · Morgenmessung HRV mit Gurt (Opt-in, Enthusiasten, R4)

| Schritt | Touchpoint | Daten | Gefühl | Feature · ⚠ Fallstrick |
|---|---|---|---|---|
| 1 Aktivieren | Profil → Geräte → Gurt mit RR ✓ → „Morgenmessung aktivieren (3× pro Woche reicht)“ | – | bewusste Wahl | Nur wenn der Gurt RR liefert; nie Standard |
| 2 Messen | Heute → „Morgenmessung“: 60 s liegend, Atem ruhig, Fortschrittsring | RR-Intervalle | ruhig | ⚠ Artefakte (Bewegung, trockener Gurt) erkennen und Messung verwerfen |
| 3 Ergebnis | Nur Trend: „7-Tage-Mittel im üblichen Bereich“ ab 3 Messungen, kein Tageswert in Rot | lnRMSSD | neutral | kein Push, keine Ampel |
| 4 Nutzung | Fließt als zweites Signal in den Trend-Wächter ein | – | – | Quelle *gemessen (Gurt)*, fest gepinnt |

## 7. Produktziele und Roadmap

### 7.1 Ziele

| # | Ziel | Messbar, wenn … (Pilot, 3–5 Fahrer, Dez. 2026 – März 2027) |
|---|---|---|
| Z1 | **Weniger Ausfälle, mehr Anpassungen** | Anteil „angepasst“ an nicht wie geplant gefahrenen Einheiten ≥ 40 %; Plan-Treue nicht schlechter |
| Z2 | **Die ganze Woche ist bekannt** | ≥ 90 % der Krafteinheiten der Pilot-Fahrer haben Härte und Beinanteil; Health-Workouts erscheinen genau einmal |
| Z3 | **Pläne, die das Leben kennen** | Keine VO₂-/Schwellen-Einheit < 24 h nach „Beine schwer“, außer der Fahrer wählt sie bewusst; ≥ 80 % 👍 für Pläne im Wochenrückblick |
| Z4 | **Fortschritt ohne Wearable** | Aufwärm-Check bei ≥ 70 % der Rollenfahrten von Fahrern mit Gurt (Brücke oder iPhone) auswertbar |
| Z5 | **Gurt in der App funktioniert zuverlässig** | ≥ 90 % der iPhone-Aufzeichnungen ohne Lücke > 30 s; Mehrfachverbindung bei TICKR und H10 bestätigt |
| Z6 | **Vertrauen und Datenschutz** | 0 Kennzahlen ohne Quellenangabe; 0 Gesundheitsdaten an Claude ohne Einwilligung; kein Backend |
| Leitplanke | **Kein Nocebo** | Ausfallquote an Tagen mit Wächter-Hinweis nicht höher als ohne; keine Pushs zu Gesundheitswerten |

### 7.2 Roadmap

| Phase | Zeitraum (Vorschlag) | Thema | Inhalt | Ziele |
|---|---|---|---|---|
| **R0 · Technik-Spike** | Anfang Dez. 2026, 1–2 Tage | Risiken klären | CoreBluetooth + Live Activity bei gesperrtem Display; `HKWorkoutSession` auf dem iPhone (iOS 26); Mehrfachverbindung TICKR/H10/HRM-Pro inkl. RR auf dem zweiten Kanal; Akkuverbrauch über 1 h | Z5 |
| **R1 · Befinden zählt** | Dez. 2026 | gerätefrei | Check-in → anpassen/tauschen/Joker; Aufwärm-Check (Claude-Block + Auswertung aus FIT/Brücke); Wochenrückblick | Z1, Z4 |
| **R2 · Brustgurt in der App** | Dez. 2026 – Jan. 2027 | Gerät + Aufzeichnung | Geräte-Menü (J-A); Aufzeichnungs-Engine mit Live Activity; Rolle ohne Brücke (J-C) mit ERG-Annahme; Datenschutz-Paket Teil 1 | Z4, Z5 |
| **R3 · Kraft & ganze Woche** | Jan. 2027 | Muskel-Spur + Health | Kraft erfassen (J-B: Aufzeichnung, Vorlagen, Übungen, Härte/Beine, Nachtragen); „Andere Einheit“; HealthKit lesend + Annotation; Überlappungsregel; aerobe Fremdsportarten in der Rad-PMC; Claude-Regeln Kraft/Rad + Studio-Tage; Gewicht automatisch; Health-Export (opt-in) | Z2, Z3 |
| **R4 · Erholung im Plan** | Feb. 2027 | Kontext | Ruhepuls, Schlafdauer, Atemfrequenz, Temperatur, HRV (Apple Watch) mit Quellen-Pinning; Trend-Wächter; Erholungskontext für Claude (Einwilligung); Morgenmessung HRV mit Gurt (J-D, opt-in) | Z3, Z6 |
| **R5 · Herz im Winter Arc** | März 2027 | Motivation | Aufwärm-Puls, Ruhepuls, aerobe Effizienz, Kraft-Winter im Saisonrückblick; Pilot-Auswertung | Z4 |
| **Später / Saison 2** | ab Herbst 2027 | Ausbau | persönliche Muster (deskriptiv); intervals.icu bzw. Garmin Personal API; Rad-spezifische Kraft-Vorlagen als Inhalt (kein Generator) | – |
| **Nicht machen** | – | – | Readiness-Score, Herstellerscores, Schlafphasen/-Score, Schlaf-Serien, HRV-Ampel per Push, Ernährung, Gewichtsziele, Kraft-Umrechnung in TSS, Kraft-Coach (1RM, Progression, Videos), Satz-Marker, Outdoor-GPS-Aufzeichnung, Aggregator- oder Hersteller-Backend, Kaufempfehlungen | – |

## 8. Entscheidungen

### 8.1 Gesamtweg: A, „lokal und geräteunabhängig“

| Kriterium | A · Gurt + HealthKit + Check-in/Aufwärm-Check | B · Direkt-APIs | C · Aggregator | D · intervals.icu |
|---|---|---|---|---|
| Kein Backend, kein Konto | ✅ | ❌ | ❌ | ✅ |
| Nutzen ohne Wearable | ✅ Gurt, Check-in, Aufwärm-Check | ❌ | ❌ | ❌ |
| Rolle ohne Mac-Brücke | ✅ Gurt am iPhone | ❌ | ❌ | ❌ |
| Krafttraining | ✅ Aufzeichnung + Annotation | ◐ | ◐ | ◐ |
| Claude-Planung erlaubt | ✅ mit Einwilligung | ◐ Oura verbietet KI | ◐ | ◐ |
| Laufende Kosten | 0 € | Server | ab 99 $/Monat | 0 € |

**Begründung:** A hilft allen drei Personas, auch Markus ohne Wearable und ohne Brücke. Er bricht kein Grundprinzip und nutzt Vorhandenes: Sekundendaten-Format, Soll/Ist-Ausrichtung, „Einheit anpassen“, Joker, `RelativeEffort` und Dublettenlogik.

### 8.2 Kraft-Modell: eigene Muskel-Spur

| Option | Bewertung |
|---|---|
| Kraft per Faktor in CTL und ATL umrechnen | ✗ erfundener Faktor, bläht die Rad-Fitness auf |
| Kraft nur in die ATL | ✗ Form sinkt bei jedem Krafttag dauerhaft, Claude plant zu vorsichtig |
| **Rad-PMC bleibt rein, Kraft in eigener Muskel-Spur, Claude bekommt beides** | **✓ gewählt** |

| Spur | Inhalt | Wirkung |
|---|---|---|
| **Rad-PMC** (CTL/ATL/TSB) | Rad-Fahrten; aerobe Fremdsportarten (Laufen, Ski, Rudern, Kurs) über Puls-TSS, Etikett *geschätzt* | Winter Arc, Prognose, Form |
| **Muskel-Spur** | Muskel-Last = Härte (CR-10) × Minuten je Einheit, Beinanteil (keine/leicht/schwer), akutes Fenster 72 h; Kraft, Bouldern | Planungsregeln, Claude-Kontext, Banner, Wochenrückblick |
| **Gesamtwoche** | Stunden und Einheiten aller Sportarten | nur Anzeige, keine Rechnung |

**Planungsregeln** (weiche Vorgaben, sichtbar in der Begründung):
1. Schwere Beinarbeit < 24 h vor einer Schlüsseleinheit (VO₂/Schwelle) vermeiden. Das ist eine Faustregel aus der Praxis, keine harte Sperre.
2. Am selben Tag Intervalle zuerst, Kraft danach, mit ≥ 3 h Abstand. Ab dieser Spanne verschwindet die Interferenz (Schumann 2022).
3. Nach schweren Beinen Grundlage oder Ruhe statt VO₂.
4. Feste Studio-Tage aus dem Profil plant Claude ein.

### 8.3 Gurt: wofür, wofür nicht

| Einsatz | Entscheidung |
|---|---|
| Rolle ohne Mac-Brücke (J-C) | **✓ Kern**, Alleinstellungsmerkmal |
| Kraft im Studio (J-B) | **✓** Aufzeichnung für Fahrer ohne Uhr; mit Uhr annotieren |
| Andere Indoor-Einheit (Laufband, Kurs, Rudergerät) | **✓ schlank:** dieselbe Engine mit Sportartwahl, kein eigenes Feature-Set |
| Morgen-HRV (J-D) | **✓ Opt-in** ab R4, nur mit RR-fähigem Gurt |
| Outdoor-Lauf mit GPS, generischer Fitness-Rekorder | ✗ Das leisten Uhr und Apple Fitness; wir lesen deren Ergebnis über Health |

### 8.4 Apple Health schreiben

Optional, **Standard aus**, je Sportart einschaltbar. Geschrieben werden nur unsere eigenen Aufzeichnungen (Puls, Dauer, Workout-Typ), nie angenommene Watt und nie bei Überlappung mit einer anderen Quelle. Beim Import filtern wir die eigene Quelle aus.

## 9. Lösungskonzept

### 9.1 Prinzipien

1. **Vorschlag statt Urteil:** Daten ändern den Plan nie automatisch. Die App bietet anpassen, tauschen oder Joker an, und der Fahrer entscheidet.
2. **Trend statt Tageswert,** immer gegen die eigene Basis.
3. **Eine Quelle pro Kennzahl** (Pinning; ein Wechsel startet eine neue Basis).
4. **Quellenetiketten:** *gemessen (Gurt/Gerät)*, *angenommen (ERG)*, *geschätzt (Puls)*, *angegeben (Check-in/Härte)*, *Mindestwert*.
5. **Gesundheitsdaten verlassen das Gerät nur aggregiert, per Opt-in und nur beim Planen,** nie im Diagnose-Export.
6. **Annotieren vor Aufzeichnen:** Hat eine Uhr die Einheit schon aufgezeichnet, ergänzt IndoorCoach nur Härte und Beine.

### 9.2 Architektur (Erweiterung von [Konzept §2](02-KONZEPT.md))

```
┌──────────────────────────────── iPhone ──────────────────────────────────────┐
│ IndoorCoachKit                                                               │
│  Domain   CheckIn · WarmupCheck · MuscleLoad (sRPE, Beine, 72 h)             │
│           StrengthSession · Exercise/Template · OtherSportLoad (Puls-TSS)    │
│           WellnessTrend · RideMerge (+Overlap, +HR-Spur) · RecoverySummary   │
│           HRMeasurement-Parser (0x2A37: HR, RR, Kontakt) · lnRMSSD           │
│  Services HeartRateStrapService (CoreBluetooth, Protokoll, Reconnect)        │
│           RecordingService (Sitzung, Lücken, Persistenz bei App-Ende)        │
│           HealthKitService (lesend; optional Export eigener Einheiten)       │
│  Store    StoredStrap · StoredRecording · StoredStrengthSession              │
│           StoredCheckIn · WellnessDay · StoredRide(+source, sport, hrTrack)  │
│  UI       DevicesView · RecordingView · StrengthFinishSheet · TemplatesView  │
│           CheckInSheet · WarmupCheckCard · DataSourcesView · TrendHintCard   │
├──────────────────────────────────────────────────────────────────────────────┤
│ IndoorCoachWidgets (neues Extension-Target, App Group)                        │
│           Live Activity „Aufzeichnung“ (Sperrbildschirm, Dynamic Island)      │
│           später Widget „Heute“ (B19)                                         │
└───────┬───────────────────────┬──────────────────────────┬───────────────────┘
        │ BLE 0x180D/0x180F     │ HealthKit (lokal)        │ Claude (Aggregate, Opt-in)
        ▼                       ▼                          ▼
  Brustgurt (TICKR, H10 …)   Apple Health ◀── Watch, Garmin, Hevy …   api.anthropic.com
```

Neue Info.plist-Einträge: `NSBluetoothAlwaysUsageDescription`, `UIBackgroundModes: bluetooth-central`, `NSSupportsLiveActivities`, `NSHealthShareUsageDescription` (+ `NSHealthUpdateUsageDescription` erst mit Export). Entitlement HealthKit. Mindestversion bleibt iOS 18; die iOS-26-Wege (Live-Activity-Hintergrundrechte, `HKWorkoutSession` auf dem iPhone) stehen hinter einer Versionsprüfung.

### 9.3 Baustein 1: Check-in vor der Einheit

- **Wann:** beim Öffnen der heutigen Einheit bzw. als Karte in „Heute“, höchstens 1× pro Tag, nie per Push, nie an Ruhetagen.
- **Inhalt:** drei Fragen × drei Stufen (Beine, Schlaf, Laune) plus Kontext-Chips („Infekt“, „heiß“, „Koffein“, „Stress“), unter 10 s, überspringbar.
- **Regel:** Ab 2 negativen Antworten oder bei „Infekt“ kommen Angebote: kürzer/leichter (`WorkoutAdjust`), gegen Grundlage tauschen oder Joker.
- **Gespeichert** wird `StoredCheckIn` inklusive angebotener und gewählter Aktion (Messgröße für Z1).

### 9.4 Baustein 2: Aufwärm-Check

- **Plan:** Claude baut in jedes Warm-up einen Standardblock ein: 6 min bei fester Referenzleistung in Watt, anfangs 55–60 % FTP, mit Kadenzhinweis und Textevent „Aufwärm-Check“. Die Referenz ändert sich nur durch eine bewusste „neue Basis“.
- **Auswertung:** Ausrichtung über `IntervalCompliance`, gewertet wird das Puls-Mittel der letzten 60 s. Gültigkeit:
  - Leistung ±5 % (mit FIT/Brücke) oder ERG-Annahme (Gurt am iPhone),
  - plausible Kadenz,
  - keine Aussetzer.
- **Etiketten:** *gemessen* bei FIT/Brücke, *angenommen (ERG)* bei Gurt am iPhone.
- **Anzeige:** Trend erst ab 3 Messungen. Nie eine Ermüdungsaussage aus diesem Wert allein, denn auch Overreaching dämpft den Puls.
- **Name:** „Aufwärm-Check“, nicht „LSCT“.

### 9.5 Baustein 3: Brustgurt-Modul

- **`HeartRateStrapService`:**
  - Scan nach 0x180D nur im Vordergrund.
  - Verbinden über die gespeicherte Peripheral-ID.
  - Liest Heart Rate Measurement (0x2A37: 8/16-bit HR, Sensorkontakt, RR in 1/1024 s), Battery Level (0x2A19) und Device Information.
  - Nach Abbruch sofort `connect` erneut absetzen (iOS verbindet automatisch wieder).
  - Läuft hinter einem Protokoll, damit Tests mit Stub-Peripherals möglich sind.
- **Fähigkeiten:** Erkennt RR, Akkustand und Mehrfachverbindung (Test im Koppel-Flow). Ein Modellwissen-Katalog (TICKR 3, H10 2 nach Aktivierung, H9 1, HRM-Pro 3, H9Z 2) liefert Hinweise, keine Sperren.
- **`RecordingService`:**
  - 1-Hz-Pulsspur im vorhandenen `RideSeconds`-Format (Leistung 0 bzw. Soll bei ERG-Annahme), Lücken als Lücken.
  - Zwischenspeicherung alle 30 s, damit ein App-Ende keine Daten verliert.
  - Startet und beendet die Live Activity.
  - Typen: Rad (mit Plan), Kraft, Andere.
- **Rolle ohne Brücke:**
  - Startsynchronisation per Knopf, nachträgliche Ausrichtung am Ende des Aufwärmens bzw. am Pulsanstieg, manuell schiebbar.
  - Zusammenführung mit der MyWhoosh-Fahrt aus der Liste, die Pulsspur wird angehängt.
  - ERG-Annahme nur in stationären Blöcken ≥ 2 min.
  - Leistungskurve und Soll/Ist werden **nicht** aus angenommenen Watt berechnet.
- **Morgenmessung (R4):** 60 s RR → Artefaktfilter → lnRMSSD, 7-Tage-Mittel, nur mit RR-fähigem Gurt.

### 9.6 Baustein 4: Kraft & ganze Woche

- **Erfassungswege:**
  1. Aufzeichnung mit Gurt (J-B),
  2. Nachtragen ohne Gurt,
  3. Annotation eines Health-Workouts (`traditionalStrengthTraining`, `functionalStrengthTraining`, `climbing`, `coreTraining` …).
- **Abschluss:** Härte (CR-10, Skala aus `RelativeEffort.perceivedExertionLabels`) und Beinanteil, vorbelegt aus den Übungen. Muskel-Last = Härte × Minuten.
- **Übungskatalog:** ca. 40 Übungen mit Muskelgruppen und Beinanteil (Kniebeuge, Kreuzheben, Ausfallschritt, Beinpresse, Step-up, Hip Thrust, Wadenheben, Rumpf, Oberkörper …). Vorlagen mit „wie letzte Woche“. Sätze × Wdh × Gewicht nur optional, mit Vorwerten. Kein Satz-Marker.
- **Andere Einheit:** Sportartwahl, dieselbe Aufzeichnung. Aerobe Sportarten bekommen Puls-TSS in der Rad-PMC (*geschätzt*), Kraft und Bouldern gehen in die Muskel-Spur.
- **HealthKit lesend:**
  - Anchored Query + Observer/Background Delivery für Workouts.
  - Gewicht als 7-Tage-Mittel.
  - Die eigene Quelle wird ausgefiltert.
- **Überlappungsregel:**
  - Überlappt ein Workout zu ≥ 50 % mit einer vorhandenen Einheit, entsteht keine neue Belastung. Fehlender Puls wird ergänzt, mit der Priorität FIT/Brücke > Gurt am iPhone > Health > MyWhoosh-Liste.
  - Rad-Workouts aus Health ohne Überlappung zählen als Outdoor- oder Fremdfahrt.
  - Jede Zusammenführung ist sichtbar und lässt sich rückgängig machen.
- **Claude:** `PlanContext` bekommt die Muskel-Spur (Einheiten der letzten 7 Tage mit Datum, Härte × min, Beine), die aerobe Fremdbelastung und die Studio-Tage aus dem Profil. Der System-Prompt bekommt die Regeln aus §8.2, und die Begründung nennt sie.
- **Motivation:** Kraft zählt für die Wochen-Serie und hat eigene Trophäen („Kraft-Winter“). Die Winter-Reise bleibt an der Rad-PMC.
- **Health-Export (opt-in):** wie in §8.4.

### 9.7 Baustein 5: Erholungsdaten, Trend-Wächter, Claude-Kontext

- **Tageswerte:** `WellnessDay` (Ruhepuls, HRV, Schlafdauer, Atemfrequenz, Temperatur, Gewicht, Morgenmessung) mit Quellen-Pinning.
- **Trend-Wächter:**
  - Er schlägt an, wenn das 3-Tage-Mittel des Ruhepulses deutlich über der 28-Tage-Basis liegt **und** ein zweites Signal dazukommt (Check-in, Atemfrequenz/Temperatur, Morgen-HRV).
  - S0-Variante ohne Ruhepuls: Check-in und Aufwärm-Check.
  - Erst im Schattenmodus, dann als ruhige Karte vor harten Einheiten.
  - Kein Push, keine Diagnose, kein Rot.
- **Claude-Kontext:**
  - `RecoverySummary` mit relativen 14-Tage-Aggregaten.
  - Nur mit Einwilligung (Apple 5.1.2(i)), widerrufbar, mit Vorschau „Das geht an Claude“.
  - Ohne Rohwerte, Gerätenamen und Diagnosebegriffe.

### 9.8 Baustein 6: Herz im Winter Arc

Monatskarte mit Aufwärm-Puls, Ruhepuls-Basis und aerober Effizienz, dazu „Kraft-Winter“. Im Saisonrückblick erscheint eine Zeile je verfügbarer Kennzahl, immer mit Quelle.

### 9.9 Datenschutz und Compliance

- Bluetooth- und Health-Texte nennen den Zweck konkret. PrivacyInfo, [PRIVACY.md](PRIVACY.md) und die App-Store-Datenschutzangaben werden um Gesundheits- und Fitnessdaten ergänzt.
- „Alle Daten löschen“ entfernt Gurte, Aufzeichnungen, Krafteinheiten, Check-ins, Wellness-Tage und Health-Importe. In Health wird nichts gelöscht; Exporte löscht der Nutzer dort selbst, und die App sagt das.
- Diagnose-Export: nur Zähler, Typnamen, Gurtmodell und Verbindungsstatus, keine Werte.
- Juristische Prüfung der Formulierungen (MDR, Art. 9 DSGVO, App Review 5.1.2/5.1.3).

## 10. Backlog

Legende wie im [Pilot-Backlog](06-BACKLOG-PILOT.md): **Agent** = im Repo umsetzbar, **Nutzer** = braucht Konto, echtes Gerät oder eine Entscheidung. Größe S/M/L. IDs schließen an B25 an (Version 1 hatte B26–B46; die Nummern sind neu vergeben).

### 10.1 Offene Punkte

| ID | Offener Punkt | Wer | Bis | Blockiert |
|---|---|---|---|---|
| O1 | ✅ **Geklärt 19.11.2026:** MyWhoosh schreibt nicht nach Apple Health (Fahrt am Mac). Offen ist nur, ob MyWhoosh auf iPad/iPhone gefahren anders handelt; geprüft wird das im Gerätetest bei Gelegenheit. | Nutzer | – | – |
| O2 | Welche Typen schreiben Garmin, Whoop, Oura, Fitbit, **Hevy und Strong** tatsächlich nach Health? | Nutzer + Pilot | vor R3 | B47, B52 |
| O3 | Juristische Kurzprüfung: MDR (Trend-Wächter), Art. 9 DSGVO (Puls, HRV, Kraft), App Review 5.1.2(i)/5.1.3 (Aggregate an Claude, HealthKit-Export) | Nutzer (ggf. extern) | vor R3 | B41, B51, B55, B56 |
| O4 | Pilot-Fragebogen: Gurtmodell, Uhr/Ring, Studio ja/nein und wie oft, Kraft-App (Hevy/Strong/Garmin), Mac-Brücke ja/nein, ERG-Modus in MyWhoosh ja/nein | PO + Nutzer | Pilotstart | – |
| O5 | Referenzleistung und Dauer des Aufwärm-Checks (55/60 % FTP, 5/6 min, Kadenz) gegen echte Fahrten testen | PO + Agent | R1 | B30 |
| O6 | Puls-TSS-Methode für aerobe Fremdsportarten (hrTSS oder TRIMP) | PO | R3 | B45, B47 |
| O7 | Schwellen des Trend-Wächters im Pilot kalibrieren (Schattenmodus) | PO + Pilot | R4 | B55 |
| O8 | iOS 27 / Watch S12: RMSSD-Typ in HealthKit befüllt? | Agent + Nutzer | R4 | B52 |
| O9 | Puls in FIT-Dateien: Gurt oder Uhr? (Geräte-Info im FIT, sonst Plausibilität) | Agent | R1 | B31 |
| O10 | Erfolgsmessung ohne Telemetrie: anonymisierte Zähler im Diagnose-Export + Plan-Feedback | PO | Pilotstart | B58 |
| O11 | **Mehrfachverbindung und RR auf dem zweiten Kanal** mit TICKR, H10 (aktiviert) und HRM-Pro Plus, während MyWhoosh am Mac verbunden ist | Nutzer (Geräte) + Agent | R0 | B35, B39 |
| O12 | **Hintergrundbetrieb:** CoreBluetooth + Live Activity bei gesperrtem bzw. ausgeschaltetem Display über 60 min; `HKWorkoutSession` auf dem iPhone (iOS 26) als Alternative; Verhalten unter iOS 18 | Agent + Nutzer (Gerät) | R0 | B37, B38 |
| O13 | **Widget-Extension-Target + App Group** für die Live Activity (Signierung, Provisioning; Synergie mit dem Widget „Heute“, B19) | Nutzer + Agent | R2 | B38 |
| O14 | **ERG-Annahme:** Fährt der Nutzer MyWhoosh-Workouts im ERG-Modus? Wie stark weicht die Ist-Leistung in stationären Blöcken ab? (mit Brücken-Daten des Nutzers prüfen) | Nutzer + Agent | R2 | B40 |
| O15 | **Übungskatalog:** Auswahl der ca. 40 Übungen, Muskelgruppen, Beinanteil; Sprache und Begriffe | PO | R3 | B44 |
| O16 | **Faustregel „24 h nach schweren Beinen“:** Formulierung in der Begründung, Stärke der Vorgabe im Prompt; nicht quantifiziert belegt | PO | R3 | B49 |
| O17 | **Mindest-iOS:** bei iOS 18 bleiben oder auf 26 anheben, wenn die Hintergrundrechte nur dort stabil sind? | Nutzer (Entscheidung) | nach R0 | B37 |

### 10.2 Umsetzungsaufgaben

#### R0 · Technik-Spike

| ID | Aufgabe | Wer | Größe | Abnahme |
|---|---|---|---|---|
| B26 | **Spike Gurt & Hintergrund:** Wegwerf-Prototyp mit CoreBluetooth (HR, RR, Akku), Live Activity, gesperrtem Display 60 min; Variante `HKWorkoutSession` (iOS 26); Mehrfachverbindung mit MyWhoosh am Mac (O11, O12); Akkuverbrauch. Ergebnis als kurzes ADR im Konzept. | Agent + Nutzer (Geräte) | M | Messprotokoll: Lücken, Abbrüche, Akku je Gurt und iOS-Version; Empfehlung zu O17. |

#### R1 · Befinden zählt (gerätefrei)

| ID | Aufgabe | Wer | Größe | Abnahme |
|---|---|---|---|---|
| B27 | **Check-in Domain + Store:** `CheckIn`, `StoredCheckIn`, Migration, Angebotsregel | Agent | S | Unit-Tests: Regel, 1× pro Tag, Migration ohne Datenverlust |
| B28 | **Check-in UI:** Sheet beim Öffnen der Einheit, Karte in „Heute“, überspringbar, Dynamic Type, VoiceOver | Agent | M | UI-Test Check-in → Angebot → „45 min“; Accessibility-Audit grün |
| B29 | **Angebote verdrahten:** kürzer/leichter (`WorkoutAdjust` inkl. MyWhoosh-Ersetzen, Kalender), gegen Grundlage tauschen (regelbasiert, gleiche Dauer), Joker | Agent | M | Unit-Tests je Aktion; Tausch ergibt gültige `WorkoutDefinition` |
| B30 | **Aufwärm-Check im Plan:** Profilfeld `warmupCheckWatts` + „neue Basis“; Prompt-Regel; Parser ergänzt fehlenden Block; Schalter bei manuellen Einheiten; `.zwo`-Textevent | Agent | M | Unit-Tests Prompt/Parser/`.zwo`; Live ein Plan mit Block (Nutzer) |
| B31 | **Aufwärm-Check Auswertung:** `WarmupCheck` aus `RideSeconds` + Ausrichtung, Gültigkeitsregeln, Etiketten *gemessen* / *angenommen (ERG)*, Cache | Agent | M | Unit-Tests: gültig, Leistung verfehlt, Aussetzer, kein Puls, FTP-Wechsel |
| B32 | **Aufwärm-Check UI:** Karte in Fahrt-Detail und Leistung, Trend ab 3 Messungen, Kontext-Chips, Erklärung ohne Gurt; Seed `-uiWarmupSeed` | Agent | M | UI-Test mit Seed, Etikett sichtbar |
| B33 | **Wochenrückblick erweitern:** angepasst statt ausgefallen, Aufwärm-Trend, Plan-Feedback 👍/👎; später Gesamtwoche (B50) | Agent | S | Unit-Test Text; UI-Test Feedback |

#### R2 · Brustgurt in der App

| ID | Aufgabe | Wer | Größe | Abnahme |
|---|---|---|---|---|
| B34 | **Parser Heart Rate Measurement + lnRMSSD:** 0x2A37 (8/16 bit, Kontakt, Energie, RR in 1/1024 s), Battery 0x2A19; RR-Artefaktfilter; plattformneutral in `Domain` | Agent | S | Unit-Tests mit Byte-Fixtures echter Gurte (aus B26) |
| B35 | **`HeartRateStrapService`:** CoreBluetooth hinter Protokoll, Scan nur im Vordergrund, gespeicherte ID, automatischer Reconnect, Fähigkeiten (RR, Akku), Modellwissen-Hinweise; `NSBluetoothAlwaysUsageDescription`, `bluetooth-central` | Agent | M | Unit-Tests mit Stub-Peripheral (Abbruch, Reconnect, zwei Gurte); Gerätetest TICKR + H10 (Nutzer) |
| B36 | **Geräte-Menü (J-A):** Profil → Geräte → Brustgurt (Suche, Verbinden, Live-Puls, Fähigkeiten, Akku, Mehrfachverbindungs-Test mit Anleitung je Modell, Vergessen); Plan-Karte „Puls auch ohne Mac-Brücke“ | Agent | M | UI-Test mit Stub; UX-Review der Texte |
| B37 | **`RecordingService`:** Sitzungen Rad/Kraft/Andere, 1-Hz-Spur im `RideSeconds`-Format, Lücken, Zwischenspeicherung alle 30 s, Wiederaufnahme nach App-Ende, Akku-Hinweis | Agent | M | Unit-Tests: Lücke, App-Ende, Wiederaufnahme; Gerätetest 60 min gesperrt (Nutzer) |
| B38 | **Live Activity:** neues Widget-Extension-Target, App Group, Sperrbildschirm + Dynamic Island (Zeit, Puls, Block/Übung, Stopp) | Agent + Nutzer (Signierung, O13) | M | Build in CI; Sichtprüfung auf dem Gerät |
| B39 | **Aufzeichnungs-UI Rad (J-C):** „Puls am iPhone mitschreiben“ in der Einheit, Start-Sync, Plan-Zeitleiste, Verbindungsstatus | Agent | M | UI-Test mit Stub-Gurt und Demo-Plan |
| B40 | **Rolle ohne Brücke – Auswertung:** Zusammenführung mit MyWhoosh-Fahrt, Pulsspur anhängen; Ausrichtung (Ende Aufwärmen/Pulsanstieg, manuell schiebbar); ERG-Annahme nur in stationären Blöcken ≥ 2 min; Zeit in Pulszonen, TRIMP, Aufwärm-Check; keine Leistungskurve/Soll-Ist aus Annahmen; Hinweis auf die Brücke | Agent | M | Unit-Tests: Versatz, Rampen „nicht auswertbar“, Merge ohne Dublette; Abgleich mit echter Brückenfahrt (O14) |
| B41 | **Datenschutz-Paket Teil 1:** PRIVACY.md, PrivacyInfo, App-Store-Angaben (Gesundheit/Fitness), „Alle Daten löschen“ um Gurte und Aufzeichnungen, Diagnose-Export ohne Werte | Agent + Nutzer | S | Unit-Tests Löschen/Export |

#### R3 · Kraft & ganze Woche

| ID | Aufgabe | Wer | Größe | Abnahme |
|---|---|---|---|---|
| B42 | **Muskel-Spur Domain:** `MuscleLoad` (Härte × min, Beinanteil, 72-h-Fenster, Wochensumme), `StoredStrengthSession` (Quelle: Aufzeichnung/manuell/Health-Annotation) | Agent | S | Unit-Tests: Fenster, Beinanteil aus Übungen, keine Wirkung auf CTL/ATL |
| B43 | **Kraft erfassen UI (J-B):** Schnellstart in „Heute“, Aufzeichnung mit Übungsliste zum Abhaken, Abschluss-Sheet Härte + Beine, Nachtragen ohne Gurt, Kraft-Detail im Verlauf, Filter Rad/Kraft/Andere | Agent | L | UI-Tests: Vorlage → Aufzeichnung → Abschluss; Nachtragen in < 15 s |
| B44 | **Übungskatalog + Vorlagen:** ca. 40 Übungen mit Muskelgruppen und Beinanteil (O15), Vorlagen, „wie letzte Woche“, optionale Sätze × Wdh × Gewicht mit Vorwerten; Profil → Kraft | Agent + PO (Inhalt) | M | Unit-Tests Vorlage kopieren, Beinanteil-Ableitung; Einhand-Bedienung im UX-Review |
| B45 | **Andere Einheit:** Sportartwahl (Laufband, Kurs, Rudergerät, Sonstiges), gleiche Aufzeichnung; aerob → Puls-TSS (*geschätzt*) in der Rad-PMC | Agent | S | Unit-Tests Zuordnung aerob/Muskel |
| B46 | **HealthKit-Service lesend:** Protokoll + Stub, Anchored Query, Observer + Background Delivery für Workouts, Gewicht, eigene Quelle ausfiltern; Entitlement, `NSHealthShareUsageDescription` | Agent + Nutzer (Entitlement) | L | Unit-Tests mit Stub; Gerätetest Freigabe-Dialog |
| B47 | **Annotation und Fremdsport:** Health-Kraft, Klettern, Rumpf → Karte „Wie hart? Beine?“; aerobe Workouts mit Puls-TSS (O6) in die Rad-PMC; nicht in Leistungskurve/eFTP/Soll-Ist | Agent | M | Unit-Tests: Garmin-Kraft, Lauf mit Puls, Lauf ohne Puls |
| B48 | **Überlappungsregel:** `RideMerge` mit ≥ 50 % Überlappung und Priorität FIT/Brücke > Gurt-iPhone > Health > Liste; Studio: Uhr + eigene Aufzeichnung → „nur annotieren“; Zusammenführung sichtbar und rückgängig machbar | Agent | M | Unit-Tests: Uhr startet 4 min früher, Garmin-Duplikat, echte Outdoor-Fahrt; Gerätetest Watch + MyWhoosh (Nutzer) |
| B49 | **Claude kennt die Woche:** `PlanContext` um Muskel-Spur, aerobe Fremdbelastung und Studio-Tage (Profil) erweitern; Prompt-Regeln §8.2 als weiche Vorgaben (O16); Plan-Banner „schwere Beine – tauschen?“ | Agent | M | Unit-Tests Prompt-Inhalt; Live-Plan legt VO₂ nicht auf den Tag nach Studio-Beinen (Nutzer) |
| B50 | **Motivation & Profil:** Gesamtwoche im Wochenrückblick, Kraft zählt für die Serie, Trophäe „Kraft-Winter“, Winter Arc mit Fremdsport; Gewicht automatisch (7-Tage-Mittel) | Agent | M | Unit-Tests: Studiowoche hält die Serie; Gewicht aus Health mit manuellem Rückfall |
| B51 | **Datenquellen-Ansicht + Health-Export (opt-in):** Profil → Datenquellen (Typen, erkannte Quellen, ehrliche Lücken, Methodenseite); Export eigener Einheiten je Sportart, Überlappungsprüfung, keine angenommenen Watt | Agent | M | UI-Test Freigabe mit Stub; Unit-Tests: kein Export bei Überlappung, keine Leistung im ERG-Fall |

#### R4 · Erholung im Plan

| ID | Aufgabe | Wer | Größe | Abnahme |
|---|---|---|---|---|
| B52 | **Wellness-Tageswerte:** `WellnessDay` aus Health (Ruhepuls, HRV, Schlafdauer, Atemfrequenz, Temperatur) mit Quellen-Pinning | Agent | M | Unit-Tests: Quellenmischung → nur gepinnte; Schlafdauer aus Phasen |
| B53 | **Trend-Berechnung:** 28-Tage-Basis, 3-/7-Tage-Mittel, Mindestdaten, Median | Agent | S | Unit-Tests |
| B54 | **Morgenmessung HRV (J-D, opt-in):** 60-s-Messung mit RR, Artefaktfilter, lnRMSSD-Trend, nur mit RR-fähigem Gurt | Agent | M | Unit-Tests mit RR-Fixtures; Gerätetest H10 (Nutzer) |
| B55 | **Trend-Wächter:** Regel „Ruhepuls + zweites Signal“, S0-Variante, Schattenmodus (O7), Karte vor harter Einheit, Angebote aus B29; keine Pushs | Agent + PO | M | Unit-Tests Regel/Schattenmodus; Code enthält keine Push-Mitteilung dafür |
| B56 | **Claude-Kontext „Erholung“:** `RecoverySummary`, Einwilligungs-Sheet (5.1.2(i)), Vorschau, widerrufbar; Datenschutz-Paket Teil 2 | Agent + Nutzer (Rechtstext) | M | Unit-Tests: ohne Einwilligung nichts im Prompt; keine Rohwerte/Gerätenamen |

#### R5 · Herz im Winter Arc

| ID | Aufgabe | Wer | Größe | Abnahme |
|---|---|---|---|---|
| B57 | **„Dein Herz im Winter Arc“:** Monatskarte Aufwärm-Puls, Ruhepuls, aerobe Effizienz, Kraft-Winter; Saisonrückblick und Teilen-Bild erweitert | Agent | M | UI-Test mit Seed; Snapshots Dark Mode/große Schrift |
| B58 | **Pilot-Zähler (O10):** Check-ins, angenommene Angebote, Aufzeichnungen und Lücken, Krafteinheiten mit Härte, Wächter-Treffer im Diagnose-Export | Agent | S | Export enthält nur Zähler |

#### Später / Saison 2

| ID | Aufgabe | Voraussetzung |
|---|---|---|
| B59 | Wellness aus intervals.icu (persönlicher Key) oder Garmin Personal API | Bedingungen prüfen (KI-Klauseln) |
| B60 | Persönliche Muster, nur deskriptiv, Mindest-n je Zelle; Rad-spezifische Kraft-Vorlagen als Inhalt | Saison 2, genug Daten |

### 10.3 Reihenfolge und Abhängigkeiten

```
R0:  B26 ─────────────────────────────────────────────┐ (klärt O11, O12, O17)
R1:  B27 ─▶ B28 ─▶ B29 ─▶ B33       B30 ─▶ B31 ─▶ B32  │
R2:  B34 ─▶ B35 ─▶ B36              B26 ─▶ B37 ─▶ B38 ─▶ B39 ─▶ B40     B41
R3:  B42 ─▶ B43 ─▶ B44  (B37 für die Aufzeichnung)    B45
     B46 ─▶ B47 ─▶ B48 ─▶ B51        B42 + B47 ─▶ B49 ─▶ B50
R4:  B46 ─▶ B52 ─▶ B53 ─▶ B55        B34 ─▶ B54          B27 + B52 ─▶ B56
R5:  B32 + B53 ─▶ B57                B58
```

**Parallelisierbar:**
- R1 braucht weder Gurt noch HealthKit und kann sofort starten.
- B34 (Parser) und B42 (Muskel-Spur Domain) sind reine Domain-Logik und laufen parallel zum Spike.
- Erst nach B26 entscheidet sich, ob B37/B38 auf CoreBluetooth + Live Activity oder auf `HKWorkoutSession` (iOS 26) aufsetzen.

## 11. Umsetzungsstand (19.11.2026)

Die Roadmap R0–R5 wurde in Wellen von Sonnet-Subagents (TDD, je Paket eigener Worktree, exklusive Dateien) umgesetzt. Der PO hat integriert, geprüft und entschieden. Danach liefen ein Code-Review (12 Befunde, alle behoben) und ein QA-Paket für die UI-Walkthroughs. Es gibt nichts gepusht; alles liegt lokal auf `main`.

**Qualität:** 939 Unit-Tests in 114 Suiten grün (vor der Roadmap 455). iOS-Build mit Widget-Extension grün. Die neuen UI-Walkthroughs (Check-in, Aufwärm-Check, Gurt, Aufzeichnung, Kraft, Kraft-Aufzeichnung, Datenquellen, Morgenmessung, Einheit anpassen) laufen mit 0 weichen Fehlern (`CHECK|FAIL`). In den älteren Walkthroughs bleibt ein weicher Fehler: Der Simulator hat keinen Kalenderzugriff („Kalender aktualisieren“).

### 11.1 Stand je Aufgabe

| ID | Stand | Anmerkung |
|---|---|---|
| B26 | ◐ | Gerätetest-Protokoll im Geräte-Menü (Mitschnitt, Lücken, Reconnects, Akku) und Ablauf in [Gerätetest Teil 7](16-GERAETETEST.md). Die Messung mit echten Gurten (O11, O12, O17) braucht den Nutzer. |
| B27–B29 | ✅ | Check-in mit Angeboten kürzer/leichter, Tausch gegen Grundlage, Joker |
| B30–B32 | ✅ | Aufwärm-Check im Plan, Auswertung *gemessen* / *angenommen (ERG)*, Karte und Trend |
| B33 | ✅ | „angepasst statt ausgefallen“, Aufwärm-Trend im Rückblick, Plan-Feedback 👍/👎 (lokal, im Pilot-Zähler) |
| B34–B36 | ✅ | Parser 0x2A37/0x2A19, RR-Filter, `HeartRateStrapService` mit Reconnect (Backoff 2/5/10/30 s, 60-s-Rückfall-Scan), Geräte-Menü |
| B37 | ✅ | `RecordingService` 1 Hz, Zwischenspeicher, Wiederaufnahme nach App-Ende. Der Test mit gesperrtem Display über 60 min steht aus. |
| B38 | ◐ | Widget-Extension `IndoorCoachWidgets` mit Live Activity gebaut. Signierung und Sichtprüfung auf dem Gerät brauchen den Nutzer (O13). |
| B39–B40 | ✅ | Aufzeichnung Rad, Merge mit MyWhoosh-Fahrt, ERG-Annahme nur in stationären Blöcken, angenommene Watt nie in Erholung, Wächter oder Health |
| B41 | ✅ | PRIVACY.md, PrivacyInfo, Löschen inklusive Gurte und Aufzeichnungen, Diagnose ohne Werte, Dateien ohne Backup und mit Dateischutz |
| B42–B45 | ✅ | Muskel-Spur (nicht in CTL/ATL), Kraft erfassen/nachtragen (< 15 s), 41 Übungen, Vorlagen, Andere Einheit |
| B46–B48 | ◐ | HealthKit lesend (Anker erst nach dem Speichern, Zeitfenster-Abfragen), Annotation, Fremdsport mit hrTSS/TRIMP, Überlappungsregel. Code und Tests sind fertig. Das Entitlement und der Freigabe-Dialog auf dem Gerät brauchen den Nutzer. |
| B49–B50 | ✅ | Claude kennt die Woche (weiche Regeln, Banner „Faustregel“), Serie zählt Wochen mit mindestens 2 Einheiten jeder Art, Gewicht aus Health |
| B51 | ✅ | Datenquellen-Ansicht, Health-Export opt-in ohne Leistung |
| B52–B55 | ✅ | Wellness mit Quellen-Pinning, Trends, Morgenmessung HRV, Trend-Wächter im Schattenmodus mit Zähler „Karte angezeigt“ |
| B56 | ✅ | Erholung an Claude nur mit Einwilligung v2. Die juristische Prüfung (O3) ist offen. |
| B57–B58 | ✅ | Herz im Winter Arc mit Saisonrückblick, Pilot-Zähler im Diagnose-Export |
| B59–B60 | – | Saison 2 |

### 11.2 Entscheidungen des PO während der Umsetzung

- **O5:** Referenz 55 % FTP, Messfenster in den letzten Minuten des Aufwärmblocks. Die Kalibrierung mit echten Fahrten folgt im Pilot.
- **O6:** hrTSS mit Schwellenpuls. Ohne Schwellenpuls TRIMP-basiert (Annahme 85 % der Herzfrequenzreserve), sonst Sportfaktor. Immer als *geschätzt* gekennzeichnet.
- **O15:** Katalog mit 41 Übungen (inklusive Dips) und Beinanteilen abgenommen.
- **O16:** Die Faustregel ist eine weiche Regel im Prompt. In der App erscheint sie nur als Banner-Vorschlag mit dem Wort „Faustregel“, ohne automatisches Verschieben.
- **Health an Claude:** Fremdsport und Erholung gehen nur mit Einwilligung (v2) an Claude. Ohne Einwilligung bleibt es bei den Raddaten.
- **Indoor-Fahrten aus Health** zählen als Rolle (`trainer`).
- **Dateischutz:** `completeUntilFirstUserAuthentication`, damit eine Aufzeichnung bei gesperrtem Display weiterschreiben kann.

### 11.3 Was nur der Nutzer erledigen kann

1. **Signierung:** Team und Provisioning für das Widget-Target `app.indoorcoach.personal.widgets` sowie die HealthKit-Fähigkeit. Die Team-ID bleibt dabei lokal.
2. **Gerätetest Gurt (O11, O12, O17):** TICKR, H10 und HRM-Pro mit gleichzeitig verbundenem MyWhoosh. Dazu 60 min bei gesperrtem Display mit Live Activity.
3. **Gerätetest Health (O2, O8):** Freigabe-Dialog, welche Typen Garmin, Hevy und Strong schreiben, und RMSSD.
4. **Juristische Kurzprüfung (O3)** vor einer Veröffentlichung.
5. **Pilot:** Fragebogen (O4) und Kalibrierung des Trend-Wächters im Schattenmodus (O7).

## 12. Quellen (Auswahl, vollständige Listen in den drei BA-Berichten)

**Sportwissenschaft:**
- Saw, Main & Gastin 2016, BJSM ([Link](https://bjsm.bmj.com/content/50/5/281.short))
- Granero-Gallegos et al. 2020 ([PMC7663087](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7663087/))
- Dial et al. 2025 ([PMC12367097](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12367097/))
- Plews et al. ([PubMed 22367011](https://pubmed.ncbi.nlm.nih.gov/22367011/))
- Buchheit 2014 ([PMC3936188](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3936188/))
- Lamberts et al. 2011 ([PubMed 19622525](https://www.ncbi.nlm.nih.gov/pubmed/19622525))
- Gavriloff et al. 2018 ([PubMed 29989248](https://pubmed.ncbi.nlm.nih.gov/29989248/))
- Mishra et al. 2020 ([Link](https://communities.springernature.com/posts/early-detection-of-covid-19-at-scale-using-wearables))
- Session-RPE nach Foster, Validität und Reliabilität ([Impellizzeri u. a.](https://researchgate.net/profile/Franco-Impellizzeri/publication/261067400_Establishing_the_Criterion_Validity_and_Reliability_of_Common_Methods_for_Quantifying_Training_Load/links/5caee628a6fdcc1d498c2081/Establishing-the-Criterion-Validity-and-Reliability-of-Common-Methods-for-Quantifying-Training-Load.pdf))
- Schumann et al. 2022, Interferenz ([Preprint](https://sportrxiv.org/index.php/server/preprint/download/37/71/54))
- Eddens et al. 2018 ([PubMed 28917030](https://pubmed.ncbi.nlm.nih.gov/28917030/))
- Krafttraining bei Radfahrern ([PMC8006227](https://pmc.ncbi.nlm.nih.gov/articles/PMC8006227))

**Geräte, APIs, Plattform:**
- Wahoo TICKR, Mehrfachverbindung ([Support](https://support.wahoofitness.com/hc/en-us/articles/204281384))
- Polar H10, mehrere Geräte ([Support](https://support.polar.com/en/support/can_i_pair_h10_with_several_devices))
- Garmin HRM 600 ([the5krunner](https://the5krunner.com/2025/05/15/garmin-hrm-600-everything-you-need-to-know/))
- CoreBluetooth ([Apple](https://developer.apple.com/documentation/corebluetooth)) und Live Activity im Hintergrund ([Forum](https://developer.apple.com/forums/thread/815189))
- HKWorkoutSession ([Apple](https://developer.apple.com/documentation/healthkit/running-workout-sessions))
- iOS 26 Fitness mit Gurt ohne Watch ([MacStories](https://www.macstories.net/stories/watchos-26-the-macstories-review/3/))
- Garmin/Whoop/Oura → Apple Health ([SensAI](https://www.sensai.fit/blog/wearable-apple-health-integration-what-syncs-oura-whoop-garmin))
- Oura-API und KI-Klausel ([Oura](https://partnersupport.ouraring.com/hc/en-us/articles/20949682312211-The-Oura-API))
- Garmin Personal API ([the5krunner](https://the5krunner.com/2026/10/22/garmin-personal-api/))
- Fitbit Air → Health ([iPhone in Canada](https://www.iphoneincanada.ca/2026/08/03/you-can-now-sync-google-fitbit-air-data-with-apple-health/))
- Apple-Richtlinie 5.1.2(i) ([Apple](https://developer.apple.com/news/?id=ey6d8onl))

**Wettbewerb:**
- Whoop Muscular Load ([Whoop](https://www.whoop.com/ca/en/thelocker/how-whoop-measures-muscular-load/))
- TrainingPeaks Strength ([TrainingPeaks](https://www.trainingpeaks.com/training-plans/cycling/tp-307899/strength-for-cyclists-8-weeks))
- Kraft-Apps für Radfahrer ([Roadman Cycling](https://roadmancycling.com/best/best-cycling-strength-training-apps))

**Hinweis zur Quellenlage:** Viele Geräte- und API-Details stammen aus Sekundärquellen, oft von Integrationsanbietern; Europreise sind teils nur als UVP belegt. Der Technik-Spike B26 und die offenen Punkte O2, O8, O11 und O12 klären das auf echten Geräten.
