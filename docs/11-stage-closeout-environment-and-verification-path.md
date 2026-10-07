# 换模链 · 全量环境同步与验证路径（收口件 · 2026-10-08）

> **用途**：把本阶段的环境、验证通道、突破点与未解项一次性固化，供本地 git 保存、
> 供 uma 侧钩子同步、供 GitHub 发布。
> **上位件**：`_reports\2026-10-08_换模链_验证通道固化与审计.md`（同日的通道固化件）

---

## 0 ★★★ 本阶段最重要的单一发现：**编译器版本是隐藏变量**

```
同一 GLB + 同一条命令 + 两个不同的编译器二进制 ⇒ 行为不同，且【产出体积完全相同】

  旧 09-30 `_reference\tools\darktide-asset-compiler\unpacked\`
     MD5 71FC7B2D8D253B3531E93D953D997BC8 ｜ 7,298,048 B ｜ 09-30 01:45
     ⇒ 不置 unit 的 +0x2b0 flag（= 引擎不创建 animation blender）
     ⇒ 调用 Unit.enable_animation_state_machine 必崩：0xc0000005 @0x38（实测两次）
  新 10-03 `_reference\_incoming_updates\Darktide-Asset-Compiler_sd_20261003\unpacked\`
     MD5 892D16C4268ECFBC56FD652542A17CDA ｜ 7,643,136 B ｜ 10-03 14:17
     ⇒ 置 flag=1 ⇒ 引擎创建 blender ⇒ enable 成功（实测 has前/enable/has后 全 true）
```

**⇒ 这类变量的性质：没有任何体积/校验信号提示你拿错了二进制。**
**⇒ 处置：旧目录已写入 `DO_NOT_USE_README.txt`；判定工具 `system\tools\mf_flag_check.py`。**

---

## 1 ★ 环境（当前线上 = 代号 B）

| 项 | 值 |
|---|---|
| **资产** | `mods\ModelForge\Custom\AgnesTestAll\` |
| **unit** | `agnes_test_all.unit` 770,132 B ｜ **flag=1** ｜ `valid UNIT v115` ｜ 318 节点 ｜ 20 物理体 |
| **状态机** | `agnes_test_all.state_machine` **16,665 B** ｜ 含 `loop` + 39 根 dangle 约束 |
| **动画** | `_animation_0/1/2` = 646,250 / 673,242 / 388,786 B（三 clip） |
| **骨** | `agnes_test_all_bones.bones` 5,048 B ｜ 名表 256 |
| **材质槽** | 9（0-2 身体+Alpha层 ｜ 3-4 face/face.001 ｜ 5 eye ｜ 6 hair ｜ 7 mayu★占位 ｜ 8 tail） |
| **entries** | `character_agnes_test_all` = `current = true` |
| **DEFAULTS** | `enable_rt2 = false` ｜ `enable_soften = false` |
| **运行侧** | `attach_official.lua`：spawn 后 `enable_animation_state_machine` ｜ `ModelForge_attach.lua`：每帧读 locomotion 写 `move_speed` |

**B = `--loop-clip 0`（已验证的 locomotion 路径，不冻结）+ 39 根 dangle 约束。**

---

## 2 ★ 验证通道（可复现，全部本地）

### 2.1 编译器（**必须用这个**）

```
GOOD = D:\02_Projects\Darktide\_reference\_incoming_updates\Darktide-Asset-Compiler_sd_20261003\unpacked\DarktideGLBCompiler.exe
```

### 2.2 代号 B 的编译命令

```
<GOOD> _staging\release\v2\all3_dangle.glb -o <OUT> \
        --asset-path content/mods/probe/unit/agnes_test_all --loop-clip 0
