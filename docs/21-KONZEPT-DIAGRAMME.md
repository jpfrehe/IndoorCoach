# 21 · Konzept: Diagramme überarbeiten

Stand: 21.11.2026 · erarbeitet mit einem Design-Engineer-Agent (Datenvisualisierung) · Status: **umgesetzt (21.11.2026)**, Entscheidungen in §9 und „Entschieden“ am Ende

**Auftrag (Produktinhaber, wörtlich):** „Führe eine Überarbeitung der Diagramme durch. Die Auflösung der aktuellen, gerade bei Intervallen oder Aufwärmphasen besteht aus unscharfen Blöcken. Die Diagramme sind Kernbestandteil der Analysen und sollen hochwertig aussehen, wie angehängte Beispiele."

**Ziel in einem Satz:** Ein kleines Diagramm-Designsystem (Farben, Linien, Marker, Achsen) und ein neu gezeichnetes Workout-Profil. Beides wirkt in allen 20 Diagrammen der App gleich, ist scharf auf dem Pixelraster und hält 3:1-Kontrast ohne „Jelly-Kappen“.

**Nicht-Ziele:** keine neuen Kennzahlen und keine neuen Datenquellen. Keine Änderung an Rechenlogik (TSS, CTL, Leistungskurve). Die Jelly-Farben für Chips, Badges und Typ-Icons bleiben unverändert. Kein Wechsel weg von Swift Charts, außer beim Workout-Profil (§4.2).

**Referenzen:** vier Bilder des Produktinhabers (Trainingsplan-Startseite, zwei Workout-Minis, Analyse-Seite). Daraus übernommen werden:
- getrennte, abgerundete Blöcke je Abschnitt; die Höhe zeigt die Intensität, die Farbe die Zone;
- schmale Stäbe für kurze Intervalle und eine ruhige, dunkle Erholungs-Grundlinie;
- geglättete Linie mit zarter Fläche und offenen Punktmarkern;
- „aktueller Wert“ als gefüllter Punkt mit Halo und senkrechter Haarlinie;
- Achsenbeschriftung rechts, Kennzahlkopf als Legende;
- Wochenbalken, bei denen die aktuelle Woche kräftig und der Rest blass ist.

**Bewusst nicht übernommen:**
- `.catmullRom`-Glättung. Im Referenzbild „Trainingsdaten“ schwingt die Kurve bei „Nov“ sichtbar unter den Datenpunkt; das wäre ein Fantasiewert.
- Gestrichelte Gitterlinien. Eine gestrichelte 1-px-Linie flimmert auf @2x/@3x und ist genau die Unschärfe, die der Auftrag beseitigen will.

Methode: Skill `dataviz` (Formwahl → Farbe nach Aufgabe → Palette per Validator prüfen → Mark-Spezifikation → Interaktion → Barrierefreiheit → ansehen). Die Kontrast- und Farbfehlsichtigkeitswerte in §3 sind gerechnet, nicht geschätzt. Verwendet wurden `validate_palette.js` aus dem Skill (OKLab, Machado 2009, Schwere 1,0) und ein Python-Skript für WCAG-Kontraste (`/private/tmp/claude-501/-Users-janphilipfrehe--claude-spares-spare-K3ZZX2/ba83ae82-a222-4587-b39e-04cb8d80a9f7/scratchpad/pal.py`, liegt nur im Scratchpad; die Prüfung wandert als Unit-Test ins Repo, AP0).

---

## 1. Ist-Stand und Ursache der „unscharfen Blöcke“

`PowerProfileChart` (`UI/Components.swift`) zeichnet jede Rampe als Treppe. Sie besteht aus `max(4, Dauer/60)` Scheiben, und jede Scheibe trägt zwei `RectangleMark` (Füllung + „Jelly-Kappe“ in 3,5 % der Höhe). Daraus entstehen fünf sichtbare Fehler (Screenshots `07-plan`, `08-einheit`, `01-heute`, `10-heute-dark`):

| # | Befund | Wirkung |
|---|---|---|
| U1 | Scheibenkanten liegen auf Bruchteilen eines Pixels. Nachbarscheiben werden kantengeglättet und überlappen. | Graue Nähte und weiche Kanten: „unscharfe Blöcke“, vor allem in Auf- und Abwärmphasen. |
| U2 | Jede Scheibe hat eine eigene Kappe in einer anderen Höhe. | Rampen wirken wie ein Sägezahn aus dunklen Strichen statt wie eine Steigung. |
| U3 | Zwischen den Abschnitten gibt es keinen Abstand. | Intervalle und Pausen fließen ineinander; „5×4“ ist in der Mini-Ansicht kaum zählbar. |
| U4 | Die Füllfarben haben auf Weiß nur 1,6 bis 2,6:1 (Z1 1,69, Z4 1,61). | Deshalb gab es die Kappen. Sie lösen den Kontrast nur am oberen Rand; die Form bleibt blass. |
| U5 | Swift Charts mit 20 bis 160 Marks je Zeile in Listen; jede Zeile baut Achsen- und Skalenlayout auf. | Unnötige Arbeit beim Scrollen im Plan (Risiko R1). |

Auch die übrigen Diagramme sind uneinheitlich: Linienstärken von 2 bis 3 pt, Achsen links und rechts gemischt, Swift-Charts-Standardlegenden neben eigenen Legenden, versteckte Doppelachse (TSS/3 auf der Fitness-Skala), Zahl an jedem Punkt (VO₂max) und ein Regenbogen für Form (fünf Zonenfarben für einen Wert mit Vorzeichen).

---

## 2. Inventar

Priorität: **P1** = oft sichtbar oder Kern der Analyse, **P2** = Analysekarte, seltener, **P3** = Randfall, kein eigenes Arbeitspaket.

