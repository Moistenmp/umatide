# umatide

**An independent Darktide mod that hands an external character model to the engine, instead of
replacing the game's model at runtime.**

Status: **personal / early.** The mod scaffold exists and its single switch is off by default.

## 0. Read this before trusting anything here

**We are in the testing stage, and we have not fully absorbed the community toolchain.**

That is not a formality. Two concrete things happened while writing these docs:

1. **We were running an out-of-date build of the official toolchain** (compiler + Blender addon
   dated 2026-09-30) while its README had already grown a whole section —
   *"Replacing the game's own units"* — and the newer addon ships an operator called
   **`Import Game Unit Nodes`** that does, as a button, the exact thing three of our documents
   describe as hard: bring in **every node of the unit being replaced, named and placed like
   the game's**, including hash-only nodes (`#1234abcd`). Its implementation is
   `addon/darktide_assets/game_unit.py`, and the module docstring states the reason plainly:
   the game finds attach points, effect points and animated nodes **by name**, so a replacement
   unit has to carry the same names in the same places.

2. **Our own asset failed the newer addon's parser and the compiler's validator.** At the time,
   `_parse_bones` rejected our `.bones` with `BONES LOD table is invalid`, and `--validate`
   reported `invalid` with `synthetic UNIT root SceneGraph linkage changed`.

   **⇒ ⚠ Status update (2026-10-08): both of those now pass.** Re-measured on the current build:

   ```
   --validate  ⇒ valid UNIT v115 ｜ 9 packed mesh primitive(s) ｜ 9 skinned
                 ｜ 318 SceneGraph node(s) ｜ 9 material slot(s)
                 ｜ 20 physics actor(s) (20 in PhysX collection)
                 ｜ simple animation 256 track(s) ｜ 1,199,942 bytes
   _parse_bones ⇒ parses cleanly
                 (['root_point', 'j_hips_transform', 'j_hips', 'j_leftupleg',
                   'j_leftleg', 'j_leftfoot', 'j_lefttoebase', 'toe_l', …])
   ```

   **The two blockers recorded here on 2026-10-07 no longer hold**, and the self-assessment that
   followed from them was therefore too pessimistic. What replaced the old failure mode is a real
   constraint rather than a malformed asset — see §7 and the note on the two goals below.

**⇒ So treat these docs as:** notes on *what the engine family requires and why the two goals
conflict* — which we believe still holds — **not** as a claim that we have found the best or the
complete way to do it. Where a statement here conflicts with the current toolchain's behaviour,
**the toolchain is right.**

### 0.0 What this mod does, and how it differs from the community replacements

The community replacements we have taken apart — `SimplySimpleDogReplacer`, and the Citlali
script our own attach layer was aligned to — all work the same way: wait for the game to spawn
the original unit, hide it, spawn a **separate** purely visual unit beside it, and copy the
transform every frame. That visual unit is spawned with `spawn_with_extensions = false`, so it
receives **no gameplay extensions at all** — no animation system, no visual loadout, no attach
points — and the mod has to drive every one of those itself. That is why those mods are large:
the dog replacer carries 884 lines of animation code and 80 KB of visual plumbing.

This mod takes the opposite route. Before any player unit is spawned, it points the player's own
rig resource,

```
content/characters/player/human/third_person/base
```

— the `base_unit` from `scripts/settings/breed/breeds/human_breed.lua` — at **our** unit, using
`SimpleAssets.replace_unit`. The player's own spawn chain then loads our model, and because that
chain carries a `unit_template`, the extension manager appends the **full player extension set**
on top of it. Animation, visual loadout, aim and locomotion come from the game rather than from
us. The whole implementation is one call.

Keeping the model while letting the engine drive it is the point. We are not trying to copy the
original animations onto our skeleton; we are trying to have the engine play them, on our
proportions, because that is the only version that scales to more than one model.

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
| **Applying external motion to a skeleton whose proportions are ours** | ❌ not covered | **the derivable part of the gap.** The formula, the metric trap, and the measured improvement — `07-retargeting-math.md` |
| Which approaches are structurally impossible (not merely untried) | ❌ not documented elsewhere | `03-falsified-paths.md` §P, `07-retargeting-math.md` §7 |

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
umatide.mod                    DMF entry point (new_mod + mod_script / mod_data / mod_localization)
info.json                      Mod metadata and prerequisites (DMF, SimpleAssets, CustomAssets)
scripts/mods/umatide/
  umatide.lua                  The whole mod: one SimpleAssets.replace_unit call, behind a switch
  umatide_data.lua             Settings (rig_replace, default off)
  umatide_localization.lua     Strings (en + zh-cn)
