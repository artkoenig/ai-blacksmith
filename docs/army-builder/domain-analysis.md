# Army list building in tabletop wargames — a domain analysis

Prepared 2026-08-27 for a software architect who does not play these games. This describes the
subject matter only. It contains no data model, no schema and no software recommendation.

## 0. How to read this document

Three things are kept apart throughout, because they behave differently and change on different
clocks:

- **P — published rule.** In the rulebook the publisher sells or gives away. Changes at an edition
  boundary or by errata.
- **T — tournament pack.** Added by an event organiser or a circuit on top of the published rules.
  Changes every season, differs between events on the same weekend.
- **C — community convention.** Not written anywhere binding. Players expect it; a stranger who
  breaks it gets grumbling, not a penalty.

Confidence is marked where it matters:

- `[primary]` — I read the publisher's own document or the publisher's own rules site/API.
- `[secondary]` — a reliable community source describing a rule I could not open directly.
- `[unverified]` — stated by one source only, or blocked from checking. Treat as a hypothesis.

Every game system named carries its edition. A rule without an edition is wrong within a year, and
in 2026 two of the five systems below changed edition inside twelve months.

Systems covered and their state at the time of writing:

| System | Publisher | Current edition / version | Note |
|---|---|---|---|
| Warhammer 40,000 | Games Workshop | 11th edition, launched June 2026 `[secondary]` | Core rules free; 10th-edition codexes still usable with errata |
| Warhammer Age of Sigmar | Games Workshop | 4th edition (2024), with General's Handbook 2025-26 `[secondary]` | Army composition rules live in the General's Handbook, not the core book |
| Kings of War | Mantic Games | 4th edition, launched December 2025 `[secondary]` | Complete rewrite of army construction |
| Grimdark Future (One Page Rules) | One Page Rules | Core Rules v3.5.1 `[primary]` | Rules are one sheet; versions bump several times a year |
| Infinity | Corvus Belli | N5 / N5.2 `[primary]` | Rules published free on the official wiki |
| Malifaux | Wyrd Games | 4th edition, season "Gaining Grounds Zero" `[primary]` | Crew is built at the table, per game |

Sources are listed in section 7.

---

## 1. The core process, end to end

What follows is the general shape. Section 5 says which systems skip or reorder steps. The single
biggest structural surprise for a newcomer is at step 11: in one of these five systems the list is
not built before the event at all, it is built at the table after the mission is known.

### Step 1 — Agree the occasion

**Decision:** casual pickup game, campaign game, or tournament; and with whom.
This determines which rules layer applies (P only, or P+T), and how much rigour the list needs.

**What goes wrong:** the two players assume different layers. One built a "casual" list with a
model that a tournament pack bans; the other expected tournament norms.

### Step 2 — Agree the battle size / points limit

**Decision:** the budget the list is built against. In most systems this is a points number
(1000/2000/3000 in 40k; 1000 or 2000 in Age of Sigmar; 300 army points in Infinity; a soulstone
number in Malifaux). Some systems attach a **named battle size** to the number, and the name then
carries further limits — 40k 11th edition's Incursion / Strike Force / Onslaught each set not only
the points ceiling but the detachment budget, the enhancement cap and the duplicate cap
`[secondary]`.

**What goes wrong:** the players agree "2000 points" but not the battle size band, and the band is
what governs the other caps. Or the event pack sets a size that differs from the publisher's
default.

### Step 3 — Choose the faction

**Decision:** which army the list is drawn from. A faction is both a *content filter* (which units
may be picked) and a *rules package* (army-wide abilities). Some systems nest this: Infinity has a
generic army for each faction and several **sectorials** — smaller sub-armies with different unit
availability and access to fireteams `[primary]`. Malifaux nests it as faction → leader → keyword.

**What goes wrong:** picking a sub-faction whose restrictions the player then forgets; or picking a
faction whose new book was released after the event's rules cut-off date.

### Step 4 — Choose the army's organising structure

**Decision:** the skeleton the units hang off. This is the step that differs most across systems.

- 40k 11th: choose one or more **detachments**, paying **Detachment Points** from a budget set by
  battle size `[secondary]`.
- Age of Sigmar 4th: choose **regiments** — 1 to 5 of them, each a hero plus up to three other
  units `[secondary, GW rules mirror]`.
- Kings of War 4th: choose **battalions**, each requiring a minimum of two Core units and a
  Commander, with further slots unlocked by what you have already taken `[secondary]`.
- Grimdark Future: no structure at all beyond an optional force-organisation guideline `[primary]`.
- Infinity: no structure; a flat list of troopers, later divided into combat groups `[primary]`.
- Malifaux: the structure is the leader's keyword `[primary]`.

**What goes wrong:** choosing a structure whose entry requirements the rest of the list cannot meet
(a Kings of War battalion needs its two Core units before anything else is legal), or spending the
structural budget so that no points remain for the units the structure demands.

### Step 5 — Pick the warlord / general / leader

**Decision:** one model that leads. Universal across every system examined, under different names:
Warlord (40k), General (Age of Sigmar), Warlord (Kings of War), Lieutenant (Infinity), Leader —
usually a Master (Malifaux).

Constraints attach here: Age of Sigmar requires the general to be a hero who leads a regiment, and
if the army contains a WARMASTER unit one of them must be the general `[secondary]`. Infinity
requires exactly one Lieutenant — no more, no fewer `[primary]`. Malifaux: if a crew contains a
master, the master must be the leader `[primary]`.

