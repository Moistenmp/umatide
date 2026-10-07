# -*- coding: utf-8 -*-
r"""mf_sm_reverse.py —— 把游戏状态机里的哈希**全量反查成明文**（只读）

## 为什么做这个

我们已确认：社区工具链对"接入游戏自己的状态机"这一格【没有提供任何东西】
（addon 原文："automatic state retirement is not provided"；README 不提 blend_base_layer）。
⇒ 所以要自己解：先拿到【游戏那个 unarmed 状态机里到底有哪些名字】。

手上有：
  · 抽出的状态机：`_staging\dt_sm\content\characters\player\human\third_person\animations\unarmed.state_machine`
  · 明文字典：`_reference\tools\limn-0.7.2\...\dictionary_hashcat_dt.txt`（19.6 MB，每行一个明文名）
  · murmur64：`reference_skeleton._murmur64`

## 做法

 ① 读字典 → 建 {h32: name}（状态机里多用 IdString32）
 ② 扫状态机全部 4 字节对齐的 u32 → 能命中的收集起来
 ③ 按"首次出现偏移"排序输出；并统计高频名（变量/状态/事件通常反复出现）

用法：python system\tools\mf_sm_reverse.py <state_machine> [--dict <path>] [--top 200]
"""
import argparse
import importlib.util
import struct
from collections import Counter
from pathlib import Path

ROOT = Path(r"D:\02_Projects\Darktide")
_A = ROOT / "_reference/_incoming_updates/Darktide-Asset-Compiler_sd_20261003/addon/darktide_assets"
_s = importlib.util.spec_from_file_location("rs", _A / "reference_skeleton.py")
_RS = importlib.util.module_from_spec(_s)
_s.loader.exec_module(_RS)

DEFAULT_DICT = (ROOT / "_reference/tools/limn-0.7.2/limn-0.7.2-x86_64-pc-windows-msvc/"
                        "dictionary_hashcat_dt.txt")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sm")
    ap.add_argument("--dict", default=str(DEFAULT_DICT))
    ap.add_argument("--top", type=int, default=200)
    a = ap.parse_args()

    # ① 建字典
    m = {}
    n = 0
    with open(a.dict, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            s = line.rstrip("\n").rstrip("\r")
            if not s:
                continue
            n += 1
            m.setdefault(_RS._murmur64(s) >> 32, s)
    print("   字典 %d 行 ｜ 唯一 h32 %d" % (n, len(m)))

    # ② 扫状态机
    b = Path(a.sm).read_bytes()
    hits = []
    cnt = Counter()
    for off in range(0, len(b) - 4, 4):
        v = struct.unpack_from("<I", b, off)[0]
        s = m.get(v)
        if s:
            hits.append((off, s))
            cnt[s] += 1

    print("   状态机 %s ｜ %d B ｜ 4 字节对齐扫描命中 %d 处 ｜ 唯一名 %d"
          % (Path(a.sm).name, len(b), len(hits), len(cnt)))
    if not hits:
        print("   ★ 未命中 —— 可能该文件用 64 位哈希，或字典不含这些名")
        return

    out = []
    out.append("# 游戏状态机哈希反查：%s\n" % Path(a.sm).name)
    out.append("文件 %d B ｜ 命中 %d 处 ｜ 唯一名 %d\n" % (len(b), len(hits), len(cnt)))
    out.append("\n## 按出现次数（高频通常是变量/状态/事件名）\n")
    out.append("| 名字 | 次数 | 首次偏移 |")
    out.append("|---|---:|---:|")
    first = {}
    for off, s in hits:
        first.setdefault(s, off)
    for s, c in cnt.most_common(a.top):
        out.append("| `%s` | %d | %d |" % (s, c, first[s]))
    out.append("\n## 按首次出现偏移（看文件结构顺序）\n")
    out.append("| 偏移 | 名字 |")
    out.append("|---:|---|")
    seen = set()
    for off, s in hits:
        if s in seen:
            continue
        seen.add(s)
        out.append("| %d | `%s` |" % (off, s))
        if len(seen) >= a.top * 3:
            break
    txt = "\n".join(out) + "\n"
    p = ROOT / "_reports" / ("2026-10-08_游戏状态机反查_%s.md" % Path(a.sm).stem)
    p.write_text(txt, encoding="utf-8")
    print("   已写出 %s（%d B）" % (p, p.stat().st_size))
    print("\n   高频前 25：")
    for s, c in cnt.most_common(25):
        print("      %-40s %d" % (s[:39], c))


if __name__ == "__main__":
    main()