assets/units/                  The compiled model — **not tracked**, see §6 and .gitignore

docs/
  06-toolchain-landscape.md    ★ START HERE: what the existing toolchain covers, and where this repo sits
  01-unit-format.md            Unit resource format: sections, hashes, local transform block, name resolution
  02-skeleton-completeness.md  What missing bone names actually break (three systems resolve names)
  03-falsified-paths.md        Approaches already disproven — with evidence and criteria
  04-cross-engine-ref.md       Comparison with the sibling engine family's conventions
  05-reproduce.md              Minimal reproduction recipe, marked verified / unverified
  07-retargeting-math.md       ★ Applying external motion to our skeleton — the derivation,
                               the measurement trap, and what is not yet established
  08-source-animation-limits.md   Source-side native-animation limits (muscle-clip only,
                               relay bone ceiling, frame-0 artifact)
  09-source-rig-facts.md       Skeleton shape (435/199/236), family table, three traps
  10-blender-gltf-pitfalls.md  Ten measured Blender->glTF export failures, all silent
  11-stage-closeout-…          Where the Darktide side of the work stands
  12-verification-channel-freeze-and-audit.md   Which verification channels are trustworthy
  zh/                          Chinese originals of docs 01–05 (working notes, kept as-is)
tools/                         Parameterized tools — **not ready yet**, see below
NOTICE.md                      Copyright and scope boundaries — **read this too**
```

> **`tools/` is intentionally empty for now.**
> The prototypes were written for a single model (hardcoded model names and paths).
> Publishing them as-is would only produce scripts nobody can follow.
> They will be added once they are configuration-driven — **swapping in another model
> should not require editing code.** Better late than misleading.

> **⚠ The `assets/` directory is not empty on a working install, but it is not tracked.**
> The compiled `.unit`, `.bones` and `.animation` files are produced by the compiler and stay
> out of the repository, in line with the scope policy in §7 — see `docs/05-reproduce.md` for how
> to build them. The mod will load without them; it will simply have nothing to point at, and its
> one switch is off by default.

---

## 3. Status, honestly

| Item | Status |
|---|---|
| Unit resource layout (sections, hashes, name resolution) | ✅ verified byte-by-byte |
| The name-addressability convention | ✅ verified, incl. cross-engine comparison |
| Consequences of an incomplete skeleton | ✅ verified (offline + matches observed in-game behavior) |
| List of disproven approaches | ✅ has in-game evidence |
| **Applying external motion to our skeleton (the formula)** | ✅ **derived and measured offline** — `07-retargeting-math.md`. The naive formula is missing the parent's world delta; adding it cuts direction error by ~half (mean ↓31%, max ↓53%) |
| **Which error metric to use** | ✅ **orientation error is dominated by roll and is misleading**; direction error is the one to use. Measured: a bone the orientation metric calls 149.81° wrong is 7.38° wrong in direction |
| **Third-person weapon placement** | ⚠️ **not finished** — see `docs/05-reproduce.md` §4 |
| **The retarget formula's own invariant check** | ⚠️ **not yet passed** — at bind the result should reproduce the bind local rotation; our check aborts before that, so the formula is "measured better", not "proved" |
| **Attributing the residual error (direction vs roll)** | ⚠️ **not done** — the equation constrains direction only; roll needs its own convention |
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


---

## 7. Scope and limitations · 范围声明

> **原文（中文）**
>
> 由于本人的开发经验不足和技术判断有部分偏差，我的这些解法很多时候都走了大量试错，所以我能提供的只有一个验证过的通道，而非技术上的唯一解法
>
> **English (machine translation)**
>
> Due to my limited development experience and some deviations in my technical judgement, many of these solutions went through a great deal of trial and error, so what I can provide is only one verified path, not the only technical solution.

**⇒ Applies to the whole repository.** What the documents here record is **one verified path
through this problem — established by trial and error, not derived as the unique answer.**
Where a claim is a measurement, the criterion for re-checking it is given next to it;
where a claim is a judgement, read it as this author's judgement and not as a general law.

**⇒ 适用于全仓库。** 这里的文档记录的是**一条被验证过的通道**——它是试错走出来的，
**不是被证明为唯一的解法**。凡属测量的结论，旁边都给了复算判据；
凡属判断的结论，请当作作者当时的判断，而不是一般规律。

