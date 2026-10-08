--[[
	umatide.lua —— 把外部角色模型【作为原版资源】交给引擎，而不是在运行期替换它

## 它与社区做法（QIangIQsCitlali / SimplySimpleDogReplacer）的根本差别

社区做法：**隐形替身**
   · 等游戏把原单位生成出来
   · 把原单位隐藏（渲染 + scene query）
   · 旁边【另生成】一个纯视觉单位
   · 每帧抄 transform
   ⇒ 代价：视觉体【不注册 gameplay 扩展】（`spawn_with_extensions = false`）
     ⇒ ⇒ 它【拿不到动画系统/武器挂载/挂点】⇒ 这些都要自己做

本 mod 做法：**占据资源名**
   · 在【玩家单位生成之前】把
       content/characters/player/human/third_person/base
     这个资源名指向【我们的 unit】
   · 之后玩家 spawn 链加载到的就是我们的 unit
   ⇒ ⇒ 而玩家 spawn 链【自带 unit_template】⇒ 扩展管理器按它添加【全套玩家扩展】
     ⇒ ⇒ ⇒ 动画（AuthoritativePlayerUnitAnimationExtension）/ 视觉挂载（PlayerUnitVisualLoadoutExtension）
           / 瞄准 / 移动 / 生命 … 全部【原生接管】
   ⇒ 代价：无需运行期补任何东西（这正是我们要的）

## 为什么用 SimpleAssets.replace_unit 而不是编译期 --asset-path

两条都能达到目的，但：
  · replace_unit 是【社区件的能力】⇒ 与社区做法对齐，且不依赖我们自己的编译约定
  · 它的语义（SimpleAssets 文档原文）：
      "Replacement functions load a source asset and then replace future engine lookups
       of a target resource."
      "replace_unit affects units spawned AFTER its Promise resolves;
       it does not change a unit that is already present in a world."
  ⇒ ⇒ 所以【必须在玩家生成之前注册】—— 本文件在 mod 加载时立即注册。

## 现状

★ 默认【关】（`rig_replace = false`）⇒ 不改变任何现有行为。
★ 打开方式：见 umatide_data.lua。
]]

local mod = get_mod("umatide")

local Umatide = {}

-- 玩家骨架 rig 的资源名（出处：scripts/settings/breed/breeds/human_breed.lua:L19
--   base_unit = "content/characters/player/human/third_person/base"）
Umatide.TARGET_RIG = "content/characters/player/human/third_person/base"

-- 我们的 unit：相对【本 mod 的 assets 目录】（SimpleAssets 的路径规则）
--   mods/umatide/assets/units/agnes_test_all.unit
Umatide.SOURCE_UNIT = "units/agnes_test_all.unit"

Umatide.done = false
Umatide.result = nil

local function log(fmt, ...)
	mod:info("[umatide] " .. fmt, ...)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 注册（只做一次）
-- ─────────────────────────────────────────────────────────────────────────────
function Umatide.install()
	if Umatide.done then
		return
	end
	Umatide.done = true

	-- 开关：只在显式打开时动作（默认关 ⇒ 零副作用）
	local on = mod:get("rig_replace")
	if on ~= true then
		log("rig_replace 未开启 ⇒ 不注册资源替换（本 mod 当前不改变任何行为）")
		log("  目标 = %s", Umatide.TARGET_RIG)
		log("  源件 = %s", Umatide.SOURCE_UNIT)
		return
	end

	local SimpleAssets = get_mod("SimpleAssets")
	if not SimpleAssets then
		mod:error("需要 SimpleAssets（info.json 已声明为前置）。未找到 ⇒ 不注册。")
		return
	end
	if type(SimpleAssets.replace_unit) ~= "function" then
		mod:error("SimpleAssets 在场但【没有 replace_unit】⇒ 版本过旧？不注册。")
		return
	end

	log("★ 注册资源替换：%s  ←  %s", Umatide.TARGET_RIG, Umatide.SOURCE_UNIT)

	-- replace_unit 返回 Promise；结果里 is_ok / target_resource_name / source_resource_name / error
	local ok, promise_or_err = pcall(SimpleAssets.replace_unit, Umatide.TARGET_RIG, Umatide.SOURCE_UNIT)
	if not ok then
		mod:error("replace_unit 调用抛错：%s", tostring(promise_or_err))
		return
	end

	if type(promise_or_err) == "table" and promise_or_err.next then
		promise_or_err:next(function(result)
			Umatide.result = result
			if result and result.is_ok then
				log("✅ 替换已注册：target=%s ｜ source=%s",
					tostring(result.target_resource_name), tostring(result.source_resource_name))
				log("   ⇒ 此后【新生成】的玩家单位会用我们的 unit；已存在的单位不重建。")
			else
				mod:error("替换失败：is_ok=%s ｜ error=%s",
					tostring(result and result.is_ok), tostring(result and result.error))
			end
		end, function(err)
			mod:error("替换 Promise 被拒：%s", tostring(err))
		end)
	else
		log("replace_unit 返回了非 Promise：%s", tostring(promise_or_err))
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 入口
-- ─────────────────────────────────────────────────────────────────────────────
mod.on_all_mods_loaded = function()
	Umatide.install()
end

-- 兜底：若 on_all_mods_loaded 未被触发，则首次 update 时注册
--   （仍然【早于】玩家单位生成 —— update 在进入任务之前就跑）
local tried_update = false
mod.update = function()
	if not tried_update then
		tried_update = true
		if not Umatide.done then
			Umatide.install()
		end
	end
end

-- 控制台命令：查看状态 / 手动注册
mod:command("umatide", "umatide 状态", function()
	log("状态：已注册=%s ｜ 开关=%s", tostring(Umatide.done), tostring(mod:get("rig_replace")))
	log("  目标 = %s", Umatide.TARGET_RIG)
	log("  源件 = %s", Umatide.SOURCE_UNIT)
	if Umatide.result then
		log("  结果：is_ok=%s ｜ target=%s ｜ source=%s ｜ error=%s",
			tostring(Umatide.result.is_ok), tostring(Umatide.result.target_resource_name),
			tostring(Umatide.result.source_resource_name), tostring(Umatide.result.error))
	else
		log("  结果：尚未返回")
	end
end)

return Umatide
