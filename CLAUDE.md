# Projekt-Instruktionen

Ziel dieses Repos: ein KI-Workflow, der ein Ziel mit **so wenigen Tool-Aufrufen wie
möglich** erreicht. Wissen wird über Auto-Memory persistiert, damit spätere Läufe
nicht erneut explorieren müssen.

## Tool-Budget (gilt für Haupt-Session und alle Subagenten)

- **Bündeln statt stückeln.** Mehrere Dateien in *einem* `Bash`-Aufruf lesen
  (`sed -n`, `head`) statt in mehreren `Read`-Aufrufen. Schritte mit `&&` verketten.
- **Unabhängige Aufrufe parallel** in einer Nachricht absetzen, nie sequenziell.
- **Erst Memory, dann Filesystem.** Vor jeder Exploration `MEMORY.md` des Agenten
  prüfen. Steht die Antwort dort, entfällt der Suchlauf.
- **Nicht nachverifizieren.** Ein `Edit`/`Write` schlägt fehl, wenn es nicht greift —
  die Datei danach nicht erneut lesen.
- **Kein Discovery für bekannte Fakten.** Build-, Test- und Lint-Kommandos stehen
  unten; sie werden nicht durch Suchen hergeleitet.

## Projekt-Fakten

- Stack: noch nicht festgelegt (Repo enthält bisher nur Konfiguration).
- Build: `—` · Test: `—` · Lint: `—`

Sobald der Stack steht, hier eintragen. Diese drei Zeilen sparen pro Lauf die
meisten Aufrufe.

## Workflow

`/flow <ziel>` orchestriert die drei Subagenten. Details: @docs/workflow.md

## Konventionen

- Änderungen laufen auf Feature-Branches, nie direkt auf `main`.
- Commit-Nachrichten: imperativ, eine Zeile Betreff, Body nur wenn nötig.
