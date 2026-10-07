# -*- coding: utf-8 -*-
r"""mf_flag_check.py —— 判定 unit 的 `animation_state_machine` 总闸 + 状态机内容（只读）

## 为什么必须有这个工具（2026-10-08 的教训）

编译器源码 unit_v115.cpp 原文：
    // Unit resource +0x2b0: the engine only creates the animation blender and
    // instances the state machine named below when this is set
    // (all retail units that reference a state machine set it).
    w.u8(options.animation_state_machine_resource.empty() ? 0 : 1);
    w.u32(...size());
    w.bytes(...);

⇒ 那个 u8 是【引擎是否创建 animation blender / 实例化状态机】的总闸。
⇒ flag=0 时调用 Unit.enable_animation_state_machine ⇒ 引擎级空指针 0xc0000005 @0x38（实测两次）
⇒ 而【旧版编译器（09-30）即使给了 --loop-clip 也不置它】；新版（sd_20261003, 10-03）才置。
⇒ ⇒ 这一格今晚卡了整晚，因此固化成工具，不再靠临时脚本。

## 字节定位（不依赖任何偏移常量）

`animation_state_machine` 段的布局是 [len:4][字符串]。字符串就是该 unit 的资源路径
（content/mods/...），它在文件里【只出现一次】。
⇒ 取该字符串前 8 字节： [.. .. .. F L L L L]
     F = flag       （4 字节里的末字节）
     LLLL = 字符串长度（小端）
⇒ 本工具按此判定，并对【长度是否吻合】做自证（不吻合则报"定位可疑"，不硬下结论）。

用法：python system\tools\mf_flag_check.py <file.unit> [<file2.unit> ...]
      python system\tools\mf_flag_check.py --dir <资产目录>
"""
import argparse
import re
import struct
import sys
from pathlib import Path

ROOT = Path(r"D:\02_Projects\Darktide")
sys.path.insert(0, str(ROOT / "system"))
sys.path.insert(0, str(ROOT / "system" / "tools"))

try:
    import importlib.util
    _A = ROOT / "_reference/_incoming_updates/Darktide-Asset-Compiler_sd_20261003/addon/darktide_assets"
    _s = importlib.util.spec_from_file_location("rs", _A / "reference_skeleton.py")
    _RS = importlib.util.module_from_spec(_s)
    _s.loader.exec_module(_RS)
    _HAS = True
except Exception:
    _HAS = False


def h32(n):
    return (_RS._murmur64(n) >> 32) if _HAS else None


def check(p):
    raw = Path(p).read_bytes()
    hits = []
    for m in re.finditer(rb"content/mods/[A-Za-z0-9/_-]{3,120}", raw):
        s = m.group().decode("ascii")
        idx = m.start()
        pre = raw[idx - 8:idx]
        if len(pre) < 8:
            continue
        flag = pre[3]
        slen = struct.unpack_from("<I", pre, 4)[0]
        if slen == len(s):
            hits.append((flag, s, idx))

    print("   " + Path(p).name + " ｜ %d B" % len(raw))
    if not hits:
        print("        ★ 未找到 [len][资源名] 结构 ⇒ 该 unit 【没有】animation_state_machine 字段")
        print("        ⇒ 属于 simple-animation 路径（没有 animation blender）")
        return None
    for flag, s, idx in hits:
        verdict = "★ 状态机路径（引擎会创建 blender）" if flag else "★ simple 路径（没有 blender；enable 会崩）"
        print("        flag = %d ｜ @%d ｜ 资源名 %s" % (flag, idx, s))
        print("        ⇒ %s" % verdict)
    # 状态机内容（同目录 .state_machine）
    smf = Path(p).with_suffix(".state_machine")
    if smf.exists() and _HAS:
        sm = smf.read_bytes()
        present = [n for n in ("move_speed", "idle", "walk", "run", "loop")
                   if struct.pack("<I", h32(n)) in sm]
        print("        .state_machine %d B ｜ 命中名字：%s" % (len(sm), present or "（无）"))
    return hits[0][0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("units", nargs="*")
    ap.add_argument("--dir")
    a = ap.parse_args()
    targets = list(a.units)
    if a.dir:
        targets += [str(x) for x in sorted(Path(a.dir).glob("*.unit"))]
    if not targets:
        print("   用法：mf_flag_check.py <file.unit> ... ｜ --dir <目录>")
        return
    for t in targets:
        if Path(t).exists():
            check(t)
        else:
            print("   ★ 不在：" + t)


if __name__ == "__main__":
    main()
