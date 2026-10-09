--[[
	umatide.lua —— entry point: load our package, hand attachment to umatide_attach.lua

## What this mod does

  Brings an external character model (Agnes Digital) into Darktide as its **own unit**,
  driven natively by the engine (not a runtime replacement of the player's body resource):

    Custom Assets package (resources) --> umatide_attach.lua (spawn + link + visibility handover)
                                                     |
                                        engine drives by bone name: animation / weapon
                                        attach points / aim / locomotion

## Dependencies

  · **DMF**          -- mod framework (hooks, logging, chat commands)
  · **CustomAssets** -- resource layer: registers and loads our compiled .unit / .bones / materials
  · ~~SimpleAssets~~ -- no longer needed: the "replace a resource name at runtime" route does
                        not take effect on this game build

## Recipe provenance (rewritten, not copied)

  · attachment recipe: community mod QIangIQsCitlali (author QIangIQ, Nexus 1391)
  · asset toolchain:   fviuff's Darktide Asset Compiler and Custom Assets patcher

## Log contract

  Every line is English and greppable, with lua field names kept as-is, e.g.:
    [umatide][hook] / [umatide][diag] / [umatide][probe] / [umatide][pkg]

## Setting convention

  Behaviour defaults live in DEFAULTS below and are read through cfg(); `mod:get` only
  overrides. Measured twice on this project: DMF's settings table is never garbage collected,
  so "no widget in the UI" once meant "reads an old garbage value" and silently turned the
  behaviour off.
]]

local mod = get_mod("umatide")

mod.VERSION = "0.3.1"

-- ────────────────────────────────────────────────────────────────────────────
-- policy layer
-- ────────────────────────────────────────────────────────────────────────────

local DEFAULTS = {
	-- master switch (on by default: showing this model is the point of the mod)
	model_enabled = true,

	-- let the vanilla visible body give way (required for attaching; off means overlap)
	hide_vanilla_body = true,

	-- our Custom Assets package. Truth source: generated\manifest.lua, entry with
	-- logical_id = "umatide:AgnesDigital" -> its package_name field
	package_ids = {
		"umatide:AgnesDigital",
	},

	-- our compiled unit. Truth source: Custom/AgnesDigital/compile_manifest.json "asset_path"
	-- (umatide_attach.lua owns the authoritative value and overwrites this at load)
	unit = "content/mods/umatide/agnes_digital.unit",
}

local function cfg(key)
	local v = mod:get(key)
	if v == nil then
		return DEFAULTS[key]
	end
	return v
end

-- queries used by umatide_attach.lua (so it does not read the settings itself)
mod.umatide_cfg_bool = function (key)
	return cfg(key) ~= false
end
mod.umatide_model_on = function ()
	return cfg("model_enabled") ~= false
end

local function log(fmt, ...)
	local ok, msg = pcall(string.format, "[umatide] " .. fmt, ...)
	if ok then
		mod:info("%s", msg)
	else
		mod:info("[umatide] (format error) %s", tostring(fmt))
	end
end

-- ────────────────────────────────────────────────────────────────────────────
-- resources: hand our package to Custom Assets
-- ────────────────────────────────────────────────────────────────────────────

local custom_assets = nil
local ready = {}
local requested = {}
local ready_n = 0

mod.umatide_ready = function ()
	return ready_n > 0
end

local function acquire(id)
	if type(id) ~= "string" or id == "" or requested[id] then
		return
	end
	requested[id] = true
	if not custom_assets then
		return
	end
	local ok, ticket, err = pcall(function ()
		return custom_assets.acquire(mod, id, function (_, _, load_error)
			if load_error then
				mod:error("[umatide][pkg] load failed id=%s err=%s (run CUSTOM_ASSETS_PATCH.bat with the game closed)",
					tostring(id), tostring(load_error))
				return
			end
			ready[id] = true
			ready_n = ready_n + 1
			mod:info("[umatide][pkg] ready id=%s", tostring(id))
		end, { resident = true })
	end)
	if not ok then
		mod:error("[umatide][pkg] acquire raised id=%s err=%s", tostring(id), tostring(ticket))
		return
	end
	if ticket == nil then
		mod:error("[umatide][pkg] acquire refused id=%s err=%s", tostring(id), tostring(err))
		return
	end
	log("[pkg] requested id=%s", tostring(id))
end

-- ────────────────────────────────────────────────────────────────────────────
-- prerequisite self report
--   The predicate must be `get_mod(name) ~= nil`: DMF mods are not globals, so
--   rawget(_G, ...) reports every present prerequisite as missing (measured false negative).
-- ────────────────────────────────────────────────────────────────────────────

local function report_prereqs()
	for _, name in ipairs({ "DMF", "CustomAssets" }) do
		log("[prereq] %s=%s", name, get_mod(name) ~= nil and "ok" or "MISSING")
	end
end

-- ────────────────────────────────────────────────────────────────────────────
-- boot
-- ────────────────────────────────────────────────────────────────────────────

local booted = false

mod.on_all_mods_loaded = function ()
	if booted then
		return
	end
	booted = true

	log("[load] version=%s channel=spawn+link (engine native driving)", mod.VERSION)
	report_prereqs()

	local Attach = mod:io_dofile("umatide/scripts/mods/umatide/umatide_attach")
	-- path convention matches DMF itself (dmf_loader.lua:17-27):
	--   <mod>/scripts/mods/<mod>/<file>, no .lua
	if type(Attach) ~= "table" then
		mod:error("[umatide] attach module failed to load, mod will do nothing")
		return
	end
	if type(Attach.UNIT) == "string" and Attach.UNIT ~= "" then
		DEFAULTS.unit = Attach.UNIT     -- single truth source: the line in the attach module
	end

	local ca = get_mod("CustomAssets")
	if not ca then
		mod:error("[umatide] CustomAssets not found (required), not attaching")
		return
	end
	if ca.is_api_compatible and not ca.is_api_compatible(1) then
		mod:error("[umatide] CustomAssets API is not 1, not attaching")
		return
	end
	custom_assets = ca

	local ids = cfg("package_ids")
	if type(ids) ~= "table" or #ids == 0 then
		mod:error("[umatide] package_ids is not set, not attaching")
		return
	end
	for i = 1, #ids do
		acquire(ids[i])
	end

	Attach.install()
end

-- per frame: the package is asynchronous, so retry and keep the handover applied from here.
-- Also carries the periodic summariser (below) so that a session always leaves evidence.
local summarise_at = 900        -- about 15 s at 60 fps
local gameplay_seen = false     -- set by on_game_state_changed (defined below), read here

mod.update = function ()
	if not booted then
		return
	end
	local A = mod.UmatideAttach
	if A and A.tick then
		pcall(A.tick)
	end
	if A and A.diag then
		local tick = A.diag.tick
		if tick >= summarise_at then
			summarise_at = summarise_at + 900
			local has_world = Managers.world ~= nil and Managers.world:world("level_world") ~= nil
			if A.diag_report then
				A.diag_report(string.format("periodic tick=%d level_world=%s gameplay_seen=%s",
					tick, tostring(has_world), tostring(gameplay_seen)))
			end
		end
	end
end

-- setting change -> recompute immediately
-- NOTE: this mod registers NO DMF widget (see umatide_data.lua), so this callback normally
-- never fires; it is kept so that adding a widget later needs no structural change. The
-- immediate effect today comes from /umatide on|off calling refresh directly.
mod.on_setting_changed = function ()
	if booted and mod.UmatideAttach and mod.UmatideAttach.refresh then
		pcall(mod.UmatideAttach.refresh)
	end
end

-- ────────────────────────────────────────────────────────────────────────────
-- self proof on entering gameplay
--
-- Why: two runs in a row produced a log that could not tell "never called" from
-- "called and returned early". This dumps the decisive counters the moment a gameplay
-- state is entered, with nobody having to type a command.
-- ────────────────────────────────────────────────────────────────────────────

mod.on_game_state_changed = function (status, state)
	if status ~= "enter" then
		return
	end
	local s = tostring(state)
	if s == "StateGameplay" or s == "GameplayStateInit" then
		gameplay_seen = true
		local A = mod.UmatideAttach
		if A and A.diag_report then
			A.diag_report("entered gameplay state=" .. s)
		end
	end
end

-- manual toggle: /umatide on|off applies immediately, /umatide diag dumps the counters
local function apply_toggle(on)
	mod:set("model_enabled", on, true)
	if booted and mod.UmatideAttach and mod.UmatideAttach.refresh then
		pcall(mod.UmatideAttach.refresh)
	end
	mod:echo("umatide model_enabled=%s", tostring(on))
end

mod:command("umatide", "umatide: on / off / diag / (no arg = status)", function (arg)
	local a = tostring(arg or ""):lower()
	if a == "on" or a == "1" then
		apply_toggle(true)
	elseif a == "off" or a == "0" then
		apply_toggle(false)
	elseif a == "diag" then
		local A = mod.UmatideAttach
		if A and A.diag then
			A.diag_report("manual /umatide diag")
			mod:echo("umatide diag tick=%s attach_calls=%s mine=%s attached=%s pkg_ready=%s",
				tostring(A.diag.tick), tostring(A.diag.calls), tostring(A.diag.mine),
				tostring(A.attached_count and A.attached_count() or 0), tostring(A.diag.ready_seen))
		else
			mod:echo("umatide attach module not loaded (booted=%s)", tostring(booted))
		end
	else
		mod:echo("umatide %s | model_enabled=%s | packages_ready=%d | unit=%s | /umatide diag for counters",
			mod.VERSION, tostring(mod.umatide_model_on()), ready_n, tostring(cfg("unit")))
	end
end)

return mod
