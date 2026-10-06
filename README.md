# umatide

**A toolchain for importing external character models into Darktide.**

Status: **personal / early.** Not a finished mod, and not a "drop-in model replacement".

## 0. Read this before trusting anything here (added 2026-10-07)

**We are in the testing stage, and we have not fully absorbed the community toolchain.**

That is not a formality. Two concrete things happened while writing these docs:

1. **We were running an out-of-date build of the official toolchain** (compiler + Blender addon
   dated 2026-09-30) while its README had already grown a whole section —
   *"Replacing the game's own units"* — and the newer addon ships an operator called
   **`Import Game Unit Nodes`** that does, as a button, the exact thing three of our documents
   describe as hard: bring in **every node of the unit being replaced, named and placed like
   the game's**, including hash-only nodes (`#1234abcd`).
2. **Our own asset fails the newer addon's parser**: `_parse_bones` rejects our `.bones` with
   `BONES LOD table is invalid`. The compiler's `--validate` had already flagged our unit as
   `invalid` (`synthetic UNIT root SceneGraph linkage changed`). So **the asset this repo
   describes is not a well-formed unit by the toolchain's own standards** — it loads, but it is
   not something we can call "correct".

**⇒ So treat these docs as:** notes on *what the engine family requires and why the two goals
conflict* — which we believe still holds — **not** as a claim that we have found the best or the
complete way to do it. Where a statement here conflicts with the current toolchain's behaviour,
**the toolchain is right.**

---

## 0.1 Where this can actually help the community (honest placement)

| Area | Covered by the community toolchain | What is left, and what we can contribute |
|---|---|---|
| Importing a model / bone names / scene nodes | ✅ covered (`Import Game Unit Nodes`, compile against a reference skeleton) | **nothing to add** — use the tool |
| Hiding the vanilla character, replacing look | ✅ covered (`set_unit_objects_visibility`, item data) | **nothing to add** |
| Effects, particles, game shaders, dangle/jiggle bones, visibility groups | ✅ covered by the newer addon (particles, shaders, dangle/jiggle, visibility groups) | **nothing to add** — our earlier hand-rolled attempts here were wasted work |
| Keeping the model's **own proportions** | ❌ deliberately cut off by the toolchain (the fit workflow warps the model) | **this is the gap.** What the engine forces on you, why it conflicts, and which compensations are already disproven — `03-falsified-paths.md` |
| Contact points under goal B (feet, hands, weapon) | ❌ not covered | partial results only: the rigid-translation foot correction works (measured); the weapon contact point is **not finished** |
| Unit-format facts, name-addressability, the `skin.joints ≤ 256` budget | ❌ not documented elsewhere | `01-unit-format.md`, `02-skeleton-completeness.md` |

**⇒ The honest one-line placement:** the toolchain solves *"get a model in"*; these docs are only
about *"get a model in **without adopting the game's proportions**"* — and on that road we have
**one working correction and one open problem**, not a solution.

---

What it actually contains is the part that is usually missing: **how to get an external model
into this engine family at all** — the unit resource format, the engine's name-addressability
requirement, skeleton completeness, and **a record of the approaches that do not work**.

---

## 1. The problem this addresses

**Read `docs/06-toolchain-landscape.md` first if you are here to get a model into the game.**
It maps what the existing toolchain already covers, and states plainly which goal this repository
is about — so you can pick the shorter path if it fits you.

Darktide runs on the Stingray/Bitsquid engine family. There are **two different goals** when
putting an external character model in:

| Goal | Status |
|---|---|
| **A. Use the game's skeleton** — fit the model to it | **already covered by the existing toolchain** (import → Blender → compile against a reference skeleton → register). Everything lines up: weapon, feet, IK. Proportions become the game's. |
| **B. Keep the model's own proportions** | **not covered — this is what these docs record.** The model keeps its proportions, and the name-driven engine systems and the weapon contact points no longer line up automatically. |

