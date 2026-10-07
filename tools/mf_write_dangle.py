# -*- coding: utf-8 -*-
r"""mf_write_dangle.py —— 在 GLB 层给【带权】配件骨写 dangle extras（2026-10-08）

## 依据（全部来自社区工具链，不是自造）

  ① 编译器 addon `darktide_assets/__init__.py` L1005–1017 的 schema：
       bone[SCHEMA_KEY] = {"version":1, "id":"dangle:<obj>:<bone>", "dangle": record}
     SCHEMA_KEY = "darktide_asset"（与本项目既有的 ragdoll extras 同一个键）
     swing（默认，不写 mode）: mass 1.0 ｜ gravity 9.82 ｜ damping 3.0
                                stiffness 0.0 ｜ max_angle 0.0(度,0=不限) ｜ length 0.0(0⇒取骨长)
     jiggle（写 mode:"jiggle"）: mass 1.0 ｜ gravity 9.82 ｜ stiffness 1000.0
                                 damping 400.0 ｜ max_stretch 0.1
  ② 挂载名单 = uma `exports\dangle_targets.json`（**只列带权骨**）
     ⇒ uma §26.2：挂在零权重骨上是【空转】（骨摆得再对，顶点不跟）
     ⇒ uma §26.3：社区 Physics.py 正是踩了这个坑（BUST 用了 _00，那两颗零权）
  ③ 模式分配 = uma §26.5：
       tail / hair / skirt / ribbon → swing
       breast                      → jiggle
       ear                         → 不走 dangle（走他们已交的事件 clip）

## 用法

  python system\tools\mf_write_dangle.py --glb <in.glb> --targets <dangle_targets.json> \
                                         --out <out.glb> [--only tail,skirt,hair,ribbon,breast] \
                                         [--stiffness-k 0.0] [--max-angle 0.0] [--apply]
  默认演练（不写文件），加 --apply 才写。
"""
import argparse
import json
import struct
from pathlib import Path

ROOT = Path(r"D:\02_Projects\Darktide")


def read_glb(p):
    raw = Path(p).read_bytes()
    _, _, total = struct.unpack_from("<III", raw, 0)
    off, js, bn = 12, None, None
    while off < total:
        clen, ctype = struct.unpack_from("<II", raw, off)
        d = raw[off + 8:off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(d.decode("utf-8"))
        elif ctype == 0x004E4942:
            bn = bytearray(d)
        off += 8 + clen
    return js, bn


def write_glb(p, js, bn):
    js = dict(js)
    js["buffers"][0]["byteLength"] = len(bn)
    s = json.dumps(js, separators=(",", ":")).encode("utf-8")
    s += b" " * ((4 - len(s) % 4) % 4)
    b2 = bytes(bn) + b"\x00" * ((4 - len(bn) % 4) % 4)
    out = bytearray()
    out += struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(s) + 8 + len(b2))
    out += struct.pack("<II", len(s), 0x4E4F534A) + s
    out += struct.pack("<II", len(b2), 0x004E4942) + b2
    Path(p).write_bytes(bytes(out))


SWING_DEFAULT = {"mass": 1.0, "gravity": 9.82, "damping": 3.0, "stiffness": 0.0,
                 "max_angle": 0.0, "length": 0.0}
JIGGLE_DEFAULT = {"mode": "jiggle", "mass": 1.0, "gravity": 9.82, "stiffness": 1000.0,
                  "damping": 400.0, "max_stretch": 0.1}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", required=True)
    ap.add_argument("--targets", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", default="tail,skirt,hair,ribbon,breast")
    ap.add_argument("--stiffness", type=float, default=None)
    ap.add_argument("--max-angle", type=float, default=None)
    ap.add_argument("--damping", type=float, default=None)
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    tg = json.loads(Path(a.targets).read_text(encoding="utf-8-sig"))
    fams = [x.strip() for x in a.only.split(",") if x.strip()]

    js, bn = read_glb(a.glb)
    nodes = js["nodes"]
    # 名 → 节点下标（大小写不敏感；同时收 glb 名）
    idx = {}
    for i, nd in enumerate(nodes):
        nm = nd.get("name")
        if nm:
            idx[nm.lower()] = i

    want = []          # (family, node_index, node_name, mode, len_cm)
    missing = []
    for fam in fams:
        blk = tg.get(fam) or {}
        mode = "jiggle" if fam == "breast" else "swing"
        for e in blk.get("bones", []):
            cand = [e.get("glb"), e.get("bone")]
            hit = None
            for c in cand:
                if c and c.lower() in idx:
                    hit = idx[c.lower()]
                    break
            if hit is None:
                missing.append((fam, e.get("bone"), e.get("glb")))
            else:
                want.append((fam, hit, nodes[hit].get("name"), mode, e.get("len_cm")))

    print("   目标骨 %d 根 ｜ 未在 GLB 里找到 %d 根" % (len(want), len(missing)))
    for fam, b, g in missing[:10]:
        print("      ★ 未找到 %-8s bone=%-24s glb=%s" % (fam, b, g))
    from collections import Counter
    print("   按族：%s" % dict(Counter(f for f, _, _, _, _ in want)))
    print("   按模式：%s" % dict(Counter(m for _, _, _, m, _ in want)))

    if not a.apply:
        print("\n   —— 演练结束（未写文件）—— 要真写：加 --apply")
        return

    changed = 0
    for fam, i, nm, mode, len_cm in want:
        rec = dict(JIGGLE_DEFAULT if mode == "jiggle" else SWING_DEFAULT)
        # ★ 实测：编译器对【无子关节的末端骨】报错
        #   "dangling bone '<name>' has no child joint; give it a length"
        #   ⇒ 必须显式给 length。用 uma 实测的 len_cm（比"自动取骨长"更准）。
        if len_cm:
            rec["length"] = round(float(len_cm) / 100.0, 6)
        if a.stiffness is not None and mode == "swing":
            rec["stiffness"] = a.stiffness
        if a.damping is not None:
            rec["damping"] = a.damping
        if a.max_angle is not None and mode == "swing":
            rec["max_angle"] = a.max_angle
        ex = nodes[i].get("extras") or {}
        ex["darktide_asset"] = {"version": 1,
                                "id": "dangle:agnes:%s" % nm,
                                "dangle": rec}
        nodes[i]["extras"] = ex
        changed += 1

    write_glb(a.out, js, bn)
    print("\n   已写 %s（%d 根骨加了 dangle）｜ %d B" % (a.out, changed, Path(a.out).stat().st_size))

    # 自证：回读
    js2, _ = read_glb(a.out)
    n = sum(1 for nd in js2["nodes"]
            if isinstance(nd.get("extras"), dict) and "dangle" in (nd["extras"].get("darktide_asset") or {}))
    print("   自证：回读后含 dangle 的节点 = %d" % n)


if __name__ == "__main__":
    main()