| # | Diagramm | Datei | Zweck | Marks heute | Probleme | Prio |
|---|---|---|---|---|---|---|
| D1 | Workout-Profil Mini (Zeile 72×34, Heute 64, Planvorschlag 56, Anpassen-Vorschau 110) | `UI/Components.swift` `PowerProfileChart`; genutzt in `WorkoutRow`, `TodayView:143`, `PlanView:338`, `WorkoutDetailView:329` | Ablauf einer Einheit auf einen Blick | 2× `RectangleMark` je Scheibe, FTP-`RuleMark` gestrichelt | U1–U5; die FTP-Linie in 34 pt ist Rauschen; „ausgelassen“ = `opacity 0.4` (< 3:1) | **P1** |
| D2 | Workout-Profil Detail (210 pt) | `WorkoutDetailView:104` | Ablauf mit Watt und Minuten | wie D1 + Achsen links | U1–U4; Achse links, Gitter in beide Richtungen; keine Auswahl je Abschnitt | **P1** |
| D3 | Zeit in Zonen (Einheit) | `Components.swift` `ZoneDistributionBar` | Anteil je Zone, geplant | `HStack` mit Farbstreifen, `Capsule`-Clip | Der Clip schneidet die Rundung des ersten und letzten Segments ab; Füllung Z1 1,69:1 | **P1** |
| D4 | Fitness & Form · 90 Tage (Heute) | `TodayView.formCard` | Fitness, Ermüdung, Tagesbelastung | Area + 2 Lines + `BarMark` TSS/3 | **Versteckte zweite Skala** (TSS/3 auf CTL-Achse); in Dunkel ein unruhiges Balkengewitter (`10-heute-dark`); keine Y-Achsenwerte; Linie 2,5 pt | **P1** |
| D5 | Fitness & Ermüdung (Detail) | `FitnessFreshnessView.loadChart` | Verlauf mit Tagesauswahl, Vorjahr | Area + 2 Lines + Vorjahr gestrichelt + `RuleMark` Auswahl | Gute Basis (Auswahl vorhanden); kein Halo-Punkt am ausgewählten Wert; Achse links | **P1** |
| D6 | Form pro Tag (Detail) | `FitnessFreshnessView.formChart` | Fitness − Ermüdung | `BarMark` je Tag in 5 Zonenfarben | **Regenbogen** für eine divergierende Größe; Nulllinie schwach | **P1** |
| D7 | Leistungskurve | `PerformanceView.curveCard` | beste Leistung je Dauer, Vergleich Vorperiode | 2 Lines (log-x) + Points | Vorperiode grau gestrichelt, verschwindet unter der Hauptlinie; Linie 3 pt; „20 min 60 min“ gedrängt; keine Auswahl | **P1** |
| D8 | Soll/Ist | `IntervalComplianceCard.ComplianceChart` | geplante vs. gefahrene Leistung | Soll `.stepEnd` gestrichelt + Ist `.monotone` (alle 10 s) | Ist ungeglättet und zackig; Standardlegende von Swift Charts; kein Bezug zu den Zonen; Achse links | **P1** |
| D9 | Verlauf · 12 Wochen | `HistoryView.HistoryChart` | Stunden/TSS je Woche | `BarMark` mit Verlauf Pink → Beere | Verlauf in der Füllung (unruhig); aktuelle Woche nicht hervorgehoben | **P1** |
| D10 | Wochenumfang · 8 Wochen (Heute) | `TodayView.volumeCard` | Stunden je Woche nach Art | gestapelte `BarMark`, `cornerRadius 5` je Segment | Rundung auch innen im Stapel, keine Segmentlücke; drei Farben auf der Startseite | P2 |
| D11 | Relative Effort Wochen | `RelativeEffortViews.EffortWeekCard` | Wochenlast im Wochenbereich | `RectangleMark` Band + `BarMark` | Muster passt schon (aktuell kräftig, Rest blass), aber der Rest liegt bei 55 % Deckkraft unter 3:1 | P2 |
| D12 | eFTP-Verlauf | `FTPHistoryCard` | geschätzte FTP über 6 Monate | Line + Points + Profil-FTP-Rule | Punkte gefüllt und klein; kein „aktuell“-Halo | P2 |
| D13 | Prognose zum Ziel | `GoalForecastCard` | Fitness-Prognose bis zum Ziel | Line + Ziel-Rule | „Heute“ fehlt; der Schnittpunkt mit dem Ziel (das Datum aus dem Satz darüber) ist nicht markiert | P2 |
| D14 | Fitness auf dem Weg zum Ziel | `WinterArcView.courseChart` | Fitness vs. Kurslinie, Vorjahr | 2 Line-Serien + Vorjahr + Ziel-Point | Y-Achse schließt die 0 ein, die Daten kleben unten (`20-herz-winterarc`); Kurs in Akzentfarbe konkurriert mit der Fitness | P2 |
| D15 | Aerobe Effizienz | `AerobicEfficiencyCard` | EF je Woche | Line + Points | Achsentitel „EF (W/bpm)“ links quer; Punkte gefüllt | P2 |
| D16 | VO₂max-Verlauf | `PerformanceView.VO2maxCard` | VO₂max je 6-Wochen-Fenster | Line + Points + **Zahl an jedem Punkt** | Anti-Muster „Zahl an jedem Punkt“; lineare Interpolation | P2 |
| D17 | Trainingsverteilung | `TrainingDistributionCard` | Anteil Grundlage/Tempo/Schwelle | `BarMark` normalisiert gestapelt, 36 pt | Keine Segmentlücken; Jelly-Füllungen < 3:1; Swift Charts für eine reine Figur | P2 |
| D18 | Zeit in Zonen (Fahrt) | `RideZonesCard` | Minuten je Leistungs-/Pulszone | 7 `Capsule`-Balken | Z1-Füllung 1,69:1; leere Zonen ohne Spur | P2 |
| D19 | Wellness-Trends (Ruhepuls, HRV …) | `WellnessTrendsView` | 28 Tage gegen Basisband | Area (Band) + Rule + Line | Standardachsen (Grau ≈ 3,5:1 in caption2); kein Endpunkt | P2 |
| D20 | Puls (Krafteinheit) | `Strength/StrengthDetailView` | HF-Verlauf | eine `LineMark` ohne Stil | Standardstil, Standardachsen | P3 |
| — | Wochenring, Challenge-Ring, LevelBar, ProgressViews | `TodayView`, `ChallengesView`, `AbilitiesViews` | Fortschritt | SwiftUI-Formen | in Ordnung; nur Tokens übernehmen | P3 |

**Barrierefreiheit heute:** D1, D7, D8, D11 und D17 sind ein VoiceOver-Element mit Zusammenfassung. D4, D5, D6, D14 und D19 setzen nur ein Label; Swift Charts legt dann eigene Knoten an. Das sind die „Contrast failed ohne Element“-Befunde aus `docs/ux-audit-2026-11-20.md` (Abschnitt „Offen“). Audio Graphs (`accessibilityChartDescriptor`) gibt es nirgends.

---

## 3. Diagramm-Designsystem

### 3.1 Farben nach Aufgabe

| Aufgabe | Regel | Token |
|---|---|---|
| **Zone (Intensität)** | feste Reihenfolge Z1…Z7, nie zyklisch; nur auf der Kartenfläche | `ChartPalette.zone(z)` (neu, §3.2) |
| **Fitness-Familie** | Fitness (CTL), eFTP-Prognose, Kurs-Fitness = Z2-Blau | `ChartPalette.fitness` = `zone(.z2)` |
| **Ermüdung** | ATL = Z6-Pink | `ChartPalette.fatigue` = `zone(.z6)` |
| **Eigene Messwerte, Einzelreihe** | Leistungskurve, Soll/Ist-Ist, Wochenbalken, Wellness, Puls = Akzent (Beere hell / Jelly-Pink dunkel) | `Theme.accent` (6,5:1 / 6,6:1) |
| **Hervorhebung vs. Rest** | aktuelle Woche = Akzent, frühere Wochen = Akzent gedämpft (deckend, ≥ 3:1) | `ChartPalette.accentMuted` hell `#D3749C` (3,11:1), dunkel `#A44E74` (3,18:1) |
| **Vergleich/Soll/Vorjahr** | neutral, gedämpft; nie eine Serienfarbe | `ChartPalette.reference` = primary 55 % (4,74:1 hell / 5,98:1 dunkel) |
| **Divergierend (Form)** | zwei Pole + neutrale Mitte: Form > 0 = Fitness-Blau, Form < 0 = Ermüdungs-Pink, Band „ausgewogen“ (−10…+5) = neutral 6 % | aus `fitness`/`fatigue` + `ChartPalette.band` |
| **Text** | Achsen, Werte, Legenden immer in Text-Tokens, nie in Serienfarbe | `Theme.axisLabel` (primary 72 %, 9,3:1), `Theme.rowSecondary` |
| **Status** | bleibt bei Chips (Form-Chip, „getroffen“) mit Icon + Text; nie als Serienfarbe | bestehende Jelly-Chips |

Zwei Serien in einem Diagramm (Fitness + Ermüdung) bestehen auch die strengste Prüfung über alle Paare: hell ΔE 12,8 (Deutan) / 27,0 (normal), dunkel ΔE 10,3 / 27,8. Mit Form als dritter Linie (Z1-Indigo, nur falls E3 = ja) gilt weiterhin: hell 12,3 / 18,2, dunkel 10,3 / 16,3.

### 3.2 Leistungszonen Z1–Z7 neu (Diagramm-Marken)

Die Jelly-Füllungen bleiben für Chips, `TypeIcon` und Textflächen; darauf steht Tinte mit 6,9–11:1. Für **Diagramme** bekommt jede Zone eine eigene Marken-Farbe je Modus. Sie trägt den 3:1-Kontrast allein, ohne Kappe oder Kontur.

Konstruktion: gleiche Farbfamilien wie bisher (Grau-Lila → Blau → Grün → Gelb → Orange → Pink → Violett, MyWhoosh/Zwift-Konvention). Die Helligkeit **alterniert** von Zone zu Zone: dunkel, hell, dunkel, hell … Nachbarzonen unterscheiden sich so in Farbton *und* Helligkeit. Ohne diesen Wechsel fielen Gelb und Orange zusammen (erster Versuch: Deutan ΔE 2,3). Z1 wird ein tiefes Indigo statt Lavendel, wie die Erholungsbalken in den Referenzen: eine ruhige, dunkle Grundlinie, über der die hellen Arbeitsblöcke stehen.

| Zone | Hell (Karte `#FFFFFF`) | Kontrast Karte / Canvas | Dunkel (Karte `#1C1C1E`) | Kontrast Karte / Schwarz | bisher Jelly-Füllung (auf Weiß) | OKLCH L hell/dunkel · h |
|---|---|---|---|---|---|---|
| Z1 Erholung | `#5152C1` | 6,31 / 5,88 | `#5863DA` | 3,41 / 4,21 | `#C9C3E6` 1,69 | 0,50 / 0,56 · 278° |
| Z2 Grundlage | `#4998DD` | 3,08 / 2,87 | `#1BA0D5` | 5,70 / 7,04 | `#8FA8FF` 2,28 | 0,66 / 0,66 · 248°/232° |
| Z3 Tempo | `#048E5C` | 4,18 / 3,89 | `#19925D` | 4,30 / 5,31 | `#5EDBB8` 1,71 | 0,57 / 0,58 · 160° |
| Z4 Schwelle | `#B68E0A` | 3,06 / 2,85 | `#B29000` | 5,58 / 6,88 | `#FFC247` 1,61 | 0,67 / 0,67 · 88° |
| Z5 VO₂max | `#C74007` | 5,04 / 4,70 | `#D13D1A` | 3,56 / 4,39 | `#FF866E` 2,36 | 0,56 / 0,58 · 38° |
| Z6 Anaerob | `#E34992` | 3,73 / 3,47 | `#E658A0` | 5,08 / 6,27 | `#F23D8B` 3,61 | 0,64 / 0,67 · 355° |
| Z7 Neuromuskulär | `#7F36BC` | 6,65 / 6,20 | `#9A43CE` | 3,30 / 4,07 | `#B48CFF` 2,58 | 0,50 / 0,56 · 305° |

