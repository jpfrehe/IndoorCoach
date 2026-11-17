# Pilot-Testplan (B12)

Stand 17.11.2026 · gilt für den ersten TestFlight-Build (v0.1).
**Ziel**: 3–5 Fahrer nutzen IndoorCoach vier Wochen lang im echten Trainingsalltag. Wir wollen wissen, ob der Kern-Thread „Woche planen → Kalender → in MyWhoosh fahren“ ohne Hilfe funktioniert, und alles finden, was im Simulator nicht prüfbar war (Strava-OAuth, Claude live, Kalender, AirDrop, echte Geräte).

Verwandte Dokumente: [Installation](03-INSTALLATION.md) · [Backlog Pilot](06-BACKLOG-PILOT.md) · [UX-Audit](ux-audit-2026-11-17.md) · [Winter Arc](05-FEATURES-WINTER-ARC.md)

## 1. Gerätematrix

Jede Zeile braucht mindestens einen Pilot-Fahrer. Die Einstellung bleibt die ganzen vier Wochen aktiv (Dynamic Type und Dunkelmodus nicht nur kurz ausprobieren).

| # | Gerät (Breite) | iOS | Schriftgröße | Darstellung | Warum |
|---|---|---|---|---|---|
| G1 | iPhone SE 2./3. Gen. oder 12/13 mini (**375 pt**) | 18.x | Standard (L) | hell | kleinster Viewport. Hier sind die 7 offenen Kontrast-Knoten aufgetreten (B13). |
| G2 | iPhone SE / mini (**375 pt**) | 18.x | **Dynamic Type „Größer“ (AX-L)** | hell | Layout-Collapse-Risiko (F07): Zahlen, Plan-Zeilen, Planer-Button über der Tastatur |
| G3 | iPhone 15/16/17 (393–402 pt) | aktuelle | Standard | **dunkel** | Sunset-Jelly-Dunkelpalette, Diagramme, Badges |
| G4 | iPhone Pro Max / Plus (430–440 pt) | aktuelle | Standard | hell, automatisch | große Breite, Charts, Wochen-Ansicht |
| G5 | beliebig, **ohne Strava-Abo / ohne Claude-Key** | 18.x | Standard | beliebig | Demo-Modus und Erststart-Erlebnis (Onboarding B01) |

Für jedes Gerät notieren: Modell, iOS-Version, Schriftgröße, Hell/Dunkel. All das steht auch im Diagnose-Export (Profil → Hilfe & Feedback).

## 2. Einrichtung (einmalig, ca. 25 min)

