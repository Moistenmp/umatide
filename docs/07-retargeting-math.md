# 07 · Retargeting an External Animation onto Our Skeleton

> **What this document is for**: external motion (recorded elsewhere) has to be applied to *our* skeleton
> — the one whose proportions we are keeping. This is the one part of Goal B that is **pure mathematics**,
> and it can be solved **entirely offline**.
>
> **It is written because the obvious formula is subtly wrong, and the wrongness is not visible
> if you measure the wrong quantity.** Both the formula and the measurement are stated here.
>
> Evidence markers: `[algebraic]` = derivable · `[bytes]` = measured at the asset layer · `[observed]` = on the running game.

---

## 1. Notation (everything is at the data layer)

| symbol | meaning | source |
|---|---|---|
| `b`, `p = parent(b)` | a bone and its parent | GLB hierarchy |
| `t(b)` | **local translation** of `b` (constant) | GLB `nodes[b].translation` |
| `Rs(b)`, `Rt(b)` | **bind world rotation** of `b` in the source / target skeleton | the 3×3 of `inv(IBM)` |
| `Ls(b,τ)`, `Ld(b,τ)` | **local rotation** of `b` at frame `τ` | the clip / the value we are solving for |
| `Ws(b,τ)`, `Wd(b,τ)` | **world rotation**, `W(b,τ) = W(p,τ)·L(b,τ)` | derived |

---

## 2. The structural fact that decides everything `[algebraic]`

The **direction** of a bone is

```
d(b, τ) = normalize( W(p, τ) · t(b) )
```

**A bone's direction depends only on its parent's world rotation.** The bone's own rotation `L(b,τ)`
does not move its own direction — it moves only its **children's** directions.

Two consequences, both of which show up in the measurements:

1. If a formula does not carry **the parent's motion**, then every bone whose parent moves will be wrong.
2. Errors therefore **compound along the chain**, and each level must be corrected in the **current** frame.

---

## 3. The transformation target, written as an equation

Direction semantics (this is the criterion to use — see §5):

> The direction of target bone `b` at frame `τ` shall equal the source bone's direction,
> carried across by the **fixed bind-frame correspondence** `C(b)`:

```
Wd(p,τ) · t_d(b)  =  C(b) · Ws(p,τ) · t_s(b)                      … (★)
C(b) := the minimal rotation taking  normalize(Rs(p)·t_s(b))  to  normalize(Rt(p)·t_d(b))   … (★★)
```

## 4. The closed-form solution

Choose **world-delta isomorphism** (it is identity at bind, which we want):

```
Wd(b,τ) = C(b) · Ws(b,τ),   with  C(b) = Rt(b) · Rs(b)⁻¹   (fixed by bind)
```

Substituting into `Ld = Wd(p,τ)⁻¹ · Wd(b,τ)` and using `Ws(b,τ) = Ws(p,τ)·Ls(b,τ)`, with

```
δs(p,τ) := Rs(p)⁻¹ · Ws(p,τ)        ← the source PARENT's world delta
```