**Validator-Ergebnis (Nachbarpaare Z1–Z2 … Z6–Z7):**
- Hell: alle Prüfungen PASS. Helligkeitsband 0,43–0,77, Chroma ≥ 0,10, CVD schlechtestes Paar Z4↔Z3 ΔE 8,3 (Protan, Ziel ≥ 8), normal schlechtestes Paar Z6↔Z5 ΔE 16,1 (≥ 15), alle ≥ 3:1.
- Dunkel: PASS bei Band, Chroma, normalem Sehen (Z2↔Z1 16,3) und Kontrast. CVD Z4↔Z3 ΔE 7,6 = **WARN** (zulässiger Bereich 6–8). Zulässig nur mit Zweitkodierung, und die ist durchgehend vorhanden: Höhe = Intensität im Profil, Lücken zwischen den Blöcken, Legende mit Zonennamen, VoiceOver-Text.

**Bekannte Einschränkungen:**
- **Z1↔Z7** (Indigo/Violett) sind kein Nachbarpaar der Skala, stehen im Profil aber zeitlich nebeneinander (Sprint nach Erholung). Über alle Paare geprüft fallen sie zusammen (ΔE 1,0 Deutan). Das ist bewusst akzeptiert: Ein Z7-Block ist ≥ 151 % FTP hoch und schmal, ein Z1-Block < 56 % und flach. Die Höhe unterscheidet sie eindeutig. Bei sieben Farben kann keine Reihenfolge alle Paare trennen (Skill, Prüfung 4).
- **Z2 und Z4 auf dem Canvas** (`#FBF6F2`) liegen bei 2,87 / 2,85. Regel: Zonenmarken stehen nur auf der Kartenfläche (Karte, Listenzelle). Das ist heute überall so; ein Test prüft beide Flächen (AP0).
- **Text in Zonenfarbe gibt es nicht.** In den hohen Segmentbalken (D17) steht der Prozentwert in Weiß auf Z1/Z3/Z5/Z7 (≥ 4,2:1) und in Tinte auf Z2/Z4/Z6 (≥ 4,8:1). Die Regel wird pro Farbe im Test festgeschrieben.

### 3.3 Mark-Spezifikationen (`ChartStyle`)

| Element | Spezifikation | Begründung |
|---|---|---|
| Linie | 2 pt, `lineCap .round`, `lineJoin .round` | Skill-Standard; heute 2–3 pt gemischt |
| Vergleichslinie (Vorjahr, Vorperiode) | 1,5 pt, `reference`, Strich `[2, 3]` (Punktlinie) | gedämpft, aber ≥ 3:1 |
| Soll-/Ziel-/FTP-Linie | 1 pt, `reference`, Strich `[4, 3]`, Beschriftung `caption2.semibold` in `axisLabel`, am Linienanfang oben | „gestrichelt = Sollwert“ als einzige Bedeutung von Strichen |
| Fläche unter Linie | Verlauf Serienfarbe 18 % → 0 % (dunkel 26 % → 0 %), nur bei Einzelreihe oder Hauptreihe | Referenz „Trainingsdaten“; ein Hauch, kein Block |
| Glättung | **`.monotone`** für alle stetigen Reihen; `.linear` bei ≤ 3 Punkten; `.stepEnd` nur für Sollwerte; **`.catmullRom` verboten** | monotone kubische Interpolation erzeugt keine Über- oder Unterschwinger; die Kurve bleibt zwischen zwei Messwerten. Swift Charts interpoliert im Bildraum, das gilt auch auf der Log-Achse (D7). |
| Punktmarker (offen) | 8 pt Kreis, Füllung = Kartenfläche, Kontur 2 pt Serienfarbe; nur bei ≤ 16 Punkten | Referenz „offene Marker“; bei Tageswerten wären es zu viele |
| **Aktueller/ausgewählter Wert** (`HighlightPoint`) | Halo 22 pt Serienfarbe 18 %, Punkt 10 pt gefüllt, Ring 2 pt Kartenfläche; senkrechte Haarlinie von der Basis zum Punkt in `reference` 40 % | Referenz „letzter Punkt mit Halo und Linie“ |
| Gitter | nur waagerecht, 3–4 Linien, Haarlinie `1 / displayScale`, durchgehend, primary 10 % (1,25:1 hell / 1,35:1 dunkel) | zurückhaltend; durchgehend statt gestrichelt (flimmert nicht) |
| Grundlinie (y = 0 bzw. x-Achse) | Haarlinie, primary 25 % | trägt die Balken |
| Senkrechtes Gitter | keins (Ausnahme: Profil-Detail, keins; Leistungskurve: Dekaden-Ticks ohne Linie) | Ruhe |
| Balken | Breite ≤ 16 pt (`.fixed` bzw. `ratio 0.6`), Ecken oben 4 pt, unten eckig, 2 pt Lücke zwischen Stapelsegmenten | Skill: abgerundetes Datenende, eckige Basis |
| Y-Achse | **rechts** (`position: .trailing`), 3–4 runde Werte (`ChartAxis.niceTicks`), `caption2` + `monospacedDigit`, `axisLabel`; Einheit einmal am obersten Wert („300 W“) oder als Achsentitel oben rechts („km“, „W“) | Referenzen; Zahlen stehen bündig am rechten Rand, die Kurve beginnt links ohne Einzug |
| X-Achse | unten, 3–5 Beschriftungen, keine Gitterlinie, Monate „Nov“, Wochen „17.11.“, Dauer „5 min“; `de_DE` | lesbar auf 375 pt |
| Legende | ab 2 Reihen immer, und zwar als **Kennzahlkopf** (`ChartCardHeader`): Wert groß, darunter Punkt + Name, wie in der Referenz „Monitoring“. Nie die Swift-Charts-Standardlegende (`.chartLegend(.hidden)` überall). Eine Reihe: keine Legende, der Kartentitel nennt sie. | Identität nie nur über Farbe |
| Direktbeschriftung | sparsam: Endwert der Hauptreihe oder Zielwert, nie jeder Punkt | Anti-Muster D16 |
| Höhen | klein 120, normal 170, groß 210 pt; `@ScaledMetric(relativeTo: .caption2)`, gedeckelt auf 1,35× | Dynamic Type ohne Explosion |

### 3.4 Leer- und Wenig-Daten-Zustände (`ChartEmptyState`)

| Datenlage | Darstellung |
|---|---|
| 0 Werte | kein Diagrammrahmen; Symbol + ein Satz in `rowSecondary`, was wann erscheint („Ab zwei Wochen mit Fahrten siehst du hier deinen Verlauf.“). Kein leerer Achsenrahmen (Audit A3-02: leere Skala erzeugt Konsolenfehler). |
| 1 Wert | ein `HighlightPoint` mit Wert als Direktbeschriftung, Satz „Ab dem zweiten Wert entsteht ein Verlauf.“ |
| 2–3 Werte | Linie `.linear` mit offenen Markern, keine Fläche, keine Glättung (wenige Punkte sollen keine Kurve vortäuschen) |
| Lücke > 7 Tage (bzw. > 2 Fenster) | Linie wird unterbrochen (`ChartMath.segments(splitWhenGapExceeds:)`, eigene `series` je Teilstück) statt über die Lücke zu interpolieren |
| Alle Werte gleich | Domäne ±1 Einheit um den Wert (`ChartAxis.domain` kollabiert nie) |

### 3.5 Animation

- Keine Einblendanimation beim ersten Erscheinen und nie in Listen (Minis).
- Wechsel des Zeitraums (6 Wochen / 90 Tage / 1 Jahr) und Auswahl: `.smooth(duration: 0.25)`.
- `@Environment(\.accessibilityReduceMotion)`: dann `transaction.animation = nil` (`ChartStyle.animation(reduceMotion:)`).
- Soll/Ist behält `.transaction { $0.animation = nil }`.

### 3.6 Interaktion

Auswahl per Antippen und Ziehen (`chartXSelection(value:)` + `chartGesture` mit `SpatialTapGesture`, so wie heute in D5). Bei Auswahl gilt:
- `RuleMark` als Haarlinie und `HighlightPoint` auf jeder Reihe;
- der **Kennzahlkopf zeigt die Werte des gewählten Tags** (Muster aus `FitnessFreshnessView.header`, „Heute“-Knopf zum Zurücksetzen);
- keine schwebende Sprechblase über dem Diagramm, sie würde in 170 pt die Kurve verdecken.

| Diagramm | Auswahl | Kopf zeigt |
|---|---|---|
| D2 Profil Detail | Abschnitt unter dem Finger | „Abschnitt 3 · 4:00 @ 115 % (288 W) · Z5“; die übrigen Blöcke werden auf 45 % gedimmt, nur solange gewählt |
| D5 Fitness Detail | Tag | Fitness / Ermüdung / Form des Tags (vorhanden) |
| D7 Leistungskurve | Dauer (auf Messpunkte einrastend) | „5 min · 279 W · Vorperiode 265 W“ |
| D8 Soll/Ist | Minute | „24:30 · Soll 225 W · Ist 219 W“ |
| D9 Verlauf | Woche | Stunden/TSS der Woche |
| D12, D15, D16 | Punkt | Wert + Fenster |
| Minis, D3, D17, D18 | keine | – (Werte stehen als Text daneben) |

