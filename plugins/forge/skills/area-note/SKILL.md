---
name: area-note
description: Write or update the area note for one directory - what is true there and nowhere else, under a paths glob that loads it when an agent reads a file in it. Use after working in a directory, and to seed an area during bootstrap.
argument-hint: "[directory, e.g. src/api]"
allowed-tools: Read, Write, Edit, Glob, Grep
---

# Area note for a directory

The argument is the directory the note covers. Without one, ask for it - never guess from the
last file you touched.

## 1. Name the area, find the note

The area name is the directory's own name, kebab-case, unless a sibling note already claims it.
The note is `.claude/rules/areas/<area>.md`, relative to the checkout you are working in - an
agent inside a worktree writes into that worktree, where `git add -A` carries it into the commit.
A note written into the main checkout instead belongs to no commit.

Read it if it exists. There is one note per area: extend it, never add a second for the same
directory.

## 2. Write it

New note: copy `${CLAUDE_SKILL_DIR}/note-template.md` and glob the directory - `<directory>/**`.
Widen the glob only to a directory whose facts are the same.

Existing note: merge what you learned into it. Delete the lines the change made false.

What earns a line is what an agent would otherwise research: the convention that bites, the
command that exercises the area, the file that must change alongside, the thing that looks safe
here and is not. What the code already says earns nothing.

- One line per durable fact.
- Nothing specific to one issue, one change or one run.
- Under 100 lines. Past that it costs more than the search it replaces.

## 3. Report

The path and what changed, in one line.
