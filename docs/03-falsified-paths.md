# 03 · Paths That Have Been Falsified

> **The purpose of this document is to save time: every item below was walked by someone at a cost, and was struck down by evidence.**
>
> **Each item gives: what was done → what was observed → why it was struck down → the kind of evidence.**
> `[observed]` = on the running game; `[bytes]` = measurement at the asset layer; `[algebraic]` = derivable.

---

## A. Runtime "make our skeleton reach for the game's contact points"

**What was done**: solve IK every frame, sending our hands/feet to the hand/foot positions of the corresponding game bones
(two-bone analytic solution, which was at one point verified mathematically to a precision of `5.7e-17`).

**What was observed**:

```
our arm chain total length             0.5821 m
character arm chain total length       0.7312 m        ⇒ difference −14.91 cm
our shoulder → character hand (where the weapon is)  0.6686 m
⇒ margin = 0.5821 − 0.6686 = −8.64 cm   ★ cannot reach
```

**Why it was struck down**: **this is not an implementation problem, it is a geometry problem.** When the limb-length difference between the two skeletons exceeds the margin,
IK has no solution; forcing a solution only produces stretching and collapsing joint angles.
`[bytes]` (measured with the rest-pose chain lengths of the assets on both sides; independent of sub-segmentation)

**⇒ Why this item is valuable**: it reduces a problem that "looks like a code bug" back to "an infeasible geometric constraint".

---

## B. Writing the character's `local_position` onto our bones of the same name ("lower body follows")

**What was done**: at runtime, read the character bone's `local_position` and write it into our bone of the same name.

**What was observed**: **falsified on the running game**, the whole block was removed, and a hard gate was added to prevent it from being switched on by accident.

**Why it was struck down**:
- The two skeletons have **different local axis systems and rest transforms** ⇒ copying local quantities directly yields a wrong world pose
- It fights with the "ground snapping" line of work (both write the lower body)

**⇒ The correct approach**: do end-effector placement with a **pure world translation** (a single rigid translation of the whole), with intermediate bones carried by the parent world rotation.
`[observed]`

---

## C. Writing `local_position` per bone (on our own bones)

**What was done**: to align positions, write local translations on several bones individually.

**What was observed**: **tearing of 20.68%** (vertex-relative relationships broken).

**Why it was struck down**: per-bone translation amounts to a **non-rigid deformation** of the skeleton;

**⇒ whereas a single "global rigid δ" gives tearing of 0** (measured on the same batch of data). `[algebraic][bytes]`

**⇒ Conclusion**: when correcting the position of a skeleton, **only a single global translation is permitted**; per-bone translations are not.

---

## D. Replacing the game's body unit with a "complete character unit"

**What was done**: replace the game's player third-person body unit with our complete character unit.

**What was observed**: **two engine-level crashes** (no Lua error).

**Why it was struck down**:
1. The game's player body unit is a **rig** (`skins` empty, with mesh geometry), not a skinned character
2. The unit we substituted in carries 329 bone slots, while the engine's animation invariant is
   **"the number of animation tracks must equal the number of skeleton bone slots"** ⇒ the two do not match
3. The visible body mesh actually comes from the **equipment item units** (upper/lower body equipment), not from the body unit itself

`[bytes][observed]`

---

## E. Renaming the "bones added in" (on the assumption that they were colliding by name with the character)

**What was done**: prefix uniformly the 89 bone names added in order to complete the skeleton (`ap_*`, IK targets, sights/magazine/muzzle, etc.).

**What was observed**: **the problem remained after the change** ⇒ the "name collision" hypothesis does not hold.

**Why it was struck down**:
- The real basis for the naming direction is: **these names are entry points that the engine addresses by name**,
  not a source of collision. Renaming amounts to **moving away the very things the engine is looking for**.
- A comparison on a same-family engine (Source) supports this: mature model replacements **declare** these points rather than avoid them.

`[observed][cross-engine comparison]`

**⇒ The lesson retained**: **before renaming anything that "looks redundant", first confirm whether it is an addressing key for some system.**

---

## F. Unconditionally setting the LOD group to static level 0 in third person

**What was done**: after registering the LOD object, unconditionally call `LODGroup.set_static_select(group, 0)`.