Gestenkonflikt: In `ScrollView` startet die Auswahl erst mit Antippen oder waagerechtem Ziehen; senkrechtes Wischen scrollt weiter. Das wird je Diagramm in der UI-Prüfung bestätigt (R4).

### 3.7 VoiceOver und Audio Graphs

- **Jedes Diagramm ist genau ein Element:** `.accessibilityElement(children: .ignore)`, `accessibilityLabel` = Titel, `accessibilityValue` = ein Satz mit Endwert, Trend und Extremwert. Beispiel: „Fitness 38, plus 3 in 7 Tagen. Ermüdung 33. Form 5, ausgewogen.“ Das beseitigt auch die Swift-Charts-Unterknoten, die der Audit als „Contrast failed ohne Element“ meldet.
- **Audio Graphs** (`accessibilityChartDescriptor`, `AXChartDescriptorRepresentable`) für die P1-Analysen D2, D5, D7, D8 und D9: Achsen mit Titel und Einheit, eine `AXDataSeriesDescriptor` je Reihe, Zusammenfassung wie oben. Minis bekommen nur den Satz (Audio Graph in Listen wäre Lärm).
- Die Identifier bleiben stabil (§8, R3); die Minis bekommen neu `profile.mini`, das Detail `profile.detail`.

### 3.8 Hell/Dunkel und Pixelraster

- Dunkle Werte sind **eigene Stufen** aus denselben Farbfamilien (§3.2), kein automatisches Umkehren. Flächen-Deckkraft dunkel 26 % statt 18 %.
- Alle Haarlinien: `1 / displayScale` (`@Environment(\.displayScale)`).
- Alle Blockkanten im Profil werden auf das Pixelraster gerundet (`round(x · scale) / scale`); Lücken sind ganze Pixel (≥ 1 px). Damit verschwindet U1 vollständig.
- „Ausgelassen“ (D1 in `WorkoutRow`): statt `opacity 0.4` alle Blöcke in `reference` (primary 55 %, 4,74:1); das Status-Icon trägt die Bedeutung.

---

## 4. Workout-Profil neu (P1)

### 4.1 Geometrie

Ein **Block je Schritt**. Gemeint sind Schritte nach `WorkoutDefinition.steps`, also mit ausgerollten Intervallen; Steady, On, Off und Free Ride sind je ein Rechteck. Zwischen zwei Schritten liegt eine Lücke in Kartenfarbe. Bei Rampen (Aufwärmen, Rampe, Abwärmen) ist der Block ein **Trapez**: Die Oberkante läuft gerade von `startPower` zu `endPower`, ohne Treppe und ohne Scheiben.

Überquert eine Rampe eine Zonengrenze (z. B. 45 % → 75 %: Z1 bis 56 %, dann Z2), wird das Trapez an der exakten Stelle senkrecht geteilt. Die Stelle ergibt sich linear: `t = (0,56 − p0) / (p1 − p0) · Dauer`. Die Teilflächen stoßen **ohne Lücke** aneinander, nur ihre Farben wechseln. Das ist ehrlich (passt zu `timeInZones()`) und scharf (eine senkrechte Pixelkante statt eines Farbverlaufs).

Ecken:
- Mini: alle vier Ecken des Schritts sind gerundet, wie die „schwebenden Steine“ der Referenz.
- Detail: nur die oberen Ecken sind gerundet; der Block sitzt auf der x-Achse.
- Bei geteilten Rampen werden nur die äußeren Ecken gerundet (oben links am ersten Teil, oben rechts am letzten).
- Radius: `r = min(r_variante, Breite/2, Höhe/2)`.

Y-Skala:
- Minis haben eine **feste Domäne 0…160 % FTP**. So sind Höhen in Listen zwischen Zeilen vergleichbar; eine Erholungsfahrt sieht neben VO₂max auch flach aus. Werte darüber (Z7-Sprints) werden auf volle Höhe begrenzt und als `clipped` markiert; die Farbe Z7 zeigt dann die Zone.
- Detail: `0…max(130 %, Spitze + 10 %)`, auf 10 % aufgerundet (wie heute).

**Mindestbreiten (nur Minis, die keine Zeitachse haben):**
1. Natürliche Breite `w_i = Dauer_i / Gesamt · Breite`.
2. Pflichtbreite `max(w_i, minBlock)`. Für On-Schritte von Intervallen gilt `minStake`, für Off-Schritte 1 px.
3. Das Defizit wird anteilig von Blöcken genommen, die breiter als 4× ihre Pflichtbreite sind; das sind fast immer lange Grundlage-Blöcke. Die Zeit wird dabei in der Mini-Ansicht leicht gestaucht. Das ist akzeptabel, weil die Minis keine Zeitachse haben und Dauer und TSS als Text daneben stehen.
4. Reicht der Spielraum für Einzelblöcke nicht (viele kurze Intervalle), wechselt der Intervallsatz in den **Kompaktmodus**: Eine durchgehende Off-Fläche in Off-Zonenfarbe liegt unter dem Satz, darauf stehen n Stäbe (On), getrennt durch einen 1-px-Ring in Kartenfarbe statt der normalen Lücke. Der Satz braucht dann nur noch `n · minStake + (n−1) · 1 px`; diese Breite wird wie in Schritt 3 geliehen. **Die Anzahl der Stäbe bleibt immer n.** Das entspricht der VO₂max-Referenz: schmale gelbe Stäbe über niedrigen Indigo-Stücken.
5. Reicht auch dafür der Spielraum nicht, schrumpft die Stabbreite auf `max(1 px, ⌊(Satzbreite − (n−1)·1 px) / n⌋)` (ganze Pixel). Erst wenn selbst 1-px-Stäbe nicht passen (n > ca. 70 je Satz bei 72 pt), wird der Satz ein Block in On-Farbe mit 45°-Schraffur (Textur-Regel des Skills). VoiceOver nennt die echte Anzahl.

Rechenbeispiel „3×(10×30/30)“, 75 min, in der Zeile (72 pt, @3x, 1 px = 0,33 pt):
- Natürlich ist ein Satz (10 min) 9,6 pt breit, ein 30-s-Intervall 0,48 pt.
- Als Einzelblöcke bräuchte ein Satz 10 × (1,5 On + 1 Lücke + 0,33 Off + 1 Lücke) ≈ 38 pt, drei Sätze also 115 pt > 72 pt. Damit greift der Kompaktmodus.
- Im Kompaktmodus braucht ein Satz 10 × 1,67 pt (5 px) + 9 × 0,33 pt ≈ 19,7 pt. Die Differenz von 3 × ≈ 10 pt wird aus Ein-/Ausfahren und den Pausen zwischen den Sätzen geliehen; diese 45 min sind natürlich ≈ 43 pt breit, der Spielraum reicht.

### 4.2 Technik: SwiftUI `Canvas` statt Swift Charts

| Kriterium | Swift Charts (heute) | Swift Charts `AreaMark` je Block | **`Canvas` + reine Geometrie (gewählt)** |
|---|---|---|---|
| Abgerundete Trapeze | nein (nur `RectangleMark.cornerRadius`) | Trapez ja, Rundung nein | ja (`addArc(tangent1End:tangent2End:radius:)`) |
| Pixelraster/Lücken exakt | nein (Werte-Raum) | nein | ja (Geometrie rechnet in Pixeln) |
| Kosten je Listenzeile | Achsen-/Skalenlayout + 20–160 Marks als Views | ähnlich | ein Zeichendurchgang, O(n) Pfade, keine View-Identität je Block |
| Testbarkeit | nur Screenshot | nur Screenshot | Geometrie ist eine reine Funktion → Unit-Tests |
| Achsen, Auswahl | eingebaut | eingebaut | im Detail über Swift Charts (siehe unten) |

**Mini** = `WorkoutProfileView`: `Canvas`, ohne Achsen, `Equatable` (Definition + Variante + Status) mit `.equatable()`. Unveränderte Zeilen zeichnen beim Scrollen nicht neu.

**Detail** = `WorkoutProfileChart`: Swift Charts liefert nur noch Rahmen, Achsen (rechts, W; unten, Minuten), FTP-`RuleMark` und Auswahl. Die Blöcke zeichnet **derselbe Renderer** im `chartBackground { proxy in … }`: Plot-Rechteck aus `proxy.plotFrame`, x/y über `proxy.position(forX:)` bzw. die bekannte Domäne. Es gibt eine Geometrie, einen Renderer, zwei Hüllen. Im Detail werden die Zeiten **nicht** gestaucht (Zeitachse!), Mindestbreite nur 1 px.

