# 04 · Same-lineage engine comparison (why "copying the mature ecosystem" has to be taken apart)

> This document records **observable structural facts** only, for the purpose of comparing design approaches.
> It does not involve the assets of any specific work, and it makes no licensing judgement (see `NOTICE.md`).

---

## 1. Origin: a very persuasive analogy

In the other engine family's ecosystem, modding is a **mature industry**: models go into the game, weapons attach to hands, animations work, and it all looks effortless.
So the natural question follows: **"Can we just copy what they do?"**

**⇒ Yes — but you have to separate "which part is provided by the engine" from "which part is provided by the model."**

---

## 2. How the other side (the Source engine family) does it

### 2.1 Attachment points: **declared inside the model, retrieved by name**

- The model declares a set of **named attachment points** in its own attachment table (observed counts fall between 28 and 30)
- Each attachment point is bound to **one specific bone** (for example, one attachment point → bone 14, another attachment point → bone 45)
- The attachment points include **weapon-related** ones (primary weapon, pistol, melee, fire bomb…), **presentation/logic** ones
  (eyes, mouth, feet, body facing…), and ones used for **IK/motion reference**

**⇒ Key point: the weapon's position is determined by the model's own declaration — so the model can be any proportion at all.**

### 2.2 Bone names: **aligned to a standard skeleton**

- A mod will **rename** a custom model's bones **to match the standard skeleton** (the observed practice: 60 bones given the same names as the original)
- Extra bones (model-specific, with no corresponding animation in the original) **follow their parent bone rigidly**

### 2.3 IK: **declared as "chains"**

- The observed practice is to declare a number of IK chains (for example, 5), which the **engine solves**
- The placement target is the **end of the chain**, not "some arbitrary handful of bones"

---

## 3. How our side (the Stingray/Bitsquid family) differs

| | The other side (Source) | Our side |
|---|---|---|
| **Who determines the weapon attachment point** | **The model declares it itself** | **The game character's skeleton** (the weapon is matched by name and attached to character bones) |
| **What the weapon's visible mesh is bound to** | The model's own bones | **The game character unit** (measured: disable the character object ⇒ the weapon disappears with it) |
| **Who solves IK** | The engine, using the chains the model declares | The engine, using a **fixed bone-name family** (missing ⇒ no effect) |
| **Bone-name requirement** | Aligning to the standard skeleton is sufficient | **Must be addressable by the engine by name** (otherwise the whole feature set stops working) |

**⇒ ⇒ In one sentence: on the other side, "the model tells the engine where the weapon is"; on our side, "the engine already knows where the weapon is."**

---

## 4. Four transferable conclusions that follow

**① "Attachment points / bone names must be addressable" is a convention, not a stopgap**
⇒ Adding names is the **proper approach** (corresponding to the `$attachment` declaration), not a patch.

**② A mature ecosystem does not "skip runtime compensation"; it "pushes down everything that can be pushed down"**
⇒ Whatever can be written into the asset layer (attachment points, IK chains, standard bone names) **is in the asset layer**;
⇒ Only what cannot be pushed down (for example, "moving an animation over from a different skeleton") is left to runtime.

**③ Completing a skeleton is a "feature checklist," not "the more the better"**
⇒ A bone name is the entry point to an engine feature. Whatever is missing, that corresponding feature set stops working for this model.

**④ Bones with no bone name must be explicitly made to "follow their parent bone rigidly"**
⇒ Do not leave them sitting in the rest pose, and do not author target values for them.

---

## 5. A counter-intuitive but important difference

**The reason the other side can say "the model can be any proportion at all" is that the weapon attachment point is declared by the model itself;
and the attachment point is bound to a bone ⇒ however the bone deforms, the weapon follows.**

**⇒ On our side this shortcut does not exist**: the weapon is bound to the **game character's bones**.
**⇒ Consequently, "keep the model's original proportions + have the weapon sit precisely in the model's own hand" becomes two geometrically mutually exclusive things**
(for the quantitative basis, see `03-falsified-paths.md` §A/§K).

**⇒ This is not a question of implementation skill; it is a difference in the binding relationship.**

---

## 6. Summary: what to copy and what not to copy

| What the other side does | Copy it or not | Reason |
|---|---|---|
| The model declares named attachment points | ✅ **Copy it (the semantics)** | We likewise require "names must be addressable" |
| Bone names aligned to the standard skeleton | ✅ **Copy it (partially)** | But note: what we are missing is **the whole set of names the engine uses**, not just the primary deformation bones |
| Extra bones follow their parent bone rigidly | ✅ **Copy it** | No target values needed, and it avoids sitting in the rest pose |
| IK done by chains, with placement at the end | ✅ **Copy it (the design)** | On our side the engine solves using a fixed bone-name family, so those names have to be completed first |
| "The model can be any proportion at all" | ❌ **Cannot be copied** | Their attachment points live in the model; our weapons are bound to the game character's bones |

**⇒ The last row is the core of this whole comparison: what can be copied is the conventions and the design; what cannot be copied is the binding relationship.**
