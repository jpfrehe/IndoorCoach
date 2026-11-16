# Status & nächste Schritte

Stand: Prototyp v0.1 · 17.11.2026

## Was fertig ist

| Slice | Status | Nachweis |
|-------|--------|----------|
| S0 Scaffold (Xcode-Projekt, Swift Package, 4 Tabs, Demo-Daten) | ✅ | läuft im iOS-27-Simulator, Screenshots in `snapshots/sim` |
| S1 Workout-Domain, Zonen, TSS/IF, `.zwo`-Export | ✅ | Unit-Tests (XML wird geparst und geprüft) |
| S2 Verlauf, CTL/ATL/TSB, Wochenumfang, Charts | ✅ | Unit-Tests + Snapshots |
| S3 Strava (OAuth, Token-Refresh, Sync, Paginierung) | ✅ Code, ⚠️ nicht live getestet | Unit-Tests mit Mock-HTTP |
| S4 Coach (Prompt, Structured Output, Validierung, Demo-Coach) | ✅ Code, ⚠️ nicht live getestet | Unit-Tests mit Mock-HTTP |
| S5 Kalender (eigener Kalender „Indoor Training“, Update/Löschen) | ✅ Code, ⚠️ nur auf Gerät prüfbar | – |
| S6 Review & Härtung | ✅ | ECC `swift-reviewer` + `security-reviewer`, alle CRITICAL/HIGH behoben |

40 Unit-Tests grün (`cd IndoorCoachKit && swift test`).

## Was du morgen tun musst (≈ 20 min)

1. App per Xcode aufs iPhone ([Installation](03-INSTALLATION.md) §1).
2. Strava-API-App anlegen, Client-ID/Secret eintragen, verbinden (§2).
3. Claude-API-Key eintragen (§3) – **erster echter Planungsaufruf**: bitte prüfen, ob ein Plan ankommt.
   Falls „Claude-Fehler 400“: Meldung notieren, ich passe den Request an.
4. Einheit exportieren und den MyWhoosh-Import einmal durchspielen.

## Bekannte Einschränkungen

- Strava/Claude/Kalender konnten ohne deine Zugangsdaten nicht end-to-end getestet werden.
- Strava-API-Bedingungen: KI-*Training* ist verboten; ob das Senden eigener Kennzahlen an ein LLM erlaubt ist, ist offiziell ungeklärt.
  Die App sendet nur Aggregate (keine Namen, Orte, GPS, Streams) und nur auf Klick. Siehe [Konzept §7](02-KONZEPT.md).
- MyWhoosh hat keine API → Import über `.zwo` + Workout Builder (2 Klicks am Mac).
- TSS ist eine Schätzung aus der gewichteten Durchschnittsleistung (kein Stream-basiertes NP).
- Free Provisioning: App muss alle 7 Tage neu aus Xcode installiert werden.

## Ideen für Phase 2

| Idee | Nutzen | Aufwand |
|------|--------|---------|
| „Einheit anpassen“ (kürzer/leichter) per Claude direkt in der Detailansicht | flexibler Alltag | S |
| FTP-Vorschlag aus Strava-Daten / nach Testeinheit | weniger Pflege | S |
| Apple Health als zweite/alternative Datenquelle (MyWhoosh/Wahoo schreiben dort hinein) | unabhängig von Strava-API-Regeln | M |
| Leistungsstreams laden → echte NP, Soll/Ist-Vergleich je Intervall | bessere Auswertung | M |
| intervals.icu-Anbindung als Brücke für automatisches Übertragen nach MyWhoosh | kein manueller Upload | M |
| Wöchentlicher Auto-Plan (Docker-Backend + Push) | „Plan ist sonntags einfach da“ | M–L |
| Widget / Live Activity „Heutige Einheit“ | schneller Blick | S |
