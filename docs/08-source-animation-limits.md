# 08 — Source-side animation limits

**What you can and cannot lift out of this source game family, and the criteria for each claim.**

> **Scope.** This document describes the *source* side of the pipeline: a character model
> originating from a PMX/MMD-style workflow. It contains **no game data, no extracted assets,
> and no keys** — only observations, measurements, and the criteria to re-check them.
>
> Every claim carries a marker: **VERIFIED** (measured by us, criterion given) or
> **UNVERIFIED** (stated for completeness, not yet checked).

---

## 1 Summary

| # | Claim | Marker |
|---|---|---|
| 1 | Native character/face/accessory animations are stored as **muscle clips**; the generic transform-curve arrays are empty | **VERIFIED** |
| 2 | ⇒ Native animation is **not offline-readable** without re-implementing the engine's humanoid solving | **VERIFIED** |
| 3 | The VMD relay path has a **hard bone ceiling** — accessory bones can never be carried | **VERIFIED** |
| 4 | Frame 0 of a relay recording is a **recorder artifact**, not animation | **VERIFIED** |
| 5 | "Non-humanoid bones must therefore be stored as readable curves" | **FALSIFIED** |
| 6 | "Facial expressions are captured by the relay" | **FALSIFIED** |
| 7 | "A database table supplies the expression→accessory mapping" | **FALSIFIED** |

---

## 2 Claim 1 — native animations are muscle clips

**Method.** Read `AnimationClip` objects out of the source bundles and inspect the six generic
curve arrays and the muscle block.

**Result.** For every clip sampled — body, facial, and accessory — all six arrays are empty:

```
m_FloatCurves    len=0      m_RotationCurves len=0     m_ScaleCurves  len=0
m_PositionCurves len=0      m_EulerCurves    len=0     m_PPtrCurves   len=0

m_MuscleClip:  IndexArray=200   ValueArrayDelta=419  (body)
               IndexArray=200   ValueArrayDelta=36   (facial)
               IndexArray=200   ValueArrayDelta=24   (accessory)
```

**Criterion.** Re-read any `AnimationClip` from the source bundles and check that
`m_FloatCurves`, `m_PositionCurves`, `m_RotationCurves`, `m_EulerCurves`, `m_ScaleCurves`,
`m_PPtrCurves` are all length 0 while `m_MuscleClip` is populated.

**Consequence.** A converter must either (a) run inside a live engine instance and sample the
posed transforms, or (b) re-implement muscle-space → transform solving, which depends on the
character's avatar description. **(b) is not a small job and is not attempted here.**

---

## 3 Claim 3 — the relay's hard bone ceiling

**Method.** Record a motion through a runtime viewer's VMD export, then list the bone names
present in the resulting file and intersect them with the model's actual skeleton.

**Result.**

| | count |
|---|---|
| Bones in the model | **435** |
| Bone names present in the recording | **52** |
| Accessory bones present in the recording (tail / hair / skirt) | **0** |

The 52 names correspond exactly to the recorder's **fixed mapping table** (62 entries; the
remainder do not exist in this model).

**Criterion.** List the bone names in any recording produced this way. The set is constant
regardless of motion, and contains no accessory bones.

**Consequence.** **Accessory motion cannot be captured through this path at all.** It must be
authored — see `09-accessory-motion.md`. This is a property of the tool, not a missing step.

---

## 4 Claim 4 — frame 0 is an artifact

**Method.** Compare two candidate loop windows for the same recording, scoring by the
**maximum per-bone angular difference** between the first and last frame of the window.

**Result.**

| window start | max per-bone seam |
|---|---|
| frame **0** | **11.7477°** |
| frame **15** | **0.0543°** |

**Criterion.** Compute the per-bone quaternion difference between the window's first and last
frame and take the maximum.

> **Methodological note — this one cost us a wrong result.**
> The same recording scored **0.02° mean** pose difference at the frame-0 window. The mean
> hides "most bones agree, a few disagree a lot". **Use the maximum, not the mean**, when
> choosing a loop window. A mean-based criterion reported a clean loop that was not one.

---

## 5 Claim 5 (FALSIFIED) — "non-humanoid bones must be stored as readable curves"

**Reasoning that was wrong.** Accessory bones are not part of a humanoid rig, so their animation
*should* have to be stored as generic transform curves rather than in muscle space.

**What actually happened.** The accessory clip is a muscle clip like all the others — empty
generic curve arrays, populated `m_MuscleClip`. The inference from "this bone is not humanoid"
to "this data must be generic" **does not hold in this engine family**.

**Cost.** One wasted investigation. Worth recording because the reasoning is natural and wrong.

---

## 6 Claim 6 (FALSIFIED) — "the relay captures facial expressions"

**Method.** Count, per recording, how many of the relay's morph channels actually change value.

**Result.**

| recording | morph channels | channels that vary | largest span |
|---|---|---|---|
| idle | 123 | **4** | 0.0014 |
| walk | 123 | **4** | 0.088 |
| run | 123 | **4** | 0.111 |

**Criterion.** For each morph channel, take `max − min` over the recording. Count how many
exceed a small epsilon.

**Consequence.** Expression state is **not** recoverable from a relay recording. Any plan that
assumed "read the expression from the recording and drive accessories from it" is dead.

---

## 7 Claim 7 (FALSIFIED) — "the database supplies the expression→accessory mapping"

Two candidate tables were checked, both with the same outcome.

| candidate | what it holds | why it fails |
|---|---|---|
| a per-motion-set table with an accessory-motion column | a **motion-set name**, not an accessory clip name; effectively a single constant across 10,582 rows | gives no per-expression selection |
| a per-character rule table keyed by expression type | covers 28 expressions, all pointing at the same single accessory set | same |

**Criterion.** Group the table by its accessory column and count distinct values. A column that
is constant (or near-constant) cannot be a selector.

> This is a **negative result about where to look**, which is often worth more than a positive
> one: it rules out the obvious database location and points at the asset-side driven keys.

---

## 8 What this implies for the pipeline

```
native animation  ──(muscle clips, not readable)──►  must be sampled live
        │
        └─ relay recording ──► body bones only (52), no accessories, frame 0 dropped
                                   │
                                   └─ accessories must be AUTHORED, then baked as bone animation
```

**Status of this document's subject: testing.** The limits above are measured; the pipeline that
works around them is still being validated end to end.
