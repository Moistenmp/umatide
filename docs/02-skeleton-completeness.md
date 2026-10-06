# 02 · Skeleton Completeness: The Cost of Missing Bone Names

> **In one line**: in this engine family, **a bone name is a "system entry point"**.
> Missing one name is not just one missing bone — it means **the entire corresponding engine feature stops working for that model**.

---

## 1. Origin: A Model That Matches Up But Cannot Be Driven

When bringing in an external model, the common approach is to **handle only the batch that "looks like the main deformation bones"** and leave the rest alone.

Observed cost (our own numbers):

```
Our bone name table (after patching 2 entries)   227
Game character bone name table                   167
Present in character, missing on our side        101      ← ★ the problem is here
Present on our side, absent in character         161      (model-specific bones, normal)
```

**⇒ The key point is not "101 are missing", it is "which ones are missing".**

---

## 2. What Is Missing Is a **Coherent, Semantic System**

### 2.1 Weapon Animation Bone Families (each with an `_offhand` mirror)

| Family | Count | Semantics |
|---|---:|---|
| `ap_anim_01..10` | 10 (+10) | Generic animation parts |
| `ap_bullet_01/02` | 2 (+2) | Shell / bullet spawn points |
| `ap_magazine_01/02` | 2 (+2) | **Magazine** (reload animation) |
| `ap_recharge_01..03` | 3 (+3) | Charging handle |
| `ap_release_01..04` | 4 (+4) | Magazine release |
| `ap_safety_01/02` | 2 (+2) | Safety / fire selector |
| `ap_sight_01/02` | 2 (+2) | Sights |
| `ap_stock_01/02` | 2 (+2) | Stock |
| `ap_trigger_01/02` | 2 (+2) | Trigger |
| `ap_underbarrel_01` | 1 (+1) | Underbarrel |
| `j_trail_01..04` | 4 (+4) | Projectile trail |

**⇒ Missing this family ⇒ the engine cannot address any weapon animation bone by name.**

#### 2.1b The `fx_` family — effects and sounds (added 2026-10-07)

The compiler's own README lists **three** categories of node a replacement must carry,
not two. The third is easy to overlook because it carries no skeleton semantics:

```
fx_ nodes are where effects and sounds come out
  fx_muzzle_01     muzzle flash
  fx_eject         shell ejection
```

**⇒ Missing the `fx_*` family ⇒ weapon/VFX effects have no anchor** — they either do not appear
or fire from the original character's position. This family was **entirely absent** from our own
first patch-up pass, because we enumerated bones (deformation semantics) and never enumerated
*effect anchors*.

**⇒ The authoritative way to get all three families at once is the addon's
`Import Game Unit Nodes`**: it brings in **every node of the unit being replaced**, placed and
named like the game's. Nodes that are hash-only show as `#1234abcd` and **must be left alone** —
the compiler writes them back as the same hash.

### 2.2 The IK Bone Family — **This Is the Official Mechanism for Foot and Hand Placement**

```
j_foot_grounded                                    ← foot-grounded marker
j_left_foot_ik / j_right_foot_ik
j_*_foot_ik_transform / _ik_orient_ref / _ik_orient_transform
j_*_foot_pv                                        ← pole vector
j_*_foot_anim_ref
j_left_hand_ik / j_right_hand_ik / _hand_ik_transform / _hand_pv
```

**⇒ Missing `j_*_foot_ik` / `j_foot_grounded` / `*_pv` ⇒ the engine's own foot IK has nothing to act on** (it shows up as feet floating or sinking into the ground).
**⇒ Missing `j_*_hand_ik` / `_pv` ⇒ hand IK likewise has nothing to act on** (it shows up as the hands not lining up with the weapon).

### 2.3 Aim / Reference Bone Family

```
j_aim_target     j_hub_head_aim     j_hub_torso_aim
j_hips_ref       j_frontchestplate  j_backchestplate
```

**⇒ Missing reference bones ⇒ no stable frame of reference** (it shows up as abnormal displacement in extreme poses).

### 2.4 Roll Bones (Usually Only Partially Patched)

```
j_leftforearmroll1/2   j_rightforearmroll1/2   j_leftlegroll1 …
```

---

## 3. Therefore: A Bunch of "Independent Symptoms" Are Really Different Faces of One Root Cause

| Symptom being fixed separately all along | The actual missing piece |
|---|---|
| Weapon not seating in the hand / not in the palm | `ap_*` + `j_trail_*` bone families missing |
| Feet floating / sinking into the ground | `j_*_foot_ik` / `j_foot_grounded` / `*_pv` missing |
| Hands not lining up with the weapon | `j_*_hand_ik` / `_pv` missing |
| Abnormal displacement in extreme poses | `j_hips_ref` / IK reference bones missing |

