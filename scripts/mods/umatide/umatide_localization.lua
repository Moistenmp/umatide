return {
	umatide = {
		mod_name = {
			en = "umatide",
			["zh-cn"] = "umatide",
		},
		mod_description = {
			en = "Import an external character model into Darktide and let the engine drive it, "
				.. "instead of replacing it at runtime.",
			["zh-cn"] = "把外部角色模型导入暗潮，并让引擎去驱动它，而不是在运行期替换它。",
		},
		rig_replace = {
			en = "Take over the player rig resource",
			["zh-cn"] = "接管玩家骨架资源",
		},
		rig_replace_tooltip = {
			en = "Point content/characters/player/human/third_person/base at our own unit, so the player's own "
				.. "spawn chain loads our model and the engine mounts the full player extension set on it "
				.. "(animation, visual loadout, aim, locomotion). Off by default: with it off this mod changes "
				.. "nothing. It only affects units spawned after registration.",
			["zh-cn"] = "把 content/characters/player/human/third_person/base 指向我们自己的 unit，"
				.. "使玩家自己的 spawn 链加载我们的模型，并由引擎在其上挂载全套玩家扩展"
				.. "（动画、视觉挂载、瞄准、移动）。默认关闭：关闭时本 mod 不改变任何行为。"
				.. "它只影响注册之后新生成的单位。",
		},
	},
}
