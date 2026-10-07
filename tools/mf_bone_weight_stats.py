# -*- coding: utf-8 -*-
r"""mf_bone_weight_stats.py —— 逐骨顶点权重统计（只读）★ 交给 uma 对表用

## 为什么做这个（uma §25.6 明确要的输入）

我们判定"嘴周消失"不是 morph（morph_targets=0）⇒ 几何/权重问题。
uma 有现成的面部骨影响域实测（FACE_BONE_REGIONS.md：105 面骨 → 80 带权 / 25 零权，
含 Mouth_Root / Mouth_bottom_01..03 / Mouth_middle / Cheek / Chin 的顶点数与相对 Head 位置）。
⇒ 交叉检查方式：把他们那份"面骨 → 带哪些顶点、在哪"与【我们编译产物的逐骨权重覆盖】对表。
⇒ 需要我方提供：产物侧【逐骨的顶点权重统计】。

## 输出

  ① 汇总：每个 joint 的 {顶点数, 权重和, 最大权重}，按权重和排序
  ② 面骨明细：名字含 mouth/cheek/chin/lip/jaw/tongue/tooth/eye/brow/nose 的骨，
     逐骨列出 {顶点数, 权重和, 顶点包围盒中心（相对 j_head 或 root）}
  ③ 零权骨清单：在 skin.joints 里但 JOINTS_0 从未引用的骨（uma 侧也有 25 根零权面骨 ⇒ 可对照）

用法：python system\tools\mf_bone_weight_stats.py <glb> [--out <md 路径>]
"""
import argparse
import json
import math
import struct
import sys
from pathlib import Path

ROOT = Path(r"D:\02_Projects\Darktide")
sys.path.insert(0, str(ROOT / "system"))
sys.path.insert(0, str(ROOT / "system" / "tools"))
import mf_retarget_bind as RB       # noqa: E402

CT = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}

FACE_KEYS = ("mouth", "cheek", "chin", "lip", "jaw", "tongue", "tooth",
             "eye", "brow", "nose", "mayu", "face")


def read_acc(js, bn, ai):
    acc = js["accessors"][ai]
    bv = js["bufferViews"][acc["bufferView"]]
    off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    fmt, sz = CT[acc["componentType"]]
    nc = NC[acc["type"]]
    stride = bv.get("byteStride") or (sz * nc)
    out = []
    for k in range(acc["count"]):
        vals = struct.unpack_from("<%d%s" % (nc, fmt), bn, off + k * stride)
        if acc.get("normalized") and fmt != "f":
            if fmt in ("B", "H"):
                mx = 255.0 if fmt == "B" else 65535.0
                vals = tuple(v / mx for v in vals)
            elif fmt in ("b", "h"):
                vals = tuple(max(v / 127.0, -1.0) for v in vals)
        out.append(vals if nc > 1 else vals[0])
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("glb")
    ap.add_argument("--out", default="")
    a = ap.parse_args()

    js, bn = RB.read_glb(Path(a.glb))
    names = [n.get("name") or ("node%d" % i) for i, n in enumerate(js["nodes"])]
    sk = js["skins"][0]
    joints = sk["joints"]

    # 逐槽（joint 在 skin.joints 里的下标）累计
    cnt = [0] * len(joints)
    wsum = [0.0] * len(joints)
    wmax = [0.0] * len(joints)
    ctr = [[0.0, 0.0, 0.0] for _ in joints]
    nvert = 0

    for m in js["meshes"]:
        for p in m["primitives"]:
            at = p["attributes"]
            if "JOINTS_0" not in at or "WEIGHTS_0" not in at:
                continue
            P = read_acc(js, bn, at["POSITION"])
            J = read_acc(js, bn, at["JOINTS_0"])
            W = read_acc(js, bn, at["WEIGHTS_0"])
            for i in range(len(P)):
                nvert += 1
                jv = J[i] if isinstance(J[i], tuple) else (J[i],)
                wv = W[i] if isinstance(W[i], tuple) else (W[i],)
                for t in range(min(len(jv), len(wv))):
                    w = float(wv[t])
                    if w <= 1e-6:
                        continue
                    s = int(jv[t])
                    if 0 <= s < len(joints):
                        cnt[s] += 1
                        wsum[s] += w
                        wmax[s] = max(wmax[s], w)
                        for c in range(3):
                            ctr[s][c] += P[i][c] * w

    # j_head 的世界位置（用于相对坐标）
    par = {}
    for i, nd in enumerate(js["nodes"]):
        for c in nd.get("children", []):
            par[c] = i
    head = next((i for i, n in enumerate(names) if n == "j_head"), None)

    lines = []
    lines.append("# 逐骨顶点权重统计（产物侧）—— 供 uma §25.6 对表\n")
    lines.append("源：`%s`\n" % a.glb)
    lines.append("顶点总数 %d ｜ skin.joints %d ｜ 被引用的 joint %d ｜ 零权 joint %d\n"
                 % (nvert, len(joints), sum(1 for c in cnt if c), sum(1 for c in cnt if not c)))

    order = sorted(range(len(joints)), key=lambda s: -wsum[s])
    lines.append("\n## ① 汇总（按权重和降序，前 60）\n")
    lines.append("| joint(slot) | 骨名 | 顶点数 | 权重和 | 最大权重 |")
    lines.append("|---|---|---:|---:|---:|")
    for s in order[:60]:
        lines.append("| %d | %s | %d | %.3f | %.3f |" % (s, names[joints[s]], cnt[s], wsum[s], wmax[s]))

    lines.append("\n## ② 面骨明细（名字命中 %s）\n" % "/".join(FACE_KEYS))
    lines.append("| joint(slot) | 骨名 | 顶点数 | 权重和 | 最大权重 | 加权中心(x,y,z) |")
    lines.append("|---|---|---:|---:|---:|---|")
    nface = 0
    for s in order:
        nm = (names[joints[s]] or "").lower()
        if any(k in nm for k in FACE_KEYS):
            c = ctr[s]
            w = wsum[s] or 1.0
            lines.append("| %d | %s | %d | %.3f | %.3f | (%.4f, %.4f, %.4f) |"
                         % (s, names[joints[s]], cnt[s], wsum[s], wmax[s], c[0] / w, c[1] / w, c[2] / w))
            nface += 1
    if not nface:
        lines.append("| — | （无命中） | | | | |")

    lines.append("\n## ③ 零权 joint（skin.joints 里但 JOINTS_0 从未引用）\n")
    zero = [names[joints[s]] for s in range(len(joints)) if not cnt[s]]
    lines.append("共 %d 根：\n" % len(zero))
    for z in zero:
        lines.append("- %s" % z)

    txt = "\n".join(lines) + "\n"
    print("   顶点 %d ｜ joints %d ｜ 被引用 %d ｜ 零权 %d ｜ 面骨命中 %d"
          % (nvert, len(joints), sum(1 for c in cnt if c), len(zero), nface))
    if a.out:
        Path(a.out).write_text(txt, encoding="utf-8")
        print("   已写出 %s（%d B）" % (a.out, Path(a.out).stat().st_size))
    else:
        print(txt[:2600])


if __name__ == "__main__":
    main()
