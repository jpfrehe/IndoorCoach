# Datenschutzerklärung IndoorCoach

> **Entwurf, kein Rechtsrat.** Dieser Text ist eine Vorlage und muss vor der Veröffentlichung geprüft und um Name und Anschrift des Verantwortlichen ergänzt werden (Impressumspflicht). Stand: November 2026.

## Kurz gesagt

IndoorCoach hat **keine eigenen Server**, **kein Nutzerkonto**, **kein Tracking** und **keine Analyse- oder Werbe-SDKs**. Deine Daten liegen auf deinem Gerät. Der Entwickler erhält keine Daten von dir.

## 1. Verantwortlicher

`[Name, Anschrift, E-Mail des Entwicklers – vor Veröffentlichung ergänzen]`

Kontakt für Fragen zum Datenschutz: über ein Issue im öffentlichen Projekt unter <https://github.com/jpfrehe/IndoorCoach/issues> (bitte keine persönlichen Daten in öffentliche Issues schreiben) oder per E-Mail an die oben genannte Adresse.

## 2. Welche Daten die App verarbeitet

Alle folgenden Daten werden **ausschließlich auf deinem Gerät** gespeichert:

- **Profil und Ziele:** FTP, Gewicht, Trainingstage, Wochenbudget, Ziele.
- **Trainingsdaten:** Fahrten (Dauer, Leistung, Puls, Distanz), Pläne, Auswertungen, Fitness-Kennzahlen.
- **Zugangsdaten:** Claude-API-Key, Strava-Tokens und die MyWhoosh-Sitzung liegen im **iOS-Schlüsselbund** (Keychain). Das MyWhoosh-Passwort wird nicht gespeichert.
- **Einstellungen:** einfache App-Einstellungen (UserDefaults).
- **Kalender (optional):** Wenn du es erlaubst, legt die App Trainingseinheiten in einem eigenen Kalender an.
- **Brustgurt (Bluetooth, optional):** Verbindest du einen Herzfrequenz-Brustgurt, nutzt die App Bluetooth nur dafür. Sie liest Puls und Herzschlag-Abstände (RR) und berechnet daraus unter anderem die Herzfrequenzvariabilität (HRV). Die Werte dienen der Anzeige, der Aufzeichnung und der Auswertung auf dem Gerät. Die Gerätekennung des gekoppelten Gurts wird lokal gemerkt.
- **Apple Health (optional):** Wenn du es erlaubst, **liest** die App Workouts, Gewicht und Erholungswerte (zum Beispiel Schlaf, Ruhepuls, HRV) aus Apple Health. Auf Wunsch **schreibt** sie aufgezeichnete Einheiten nach Apple Health. Jede Freigabe erteilst und entziehst du in iOS unter Einstellungen → Gesundheit. Die gelesenen Werte bleiben auf dem Gerät.
- **Krafttraining und andere Sportarten:** Übungen, Sätze, Wiederholungen, Gewichte, Anstrengung, Beinbelastung und Notizen zu Kraft- und anderen Einheiten.
- **Check-ins:** Deine Antworten vor einer Einheit (Beine, Schlaf, Laune, Kontext wie „Infekt“). Sie sind keine Diagnose und ändern den Plan nie automatisch.
- **Aufwärm-Check:** der Puls bei einer festen Referenzleistung im Einfahren, als Vergleichspunkt über die Zeit.

**Speicherorte:** Fahrten, Pläne, Kraft-Einheiten und Check-ins liegen in der App-Datenbank (SwiftData) auf deinem Gerät. Zugangsdaten liegen im Schlüsselbund, Einstellungen und Entscheidungen (zum Beispiel Einwilligungen) in den UserDefaults. Es gibt keine Cloud-Synchronisierung durch den Entwickler.

## 3. Datenweitergabe an Dritte

Die App sendet Daten nur dann, wenn **du** die jeweilige Funktion nutzt. Die Verbindung geht direkt von deinem Gerät zum jeweiligen Dienst, mit **deinen eigenen** Zugangsdaten. Der Entwickler ist nicht beteiligt und sieht diese Daten nicht.

| Dienst | Wann | Was wird gesendet |
|---|---|---|
| **Anthropic (Claude)** | Du lässt einen Plan oder eine Auswertung erstellen | Trainingsdaten und Profil-Eckdaten (z. B. FTP, Ziele, Belastungsverlauf), Krafteinheiten und andere Sportarten der letzten Tage als Text, dein API-Key. **Nur mit deiner ausdrücklichen Einwilligung** zusätzlich ein relativer Erholungskontext (siehe unten). Es gelten die Bedingungen und die Datenschutzerklärung von Anthropic und dein eigener Vertrag mit Anthropic. |
| **MyWhoosh** | Du meldest dich an, synchronisierst Fahrten oder schickst ein Workout | E-Mail und Passwort zur Anmeldung, Workout-Daten; Abruf deiner Fahrten. Die Schnittstelle ist inoffiziell. Es gelten die Bedingungen von MyWhoosh. |
| **Strava** | Du verbindest Strava | OAuth-Anmeldung, Abruf deiner Aktivitäten. Es gelten die Bedingungen von Strava. |
| **GitHub** | Du sendest Feedback | Die App öffnet im Browser ein vorausgefülltes Issue-Formular. Gesendet wird erst, wenn du dort selbst auf „Create“ tippst; dafür brauchst du ein GitHub-Konto. Issues sind öffentlich. |

