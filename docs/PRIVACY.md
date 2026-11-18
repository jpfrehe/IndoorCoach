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

## 3. Datenweitergabe an Dritte

Die App sendet Daten nur dann, wenn **du** die jeweilige Funktion nutzt. Die Verbindung geht direkt von deinem Gerät zum jeweiligen Dienst, mit **deinen eigenen** Zugangsdaten. Der Entwickler ist nicht beteiligt und sieht diese Daten nicht.

| Dienst | Wann | Was wird gesendet |
|---|---|---|
| **Anthropic (Claude)** | Du lässt einen Plan oder eine Auswertung erstellen | Trainingsdaten und Profil-Eckdaten (z. B. FTP, Ziele, Belastungsverlauf) als Text, dein API-Key. Es gelten die Bedingungen und die Datenschutzerklärung von Anthropic und dein eigener Vertrag mit Anthropic. |
| **MyWhoosh** | Du meldest dich an, synchronisierst Fahrten oder schickst ein Workout | E-Mail und Passwort zur Anmeldung, Workout-Daten; Abruf deiner Fahrten. Die Schnittstelle ist inoffiziell. Es gelten die Bedingungen von MyWhoosh. |
| **Strava** | Du verbindest Strava | OAuth-Anmeldung, Abruf deiner Aktivitäten. Es gelten die Bedingungen von Strava. |
| **GitHub** | Du sendest Feedback | Die App öffnet im Browser ein vorausgefülltes Issue-Formular. Gesendet wird erst, wenn du dort selbst auf „Create“ tippst; dafür brauchst du ein GitHub-Konto. Issues sind öffentlich. |

Außerdem kann iOS Standard-Funktionen anbieten, etwa das Teilen eines Bildes oder einer Datei über das Share-Sheet. Dabei entscheidest du, wohin die Daten gehen.

## 4. Was nicht passiert

- Keine Werbung, kein Tracking, keine Weitergabe oder der Verkauf von Daten.
- Keine Analyse- oder Absturzberichts-SDKs von Dritten in der App. (Apple kann, wenn du es in iOS erlaubt hast, anonyme Absturz- und Nutzungsdaten über TestFlight/App Store an den Entwickler melden; darauf hat die App keinen Einfluss.)
- Keine Nutzerkonten und keine Server des Entwicklers.

## 5. Speicherdauer und Löschung

Die Daten bleiben auf dem Gerät, bis du sie löschst. Unter **Profil → „Alle Daten löschen“** entfernt die App alle lokalen Daten, alle Schlüsselbund-Einträge, die App-Einstellungen und ihre Kalendereinträge. Daten bei Strava, MyWhoosh und Anthropic bleiben davon unberührt; sie löschst du dort selbst. Beim Löschen der App entfernt iOS die lokalen App-Daten.

## 6. Deine Rechte

Da der Entwickler keine personenbezogenen Daten von dir erhält, kann er sie auch nicht auskunftsfähig speichern. Für die Daten bei Anthropic, MyWhoosh, Strava und GitHub wende dich an den jeweiligen Anbieter (Auskunft, Berichtigung, Löschung, Beschwerde bei der Aufsichtsbehörde).

## 7. Kinder

Die App richtet sich nicht an Kinder unter 13 Jahren.

## 8. Änderungen

Wird die App um Funktionen erweitert, die Daten übertragen, wird diese Erklärung vorher angepasst. Die aktuelle Fassung liegt im Projekt unter `docs/PRIVACY.md`.