**⇒ This repository is about goal B.** It is not a claim that hand-editing is the only route.

What goal B forces you to deal with, and what we found while doing so:

- the binary layout of a unit resource (sections, name hashes, the local transform block)
- the engine family's convention that **attachment points and bone names must be addressable**
- **why the two goals conflict at all** — the weapon's visible mesh is bound to the game
  character's skeleton, so a model with different proportions cannot receive it by moving things around
- **which approaches have already been tried and disproven** (runtime IK compensation,
  re-parenting, renaming bones), with the measurements behind each

---

## 2. Layout

```
docs/
  06-toolchain-landscape.md    ★ START HERE: what the existing toolchain covers, and where this repo sits
  01-unit-format.md            Unit resource format: sections, hashes, local transform block, name resolution
  02-skeleton-completeness.md  What missing bone names actually break (three systems resolve names)
  03-falsified-paths.md        Approaches already disproven — with evidence and criteria
  04-cross-engine-ref.md       Comparison with the sibling engine family's conventions
  05-reproduce.md              Minimal reproduction recipe, marked verified / unverified
  zh/                          Chinese originals of docs 01–05 (working notes, kept as-is)
tools/                         Parameterized tools — **not ready yet**, see below
NOTICE.md                      Copyright and scope boundaries — **read this too**
```

> **`tools/` is intentionally empty for now.**
> The prototypes were written for a single model (hardcoded model names and paths).
> Publishing them as-is would only produce scripts nobody can follow.
> They will be added once they are configuration-driven — **swapping in another model
> should not require editing code.** Better late than misleading.

---

## 3. Status, honestly

| Item | Status |
|---|---|
| Unit resource layout (sections, hashes, name resolution) | ✅ verified byte-by-byte |
| The name-addressability convention | ✅ verified, incl. cross-engine comparison |
| Consequences of an incomplete skeleton | ✅ verified (offline + matches observed in-game behavior) |
| List of disproven approaches | ✅ has in-game evidence |
| **Third-person weapon placement** | ⚠️ **not finished** — see `docs/05-reproduce.md` §4 |
| Parameterized toolchain | ⚠️ **not ready** |
| Model asset conversion pipeline | ⚠️ **not ready** |

**⇒ This repository ships no game assets, no decompiled source, and no model assets. See `NOTICE.md`.**

---

## 4. If you want to reproduce this

1. Read `docs/06-toolchain-landscape.md` — **decide whether you actually need goal B first.**
   If the game's proportions are acceptable to you, the existing toolchain is the shorter path.
2. Read `NOTICE.md` (scope).
3. Read `docs/01-unit-format.md` (the format facts you will need).
4. Read `docs/03-falsified-paths.md` — **this one saves the most time.** It is the list of
   roads already walked and closed.
5. Then use `docs/05-reproduce.md`, paying attention to the `verified` / `unverified` markers.

**⇒ Provided as-is, with no support commitment.** If you hit a problem while reproducing this,
please open an issue with **what you observed and your logs** — observations are worth more than
conclusions here.

---

## 5. On how this was produced

Parts of this work were developed with AI assistance (reverse engineering, scripts, documentation).
**The factual claims are meant to be independently checkable** — each conclusion carries its
criteria where possible (byte offsets, measured values, observed behavior, algebra).

If you find a claim that **does not hold**, say so and bring your evidence.
**We would rather have facts that survive scrutiny than a tidy story.**

---

## 6. Licensing

| Content | License |
|---|---|
| **Documentation** (all `.md` files) | **CC BY 4.0** — reuse and adapt freely, including commercially, **with attribution** |
| **Code** (`tools/`, when it appears) | **MIT** |

**⇒ See `LICENSE` and `LICENSE-CODE`.**
**⇒ Neither license grants any rights to the game, its assets, or any third-party model or asset —
see `NOTICE.md`.**

**Suggested attribution:** *Based on "umatide" documentation — https://github.com/Moistenmp/umatide — CC BY 4.0.*