**Einwilligung für den Erholungskontext (Claude):** Bevor Erholungsdaten an Claude gehen, fragt die App ausdrücklich nach, sobald du Apple Health oder Check-ins nutzt und zum ersten Mal planst. Ohne Einwilligung wird kein Erholungskontext gesendet. Gesendet wird dann nur eine **relative, gerundete Zusammenfassung der letzten 14 Tage**: Schlaf und Ruhepuls als Abweichung von deiner eigenen Basis, HRV als Trend (unter, im oder über der Basis), eine Zusammenfassung der Check-ins (zum Beispiel „2× Beine schwer“), der Trend des Aufwärm-Checks und ob der Trend-Wächter aktiv ist. **Nie** gesendet werden Rohwerte, Zeitreihen, Gerätenamen, Notizen, Diagnosen oder Namen. Unter **Profil → Datenschutz** siehst du eine Vorschau mit genau diesem Text und kannst die Einwilligung jederzeit widerrufen; der Widerruf wirkt sofort. Ändert sich, was gesendet wird, fragt die App erneut.

**IndoorCoach Brücke (Mac, optional):** Die Mac-App liest nach deiner Freigabe die FIT-Dateien im MyWhoosh-Ordner und speichert eine Kopie auf deinem Mac. Sie gibt die Fahrten nur an iPhones weiter, die du per Code gekoppelt hast, und nur verschlüsselt (TLS mit einem gemeinsamen Schlüssel) im lokalen Netzwerk. Es gibt keinen Server und keine Übertragung ins Internet. Den Schlüssel speichern beide Geräte im Schlüsselbund. „Kopplung zurücksetzen“ auf dem Mac macht ihn ungültig.

Außerdem kann iOS Standard-Funktionen anbieten, etwa das Teilen eines Bildes oder einer Datei über das Share-Sheet. Dabei entscheidest du, wohin die Daten gehen.

## 4. Was nicht passiert

- Keine Werbung, kein Tracking, keine Weitergabe oder der Verkauf von Daten.
- Keine Analyse- oder Absturzberichts-SDKs von Dritten in der App. (Apple kann, wenn du es in iOS erlaubt hast, anonyme Absturz- und Nutzungsdaten über TestFlight/App Store an den Entwickler melden; darauf hat die App keinen Einfluss.)
- Keine Nutzerkonten und keine Server des Entwicklers.
- Gesundheits- und Fitnessdaten (Puls, HRV, Apple-Health-Werte, Krafttraining, Check-ins) werden nicht an Dritte weitergegeben, nicht für Werbung oder Profiling genutzt und nicht in iCloud oder einer anderen Cloud des Entwicklers gespeichert. Die einzige Ausnahme ist der oben beschriebene Erholungskontext an Claude mit deiner Einwilligung.

## 5. Speicherdauer und Löschung

Die Daten bleiben auf dem Gerät, bis du sie löschst. Unter **Profil → „Alle Daten löschen“** entfernt die App alle lokalen Daten (auch Krafttraining, Check-ins, Health-Zustand und Einwilligungen), alle Schlüsselbund-Einträge, die App-Einstellungen und ihre Kalendereinträge. Nach Apple Health geschriebene Einheiten löschst du in der Health-App; die Freigaben entziehst du in iOS unter Einstellungen → Gesundheit. Daten bei Strava, MyWhoosh und Anthropic bleiben davon unberührt; sie löschst du dort selbst. Beim Löschen der App entfernt iOS die lokalen App-Daten.

## 6. Deine Rechte

Da der Entwickler keine personenbezogenen Daten von dir erhält, kann er sie auch nicht auskunftsfähig speichern. Für die Daten bei Anthropic, MyWhoosh, Strava und GitHub wende dich an den jeweiligen Anbieter (Auskunft, Berichtigung, Löschung, Beschwerde bei der Aufsichtsbehörde).

## 7. Kinder

Die App richtet sich nicht an Kinder unter 13 Jahren.

## 8. Änderungen

Wird die App um Funktionen erweitert, die Daten übertragen, wird diese Erklärung vorher angepasst. Die aktuelle Fassung liegt im Projekt unter `docs/PRIVACY.md`.