**What was observed**: inconsistent with the game's native behavior.

**Why it was struck down**: the game natively does this **only in first person or when the highest LOD is forced**;
the normal third-person flow **does not** take this step. Doing it unconditionally amounts to forcibly pinning the LOD level. `[source][observed]`

---

## G. A **premise** that was falsified (not a path, but the most expensive of all)

**The former premise**: "the weapon's mesh belongs to the weapon unit, so moving the weapon unit moves it."

**The evidence that falsified it**: after switching off the **character unit's** mesh object, **the weapon disappeared along with it** (particles unaffected).

**⇒ The actual mechanism**: the weapon's visible object is bound together with the **character unit's** object set.
**⇒ Direct consequence**: writing the weapon unit's own local pose **produces no visual change whatsoever**. `[observed]`

**⇒ This item explains a whole earlier batch of attempts that "were set but produced no reaction".**

---

## H. Two items whose status is undetermined (**do not read these as "falsified"**)

| Approach | Status | Notes |
|---|---|---|
| **Re-parenting the weapon unit to our attachment point** (unlink → link to our node) | ⚠️ **undetermined** | It was once judged to "break rendering", but that batch of tests was done **under the invisible state of G above** ⇒ the conclusion is void, and it is being retested |
| **Writing the weapon's local pose every frame** so that it appears in our hands | ⚠️ **undetermined** | Likewise masked by G; "no reaction" considered on its own cannot establish that it is ineffective |

**⇒ We mark these as "undetermined" rather than "struck down" — because that distinction affects whether someone else should try them.**
**⇒ This is also a methodological mistake we made: a negative conclusion measured in a state "with other confounding variables" is unreliable.**

---

## I. Falsifications at the methodological level (equally valuable)

| Practice | Why it is wrong | Cost |
|---|---|---|
| **Inferring engine behavior from our own code comments** | a comment may be written backwards (we encountered a comment that reversed the semantics of a parameter, and the guard added on that basis in fact obscured the real cause) | several rounds |
| **Changing the runtime first, then asking "how does the original do it"** | the original path is the baseline; without reading the original first, you end up chasing symptoms all the way | several rounds |
| **Making a single-variable determination in a state that has confounding variables** | see H: the negative conclusion obtained is unusable | several rounds |
| **Addressing by array index instead of by name** | indices drift as assets are rebuilt (change an asset once and every index is out of place) | has already caused an incident |
| **Silent failure** | a runtime branch that "does nothing" raises no error ⇒ it gets misread as "it was hidden" | several rounds |

**⇒ Conclusion**: **read the original first, build a minimal difference table first, then act**; every step needs a **decidable log**.

---

## J. If you remember only one thing

**⇒ The positions of the contact points (hands, feet) are determined by "bone length"; whereas the weapon's visible mesh is bound to the game character's skeleton.**

```
⇒ Wanting "keep the model's original proportions" + "contact points exactly correct" ⇒ in the engine this document concerns, the two [cannot both be had] (see K)
⇒ The only options: ① align the model's skeleton proportions to the game (the community/official practice), or
                   ② keep the proportions and accept a contact-point discrepancy, or
                   ③ hybrid: align only the limb bone lengths to the game (torso/head/hair/clothing kept)
```

**⇒ K is the quantitative basis for this claim.**

---

## K. Why "keep proportions + correct contact points" cannot both be had (formalized)

```
contact point positions   ← determined by bone lengths
skin does not stretch     ← requires that bone lengths agree with the model's own binding (otherwise the mesh is stretched even in the rest pose)
⇒ the two requirements are mutually exclusive on one and the same skeleton
```

**⇒ Same-family comparison**: the reason the Source side can achieve "the model's own proportions + a correct weapon"
is that **the weapon's attachment point is declared by the model itself**, and the IK chain is written inside the model too —
**the engine reads "the model's own bones"**.

**⇒ But in the engine this document concerns, the weapon mesh is bound to the game character's skeleton**
⇒ and so "the model's own proportions" here cannot buy you "the weapon in the model's own hands".

**⇒ If the model's proportions and the original skeleton are to hold at the same time, there is only one road:
change the model's skeleton **into** bone lengths consistent with the game skeleton (that is, give up the goal of "original proportions").**
