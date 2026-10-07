# 09 — Source-side rig facts (and the traps in them)

**What a character skeleton from this source family actually looks like, and the three things
about it that silently break naive tooling.**

> **Scope.** No game data, no assets, no keys. Numbers only, with criteria.
> Markers: **VERIFIED** / **UNVERIFIED**.

---

## 1 Shape of the skeleton

| Quantity | Value |
|---|---|
| Total bones | **435** |
| Bones that actually carry skin weights | **199** |
| Bones with **zero** weight (control/helper) | **236** |
| Of those, names ending in a handle suffix | 159 |
| Root bone | 1 (`Position`) |

**Criterion.** For each bone, sum the vertex weights of the deform groups bound to it. Bones that
appear in no weighted vertex group are control-only.

**Consequence.** "Bone count" is not "deform bone count". Mapping a 435-bone rig one-to-one onto a
target rig will map mostly bones that deform nothing.

---

## 2 Family breakdown (the useful grouping)

| family | bones | of which **weighted** |
|---|---|---|
| body | 304 | — |
| hair | 52 | 20 |
| skirt | 40 | **10** |
| ear | 12 | 6 |
| tail | 11 | **5** |
| ribbon | 8 | 2 |
| breast | 8 | 2 |
| **total** | **435** | **199** |

**VERIFIED.** Family membership is assigned by bone-name prefix; the weighted column is measured.

### 2.1 What the low weighted counts mean

- **Skirt: 10 of 40.** Each skirt *panel* is represented by a **single weighted bone**. Panels are
  addressed individually (front / front-left / front-right / left / right / back / …), so a
  skirt is driven by **one rotation per panel**, not by a chain per panel.
- **Tail: 5 of 11.** One real chain of 5 segments; the remaining 6 are a control bone and five
  zero-weight handles.
- **Ear: 6 of 12.** Two chains of 3 segments (left/right); the rest are handles.

---

## 3 Trap 1 — the weighted bone is not the one you named

**VERIFIED.** Walking down the leg chain by *name* gives:

| bone (hierarchy order) | parent | weighted? |
|---|---|---|
| Hip | Position | ✅ |
| Thigh_L | Hip | ✅ |
| Knee_L | Thigh_L | ✅ |
| `Ankle_L` | Knee_L | ❌ **zero weight** |
| **`Ankle_offset_L`** | Ankle_L | ✅ |
| `Toe_L` | Ankle_offset_L | ❌ **zero weight** |
| **`Toe_offset_L`** | Toe_L | ✅ |

**Criterion.** Check the vertex-group weights of each bone in the chain.

**Consequence.** A mapping that targets `Ankle`/`Toe` by name will attach to **zero-weight
bones** — it will appear to succeed and deform nothing. The engine will then report legs that do
not move, with no error anywhere.

---

## 4 Trap 2 — the naming is not what the ecosystem assumes

**VERIFIED.** Every one of the 435 bones carries an **English** name in this export
(`Position`, `Hip`, `Thigh_L`, `Knee_L`, `Spine`, `Head`, `Shoulder_L`, …). **Zero** bones carry
Japanese/kanji names.

**Criterion.** Count bone names matching a kana/kanji range.

**Consequence.** Every community fix-up table written against **Japanese** MMD bone names
evaluates to zero matches on this export. When such a table is consumed by a lookup that
**falls through silently** — which is the common shape — the result is a pipeline that reports
success while doing nothing.

> We hit this **four separate times** across four independently written tools. It is a property of
> the ecosystem, not of one tool. See `03-falsified-paths.md` for the pattern and its cost.

---

## 5 Trap 3 — a hardcoded bone list cannot survive a different export

**VERIFIED.** Two concrete instances, both from published community tooling, both silent:

| tool's hardcoded list | this model's actual chain | outcome |
|---|---|---|
| accessory chain listed as segments `00`–`03` | actual chain is `00`–`**04**` (5 segments) | **last segment never driven** |
| ear chain listed as `01`,`02` | actual chain is `01`–`**03**` (3 segments) | **`03` never driven** |
| chest bones listed as `_00` | the **weighted** bone is `_01` | **constraint attached to a bone that deforms nothing** |

**Criterion.** For any hardcoded bone-name list, compute the set difference against the skeleton
in both directions, and separately check whether the listed bones are weighted.

**Rule that follows.** Bone-name lists must be **generated from the skeleton**, and any
name-based lookup must **fail loudly** rather than fall through.

---

## 6 What a rig handoff needs to contain (and why)

Derived from the traps above, the minimum useful description of a source rig is:

1. `name`, `parent`, and **rest pose** (position + rotation) per bone — parents alone are not enough
2. **`weighted` flag and total weight** per bone — to distinguish deform bones from controls
3. **family/group membership** — so accessory tooling can select without name matching
4. **chain structure** — because accessories are short chains or single bones, not uniform

Items 1–4 are what makes an accessory or physics step *configuration-driven* instead of
per-model code.

---

**Status: testing.** The rig facts above are measured; the downstream consumer of them is still
being validated.