**What goes wrong:** forgetting to nominate one at all — a very common cause of an otherwise legal
list being illegal. Or nominating a model the rules forbid (allied units in 40k that "cannot be
your Warlord" `[secondary]`).

### Step 6 — Pick units

**Decision:** the bulk of the work. For each unit: which datasheet, how many models, and where it
sits in the structure.

**What goes wrong:** the most common failure class overall. Exceeding a duplicate cap; taking a
unit the chosen structure does not allow; taking a model count that is not one of the legal sizes;
taking a named character twice; taking a unit whose entry has a per-army or per-structure limit.

### Step 7 — Set unit sizes

**Decision:** how many models in each unit. Systems handle this in three distinct ways, and the
difference matters:

- **A range with a step.** Take 5, 10, 15 or 20 models; cost scales.
- **A doubling switch.** Age of Sigmar 4th: a unit is taken at its minimum size, or **reinforced** —
  exactly twice the models for exactly twice the points, once only, and some units may not be
  reinforced at all `[secondary]`.
- **Fixed sizes with names.** Kings of War: infantry comes as Troop (10), Regiment (20), Horde (40)
  or Legion (60) — and the size is part of the unit's identity, affecting its stats and its
  category, not just its cost `[secondary]`.

**What goes wrong:** treating a reinforced unit as two units (or vice versa) for the purposes of
duplicate caps and unit-count caps. Grimdark Future has the mirror-image mechanic — **combined
units**, where two copies of the same unit merge into one, and the rules state explicitly that a
combined unit counts as one for the copy limit `[primary]`.

### Step 8 — Buy wargear and options

**Decision:** per unit and often per model, which weapons and equipment. This is where the
combinatorics live. Typical shapes of restriction: "one model in the unit may replace X with Y";
"for every five models, one may take Z"; "the champion only may take W"; mutually exclusive
choices; options that are free versus options that cost points.

**What goes wrong:** an option quantity that scales with model count, applied to the wrong count
after the unit was resized. Options that were free in one edition and cost points in the next.
Options removed by errata after the models were assembled — which collides with the physical
requirement in step 13.

### Step 9 — Buy enhancements / artefacts / traits

**Decision:** character upgrades drawn from a pool attached to the structure or the faction.

- 40k 11th: **Enhancements** from the detachment, capped per battle size across the whole army (2 at
  Incursion, 4 at Strike Force and Onslaught), one per Character, none on named characters
  `[secondary]`; a transcription of the official app's rules text adds that no unit, including a
  unit a character has joined, may carry more than one `[unverified]`.
- Age of Sigmar 4th: heroic traits, artefacts of power, and one manifestation lore for the army
  `[secondary]`.
- Kings of War 4th: magic artefacts bought onto units `[secondary]`.

**What goes wrong:** enhancement budgets are *global* while the eligibility is *local* — a classic
source of a list that looks legal unit by unit and fails as a whole.

### Step 10 — Reconcile against the budget and the caps

**Decision:** what to cut. Iterative, and where most of a player's time actually goes.

**What goes wrong:** everything at once — the list is 30 points over, dropping a unit breaks a
structural minimum, and swapping it breaks a duplicate cap.

### Step 11 — Freeze and record

**Decision:** what artefact leaves the process. A printed sheet, an app export, a submission to a
tournament platform.

Malifaux is the exception that matters most for anyone generalising: hiring is **step G of encounter
setup**, after terrain is placed and the scenario is determined, with both players hiring
simultaneously and hidden, then step H **reveals** the crews to each other `[primary]`. There is no
pre-built list to submit at all; what is fixed in advance at an event is the faction, and often the
leader.

**What goes wrong:** submitting a list in the wrong format (some events accept only the official
app's export format `[primary, event pack]`), submitting after the deadline, or submitting a list
that does not match what was actually built.

### Step 12 — External validation

**Decision:** none by the player; this is where someone else checks. At the World Team
Championship, after the submission deadline each team checks the lists of the teams in its own pod
`[primary]`. At a singles event, players matched for round one are required to review their
opponent's list and report errors to the organisers by email, and failing to do so can itself carry
a point penalty `[primary]`.

**What goes wrong:** an error found after the deadline. Packs differ on whether it is corrected,
penalised, or played as written.

### Step 13 — Bring the physical army

**Decision:** which models represent which entries. Two constraints bite here, both from the
tournament layer:

- **WYSIWYG** ("what you see is what you get") — the model must visibly carry the wargear its entry
  claims. Mandatory at the WTC and at the events surveyed `[primary]`.
- **Painting standard** — mandatory at those events, with a defined and scored standard `[primary]`.
  Not a published rule of any of these games.

Grimdark Future's tournament pack states the same idea in the plainest form available: all minis and
upgrades must be clearly identifiable and have a corresponding entry in the army list `[primary]`.

**What goes wrong:** a legal list that cannot be fielded because the models do not exist, are not
painted, are not the right base size, or do not visibly carry the options bought.

### Step 14 — Play, and possibly revise

See section 4.

---

## 2. Glossary

Marked **[U]** universal across the systems examined, **[M]** most systems in a varying form, **[1]**
belongs to one system.

**Army list / roster / list** **[U]** — the complete written record of a legal force: every unit,
its size, its equipment, its points, and any structural choices. "Roster" is the more formal word
in 40k and Age of Sigmar; "list" is what everybody says.

**Faction** **[U]** — the army the list is drawn from; both a content filter and a rules package.

**Sub-faction** **[M]** — a narrower slice with its own restrictions and its own bonuses.
Infinity's **sectorial armies** are the sharpest example: a sectorial has its own list of troopers
with availability numbers different from the parent generic army `[primary]`.

**Battle size** **[M]** — a named points band that carries further limits. 40k 11th: Incursion,
Strike Force, Onslaught, at roughly 1000 / 2000 / 3000 points `[secondary]`. Elsewhere the points
number stands alone.

**Points / points value / cost** **[U]** — the number every choice carries, summed against a limit.
Called Army Points in Infinity, soulstone cost or scrip in Malifaux, points everywhere else.

**Power level** **[1, historical]** — 40k's abandoned coarse-grained alternative currency, present
in 8th and 9th edition alongside points. Gone from current editions; mentioned because older
datasets and older third-party tools still carry the field.

**Unit** **[U]** — the thing that acts as one on the table: one model or many. The building block of
a list.

**Model / miniature / trooper** **[U]** — one physical figure. In skirmish games a unit is normally
one model, so the two words collapse — Infinity says "trooper", Malifaux says "model".

**Datasheet / warscroll / unit profile / stat card** **[U, name varies]** — the rules page for one
unit: its statistics, its weapons, its abilities, its legal sizes and its options. 40k calls it a
datasheet, Age of Sigmar a warscroll, Infinity a unit profile, Malifaux a stat card, Kings of War a
unit entry.

**Keyword** **[M]** — a machine-readable tag on a unit used by rules to address groups of units
("all ADEPTUS ASTARTES units"). Load-bearing for legality: faction membership, enhancement
eligibility and structural eligibility are frequently expressed as keyword tests. In Malifaux the
keyword is the primary hiring mechanism `[primary]`.

**Wargear / options / upgrades** **[U]** — the equipment choices on a datasheet, with restrictions
per model and per unit.

**Character / hero / commander** **[U]** — a single-model unit, usually a leader, usually the target
of enhancements and often required by the structure.

**Warlord / general / leader / lieutenant** **[U]** — the one nominated commander of the whole list.

**Epic Hero / named character / Unique** **[U]** — a specific individual from the setting. Universally
limited to one per list, and universally barred from generic upgrades. 40k: Epic Heroes, once each
`[secondary]`. Age of Sigmar: the UNIQUE keyword, once each and never reinforced `[secondary]`.
Kings of War: the **[U]** suffix on a unit entry, once per list regardless of how many battalions
`[secondary]`. Infinity: characters are AVA 1 `[secondary]`.

**Enhancement** **[1, 40k 11th]** — a purchasable upgrade from the detachment, given to a Character,
capped per army by battle size `[secondary]`. The equivalents elsewhere are Age of Sigmar's heroic
traits and artefacts of power, and Kings of War's magic artefacts.

**Detachment** **[1, 40k]** — the rules package the army is built inside, giving an army-wide
ability, stratagems and a list of enhancements. In 11th edition each detachment has a **Detachment
Points** cost of 1 to 3, and the army has a DP budget set by battle size, so several detachments can
be combined `[secondary]`.

**Force organisation chart** **[historical / genre term]** — the older mechanism, in 40k up to 8th
edition and in many other games, of slots by role: so many HQ, so many Troops, so many Elites. The
current 40k and Age of Sigmar editions have abandoned slot charts. Kings of War 4th edition uses a
descendant of the idea — five unit types (Core, Auxiliary, Specialist, Support, Commanders) where
Core units *unlock* the others `[secondary]`. Grimdark Future names its optional caps
"Force Org." explicitly `[primary]`. The caller should expect the phrase to mean "the structural
rules of the list", not one specific mechanism.

**Regiment** **[1, Age of Sigmar 4th]** — a hero plus up to three other units; the army is 1 to 5 of
them; the general's regiment may hold four `[secondary]`. Doubles as a deployment unit.

**Battalion** **[1, Kings of War 4th]** — the structural block: at least two Core and one Commander
to open one, at least four Core before a second may be started `[secondary]`.

**Battleline** **[1, 40k]** — the tag on rank-and-file units; in 11th edition Battleline units may
be duplicated more often than others (six at Strike Force, four at Incursion) `[secondary]`. Age of
Sigmar 4th deliberately removed the equivalent category `[secondary]`.

**Dedicated Transport** **[1, 40k]** — a vehicle bought to carry a specific unit; in 11th edition
capped at six per army regardless of battle size `[secondary]`.

**Reinforced unit** **[1, Age of Sigmar 4th]** — a unit taken at double models for double points,
once only `[secondary]`.

**Combined unit** **[1, Grimdark Future]** — two copies of the same multi-model unit merged into
one, permitted only if upgrades that apply to all models are bought for both; counts as one unit for
the copy limit `[primary]`.

**Auxiliary unit** **[1, Age of Sigmar 4th]** — a unit outside any regiment. Legal, but each one
after the first adds a cumulative 20-point surcharge, and the player with fewer auxiliaries gains a
command point each battle round `[secondary]`. A rare and interesting case: a soft, priced
constraint rather than a hard limit.

**Allies / coalition / Regiments of Renown** **[M]** — units from outside the faction. Age of Sigmar
4th allows one **Regiment of Renown**, a pre-built regiment whose units cannot use the faction rules
of the army they are allied into `[secondary]`. Kings of War 4th **removed** allies entirely
`[secondary]`. Malifaux allows out-of-faction hiring only through specific effects, and charges for
out-of-keyword hiring within the faction `[primary]`. 40k handles allies through specific faction
rules rather than a general mechanism, with restrictions such as allied units being barred from
being the Warlord `[secondary]`.

**Availability (AVA)** **[1, Infinity]** — a number on each unit profile capping how many of that
unit the list may contain; can be "Total", meaning unlimited `[primary/secondary]`.

**SWC — Support Weapons Cost** **[1, Infinity]** — a *second, parallel budget* alongside points,
earned at 1 SWC per 50 army points, spent on heavy and special weapons `[primary]`. The clearest
example anywhere of a list needing to satisfy two independent budgets at once.

**Combat group** **[1, Infinity]** — the list is capped at 15 troopers, and troopers are organised
into groups of at most 10 `[primary]`. A partition constraint on top of a count constraint.

**Open information / private information** **[1, Infinity]** — parts of a list are secret from the
opponent. The **Complete Army List** holds everything; the **Courtesy Army List** holds only the
open information and is what an opponent may be shown, and then only after deployment `[primary]`.
A list is therefore not one document but two projections of one.

**Crew** **[1, Malifaux]** — the skirmish equivalent of an army list: a leader, the leader's totem,
and models hired against a soulstone budget `[primary]`.

**Totem** **[1, Malifaux]** — a model bound to a specific master; must be hired if that master is in
the crew `[primary]`.

**Versatile** **[1, Malifaux]** — a characteristic marking models that any crew in their faction may
hire without paying the out-of-keyword surcharge `[primary]`.

**Model limit** **[1, Malifaux]** — the per-model cap on copies in a crew `[primary]`.

**Title** **[1, Malifaux]** — an alternate version of a named character; a crew containing a model
with a title cannot hire models of the same name with a different title `[primary]`.

**Battlepack / battleplan / mission / scenario** **[U]** — the mission being played. Relevant here
because the mission sometimes sets the points limit, and in Malifaux is known *before* the crew is
hired.

**Faction terrain** **[1, Age of Sigmar]** — a terrain piece the army may include, at no points cost
`[secondary]`.

**Battlescroll / balance dataslate / Munitorum Field Manual / errata / FAQ** **[U, names vary]** —
the publisher's periodic corrections. 40k points live in the **Munitorum Field Manual** and are
revised by balance dataslates `[secondary]`. Age of Sigmar uses **battlescrolls**. Any list is
valid only against a stated version of these.

**Legends** **[1, GW]** — units moved out of the current supported range but still given rules.
Commonly banned by tournament packs `[primary, event pack]`.

**Rules cut-off date** **[T]** — the date after which newly published rules do not apply at an
event. The WTC 2026 pack sets one explicitly, ahead of the list submission deadline `[primary]`.

**List submission** **[T]** — handing the list to the organiser by a deadline, usually through an
event platform (Best Coast Pairings is the common one) `[primary]`.

**List checking** **[T]** — validation by opponents or by the organiser after submission
`[primary]`.

**WYSIWYG** **[T/C]** — the model shows the wargear the list claims `[primary]`.

**Proxy / counts-as** **[C]** — using a model to represent a different one. Normal in casual play,
usually restricted at events.

**Sideboard** **[C, and mostly absent]** — a reserve of models swapped between rounds. Not a feature
of any of the published rules examined; Infinity's two-list system is the closest legitimate
equivalent `[primary]`.

**Rule of Three** **[historical T → now P in 40k]** — the convention, then tournament rule, then
published rule, that no more than three of any one datasheet may be taken. In 40k 11th edition it
has been absorbed into the core rules as a duplicate cap that varies by battle size `[secondary]`.
A good illustration of the migration path: convention → tournament pack → published rule.

---

## 3. What makes a list legal

The critical distinction the caller asked for is **scope**. There are four, not two:

1. **Local — one unit.** Checkable with only that unit in hand.
2. **Global — the whole list.** Requires the full list.
3. **Structural — one block within the list** (a 40k detachment, an Age of Sigmar regiment, a Kings
   of War battalion). Intermediate scope; a constraint may be per-battalion in one system and
   per-army in another, and Kings of War explicitly has both: `[n]` limits are per battalion,
   `[U]` uniqueness is per list `[secondary]`.
4. **External — beyond the list.** Team composition rules (WTC: only one of each faction per team,
   evaluated by keyword `[primary]`), and rules spanning a player's *set* of lists (Infinity: one or
   two lists, and both must come from a single generic or sectorial army `[primary]`).

### 3.1 Local constraints (one unit)

| Constraint | Example | Layer |
|---|---|---|
| Legal model counts | Age of Sigmar: minimum size, or reinforced at exactly double, once `[secondary]` | P |
| Fixed size categories | Kings of War: Troop 10 / Regiment 20 / Horde 40 / Legion 60 `[secondary]` | P |
| Wargear per model | "this model may replace its X with Y" | P |
| Wargear scaled to unit size | "for every 5 models, one may take Z" | P |
| Champion/leader-only options | the unit's sergeant only | P |
| Mutually exclusive options | pick one of three loadouts | P |
| Attachment rules | 40k 11th: leader and support units attach to a bodyguard unit `[secondary]`; Malifaux: totem must be hired with its master `[primary]` | P |
| Reinforce/combine eligibility | AoS: some units may not be reinforced `[secondary]` | P |
| Enhancement eligibility | 40k: Characters only, not Epic Heroes `[secondary]` | P |

### 3.2 Global constraints (whole list)

| Constraint | Example | Layer |
|---|---|---|
| Points budget | every system | P |
| A *second* budget | Infinity SWC, 1 per 50 points `[primary]`; 40k Detachment Points `[secondary]` | P |
| Duplicate cap | 40k 11th: 2 at Incursion, 3 at Strike Force/Onslaught; doubled for Battleline; six Dedicated Transports `[secondary]`. Grimdark Future: 1+X copies, X = 1 per 1000 points `[primary]`. Infinity: AVA `[primary]`. Malifaux: model limits `[primary]` | P |
| Unique / 0-1 | named characters once (all systems) | P |
| Exactly one leader | one Warlord / General; Infinity: exactly one Lieutenant `[primary]` | P |
| Upgrade cap | 40k enhancements: 2 or 4 per army by battle size `[secondary]` | P |
| Concentration cap | AoS: no more than half the points on one unit `[secondary]`. Grimdark Future: no single unit over 35% of total `[primary]` | P |
| Unit-count cap | Grimdark Future: max 1 unit per 200 points; max 1 hero per 500 points `[primary]`. Infinity: max 15 troopers `[primary]` | P |
| Partition rules | Infinity combat groups of at most 10 `[primary]` | P |
| Structural minima | Kings of War: 2 Core + 1 Commander to open a battalion; 4 Core before a second `[secondary]` | P |
| Unlock chains | Kings of War: each Core unlocks one Auxiliary and one Specialist; each pair of Core/Specialist unlocks a Support and a Commander `[secondary]` | P |
| Faction coherence | every unit must belong to the chosen faction, expressed by keyword | P |
| Ally allowance | AoS: one Regiment of Renown `[secondary]`; Kings of War 4th: none `[secondary]` | P |
| Priced soft constraints | AoS auxiliary surcharge of 20 points cumulative `[secondary]`; Malifaux out-of-keyword +1 cost `[primary]` | P |
| Free inclusions | AoS: one faction terrain, no points `[secondary]` | P |
| Single-selection extras | AoS: one manifestation lore `[secondary]` | P |

Two properties of this table are worth the caller's attention. First, **a budget overrun and a
category violation are different failure kinds**: one is arithmetic on a total, the other is a
predicate over a collection. Second, **some constraints are priced rather than forbidden** — the
auxiliary surcharge and the out-of-keyword surcharge are not legality rules at all; they change the
cost function. A validator that only knows "legal/illegal" cannot express them.

### 3.3 Constraints added by tournament packs (T)

Verified from the packs themselves:

- A fixed battle size for the event, and a fixed round structure `[primary, WTC 2026; Grimdark
  Future 2025-26 pack]`.
- A **rules and release cut-off date** before the submission deadline `[primary, WTC 2026]`.
- **List submission by deadline**, through a named platform, in a named format — one surveyed pack
  requires the format of the official Warhammer 40,000 app and states that other formats will not be
  accepted `[primary]`.
- **Bans and allowances on content**: one pack allows Forge World units, bans Legends units and bans
  Fortifications `[primary]`; another requires official armies only and forbids mixing factions
  `[primary, OPR]`.
- **List checking duties** imposed on players `[primary, WTC 2026 and a singles pack]`.
- **Public release of all lists** before the event `[secondary, WTC schedule]`.
- **Painting and WYSIWYG requirements**, with a scored painting standard `[primary]`.
- **Team-level composition**: only one of each faction per team, decided by the final faction
  keyword `[primary, WTC 2026]`.
- **Physical materials**: at least two printed copies of the list, one for the opponent
  `[primary, OPR pack; Infinity ITS]`.
- **Event-level locks**: 40k 11th's Event Companion has players choose a single **Force Disposition**
  at submission, kept for the whole event `[secondary]`. Malifaux's current season makes events
  fixed-faction — one declared faction for the entire event, and the leader must be from it
  `[primary]`.
- **Organiser discretion is itself a rule**: the Grimdark Future pack states that the organiser must
  announce before the event whether a different army structure applies, such as not following the
  official Force Org, allowing army mixing, or permitting unofficial armies `[primary]`.

That last point is the important one for anyone generalising: in at least one system the tournament
layer can **switch off** a published structural rule.

### 3.4 Community convention (C)

Not written in any binding document, but expected:

- Bring a printed list and hand it over unasked.
- Don't build a list that is legal but reads as bad faith in a friendly game ("beer and pretzels"
  norms; the phrase "that's a tournament list" is a complaint, not a compliment).
