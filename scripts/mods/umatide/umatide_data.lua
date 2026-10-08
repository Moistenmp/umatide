--[[
	umatide_data.lua —— 本 mod 的默认设置

★ 命名纪律（全局 AGENTS 人类裁决 2026-09-14）：
  `moisten` 没有任何实际含义，是前期测试期的临时字段，属于待淘汰物。
  新增的 mod id / 目录名 / 标识符一律不得使用它。本 mod 用 `umatide`。
]]

return {
	name = "umatide",
	description = "umatide_mod_description",
	is_togglable = true,
	allow_rehooking = true,

	settings = {
		{
			setting_id = "rig_replace",
			type = "checkbox",
			default_value = false,
			-- ★ 默认【关】：本 mod 当前不改变任何行为。
			--   打开后才会把玩家骨架 rig 的资源名指向我们的 unit。
			title = "rig_replace",
			tooltip = "rig_replace_tooltip",
		},
	},
}
