# 换模链 · 验证通道固化与审计（2026-10-08 凌晨）

> 目的：把今晚**已经打通**的东西固化成可复现的通道，防止后续丢失；并对当前内容做一次审计。
> 作者要求：① 干净测试环境 ② 验证通道落到本地 ③ 审计现有内容（含"手臂摆动方向不对"这条新观察）

---

## 0 ★ 今晚打通的（已成事实，不要再推翻）

| # | 事实 | 证据 |
|---|---|---|
| **1** | **编译器版本是隐藏变量** | 同一 GLB、同一 `--loop-clip 0`：<br>旧 `_reference\tools\darktide-asset-compiler\unpacked\`（09-30, MD5 `71FC7B2D8D253B35`）⇒ **flag=0**<br>新 `_reference\_incoming_updates\Darktide-Asset-Compiler_sd_20261003\unpacked\`（10-03, MD5 `892D16C4268ECFBC`）⇒ **flag=1**<br>两者产出**大小完全相同**（770,132 B），唯一差别是那个字节 |
| **2** | **`unit +0x2b0` 那个字节 = 引擎是否创建 animation blender** | 编译器源码注释：<br>*"the engine only creates the animation blender and instances the state machine named below when this is set"* |
| **3** | **flag=0 ⇒ `enable_animation_state_machine` 引擎级崩溃（0xc0000005 @0x38）** | 两次实测；与状态机内容无关（267 B 与 4398 B 崩在同一处） |
| **4** | **flag=1 ⇒ 启用成功** | 日志：`★状态机启用：has前=true ｜ enable=true(nil) ｜ has后=true` |
| **5** | **运行侧输入链通** | 日志：`[mf-smvar] #6000 ｜ 速度来源=locomotion ｜ move_speed=0.000 ｜ 写入=no-var`（当时件是最小循环机，故 no-var） |
| **6** | **变量驱动状态机版已部署** | `flag=1` ｜ `.state_machine` 860 B ｜ 含 `move_speed`/`idle`/`walk`/`run`（哈希复核全命中） |
| **7** | **VMD 表达已被复现** | 作者实机确认 |
| **8** | **配件骨全在名表里，没被 kill** | 我方 256 名表：尾 5 ｜ 耳 8 ｜ 面 79 ｜ 裙 10 ｜ 发 37 ｜ 缎带 2 |

**⇒ ⇒ 缺的不是"骨"，是【通道】与【物理定义】。**

---

## 1 ★★ 新观察的诊断：**前后摆臂 → 变成 T 型摆动**

### 1.1 结论（推断，但依据很强）

**这是【滚转约定（roll）】的签名，不是位移/朝向错误。**

```
mf_retarget_bind.py 有 --roll：
   a = 世界增量同构（原样搬运源的滚转）—— 闭式解本身      ← ★ 我们一直用的默认
   b = 最小滚转（保持指向，滚转走"从 bind 方向的最短弧"）
   依据：_reference\blender_BoneAnimCopy 源码
         ——【社区成熟件默认即"最小旋转"】，并把滚转暴露成可微调参数

而两套骨架的【静置朝向差异】实测：
   中位 55.11° ｜ 中位(另测) 23.93° ｜ 最大 171.51°
⇒ 差异这么大时，约定 a 会把源的滚转"原样搬"到朝向完全不同的骨上
   ⇒ 观感就是：手臂本该前后摆，却绕成了另一个平面（T 型）
```

### 1.2 与作者记忆里那个"90° 测试"的关系

```
今晚早前实测（--roll a vs --roll b 在 walk 上）：
   (a) 平均 45.54° ｜ 最大 91.14° ｜ 滚转占比 67.7%
   (b) 平均 28.87°                  ｜ 滚转占比 54.6%
⇒ ★ 最大 91.14° ≈ 90° ⇒ 与作者看到的"变成 T 型"在量级上一致
```

### 1.3 待验的最小实验（不改运行侧，只重跑 retarget + 重编）

```
① 用 --roll b 重跑三条 clip 的 retarget（其余参数与现件完全一致）
② 用 mf_glb_merge_clips.py 合并
③ 用【新版编译器 sd_20261003】编译
④ 量：flag=1 ｜ valid ｜ .state_machine 大小
⇒ 上机判据：手臂摆动平面是否回到【前后】
```

---

## 2 ★ 验证通道固化（可复现命令清单）

### 2.1 编译器（**必须用这个**）

```
GOOD = D:\02_Projects\Darktide\_reference\_incoming_updates\Darktide-Asset-Compiler_sd_20261003\unpacked\DarktideGLBCompiler.exe
       MD5 892D16C4268ECFBC56FD652542A17CDA ｜ 7,643,136 B ｜ 10-03 14:17
BAD  = D:\02_Projects\Darktide\_reference\tools\darktide-asset-compiler\unpacked\DarktideGLBCompiler.exe
       MD5 71FC7B2D8D253B3531E93D953D997BC8 ｜ 7,298,048 B ｜ 09-30 01:45   ← ⛔ 不置 flag，禁用
```

### 2.2 变量驱动状态机（当前线上形态）