- Proxies are fine among friends, cleared with the opponent, and disappear at events.
- Whole-model modelling honesty: no measuring advantage from how a model is posed or based.
- In systems with a hidden-information list, don't fish for the private half.
- "Rule of three" was community convention before it was a tournament rule and before it was a
  published rule. Expect other conventions to be on the same escalator.

### 3.5 Genuinely contested or ambiguous areas

State these as ambiguous rather than picking a side:

- **Duplicate counting for merged and split units.** Grimdark Future settles it in the text — a
  combined unit counts as one `[primary]`. Age of Sigmar's reinforced unit is likewise one unit. Not
  every system says so explicitly, and where it does not, players argue.
- **What "the same datasheet" means** when a unit appears under two faction entries, or when a
  character is available to two factions. The WTC pack has to legislate around exactly this for team
  composition — the same named character taken as part of two different factions counts differently
  `[primary]`.
- **Whether a list must spend all its points.** Every system examined permits spending less. Age of
  Sigmar 4th actively rewards it: 50 or more points under the limit gives an extra command point
  `[secondary]`. So "unspent points" is not an error and must not be reported as one.
- **Whether an attached character makes the host unit ineligible for something.** The 40k
  enhancement-per-unit reading comes from a transcription of the official app rather than from the
  published core rules PDF `[unverified]`. Treat as contested until the published text is in hand.
