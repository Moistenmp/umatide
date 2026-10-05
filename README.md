# umatide

**A toolchain for importing external character models into Darktide.**

Status: **personal / early.** Not a finished mod, and not a "drop-in model replacement".

What it actually contains is the part that is usually missing: **how to get an external model
into this engine family at all** — the unit resource format, the engine's name-addressability
requirement, skeleton completeness, and **a record of the approaches that do not work**.

---

## 1. The problem this addresses

Darktide runs on the Stingray/Bitsquid engine family. Importing an external character model
(for example a model originating from a PMX/MMD workflow) is **not primarily a coding problem**.
The hard part is that **nobody has published the format and the conventions**:

- the binary layout of a unit resource (sections, name hashes, the local transform block)
- a convention of this engine family: **attachment points and bone names must be addressable**
  (the equivalent of a `$attachment` declaration in Source-engine models)
- **skeleton completeness**: a missing bone name means the engine's own weapon animation,
  foot IK and hand IK **have nothing to act on**
- **which approaches have already been tried and disproven** (runtime IK compensation,
  re-parenting, renaming bones)

This repository turns the above into **checkable facts**, and will gradually add
**parameterized tools**.

---

## 2. Layout

```
docs/
  01-unit-format.md            Unit resource format: sections, hashes, local transform block, name resolution
  02-skeleton-completeness.md  What missing bone names actually break (three systems resolve names)
  03-falsified-paths.md        Approaches already disproven — with evidence and criteria
  04-cross-engine-ref.md       Comparison with the sibling engine family's conventions
  05-reproduce.md              Minimal reproduction recipe, marked verified / unverified
  zh/                          Chinese originals of the above (working notes, kept as-is)
tools/                         Parameterized tools — **not ready yet**, see below
NOTICE.md                      Copyright and scope boundaries — **read this first**
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

1. Read `NOTICE.md` first (scope).
2. Read `docs/01-unit-format.md` (the format facts you will need).
3. Read `docs/03-falsified-paths.md` — **this one saves the most time.** It is the list of
   roads already walked and closed.
4. Then use `docs/05-reproduce.md`, paying attention to the `verified` / `unverified` markers.

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
