# 22 · Marktanalyse & Konzept: Begeisterungselemente („Wow-Effekt“)

Stand: 21.11.2026 · Web-Recherche am 21.11.2026 · erarbeitet von einem Produktstrategie-/UX-Research-Agent · Status: **Konzept, noch nicht freigegeben** (Entscheidungen in §7)

**Auftrag (Produktinhaber):** „Suche Begeisterungselemente für die vorhandenen Personas und baue sie in die App ein, um einen Wow-Effekt zu erzeugen. Gehe dafür zunächst in die Marktanalyse und baue anschließend eine qualitativ hochwertige Integration in die App.“
**Zielgruppe:** alle, die im Winterloch stecken. Niemand muss technisch begabt sein.

**Ergebnis in einem Satz:** IndoorCoach *berechnet* schon fast alles, was begeistern kann (Level, Etappen, Bestleistungen, Challenges, Serie, Effizienz). Es fehlt der **Moment**, in dem man das spürt. Die Empfehlung: vier aufeinander abgestimmte Elemente unter dem Motto **„Vom Frost zum Frühling“**:
1. Gipfelmoment nach der Fahrt
2. Postkarten von der Alpenüberquerung
3. Winterlicht
4. Willkommen zurück mit deinem Warum

Alle vier laufen lokal, ohne Verbindung und ohne Claude-Key.

---

## 0. Ist-Stand: Was es schon gibt (nicht erneut vorschlagen)

| Bereich | Vorhanden | Lücke aus Sicht „Begeisterung“ |
|---|---|---|
| Winter Arc | 10 Level („Erster Frost“ bis „Frühlingsform“), Kurs, Vorjahres-Schatten, Prognose mit Was-wäre-wenn | Ein Level-Aufstieg passiert **still**: Die Karte zeigt einfach das neue Level. |
| Winter-Reise | `WinterJourney`: 10 Etappen von Garmisch zum Gardasee, Position = Level + Fortschritt | Rein darstellend: Orte ohne Geschichte, kein Ankommen. |
| Trophäen & Challenges | `Trophies.all` (Challenges, Level, Serie 4/8/12, Kraft-Winter, Bestleistungen, „Sekundengenau“), 4 Saison-Challenges, Highlight-Slot | Trophäen werden **berechnet, aber nie überreicht**. Es gibt keinen „gesehen“-Zustand und keinen Neu-Moment (Code-Suche: kein `seen`/`levelUp`). |
| Nach der Fahrt | Banner „MyWhoosh: 1 Fahrt importiert.“, Fahrt-Detail mit Soll/Ist, `RideChallengeNote` | Der emotional stärkste Moment (gerade gefahren, stolz) bekommt nur einen Text-Banner. |
| Rückblicke | Wochenrückblick (Sonntag, regelbasierte Sätze), Saisonrückblick als Bild (1080×1350, `SeasonShareCard`) | Teilen gibt es nur einmal pro Saison. Über Wochen hinweg sagt der Coach nichts Persönliches. |
| Konstanz | Wochen-Serie mit Joker, Ruhewochen zählen, „angepasst statt ausgefallen“ | Nach einer Pause (Krankheit, Weihnachten, Skiurlaub) gibt es keinen freundlichen Wiedereinstieg. |
| Coach | Claude-Plan (optional, eigener Key), Check-in, Trend-Wächter | Ohne Key spricht der Coach nie direkt zum Nutzer. |
| Technik | Theme „Sunset Jelly“ (`Theme.sunset`, `JellyButtonStyle`), `ImageRenderer`-Teilen, Live Activity, Feature-Tour mit eigener Animationsschleife, `accessibilityReduceMotion` an 4 Stellen | Es gibt keine gemeinsame Feier-Komponente, keine Haptik-Konvention und keinen Datums-Override für UI-Tests. |

**Leitplanken (gelten weiter):**
- keine Tagesstreaks
- keine Ranglisten nach Watt
- Ruhe zählt
- jede Kennzahl nennt ihre Quelle
- kein Backend
- nichts verlässt das Gerät ohne Zutun

---

## 1. Marktanalyse (Kano: Begeisterungsmerkmale)

**Methode:** Web-Recherche am 21.11.2026: Hersteller-Seiten, Fachpresse, Foren und eine qualitative Studie. Herstellerzahlen sind als solche markiert. Bewertet wird, was **unerwartet** ist und **emotional wirkt**, und was Nutzer daran lieben oder kritisieren.

### 1.1 Kurzfassung

