# Gerätetest iPhone + Mac (B25 und offene Live-Prüfungen)

Stand 18.11.2026 · Dauer ca. 60–75 min plus eine echte Fahrt in MyWhoosh · Ergebnis: Häkchen und Notizen hier eintragen oder als Feedback-Issue („Fehler“) melden. Bei Problemen immer **Profil → Hilfe & Feedback → Diagnose exportieren** anhängen. Der Export enthält jetzt auch den Brückenstatus, aber keinen Mac-Namen.

Im Simulator und per Loopback ist alles automatisch geprüft, siehe [Brücke §7](14-SEKUNDENDATEN-MAC-BRUECKE.md#7-umsetzung-und-prüfung-18112026). Hier geht es um das, was nur echte Geräte zeigen:
- macOS-Freigaben für App-Daten und lokales Netzwerk
- signierter Schlüsselbund
- Login-Item
- echte MyWhoosh-FIT-Dateien
- echtes WLAN

## 0. Vorbereitung (Xcode, ca. 10 min)

| # | Schritt | Erwartung | ✓ |
|---|---|---|---|
| 0.1 | `git pull`, Xcode öffnen | Projekt öffnet ohne Fehler | ☐ |
| 0.2 | Scheme **IndoorCoach** → dein iPhone → Run | App startet auf dem iPhone | ☐ |
| 0.3 | Brücke: **bereits installiert am 19.11.** (`/Programme/IndoorCoach Brücke.app`, signiert mit deinem Apple-Development-Zertifikat). Neu installieren nach Änderungen: `scripts/install-bridge.sh` | In der Menüleiste erscheint das Fahrrad-Symbol, das Fenster „Einrichtung“ geht auf | ☐ |

## 1. Mac-Brücke einrichten (Journey-Schritte 3–4, 6)

| # | Schritt | Erwartung | ✓ |
|---|---|---|---|
| 1.1 | „MyWhoosh-Ordner freigeben“ | Der Öffnen-Dialog steht in `…/com.whoosh.whooshgame/…/MyWhoosh/Content/Data` | ✅ |
| 1.2 | „Freigeben“ klicken, eine macOS-Abfrage zu „Daten anderer Apps“ mit **Erlauben** bestätigen | „✓ N Fahrten gefunden“ (N > 0, wenn du schon in MyWhoosh gefahren bist). **Notieren:** Erschien eine Abfrage? Wie hieß sie? | ✅ |
| 1.3 | „iPhone koppeln“ | 6-stelliger Code mit Countdown. macOS fragt nach dem **lokalen Netzwerk** → *Erlauben* | ✅ |
| 1.4 | „Beim Anmelden starten“ an lassen | *Systemeinstellungen → Allgemein → Anmeldeobjekte* zeigt „IndoorCoach Brücke“ | ☐ |
| 1.5 | Fenster schließen | Brücke läuft nur in der Menüleiste weiter, das Panel zeigt den Status | ☐ |

## 2. iPhone koppeln (Journey-Schritte 2, 4, 5)

| # | Schritt | Erwartung | ✓ |
|---|---|---|---|
| 2.1 | iPhone im selben WLAN. *Verlauf → Leistung* | Karte „Volle Leistungskurve für jede Fahrt“ mit „Einrichten“, sofern Fahrten ohne Sekundendaten existieren | ☐ |
| 2.2 | „Einrichten“ | Drei Schritte. iOS fragt nach dem **lokalen Netzwerk** → *Erlauben*. Dein Mac erscheint unter „Gefundene Macs“ (≤ 10 s) | ✅ |
| 2.3 | Mac antippen, **falschen** Code eingeben | Fehlertext, keine Kopplung | ☐ |
| 2.4 | Richtigen Code eingeben | „Gekoppelt mit <Mac>“, „N Fahrten übertragen, M bestehende ergänzt“, Banner | ✅ |
| 2.5 | *Verlauf* öffnen | Fahrten aus der MyWhoosh-Liste haben jetzt das Abzeichen „Sekundendaten“, *Leistung* zeigt „X von X Fahrten mit Sekundendaten“ | ☐ |
| 2.6 | Eine ergänzte Fahrt öffnen | Leistungskurve gemessen statt „Mindestwert“. Ist Paket Z gemergt, auch „Zeit in Zonen“ | ☐ |

## 3. Alltag: echte Fahrt (Journey-Schritt 7)

| # | Schritt | Erwartung | ✓ |
|---|---|---|---|
| 3.1 | Eine kurze Fahrt (≥ 10 min) in MyWhoosh auf dem Mac fahren und speichern | Nach ≤ 1 min zeigt das Menüleisten-Panel eine Fahrt mehr | ☐ |
| 3.2 | **Notieren:** Name der neuen Datei im MyWhoosh-Ordner, und ob dieselbe Datei überschrieben wurde | z. B. `MyNewActivity-<Version>.fit`. Wird sie überschrieben, ist das in Ordnung: Die Brücke kopiert jede Fahrt in ihren eigenen Ausgang | ✅ |
| 3.3 | IndoorCoach auf dem iPhone öffnen (Vordergrund) | Banner „Neue Fahrt vom Mac: … min · NP … W“ innerhalb weniger Sekunden | ☐ |
| 3.4 | Ist die Fahrt auch über die MyWhoosh-Liste gekommen (Sync beim Start)? | Nur **eine** Fahrt im Verlauf, keine Dublette | ☐ |
| 3.5 | War für heute eine Einheit geplant? | Einheit ist „Erledigt“. Ist Paket S gemergt, zeigt die Einheit „Soll/Ist“ | ☐ |

## 4. Sonderfälle (Journey-Schritt 8)

| # | Schritt | Erwartung | ✓ |
|---|---|---|---|
| 4.1 | Mac zuklappen, im iPhone „Jetzt abholen“ | „Mac nicht erreichbar – ist die Brücke geöffnet und seid ihr im selben WLAN?“ | ☐ |
| 4.2 | App ohne erreichbaren Mac öffnen (automatischer Abgleich) | keine Fehlermeldung | ☐ |
| 4.3 | Mac neu starten | Brücke startet von selbst (Anmeldeobjekt), Kopplung bleibt (signierter Schlüsselbund). In der Menüleiste **keine** Warnung „Schlüsselbund nicht verfügbar“ | ☐ |
| 4.4 | Mac: „Kopplung zurücksetzen…“ → iPhone: „Jetzt abholen“ | „Die Kopplung passt nicht mehr. Löse sie und koppele den Mac neu.“ | ☐ |
| 4.5 | iPhone: „Kopplung lösen“, neu koppeln | funktioniert, Fahrten werden nicht doppelt geladen | ☐ |
| 4.6 | Ohne Brücke: eine `.fit`-Datei per AirDrop oder aus der Dateien-App mit „Öffnen in IndoorCoach“ | „1 Fahrt mit Sekundendaten ergänzt“ bzw. „importiert“ | ☐ |

## 5. Neue Features (nach dem Merge der Pakete Z, S, A)

| # | Schritt | Erwartung | ✓ |
|---|---|---|---|
| 5.1 | Fahrt-Detail → „Zeit in Zonen“, Leistung/Puls umschalten | plausible Minuten je Zone, Summe ≈ Fahrzeit ohne Pausen | ☐ |
| 5.2 | Relative Effort einer Fahrt mit Pulssekunden | Quelle „Puls (Sekunden)“. Wert plausibel zum Gefühl | ☐ |
| 5.3 | Erledigte Einheit mit Intervallen öffnen | „Soll/Ist“: Intervalle erkannt, getroffen/zu leicht/zu hart passt zur Erinnerung | ☐ |
| 5.4 | Geplante Einheit → „Anpassen“ → 45 min, −5 % → Übernehmen | Dauer und TSS sinken, Kalendereintrag geändert. War sie schon in MyWhoosh, ist dort die angepasste Version | ☐ |
| 5.5 | „Original wiederherstellen“ | alte Dauer, auch in MyWhoosh | ☐ |

## 6. Weitere offene Live-Prüfungen

| # | Aus | Schritt | ✓ |
|---|---|---|---|
| 6.1 | Status „nächste Schritte“ | **Ersetzen einer Einheit in MyWhoosh** (bereits gesendete Einheit neu senden) → in MyWhoosh nur die neue Version, alter Kalendereintrag weg | ☐ |
| 6.2 | B13 | Kontrast-Knoten mit dem Accessibility Inspector (Xcode → Open Developer Tool) auf dem iPhone: Einheit-Detail nach „An MyWhoosh senden“ | ☐ |
| 6.3 | B14 | VoiceOver-Durchlauf: Heute → Einheit → senden, Plan → neu planen, Verlauf → Fahrt, Profil → Mac-Brücke | ☐ |
| 6.4 | B15 | Release-Build (*Edit Scheme → Run → Release*): Kaltstart < 2 s, Verlauf scrollt flüssig | ☐ |

## 7. Brustgurt (O11/O12, B26)

Voraussetzung: Paket „HR · Brustgurt-Basis“ im Build, ein BLE-Brustgurt (TICKR, Polar H10 oder ähnlich) mit frischer Batterie, MyWhoosh am Mac. Gurt vorher anfeuchten und anlegen. **Polar H10:** in der App Polar Beat einmal verbinden und die Mehrfachverbindung aktivieren. Das Protokoll liefert nur Zähler und Status, keine Pulswerte. Es steht danach im Diagnose-Export (*Profil → Hilfe & Feedback → Diagnose exportieren*).

### 7a. Koppeln und Fähigkeiten

| # | Schritt | Erwartung | ✓ |
|---|---|---|---|
| 7.1 | *Profil → Geräte → Brustgurt* | Erklärseite „Nur dein Pulsgurt. Nichts verlässt das iPhone.“ | ☐ |
| 7.2 | „Weiter“ | iOS fragt nach Bluetooth, Text nennt den Brustgurt. *Erlauben* | ☐ |
| 7.3 | Suche, Gurt in der Liste antippen: „Verbinden“ | Gurt erscheint mit Signalstärke, nach dem Verbinden Live-Puls, plausibel zum Gefühl | ☐ |
| 7.4 | Fähigkeiten ansehen | RR-Intervalle „✓ empfangen“ (sonst notieren), Akku in %, Gurtname, Modellhinweis | ☐ |

### 7b. Mehrfachverbindung parallel zu MyWhoosh (O11)

| # | Schritt | Erwartung | ✓ |
|---|---|---|---|
| 7.5 | Gurt hier verbunden lassen. Am Mac MyWhoosh öffnen, Gurt als Pulsquelle wählen | MyWhoosh zeigt Puls | ☐ |
| 7.6 | In der App „Mehrfachverbindungs-Test“ → starten, Ablauf bestätigen | Puls läuft hier weiter, ohne Abbruch | ☐ |
| 7.7 | 2 min beobachten, Puls hier und in MyWhoosh vergleichen | Beide Werte laufen, RR bleibt „✓“ | ☐ |
| 7.8 | Bei Abbruch: Welche Seite verliert den Puls? | **Notieren:** Gurtmodell, wer abbricht, ob RR nur auf einer Seite ankommt | ☐ |

### 7c. Gesperrtes Display (O12), 60 min

| # | Schritt | Erwartung | ✓ |
|---|---|---|---|
| 7.9 | „Gerätetest → Protokoll starten“, Gurt tragen oder auf dem Rad ruhig fahren | Zähler laufen | ☐ |
| 7.10 | iPhone sperren (Seitentaste), 60 min liegen lassen, MyWhoosh am Mac läuft parallel | – | ☐ |
| 7.11 | Entsperren, App öffnen, „Protokoll beenden“ | Bericht: Hintergrund ≈ 60 min, Pakete ≈ 1/s, Lücken > 2 s: 0 (Ziel), Reconnects notiert | ☐ |
| 7.12 | *Diagnose exportieren* und prüfen | Abschnitt „Gerätetest Brustgurt“ ohne Pulswerte | ☐ |

**Ergebnis (eintragen):** Modell ____ · Mehrfachverbindung ja/nein ____ · RR auf zweitem Kanal ja/nein ____ · Lücken ____ (längste ____ s) · Reconnects ____ · Akku Start/Ende ____ / ____ · Auffälligkeiten ____

## Notizen

| Punkt | Beobachtung |
|---|---|
| 19.11.2026, 1.1–2.4 | Brücke per `scripts/install-bridge.sh` installiert (Apple-Development-Zertifikat, kein Profil). Ordner freigegeben: macOS zeigte den Freigabe-Dialog (Wortlaut nicht notiert). Kopplung mit dem iPhone 17e im WLAN erfolgreich, Sekundendaten der heutigen Einheit in der App. |
| 3.2 Dateiname | `MyNewActivity-<MyWhoosh-Version>.fit`, **eine Datei je App-Version**, jede neue Fahrt derselben Version überschreibt sie. Im Ordner lagen 6 Dateien (5.5.0 … 6.3.0, Dez. 2025 bis heute), alle mit Leistung, Puls und Kurve. Heute: `MyNewActivity-6.3.0.fit`, 45:06, Ø 122 W, NP 125 W. Die Brücke sichert jede neue Fassung in ihrem Ausgang. |
| 2.4 „4 von 6“ | Die Brücke hat alle 6 Dateien gelesen und ausgeliefert (Protokoll). Wahrscheinlich war es der Banner „Vom Mac: 4 neu, 2 ergänzt“: Die Fahrten vom 14.05. und von heute kamen schon aus der MyWhoosh-Liste (210 Tage) und wurden ergänzt, die vier älteren neu angelegt. Gegenprobe offen: *Verlauf → Leistung* „X von Y Fahrten mit Sekundendaten“. |

## Live Activity (B38)

Voraussetzung: Einstellungen → IndoorCoach → „Live-Aktivitäten“ ist an. Für das Widget-Target `IndoorCoachWidgets` (Bundle-ID `app.indoorcoach.personal.widgets`) in Xcode dasselbe Team wie für die App wählen.

| # | Schritt | Erwartung | ✓ |
|---|---|---|---|
| L.1 | Aufzeichnung starten (Gurt tragen), iPhone sperren | Sperrbildschirm zeigt Titel, laufende Zeit, Puls groß mit Herz | ☐ |
| L.2 | Plan-Einheit: Block wechselt | Blockname und Restzeit-Countdown aktualisieren sich | ☐ |
| L.3 | Gurt ausschalten oder weit weglegen | „Gurt getrennt“ in Gelb, Puls „–“; nach Wiederverbinden normal | ☐ |
| L.4 | iPhone mit Dynamic Island, App verlassen | Kompakt: Herz + Puls; lang drücken: Puls, Titel, Zeit, Block | ☐ |
| L.5 | VoiceOver auf dem Sperrbildschirm | Ein Satz: Titel, Puls, ggf. Gurt getrennt, Block mit Restzeit | ☐ |
| L.6 | Live-Aktivitäten in den Einstellungen abschalten, neu aufzeichnen | Aufzeichnung läuft normal, keine Live Activity, kein Fehler | ☐ |
| L.7 | Aufzeichnung beenden | Aktivität endet, Sperrbildschirm räumt nach ca. 1 min auf | ☐ |
| L.8 | Dunkel- und Hellmodus | Immer dunkle Fläche, Schrift gut lesbar | ☐ |
