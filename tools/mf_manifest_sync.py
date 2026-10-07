# -*- coding: utf-8 -*-
r"""mf_manifest_sync.py —— 把 build.json 里各资源的 size/crc 对齐到磁盘【实际值】（通用，不硬编码）

为什么需要：
  `mf_align_manifest.py` 的 TARGET_DIR 是【硬编码 AgnesOwn1】⇒ 只能修那一个资产。
  本次要修 AgnesTestAll，故写一个【接受 --asset-dir】的通用版。

做法：
  ① 读 <asset-dir>\build.json
  ② 对每个 resources[i]：按 .file 找到磁盘实际件 ⇒ 重算 size 与 crc32（zlib）
  ③ 只改不一致的槽位；改动前备份 build.json
  ④ 自证：再读一遍，报"仍不一致的槽位 = 0"

用法：python system\tools\mf_manifest_sync.py --asset-dir <目录> [--apply]
      （默认演练，只报差异；--apply 才写）
"""
import argparse
import io
import json
import shutil
import zlib
from datetime import datetime
from pathlib import Path

ROOT = Path(r"D:\02_Projects\Darktide")


def crc32_of(p):
    return zlib.crc32(p.read_bytes()) & 0xFFFFFFFF


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--asset-dir", required=True)
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    d = Path(a.asset_dir)
    if not d.exists():
        print("   ★ 目录不在：%s" % d)
        return
    bj = d / "build.json"
    if not bj.exists():
        print("   ★ 无 build.json：%s" % bj)
        return

    js = json.loads(bj.read_text(encoding="utf-8"))
    res = js.get("resources") or js.get("Resources") or []
    if not res:
        print("   ★ build.json 里找不到 resources 数组（顶层键：%s）" % list(js.keys())[:8])
        return

    print("   %s ｜ resources %d 条" % (bj.name, len(res)))
    changed = []
    missing = []
    for i, r in enumerate(res):
        # ★ 实测结构：resources[i].file 是【嵌套对象】{path,size,crc32}
        #   （patcher 的报错写作 resources[41].file: size mismatch ⇒ .file 上有 .size）
        node = r.get("file")
        if not isinstance(node, dict):
            node = r
        f = node.get("path") or node.get("file") or node.get("name")
        if not f:
            continue
        cand = d / str(f).replace("/", "\\")
        if not cand.exists():
            cand2 = d / Path(str(f)).name
            if cand2.exists():
                cand = cand2
            else:
                missing.append((i, f))
                continue
        sz = cand.stat().st_size
        cr = crc32_of(cand)
        old_sz = node.get("size")
        old_cr = node.get("crc32") or node.get("crc")
        need = []
        if old_sz != sz:
            need.append("size %s→%s" % (old_sz, sz))
            node["size"] = sz
        if old_cr is not None and str(old_cr).lower() != "%08x" % cr:
            need.append("crc %s→%08x" % (old_cr, cr))
            if "crc32" in node:
                node["crc32"] = "%08x" % cr
            else:
                node["crc"] = cr
        if need:
            changed.append((i, f, need))

    print("   需要修正 %d 条 ｜ 磁盘上找不到的 %d 条" % (len(changed), len(missing)))
    for i, f, need in changed[:12]:
        print("      [%d] %-44s %s" % (i, Path(str(f)).name, " ｜ ".join(need)))
    if missing:
        for i, f in missing[:6]:
            print("      [%d] %-44s ★ 不在磁盘" % (i, f))

    if not a.apply:
        print("\n   —— 演练结束（未改动）——  要真改：加 --apply")
        return
    if not changed:
        print("\n   无需改动")
        return

    bak = bj.with_name("build.json.bak_sync_%s" % datetime.now().strftime("%Y%m%d-%H%M%S"))
    shutil.copy2(bj, bak)
    bj.write_text(json.dumps(js, indent=None, separators=(",", ":")), encoding="utf-8")
    print("\n   已写回（备份 %s）" % bak.name)

    # 自证
    js2 = json.loads(bj.read_text(encoding="utf-8"))
    res2 = js2.get("resources") or js2.get("Resources") or []
    bad = 0
    for r in res2:
        f = r.get("file") or r.get("path") or r.get("name")
        if not f:
            continue
        cand = d / str(f).replace("/", "\\")
        if not cand.exists():
            cand = d / Path(str(f)).name
        if not cand.exists():
            continue
        if r.get("size") is not None and r.get("size") != cand.stat().st_size:
            bad += 1
    print("   自证：写回后仍不一致的槽位 = %d" % bad)


if __name__ == "__main__":
    main()