| App | Begeisterungsmerkmal | Warum es wirkt / Kritik | Übertragbar auf IndoorCoach | Quelle |
|---|---|---|---|---|
| **Zwift** | **Progress Report** direkt nach jeder Fahrt (seit 12/2025): Level, Erfolge, Abstand zum nächsten Meilenstein, Jahresbestleistungen, Wochenziel. Lässt sich als Bild speichern. | Abschluss-Ritual im Moment des Stolzes. **Kritik:** nur etwa 15 s sichtbar, nicht später aufrufbar, nicht auszublenden. | **Hoch:** Feier nach der Fahrt, aber ohne Zeitlimit, später im Verlauf abrufbar und abschaltbar. | [Zwift-Forum 12/2025](https://forums.zwift.com/t/introducing-progress-report-screen-december-2025/660989) |
| Zwift | **Spinback**: persönliches Jahresvideo (Distanz, Höhenmeter, Ride Ons), nur in der Companion-App | Erzählung und Identität. Startprobleme laut Forum. | Mittel: Den Saisonrückblick gibt es schon, ein Story-Format kann später kommen. | [Zwift Insider: Spinback 2025](https://zwiftinsider.com/2025-spinback/), [Zwift News](https://news.zwift.com/en-WW/258580-spinback-2025-a-year-on-zwift/) |
| Zwift | **Drops/Drop Shop**, Tour-Fever-Drop (+17 % Käufe, Herstellerangabe), neu: **Watt Lock** für disziplinierte Erholungstage | Variable Belohnung, Sammeln | Gering: keine Währung und kein Shop (Leitplanke). Sammeln ja, aber als **Postkarten** statt Kaufware. | [bikerumor, Herbst 2026](https://bikerumor.com/zwift-fall-2026-update-whoop-recovery-watt-lock-new-watopia-roads-zwift-ride-v2/), [BikeRadar](https://bikeradar.com/news/this-season-on-zwift-fall-2026) |
| **MyWhoosh** | Kostenlos, 5.7 bringt **Streaks**, Strava- und TrainerDay-Import | Niedrige Hürde. Soziale Funktionen hinken laut Tests hinterher. | IndoorCoach ergänzt MyWhoosh. Streaks gibt es schon, bewusst wochenbasiert. Die Lücke ist die **Bedeutung** der Fahrt. | [bike-magazin: MyWhoosh 5.7](https://www.bike-magazin.de/en/training/fitness/mywhoosh-5-7-updates-free-training-now-also-with-strava-trainerday-and-bikecontrol/), [cyclistshub](https://www.cyclistshub.com/mywhoosh-review) |
| **Rouvy** | **Karriere** mit bis zu 100 Leveln, Real-Routen, Segment-Trophäen, Lebenszeit-Erfolge | Fortschritt als Reise über **echte Orte** | **Hoch:** Die Winter-Reise hat echte Orte, die aber noch stumm sind. Daraus werden Postkarten. | [Rouvy Career](https://rouvy.com/en/career), [tri247](https://www.tri247.com/rouvy/how-to-level-up-on-rouvy-career-coins-and-experience-points-explained) |
| **TrainerRoad** | **AI FTP Detection** („kein Testtag-Stress“), Adaptive Training | „Die App merkt, dass ich stärker werde.“ Das nimmt Angst. Zahlen sind Herstellerangaben. **Kritik:** Bei manueller FTP greift die KI schlechter. | **Hoch:** eFTP gibt es schon. Ein Sprung der eFTP wird ein feierbarer Moment. | [TrainerRoad-Blog](https://www.trainerroad.com/blog/no-more-test-day-stress-how-ai-ftp-detection-makes-you-faster/), [Forum: 6-Monats-Review](https://www.trainerroad.com/forum/t/my-six-month-review-and-opinion-of-tr-ai-okay-but-also-not/113957) |
| **Wahoo SYSTM** | Test „Full Frontal“ als **Erzählung mit Humor** (Sufferlandria), 4DP-Profil | Humor und Story machen Härte erträglich. **Kritik:** Testergebnisse verwirren manche. | Mittel: **Tonalität** für eigene Texte (Postkarten mit Augenzwinkern), ohne Figuren zu übernehmen | [Cycling Weekly](https://www.cyclingweekly.com/products/wahoo-systm-absorbs-the-sufferfest-into-a-new-more-corporate-app-and-you-should-absolutely-check-it-out), [road.cc](https://road.cc/content/review/wahoo-systm-training-app-290899) |
| **TrainingPeaks** | **Peak Performances** (Bestleistungen je Jahr und gesamt). Der Alarm geht vor allem an den **Coach**. | Dokumentiert, aber der Athlet wird kaum gefeiert. | **Hoch:** Genau hier liegt die Lücke: Der Athlet selbst wird gefeiert. | [TrainingPeaks: Peak Performances](https://www.trainingpeaks.com/learn/articles/peak-performances), [Coach-Alerts](https://help.trainingpeaks.com/hc/en-us/articles/115006532487) |
| **intervals.icu** | Kostenlos, Fitness-Chart (CTL/ATL/TSB), tiefe Analyse | Kompetenz und Kontrolle. **Kritik:** Das Diagramm ist schwer zu lesen („warum ist Ermüdung über Fitness?“). | Zahlen in **Sätze** übersetzen (Coach-Notiz) | [intervals.icu Fitness-Chart](https://www.intervals.icu/features/fitness-chart/), [Fast Talk Labs](https://fasttalklabs.com/training/a-deeper-dive-into-intervals-icu), [TrainerRoad-Forum](https://www.trainerroad.com/forum/t/thoughts-on-intervals-icu-data-breakdown/24698?page=3) |
| **Strava** | **Year in Sport** (2025 nur noch im Abo: Unmut), **Kudos** (14 Mrd. im Jahr) | Rückblick und soziale Anerkennung. Die Paywall kostet Sympathie. | Rückblicke **kostenlos und lokal**. Anerkennung kommt vom eigenen Coach und aus der eigenen Gruppe (Teilen). | [Ars Technica via Harvard TagTeam](https://tagteam.harvard.edu/hub_feeds/3415/feed_items/17132945/content), [Strava-Support](https://support.strava.com/hc/en-us/articles/22067973274509-Your-Year-in-Sport), [Strava Trend Report](https://www.endurancesportswire.com/strava-releases-12th-annual-year-in-sport-trend-report-revealing-that-doomscrolling-is-out-movement-is-in/) |
| Strava | **Athlete Intelligence** (KI-Zusammenfassung je Aktivität) | **Studie (297 Reddit-Threads):** „Captain Obvious“. Die KI ignoriert Kontext (Absicht, Müdigkeit), sieht nur die Einzelfahrt, hat für alle denselben **immer positiven** Ton und lässt Pausen außer Acht. Empfehlung der Autoren: Muster über Wochen zeigen, Kontext einholen, Pausen akzeptieren, Beobachtung statt Urteil. | **Sehr hoch:** Die Coach-Notiz nutzt den **Langzeitbezug** und Kontext aus dem Check-in, der Ton passt sich an, Pausen werden willkommen geheißen. | [Shalawadi, Wester et al. 2026 (Zusammenfassung)](https://www.themoonlight.io/review/who-gets-to-interpret-the-workout-user-tensions-with-ai-generated-fitness-feedback), [Cycling Weekly](https://www.cyclingweekly.com/news/strava-says-its-new-ai-feature-is-not-a-novelty-but-i-think-its-pointless), [TechRadar](https://techradar.com/health-fitness/i-used-stravas-new-athlete-intelligence-ai-feature-for-a-week-heres-what-happened) |
| **Garmin Connect** | Badges und Challenges. 2025 teils hinter Connect+ (Kritik „pay-to-win“), Badges kommen nicht an. | Sammeln motiviert, aber Paywall und Fehler zerstören Vertrauen. | Alles ohne Abo, lokal und deterministisch (Unit-Tests) | [Gadgets & Wearables](https://gadgetsandwearables.com/2025/03/28/garmin-badge-pay/), [Garmin-Forum 2026](https://forums.garmin.com/apps-software/mobile-apps-web/f/garmin-connect-web/443421/2026-cycling---stage-3-challenge---connect-cannot-count) |
| **Whoop** | Früher geliebt: „Monthly Performance Assessment“. Die neue „Month in Review“ gilt als oberflächlich. Journal „Verhalten ↔ Erholung“. | **Tiefe persönliche Einsicht schlägt Unterhaltung.** | Die Coach-Notiz braucht eine echte Einsicht aus eigenen Daten statt Floskeln. | [Whoop-Community](https://www.community.whoop.com/t/new-month-in-review-is-a-huge-disappointment/9035), [Whoop-Community: Lieblingsfunktion](https://www.community.whoop.com/t/whats-one-whoop-feature-you-love/1629) |
| **Oura** | Year in Review mit „Element-Persönlichkeit“ (Erde, Wasser, Feuer, Luft) | Identität durch Typ-Zuschreibung | Später: „Dein Wintertyp“ im Saisonrückblick | [Wareable](https://www.wareable.com/wearable-tech/oura-year-in-review-2025-sleep-stress-data-elemental) |
| **Apple Fitness / Aktivitätsringe** | Ringe schließen mit animierten Awards, Ringe an Ruhetagen **pausieren**. **Workout Buddy** (KI-Stimme, watchOS 26) | Abschlussgeste, visuelle Vollständigkeit, Pause ist erlaubt. Workout Buddy: gemischte Tests. | Abschluss-Moment als **eigene** Geste (keine Ringe). Pausen ausdrücklich erlaubt. Sprach-Coach erst später. | [Apple Newsroom 04/2025](https://www.apple.com/newsroom/2025/04/get-active-with-apple-watch/), [Tom's Guide](https://www.tomsguide.com/wellness/fitness/i-ran-15-miles-with-the-apple-watchs-new-workout-buddy-heres-my-verdict), [Macworld](https://www.macworld.com/article/2888428/ive-been-using-watchos-26-for-months-its-not-ready-for-your-apple-watch.html) |
| **Duolingo** | Streak, **Streak Freeze**, Maskottchen | Verlustaversion plus „etwas Nachsicht motiviert mehr als starre Regeln“ (Duolingo zitiert UPenn/UCLA). **Kritik:** Ein gerissener Streak fühlt sich wie ein Urteil an und wird zum Ausstiegspunkt. | Den Joker gibt es schon. **Kein Maskottchen-Klon.** Wiedereinstieg ohne Urteil (Willkommen zurück). | [Duolingo-Blog](https://blog.duolingo.com/how-duolingo-streak-builds-habit), [Smashing Magazine 02/2026](https://smashingmagazine.com/2026/02/designing-streak-system-ux-psychology/) |
| **Peloton** | **Meilensteine** (100. Fahrt): Shoutout der Trainer, High Fives, Abzeichen | Anerkennung durch Menschen im Moment | Mittel: Ohne Backend kommt die Anerkennung durch persönliche Coach-Worte und durch Teilen in der eigenen Gruppe. | [Peloton: Milestones](https://www.onepeloton.com/blog/milestones), [Peloton: High Fives](https://www.onepeloton.com/blog/peloton-motivation-high-fives) |
| **Runna** (KI-Coach) | Personalisierte, flexible Pläne. **Kritik:** Bugs, Support. Ohne Feedback zur Härte riskante Steigerung. | Plan „für mich“ | Den Claude-Plan gibt es schon, der Check-in liefert Kontext. Begeisterung entsteht eher **nach** der Einheit. | [the5krunner 02/2026](https://the5krunner.com/2026/02/21/runna-ai-marathon-training-injury/), [Trustpilot](https://www.trustpilot.com/review/runna.com?page=2) |
| **Spotify Wrapped** | Daten als **Story**, Hochformat 9:16, der Nutzer steht im Mittelpunkt, nicht die Marke | „People share stories, not charts.“ Teilen ist Selbstausdruck. | Teilen-Bilder zeigen die Person und ihren Weg, das App-Logo bleibt klein. Story-Format 9:16. | [Fortune 12/2025](https://fortune.com/2025/12/03/why-spotify-wrapped-marketing-genius-individuality-uniqueness-belonging-psychology/), [uxdesign.cc](https://uxdesign.cc/why-is-spotify-wrapped-so-popular-5c503e79a3ee) |

**Forschung (Mechanismen, die die Auswahl begründen):**
- **Fresh-Start-Effekt:** Zeitliche Marken (neue Woche, neuer Monat, Neujahr, Feiertage) erhöhen die Bereitschaft, Ziele anzugehen, weil sie vom „alten Ich“ trennen. Der Effekt ist eher kurz, kann aber reichen. [Dai, Milkman, Riis 2014, Management Science](https://faculty.wharton.upenn.edu/wp-content/uploads/2014/06/Dai_Fresh_Start_2014_Mgmt_Sci.pdf), [Wharton](https://knowledge.wharton.upenn.edu/article/need-fresh-start-heres-begin/). Daraus folgen **Wintersonnenwende** und **Willkommen zurück**.
- **Endowed Progress / Goal Gradient:** Wer sich näher am Ziel sieht, strengt sich mehr an. Vorgegebener Fortschritt steigert die Abschlussquote (Waschanlagen-Feldversuch). [Nunes & Drèze 2006](https://msbfile03.usc.edu/digitalmeasures/jnunes/intellcont/Endowed%20Progress%20Effect-1.pdf), [Kivetz et al. 2006](https://business.columbia.edu/faculty/research/goal-gradient-hypothesis-resurrected-purchase-acceleration-illusionary-goal). Daraus folgen der **sichtbare nächste Ort** auf der Postkarte und „+34 min Licht“.

### 1.2 Muster, die wirken, und Muster, die schaden

| Wirkt (übernehmen) | Schadet (vermeiden) |
|---|---|
| Feier **im Moment** nach der Fahrt (Zwift Progress Report) | Zeitlimit oder Zwang: Zwifts 15 s, ein Feier-Screen, den man nicht abschalten kann |
| Fortschritt als **Reise über echte Orte** (Rouvy) | Shop, Währung, Lootboxen (Drops) |
| **Langzeit-Vergleich mit dir selbst** („gleiche Watt, weniger Puls als im November“) | KI-Floskeln ohne Kontext, immer gleich positiv (Strava-Studie) |
| **Nachsicht** bei Pausen (Streak Freeze, Ringe pausieren) | Ein gerissener Streak als Urteil, rote Zahlen nach dem Urlaub |
| **Zeitliche Marken** als Neubeginn | Paywall vor dem eigenen Rückblick (Strava, Garmin) |
| Teilen als **Selbstausdruck**, Person statt Marke (Wrapped) | Fremde Marken oder Leistungswerte ungefragt auf dem Bild |
| **Humor und Erzählung** in der Härte (SYSTM) | Kopierte Figuren, Maskottchen oder Welten |

**Marktlücke für IndoorCoach:** Kein Anbieter verbindet einen **Winter-spezifischen Erzählbogen** (Licht, Reise, Frühling) mit einer **ehrlichen, kontextbewussten Coach-Stimme ohne KI-Pflicht** und **Feiern ohne Abo und Backend**. Gerade Nutzer von MyWhoosh (kostenlos, schwach bei Bedeutung und Sozialem) und intervals.icu (stark bei Zahlen, schwach bei Gefühl) haben diese Lücke.

---

## 2. Personas: emotionale Hürde im Winter und Wow-Momente

Personas aus [docs/20 §2](20-KONZEPT-ONBOARDING-DIENSTE.md). Die Alltagsprofile Markus, Sabine (Garmin) und Jonas aus [docs/17 §4](17-BRAINSTORM-DATENQUELLEN-ALLTAG.md) und Lena aus [docs/14](14-SEKUNDENDATEN-MAC-BRUECKE.md) sind als Varianten mitgedacht.

| Persona | Größte emotionale Hürde im Winter | Wow-Momente (Shortlist-Bezug) |
|---|---|---|
| **P1 Sabine, 52** (MyWhoosh auf dem Mac, Wahoo-Rolle, Angst vor IT) | „Bringt das überhaupt was? Halte ich im Frühjahr mit dem Treff mit?“ Dazu dunkle Abende und die Unsicherheit, ob die Daten richtig angekommen sind. | 1. **Gipfelmoment** nach der Fahrt: „Deine beste 20-Minuten-Leistung seit Juli“, sichtbar, ohne etwas suchen zu müssen (B1).<br>2. **Postkarte vom Reschenpass** für die Treff-WhatsApp-Gruppe, ohne Watt und ohne fremde Marke (B2).<br>3. **Winterlicht:** „+41 Minuten Tageslicht seit der Sonnenwende“ (B3). |
| **P2 Tobias, 34** (Zwift auf Apple TV, Strava, intervals.icu) | Strukturiertes Training fühlt sich gegenüber Rennen in der bunten Welt langweilig an. Der Plan „verschwindet“ in Zwift. Der Stolz bleibt dort, IndoorCoach wirkt wie Buchhaltung. | 1. **Gipfelmoment** mit „Plan der Woche geschafft · 4/4“ und Bestleistung aus den intervals.icu-Sekundendaten (B1).<br>2. **Teilen im Story-Format**, das ihn zeigt statt einer App (B1).<br>3. **Willkommen zurück** nach der Dienstreise statt roter Formkurve (B4). |
| **P3 Claudia, 41** (Garmin, läuft, 2× Rolle, wenig Zeit, iPhone SE) | Schlechtes Gewissen in Wochen mit weniger Einheiten. Fachbegriffe. „Ich bin keine richtige Radfahrerin, ich laufe ja auch.“ | 1. **Willkommen zurück** ohne Urteil, mit ihrem eigenen Satz: „Du hast geschrieben: Fit in den Frühling, ohne Stress.“ (B4)<br>2. **Coach-Notiz** in Alltagssprache, die die ganze Woche würdigt (B1).<br>3. **Winterlicht** als stiller Trost (B3). |
| **P4 Murat, 29** (Einsteiger, keine App, Gurt aus dem Studio) | Fühlt sich als Hochstapler, Zahlen sagen ihm nichts, Angst, „falsch“ zu trainieren | 1. **Erste Fahrt = erste Etappe:** Gipfelmoment „Start in Garmisch“ mit Postkarte statt Wattzahl (B1+B2).<br>2. **Dein Warum** gibt seinem Winter einen Satz: „Rad und Studio kombinieren, im Mai fit sein“ (B4).<br>3. Postkarten **sammeln** statt Watt vergleichen (B2). |
| **P5 Jan** (Entwickler, will Tempo) | Störende Animationen, Klicks, Wiederholung | Alles ist mit einem Tipp oder Wischen weg, abschaltbar unter Profil → App und per UI-Test-Argument steuerbar. Die Coach-Notiz zeigt die Quelle („aus deinen Sekundendaten“). |

---

## 3. Ideen-Longlist (22 Ideen)

Legende:
- **Wow:** 1–5
- **Nutzen je Persona:** ● hoch, ◐ mittel, ○ gering
- **Aufwand:** S ≤ ½ Tag, M ≈ 1 Tag, L > 2 Tage
- **Risiko:** Datenschutz/App Store
- **Offline:** funktioniert ohne Verbindung, im Demo-Modus und ohne Claude-Key (✅ voll, ◐ eingeschränkt, ❌ nein)

| ID | Idee | Wow | P1 | P2 | P3 | P4 | Aufwand | Risiko DS/App Store | Offline | Abgrenzung zu Vorhandenem |
|---|---|---|---|---|---|---|---|---|---|---|
| **L1** | **Gipfelmoment:** Moment-Erkennung (Level, Bestleistung, Challenge, Serie, Plan der Woche, erste Fahrt, Comeback, eFTP-Sprung) plus Feier-Bildschirm nach neuen Fahrten | 5 | ● | ● | ● | ● | M–L | gering (lokal) | ✅ | Trophäen und Level werden heute nur berechnet. L1 **überreicht** sie einmal im richtigen Moment. |
| **L2** | **Postkarten von der Alpenüberquerung:** je Etappe eine eigene illustrierte Karte mit Text, Album, Teilen | 4 | ● | ◐ | ◐ | ● | M | gering (keine Fotos, keine Marken) | ✅ | `WinterJourney` hat Orte, aber keine Geschichte und kein Ankommen. |
| **L3** | **Winterlicht:** „+34 min Tageslicht seit der Sonnenwende“, Countdown, Himmel im Winter Arc wird mit dem Fortschritt heller | 4 | ● | ◐ | ● | ● | S–M | keins (keine Ortung, Breitengrad als Näherung) | ✅ | Neu. Passt zu Level 5 „Wintersonnenwende“. |
| **L4** | **Willkommen zurück:** Karte nach ≥ 10 Tagen Pause, lockerer Wiedereinstieg mit einem Tipp, Comeback-Moment | 4 | ◐ | ● | ● | ● | S–M | keins | ✅ | Joker und Swap gibt es schon, aber keinen Wiedereinstieg als Erlebnis. |
| **L5** | **Dein Warum:** 1 Satz zu Saisonbeginn, die App zeigt ihn im richtigen Moment (Comeback, Level 5, Level 10) | 4 | ● | ◐ | ● | ● | S | gering (Freitext bleibt lokal und geht nicht an Claude) | ✅ | Das Profilziel ist ein Datum oder Event, kein persönlicher Satz. |
| **L6** | **Coach-Notiz ohne KI:** ein regelbasierter Satz mit Langzeitbezug und Kontext aus dem Check-in, der Ton passt sich an | 4 | ● | ● | ● | ● | M | keins | ✅ | Der Wochenrückblick fasst nur die Woche zusammen. L6 vergleicht über Monate und kennt den Check-in. |
| L7 | **Brief an dein Frühlings-Ich:** Zeitkapsel, im November geschrieben und am Zieltag geöffnet | 5 | ● | ◐ | ● | ● | S | gering | ✅ | Erweiterung von L5. Kann in L5 aufgehen (Level 10 zeigt den Satz). |
| L8 | **Adventsweg (1.–24.12.):** je *gefahrener* Einheit öffnet sich ein Türchen (Tipp, Postkarten-Vorschau). Keine Tagespflicht. | 4 | ● | ◐ | ◐ | ● | M | gering | ✅ | Neu, saisonal. Nah an den Challenges. Kandidat für Welle 2, eng getaktet (heute 21.11.). |
| L9 | **Winter-Story (Wrapped-artig):** 6 Karten im Hochformat am Monatsende und Ende März | 4 | ◐ | ● | ◐ | ◐ | M–L | gering | ✅ | Der Saisonrückblick ist heute **ein** Bild. |
| L10 | **eFTP-Sprung als Moment:** „Deine Schwelle ist gestiegen: 231 → 238 W, ohne Test“ | 4 | ◐ | ● | ○ | ◐ | S (als Kind in L1) | keins | ◐ (braucht Sekundendaten, Demo hat sie) | Den eFTP-Verlauf gibt es, aber keinen Moment. In L1 aufgenommen. |
| L11 | **Ruhe-Quittung:** Ruhetag oder Ruhewoche wird sichtbar „verbucht“ („Erholung zählt: 2 Ruhetage, wie geplant“) | 3 | ◐ | ○ | ● | ◐ | S | keins | ✅ | Die Ruhewoche-Regel gibt es, aber kein Gefühl dazu. |
| L12 | **Formkurven-Zeitraffer:** Fitness seit dem 1.11. zeichnet sich beim Level-Aufstieg einmal animiert | 3 | ◐ | ● | ○ | ○ | S | keins | ✅ | Diagramm D14 ist statisch. Optionaler Teil von L1. |
| L13 | **Monatskapitel:** Monatsabschluss mit Titel („Dein Dezember: 9 Einheiten, 3 Etappen“) | 3 | ◐ | ◐ | ◐ | ◐ | M | keins | ✅ | Überschneidet sich mit dem Wochenrückblick, später mit L9 bündeln. |
| L14 | **Widget/Sperrbildschirm „Heute“** mit Winterlicht und Level | 3 | ◐ | ◐ | ● | ◐ | L | gering, aber Signierung und App Group | ✅ | Roadmap G7, braucht ein eigenes Target. |
| L15 | **Haptischer Intervall-Takt** in der eigenen Aufzeichnung („Intervall getroffen“-Tick) | 3 | ○ | ○ | ◐ | ● | M | keins | ◐ (nur mit Gurt) | Live Activity gibt es schon. Geringe Reichweite (MyWhoosh fährt man woanders). |
| L16 | **Sprach-Coach** (AVSpeech) während der eigenen Aufzeichnung | 2 | ○ | ○ | ◐ | ◐ | M | gering | ◐ | Nervt laut Workout-Buddy-Tests schnell. Später. |
| L17 | **„Fahr mit mir“-Einladung:** Challenge oder Plan als Bild und Text an Freunde teilen, ohne Backend | 3 | ● | ◐ | ◐ | ◐ | S–M | gering | ✅ | Teilen gibt es nur für die Saison. Soziale Bindung ohne Server. |
| L18 | **Eigenes Maskottchen** (z. B. eine Schneeflocke, die zur Sonne wird) | 3 | ◐ | ○ | ◐ | ● | L (Illustration) | Kitsch- und Markenrisiko | ✅ | Bewusst **nicht** in der Shortlist. Die Bildsprache übernimmt der Himmel aus L3. |
| L19 | **„Wusstest du?“-Muster:** „Dienstags fährst du am konstantesten“ | 3 | ◐ | ● | ◐ | ○ | M | gering | ◐ (braucht ≥ 6 Wochen Daten) | Neu. Fehlerrisiko bei wenigen Daten, daher später. |
| L20 | **Claude-Satz zum Gipfelmoment** (optional, mit Einwilligung) | 3 | ◐ | ● | ◐ | ◐ | S | **mittel** (Daten an Claude, Kosten) | ❌ | Die Einwilligung gibt es (`ClaudeConsentSheet`). Erst nach L6, nur als Zusatz. |
| L21 | **Klang beim Gipfelmoment** (kurzes eigenes Jingle) | 2 | ◐ | ◐ | ○ | ◐ | S | keins | ✅ | Viele hören dabei Musik, standardmäßig aus. Später. |
| L22 | **Wintertyp im Saisonrückblick** („Du bist ein Frühaufsteher-Fahrer“) | 3 | ◐ | ● | ◐ | ◐ | S | gering | ✅ | Typ-Zuschreibung wie bei Oura. Mit L9 bündeln. |

**Bewertungsfazit:**
- **L1, L2, L3, L4 + L5** (mit L6 als Teil von L1, L10 als Moment-Art in L1 und L7 als Teil von L5) ergeben zusammen den höchsten Wow-Faktor je Aufwand.
- Sie funktionieren vollständig offline und im Demo-Modus.
- Sie bedienen **alle vier** Zielpersonas.
- Sie haben kein App-Store-Risiko.

---

## 4. Empfehlung: Shortlist „Vom Frost zum Frühling“

**Der rote Faden:**
- Das **Licht** wird jeden Tag mehr (B3).
- Du **reist** Etappe für Etappe Richtung Gardasee (B2).
- Am Ende jeder Fahrt, die etwas bedeutet, stehst du auf dem **Gipfel** (B1).
- Wenn der Winter dich rauswirft, wirst du mit **deinen eigenen Worten** zurückgeholt (B4).

Alle Elemente nutzen dieselbe Bildsprache: Theme „Jelly“ und Sunset-Verlauf. Der Himmel verläuft von Winter-Indigo zu Frühlings-Mango, die Schneeflocken werden weniger.

**Aufwand gesamt:** etwa 5 Entwicklertage. Mit zwei Agents parallel sind es etwa 3 Kalendertage (§5).

| # | Element | Kern | Aufwand |
|---|---|---|---|
| B1 | Gipfelmoment nach der Fahrt (mit Coach-Notiz) | Moment-Erkennung + Feier-Bildschirm + Teilen | 1,5 d |
| B2 | Postkarten von der Alpenüberquerung | 10 Karten, Album, Teilen | 1 d |
| B3 | Winterlicht | Tageslicht-Gewinn, Countdown, lebendiger Himmel | 0,75 d |
| B4 | Willkommen zurück & Dein Warum | Comeback-Karte, ein Satz, der wiederkommt | 0,75 d |
| – | AP0 Verträge, AP7 Abschluss | gemeinsame Bausteine, Integration, Matrix | 1 d |

### Gemeinsame Regeln für alle vier Elemente

**Bewegung:**
- `@Environment(\.accessibilityReduceMotion)` ist Pflicht.
- Bei „Bewegung reduzieren“: keine Partikel, kein Skalieren, nur eine Überblendung von 0,2 s.
- Bei Stromsparmodus (`ProcessInfo.isLowPowerModeEnabled`) bleiben die Partikel statisch.
- Gemeinsame Komponente `CelebrationMotion` mit genau zwei Kurven: `.spring(duration: 0,5, bounce: 0,25)` und `.smooth(0,25)`.

**Haptik:**
- `.sensoryFeedback(.success, trigger:)` einmal beim Erscheinen eines Gipfelmoments, `.impact(weight: .light)` beim Umblättern einer Postkarte.
- Das System respektiert die Einstellung „Systemhaptik“ selbst. Keine Haptik in Listen und keine Haptik in Dauerschleife.

**Barrierefreiheit:**
- Dynamic Type bis AX5: Inhalte stehen in einer `ScrollView`, und keine Zahl ist abgeschnitten.
- VoiceOver: Die Überschrift ist `.isHeader` und bekommt beim Erscheinen den Fokus (`@AccessibilityFocusState`). Dekorative Grafik ist `accessibilityHidden`.
- Kontrast: Text steht nie direkt auf dem Himmel, sondern als Tinte `#24131D` auf Sunset (≥ 6,9:1, vorhanden) oder auf Kartenweiß.
- Jede Aktion hat ein Label. Kein Element verschwindet automatisch (Lehre aus Zwifts 15 s).

**Datenschutz:**
- Alles wird auf dem Gerät berechnet. Der Speicher liegt in `UserDefaults` und wird von „Alle Daten löschen“ erfasst.
- Kein Netzwerk, keine Ortung, keine neuen Berechtigungen, keine Mitteilungen.
- Teilen nur über das System-Teilen-Menü nach einem Tipp. Bilder werden als PNG im temporären Ordner abgelegt.
- „Dein Warum“ geht **nie** an Claude.

**Teilen ohne fremde Marken:**
- Auf Bildern stehen keine Namen von Diensten (MyWhoosh, Zwift, Strava, Garmin, intervals.icu …).
- Fahrtnamen werden durch den Einheitentyp ersetzt („Sweet Spot 3×12“). Die Funktion `ShareText.neutral(_:)` entfernt bekannte Dienstnamen.
- Leistungswerte und Puls stehen nur auf dem Bild, wenn „Werte zeigen“ eingeschaltet ist (Standard: aus). Der Name steht nur darauf, wenn er im Profil gesetzt ist.
- Das IndoorCoach-Logo bleibt klein am unteren Rand.

**Demo und ohne Verbindung:** Jedes Element hat einen Demo-Pfad. Demo-Momente tragen den Hinweis „Beispiel mit Demo-Daten“, damit die Leitplanke „Quelle sichtbar“ gilt.

**Abschaltbar:** Unter Profil → App gibt es den Schalter „Feiern nach der Fahrt“ (Standard: an). Die Postkarten im Album und Winterlicht bleiben auch bei ausgeschaltetem Schalter.

---

### B1 · Gipfelmoment nach der Fahrt

**User Story:** Als Fahrerin, die gerade eine Einheit beendet hat, möchte ich beim Öffnen der App sofort sehen, was diese Fahrt bedeutet (neues Level, Bestleistung, geschaffte Woche), damit ich stolz bin und morgen wieder fahre.

**Auslöser und Moment:**
- Neue Aktivitäten landen in der Datenbank, egal über welchen Weg: MyWhoosh-Import, intervals.icu, Mac-Brücke, FIT-Import, eigene Aufzeichnung, Strava, Apple Health.
- Beim nächsten `scenePhase == .active` (oder sofort, wenn die App offen ist) wertet `AppModel.evaluateMoments()` den Stand aus.
- Der Gipfelmoment erscheint nur, wenn keine Einführung, keine Aufzeichnung und kein anderes Blatt offen ist.
- Höchstens **ein** Gipfelmoment pro Auswertung, mit bis zu 3 Teil-Momenten.

**Moment-Arten (Priorität absteigend) und stabile IDs:**

| Art | Bedingung | ID | Überschrift (Beispiel) |
|---|---|---|---|
| `levelUp` | Winter-Arc-Level gestiegen (Level = Etappe, daher **mit Postkarte**) | `level-<n>-<saison>` | „Level 4 · Rollen-Routine“ / „Etappe 4: Stilfser Joch“ |
| `record` | neue Bestleistung (90 Tage) über 5 s, 1, 5, 20 min (`PowerCurve.records`) | `record-<dauer>-<rideID>` | „Neue Bestleistung: 5 min · 268 W“ |
| `ftpRise` | eFTP ≥ 2 % über dem letzten gefeierten Wert | `ftp-<watt>-<saison>` | „Deine Schwelle ist gestiegen: 231 → 238 W“ |
| `challengeCompleted` | Challenge geschafft (`Challenges.completed(by:)`) | `challenge-<id>` | „Indoor-500 geschafft“ |
| `comeback` | Lücke ≥ 10 Tage vor der neuen Aktivität | `comeback-<rideID>` | „Du bist zurück“ |
| `streak` | Serie erreicht 4, 8 oder 12 Wochen | `streak-<n>-<saison>` | „8 Wochen in Folge“ |
| `firstRide` | erste Fahrt der Saison | `first-<saison>` | „Start in Garmisch“ |
| `weekPlanDone` | alle geplanten Einheiten der Woche erledigt (`Adherence.done == planned`, planned ≥ 2) | `week-<wochenstart>` | „Plan der Woche geschafft · 4/4“ |
| `strengthTier` | Kraft-Winter 8/16/24 | `strength-<n>-<saison>` | „Kraft-Winter · 16“ |
| `secondData` | erste Fahrt mit Sekundendaten | `seconds-first` | „Sekundengenau“ |

**Regeln der Erkennung (pure Funktion, Kern der Tests):**
1. **Frische:** Nur Ereignisse mit Datum ≥ jetzt − 72 h kommen in Frage.
2. **Erstauswertung** (Ledger nicht initialisiert, z. B. nach Neuinstallation oder dem ersten Import von 210 Tagen):
   - Alle schon verdienten IDs werden still als gesehen markiert.
   - Ausnahme: der **eine** wichtigste Moment der letzten 72 h.
   - So gibt es kein Trophäen-Feuerwerk mit 30 Karten.
3. Dieselbe ID erscheint **nie zweimal**. Der Ledger speichert gesehene IDs, höchstens 500, die ältesten fallen heraus.
4. Höchstens 3 Teil-Momente pro Gipfelmoment, nach Priorität. Der Rest wird still als gesehen markiert.
5. `levelUp` und Etappe sind dasselbe Ereignis (`WinterJourney.position(level:)`), also gibt es eine Karte und keine doppelte Feier.
6. Demo-Modus: genau ein Beispiel-Moment (`levelUp` aus den Demo-Daten) nach dem ersten Öffnen von Heute, mit dem Hinweis „Beispiel“.

**Coach-Notiz (Teil von B1, regelbasiert, ohne Claude):**

Ein Satz unter der Überschrift, mit Quelle. Es zählt die erste Regel, die zutrifft. Dieselbe Regel-ID kommt höchstens 1× in 3 aufeinanderfolgenden Notizen vor (Abwechslung, im Ledger gespeichert).

| # | Regel | Text (Beispiel, Du-Form) | Quelle |
|---|---|---|---|
| 1 | Check-in heute „schwer“, „schlecht“ oder „mies“ **und** Einheit gefahren oder gekürzt | „Trotz schwerer Beine gefahren und klug gekürzt. So bleibt man durch den Winter dran.“ | Check-in |
| 2 | aerobe Effizienz: gleiche Watt, ≥ 3 % weniger Puls als in den ersten 3 Wochen der Saison | „Bei 150 W schlägt dein Herz 6-mal pro Minute weniger als Anfang November.“ | gemessen |
| 3 | Aufwärm-Check-Trend sinkt | „Im Aufwärm-Check: 4 Schläge weniger bei gleichen 140 W als vor 5 Wochen.“ | gemessen |
| 4 | Bestleistung mit Vergleich | „Deine stärksten 5 Minuten seit Juli.“ | gemessen/Mindestwert |
| 5 | Serie gewachsen | „5 Wochen in Folge dabei. Anfang November waren es 2.“ | Plan/Fahrten |
| 6 | Fitness gestiegen | „Seit dem 1. November ist deine Fitness von 24 auf 33 gestiegen.“ | geschätzt |
| 7 | Rückfall | „12 Einheiten seit dem 1. November, 9 Stunden auf der Rolle, während draußen Winter ist.“ | Fahrten |

**Tonregeln:**
- höchstens ein Ausrufezeichen
- kein Vergleich mit anderen Menschen
- keine medizinischen Aussagen („Herz gesünder“ ist verboten, „Puls niedriger“ ist erlaubt)
- Name aus dem Profil höchstens in der Überschrift („Stark, Sabine.“) und nur jedes zweite Mal
- nach einem Comeback nie „Fitness gesunken“

Dieser Ansatz antwortet direkt auf die Kritik an KI-Zusammenfassungen (Kontext, Langzeit, Ton, Quelle).

**Screen-Skizze (Vollbild, `fullScreenCover`, Identifier `moment.sheet`):**
- **Hintergrund:** Himmel aus B3 passend zum Level (`WinterSky`), darüber `Theme.sunset` mit 85 % Deckkraft.
- **Oben links:** Knopf „Schließen“ (`xmark`, 44 pt), oben Mitte die kleine Zeile „GIPFELMOMENT · Do., 18. Dez.“
- **Mitte:** Symbol (Level-Symbol, `trophy` …) in einem weißen Kreis (55 %), 160 pt. Darunter die Überschrift (`.largeTitle.bold`, Identifier `moment.headline`), z. B. „Level 4 · Rollen-Routine“, und die Unterzeile „Etappe 4 von 10: Stilfser Joch, 2757 m“.
- **Bei Level:** die **Postkarte** aus B2 in kompakter Form, antippbar → Album.
- **Bei Bestleistung:** „+7 W gegenüber deiner bisherigen Bestleistung (3. Dez.)“ und der Chip „gemessen · Sekundendaten“.
- **Weitere Teil-Momente** als Zeilen mit Symbol: „Challenge Indoor-500 geschafft“, „Plan der Woche geschafft · 4/4“.
- **Karte „Dein Coach“** (Identifier `moment.coachNote`): der Satz der Coach-Notiz und die Quelle klein darunter („aus deinen Sekundendaten“).
- **Bei Level 5 und 10:** zusätzlich „Du hast im November geschrieben: ‚…‘“ (aus B4).
- **Unten:**
  - Hauptknopf „Weiter“ (`JellyButtonStyle`, `moment.continue`)
  - zweiter Knopf „Als Bild teilen“ (`ShareLink`, `moment.share`)
  - darunter der Schalter „Werte auf dem Bild zeigen“ (Standard: aus)
- Im Demo-Modus steht oberhalb der Knöpfe „Beispiel mit Demo-Daten“.

**Animation und Haptik:**
- Der Kreis skaliert von 0,6 auf 1 (Spring), die Überschrift blendet 0,15 s später ein.
- In einem `Canvas` fallen 40 Schneeflocken etwa 1,2 s lang und werden dabei zu goldenen Funken (Farbe von `#FFFFFF` zu `mangoPop`). Danach steht das Bild still, es gibt keine Schleife.
- Haptik `.success` einmal.
- Bei „Bewegung reduzieren“: alles sofort sichtbar, Überblendung von 0,2 s, keine Partikel.

**Teilen:**
- Bild `MomentShareCard` 1080×1920 (Story-Format): Himmel, Symbol, Überschrift, Etappe oder Bestleistung (Werte nur mit Schalter), Datum, „IndoorCoach“ klein.
- Text fürs Teilen: „Gipfelmoment: Level 4 · Rollen-Routine – Etappe Stilfser Joch.“
- Keine Fahrtnamen, keine Dienstnamen.

**Später wieder ansehen:**
- Fahrt-Detail (`RideDetailView`): Zeile „Gipfelmoment dieser Fahrt ansehen“, wenn zu dieser Fahrt ein Moment gehört.
- Trophäenschrank: neue Trophäen tragen 7 Tage einen kleinen Punkt „neu“.

**Akzeptanzkriterien:**
1. Nach dem Import einer Fahrt, die Level 3 → 4 auslöst, erscheint beim nächsten Aktivwerden genau ein Gipfelmoment mit Überschrift „Level 4 · Rollen-Routine“ und der Postkarte „Stilfser Joch“.
2. Ein erster Import mit 210 Tagen Historie zeigt höchstens einen Gipfelmoment.
3. Derselbe Moment erscheint nach einem Neustart nicht erneut.
4. Während einer Aufzeichnung, in der Einführung und bei offenem Blatt erscheint nichts. Der Moment wartet.
5. Mit dem Schalter „Feiern nach der Fahrt“ aus erscheint nichts, die Trophäen sind trotzdem verdient.
6. Bei „Bewegung reduzieren“ gibt es keine Partikel und kein Skalieren. VoiceOver liest zuerst die Überschrift.
7. Das geteilte Bild enthält keine Dienstnamen, ohne Schalter keine Watt- oder Pulswerte und den Namen nur, wenn er gesetzt ist.
8. Ohne Verbindung, ohne Claude-Key und im Demo-Modus funktioniert alles. Demo-Momente sind als Beispiel markiert.
9. Die Coach-Notiz zeigt immer eine Quelle und verwendet nie einen Vergleich mit anderen Menschen.

**Unit-testbare Logik:**
- `MomentDetector.detect(_ input: MomentInput, ledger: MomentLedger, now:) -> MomentBatch`
  - Frische 72 h, Erstauswertung, Deduplizierung, Priorität, Obergrenze 3
  - Level = Etappe ohne Doppelung, Demo-Kennzeichen, Saisonwechsel (IDs je Saison)
  - Zeitzone: Wochenstart Montag in `Locale.de`
- `CoachNote.make(_ context: CoachNoteContext) -> CoachNote?`
  - jede Regel einzeln
  - Abwechslung (3er-Fenster)
  - Tonregeln als Tests: kein „!“ doppelt, keine Wörter aus einer Sperrliste wie „gesünder“, „besser als andere“, „Diagnose“
  - Comeback ohne „gesunken“
- `ShareText.neutral(_:)`: entfernt Dienstnamen, ersetzt Fahrtnamen.
- `MomentLedger`: Codable, Kappung auf 500, Löschen.

**UI-Test-Idee** (`AuditMomentsTests`):
- `-uiMoment levelUp`: Sheet sichtbar, Überschrift, Postkarte, Coach-Notiz, Teilen vorhanden; „Weiter“ schließt; erneuter Start zeigt nichts.
- `-uiMoment record -uiReduceMotion` (über das Accessibility-Override des Simulators): sofort vollständig.
- Matrix AX5 + Dark + iPhone SE: alles scrollbar, `performAccessibilityAudit()` grün.

**Betroffene Dateien (neu, sofern nicht anders angegeben):**
- `Domain/Moments.swift` (Typen aus AP0), `Domain/MomentDetector.swift`, `Domain/CoachNote.swift`, `Domain/ShareText.swift`
- `Store/AppModel+Moments.swift`
- `UI/Moments/MomentSheet.swift`, `UI/Moments/CelebrationBackdrop.swift`, `UI/Moments/MomentShareCard.swift`
- Anker-Zeilen in `UI/RootView.swift` (Präsentation), `UI/HistoryView.swift` (`RideDetailView`: Zeile „Gipfelmoment ansehen“), `UI/ChallengesView.swift` (Punkt „neu“) und `UI/ProfileSettings/ProfileSettingsViews.swift` (Schalter)
- `Services/Demo+Moments.swift`
- Tests: `MomentDetectorTests`, `CoachNoteTests`, `ShareTextTests`, `MomentLedgerTests`, UI `AuditMomentsTests`

---

### B2 · Postkarten von der Alpenüberquerung

**User Story:** Als Einsteiger, dem Watt nichts sagen, möchte ich mit jedem Level an einem echten Ort „ankommen“ und eine Postkarte bekommen, damit mein Winter eine Geschichte hat, die ich sammeln und meinen Freunden zeigen kann.

**Auslöser und Moment:**
- Level-Aufstieg: Die Postkarte erscheint im Gipfelmoment (B1).
- Album im Winter-Arc-Hub unter der Winter-Reise: „Deine Postkarten · 4 von 10“. Noch nicht erreichte Karten sind gedimmt, mit „Noch 38 % bis Bormio“ (Goal Gradient).
- Die Erstkarte „Garmisch“ gibt es sofort mit dem Winter-Arc-Start (Endowed Progress: 1 von 10 statt 0).

**Inhalt:** Je Etappe eine Karte mit eigenem Text. Die Fakten sind öffentlich bekannt, die Formulierung ist eigen, der Ton hat ein leichtes Augenzwinkern.

| # | Ort, Höhe | Kartentext |
|---|---|---|
| 1 | Garmisch, 708 m | „Start in Garmisch. Die Zugspitze schaut zu, der Winter fängt gerade erst an. Der erste Tritt ist der schwerste, und der liegt hinter dir.“ |
| 2 | Fernpass, 1216 m | „Grüße vom Fernpass. Unten glitzern die Seen. Du rollst ruhig und gleichmäßig. Genau so gewinnt man einen Winter.“ |
| 3 | Reschen, 1507 m | „Am Reschensee schaut ein Kirchturm aus dem Eis. Hier oben ist es kalt, aber deine Beine sind warm.“ |
| 4 | Stilfser Joch, 2757 m | „48 Kehren, 2757 Meter: das Dach deiner Reise. Ab hier geht es dem Frühling entgegen.“ |
| 5 | Bormio, 1225 m | „Bormio, die Thermen dampfen. Halbzeit. Und ab der Wintersonnenwende werden die Tage wieder länger.“ |
| 6 | Aprica, 1176 m | „Über Aprica blinzelt die Sonne jeden Tag ein bisschen länger hinter den Gipfeln hervor.“ |
| 7 | Edolo, 699 m | „In Edolo tropft es von den Dächern. Tauwetter in den Bergen und in deinen Beinen.“ |
| 8 | Crocedomini, 1892 m | „Der Passo Crocedomini: einsam, steil, ehrlich. Hier zeigt sich, was der Winter gebracht hat.“ |
| 9 | Idrosee, 368 m | „Am Idrosee riecht es schon nach Frühling. Nur noch eine Etappe.“ |
| 10 | Gardasee, 65 m | „Riva am Gardasee. Zitronenbäume, Wasser, Sonne. Du bist angekommen, in Frühlingsform.“ |

**Screen-Skizze (Postkarte, `PostcardView`, Identifier `postcard.view`):**
- **Format:** Querformat 3:2, abgerundete Ecken 20 pt, leichter Schatten, Papierton `canvasLight`.
- **Links (60 %):** eigene Vektor-Illustration in einem `Canvas`:
  - Bergsilhouette aus dem Höhenprofil der Etappe (`WinterJourney.stages`)
  - Schneekappen, deren Menge mit dem Saisonfortschritt abnimmt
  - eine Sonne, die von Etappe zu Etappe höher steht
  - der Himmel aus `WinterSky`
- **Rechts (40 %):**
  - Briefmarke (gezackter Rand, Level-Symbol, „Etappe 4/10“)
  - runder Poststempel mit Ankunftsdatum („18. DEZ. 2026“)
  - Kartentext in `.callout` mit Dynamic Type
  - Unterschrift „Dein Coach“
- **Bei großen Schriftgrößen** (ab `.accessibility1`) wechselt die Karte ins Hochformat: Bild oben, Text unten.
- **Album** (`PostcardAlbumView`, `postcard.album`): Raster mit 2 Spalten, nicht erreichte Karten gedimmt mit Schloss und „Noch 38 % bis Bormio“. Ein Tipp öffnet die Karte groß, mit Wischen zur nächsten.
- **Teilen** (`postcard.share`): Bild 1500×1000, Text „Grüße vom Stilfser Joch. Etappe 4 von 10 meiner Winter-Alpenüberquerung.“ Ohne Werte.

**Animation und Haptik:**
- Beim Öffnen dreht sich die Karte einmal von der Rückseite (Briefmarke) auf die Vorderseite (`rotation3DEffect`, 0,5 s Spring).
- Haptik `.impact(.light)` beim Umblättern.
- Bei „Bewegung reduzieren“: keine Drehung, nur eine Überblendung.

**Barrierefreiheit:**
- Die Illustration ist dekorativ.
- Die Karte ist ein VoiceOver-Element: „Postkarte, Etappe 4 von 10, Stilfser Joch, 2757 Meter, angekommen am 18. Dezember. Text: …“
- Gesperrte Karten: „Noch nicht erreicht, noch 38 Prozent bis Bormio.“

**Datenschutz:** Keine Fotos, keine Ortung, keine Werte auf dem Bild. Das Ankunftsdatum wird aus `Trophies.levelDates` abgeleitet, also gibt es keine neue Speicherung.

**Akzeptanzkriterien:**
1. Auf Level n sind die Karten 1…n freigeschaltet und zeigen ihr Ankunftsdatum, die Karten n+1…10 sind gesperrt mit Prozentangabe bis zur nächsten.
2. Garmisch ist mit Saisonstart immer freigeschaltet.
3. Alle 10 Texte sind ≤ 160 Zeichen lang, in Du-Form und frei von Marken.
4. Die Karte ist bei AX5 vollständig lesbar (Hochformat).
5. Das geteilte Bild ist 1500×1000 px groß und enthält keine Watt-, Puls- oder Dienstnamen.
6. Im Demo-Modus zeigt das Album die Demo-Level korrekt.

**Unit-testbare Logik:**
- `Postcards.all(level:levelProgress:levelDates:) -> [Postcard]`: Freischaltung, Datum, Prozent bis zur nächsten Karte, Garmisch immer frei.
- Texte: Länge, keine Sperrwörter oder Dienstnamen, Du-Form (enthält kein „Sie “).
- `PostcardScene.geometry(stage:seasonProgress:)`: Schnee nimmt monoton ab, die Sonne steigt monoton.
- Render-Test: Größe des Teilen-Bilds.

**UI-Test-Idee** (`AuditWinterWorldTests`): Winter Arc öffnen → `postcard.album` → erste Karte antippen → `postcard.view` sichtbar → wischen → gesperrte Karte nennt den Prozentwert → `postcard.share` vorhanden. Dazu ein Accessibility-Audit.

**Betroffene Dateien:**
- `Domain/Postcards.swift` (Stub aus AP0, füllen)
- `UI/Postcards/PostcardView.swift` (Stub aus AP0, füllen), `UI/Postcards/PostcardScene.swift`, `UI/Postcards/PostcardAlbumView.swift`
- Anker in `UI/WinterArcView.swift` (Album unter der Winter-Reise) und `UI/WinterJourneyCard.swift` (Link „Postkarten“)
- Tests: `PostcardsTests`

---

### B3 · Winterlicht

**User Story:** Als Fahrerin, die an dunklen Abenden auf der Rolle sitzt, möchte ich sehen, dass es draußen jeden Tag heller wird und wie nah der Frühling ist, damit ich mich auf das Ziel freue statt gegen die Dunkelheit anzukämpfen.

**Auslöser und Moment:** Dauerhaft, aber leise:
- **Heute:** eine Zeile in der Winter-Arc-Karte
- **Winter-Arc-Hub:** Kopf mit Himmel
- **Gipfelmoment:** Hintergrund

Ein Sonderzustand gilt am **21. Dezember** (Wintersonnenwende) und zur **Tagundnachtgleiche** am 20. März (zeitliche Marken, Fresh-Start-Effekt).

**Texte (Identifier `winterlight.line`):**
- **Vor dem 21.12.:** „Noch 9 Tage bis zur Wintersonnenwende. Danach wird jeder Tag ein bisschen heller.“
- **Am 21.12.:** „Heute ist Wintersonnenwende, der kürzeste Tag des Jahres. Ab morgen geht’s bergauf.“
- **Danach:** „+34 min Tageslicht seit der Wintersonnenwende“, im Hub zusätzlich „Bis zu deinem Ziel am 21. März: noch 86 Tage. Dann hast du 4 h 10 min mehr Licht als heute.“
- **Ab dem 20.3.:** „Die Tage sind jetzt länger als die Nächte. Frühling!“
- **Fußnote im Hub:** „Berechnet für die Mitte Deutschlands (50° N).“ Bei Zeitzone Wien: „für Österreich“, Zürich: „für die Schweiz“. Ohne Ortung.

**Berechnung:**
- Tageslänge nach Standardformel: Sonnendeklination δ, Stundenwinkel ω₀ mit −0,833° für Refraktion, Tageslänge = 2·ω₀/15 h.
- Breitengrad aus einer kleinen Tabelle je Zeitzone: Berlin 50°, Wien 48°, Zürich 47°, sonst 50°.
- Rein lokal und unit-testbar.

**Lebendiger Himmel (`WinterSky`):**
- Verlauf aus drei Schlüsselbildern in OKLab, interpoliert über den Saisonfortschritt (`levelProgress` gesamt):
  - Winterdämmerung: Indigo `#5152C1` → Koralle
  - Sonnenuntergang: `Theme.sunset`
  - Frühlingsmorgen: Mango `#FFC247` → Pfirsich `#FFB38A`
- Im Hub-Kopf fallen im `Canvas` höchstens 40 Schneeflocken, Dichte = 1 − Fortschritt (bei Level 10 keine mehr).
- `TimelineView` mit 30 fps nur, solange der Kopf sichtbar ist und weder „Bewegung reduzieren“ noch Stromsparmodus aktiv ist. Sonst stehen die Flocken still.

**Screen-Skizze:**
- **Heute:** In der Winter-Arc-Karte unter der Level-Zeile ein Chip mit `sun.horizon` und „+34 min Licht“ (Tinte auf `Theme.softFill`). Mit Tipp in den Hub.
- **Winter-Arc-Hub, Kopf (180 pt):**
  - Himmel mit Flocken, unten eine stilisierte Horizontlinie und die Sonne, deren Höhe dem Tageslicht-Gewinn entspricht
  - darunter auf Kartenweiß: „+34 min Tageslicht seit der Wintersonnenwende“
  - kleines Diagramm „Tageslicht 1.11. bis Ziel“ (Linie, heute als `HighlightPoint`, Konzept 21)
  - die Fußnote
- **Am 21.12.** zeigt der Kopf einmalig ein sanftes Aufleuchten der Sonne (Opazität, 1 s). Ohne Bewegung: statisch heller.

**Barrierefreiheit:**
- Der Himmel ist dekorativ.
- Die Zeile ist Text, die Minuten werden von VoiceOver als „34 Minuten“ gelesen.
- Das Diagramm hat ein Audio Graph (vorhandenes Muster `ChartAccessibility`).

**Datenschutz:** Keine Ortung und keine Berechtigung. Die Zeitzone ist bereits im System bekannt.

**Akzeptanzkriterien:**
1. Die Tageslänge bei 50° N am 21.12. liegt zwischen 7 h 55 min und 8 h 10 min, am 20.3. zwischen 12 h 0 min und 12 h 20 min.
2. Der Gewinn seit der Sonnenwende steigt vom 22.12. bis 20.6. streng monoton.
3. Vor, am und nach dem 21.12. sowie ab dem 20.3. erscheint jeweils der passende Text, in jeder Zeitzone korrekt (Tageswechsel in der lokalen Zone).
4. Bei „Bewegung reduzieren“ und im Stromsparmodus gibt es keine laufende Animation.
5. Der Text erfüllt überall ≥ 4,5:1 Kontrast (er steht nie auf dem Himmel).
6. Es gibt keine Abhängigkeit von Verbindungen, Daten oder Claude. Ohne Winter Arc (vor dem 1.11.) erscheint nur die Zeile im Hub, nicht auf Heute.

**Unit-testbare Logik:**
- `Daylight.length(on:latitude:calendar:)`, `Daylight.gainSinceSolstice(now:latitude:)`, `Daylight.phase(now:)` (`.beforeSolstice(days)`, `.solstice`, `.lengthening(gain)`, `.afterEquinox`)
- `Daylight.latitude(for: TimeZone)`
- `WinterSky.stops(progress:)`: Endpunkte exakt, Helligkeit (L in OKLab) steigt monoton
- `WinterSky.snowDensity(progress:)`

**UI-Test-Idee:** `-uiToday 2027-01-10`: Heute zeigt `winterlight.line` mit „+“ und „min“. `-uiToday 2026-12-21`: Text „Wintersonnenwende“. Hub-Kopf vorhanden, Audit grün (AX5, Dark).

**Betroffene Dateien:**
- `Domain/Daylight.swift`, `Domain/WinterSky.swift`
- `UI/WinterArc/WinterlightHeader.swift`, `UI/WinterArc/SnowfallCanvas.swift`
- Anker in `UI/WinterArcView.swift` (Kopf im Hub, Chip in `WinterArcCard`)
- Tests: `DaylightTests`, `WinterSkyTests`

---

### B4 · Willkommen zurück & Dein Warum

**User Story:** Als Fahrer, der nach Krankheit, Weihnachten oder Skiurlaub zwei Wochen nicht gefahren ist, möchte ich beim Öffnen der App freundlich empfangen werden, an meinen eigenen Grund erinnert werden und mit einem Tipp locker einsteigen können, statt rote Zahlen und eine gerissene Serie zu sehen.

**Teil 1 · Dein Warum** (Karte im Winter-Arc-Hub, Identifier `why.card`):
- **Frage:** „Warum fährst du diesen Winter?“ Ein Textfeld (`why.field`) mit höchstens 140 Zeichen.
- **Vorschlags-Chips:** „Im Frühling mit meiner Gruppe mithalten“, „Fit durch den Winter, ohne Stress“, „Ein Ziel: ______“, „Rad und Studio kombinieren“.
- Optional, jederzeit änderbar. Der Hinweis „Bleibt auf deinem iPhone. Geht nicht an Claude.“
- **Einstieg:** Nach der ersten Fahrt der Saison zeigt der Highlight-Slot auf Heute einmalig „Magst du deinem Winter einen Satz geben?“ (wegtippbar). Es gibt keinen Eingriff in die Einführung.
- **Wiederkehr des Satzes** (der Kern des Wow): Die App zitiert ihn wörtlich.
  - in der Willkommen-zurück-Karte
  - im Gipfelmoment bei Level 5 (Halbzeit) und Level 10
  - auf der Postkarte Gardasee als Zusatz „Dein Satz vom 4. November: …“
  - Brief an dein Frühlings-Ich (L7) als Teil davon

**Teil 2 · Willkommen zurück** (Highlight-Slot auf Heute mit höchster Priorität, Identifier `comeback.card`):

**Bedingung:** letzte Aktivität (Rad, Kraft, andere Einheit, Fremdsport aus Health) ≥ 10 Tage her **und** Winter Arc aktiv. Die Karte verschwindet, sobald eine neue Aktivität da ist. Dann übernimmt der Comeback-Moment aus B1.

**Skizze:**
- **Titel:** „Schön, dass du wieder da bist“ (Symbol `sunrise`)
- **Text:**
  - „12 Tage Pause. Das gehört zum Winter dazu.“
  - Wenn ein Joker gegriffen hat: „Dein Joker hat die Woche ab 22. Dez. aufgefangen, deine Serie steht.“
  - sonst: „Deine nächste Serie beginnt mit der nächsten Einheit.“
- **Wenn ein Warum gesetzt ist:** ein Zitatblock „Du hast geschrieben: ‚Im Mai die RTF mit Freunden.‘“
- **Hauptknopf** „Heute locker einsteigen“ (`comeback.start`):
  - Mit einer geplanten Einheit heute oder morgen öffnet er „Einheit anpassen“, vorausgewählt auf 30 min und 10 % leichter (vorhandenes `WorkoutAdjust`).
  - Ist die Einheit hart, wird stattdessen der vorhandene Tausch gegen Grundlage angeboten (`WorkoutSwap`).
  - Ohne Plan öffnet er die Detailansicht „Grundlage 30 min“ aus dem Katalog mit Senden und Export wie gewohnt.
- **Zweitknopf** „Später“: blendet die Karte für heute aus.
- **Hinweis klein:** „Die ersten zwei Einheiten dürfen ruhig locker sein.“
- **Zeitliche Marken:** Fällt die Rückkehr auf einen Montag, den 1. eines Monats oder den 1. Januar, ergänzt die Karte „Neue Woche, neuer Anfang.“, „Neuer Monat, neues Kapitel.“ bzw. „Neues Jahr. Dein Frühling kommt trotzdem pünktlich.“

**Tonregeln:**
- nie „verpasst“, „gesunken“, „verloren“ oder „Rückstand“
- keine Formkurve auf der Karte
- die Formkarte auf Heute bleibt unverändert, steht aber unter der Willkommen-Karte

**Animation und Haptik:**
- Die Karte erscheint mit einer sanften Überblendung, das Symbol `sunrise` steigt einmal leicht nach oben (`symbolEffect(.bounce)`, nur ohne „Bewegung reduzieren“).
- Keine Haptik (ruhiger Moment).

**Barrierefreiheit:**
- Die Karte ist ein `contain`-Element.
- Das Zitat wird als „Zitat: …“ vorgelesen.
- Die Knöpfe sind ≥ 44 pt groß. Bei AX5 werden die Knöpfe untereinander gesetzt.

**Datenschutz:**
- „Dein Warum“ liegt in `UserDefaults` (`why.note`) und wird von „Alle Daten löschen“ erfasst.
- Es ist **nicht** Teil von `PlanPrompt` (Test) und nicht im Diagnose-Export (Test).

**Akzeptanzkriterien:**
1. Bei letzter Aktivität vor ≥ 10 Tagen erscheint die Karte im Highlight-Slot vor Wochenrückblick und Challenge. Bei 9 Tagen erscheint sie nicht.
2. Nach einer neuen Aktivität ist die Karte weg, und der Gipfelmoment (B1) zeigt „Du bist zurück“.
3. Mit gesetztem Warum steht es wörtlich in der Karte, im Gipfelmoment bei Level 5 und 10 und auf der Postkarte Gardasee.
4. „Heute locker einsteigen“ führt in allen drei Fällen (geplant leicht, geplant hart, kein Plan) zu einer startbaren Einheit, ohne Claude.
5. Kein Text enthält die Wörter aus der Sperrliste.
6. Das Warum taucht weder im Claude-Prompt noch im Diagnose-Export auf.
7. Montag, Monatserster und Neujahr ergänzen den passenden Satz.

**Unit-testbare Logik:**
- `Comeback.state(lastActivity:now:calendar:) -> .none | .returning(days:landmark:)`: Grenze 10 Tage, Zeitzonen, Landmarken Montag, Monatserster, 1.1.
- `Comeback.texts(state:jokerWeek:why:)`: Sperrliste, Joker-Satz.
- `Comeback.startAction(planned:)`: Fall leicht → adjust, Fall hart → swap, kein Plan → Katalog.
- `WhyNote`: Kürzung auf 140, Trimmen, Leerstring = nil.
- `PlanPrompt`/Diagnose enthalten kein `why.note` (Regressionstest).

**UI-Test-Idee:**
- `-uiToday 2027-01-05 -uiSeed lastRide=2026-12-22`: `comeback.card` sichtbar, Text „Neues Jahr“, `comeback.start` öffnet „Einheit anpassen“ mit 30 min.
- `why.field` füllen → zurück → Zitat in der Karte.

**Betroffene Dateien:**
- `Domain/Comeback.swift`, `Domain/WhyNote.swift`
- `Store/AppModel+Comeback.swift`
- `UI/WinterArc/WhyCard.swift`, `UI/ComebackCard.swift`
- Anker in `UI/TodayView.swift` (Highlight-Slot, vor `ANCHOR-K2-HEUTE`) und `UI/WinterArcView.swift` (WhyCard)
- Tests: `ComebackTests`, `WhyNoteTests`

---

## 5. Arbeitspakete (ECC, Tests zuerst)

**Vorgehen:** `ecc:orch-add-feature` je Paket. Jedes Paket beginnt mit roten Unit-Tests (`ecc:tdd-workflow`) und endet mit `swift test` grün, `ecc:orch-review` und dem UI-Audit des Pakets.

**Parallelisierung:**
- Zwei Agents arbeiten auf getrennten Worktrees.
- **Agent A „Momente“** (B1) und **Agent B „Winterwelt“** (B2, B3, B4) ändern keine gemeinsamen Dateien.
- Die Hauptsession legt vorher die Verträge an (AP0) und führt am Ende zusammen (AP7).

```
AP0 (Hauptsession) ──┬── Agent A: AP1 → AP2 → AP3 → AP-A-UI ──┐
                     └── Agent B: AP4 → AP5 → AP6 → AP-B-UI ──┴── AP7 (Hauptsession)
```

### AP0 · Verträge und gemeinsame Bausteine (Hauptsession, S, ½ Tag)

1. `Domain/Moments.swift`: `Moment`, `Moment.Kind` (alle Arten aus B1), `priority`, `id`, `MomentBatch`, `MomentLedger` (Codable), **nur Typen und Ledger mit Tests**.
2. `Domain/Postcards.swift`: `Postcard` (stage, place, elevation, text, unlocked, arrivedOn, percentToNext) und Signatur `Postcards.all(level:levelProgress:levelDates:)` mit Platzhaltertexten. `UI/Postcards/PostcardView.swift` als Stub mit fester Signatur `PostcardView(postcard:style:)` mit `style: .compact | .full`.
3. `Domain/WinterSky.swift`: Signatur `WinterSky.stops(progress:) -> [RGB]`, zunächst mit linearem Platzhalter. Wird von A (Gipfelmoment-Hintergrund) und B genutzt, B füllt die Logik.
4. `UI/Share/ShareImageRenderer.swift`: generischer Renderer (`render<V: View>(_:size:filename:)`), aus `SeasonShareRenderer` herausgelöst. Regressionstest: Saisonbild weiter 1080×1350.
5. `CelebrationMotion` (2 Kurven, Reduce-Motion-Helfer) in `UI/Share/CelebrationMotion.swift`.
6. `AppModel`:
   - Debug-Override `-uiToday yyyy-MM-dd` als `AppModel.today` (nur DEBUG, nur von den neuen Funktionen gelesen)
   - Eigenschaften `pendingMoments` (A füllt) und `whyNote` (B füllt)
   - Schlüssel `moments.ledger`, `moments.enabled`, `why.note` in `deleteAllData` und `uiFlagKeys`
7. Anker setzen:
   - `ANCHOR-B1-ROOT` (RootView), `ANCHOR-B1-RIDE` (RideDetailView), `ANCHOR-B1-TROPHY` (ChallengesView), `ANCHOR-B1-SETTING` (ProfileSettingsViews)
   - `ANCHOR-B3-CARD`, `ANCHOR-B3-HUB`, `ANCHOR-B2-ALBUM`, `ANCHOR-B4-WHY` (WinterArcView)
   - `ANCHOR-B4-HEUTE` (TodayView), `ANCHOR-B2-JOURNEY` (WinterJourneyCard)
8. Identifier-Vertrag (§4) in `IndoorCoachUITests/AuditSupport.swift` als Konstanten.

### Agent A · Momente (B1)

| AP | Inhalt | Tests zuerst | Größe |
|---|---|---|---|
| AP1 | `MomentDetector` (Frische, Erstauswertung, Deduplizierung, Priorität, Obergrenze, Level = Etappe, eFTP-Sprung, Woche geschafft, Comeback-Erkennung, Saison-IDs, Demo) | `MomentDetectorTests` (≥ 20 Fälle inkl. Erstimport 210 Tage, Neustart, Zeitzone) | M |
| AP2 | `CoachNote` (7 Regeln, Abwechslung, Tonregeln, Quellen), `ShareText.neutral` | `CoachNoteTests`, `ShareTextTests` (Sperrliste, Dienstnamen) | S–M |
| AP3 | `AppModel+Moments` (Auswertung bei aktiv/Import, Sperren während Aufzeichnung/Einführung/Blatt, Schalter), `MomentSheet`, `CelebrationBackdrop` (Canvas-Partikel), `MomentShareCard` (1080×1920), Zeilen an `ANCHOR-B1-*`, `Demo+Moments` | Store-Tests mit In-Memory-Container: ein Gipfelmoment nach Import, keiner im zweiten Durchlauf, keiner bei Aufzeichnung; Render-Größe | M |
| AP-A-UI | `AuditMomentsTests`: `-uiMoment levelUp|record|comeback|week`, Schließen, Teilen vorhanden, kein zweites Mal, Matrix SE/AX5/Dark, Audit | – | S |

**Dateien exklusiv Agent A:**
- `Domain/MomentDetector.swift`, `Domain/CoachNote.swift`, `Domain/ShareText.swift`
- `Store/AppModel+Moments.swift`, `UI/Moments/*`, `Services/Demo+Moments.swift`
- Zeilen an den Ankern in `RootView`, `HistoryView`, `ChallengesView`, `ProfileSettingsViews`
- Tests wie oben

**Liest nur:** `Moments.swift`, `Postcards.swift`/`PostcardView` (Stub, später echt), `WinterSky`, `whyNote`.

### Agent B · Winterwelt (B2, B3, B4)

| AP | Inhalt | Tests zuerst | Größe |
|---|---|---|---|
| AP4 | `Postcards` mit Texten, `PostcardScene` (Canvas), `PostcardView` (kompakt/voll, Drehung, AX-Hochformat), `PostcardAlbumView`, Teilen 1500×1000, Anker `ANCHOR-B2-*` | `PostcardsTests` (Freischaltung, Datum, Prozent, Texte, Geometrie monoton, Bildgröße) | M |
| AP5 | `Daylight`, `WinterSky` (füllen), `WinterlightHeader`, `SnowfallCanvas`, Chip in `WinterArcCard`, Anker `ANCHOR-B3-*` | `DaylightTests` (Referenzwerte, Monotonie, Phasen, Zeitzonen), `WinterSkyTests` | S–M |
| AP6 | `WhyNote`, `WhyCard`, `Comeback`, `ComebackCard`, `AppModel+Comeback` (letzte Aktivität quellenübergreifend, Startaktion über vorhandenes Adjust/Swap), Highlight-Slot-Zeile, Erstfahrt-Hinweis „Magst du deinem Winter einen Satz geben?“ | `ComebackTests`, `WhyNoteTests`, Regression: `PlanPrompt` und Diagnose ohne `why.note` | S–M |
| AP-B-UI | `AuditWinterWorldTests`: Album, Postkarte, Winterlicht mit `-uiToday` (3 Daten), Comeback-Pfad, Warum eingeben, Matrix, Audit | – | S |

**Dateien exklusiv Agent B:**
- `Domain/Postcards.swift`, `Domain/Daylight.swift`, `Domain/WinterSky.swift`, `Domain/Comeback.swift`, `Domain/WhyNote.swift`
- `Store/AppModel+Comeback.swift`
- `UI/Postcards/*`, `UI/WinterArc/*`, `UI/ComebackCard.swift`
- Zeilen an den Ankern in `WinterArcView`, `WinterJourneyCard`, `TodayView`
- `Services/Demo+Winter.swift` (falls nötig)
- Tests wie oben

**Abhängigkeiten zwischen A und B:**
- Nur über die AP0-Signaturen: `PostcardView(postcard:style:)`, `WinterSky.stops(progress:)`, `AppModel.whyNote`.
- A testet gegen Stubs. Nach dem Merge von B zeigt der Gipfelmoment automatisch die echte Postkarte und den echten Himmel.
- Keine Datei wird von beiden geändert. Konflikte sind nur an den vorab gesetzten Ankern möglich, und die liegen in verschiedenen Dateien.

### AP7 · Abschluss (Hauptsession, S–M, ½ Tag)

- B mergen, dann A mergen.
- Integration prüfen: Gipfelmoment Level 5 zeigt Postkarte Bormio, Himmel und Warum-Zitat.
- Volle Unit- und UI-Suite, Matrix auf iPhone SE und 402 pt, hell/dunkel, AX5.
- `performAccessibilityAudit`, Start-Performance-Test (Gipfelmoment-Auswertung < 20 ms bei 300 Fahrten).
- Screenshots `docs/screenshots/22-*`, Abschnitt in `README.md`, Zeile in `docs/04-STATUS.md`, `ecc:orch-review` über das Gesamtpaket.

**Definition of Done (Paket):**
- alle Akzeptanzkriterien aus §4 erfüllt
- neue Unit-Tests grün
- keine Regression in den vorhandenen Unit- und 66 UI-Tests
- Audit ohne neue Befunde
- Demo-Modus, Flugmodus und ohne Claude-Key manuell geprüft

---

## 6. Risiken

| # | Risiko | Gegenmaßnahme |
|---|---|---|
| R1 | **Feier-Inflation:** zu viele Momente, Abstumpfung | Obergrenze ein Gipfelmoment pro Auswertung, Erstauswertung still, Priorität, Schalter. `weekPlanDone` höchstens 1× pro Woche. |
| R2 | **Kitsch oder Ton daneben** (Strava-Effekt „hohl“) | Kontextregeln (Check-in, Comeback), Sperrliste als Test, keine Superlative ohne Beleg, Quelle an jedem Satz |
| R3 | **Falsche Bestleistung** durch Mindestwerte ohne Sekundendaten | Die Quelle steht dabei („Mindestwert“). Rekord-Momente nur aus Fahrten mit `powerCurve` (wie die heutigen Trophäen). |
| R4 | **Performance:** `Canvas`-Partikel und Schnee | Partikel nur 1,2 s, Schnee nur im sichtbaren Hub-Kopf, keine Animation bei Reduce Motion oder Stromsparmodus. Messung in AP7. |
| R5 | **Unterbrechung** des eigentlichen Ziels (App öffnen → Einheit senden) | Vollbild nur nach neuer Aktivität und nie vor einer geplanten Einheit innerhalb von 30 min (Erinnerung). Schließen mit einem Tipp oder Wischen. |
| R6 | **Tageslicht ungenau** für Nutzer weit im Norden oder Süden | ehrliche Fußnote mit Breitengrad, Werte gerundet auf Minuten. Später optional eine Region wählbar (§7 E3). |
| R7 | **Markenrecht/App Store** | eigene Illustrationen, keine Fotos, keine fremden Figuren, Dienstnamen auf Bildern entfernt (Test). Keine Gesundheitsversprechen (Sperrliste). |

---

## 7. Entscheidungen für den Produktinhaber

| # | Frage | Empfehlung |
|---|---|---|
| E1 | Shortlist B1–B4 so freigeben (etwa 5 Entwicklertage, 2 Agents)? | ja |
| E2 | „Feiern nach der Fahrt“ standardmäßig **an**? | ja (abschaltbar) |
| E3 | Breitengrad für Winterlicht: feste Näherung je Zeitzone (ohne Ortung) oder zusätzlich Region wählbar? | zunächst Näherung, Region später |
| E4 | Werte (Watt/Puls) auf Teilen-Bildern standardmäßig **aus**? | ja |
| E5 | Welle 2: Adventsweg (L8, zeitkritisch bis 1.12.), Winter-Story (L9), „Fahr mit mir“ (L17), optionaler Claude-Satz (L20)? | L9 + L17 für Januar. L8 nur, wenn B1–B4 vor dem 28.11. fertig sind. |

---

## Zusammenfassung

**Marktanalyse** (Recherche 21.11.2026, 15 Apps mit 18 Merkmalen und 2 Forschungsbefunde):
- Begeisterung entsteht im **Moment nach der Leistung** (Zwift Progress Report, aber mit 15-s-Zeitlimit), durch **Reisen über echte Orte** (Rouvy), durch einen **ehrlichen Langzeitvergleich mit dir selbst** und durch **Nachsicht bei Pausen** (Duolingo Streak Freeze, Ringe pausieren).
- Sie stirbt an KI-Floskeln ohne Kontext (Studie zu Strava Athlete Intelligence), an Paywalls vor dem eigenen Rückblick (Strava, Garmin) und an Shops oder Währungen.
- **IndoorCoach berechnet Level, Etappen, Trophäen und Bestleistungen bereits, überreicht sie aber nie.**

**Shortlist „Vom Frost zum Frühling“** (alles lokal, ohne Verbindung, Demo-fähig, ohne Claude-Key):

| # | Element | Inhalt |
|---|---|---|
| B1 | **Gipfelmoment nach der Fahrt** | Moment-Erkennung (Level/Etappe, Bestleistung, eFTP-Sprung, Challenge, Serie, Plan der Woche, Comeback), Vollbild-Feier mit Haptik und kurzem Schnee-zu-Funken-Effekt, regelbasierte **Coach-Notiz** mit Quelle und Kontext, Teilen 9:16 ohne fremde Marken |
| B2 | **Postkarten von der Alpenüberquerung** | 10 eigene illustrierte Karten mit Text, Album mit „Noch 38 % bis Bormio“, Teilen 3:2 |
| B3 | **Winterlicht** | „+34 min Tageslicht seit der Wintersonnenwende“, Countdown zum Ziel, Himmel und Schnee im Winter Arc folgen dem Fortschritt |
| B4 | **Willkommen zurück & Dein Warum** | nach ≥ 10 Tagen Pause freundliche Karte ohne Urteil, „Heute locker einsteigen“ über vorhandenes Anpassen/Tauschen, dein eigener Satz kehrt in Comeback, Level 5/10 und Gardasee-Postkarte zurück |

**Durchgängig:**
- „Bewegung reduzieren“ und Stromsparmodus werden respektiert.
- VoiceOver-Fokus auf der Überschrift, AX5-tauglich.
- Nichts verlässt das Gerät ohne Zutun, „Dein Warum“ geht nie an Claude.
- Schalter „Feiern nach der Fahrt“.

**Arbeitspakete** (ECC, Tests zuerst, etwa 5 Entwicklertage, etwa 3 Kalendertage mit 2 Agents):
- **AP0** Hauptsession: Typen, Stubs `PostcardView`/`WinterSky`, generischer Share-Renderer, `-uiToday`, Lösch-Schlüssel, Anker
- **Agent A „Momente“:** AP1 `MomentDetector` → AP2 `CoachNote` + `ShareText` → AP3 Gipfelmoment-UI → UI-Tests
- **Agent B „Winterwelt“:** AP4 Postkarten → AP5 Winterlicht → AP6 Comeback + Warum → UI-Tests
- Keine gemeinsamen Dateien, Kopplung nur über AP0-Signaturen.
- **AP7** Hauptsession: Merge, Integration, Matrix, Audit, Screenshots, README/Status

**Offene Entscheidungen:** E1–E5 (§7).

### Entschieden (21.11.2026)

- E1: Shortlist B1–B4 freigegeben. E2: Feiern standardmäßig an (abschaltbar). E3: Breitengrad als Näherung je Zeitzone, keine Ortung. E4: Werte auf Teilen-Bildern standardmäßig aus. E5: Welle 2 (Adventsweg) vorerst nicht.