- **Where the rules actually live.** 40k 11th's core rules PDF references section 25 "Muster
  Armies", but the fullest army-construction detail circulating in the community is attributed to
  the official app rather than the free PDF `[unverified]`. Age of Sigmar's core rules point at the
  General's Handbook for army composition `[secondary]`. A system's "army building rules" are
  frequently not in its rulebook.

---

## 4. The states a list passes through

These are the states players and organisers actually distinguish. The names are mine where the
hobby has no fixed term; the transitions are real.

**1. Draft.** Incomplete and possibly illegal by construction — over points, missing a warlord, a
half-filled structure. Everything is mutable. Players keep many drafts, and versioning them by hand
("Necrons v7 final ACTUAL") is a known annoyance.

**2. Complete.** Every required choice is made. Not the same as legal.

**3. Legal.** Satisfies the published rules at a stated data version. Legality is always relative to
a version: a list legal on Monday can be illegal on Tuesday after a points change. The version is
part of the state, not metadata about it.

**4. Event-legal.** Also satisfies a specific event's pack: its battle size, its bans, its cut-off
date. A list can be legal and not event-legal, or event-legal at one event and not at another on
the same weekend.

**5. Submitted.** Handed to the organiser by the deadline. What freezes here is the whole content
of the list, plus, in current 40k, the chosen Force Disposition `[secondary]`, and in Malifaux the
declared faction for the event `[primary]`. What does not freeze: play decisions made per game
(deployment, mission-specific picks), and in Infinity, *which* of the submitted lists is used in a
given round.

