---
description: Ziel mit minimalem Tool-Budget umsetzen — recon → builder → checker
argument-hint: <ziel>
---

Setze dieses Ziel um: $ARGUMENTS

Halte dich strikt an diese Kette. Jede Stufe bekommt genau eine Delegation, keine
Zwischenfragen, keine eigenen Suchläufe im Haupt-Kontext.

1. **recon** — delegiere das Ziel wörtlich und lass dir `FAKTEN`, `KOMMANDOS`,
   `OFFEN` zurückgeben. Ist `OFFEN` nicht leer und blockiert es die Umsetzung,
   frage den Nutzer; sonst weiter.
2. **builder** — delegiere das Ziel **zusammen mit dem vollständigen
   recon-Output**. Der builder darf nicht erneut suchen müssen, also gib ihm die
   Pfade wörtlich mit.
3. **checker** — nur wenn `KOMMANDOS` echte Kommandos enthält. Bei `fail` genau
   **einen** Reparaturdurchgang über builder (mit dem `FEHLER`-Block als Auftrag),
   danach erneut checker. Bleibt es rot, berichte den Stand, statt weiter zu
   iterieren.

Lies selbst keine Dateien, die dir ein Subagent schon beschrieben hat. Fasse am
Ende in maximal fünf Zeilen zusammen: was geändert wurde, ob die Checks grün sind,
was offen blieb.