```
**⇒ `all3_dangle.glb` = `all3.glb` + 39 根带权配件骨的 dangle extras（由 `mf_write_dangle.py` 生成）**

### 2.3 判定（三条）

| 判据 | 工具/方法 | 期望 |
|---|---|---|
| **flag 字节** | `python system\tools\mf_flag_check.py <file.unit>` | **flag=1** |
| **形式闸门** | `<GOOD> --validate <file.unit>` | **`valid UNIT v115`** |
| **状态机内容** | 同上工具（murmur64 高32 命中） | 含 `loop`（B）/ 或变量与状态名 |

### 2.4 部署链（顺序不能变）

```
① 显式逐个 Copy-Item（⛔ 递归 Get-ChildItem|ForEach Copy-Item 会静默失败，实测两次）
② python system\tools\mf_manifest_sync.py --asset-dir <目录> --apply   （自证必须 0 不一致）
③ custom-assets-patcher.exe                                            （期望 279 cooked resources、SUCCESS）
④ 复核 flag + --validate
```

### 2.5 实机判据（日志两行）

```
[attach2] ★状态机启用：has前=true ｜ enable=true(nil) ｜ has后=true ｜ 件=…
[mf-smvar] #N ｜ 速度来源=locomotion ｜ move_speed=<值> ｜ 写入=<ok(idx=N)|no-var>
```

---

## 3 ★ 本阶段已成立的成果

| # | 成果 | 证据 |
|---|---|---|
| **1** | **VMD 表达被引擎复现** | 作者实机确认 |
| **2** | **引擎认得并启用我方状态机** | `has前=true ｜ enable=true ｜ has后=true` |
| **3** | **配件骨全部存活**（尾5/耳8/面79/裙10/发37/缎带2） | 256 名表计数 |
| **4** | **dangle 被编译器接受并进状态机** | `.state_machine` 267 B（无 dangle）→ 16,665 B（`--loop-clip`+dangle）｜ 编译器字符串 `STATE_MACHINE pendulum/jiggle` |
| **5** | **发/尾/裙在实机被驱动** | 作者截图确认 |
| **6** | **比例仍是我们的** | 骨段和比 0.8940 |
| **7** | **权重未丢** | 产物侧面骨带权 80 = uma 侧 80 |

---

## 4 ★ 未解项（三条，边界清楚）

| # | 问题 | 已知 | 缺 |
|---|---|---|---|
| **1** | **locomotion 的正解** | 游戏 `unarmed` 状态机**没有 walk/run**（只有 `move_fwd`/`move_bwd` + `land_*`/`airtime_*`/`falling`/`ragdoll`/`dodge` 等）；**速度是 BLEND 不是状态**（API 名即 `set_animation_state_machine_blend_base_layer`） | blend base layer 的 NAME 语义与接入方式（**社区零文档**） |
| **2** | **嘴周消失** | **不是 morph**（`morph_targets=0`）｜**不是丢权重**（80=80） | 材质槽 [3]`face` 与 [4]`face.001` 共用同一张 diff ⇒ 需确认两层各自的 alphaMode/排序 |
| **3** | **手臂摆动平面（前后→T型）** | uma §25.5：他们**没有**施加滚转约定 ⇒ 我方改 `--roll b`（社区成熟件默认"最小滚转"）方向正确 | 尚未重跑验证 |

---

## 5 ★ 社区工具链的边界（结论，有原文依据）

```
✅ 已验证：资产侧声明状态/变量/转移（addon UI：State name/Clip/Variable/From-To/Event/Blend/Variable index）
           + mod 侧 Unit.enable_animation_state_machine(unit)（README L75/L139/L253）
           + dangle（addon 一等公民）
❌ 没有的：addon 原文 L180 ——
             "Create a one-state controller for the selected clip;
              ★ automatic state retirement is not provided"
           ⇒ 【状态之间怎么自动切换】，工具链没有提供
           ⇒ 而"接入游戏自己的状态机 / blend base layer"这一步：
             README 一个字不提、addon 无入口、无示例
⇒ ⇒ 我们已走出社区那条路。这一格由我们自己解。
```

---

## 6 ★ 给 uma 的钩子（他们要的东西都已产出）

| # | 交付 | 路径 |
|---|---|---|
| **1** | **逐骨顶点权重统计（面骨 80 根明细 + 零权 59 根）** | `D:\02_Projects\uma musume\HANDOFF_20261008_逐骨顶点权重统计_嘴周对表输入.md` |
| **2** | **本收口件** | 见本文件（可复制一份过去） |
| **3** | **等待他们的** | ① 面部两层 [3]/[4] 的 alphaMode/排序意图 ② dangle 参数标定表（可选，已有可用默认值） |

**⇒ 同步方式：放入 `D:\02_Projects\uma musume\`（他们的钩子会拾取）。**

---

## 7 ★ GitHub 同步准备（待执行）

```
① 本地 git：本文件与全部工具/报告提交（提交口：本次收口）
② 仓库：D:\02_Projects\umatide（已存在的公开仓库，此前收过 uma 的投稿）
③ 待推内容：
   · system\tools\mf_flag_check.py            —— flag 判据工具（本阶段最关键的可复用件）
   · system\tools\mf_write_dangle.py          —— dangle extras 写入器（按社区 schema）
   · system\tools\mf_bone_weight_stats.py     —— 逐骨权重统计（uma §25.6 要的）
   · system\tools\mf_sm_reverse.py            —— 状态机哈希全量反查（字典驱动）
   · system\tools\mf_manifest_sync.py         —— 通用 build.json 对齐（替代硬编码版）
   · _reports\2026-10-08_*.md                 —— 通道固化 / 审计 / 权重统计 / 状态机反查
④ ⛔ 不推：编译器二进制、游戏资产、任何 .unit/.bones/.texture
```

---

## 8 ★ 最短复现（给下一个会话）

```
1. 读本文件 + `_reports\2026-10-08_换模链_验证通道固化与审计.md`
2. 用 GOOD 编译器 + §2.2 命令编译 `_staging\release\v2\all3_dangle.glb`
3. mf_flag_check 必须 flag=1；--validate 必须 valid；
4. mf_manifest_sync --apply 自证 0 不一致 ⇒ patcher ⇒ SUCCESS
5. 重启游戏 ⇒ 日志两行（§2.5）
6. 若要走 locomotion 正解 ⇒ 见 §4-#1（blend base layer，需自己解）
```

---

> **范围声明（Scope and limitations）：** 由于本人的开发经验不足和技术判断有部分偏差，我的这些解法很多时候都走了大量试错，所以我能提供的只有一个验证过的通道，而非技术上的唯一解法
>
> *Due to my limited development experience and some deviations in my technical judgement, many of these solutions went through a great deal of trial and error, so what I can provide is only one verified path, not the only technical solution.*
>
> **⇒ 这是一条被验证过的通道，不是唯一解法。** 详见 `README.md` §7。