**6. Checked / published.** Validated by the organiser or by opponents, and often published to all
attendees before the event `[secondary, WTC schedule]`. After publication the list is public
information and is studied by future opponents.

**7. Played.** During a game nothing about the list changes. What changes is game state — models
removed, resources spent. Worth stating for a modeller: a list is the *input* to a game, not the
game's state; the two must not be conflated.

**8. Between rounds.** The default across every system examined is that **nothing changes** — the
submitted list is the list for the whole event. The exceptions are specific and named:

- Infinity ITS: a player submits one or two lists and **chooses which to use at the start of each
  round, after learning the opponent, their faction, the table, and their own classified objectives**
  `[primary]`. Neither list may be edited during the event; the choice is between two frozen
  documents.
- Malifaux: the crew is hired fresh for every encounter, inside the encounter setup sequence
  `[primary]`. Between rounds the *faction* and often the *leader* are frozen while the rest of the
  crew is not. Some event formats freeze the crew too — one format states explicitly that crews are
  fixed for the event and cannot change between games `[primary]`.

So "revised between rounds" is not a general state. It exists in two of five systems, in two
different forms: choosing among pre-frozen alternatives (Infinity) and rebuilding within a frozen
envelope (Malifaux).

**9. Superseded.** A balance update lands; the list is now an artefact of a past data version.
Tournament results are only interpretable against the version they were played under, which is why
cut-off dates are written into packs `[primary]`.