```
<GOOD> _staging\release\v2\all3.glb -o <OUT> --asset-path content/mods/probe/unit/agnes_test_all \
  --sm-state idle 1 loop --sm-state walk 0 loop --sm-state run 2 loop \
  --sm-variable move_speed 0 0 10 \
  --sm-range-transition 0 1 mf_speed_change 0.2 0 0.05 2.0 inclusive exclusive \
  --sm-range-transition 1 0 mf_speed_change 0.2 0 0.0 0.05 inclusive inclusive \
  --sm-range-transition 1 2 mf_speed_change 0.2 0 2.0 99.0 inclusive exclusive \
  --sm-range-transition 2 1 mf_speed_change 0.2 0 0.05 2.0 inclusive exclusive
```
**⇒ ⚠ `EVENT_NAME` 不能是空串**（编译器报 `Invalid --sm-range-transition blend, variable, or bounds`）

### 2.3 判定脚本（三条，全部本地）

| 判据 | 命令 |
|---|---|
| **① flag 字节** | 找 unit 里 `content/mods/...` 字符串；其前 8 字节 `[.. .. .. F L L L L]` ⇒ **F 就是 flag**；`LLLL` = 字符串长度 |
| **② 状态机是否含变量/状态** | murmur64 高32 命中：`move_speed` / `idle` / `walk` / `run` |
| **③ 形式闸门** | `<GOOD> --validate <file.unit>` ⇒ 必须 `valid UNIT v115` |

### 2.4 部署链（顺序不能变）

```
① 覆盖 <资产目录>\{unit, state_machine, bones}
② python system\tools\mf_manifest_sync.py --asset-dir <资产目录> --apply     ← 补 size/crc，自证必须 0 不一致
③ custom-assets-patcher.exe                                                  ← 期望 cooked resource 数 +1
④ 复核 flag + --validate
```

**⇒ ⛔ 不要再用 `mf_align_manifest.py`**（它的 `TARGET_DIR` 硬编码为 `AgnesOwn1`，会改错目录）

---

## 3 ★ 审计：当前内容的问题清单

| # | 现象 | 判定 | 归属 |
|---|---|---|---|
| **1** | **手臂摆动平面不对（T 型）** | **滚转约定 `--roll a`** ⇒ 应改 `--roll b`（社区成熟件默认） | **retarget 层** |
| **2** | **尾/裙/发/缎带 自然下垂到脚底** | **无 `dangle` 定义**（实测 `"dangle"` 出现 0 次；20 个 extras 全是身体 ragdoll `mfcol_*`） | **GLB extras 层（工具链原生支持）** |
| **3** | **嘴周消失** | **不是 morph**（`morph_targets=0`）⇒ 几何/权重问题 | **几何层，待查** |
| **4** | **run 不切换** | 已部署变量驱动版 ⇒ **待上机验证** | **已解，待验** |
| **5** | 耳骨通道 | uma 已交（`agnes_digital_ear_only01/02.glb`，18 通道） | 待并 |
| **6** | `--roll` 之外还有 `--mapping`/`--formula` | 现用 `auto`/`c1`；`closed` 实测跨度更差（已排除） | 保持现状 |

---

## 4 ★ 交给 uma 处理的部分（清单）

```
① 通用【尾】处理 —— 他们说已有整套；请他们给：
     · dangle 记录的完整字段与量纲（mass/gravity/damping/stiffness/max_angle/length）
     · 以及它是否写在 GLB 的【节点 extras】还是 asset_definition
② 【耳/眼/其他通用组件】同样处理
③ 【裙/发/缎带】的 follow 与 dangle 分工（避免双重降幅 —— 他们 §21.1 已给规则）
④ 【嘴周消失】的几何排查（面骨 79 根都在名表里，所以不是缺骨）
⑤ 【手臂摆动平面】—— 请他们从他们那条链确认：他们交付件里的滚转约定是哪一种
     （若他们的 VMD 导出件本身带滚转，我们改 --roll b 可能与他们的原意不同）
```

---

## 5 ★ 环境清洁（作者要求"干净测试环境"）

| 项 | 现状 | 处理 |
|---|---|---|
| **旧编译器副本** | `_reference\tools\darktide-asset-compiler\unpacked\`（09-30, 不置 flag） | **改名或加 `DO_NOT_USE` 标记**，防止再被误用 |
| `AgnesTestAll` 目录内残留 | 曾出现 `agnes_body.unit` 854,018 B | 待确认是否属本资产；不属则移除 |
| 多版本构建物 | `_staging\{loopclip, nosa, sd1003, sd1003_var, smvar, formulatest, mathtest}` | 保留 `sd1003_var`（现线上形态）+ `sd1003`（对照），其余可归档 |
| ModelForge 旧测试开关 | `enable_rt2=false`（已关，正确）、`enable_soften=false` | 保持 |

---

## 6 ★ 最短复现路径（给下一个会话/给 uma）

```
1. 读本文件
2. 用【GOOD 编译器】+ §2.2 命令重编 all3.glb ⇒ 必须 flag=1、valid
3. mf_manifest_sync.py --apply ⇒ 自证 0 不一致
4. custom-assets-patcher.exe ⇒ SUCCESS
5. 重启游戏 ⇒ 日志应出现：
      [attach2] ★状态机启用：has前=true ｜ enable=true ｜ has后=true
      [mf-smvar] #N ｜ 速度来源=locomotion ｜ move_speed=<随移动变化> ｜ 写入=ok(idx=N)
6. 若手臂摆动平面仍不对 ⇒ 改 retarget 的 --roll b 重跑 §2.2
```
