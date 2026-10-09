# -*- coding: utf-8 -*-
r"""umatide_map_lr_check.py —— 给"跨侧数据"的左右一致性自证（补盲区）

	背景（2026-10-09，uma 报错引发）：
	  bone_integration_map.json 曾把【所有右侧骨的父】写成左侧（镜像错误）。
	  我方闸门体系都是对【我方件】做的 ⇒ 查不出这张"给 uma 用的映射表"里的错。
	判据（三类）：
	  ① 右侧骨（source_bone 以 _R 结尾）的 engine_parent_name 不得含 left
	  ② 左侧骨（_L 结尾）的父不得含 right
	  ③ 左右对称性：对 (X_L, X_R) 两侧同名骨，其父去掉侧向后应相同
	用法：python system\tools\umatide_map_lr_check.py [map.json]
	退出码：0 通过 / 1 不通过
"""
import json
import re
import sys
from pathlib import Path

MAP = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"rules\data\bone_integration_map.json")


def side(name):
    if not name:
        return None
    if re.search(r"(^|_)left|_L$", name) or name.startswith("左"):
        return "L"
    if re.search(r"(^|_)right|_R$", name) or name.startswith("右"):
        return "R"
    return None


def unsided(name):
    if not name:
        return name
    n = re.sub(r"(^|_)left", lambda m: m.group(1) + "SIDE", name)
    n = re.sub(r"(^|_)right", lambda m: m.group(1) + "SIDE", n)
    n = re.sub(r"_L$", "_SIDE", n)
    n = re.sub(r"_R$", "_SIDE", n)
    n = n.replace("左", "SIDE").replace("右", "SIDE")
    return n


def main():
    d = json.loads(MAP.read_text(encoding="utf-8"))
    rows = d.get("map", [])
    bad = []
    # ① / ②
    for r in rows:
        sb, p = r.get("source_bone"), r.get("engine_parent_name")
        s = side(sb)
        if not s or not p:
            continue
        if s == "R" and re.search(r"left|左", p):
            bad.append((sb, p, "右侧骨的父指向左侧"))
        if s == "L" and re.search(r"right|右", p):
            bad.append((sb, p, "左侧骨的父指向右侧"))
    # ③ 对称性
    by = {}
    for r in rows:
        sb = r.get("source_bone")
        s = side(sb)
        if not s:
            continue
        by.setdefault(unsided(sb), {})[s] = r.get("engine_parent_name")
    asym = []
    for k, v in by.items():
        if "L" in v and "R" in v:
            gl, gr = unsided(v["L"]), unsided(v["R"])
            if gl and gr and gl != gr:
                asym.append((k, v["L"], v["R"]))
    print("   映射表：%d 行 ｜ ★违例 %d 条 ｜ ★左右不对称 %d 条" % (len(rows), len(bad), len(asym)))
    for sb, p, why in bad[:10]:
        print("      ⛔ %-14s 父 %-20s（%s）" % (sb, p, why))
    for k, pl, pr in asym[:10]:
        print("      ⚠ %-14s 父 L=%-18s R=%-18s（去侧向后不同）" % (k, pl, pr))
    return 0 if not bad and not asym else 1


if __name__ == "__main__":
    sys.exit(main())