### 4.3 Maße je Größenvariante

| Variante | Einsatz | Größe | Lücke | Radius | min. Blockbreite / Stab | min. Höhe | Y-Domäne | FTP-Linie | Achsen |
|---|---|---|---|---|---|---|---|---|---|
| `.row` | `WorkoutRow` | 72 × 34 pt | 1 pt (3 px @3x, 2 px @2x) | 1,5 pt alle Ecken | 2 pt / 1,5 pt | 2 pt | 0–160 % fest | nein | nein |
| `.card` | Heute „Nächste Einheit“ (64), Planvorschlag (56) | volle Kartenbreite × 56/64 pt | 2 pt | 3 pt alle Ecken | 3 pt / 2 pt | 3 pt | 0–160 % fest | nein | nein |
| `.preview` | Anpassen-Vorschau | volle Breite × 110 pt | 2 pt | 4 pt alle Ecken | 3 pt / 2 pt | 3 pt | 0–160 % fest | Haarlinie `reference`, ohne Text | nein |
| `.detail` | Einheit-Detail | volle Breite × 210 pt | 2 pt | 4 pt oben, 0 unten | 1 px (keine Stauchung) | 2 pt | 0…max(130 %, Spitze+10 %) | 1 pt `[4,3]` + „FTP 250 W“ | y rechts: 50/100/150 % als Watt, x: 0′/15′/30′/45′/60′ (`ChartAxis.minuteTicks`) |
| `.row` bei AX-Größen | `WorkoutRow` ab `isAccessibilitySize` | unter dem Text, volle Breite × 28 pt | 1 pt | 1,5 pt | wie `.row` | 2 pt | fest | nein | nein |

Die letzte Zeile ist neu: Heute wird das Mini bei AX-Größen ausgeblendet; künftig steht es unter dem Titel, statt den Titel zu quetschen.

**Dunkelmodus:** dunkle Zonenstufen (§3.2) auf `#1C1C1E`, Lücken in Kartenfarbe. **Kanten:** auf ganze Pixel gerundet, Antialiasing nur an Rundungen und Trapez-Oberkanten.

**VoiceOver (Satz):**
- bisher: „1:05 h, 4 Abschnitte, Spitze 115 % FTP (288 W)“;
- neu zusätzlich: „überwiegend Z1 und Z5, 5 Intervalle à 4:00“, aus der Geometrie bzw. `timeInZones()`.

---

## 5. Analyse-Diagramme: Zielgestaltung

Alle Diagramme übernehmen §3. Hier steht nur, was je Diagramm anders oder neu ist.

| # | Zielgestaltung | Wegfall |
|---|---|---|
| **D4 Fitness & Form · Heute** (P1) | Kopf: drei Kennzahlen Fitness · Ermüdung · Form mit Punkt (= Legende), Form-Chip bleibt. Diagramm 140 pt: Fitness als Linie + Fläche (Z2), Ermüdung als Linie (Z6), `.monotone`. Am rechten Ende ein `HighlightPoint` je Reihe. Y rechts mit 3 Werten, X mit Monaten. | **TSS-Balken (TSS/3 auf der CTL-Skala = versteckte Doppelachse)** entfallen; Tagesbelastung steht in Verlauf/D9. |
| **D5 Fitness & Ermüdung · Detail** (P1) | wie D4, 200 pt; Vorjahr als Punktlinie `reference`; Auswahl mit Haarlinie + `HighlightPoint` auf beiden Reihen; Audio Graph. | Ink-35-%-Auswahllinie → Token |
| **D6 Form pro Tag** (P1) | divergierende Balken: > 0 Fitness-Blau, < 0 Ermüdungs-Pink, Band −10…+5 als `RectangleMark` in `band` mit Text „ausgewogen“ rechts innen, Nulllinie = Grundlinie. Auswahl synchron mit D5 (vorhanden). | 5-Farben-Regenbogen (`Theme.formColor` bleibt nur für den Chip) |
| **D7 Leistungskurve** (P1) | Aktuell: Akzentlinie 2 pt + Fläche (Verlauf) bis zum Plotboden. Vorperiode: Punktlinie `reference` **über** der Fläche, aber unter der Hauptlinie. Offene Marker auf den Kopf-Dauern (5 s, 1, 5, 20, 60 min), nur gemessen. Auswahl rastet auf Messpunkte ein, der Kopf zeigt Watt, W/kg und Vorperiode. X-Ticks `ChartAxis.powerCurveTicks`: 5 s · 1 min · 5 min · 20 min, „60 min“ nur wenn ≥ 45 min Daten, sonst entfällt es (heute gedrängt). | Linie 3 pt, gefüllte Punkte |
| **D8 Soll/Ist** (P1) | **Soll = das Workout-Profil selbst** als Hintergrund: Zonenblöcke als Hauch (Zonenfarbe 20 %, dekorativ). Die Sollkante wird als 1-pt-Linie `reference` `.stepEnd` gezeichnet (≥ 4,7:1), sie trägt den Wert. Ist: Akzentlinie 2 pt, **30-s-gleitender Mittelwert** (`ChartMath.rollingMean`) und Ausdünnung auf ≤ 400 Punkte (`ChartMath.downsampleMinMax`, Extremwerte bleiben), `.monotone`. Kopfzeile mit eigener Legende „— Soll  — Ist“. Auswahl: Minute → Soll/Ist im Kopf; das Intervall unter dem Finger wird in der Liste darunter markiert. Audio Graph. | Swift-Charts-Standardlegende, Rohwerte alle 10 s |
| **D9 Verlauf · 12 Wochen** (P1) | Einzelreihe: aktuelle Woche `accent`, frühere Wochen `accentMuted` (deckend, 3,1:1), Breite ≤ 16 pt, oben 4 pt rund. Direktwert nur über der aktuellen Woche. Gestrichelte Durchschnittslinie `reference` mit „Ø 4:12 h“. Auswahl Woche. | Farbverlauf in der Füllung |
| D10 Wochenumfang · Heute (P2) | Referenz „Woche für Woche“: Einzelreihe Gesamtstunden, aktuelle Woche `accent`, Rest `accentMuted`; Kopf „2:50 h / 3:20 h Ziel“. Indoor/Outdoor/Andere wandern in den VoiceOver-Wert und in D9 (Entscheidung E2). | gestapelte drei Farben auf der Startseite |
| D11 Relative Effort (P2) | Muster bleibt; Rest `accentMuted` statt 55 % (≥ 3:1); Wochenbereich als `band` mit Beschriftung „dein Bereich“ rechts innen. | – |
| D12 eFTP-Verlauf (P2) | Akzentlinie + Fläche, offene Marker (≤ 6 Fenster), letzter Punkt `HighlightPoint` mit Direktwert „263 W“; Profil-FTP als Sollinie `[4,3]` beschriftet. | Profil-FTP in Akzentfarbe (konkurrierte mit der Linie) |
| D13 Prognose (P2) | Bis heute Fitness als durchgezogene Linie + Fläche (falls Historie geliefert wird, sonst nur Prognose). Ab heute Fitness durchgezogen und gedämpft (Z2, 70 % Deckkraft; Striche bleiben Soll/Ziel/FTP vorbehalten). „Heute“-Beschriftung entfällt, wenn der Schnittpunkt näher als ein Fünftel der Breite liegt. „Heute“ als senkrechte Haarlinie mit Beschriftung unten. Ziel als Sollinie. **Schnittpunkt** = `HighlightPoint` mit Direktbeschriftung „22. Jan“ (dasselbe Datum wie im Satz darüber). | – |
| D14 Kurs zum Ziel (P2) | Y-Domäne ohne 0 (`ChartAxis.domain(includeZero: false)`), Kurs als Sollinie `reference` `[4,3]` (nicht Akzent), Fitness Z2 + Fläche, Vorjahr Punktlinie, Ziel = `HighlightPoint` + „Ziel 48“. Heute = Endpunkt mit Halo. | 0…60-Achse mit leerer unterer Hälfte |
| D15 Aerobe Effizienz (P2) | Akzentlinie, offene Marker (Wochen), letzter Punkt Halo + Direktwert „1,52“; Einheit als Achsentitel oben rechts „W/bpm“. | quer gestellter Achsentitel links |
| D16 VO₂max (P2) | wie D15; Direktwert **nur** am letzten Punkt. | Zahl an jedem Punkt |
| D17 Trainingsverteilung (P2) | **hoher Segmentbalken** (Skill-Figur) als reines SwiftUI, nicht Swift Charts: 28 pt hoch, jedes Teil ein eigener Block mit 4 pt Ecken und 2 pt Lücke; Anteil („46 %“) innen am Anfang in Weiß oder Tinte (§3.2), nur wenn er passt. Farben Z2/Z3/Z5-Marken, „unbekannt“ = `band`. Die Liste darunter bleibt die Legende. | Swift Charts, Jelly-Füllungen |
| D3 Zeit in Zonen · Einheit (P1) | **dünner Segmentbalken** (dieselbe Komponente `SegmentedBar`, Variante `.thin`): 10 pt, jedes Teil voll gerundet, 2 pt Lücke, Mindestbreite 4 pt, Zonenmarken; `FlowLegend`-Punkte in Markenfarbe. | `Capsule`-Clip |
| D18 Zeit in Zonen · Fahrt (P2) | je Zone: Spur (primary 6 %, volle Breite, 8 pt, rund) + Balken in Zonenmarke; 0-min-Zonen zeigen nur die Spur und „0 min“ in `rowSecondary`. | Jelly-Füllung Z1 1,69:1 |
| D19 Wellness (P2) | Akzentlinie, Basisband `band`, Basislinie `[4,3]` beschriftet „Basis 52“, letzter Punkt Halo, Y rechts 3 Werte, X 4 Daten; Check-in-Stil aus der Referenz (heller Bandhintergrund). | Standardachsen |
| D20 Puls Kraft (P3) | nur Tokens: Akzentlinie, `.monotone`, auf ≤ 300 Punkte ausgedünnt, Maximum als offener Marker, Achsen rechts. | Standardstil |

