# 06 · Toolchain landscape: what already exists, and where the gap is

> **Purpose of this document.** When someone asks *"can't the existing compiler just output this?"*,
> the honest answer is **yes for one goal, and no for another.** This page states which is which,
> so nobody has to guess what these docs are for.

---

## 1. What already exists (and works)

The community toolchain for Darktide custom models already covers a complete pipeline.
None of the following is our work — we list it because any honest map has to include it.

| Stage | What it does |
|---|---|
| **Unpacking / import** | Reads the game's cooked resources and produces an editable scene in Blender, **with readable bone names** and material parameters |
| **Authoring + compiling** | A Blender addon plus a GLB compiler that turns authored content into a native Darktide `unit` (v115). It ships a **reference-skeleton** workflow: auto-map your model's bones onto the game's skeleton rows, then fit, then compile against a reference `.bones` |
| **Registration** | The custom-assets patcher validates cooked resources and packs them into the game's bundle database so the game can load them by name |

**⇒ So: bone names, scene nodes, and skeleton alignment do NOT have to be edited into a cooked
unit by hand.** The compiling route can produce all of it, provided the source scene is authored
against the game's skeleton.

---

## 2. Where the gap actually is

The existing fit-based workflow has one deliberate property:

```
"Fit to skeleton" warps every skinned vertex (and shape key) into the
reference rest pose.
```

**⇒ That is the point of it: after fitting, your model *is* the game's skeleton, so every
name-driven engine system (weapon attachment, foot IK, hand IK, aiming) lines up by construction.**

**⇒ The consequence is equally deliberate: the model no longer has its own proportions.**

So the two goals are:

| Goal | Covered by | Result |
|---|---|---|
| **A. Use the game's skeleton** (fit the model to it) | existing toolchain | ✅ everything lines up: weapon in hand, feet planted, IK active — **proportions become the game's** |
| **B. Keep the model's own proportions** | **not covered — this is what these docs record** | the model keeps its proportions; the name-driven systems and the weapon contact points **do not line up automatically** |

**⇒ This repository is about goal B**, and about the constraints that follow from it.

**⇒ To be explicit: we are not claiming hand-editing is the only route, nor that it is a better
route. Goal A is the shorter path, and if your goal is "the model must behave like the game's
character", goal A is the right one.**

---

## 3. What changes when you pick goal B

The engine resolves things **by name**, and several of those names carry engine semantics:

- weapon animation bones (`ap_*`, `j_trail_*`)
- foot IK family (`j_*_foot_ik`, `j_foot_grounded`, `*_pv`)
- hand IK family (`j_*_hand_ik`, `_pv`)
- aim / reference bones (`j_aim_target`, `j_hips_ref`, …)

**⇒ Under goal A these arrive for free, because the reference skeleton is adopted wholesale.
Under goal B you inherit them, but the *geometry* they drive no longer matches the game's
character — and one of those mismatches is not solvable by compensation:**

```
The weapon's visible mesh is bound to the game character's skeleton, not to the weapon's own unit.
⇒ With goal B, your hand is somewhere else than the character's hand.
⇒ No amount of moving the weapon unit fixes that; and making your skeleton reach the
   game's contact points is geometrically bounded (we measured a shortfall).
```

**⇒ The details, the measurements, and the list of approaches that were tried and disproven are
in `03-falsified-paths.md`. The reproduction notes are in `05-reproduce.md`.**

---

## 4. How to choose

| If you want… | Do this |
|---|---|
| a model that behaves like the game's character (weapon, feet, IK all correct) | use the existing fit-to-skeleton workflow |
| to keep a specific model's proportions, and accept that contact points diverge | read `03` and `05` here first — they will save you the attempts we already falsified |
| to know **why** the two goals conflict at all | `03-falsified-paths.md` §K |

**⇒ We would rather point you at the shorter path than have you walk ours.**