1. **TestFlight**: Einladung per Mail annehmen → TestFlight-App installieren → IndoorCoach installieren. Voraussetzung: B07 (Apple Developer Program, App Store Connect, Tester eingeladen).
2. **Erster Start**: Onboarding durchlaufen (FTP, Trainingstage, Wochenbudget), dann zuerst „Erst mit Demo-Daten ansehen“ wählen und die App 5 Minuten erkunden.
3. **Strava-API-App** (nach [Installation §2](03-INSTALLATION.md#2-strava-verbinden)): auf strava.com/settings/api eine App anlegen, Callback-Domain `localhost`, dann Client-ID und Client-Secret im Profil eintragen und **Mit Strava verbinden** tippen. Hinweis: Neue Standard-API-Apps setzen seit Juni 2026 ein Strava-Abo voraus.
4. **Claude-Key** (nach [Installation §3](03-INSTALLATION.md#3-claude-verbinden)): In der Anthropic Console einen Key anlegen und Billing einrichten. Dann Profil → Coach · Claude → Key einfügen. Modell zunächst *Sonnet 5.5*, für den Vergleich in Woche 3 *Opus 5.5*.
5. **Kalender**: Beim ersten „Übernehmen & in Kalender“ den Vollzugriff erlauben.
6. **MyWhoosh**: im Profil mit dem MyWhoosh-Konto anmelden (Upload, Kalender, Fahrten-Import). Nur für den Rückfallweg `.zwo`: am Mac unter workout.mywhoosh.com anmelden.
7. **Profil prüfen**: Ruhe- und Max-HF eintragen (für Relative Effort), Saisonstart des Winter Arc kontrollieren.

## 3. Test-Szenarien (die 5 Threads aus dem UX-Audit)

Jedes Szenario einmal in Woche 1 bewusst durchspielen, danach im Alltag. Abweichungen sofort per **Feedback senden** melden, mit Diagnose-Export im Anhang.

| # | Thread | Schritte | Erwartetes Ergebnis |
|---|---|---|---|
| T1 | **Heute → Einheit** | App morgens öffnen → Karte „Heute“ → Einheit antippen | Heute zeigt die geplante Einheit mit Dauer, TSS und Leistungsprofil. Das Detail öffnet sich mit einem Tap, Wattangaben passen zur FTP. Ohne Plan steht ein klarer „Plan erstellen“-CTA da, der direkt den Planer öffnet (F02). |
| T2 | **Woche planen** | Plan → **Planen** → 7 Tage → Wunsch tippen („Mittwoch nur 45 min“) → **Mit Claude planen** → Vorschlag prüfen → **Übernehmen & in Kalender** | Der Button bleibt bei offener Tastatur sichtbar (F01). Nach ≤ 60 s kommt ein Vorschlag mit Begründung je Einheit, der den Wunsch berücksichtigt und nur markierte Trainingstage nutzt. Nach der Übernahme stehen die Einheiten in Plan und Kalender „Indoor Training“, jeweils zur Startzeit aus dem Profil. |
| T3 | **Einheit → MyWhoosh** | Einheit öffnen → **An MyWhoosh senden** (oder automatisch beim Übernehmen) → in MyWhoosh unter „Custom Workouts“/Kalender fahren | Die `.zwo` lässt sich ohne Fehlermeldung importieren. Intervalle und Wattwerte stimmen mit der App überein, ERG-Modus funktioniert. Wenn B21 ausgeliefert ist, zusätzlich den Direktupload testen (siehe §6). |
| T4 | **Rückblick** | Nach der Fahrt: App öffnen (oder Pull-to-Refresh) → Verlauf → Fahrt öffnen → Metrik-Umschalter „Stunden \| TSS“ | Die Fahrt erscheint nach dem Strava-Upload innerhalb von 1 min nach dem Sync. Die geplante Einheit desselben Tags ist als erledigt markiert. Der Umschalter reagiert beim **ersten** Tap (F08, siehe §5). Der Wochenumfang stimmt mit Strava überein (± Rundung). |
| T5 | **Profil einrichten / ändern** | FTP +5 W, Trainingstag ändern, Wochenbudget ändern → neu planen | Werte überleben einen App-Neustart. Der nächste Plan nutzt die neue FTP und die neuen Tage. Beim Wechsel aus dem Profil erscheint kein Dialog „Passwort sichern?“ (F15). |

## 4. Winter Arc, Relative Effort, Fitness & Freshness

| # | Prüfung | Erwartet |
|---|---|---|
| W1 | **Winter-Arc-Karte** auf Heute → Detail | Das Level (1 von 10, „Erster Frost“ … „Frühlingsform“) passt zum Fortschritt Start-CTL → Ziel-CTL. Das Level steigt nie ab, auch nach einer Ruhewoche nicht. Der Kursstatus (vor / auf / hinter Kurs, ± 3 CTL) wirkt plausibel. |
| W2 | **Serie** | Eine Woche mit ≥ 80 % des Wochenbudgets erhöht die Serie um 1, eine schwächere Woche setzt sie zurück. Kontrolle immer montags. |
| W3 | **Ziel-Tag / Ziel-Fitness** im Profil ändern | Detail und Kurslinie aktualisieren sich sofort. Ein Zieldatum, das mehr als 8 Monate nach dem Start liegt, wird durch den 21. März ersetzt. |
| R1 | **Relative Effort** einer Fahrt mit HF | Der Wert liegt in derselben Größenordnung wie bei Strava (1 h locker ≈ 60, 1 h Schwelle ≈ 150). Liefert Strava `suffer_score`, wird dieser Wert angezeigt. Die Abweichung zu Strava notieren. |
| R2 | **Perceived Exertion** bei einer Fahrt ohne HF setzen | Der Wert bleibt nach dem nächsten Strava-Sync erhalten. „PE bevorzugen“ wirkt sich auf den RE-Wert aus. |
| R3 | **Wochenkarte RE** im Verlauf | Die Wochensumme steht zusammen mit dem Bereich aus dem 3-Wochen-Schnitt da. „Unter / im / über dem Bereich“ passt zum Gefühl. |
| F1 | **Fitness & Freshness** (Form-Karte antippen) | Zeitraumwähler, Werte per Tap auf einen Tag, 7-Tage-Delta. Der Kurvenverlauf ähnelt dem in Strava (absolute Werte dürfen abweichen). |
| F2 | Fahrt **ohne Leistungsmesser** (Outdoor) | Sie fließt über RE bzw. HF-TSS in die Fitness ein und verschwindet nicht. |

## 5. Offene Punkte aus dem UX-Audit (auf echtem Gerät prüfen)

| # | Punkt | Vorgehen | Abnahme |
|---|---|---|---|
| A1 | **7 nicht zuordenbare Kontrast-Knoten auf 375 pt** (Verlauf 3, Profil 2, Plan bei AX-L 2), siehe B13 | Auf G1/G2: Xcode → Open Developer Tool → Accessibility Inspector → Gerät wählen → Audit für Verlauf, Profil und Plan (AX-L). Knoten antippen, Screenshot und Element notieren. | Jeder Knoten ist einem View zugeordnet. Danach: Fix oder begründete Ausnahme. Das Gate 375 pt wird grün. |
| A2 | **F08 First-Tap**: In der langen UI-Test-Sequenz griff der erste Tap auf den Umschalter „Stunden \| TSS“ nicht | Auf G1 und G3 10× hintereinander zwischen Stunden und TSS wechseln, dazwischen scrollen und eine Fahrt öffnen. | 10 von 10 Taps greifen beim ersten Mal. Sonst Bildschirmaufnahme + Diagnose senden. |
| A3 | **VoiceOver** (B14) | Die 5 Threads T1–T5 mit VoiceOver auf G3 durchgehen. | Jedes Element hat ein Label, Charts sind ein Element mit Kurzbeschreibung (F03), kein Thread hängt fest. |
| A4 | **Performance** (B15) | Kaltstart messen (Stoppuhr, 3×). Verlauf mit allen Fahrten 10× schnell scrollen. | Kaltstart unter der Audit-Schwelle von 4 s (Simulator-Debug: 3,5 s), kein sichtbares Ruckeln. |

## 6. Live-Checks aus dem Backlog

### B08 – Strava-OAuth & Sync auf dem iPhone

- [ ] **Mit Strava verbinden** öffnet die Strava-Anmeldung. Nach „Autorisieren“ kehrt die App über `indoorcoach://localhost/strava` zurück. Ein Banner „Mit Strava verbunden als …“ erscheint.
- [ ] Verweigern („Abbrechen“ im Strava-Dialog) führt zur Meldung „Strava-Anmeldung abgebrochen oder verweigert.“, ohne Absturz.
- [ ] Ohne Häkchen bei „Alle Aktivitäten anzeigen“ erscheint der Hinweis auf den fehlenden Scope.
- [ ] Der erste Sync lädt **210 Tage**. Die Anzahl der Fahrten stimmt mit dem Strava-Profil überein (nur Rad-Aktivitäten).
- [ ] Die Demo-Daten sind nach dem Verbinden weg, eigene Fahrten bleiben erhalten (B10).
- [ ] **Token-Refresh**: Die App > 6 h nicht öffnen, dann öffnen. Der Sync läuft ohne erneute Anmeldung. Im Diagnose-Export steht „Access-Token läuft ab – wird erneuert“.
- [ ] Inkrementeller Sync bei jedem App-Start und per Pull-to-Refresh. Eine nachträglich in Strava geänderte Fahrt (Name, Typ) wird aktualisiert.
- [ ] **Rate-Limit** (B04): Nach vielen schnellen Refreshes erscheint die verständliche Meldung, ohne Datenverlust.
- [ ] **Strava trennen** entfernt die Fahrten, Demo-Daten erscheinen wieder.

### B09 – Claude-Planung live

- [ ] Ein Key mit < 20 Zeichen lässt sich nicht speichern. Ein ungültiger Key führt zu „Der Claude-API-Key wurde abgelehnt.“
- [ ] Der erste echte Plan kommt an (Dauer notieren: ______ s). Bei „Claude-Fehler 400“: genauen Text und Diagnose senden.
- [ ] Header und Beta: Im Diagnose-Export steht `[claude] HTTP 200`. Falls die Fallback-Beta abgelehnt wird, steht dort „Fallback-Beta nicht verfügbar – erneuter Versuch ohne“, und der zweite Versuch gelingt.
- [ ] **Kosten pro Plan**: Die Zeile `Tokens: input …, output …` im Diagnose-Export notieren und in der Console unter Usage gegenprüfen. Je einmal mit Sonnet 5.5 und Opus 5.5. Erwartung: Opus ≈ 0,10 $ pro 7-Tage-Plan.
- [ ] Der Wunschtext wird berücksichtigt. Ziel und Hinweise aus dem Profil tauchen sinnvoll in der Begründung auf.
- [ ] Der Plan respektiert Trainingstage, Wochenbudget und maximale Einheitendauer. Bereits geplante Einheiten werden nicht doppelt geplant.
- [ ] Flugmodus während der Planung führt zu einer verständlichen Fehlermeldung, die App bleibt bedienbar.

### B10 – Kalender (Kontrolle im Alltag)

- [ ] Ein Eintrag, der in der Kalender-App gelöscht wurde, wird bei „Kalender aktualisieren“ neu angelegt.
- [ ] Wird eine Einheit in der App gelöscht, verschwindet auch der Kalendereintrag.
- [ ] Der Kalender „Indoor Training“ erscheint per iCloud auch am Mac.

## 7. MyWhoosh-Direktupload und Fahrten-Import (B21, B22)

Anmeldung: Profil → MyWhoosh. Upload: Einheit-Detail → „An MyWhoosh senden“ oder automatisch beim Übernehmen eines Plans.

- [ ] Upload einer Einheit: Sie erscheint in MyWhoosh unter „Custom Workouts“ und im MyWhoosh-Kalender, ohne Umweg über den Mac. *(am 17.11.2026 vom Entwickler bestätigt)*
- [ ] Nach der Anmeldung erscheinen die MyWhoosh-Fahrten der letzten 210 Tage im Verlauf. *(am 17.11.2026 bestätigt)*
- [ ] FIT-Import über die Dateien-App: volle Leistungskurve, keine doppelte Fahrt.
- [ ] Erneuter Upload derselben Einheit: wird sie aktualisiert oder doppelt angelegt?
- [ ] Fehlerfall (offline, abgelaufene Anmeldung) mit verständlicher Meldung. Fallback `.zwo`-Export funktioniert weiter.
- [ ] Diagnose-Export enthält Status und Dauer des Uploads, aber keine Zugangsdaten.

## 8. Ablauf: vier Wochen Pilot

| Woche | Fokus | Aufgaben der Fahrer | Aufgaben Entwickler |
|---|---|---|---|
| **0** (Vorbereitung) | Build & Einladung | – | B07 TestFlight, `AppConfig.feedbackEmail` setzen, Build hochladen, Kick-off-Mail mit diesem Plan |
| **1** | Einrichtung & Kern-Threads | §2 Einrichtung, T1–T5 einmal bewusst, B08-Checkliste | Täglich Feedback sichten, Blocker-Hotfix innerhalb von 48 h |
| **2** | Alltag | 3–4 Einheiten nach Plan fahren, T3 MyWhoosh jedes Mal, A2 (F08) | Diagnose-Exporte auswerten (Sync-Dauer, HTTP-Fehler), Build 2 bei Bedarf |
| **3** | Coach & Winter Arc | Zweite Woche mit Claude planen, Modellvergleich Sonnet ↔ Opus (B09-Kosten), W1–F2 prüfen | Kosten pro Plan zusammenfassen, Prompt bei Bedarf anpassen |
| **4** | Rand & Abschluss | A1 Kontrast (G1/G2), A3 VoiceOver, A4 Performance, Feedback-Fragebogen (§9) | Auswertung, Liste für Phase 2 (P2-Backlog), Entscheidung über breiteren Rollout |

**Abbruchkriterien**: Datenverlust (Fahrten, Plan, Profil), ein Absturz, der sich wiederholt, oder ein Key/Token im Klartext in einem Export. Dann wird der Pilot pausiert und ein Hotfix-Build geliefert.

## 9. Feedback-Fragen (Ende Woche 4)

Skala 1–5 (1 = trifft gar nicht zu, 5 = trifft voll zu), dazu ein Freitextfeld je Frage.

1. Die Einrichtung (Strava, Claude-Key, Kalender) war ohne Hilfe machbar. *Wo hast du gestockt?*
2. Morgens sehe ich in wenigen Sekunden, was heute ansteht.
3. Die Pläne von Claude passten zu meiner Zeit, meinem Ziel und meiner Form. *Was hast du am häufigsten geändert?*
4. Die Begründungen je Einheit waren verständlich und haben mein Vertrauen in den Plan erhöht.
5. Der Weg von der Einheit nach MyWhoosh war zumutbar. *Wie viele Minuten hat er pro Einheit gedauert?*
6. Relative Effort sowie Fitness & Freshness stimmen mit meinem Gefühl und mit Strava überein.
7. Der Winter Arc (Level, Kurs, Serie) motiviert mich, dranzubleiben.
8. Texte, Zahlen und Diagramme sind auf meinem Gerät gut lesbar (Größe, Kontrast, Dunkelmodus).
9. Ich hatte nie das Gefühl, dass Daten verloren gehen oder ungefragt geteilt werden.
10. Ich würde IndoorCoach nach dem Pilot weiter nutzen. *Was müsste passieren, damit es eine 5 wird?*

## 10. Feedback-Kanal & Diagnose

- **Profil → Hilfe & Feedback → Diagnose exportieren** erzeugt eine Textdatei mit den App-Protokollen der letzten 24 h. Sie enthält App- und iOS-Version, Gerät, Zähler und Status, aber keine Keys, Tokens, Fahrtnamen, Ziele oder Hinweise. Die Datei vor dem Senden kurz ansehen.
- **Feedback senden** öffnet eine Mail an die Pilot-Adresse (`AppConfig.feedbackEmail`, wird vor Woche 1 gesetzt). Bis dahin erklärt die App, dass die Adresse noch folgt.
- Für jedes Problem: **was getan, was erwartet, was passiert**, dazu ein Screenshot oder eine Bildschirmaufnahme und der Diagnose-Export.