**10. Retired / archived.** Kept as a record. Players re-import old lists into new editions
constantly, and the mapping is lossy — units are removed to Legends, options disappear, categories
change meaning.

Two observations about freezing worth handing on. First, **what freezes is not always the list**:
it can be the faction (Malifaux), the mission-deck choice (40k Force Disposition), or the pair of
lists (Infinity). Second, **the freeze point precedes the first game by days**, and the rules the
list was legal under are themselves frozen at an earlier date still.

---

## 5. Cross-system comparison

### 5.1 What every system has

Verified present in all six systems examined:

1. A **budget** (points, army points, soulstones) and a limit agreed before building.
2. A **faction** that filters which entries may be taken.
3. **Units** built from **models**, each unit backed by a **profile document** carrying its
   statistics, its options and its cost.
4. A **single nominated leader** for the force.
5. **Named individuals limited to one copy**, and normally barred from generic upgrades.
6. Some **cap on repetition** of ordinary units — by count, by availability number, or by ratio.
7. **Options bought onto units**, changing both capability and cost.
8. A **published cost list revised on a cycle independent of the rulebook**, so that a list is only
   valid against a data version.
9. A **physical dimension**: the list must be fieldable with models the player owns.

### 5.2 What most systems have, in varying form

1. **A structural layer between the army and its units** — 40k detachments, Age of Sigmar regiments,
   Kings of War battalions. Absent in Grimdark Future, Infinity and Malifaux, whose lists are flat.
   Where it exists, it carries its own budgets, minima and slot limits.
2. **A second currency alongside points** — Detachment Points in 40k, SWC in Infinity. Absent
   elsewhere. Where present, a list must satisfy two budgets independently.
3. **Character upgrade pools** — enhancements, artefacts, heroic traits. Capped globally, applied
   locally. Absent from Infinity and, in the hiring sense, from Malifaux.
4. **Named battle sizes that carry rules** — 40k, where the size sets the duplicate cap, the DP
   budget and the enhancement cap `[secondary]`. Elsewhere the points number carries nothing else.
5. **Allies** — one Regiment of Renown in Age of Sigmar, faction-specific allowances in 40k, priced
   out-of-keyword hiring in Malifaux, removed entirely from Kings of War 4th, and expressed as
   sectorial membership in Infinity.
6. **Unit-size mechanics beyond a free range** — reinforcing (Age of Sigmar), combining (Grimdark
   Future), fixed named sizes (Kings of War).
7. **An optional or organiser-switchable force-organisation layer** — explicit in Grimdark Future,
   where the caps are labelled optional in the rules and the tournament pack requires them
   `[primary]`.

### 5.3 What is unique to one system

- **Detachment Points as a spendable budget for rules packages** — 40k 11th `[secondary]`. Nothing
  else prices its structural choices in a second currency.
- **SWC, a weapons budget earned per 50 points** — Infinity `[primary]`.
- **A hard cap on total models (15) plus a partition into groups of 10** — Infinity `[primary]`.
- **Lists with hidden information, existing as two documents (Complete and Courtesy)** — Infinity
  `[primary]`. Every other system's list is fully open once shown.
- **Two lists carried, chosen per round after seeing the matchup** — Infinity ITS `[primary]`.
- **Hiring at the table, simultaneously and hidden, after the mission is known, then revealed** —
  Malifaux `[primary]`. This alone breaks any assumption that "a list is built before an event".
- **A leader keyword as the primary content filter, with a priced escape hatch** — Malifaux
  `[primary]`.
- **Cumulative surcharges for structural deviation rather than prohibition** — Age of Sigmar's
  auxiliary units `[secondary]`.
- **Unlock chains where taken units grant slots for other units** — Kings of War 4th `[secondary]`.
- **A concentration cap expressed as a fraction of the total** — Age of Sigmar (half) and Grimdark
  Future (35%) `[secondary/primary]`. Note the two express it differently.
- **Reinforcement as an exact doubling of both models and cost, once** — Age of Sigmar `[secondary]`.
- **Free faction terrain outside the points economy** — Age of Sigmar `[secondary]`.

### 5.4 Judgement on whether one engine can serve several systems

This is the caller's real question, so it is stated plainly, with the reasoning visible.

What generalises well: budgets and totals; a catalogue of entries with costs; counting constraints
over sets (per list, per structural block); uniqueness; keyword-based eligibility tests; option
trees on units; validation as a set of predicates producing errors and warnings; versioned data.

