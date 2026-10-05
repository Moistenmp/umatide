# 01 · Unit resource format

> **Every conclusion in this document is tagged with its evidence type:**
> `[bytes]` = bytes/offsets read directly; `[observed]` = on-machine or tool behavior; `[inferred]` = not yet directly confirmed.
>
> **Scope**: the `unit` resource of Darktide (Stingray/Bitsquid engine family) and the accompanying `bones` resource.
> **Contains** no game resource payloads.

---

## 1. File shape

```
unit file = [38-byte cooked header][body]
```

### 1.1 Two confirmed fields in the header `[observed]`

| Offset | Type | Meaning | Evidence |
|---|---|---|---|
| `8` | `u64` | **murmur64 hash of the resource name** | the community asset registrar reports `header name hash does not match ...` when validation fails |
| `29` | `u32` | **body length** (= file length − 38) | when the length declared in the header disagrees with the actual file length, the validator reports `cooked resource envelope length mismatch: header declares X bytes, got Y` |

**⇒ These two are the entire reason for "after editing a file you must write the header back".**
**⇒ `bones` files are isomorphic**: they also have a 38-byte header, and also write the body length at offset 29. `[observed]`

### 1.2 The name-hash algorithm `[bytes][observed]`

- name → `murmur64(name)` → **take the high 32 bits** and store them in the scene graph's name hash array
- that same hash also determines the **resource file name** (the 16 hexadecimal digits used by the export tool are the full `murmur64`)

---

## 2. Section structure of the body

**The body is a sequence of "self-describing sections"; there is no offset table.** `[bytes]`

⇒ **The correct way to assemble a unit is: concatenate the sections in the same order, and write the body length back into the header.**
⇒ **Section lengths are implicit in each section's own data** (there is no global index to consult).

### 2.1 Observed section names `[bytes]`

```
version                     actors                      actors_2
animation_state_machine      cameras                     default_material_resource
dynamic_data                 flow                        flow_dynamic_data
has_animation_blender_bones  joints                      lights
lod_objects                  materials                   mesh_geometries
mesh_geometry_triangle_finder  meshes                    movers
physics_scene_data_64bit     scene_graph                 simple_animation
simple_animation_groups      skeleton_name               skins
terrains                     visibility_groups           unk9..unk20 (purpose unknown)
```

> **Note**: the **spelling and order** of the section names are observations. Different units may omit some sections (an empty section shows up as a count of 0 with length 4).

---

## 3. Exact layout of `scene_graph` `[bytes]`

**This is the section that is easiest to misread and the one that most affects editing. The observed layout is as follows (in order):**

```
u32  node count N
N × 60 bytes    local transform
N × 64 bytes    world matrix
N × 4  bytes    parent/child table
N × 4  bytes    name hash table
```

### 3.1 Local transform block = 60 bytes = `36 + 12 + 12` `[bytes]`

```
[0:36]   3×3 rotation (9 floats)
[36:48]  translation (3 floats)   ← this is the "bone length" (the offset vector relative to the parent origin, whose magnitude = segment length)
[48:60]  scale (3 floats)         ← in normal units this is (1, 1, 1)
```

**⇒ A real example of misreading it (worth remembering):**
if this block is read as a 4×4 matrix, the displacement lands in `[48:60]` and what is read is the **scale (1,1,1)**,
so the "segment length" is computed throughout as `√(1²+1²+1²) = 1.732` m — a number that looks like data but is entirely wrong.

### 3.2 World matrix block = 64 bytes `[bytes]`

Standard 4×4 row-major float; the translation components are at float indices `12..14`.

### 3.3 Parent/child table = 4 bytes per node = `(u16 type, u16 parent index)` `[bytes]`

- **parent index >= node count** ⇒ that node is a root (no parent)
- the semantics of the type field are not yet fully confirmed `[inferred]`

### 3.4 The name hash table is **after the parent/child table** `[bytes]`

```
hash_offset = section_offset + 4 + N*60 + N*64 + N*4
                                                   ^^^^  ← skip this segment and you read garbage
```

**⇒ This is a pitfall we actually hit**: skipping `N*4` (the parent/child table) and then reading the name hashes
produces the illusion of "nothing matches, 0 hits", which leads to the misjudgment that "the names are not bound to nodes".

---

## 4. Rules for resolving names and nodes (a core convention of this engine family)

