return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`umatide` encountered an error loading the Darktide Mod Framework.")

		new_mod("umatide", {
			mod_script       = "umatide/scripts/mods/umatide/umatide",
			mod_data         = "umatide/scripts/mods/umatide/umatide_data",
			mod_localization = "umatide/scripts/mods/umatide/umatide_localization",
		})
	end,
	-- ★ 不写 load_after：DMF 的加载顺序由 mod_load_order.txt 决定，
	--   而 SimpleAssets / CustomAssets 都必须在【本 mod 之前】加载
	--   （replace_unit 要在玩家单位生成之前注册完）。
	--   依赖关系写在 info.json 的 dependencies，便于人与管理器识别。
	packages = {},
}