What generalises badly:

- **Multiple simultaneous currencies** with different earning rules (SWC is *derived from* the
  points limit, not spent from it).
- **Cost functions that depend on the rest of the list** — Age of Sigmar's cumulative auxiliary
  surcharge, Malifaux's out-of-keyword +1. Cost stops being a property of the entry.
- **Unlock chains**, where legality is a flow problem over the list rather than a count.
- **Structure with its own nested budgets** — a 40k detachment carries points, a DP price, an
  enhancement pool and eligibility rules at once.
- **Hidden information**, which makes "the list" two different documents for two different audiences.
- **Building at the table**, which puts list construction inside the game's setup sequence and makes
  mission information an input to it.
- **A tournament layer able to disable published rules** — so the rule set applied is (published
  rules ⊕ event overrides), not a fixed program.

The honest summary: a generic engine can serve the *counting and budgeting* core of all six systems.
It will need per-system extension points for cost functions, for structural nesting, for
multi-currency budgets, and for the information model (open/private, per-round choice). Whether that
is one engine with adapters or several engines sharing a catalogue format is a software judgement I
am not making — but the domain does not present six variations of one shape. It presents one shared
core with at least four genuinely different outer layers.

---

## 6. Where catalogue data comes from

"Catalogue data" here means the machine-readable facts a builder needs: every unit, its legal sizes,
its options with their restrictions, its keywords, its cost, and the structural rules.

### 6.1 Publisher-operated tools

- **Games Workshop, Warhammer 40,000 app.** Free to download; contains an army builder branded
  **Battle Forge**; datasheets update as they change; codex content is unlocked with a code printed
  in the physical book `[secondary]`. It supported three game sizes at 1000 / 2000 / 3000 points at
  the previous edition's launch `[secondary]`. At least one tournament pack requires lists in this
  app's export format and advises players to disable app updates on the rules cut-off day
  `[primary]` — a strong signal that the publisher tool is the de facto canonical format at events
  even where third-party builders are used to construct the list. Reports that full list building
  sits behind a subscription tier are `[unverified]` here.
- **Mantic Games, Mantic Companion.** Free official Kings of War list builder; Mantic has moved its
  free rules there as living rulebooks `[secondary]`. This is the friendliest publisher posture of
  the six.
- **Corvus Belli, Infinity Army.** Free official builder, and the ITS rules state it is **the only
  officially sanctioned army list management tool for ITS play** `[primary]`. Corvus Belli also
  publishes the rules themselves free on the official Infinity wiki `[primary]`.
- **Wyrd Games, Malifaux.** Rules published free at an official rules site with a public JSON API
  behind it `[primary, observed directly]`, plus official crew-builder apps `[secondary]`.
- **One Page Rules, Army Forge.** Free official web builder; the core rules are free PDFs; income
  comes from Patreon, expansions and miniatures rather than from rules access `[secondary,
  publisher's own site]`.

### 6.2 Community datasets

**BSData** is the significant one. Observed directly on 2026-08-27:

- It is a GitHub organisation of XML data repositories, originally authored for the BattleScribe
  application. Its own README says: "BSData organisation created this project. It's a GitHub
  repository of datafiles. Maintained by community, in no way endorsed by BattleScribe or any other
  company/publisher." `[primary]`
- The site describes BSData as "an open community of volunteers maintaining a wide range of
  datafiles for list-building software for tabletop miniature games" `[primary]`.
- Repositories exist for the current 40k edition: `BSData/wh40k-11e` and `BSData/wh40k-10e` both
  resolve `[primary, HTTP 200 on raw README]`.
- **No licence file is present at the root of `wh40k-11e`** under any of the usual names — LICENSE,
  LICENSE.md, LICENSE.txt and COPYING all return 404 `[primary, checked 2026-08-27]`. So the data is
  publicly readable but not, on the evidence I could gather, released under a stated open licence.
  Anyone planning to depend on it should check per repository and, ideally, ask the maintainers.
- The legacy distribution index at `battlescribedata.appspot.com/repos` still advertises
  `battleScribeVersion 2.03` and 114 repositories, and its listing is stale — it names
  `wh40k-9e` and "Warhammer: Age of Sigmar 3.0" and does not list the 10th or 11th edition
  repositories `[primary, fetched directly]`. The GitHub repositories are the live source; the old
  appspot feed is not.
- BattleScribe itself, the original consuming application, is widely described as unmaintained, and
  several successor apps consume the same data `[secondary]`. **New Recruit** states that it does
  not host the data files itself (with one exception) and downloads BSData directly from GitHub
  `[secondary]`, and carries a not-affiliated-with-Games-Workshop disclaimer `[secondary]`.

The practical shape of the ecosystem is therefore: **volunteers transcribe published rules into XML;
several independent front-ends consume that XML; the publishers operate their own competing tools.**
A third-party builder that does not want to transcribe rules itself has essentially one community
source per game, and inherits that source's release cadence, its errors and its licence ambiguity.

### 6.3 The legal position

Stated carefully, because this is where a wrong confident answer is expensive.

What I can source:

- Games Workshop's published Intellectual Property Guidelines require fan sites to be
  non-commercial, forbid copying text, artwork or imagery from official material, and state that
  fan sites must "not post rules or stats copied from any official Games Workshop material". They
  further state that individuals "must not create computer games or apps based on our characters and
  settings. These are only to be created under licence from Games Workshop." `[secondary — the
  primary page at warhammer.com is behind a CAPTCHA from this environment; text is quoted from a
  community reproduction and should be re-verified against the publisher's page before anyone relies
  on it]`
- Games Workshop's guidelines also state that they do not constitute approval, authorisation, or a
  waiver of legal rights `[secondary]`.
- Games Workshop has pursued enforcement against creators and small businesses, including a 2025
  action reported against a large number of them `[secondary]`.
- Corvus Belli, by contrast, publishes its rules free and names one sanctioned tool `[primary]`;
  Mantic publishes living rules and an official free builder `[secondary]`; Wyrd publishes its rules
  free on the open web with an API `[primary]`; One Page Rules publishes free rules and an official
  free builder `[secondary]`. Four of the five publishers examined are permissive about rules access;
  one is not.

What follows for a third-party builder, as domain fact rather than legal advice:

- Points values and rules text are the publisher's material. There is a genuine and much-argued
  question about whether a rule as a functional system attracts copyright, but its **expression**
  clearly does, and names and trade dress are separately protected. Community datasets sit in that
  grey zone knowingly; they survive largely by being non-commercial and by staying quiet.
- The risk profile varies by publisher, sharply. A tool serving Infinity, Malifaux, Kings of War and
  One Page Rules sits on published permissions and official free data. A tool serving Warhammer sits
  against explicit written guidance that says do not do this without a licence.
- The community datasets carry no licence I could find, so downstream reuse — especially commercial
  reuse — has no permission from the transcribers either, quite apart from the publisher.
- **This is not legal advice and I am not qualified to give it.** Any product decision here needs a
  lawyer, and the publisher-by-publisher difference is the first thing to put in front of them.

---

## 7. Sources

Publisher and official documents (primary):

- One Page Rules, *Grimdark Future — Core Rules v3.5.1* (PDF, current as of Aug 2026):
  https://onepagerules.com/resources — army building text quoted from the "Preparation" section.
- One Page Rules, *Grimdark Future — 2025-26 Tournament Pack v1.0.0* (PDF, "valid from September
  2025 until September 2026"): same resources page.
- Corvus Belli, *Infinity ITS Rules, Season 17* (PDF):
  https://downloads.corvusbelli.com/infinity/organized-play/its-rules-season-17-en-v1.pdf
- Corvus Belli, *Infinity Wiki — Army List* (N5 / N5.2): https://infinitythewiki.com/Army_List
- Wyrd Games, *Malifaux 4th Edition rules database* (and its public API):
  https://malifauxrules.com/ — sections 381 "G. Hire Crew", 232 "H. Reveal Crews", 354 "Encounters",
  139 "Model Limits", 231 "Totems", 138 "The Versatile Characteristic", 229 "Titles", 133 "Master",
  400 "Overview" and 442 "Choose Faction and Leader" (Gaining Grounds Zero season, published
  2026-03-06 per the API).
- WTC-Belgium, *WTC 2026 Team Event Pack, 11th Edition, v1.1* (June 2026):
  https://wtc-belgium.com/wp-content/uploads/2026/06/2026-WTC40K-11th-edition-Event-Pack-v1.1.pdf
- Prague GT 2026 Singles event pack (10th edition event, 2026):
  https://www.praguegt.com/assets/doc/Propozice-GT-2026-40k-SINGLES-latest.pdf
- BSData: https://github.com/BSData/wh40k-11e (README), https://www.bsdata.net/,
  https://battlescribedata.appspot.com/repos — all fetched 2026-08-27.

Rules mirrors and community sources (secondary):

- Wahapedia, *Warhammer 40,000 11th edition Core Rules* (section 25 "Muster Armies" referenced in
  the contents): https://wahapedia.ru/wh40k11ed/the-rules/core-rules/
- Wahapedia, *Age of Sigmar 4th edition Core Rules* and *General's Handbook 2025-26*:
  https://wahapedia.ru/aos4/the-rules/the-core-rules/ ,
  https://wahapedia.ru/aos4/the-rules/general-s-handbook-2025-26/ — source for the regiment,
  general, reinforced, unique, Regiment of Renown, auxiliary-surcharge, faction-terrain,
  manifestation-lore and half-points rules.
- Wargamer, *GW reveals Age of Sigmar army building rules for 4th edition*:
  https://www.wargamer.com/warhammer-age-of-sigmar/army-building-rules
- GrimSlate, *Warhammer 40K 11th Edition Army Composition Rules Explained*:
  https://grimslate.com/blog/army-composition-rules-11th-edition — source for the battle-size table,
  duplicate caps, Battleline and Dedicated Transport exceptions, enhancement caps.
- Warhammer Guild, *40k Detachment Points Explained (11th Edition)*:
  https://warhammerguild.com/guides/warhammer-40k-detachment-points-explained/
- Sprues & Brews, *Warhammer 40,000 11th Edition Core Rules Deep Dive* (2026-06-01):
  https://spruesandbrews.com/2026/06/01/warhammer-40000-11th-edition-core-rules-deep-dive/
- Mantic Games, *Kings of War 4th Edition: Building Armies*:
  https://www.manticgames.com/news/kings-of-war-4th-edition-building-armies/ — battalions, five unit
  types, unlock rules, `[n]` and `[U]` limits, removal of allies.
- Bell of Lost Souls / Spikey Bits on the 11th edition Event Companions and Force Disposition,
  June–August 2026.
- Games Workshop Intellectual Property Guidelines — reproduction at
  https://40kfan.com/games-workshop-intellectual-property-guidelines/ (the publisher's own page,
  https://www.warhammer.com/shop/Intellectual-Property-Guidelines, is CAPTCHA-gated from this
  environment and could not be read directly).

Explicitly unverified, listed so the caller does not mistake them for established fact:

- The precise 40k 11th-edition text on enhancements per unit and on roster construction, attributed
  in the community to sections 25.03–25.04 of the official app rather than the free PDF.
- The Onslaught battle size's Detachment Points budget.
- Whether full list building in the official Warhammer 40,000 app requires a paid subscription.
- Kings of War 4th-edition per-unit magic-artefact limits and its current points limits for
  tournament play.
- Any claim about how a court would treat community rules transcription.
