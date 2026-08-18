# KI-Workflow mit minimalem Tool-Budget

Ziel: ein Ziel mit so wenigen Tool-Aufrufen wie möglich erreichen. Der größte
Hebel ist nicht, einzelne Aufrufe zu sparen, sondern **Wiederholung zu vermeiden** —
dieselbe Datei zweimal lesen, dieselbe Suche in jeder Session neu fahren, ein
Kommando erraten, das letzte Woche schon verifiziert wurde. Genau dafür ist die
projektbezogene Auto-Memory da.

## Aufbau

```
CLAUDE.md                              Regeln + stabile Projektfakten, jede Session geladen
.claude/settings.json                  autoMemoryEnabled, Allowlist gegen Rückfragen
.claude/commands/flow.md               /flow <ziel> — orchestriert die Kette
.claude/agents/recon.md                klärt Fakten          (memory: project)
.claude/agents/builder.md              setzt um              (memory: project)
.claude/agents/checker.md              prüft                 (memory: project)
.claude/agent-memory/<agent>/MEMORY.md persistiertes Wissen, versioniert
```

## Ablauf

```
/flow <ziel>
   │
   ├─ recon    → FAKTEN / KOMMANDOS / OFFEN        (Memory zuerst, dann ein Suchlauf)
   ├─ builder  → GEÄNDERT / ANNAHMEN / OFFEN       (bekommt recon-Output wörtlich)
   └─ checker  → ERGEBNIS / KOMMANDOS / FEHLER     (max. ein Reparaturdurchgang)
```

Die Stufen sind fachlich getrennt, damit jede in ihrem eigenen Kontextfenster
läuft und der Haupt-Kontext nur die drei kurzen Rückgabeblöcke sieht. Der
Haupt-Agent liest selbst nichts, was ein Subagent bereits beschrieben hat.

## Warum das Aufrufe spart

**Auto-Memory pro Projekt.** Jeder Agent hat `memory: project`, also ein eigenes
Verzeichnis unter `.claude/agent-memory/<name>/`. Die ersten 200 Zeilen (bzw.
25 KB) von `MEMORY.md` sind zu Beginn jedes Laufs schon im Kontext. Was dort
steht, muss nicht gesucht werden: Lauf 1 kostet die Exploration, Lauf 2 bis n
nicht mehr. `project` statt `user`, weil das Wissen repo-spezifisch ist — und weil
es unter `.claude/` liegt, geht es über Git ins Team.

Wichtig zur Abgrenzung: Die Auto-Memory der Haupt-Session
(`~/.claude/projects/<project>/memory/`) wird **nicht** in Subagenten geladen. Die
Agenten-Memory ist ein davon getrenntes Verzeichnis. Nur Subagenten mit `memory:`
haben überhaupt eine.

**Stabile Fakten in CLAUDE.md statt in Suchläufen.** Build-, Test- und
Lint-Kommando in `CLAUDE.md` ersetzen pro Lauf mehrere Aufrufe zum Auffinden des
Manifests. Diese drei Zeilen auszufüllen ist die lohnendste Einzelmaßnahme im
ganzen Setup.

**Enge Tool-Listen.** `recon` und `checker` können nicht schreiben. Ein Agent, der
eine Änderung gar nicht vornehmen kann, versucht sie auch nicht — das spart die
Fehlversuche mitsamt Korrektur.

**`maxTurns` als harte Grenze.** 10 / 30 / 8 Turns. Eine Schleife, die sich
festfrisst, wird abgeschnitten, statt Budget zu verbrennen.

**Feste Rückgabeformate.** Jeder Agent liefert einen Block mit festen Feldern.
Der Haupt-Agent muss nichts nachfragen und nichts nachlesen, um die Antwort zu
verwerten — das spart die Rückfrage-Runde.

**Bündeln.** Mehrere Ausschnitte in einem `Bash`-Aufruf (`sed -n`, `rg` mit
mehreren Patterns) statt in mehreren `Read`-Aufrufen; unabhängige Aufrufe
parallel in einer Nachricht.

**Allowlist in `settings.json`.** Vorab erlaubte Lesekommandos vermeiden
Berechtigungs-Rückfragen, die den Lauf unterbrechen.

**`effort: low`** für `recon` und `checker`: mechanische Stufen brauchen kein
tiefes Nachdenken, nur wenige gezielte Aufrufe.

## Memory sauber halten

`MEMORY.md` ist ein **Index**, kein Notizbuch: eine Zeile pro Eintrag, Details in
Themendateien (`layout.md`, `commands.md`, `pitfalls.md`), die nur bei Bedarf
gelesen werden. Wächst der Index über 200 Zeilen, fällt der Rest beim nächsten
Start still weg — Claude Code warnt vorher und meldet einen Fehler, wenn das Limit
überschritten ist.

Hinein gehört nur, was auch beim nächsten Mal noch stimmt: Layout, Kommandos,
Fallstricke. Nichts Aufgabenspezifisches, nichts, was der nächste Commit ändert.
Falsche Einträge sind teurer als fehlende — sie erzeugen Arbeit auf Basis
veralteter Annahmen. Inhalte lassen sich jederzeit mit `/memory` ansehen und
bearbeiten.

## Erweitern

- Reicht eine Stufe, `/flow` überspringen und direkt delegieren: `@agent-recon …`.
- Sollen Agenten parallel laufen, in *einer* Nachricht delegieren.
- Muss eine Regel garantiert greifen (statt nur wahrscheinlich), gehört sie in
  einen `PreToolUse`-Hook, nicht in `CLAUDE.md` — Instruktionen sind Kontext,
  keine Durchsetzung.

## Quellen

- Memory und Auto-Memory: https://code.claude.com/docs/en/memory
- Subagenten und `memory:`-Feld: https://code.claude.com/docs/en/sub-agents