---

## 6. Gemeinsame Bausteine

Wenige Bausteine, die überall wirken. Neu sind ein Ordner `UI/Charts/` und zwei reine Domain-Dateien.

| Baustein | Datei | Inhalt | Genutzt von |
|---|---|---|---|
| `Palette.Swatch.mark` / `.markDark`, `ChartPalette` | `Domain/Palette.swift` (erweitern) | Zonenmarken §3.2; `accentMuted`, `reference`, `grid`, `baseline`, `band` als RGB-Daten; Hilfen `oklab`, `deltaE`, `cvd(protan/deutan)` für Tests | Theme, alle Diagramme, Tests |
| `WorkoutProfileGeometry` | `Domain/WorkoutProfileGeometry.swift` (neu, rein, nur Foundation/CoreGraphics) | `make(definition:size:scale:variant:) -> [ProfileBlock]` mit Polygon (4 Punkte), Zone, Ecken-Flags, Radius, `clipped`, `stepIndex`, `segmentIndex`; `Variant`-Maße aus §4.3; Kompaktmodus | Mini, Detail, Soll/Ist-Hintergrund |
| `ChartMath` | `Domain/ChartMath.swift` (neu, rein) | `niceTicks(min:max:count:)`, `domain(values:includeZero:)`, `minuteTicks(total:)`, `powerCurveTicks(maxDuration:)`, `rollingMean(_:window:)`, `downsampleMinMax(_:maxPoints:)`, `segments(_:splitWhenGapExceeds:)`, `nearest(_:to:)` | alle Achsen, D8, D19, D20, Auswahl |
| `ChartStyle` | `UI/Charts/ChartStyle.swift` (neu) | Tokens §3.3 als `Color`/`StrokeStyle`/`CGFloat`; Modifier `.standardAxes(y:x:)` (rechts, Haarlinie, `axisLabel`), `.chartAnimation(reduceMotion:)`, `ChartStyle.area(_ color:)` | alle Swift-Charts-Diagramme |
| `WorkoutProfileView` / `WorkoutProfileChart` / `ProfileRenderer` | `UI/Charts/WorkoutProfileView.swift` (neu; ersetzt `PowerProfileChart`) | Canvas-Renderer, Mini-Hülle, Detail-Hülle mit Achsen/FTP/Auswahl | D1, D2, D8 |
| `HighlightPoint`, `ChartRule` | `UI/Charts/ChartParts.swift` (neu) | `ChartContent`: Halo + Punkt + Ring (+ optional Haarlinie); beschriftete Sollinie | D4–D9, D11–D16, D19 |
| `ChartCardHeader` | `UI/Charts/ChartParts.swift` | Kennzahlkopf = Legende (Wert, Punkt, Name), zeigt Auswahl oder „heute“, Knopf „Heute“ | D4, D5, D7, D8, D9, D10 |
| `SegmentedBar` | `UI/Charts/ChartParts.swift` | `.thin` (D3) und `.tall` (D17), rein SwiftUI | D3, D17 |
| `ChartEmptyState` | `UI/Charts/ChartParts.swift` | Zustände §3.4 | alle |
| `ChartAccessibility` | `UI/Charts/ChartAccessibility.swift` (neu) | `AXChartDescriptor`-Bauer für Zeitreihen und das Profil; Satzbauer für `accessibilityValue` | D2, D5, D7, D8, D9 |
| Diagramm-Galerie (nur DEBUG) | `UI/Charts/ChartGalleryView.swift` (neu, `#if DEBUG`), Start mit `-uiChartGallery YES` | alle Profil-Varianten (Sweet Spot, VO₂max 5×4, 30/30, Tabata, Rampe über 3 Zonen, Sprint Z7, leer) und je ein Analyse-Diagramm mit 0/1/3/n Punkten | Screenshots, Review |

`Theme.fitness`, `fitnessLine`, `fatigueLine`, `indoorMark` usw. zeigen danach auf `ChartPalette`; `Theme.fill`/`cap` bleiben für Chips und Icons. `cap` entfällt erst, wenn kein Diagramm ihn mehr nutzt (AP6).

---

## 7. Arbeitspakete (ECC, Tests zuerst)

Ablauf je AP: zuerst Tests schreiben (rot), dann umsetzen (grün), dann die UI-Prüfung (402 pt + SE 375 pt, hell/dunkel, AX5) und `ecc:orch-review`, dann ein Commit je AP. Die Reihenfolge ist so gewählt, dass das **Workout-Profil nach AP2 fertig und überall sichtbar** ist.

```
AP0 Palette ─┬─> AP1 Geometrie ─> AP2 Profil Mini ─> AP3 Profil Detail + Segmentbalken
             └─> AP4 Bausteine (ChartStyle, ChartMath, Parts) ─> AP5 P1-Analysen ─> AP6 P2-Analysen
                                                                         └──────────────> AP7 A11y-Abschluss + Screenshots
```

### AP0 · Diagrammpalette und Kontrasttests (S, ½ Tag)
- **Dateien:** `Domain/Palette.swift`, `Tests/IndoorCoachKitTests/PaletteTests.swift` (erweitern).
- **Tests (Swift Testing):**
  - `zoneMarksMeetNonTextContrastOnCards`: hell ≥ 3,0 gegen `cardLight`, dunkel ≥ 3,0 gegen `cardDark` und `canvasDark`.
  - `zoneMarksAreOnlyForCards`: dokumentiert Z2/Z4 < 3 auf `canvasLight` (bewusst).
  - `adjacentZoneMarksSeparateForNormalVision`: OKLab-ΔE×100 ≥ 15, beide Modi.
  - `adjacentZoneMarksSeparateUnderCVD`: Machado 2009 Protan/Deutan; hell ≥ 8, dunkel ≥ 6 (Zweitkodierung; Ist-Wert 7,6).
  - `fitnessAndFatigueSeparateAllPairs` (≥ 8 CVD, ≥ 15 normal).
  - `accentMutedMeetsThreeToOne`, `referenceLineMeetsThreeToOne`.
  - `gridIsRecessive`: 1,15–1,6:1.
  - `labelOnTallSegmentPicksReadableInk`: Weiß/Tinte je Zone ≥ 4,5:1.
  - `oklabMatchesReference`: Weiß L = 1,0, `#5152C1` L ≈ 0,50.
- **Akzeptanz:** alle Tests grün; Werte = Tabelle §3.2; noch keine sichtbare Änderung.

### AP1 · Profilgeometrie (M, 1 Tag) – abhängig von AP0 (nur Zonentyp)
- **Dateien:** `Domain/WorkoutProfileGeometry.swift`, `Tests/IndoorCoachKitTests/WorkoutProfileGeometryTests.swift`.
- **Tests:**
  - `oneBlockPerSteadyStep` (Sweet Spot 3×12 → 1 + 6 + 1 Blöcke bzw. Teilblöcke).
  - `blocksAreOrderedAndDoNotOverlap`, `gapsAreWholePixelsAndAtLeastOne` (scale 2 und 3), `firstAndLastTouchEdges`.
  - `allEdgesSnapToPixelGrid`.
  - `rampIsTrapezoidNotStairs` (Aufwärmen 50→70 %: genau 2 Teilpolygone, linke Höhe ≙ 50 %, rechte ≙ 70 %).
  - `rampSplitsExactlyAtZoneBoundary` (x der Teilung = 0,56-Durchgang ±1 px), `rampPartsShareEdgeWithoutGap`.
  - `cooldownDescends`, `outerCornersOnlyRounded`.
  - `heightsFollowFixedListDomain` (100 % bei 0–160 % und h 34 → 21,25 pt, gerundet), `clampsAboveDomainAndFlagsClipped` (200 %), `minimumHeight` (30 % → ≥ 2 pt).
  - `shortIntervalsKeepMinimumStakeWidth` (20×30/30 in 60 min, 72 pt → jeder Stab ≥ 1,5 pt, 20 Stäbe).
  - `compactModeKeepsIntervalCount` (3×(10×30/30) in 75 min → 30 Stäbe, Off-Fläche je Satz), `hatchFallbackOnlyBeyondPixelLimit`.
  - `widthIsConserved` (Summe Blöcke + Lücken = Breite ± 1 px), `detailVariantDoesNotWarpTime` (Blockbreiten ∝ Dauer ± 1 px).
  - `zoneAreaMatchesTimeInZones` (Detail: Breite je Zone ∝ `timeInZones()` ± 1 s).
  - `cornerRadiusClamped`, `emptyAndZeroDurationProduceNoBlocks`, `freeRideIs55Percent`.
  - `geometryIsFast` (200 Schritte < 2 ms, `ContinuousClock`).