gives

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│  Ld(b,τ) = δs(p,τ)⁻¹ · [ Rt(p)⁻¹·Rt(b) · Rs(b)⁻¹·Rs(p) ] · δs(p,τ) · Ls(b,τ)      │
└──────────────────────────────────────────────────────────────────────────────────┘
```

**Compare with the "obvious" formula** (which we had implemented and were treating as the best candidate):

```
Naive:   Ld(b,τ) = [ Rt(p)⁻¹·Rt(b) ] · Ls(b,τ) · [ Rs(b)⁻¹·Rs(p) ]
```

**The only difference is the conjugation by `δs(p,τ)`** — that is, whether the parent's **motion** is carried.

---

## 5. The measurement trap: roll dominates an orientation metric `[bytes]`

The obvious error metric compares **orientations** (`acos` of the quaternion dot product).
**It is dominated by roll about the bone's own axis, which is visually irrelevant.**

Measured on one clip, first frame, the same formula (the naive one), two metrics:

| bone | **direction error** | orientation error |
|---|---:|---:|
| `j_leftarm` | **7.38°** | 149.81° |
| `j_leftupleg` | 4.10° | 28.25° |
| `j_rightupleg` | **2.31°** | 162.54° |
| `j_rightleg` | 32.14° | 161.89° |

**⇒ The bone that the orientation metric reports as the worst (`j_leftarm`, 149.81°) is, in direction, off by 7.38°.**
**The 149.81° is almost entirely roll.**

**⇒ Use the direction metric.** (Orientation is still worth reporting — but separately, as roll.)

---

## 6. Measurement: the conjugation is worth roughly half the error `[bytes]`

Direction metric, symmetric 17-bone set, **four different frames** of the same clip:

| frame | formula | mean | max | max (limbs) |
|---:|---|---:|---:|---:|
| 0 | naive | 33.19° | 115.36° | 115.36° |
| 0 | **closed form** | **22.89°** | **54.79°** | **54.79°** |
| 10 | naive | 33.04° | 115.10° | 115.10° |
| 10 | **closed form** | **22.82°** | **54.77°** | **54.77°** |
| 25 | naive | 33.19° | 115.36° | 115.36° |
| 25 | **closed form** | **22.89°** | **54.78°** | **54.78°** |
| 40 | naive | 33.25° | 115.05° | 115.05° |
| 40 | **closed form** | **23.04°** | **54.99°** | **54.99°** |

**⇒ mean ↓31%, max ↓53%, and stable across frames** (so it is not fitted to frame 0).

### 6.1 The error profile explains itself

With the naive formula, direction error by chain level:

| level | bones | direction error |
|---|---|---|
| 1st | `arm` / `upleg` | **2.31° – 7.38°** (already good — their parents barely move) |
| 2nd | `forearm` / `leg` | **52.16° / 53.34° / 53.27°** (parents now move) |
| 3rd | `hand` | **113.98° / 115.36°** (parent already wrong) |

**The three 2nd-level bones landing on 52–53° independently is the fingerprint of a missing term,
not of three separate bugs.**

---

## 7. Why bind-frame-only corrections cannot work `[algebraic]`

An "alignment term" built only from bind quantities, e.g. `A_bone = Rt(b)·Rs(b)⁻¹`,
is **independent of `τ`**. It therefore **cannot produce `δs(p,τ)`**, which contains `τ`.

**⇒ Every such term is structurally incapable of fixing the 2nd/3rd-level error, no matter where it is multiplied in.**
This was confirmed by measurement (six insertion positions, all worse: 80–94° vs 45.29° on the same bone set),
but the algebraic statement is the stronger one: *it could not have worked.*

---

## 8. What is **not** yet established

| # | open item |
|---|---|
| 1 | **The closed form has not passed its own invariant check.** At bind (`Ls` = source bind local), `Ld` should equal the target bind local. Our check aborted on a missing parent entry, so this is **unverified**. Until it holds, the numbers above are "an improvement under the direction metric", not "proved correct". |
| 2 | **The remaining 54.79° has not been attributed.** The equation (★) constrains direction only; **roll is unconstrained** and needs a separate convention. Direction / orientation / roll must be reported separately. |
| 3 | Multi-clip, all-frames statistics are not yet taken. |

---

## 9. Practical note for anyone reproducing this

* Everything here is **offline**: two GLBs in, numbers out. No game needed.
* The **direction** metric needs the bone's **local translation** and both skeletons' **bind world rotations**
  — both are in the files. The bind world rotation is `inv(IBM)`'s 3×3; **do not** use the node TRS.
* **An animation clip requires a same-stem `.bones` file** when loaded as a resource (see `01-unit-format.md`).
* Keep **roll and direction apart from the beginning** — mixing them is what makes the numbers move around.
