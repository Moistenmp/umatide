return {
	umatide = {
		mod_name = {
			en = "umatide",
		},
		mod_description = {
			en = "Bring an external character model into Darktide as its own unit and let the engine "
				.. "drive it (animation, weapons, aim, locomotion), instead of replacing the player's "
				.. "body resource at runtime.",
		},
		model_enabled = {
			en = "Show the model",
		},
		model_enabled_tooltip = {
			en = "Spawn our unit, link it to the player unit with LINK_MODE_NODE_NAME and hand the "
				.. "driving to the engine. Off removes our unit and restores the vanilla body. "
				.. "/umatide on|off does the same in game.",
		},
		hide_vanilla_body = {
			en = "Hide the original visible body",
		},
		hide_vanilla_body_tooltip = {
			en = "The game sets the vanilla body parts back to visible on every visibility update; "
				.. "they are hidden again in the same frame, right after the game's own call. "
				.. "Weapon slots are explicitly excluded.",
		},
	},
}