- **Akzeptanz:** alle grün; keine SwiftUI-Abhängigkeit in der Datei.

### AP2 · Profil-Minis sichtbar (M, 1 Tag) – abhängig von AP1
- **Dateien:** `UI/Charts/WorkoutProfileView.swift` (Renderer + Mini), `UI/Components.swift` (`WorkoutRow`: Mini, AX-Variante, „ausgelassen“ in `reference`), `UI/TodayView.swift:143`, `UI/PlanView.swift:338`, `UI/WorkoutDetailView.swift:329`, `UI/Charts/ChartGalleryView.swift` (DEBUG), App-Start-Schalter `-uiChartGallery`.
- **Tests:** Unit `profileSummaryMentionsZonesAndIntervals` (Satzbauer, rein). UI `AuditChartsTests.testProfileMinis`: Plan, Heute und Galerie mit 402 pt + SE, hell/dunkel, AX5; `profile.mini` existiert je Zeile; `performAccessibilityAudit` ohne `contrast` auf `profile.*`.
- **Akzeptanz:**
  - Plan, Heute und Planvorschlag zeigen getrennte, gerundete Blöcke ohne Nähte.
  - 5×4 ist zählbar, 30/30 erscheint als Stäbe.
  - Bei AX5 steht das Mini unter dem Titel.
  - Scrollen im Plan mit 20 Einheiten zeigt im Instruments-Template „SwiftUI“ keinen Hänger über einem Frame (iPhone 13 oder Simulator-Profil).
  - `PowerProfileChart` wird nur noch vom Detail genutzt.

### AP3 · Profil-Detail und Segmentbalken (M, 1 Tag) – abhängig von AP2
- **Dateien:** `UI/Charts/WorkoutProfileView.swift` (`WorkoutProfileChart`: Swift-Charts-Hülle, `chartBackground` mit Renderer, Achsen rechts, FTP-Linie, Auswahl je Abschnitt), `UI/Charts/ChartParts.swift` (`SegmentedBar`), `UI/Components.swift` (`ZoneDistributionBar` → `SegmentedBar(.thin)`, `FlowLegend` in Markenfarbe, **`PowerProfileChart` löschen**), `UI/WorkoutDetailView.swift:104`.
- **Tests:** Unit `minuteTicksAreRound` (60 min → 0/15/30/45/60; 45 → 0/15/30/45; 95 → 0/30/60/90), `segmentIndexAtX` (Auswahl → Schritt), `segmentedBarWidthsAndMinimum` (Anteile, 2 pt Lücke, min. 4 pt, Summe = Breite). UI: Einheit-Detail 402 + SE, hell/dunkel; Antippen eines Intervalls zeigt im Kopf „Abschnitt … Z5“; Audio Graph vorhanden (`accessibilityChartDescriptor` nicht nil über Debug-Hook) – sonst Sichtprüfung.
- **Akzeptanz:** `08-einheit` entspricht §4.3; kein Clip schneidet Segmentrundungen; FTP-Beschriftung überlappt keine Blöcke (Sichtprüfung 375 pt).

### AP4 · Gemeinsame Diagramm-Bausteine (S–M, 1 Tag) – abhängig von AP0
- **Dateien:** `Domain/ChartMath.swift`, `UI/Charts/ChartStyle.swift`, `UI/Charts/ChartParts.swift` (`HighlightPoint`, `ChartRule`, `ChartCardHeader`, `ChartEmptyState`), `UI/Charts/ChartAccessibility.swift`, `Tests/IndoorCoachKitTests/ChartMathTests.swift`.
- **Tests:**
  - `niceTicksRoundValues` (37…262 → 0/100/200/300; 1,41…1,58 → 1,4/1,5/1,6), `niceTicksNeverEmpty`, `domainNeverCollapses` (alle gleich → ±1), `domainExcludesZeroWhenAsked`.
  - `powerCurveTicksDropCrowdedSixtyMinutes`.
  - `rollingMeanKeepsConstantAndLength`, `rollingMeanStepIsMonotone`, `rollingMeanIgnoresDropouts` (0 W als Pause).
  - `downsampleKeepsExtremesAndBound`.
  - `segmentsSplitOnGaps` (Lücke > 7 Tage).
  - `nearestPicksClosestDate`.
  - `accessibilitySentenceForSeries` (Endwert, Trend, Extrem; deutsche Zahlen mit Komma).
- **Akzeptanz:** Bausteine in der Galerie sichtbar (0/1/3/n Punkte, hell/dunkel); noch keine Analyse umgestellt.

### AP5 · P1-Analysen (M–L, 2 Tage) – abhängig von AP3 + AP4
- **Dateien:** `UI/TodayView.swift` (D4, D10), `UI/FitnessFreshnessView.swift` (D5, D6), `UI/PerformanceView.swift` (D7), `UI/IntervalComplianceCard.swift` (D8, nutzt Profilgeometrie als Soll-Hintergrund), `UI/HistoryView.swift` (D9).
- **Tests:** Unit `complianceIstIsSmoothedAndBounded` (≤ 400 Punkte, 30-s-Mittel), `formBarColorFollowsSign`, `weekBarsHighlightOnlyCurrent`. UI: bestehende Tests müssen grün bleiben, nämlich test37 (`compliance.chart`), die Leistungskurve (`performance.curve`), das Antippen von „Verlauf von Fitness und Ermüdung“ (Label unverändert!) und `shadow.legend`. Neu: Screenshots 01/05/10/13 + Verlauf, je 402 + SE, hell/dunkel, AX5; Accessibility-Audit ohne `contrast` auf Diagramm-Elementen.
- **Akzeptanz:**
  - In D4 keine TSS-Balken mehr, Y-Werte rechts sichtbar.
  - Kein Diagramm nutzt `.catmullRom`; ein Lint-Grep in der Review prüft das.
  - Alle P1-Diagramme haben Kennzahlkopf oder keine Legende, Halo am aktuellen Wert und Audio Graph (D5, D7, D8, D9).

### AP6 · P2-Analysen (M, 1½ Tage) – abhängig von AP4
- **Dateien:** `FTPHistoryCard`, `GoalForecastCard`, `WinterArcView.courseChart`, `AerobicEfficiencyCard`, `PerformanceView.VO2maxCard`, `RelativeEffortViews`, `TrainingDistributionCard` (→ `SegmentedBar(.tall)`), `RideZonesCard`, `WellnessTrendsView`, `Strength/StrengthDetailView`; danach `Theme.cap` aus Diagrammen entfernen.
- **Tests:** Unit `forecastCrossingDateMatchesSentence` (der Schnittpunkt im Diagramm = Datum aus `GoalForecast`), `distributionLabelFitsOrHides`. UI: test25 (`forecast.card`, `distribution.card`, `ftpHistory.card`), Effizienz (`efficiency.chart`), Zonen (`ride.zones`, `ride.zones.power/heart`), Wellness (`wellness.*.chart`) bleiben grün; Screenshots 04/12/20 neu.
- **Akzeptanz:**
  - D14 ohne leere untere Hälfte; D16 ohne Zahl an jedem Punkt.
  - D17 und D18 ohne Füllung unter 3:1.
  - `grep -rn "Theme.cap(" UI` findet nur noch `TypeIcon`.

### AP7 · Abschluss Barrierefreiheit und Screenshots (S, ½ Tag) – abhängig von AP5 + AP6
- **Dateien:** `IndoorCoachUITests/AuditChartsTests.swift` (Matrix), `docs/screenshots/*.png` (01, 04, 05, 07, 08, 10, 12, 13, 20 neu), `docs/04-STATUS.md`.
- **Prüfungen:**
  - Matrix 402 pt (iPhone 17) + SE (375 pt) × hell/dunkel (`XCUIDevice.shared.appearance`) × L/AX5.
  - `performAccessibilityAudit`: kein „Contrast failed ohne Element“ mehr auf Diagrammknoten, damit ist der offene Punkt aus `ux-audit-2026-11-20` geschlossen.
  - VoiceOver-Stichprobe: Profil, Fitness, Leistungskurve, Soll/Ist als je ein Element; Audio Graph spielbar.
  - „Bewegung reduzieren“ an: keine Animation beim Zeitraumwechsel.
