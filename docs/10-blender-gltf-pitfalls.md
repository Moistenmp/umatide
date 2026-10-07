# 10 — Blender → glTF export pitfalls (measured)

**Ten failure modes we hit exporting skinned, animated characters from Blender to glTF, with the
measurement that exposes each one.**

> **Scope.** No game data, no assets. Everything here is about tool behaviour and is reproducible
> with any rigged character.
> Markers: **VERIFIED** (measured, criterion given) / **UNVERIFIED**.

The common shape of these failures: **the export succeeds, the file validates, and the result is
wrong.** None of them raise an error.

---

## Summary

| # | Failure | Symptom | Marker |
|---|---|---|---|
| 1 | `export_optimize_animation_size` defaults **on** | most joint channels silently reduced to 2 keys | **VERIFIED** |
| 2 | `export_optimize_animation_keep_anim_armature / _object` | **armature animation disappears entirely** | **VERIFIED** |
| 3 | Time base is absolute | clip starts at t = start_frame / fps, not 0 | **VERIFIED** |
| 4 | Morph targets not filtered | 1.7 MB → 12.5 MB | **VERIFIED** |
| 5 | Addon reset ordering | `bpy.ops.<addon>.*` → "could not be found" | **VERIFIED** |
| 6 | Extension module name (4.2+) | "No module named ..." | **VERIFIED** |
| 7 | Action inspection API (4.4+) | falls through silently, reports nothing | **VERIFIED** |
| 8 | Half-open loop window | first pose ≠ last pose | **VERIFIED** |
| 9 | Operator keyword drift | `TypeError: ... keyword "x" unrecognized` | **VERIFIED** |
| 10 | Verifying the *set* of sample counts | a broken export passes the check | **VERIFIED** |

---

## 1 `export_optimize_animation_size` is on by default

**Symptom.** A clip that should key every joint every frame is exported with most channels
reduced to **two** keys, interpolated `STEP`.

**Measurement.** Count the number of samples per animation channel, grouped by target path:

```
path=rotation      sample counts {2: 422, 51: 13}     interpolation {STEP: 387, LINEAR: 48}
path=translation   sample counts {2: 435}             interpolation {STEP: 435}
path=scale         sample counts {2: 435}             interpolation {STEP: 435}
```

435 rotation channels exist; **13** are per-frame and **422** are constant-stubs.

**Fix.** Set `export_optimize_animation_size = False` explicitly.

**Why it is dangerous.** A per-frame contract is a *requirement* in some pipelines
(bake everything; the consumer does its own fitting). This option silently violates it.

---

## 2 `export_optimize_animation_keep_anim_armature` / `_object`

**Symptom.** With `export_optimize_animation_size = False` **and** these two flags set to `True`,
the exported file contains **one animated node with three channels**.

```
animation channels: 3        (rotation/translation/scale of a single node)
```

The skeleton's animation is gone.

**Fix.** Do not set them. **UNVERIFIED** what the underlying interaction is — recorded so it is
not re-attempted.

---

## 3 The time base is absolute

**Symptom.** The clip's first keyframe is at `start_frame / fps` instead of `0.0`. A consumer
that assumes t = 0 is a hard requirement sees a clip that starts late.

**Measurement.** `0.8667 … 2.5000 s` for a window that should be `0 … 1.6667 s`.

**Fix.** Shift every keyframe by `−start_frame` before export (and shift handles too), **or**
verify after export that `min(t) == 0`.

---

## 4 Morph targets are all-or-nothing

**Symptom.** A model with many shape keys produces an enormous file.

**Measurement.** Same model and clip:

| export | size |
|---|---|
| shape keys excluded | **1.7 MB** |
| shape keys included | **12.5 MB** |

**Consequence.** If you need morphs, filter them **before exporting** — do not "export everything
and let the consumer deal with it".

> **Note for this source family specifically.** A common intermediate recording format carries
> its full morph mapping table **on every frame regardless of value** — so "keep only the morph
> channels that are animated" is not a valid filter. The correct filter is
> **"keep only the channels whose value actually changes"** (see `08` §6).

---

## 5 Addon reset ordering

**Symptom.**

```
AttributeError: Calling operator "<addon>.<op>" error, could not be found
```

**Cause.** Calling `bpy.ops.wm.read_factory_settings()` **after** `addon_enable` unloads the
addon.

**Fix.** Reset first, **then** enable.

---

## 6 Extension module names (Blender 4.2+)

**Symptom.** `ModuleNotFoundError: ... No module named '<name>'` when enabling an addon by its
bare name.

**Fix.** Extensions are enabled as `bl_ext.<repository>.<name>`. Try both and report which one
worked in the log — do not assume.

---

## 7 Action inspection API (Blender 4.4+)

**Symptom.** Code iterating `action.fcurves` returns nothing and the tool reports *no results*
instead of an error. `action.id_root` no longer exists.

**Fix.** A **layered** action exposes its curves through:

```
action.layers[*].strips[*].channelbags[*].fcurves[*]
```

and `action.slots[*]` carries slot/ID-type information.

**Why it matters.** This is the same shape as the export bugs: **silent empty result**. A tool
that reports "0 matches" must be suspected before its conclusion is believed.

---

## 8 Loop windows must be closed intervals

**Symptom.** "First pose equals last pose" fails by a small but visible amount.

**Fix.** For a cycle of N frames, sample **N + 1** frames: `[start, start + N]` inclusive.

---

## 9 Operator keyword drift

**Symptom.** `TypeError: Converting py args to operator properties: keyword "x" unrecognized`.

**Cause.** Operator keyword sets differ between addon versions (`name=`, `scale=`, `types=`, …).

**Fix.** Pass the **minimum** keyword set (often just `filepath`), then configure the result
through the datablock API. When in doubt, read a call that already works in your own codebase
rather than guessing from documentation.

---

## 10 The verifier that blesses a broken export

**Symptom.** None — the check passes.

**What happened.** The verification script reported the *set* of sample counts observed across
channels:

```
sample counts (set): [2, 51]
```

`51` is present, so the check "every joint every frame" was marked ✓ — while **422 of 435
channels had 2 samples**.

**Fix.** Verify **per channel**, and report the **distribution** ("how many channels have 51
samples / how many have 2"), not the set of observed values.

> This is the single most transferable lesson in this document. The bug in the exporter was
> invisible to a check that summarised instead of enumerated.

---

## A note on how these were found

Every item above was found by **measuring the produced artefact**, not by reading the tool's
documentation or trusting the tool's own log. In several cases the exporting tool's log looked
entirely normal, and the script's own console output said the operation succeeded.

**If a claim in the pipeline has not been re-measured on the artefact, treat it as unverified.**

**Status: testing.** These are measured behaviours of specific Blender versions; behaviour may
differ on others.