**⇒ Without this step, every following step turns into "hand-writing a runtime compensation for something that the engine was supposed to drive by name".**
**⇒ This is the mechanical reason for "why does fixing one thing make another appear".**

---

## 4. Three Design Alignments When Patching Up (from a Same-Family Engine Comparison)

**① Bones with no animation source should "just follow the parent bone"**
Mature modded skeletons often have far more bones than the original (for example 126 vs 73). The extra bones **have no corresponding animation** in the original,
and they are handled by **following the parent bone rigidly**, rather than being given target values of their own.

**⇒ The same holds for us**: drive only the batch that matches up; let the rest explicitly "follow the parent bone rigidly",
**rather than leaving them sitting in the rest pose**.

**② IK is a "chain", not "a few bones"**
The same-family engine declares IK by `$ikchain` (the whole chain).

**⇒ Lower-body following should be enumerated per chain** (hip → leg → foot → toe), with an explicit statement that **the end of each chain** is the placement target.

**③ Placement uses "pure world translation", not per-bone translation**
See `03-falsified-paths.md` §C: per-bone translation tears (observed 20.68%), whole-body rigid translation tears 0.

---

## 5. Patching Up ≠ Just Changing the Name Table (The Easiest Trap to Fall Into)

```
The name table (.bones) is only a dictionary
The engine's resolution path is: name → hash → scene graph node
⇒ In the dictionary but no corresponding node in the scene graph ⇒ cannot be resolved
```

**⇒ So "completing the skeleton" consists of two things:**
1. Add the names to the **name table**
2. Build the corresponding nodes in the **scene graph** (correct hash + correct parent bone + reasonable initial position)

**⇒ And after adding nodes, check: whether the `skins` bone slots and mesh references need to be synchronized.**
(We have only partially verified this item; see `01-unit-format.md` §9.)

### 5.1 ★★★ The hard limit that decides this (verified 2026-10-07)

This is the single most important number when planning a skeleton patch-up, and it is **not**
negotiable:

```
Vertex joint indices are UBYTE4  ⇒  joint index < 256  ⇒  skin.joints ≤ 256
```

Measured behaviour at the official compiler (`DarktideGLBCompiler.exe`), same source scene,
only `skin.joints` varying:

| `skin.joints` | Compiler output |
|---:|---|
| 256 | `valid UNIT v115` ｜ **`9 skinned`** ｜ **all added bone names preserved in `.bones`** |
| 408 | `valid` ｜ **`0 skinned`** — the compiler detaches the skinned geometry and bakes it as static channels (`[skinning_static_bake]`) |

**⇒ Two consequences that invert the naive plan:**

1. **"Add the names to the table" is not sufficient** — a node outside `skin.joints` is **not
   addressable by name at runtime** (`Unit.node` fails; the subagent-side check logged
   `[wp1] our unit has no node …`).
2. **But putting them inside `skin.joints` costs slots**, and the budget is shared with the
   model's own deforming bones. On our model: base `skin.joints = 225`, of which **only 198 are
   actually referenced by `JOINTS_0`** — and **27 of the remaining are *not* padding**:
   `j_leftfoot`, `j_rightfoot`, `toe_l`, `toe_r`, the `j_*inhand*` grip bones, `cheek/eyebrow/mouth`
   offsets, `sp_bust*`, `tail_ctrl`. Dropping them as "unused slots" removes exactly the bones
   the foot/hand systems need.

**⇒ Practical rule:** the addressable set must be **planned as a budget of 256**, not grown
incrementally. Enumerate (a) mesh-referenced bones, (b) engine-addressed bones (the families in
§2), then spend what remains. In our case that left room for **29** added bones on the asset
that reproduced the working state.

> **Provenance:** measured on 2026-10-07, offline (`skin.joints` rewritten at GLB level,
> compiler output inspected) and in game (`[diag]` name-addressability counts).
> A GLB-level rewrite is required to change `skin.joints`; **do not hand-edit a cooked `.unit`**
> (`03-falsified-paths.md` §D and the validate gate).

---

## 6. A Useful Criterion

**⇒ The fastest way to decide "whether a given name should be added":**
**Go look at what the identically named bone in the original game is doing.** If the engine references it by name (attachment points, IK, aiming),
then your model missing it ⇒ that whole feature is dead for you.

**⇒ In other words: the bone name list is not a completeness fetish, it is a **feature list**.**