- **Akzeptanz:** Audit-Gate für Diagramme grün; Screenshots im Repo; Galerie bleibt DEBUG-only.

**Umfang gesamt:** etwa 8–9 Entwicklertage. Das Profil (AP0–AP3) ist nach etwa 3½ Tagen fertig und überall sichtbar.

---

## 8. Risiken

| # | Risiko | Gegenmaßnahme |
|---|---|---|
| R1 | **Performance in Listen** (Plan mit vielen Zeilen, Heute). | `Canvas` statt Swift Charts für Minis, `Equatable`-View mit `.equatable()`, Geometrie O(n) und < 2 ms (Test). Messung mit Instruments vor und nach AP2. Kein `drawingGroup` nötig; falls doch Hänger auftreten, Geometrie je `(definition, size, scale)` cachen. |
| R2 | **`Canvas` ist für XCUITest unsichtbar.** | Jedes Mini ist ein Element mit `accessibilityIdentifier("profile.mini")`, Label und Wert; das Detail heißt `profile.detail`. |
| R3 | **UI-Tests hängen an Diagramm-Labels und -Identifiern:** `"Verlauf von Fitness und Ermüdung"` (Antippen bei x = 0,3, `AuditWalkthroughTests:560`), `compliance.chart`, `performance.curve`, `efficiency.chart`, `distribution.card`, `forecast.card`, `ftpHistory.card`, `shadow.legend`, `ride.zones*`, `wellness.*.chart`. | Labels und Identifier unverändert lassen (in jedem AP als Akzeptanzkriterium). Das Antippen bei 0,3 trifft im neuen D5 weiterhin einen Tag. Snapshot-Vergleiche gibt es nicht (nur Anhänge), also gibt es keine Pixel-Tests, die brechen könnten. `docs/screenshots` und `snapshots/` werden bewusst neu erzeugt. |
| R4 | **Auswahlgesten gegen Scrollen** (`chartXSelection` in `ScrollView`). | Muster aus D5 (Antippen + waagerechtes Ziehen) übernehmen; je Diagramm in der UI-Prüfung senkrecht wischen und prüfen, dass gescrollt wird. |
| R5 | **Farbwechsel Z1 (Lavendel → Indigo) und Z4 (Mango → Gold) wirkt auf Nutzer ungewohnt;** Chips bleiben Jelly, Diagramme werden kräftiger. | Gleiche Farbfamilien, nur dunkler; Chips und Diagramme behalten dieselbe Farbfamilie je Zone. Entscheidung E1 bietet die Alternative „Schiefergrau“ für Z1. |
| R6 | **Swift-Charts-Unterknoten erzeugen weiter Audit-Befunde.** | Überall `children: .ignore`; Achsenbeschriftung in `axisLabel` (9,3:1). Bleibt ein Befund ohne Element, wird er mit Position protokolliert und in AP7 bewertet. |
| R7 | **Zeitstauchung in Minis** könnte Dauer falsch suggerieren. | Nur in Minis ohne Achse, nur für kurze Intervalle, begrenzt durch Schritt 3 (§4.1); Dauer steht als Text daneben; das Detail staucht nie (Test `detailVariantDoesNotWarpTime`). |
| R8 | **Dunkle Zone Z4/Z3 im CVD-Warnbereich (7,6).** | Zweitkodierung (Höhe, Lücken, Legende, VoiceOver) ist überall vorhanden; der Test hält die Untergrenze 6 fest. |
| R9 | **`chartBackground` + `proxy.plotFrame`** verhält sich beim Ändern der Dynamic-Type-Größe anders als erwartet (Achsenbreite ändert den Plot). | Der Renderer liest das Plot-Rechteck bei jedem Layout neu; Galerie-Screenshots bei L und AX5. |

---

## 9. Entscheidungen für den Produktinhaber

| # | Frage | Empfehlung |
|---|---|---|
| E1 | Z1 als **Indigo** (wie die Referenzen, ruhige dunkle Grundlinie) oder als **Schiefergrau** (näher an Zwift/MyWhoosh, Chroma < 0,10 = bewusst „neutral“)? | Indigo |
| E2 | Wochenumfang auf **Heute** als eine Reihe (Referenz „Woche für Woche“), die Aufteilung Indoor/Outdoor nur in Verlauf und VoiceOver? | ja |
| E3 | Form auf **Heute** als dritte Linie im Fitness-Diagramm (wie Referenz „Monitoring“) oder weiter nur als Kennzahl + Chip? | nur Kennzahl + Chip (die Y-Achse müsste sonst negative Werte zeigen, und die Fitness würde gestaucht); im Detail die divergierenden Balken D6 |

---

## Zusammenfassung

**Inventar:** 20 Diagramme, davon 9 P1:
- Workout-Profil Mini/Detail;
- Zeit in Zonen (Einheit);
- Fitness & Form (Heute);
- Fitness Detail und Form pro Tag;
- Leistungskurve;
- Soll/Ist;
- Verlauf 12 Wochen.

Dazu 10 P2-Analysekarten und 1 P3. Ursache der Unschärfe: Rampen als Treppe aus Scheiben mit Kappen, Kanten auf Subpixeln, keine Lücken, Füllungen 1,6–2,6:1. Weitere Befunde: versteckte Doppelachse (TSS/3) auf Heute, Regenbogen für Form, Zahl an jedem VO₂max-Punkt, Achsen und Legenden uneinheitlich, keine Audio Graphs.

**Kernentscheidungen:**
- Neue Zonen-Marken je Modus mit abwechselnder Helligkeit, alle ≥ 3:1 auf der Karte. Hell bestehen alle Validator-Prüfungen, dunkel mit CVD-Warnung 7,6 bei vorhandener Zweitkodierung. Die Jelly-Farben bleiben für Chips.
- Workout-Profil als reine Geometrie (Block je Schritt, Trapez-Rampen mit exakter Zonenteilung, Pixelraster, Lücken) mit `Canvas`-Renderer. Minis haben eine feste Skala 0–160 %, Mindestbreiten und einen Kompaktmodus, der die Intervallzahl immer erhält. Das Detail nutzt denselben Renderer unter Swift-Charts-Achsen.
- Stil: Linie 2 pt `.monotone` (nie `.catmullRom`), zarte Fläche, offene Marker, Halo am aktuellen Wert, Haarlinien-Gitter, Achsen rechts, Kennzahlkopf als Legende.
- Gestrichelt bedeutet nur „Soll/Ziel/FTP“, punktiert nur „Vorjahr/Vorperiode“.
- Auswahl per Antippen/Ziehen; jedes Diagramm ist ein VoiceOver-Element, Audio Graphs für die P1-Analysen.

**Arbeitspakete:**
- AP0 Palette + Kontrast-/CVD-Tests (½ T);
- AP1 Profilgeometrie mit rund 20 Unit-Tests (1 T);
- AP2 Minis sichtbar in Plan, Heute, Vorschlag + Galerie (1 T);
- AP3 Profil-Detail + Segmentbalken, `PowerProfileChart` entfällt (1 T);
- AP4 ChartStyle/ChartMath/Parts (1 T);
- AP5 P1-Analysen (2 T);
- AP6 P2-Analysen (1½ T);
- AP7 A11y-Matrix + Screenshots (½ T).

Profil fertig nach etwa 3½ Tagen, alles nach etwa 8–9 Tagen. Größte Risiken: UI-Tests an Labels und Identifiern (bleiben unverändert), Auswahlgesten in ScrollViews, Performance in Listen (`Canvas`, `Equatable`, Messung).

### Entschieden (21.11.2026)

- E1: Z1 Indigo (wie Referenz). E2: Wochenumfang auf Heute als eine Reihe. E3: Form auf Heute nicht als dritte Linie, Kennzahl und Chip reichen.

### Umsetzung (21.11.2026)

- AP0–AP7 umgesetzt (Palette, Geometrie, Profil Mini/Detail, Bausteine, P1/P2-Analysen, Galerie-Matrix `AuditChartsTests`).
- Abweichung D9/D10/D11: Vorwochen nicht in `accentMuted`, sondern neutral in `ChartPalette.pastBar` (primary 45 % über der Karte, ≥ 3:1). Nach Sichtprüfung trug der gedämpfte Akzent zu viel Farbe; nur die aktuelle Woche ist farbig, wie in den Referenzen.
- Abweichung D13: Prognoselinie durchgezogen (Fitnessfarbe, 70 % Deckkraft) statt gestrichelt – Strich bleibt Soll/Ziel/FTP vorbehalten.
- Detail-Profil ohne horizontale Gitterlinien (der Renderer liegt hinter dem Plot; Linien liefen sonst durch die Blöcke). Alle Plots sind geclippt; Flächen beginnen an der unteren Domänengrenze (`ChartMath.areaBase`).
- Offen: neue Screenshots in `docs/screenshots`, Auswahlgesten in ScrollViews und Audio Graphs am Gerät prüfen, Instruments-Messung der Listen.