### 4.1 Engine-side node numbering = in-file index + 1 `[observed]`

Verified independently in several places (file 0 → engine 1; file 238 → engine 239; file 4 → engine 5; file 171 → engine 172).

**⇒ Every bone-writing interface takes engine numbering, while asset editing is done on in-file indices. This off-by-one is a common source of errors.**

### 4.2 What it takes for a node to be "addressable by name" `[bytes][observed]`

```
① the node's name hash must be written into the scene_graph name hash table
② that name must appear in the accompanying .bones name table
③ (for bones) it must also occupy a bone slot in skins   ← adding only the name without a bone slot may still leave the engine not treating it as a bone
```

**⇒ Doing only ② is not enough**: the name table is merely a **dictionary**, and the engine's resolution path is
`name → hash → scene_graph node`. **The dictionary has it but the scene graph has no corresponding hash ⇒ it cannot be resolved.**

### 4.3 Why this convention matters

**Attachments and bone names must be addressable, otherwise the engine's own systems (weapon attachment, foot IK, hand IK, aiming)
simply cannot act on your model** — in the sibling engine (Source) this corresponds to "declaring `$attachment` in the model".

---

## 5. Body layout of the `bones` resource `[bytes]`

**We performed the self-proof that "rebuilding the body from the existing names must be byte-identical to the file", so this one is fairly reliable:**

```
u32  name count C
u32  constant (observed value = 1)
C × u32   name hashes (murmur64(name) >> 32)
u32  name count C (appears again)
C × (ASCII name + 0x00)
```

**⇒ When editing the name table, always run the self-proof above**: rebuild once from the **existing** names, and it must be byte-identical to the current body.
**Only after the self-proof passes are you allowed to write a new name table back with the same code.**

---

## 6. `skins`: skinning and inverse bind matrices

- The body contains **the node index corresponding to each bone slot** and the **inverse bind matrices (IBM)**
- **The IBM is by definition `inverse(the bone's world transform in that pose)`** `[inferred, but with strong evidence]`

### 6.1 An identity that follows from this (you must know it when editing bone lengths)

```
skinning:  v_world = Σ wᵢ · Wᵢ(animation) · IBMᵢ · v_bind
if         IBMᵢ = inverse(Wᵢ(bind))
then       animation == bind  ⇒  v_world == v_bind
```

**⇒ Conclusion: as long as "change the bone length" and "recompute the IBM of that bone (and its subtree)" are done as a pair, the mesh is deformed by zero in the rest pose.**
**⇒ This is an algebraic identity, not an approximation.**

**⇒ And changing one bone's local translation moves the world rest transform of its entire subtree**
⇒ **the IBMs affected = that bone and all of its descendants.**

---

## 7. Animation is bound **by index** `[observed]`

- The compiler has a hard invariant: **the track count of a simple animation must equal the bone count of the skeleton**, and track `i` corresponds to scene graph node `i`
- Searching the animation data for a **bone name hash** finds nothing

**⇒ Direct consequence: animation does not know names. To make each bone move, it must appear at the correct **index** position.**

---

## 8. Safe practices available when editing a unit (ones we have actually used)

```
1. Back up before any change (move only, never delete)
2. Read into memory → change only the target bytes → write back in one pass (never "read it in, then write in steps, then write back at the end")
3. Run local validation immediately after the change:
    · the scene graph name hash array and the parent/child table lengths are self-consistent
    · the .bones "rebuild from existing names" self-proof
    · the hash at header offset 8 and the length at offset 29
4. Hand it to the game-side asset registrar (patcher) for final validation — **it will reject files with an inconsistent header**
5. Names changed ⇒ data tables that depend on names must be recomputed in sync (otherwise the write lands on the wrong node, and the engine reports no error)
```

---

## 9. What is not yet confirmed (honesty list)

| Item | Status |
|---|---|
| full semantics of the "type" field in the `scene_graph` parent/child table | `[inferred]` |
| purpose of the `unk9..unk20` sections | unknown |
| whether `skins.node_indices` needs additional synchronization after adding nodes | partially verified |
| the full impact of the material layer and visibility groups on custom models | `[observed]` phenomena, mechanism not fully broken down |
| how the animation state machine and `flow` act on custom units | unverified |

**⇒ For the points above that we are not sure about, we write "not sure".**
**If you already have conclusions on these points, say so directly — a correction of a fact is more useful than agreement with a conclusion.**
