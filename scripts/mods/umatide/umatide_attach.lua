--[[
	umatide_attach.lua —— hand our unit to the Darktide engine and let it drive

## Where the recipe comes from (rewritten to our own shape, not copied)

  · Attachment recipe: the community mod **QIangIQsCitlali** (Nexus 1391, author QIangIQ).
      It is a publicly distributed, working implementation of "spawn the external model as its
      own unit, link it to the player unit, and take over the vanilla body slots' visibility".
      This file re-implements that recipe in umatide's own terms: naming, structure, the
      visibility criteria, lifecycle reclamation and log layers are ours; nothing is copied
      line for line.
  · Asset toolchain: **fviuff**'s Darktide Asset Compiler + Custom Assets patcher.
      Our .unit / .bones come out of it; the resources are loaded through the Custom Assets
      package registry.

## Why "attach" and not "replace base_unit"

  · Replacing `Breeds.human.base_unit` crashed the engine twice (no Lua error).
  · Attaching is engine-native driving: our unit carries the character's node names in the
    same places, so `World.LINK_MODE_NODE_NAME` maps them name to name. Position following,
    animation, weapon attach points, aim and foot IK are then done by the engine.
    We write no bones, no per-frame transforms and no compensations.

## Offline facts about our unit (system\tools\umatide_nodes_audit.py)

    content/mods/umatide/agnes_digital.unit
      n_nodes=308 | named nodes 256 | exactly ONE node without a parent = engine node 1
      j_hips=28 | j_head=84 | j_righthand=207 | j_rightweaponattach=228 | j_leftweaponattach=71
    => the root is node 1 (same shape as the community citlali unit), so linking
       node 1 to node 1 by name is all that is needed.

## Runtime log contract

  Every line this file prints is **English and greppable**, with the lua field names kept
  as-is (`ext._unit`, `slot.unit_3p`, `update_item_visibility`, ...) so a log line can be
  matched against the decompiled source without translation.
]]

local mod = get_mod("umatide")

local Attach = {}

-- Our unit's **engine resource name**.
--
-- 2026-10-09, measured on the live run: this must NOT carry the file extension.
--   unit_spawner_manager.lua:586 reported `Unit not found #ID[d0f3a1e72fe261db]`, and
--   murmur64("content/mods/umatide/agnes_digital.unit") matches that ID exactly
--   (tool: system\tools\mf_umatide_name_hash.py) -> the engine looked up the string WITH
--   `.unit`, while the Custom Assets registry holds the resource under the name printed in
--   the manifest, which is this one WITHOUT the extension
--   (`compile_manifest.json "asset_path"`, `build.json roots[0].name`).
--   Cross-check: the decompiled `scripts` tree contains zero resource strings ending in
--   `.unit` -- every unit reference in the game is written without the extension.
Attach.UNIT = "content/mods/umatide/agnes_digital"

-- Secondary form, tried only if the primary returns nil (and logged as such).
Attach.UNIT_ALT = Attach.UNIT .. ".unit"

-- Only human: ogryn uses a different skeleton and we have not fitted it.
local EXCLUDED_BREEDS = { ogryn = true }

-- Vanilla visible-body slots to hide. Exact names plus the underscore variants only --
-- a "starts with slot_" catch-all would also swallow slot_primary / slot_secondary and the
-- symptom of that is "weapon mesh gone, particles still there" (measured on ModelForge).
local HIDDEN_SLOTS = {
	slot_body       = true,
	slot_body_1p    = true,
	slot_base       = true,
	slot_gear       = true,
	slot_gear_1p    = true,
	slot_attachment = true,
}

local function is_hidden_slot(slot_name)
	if slot_name == nil then
		return false
	end
	if HIDDEN_SLOTS[slot_name] == true then
		return true
	end
	return string.find(slot_name, "^slot_body_") ~= nil
		or string.find(slot_name, "^slot_gear_") ~= nil
		or string.find(slot_name, "^slot_base_") ~= nil
end

-- ────────────────────────────────────────────────────────────────────────────
-- helpers
-- ────────────────────────────────────────────────────────────────────────────

local function alive(u)
	return u ~= nil and Unit.alive(u)
end

local function local_player_unit()
	local ok, u = pcall(function ()
		local pm = Managers.player
		local p = pm and pm.local_player_safe and pm:local_player_safe(1)
		return p and (p.player_unit or p.unit)
	end)
	return ok and u or nil
end

-- Is this character unit the local player? Evidence only from references we have proven:
-- the local player unit handle, or a character we attached to ourselves.
local function is_mine(char_unit, ext)
	if not alive(char_unit) then
		return false
	end
	-- ★ 2026-10-09 修正：以【扩展实例的类身份】为主判据（Player 类=本地玩家；husk 类=别人）。
	--   原因：旧判据依赖运行时 local_player_unit()，关卡世界里该值实测为 nil ⇒ 闸门恒 false。
	if ext ~= nil and (ext.__umatide_local_class == true or ext.__umatide_ours == true) then
		return true
	end
	local lp = local_player_unit()
	if lp ~= nil and char_unit == lp then
		return true
	end
	if ext ~= nil and ext.__umatide_ours == true then
		return true
	end
	return false
end

local function breed_of(ext)
	local props = ext and ext._static_profile_properties
	return props and props.breed or nil
end

local function excluded(ext)
	local b = breed_of(ext)
	return b ~= nil and EXCLUDED_BREEDS[b] == true
end

-- one-shot log lines, deduplicated by key
local said = {}
local function say(key, fmt, ...)
	if said[key] then
		return
	end
	said[key] = true
	mod:info(fmt, ...)
end

-- ────────────────────────────────────────────────────────────────────────────
-- visibility handover
-- ────────────────────────────────────────────────────────────────────────────

-- Hide the vanilla units in one slot group (and their attachments).
local function hide_slots(slots, key)
	if type(slots) ~= "table" then
		return 0
	end
	local att_key = (key == "unit_1p") and "attachments_by_unit_1p" or "attachments_by_unit_3p"
	local n = 0
	for slot_name, slot in pairs(slots) do
		if is_hidden_slot(slot_name) and type(slot) == "table" then
			local u = slot[key]
			if alive(u) then
				Unit.set_unit_visibility(u, false, true)
				n = n + 1
				local att = slot[att_key] and slot[att_key][u]
				if type(att) == "table" then
					for i = 1, #att do
						if alive(att[i]) then
							Unit.set_unit_visibility(att[i], false, true)
							n = n + 1
						end
					end
				end
			end
		end
	end
	return n
end

-- Character body meshes on some paths do not go through the slot table.
-- NOT recursive: our unit is linked under the character root, so a recursive hide
-- would hide our unit together with the body.
local function set_body_objects_visible(char_unit, visible)
	if alive(char_unit) then
		pcall(Unit.set_unit_objects_visibility, char_unit, visible, false)
	end
end

Attach.keep_hidden = function (ext)
	if not mod.umatide_cfg_bool("hide_vanilla_body") then
		return 0
	end
	if not is_mine(ext and ext._unit, ext) then
		return 0
	end
	return hide_slots(ext._equipment, "unit_3p")
end

-- ────────────────────────────────────────────────────────────────────────────
-- lifecycle
-- ────────────────────────────────────────────────────────────────────────────

local function delete_unit(u)
	if alive(u) then
		local spawner = Managers.state and Managers.state.unit_spawner
		if spawner then
			pcall(spawner.mark_for_deletion, spawner, u)
		end
	end
end

local attached_n = 0     -- log only, never a driving input

local function despawn(ext)
	if type(ext) ~= "table" then
		return
	end
	local ok = pcall(function ()
		delete_unit(ext.__umatide_unit)
		ext.__umatide_unit = nil
		ext.__umatide_ours = nil
	end)
	if not ok then
		-- the unit is gone: touching the extension fields itself throws, so clean silently
		ext.__umatide_unit = nil
	end
	attached_n = math.max(0, attached_n - 1)
end
Attach.despawn = despawn

Attach.attached_count = function ()
	return attached_n
end

-- Spawn our unit and link it to the character.
--   · community-identical: World.LINK_MODE_NODE_NAME (the engine maps by bone name)
--   · root node = engine node 1 (offline measured: our only parentless node)
--
-- Name forms: the primary is the registry name (no extension). The `.unit` form is tried once
-- only as a fallback; if the primary works the alternative is never attempted, so no
-- misleading "not found" line reaches the log. The form that worked is remembered and logged.
local function spawn_and_link(world, char_unit)
	local spawner = Managers.state and Managers.state.unit_spawner
	if not (world and spawner and alive(char_unit)) then
		return nil, "world/unit_spawner/char_unit unavailable"
	end
	local pose = Unit.world_pose(char_unit, 1)
	local form = Attach.WORKING_NAME_FORM or Attach.UNIT
	local u
	local ok, res = pcall(function ()
		return spawner:spawn_unit(form, pose)
	end)
	if ok and alive(res) then
		u = res
	elseif not Attach.WORKING_NAME_FORM then
		-- primary failed: try the alternative once, quietly
		local alt = Attach.UNIT_ALT
		local ok2, res2 = pcall(function ()
			return spawner:spawn_unit(alt, pose)
		end)
		if ok2 and alive(res2) then
			u, form = res2, alt
		end
	end
	if not u then
		return nil, string.format("spawn_unit returned no unit for name '%s'", form)
	end
	Attach.WORKING_NAME_FORM = form
	local ok_link, err = pcall(World.link_unit, world, u, 1, char_unit, 1, World.LINK_MODE_NODE_NAME)
	if not ok_link then
		delete_unit(u)     -- never leave a floating unit behind
		return nil, "link_unit: " .. tostring(err)
	end
	-- Make it visible explicitly: linking changes the scene graph parent, and we do not want
	-- "is it visible after linking" to depend on an engine default.
	pcall(Unit.set_unit_visibility, u, true, true)
	return u
end

-- ────────────────────────────────────────────────────────────────────────────
-- diagnostic counters
--
-- Why they exist: the 2026-10-09 runs logged "hooks installed / package ready" and nothing
-- else, which cannot tell "never called" from "called and returned early". The counters can.
-- ────────────────────────────────────────────────────────────────────────────
local diag = { calls = 0, mine = 0, tick = 0, ready_seen = false, said = false }

local function diag_report(reason)
	if diag.said then
		return
	end
	diag.said = true
	mod:info("[umatide][diag] %s | tick=%d | attach_calls=%d | mine=%d | attached=%d | pkg_ready=%s | unit_name_form=%s",
		reason, diag.tick, diag.calls, diag.mine, attached_n, tostring(diag.ready_seen),
		tostring(Attach.WORKING_NAME_FORM))
end
Attach.diag = diag
Attach.diag_report = diag_report

-- ────────────────────────────────────────────────────────────────────────────
-- self proof, first frames after spawn (read only, changes nothing)
--
-- Expected values (offline, system\tools\umatide_nodes_audit.py):
--   root = node 1 (only parentless node) | j_head = 84 | j_hips = 28 | j_righthand = 207
-- ────────────────────────────────────────────────────────────────────────────
local PROBE_BONES = { "j_head", "j_hips", "j_righthand", "root_point" }

local function node_or_nil(u, name)
	local ok, n = pcall(Unit.node, u, name)
	if ok then
		return n
	end
	return nil
end

local function verify_once(ext)
	local our, char = ext.__umatide_unit, ext._unit
	if not (alive(our) and alive(char)) then
		return
	end
	local named, parts = 0, {}
	for i = 1, #PROBE_BONES do
		local n = node_or_nil(our, PROBE_BONES[i])
		if n ~= nil then
			named = named + 1
		end
		parts[#parts + 1] = string.format("%s=%s", PROBE_BONES[i], tostring(n))
	end
	mod:info("[umatide][probe] named_ref_bones=%d/%d (%s) | our_unit_alive=%s",
		named, #PROBE_BONES, table.concat(parts, " "), tostring(Unit.alive(our)))

	pcall(function ()
		local a = Unit.world_position(our, 1)
		local b = Unit.world_position(char, 1)
		if a and b then
			local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
			mod:info("[umatide][probe] our_node1=(%.3f,%.3f,%.3f) char_node1=(%.3f,%.3f,%.3f) dist=%.4f",
				a.x, a.y, a.z, b.x, b.y, b.z, math.sqrt(dx * dx + dy * dy + dz * dz))
		end
		local okp, par = pcall(Unit.scene_graph_parent, our, 1)
		mod:info("[umatide][probe] scene_graph_parent_readable=%s value=%s", tostring(okp), tostring(par))
	end)

	pcall(function ()
		local nm = "j_rightweaponattach"
		local oi = node_or_nil(our, nm)
		if oi == nil then
			mod:info("[umatide][probe] our unit has no node '%s' -> the engine will use the character's own attach point", nm)
			return
		end
		local wp = Unit.world_position(our, oi)
		mod:info("[umatide][probe] our %s = node %d at (%.3f,%.3f,%.3f)", nm, oi,
			wp and wp.x or 0, wp and wp.y or 0, wp and wp.z or 0)
	end)
end

-- second sample, a few seconds later: does the unit survive and does it follow?
local function follow_sample(ext)
	local our, char = ext.__umatide_unit, ext._unit
	if not (alive(our) and alive(char)) then
		mod:info("[umatide][probe] follow_sample our_alive=%s char_alive=%s",
			tostring(alive(our)), tostring(alive(char)))
		return
	end
	pcall(function ()
		local a = Unit.world_position(our, 1)
		local b = Unit.world_position(char, 1)
		if a and b then
			local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
			mod:info("[umatide][probe] follow_sample our_node1=(%.3f,%.3f,%.3f) char_node1=(%.3f,%.3f,%.3f) dist=%.4f (near 0 means it follows)",
				a.x, a.y, a.z, b.x, b.y, b.z, math.sqrt(dx * dx + dy * dy + dz * dz))
		end
	end)
end

-- ────────────────────────────────────────────────────────────────────────────
-- attach
-- ────────────────────────────────────────────────────────────────────────────
local function ensure_attached(ext)
	if type(ext) ~= "table" then
		return false
	end
	diag.calls = diag.calls + 1
	if mod.umatide_ready() and not diag.ready_seen then
		diag.ready_seen = true
		mod:info("[umatide][diag] package ready: attach will now really try on every call")
	end
	if not mod.umatide_model_on() then
		despawn(ext)
		return false
	end
	if excluded(ext) then
		despawn(ext)
		return false
	end
	if not is_mine(ext._unit, ext) then
		say("not_mine", "[umatide][diag] a character extension is being driven but is not the local player (we only replace the local player)")
		return false
	end
	diag.mine = diag.mine + 1
	if not mod.umatide_ready() then
		say("waiting", "[umatide][diag] package not ready yet, not spawning this frame (will retry)")
		return false
	end
	if alive(ext.__umatide_unit) then
		return false
	end
	local world = Managers.world and Managers.world:world("level_world")
	local u, err = spawn_and_link(world, ext._unit)
	if not u then
		say("spawn_fail", "[umatide] spawn failed (will retry): %s", tostring(err))
		return false
	end
	ext.__umatide_unit = u
	ext.__umatide_ours = true
	ext.__umatide_verify_in = 60       -- about 1 s: verify_once
	ext.__umatide_follow_in = 300      -- about 5 s: follow_sample
	attached_n = attached_n + 1
	mod:info("[umatide] attached our_unit=%s name_form=%s char=%s link=node1->node1 mode=LINK_MODE_NODE_NAME",
		Attach.UNIT, tostring(Attach.WORKING_NAME_FORM), tostring(ext._unit))
	local n = Attach.keep_hidden(ext)
	if n > 0 then
		mod:info("[umatide] hid vanilla visible units n=%d", n)
	end
	return true
end
Attach.ensure_attached = ensure_attached

-- ────────────────────────────────────────────────────────────────────────────
-- hooks
-- ────────────────────────────────────────────────────────────────────────────

-- ① equipment component: hide again in the SAME frame, right after the game's own call.
--    The game sets the body back to visible inside update_item_visibility, so whoever runs
--    last wins; hiding only "every frame" would toggle and be seen as flicker.
local function hook_item_visibility()
	local ok, install_err = pcall(function ()
		local EC = require("scripts/extension_systems/visual_loadout/equipment_component")
		if not (EC and type(EC.update_item_visibility) == "function") then
			error("equipment_component.update_item_visibility is missing")
		end
		mod:hook(EC, "update_item_visibility", function (func, equipment, wielded_slot, unit_3p, unit_1p, first_person_mode, item_defs, ...)
			local r1, r2, r3, r4, r5 = func(equipment, wielded_slot, unit_3p, unit_1p, first_person_mode, item_defs, ...)
			pcall(function ()
				if not mod.umatide_cfg_bool("hide_vanilla_body") then
					return
				end
				-- only the local player (evidence: equipment_component.lua self._player)
				local p = equipment and equipment._player
				local owner = p and (p.player_unit or p.unit)
				if not (owner ~= nil and owner == local_player_unit()) then
					return
				end
				local ws = tostring(wielded_slot or "")
				if not is_hidden_slot(ws) then
					return     -- weapon slots are never touched here
				end
				if alive(unit_3p) then
					-- object level, not recursive: only this unit's own meshes
					Unit.set_unit_objects_visibility(unit_3p, false, false)
				end
				hide_slots(equipment, "unit_3p")
			end)
			return r1, r2, r3, r4, r5
		end)
	end)
	if ok then
		mod:info("[umatide][hook] installed EquipmentComponent.update_item_visibility post-hide hook")
	else
		mod:info("[umatide][hook] failed to hook update_item_visibility: %s", tostring(install_err))
	end
end

-- ② spawn point: hide vanilla body parts the moment they are spawned (no bright first frame)
local function hook_spawn_body()
	local ok, install_err = pcall(function ()
		local VLC = require("scripts/extension_systems/visual_loadout/utilities/visual_loadout_customization")
		if not (VLC and type(VLC.spawn_base_unit) == "function") then
			error("visual_loadout_customization.spawn_base_unit is missing")
		end
		mod:hook(VLC, "spawn_base_unit", function (func, item_data, attach_settings, parent_unit, ...)
			local u = func(item_data, attach_settings, parent_unit, ...)
			pcall(function ()
				if not mod.umatide_cfg_bool("hide_vanilla_body") then
					return
				end
				local st = attach_settings
				if type(st) ~= "table" then
					return
				end
				if st.from_script_component == true or st.is_first_person == true
					or st.is_ui_preview == true then
					return
				end
				if not is_mine(parent_unit, nil) then
					return      -- never touch another player's character
				end
				local name = tostring(item_data and item_data.name or "")
				if (name:find("/body_", 1, true) or name:find("/gear_", 1, true)) and alive(u) then
					Unit.set_unit_visibility(u, false, true)
				end
			end)
			return u
		end)
	end)
	if ok then
		mod:info("[umatide][hook] installed visual_loadout_customization.spawn_base_unit hide-on-spawn hook")
	else
		mod:info("[umatide][hook] failed to hook spawn_base_unit: %s", tostring(install_err))
	end
end

-- ③ the two visual loadout extension classes: local player and the husk twin
local EXT_CLASSES = {
	"PlayerUnitVisualLoadoutExtension",
	"PlayerHuskVisualLoadoutExtension",
}

local tracked = setmetatable({}, { __mode = "k" })

local function hook_extensions()
	local hooked = 0
	for i = 1, #EXT_CLASSES do
		local cname = EXT_CLASSES[i]
		local C = CLASS and CLASS[cname]
		if C then
			hooked = hooked + 1
			mod:hook_safe(C, "init", function (self)
				tracked[self] = true
				-- ★ 类身份标记：Player 类 = 本地玩家；husk 类 = 别的玩家（供 is_mine 使用）
				self.__umatide_local_class = (cname == "PlayerUnitVisualLoadoutExtension")
			end)
			mod:hook_safe(C, "update", function (self)
				tracked[self] = true
				pcall(ensure_attached, self)
			end)
			mod:hook_safe(C, "_update_item_visibility", function (self)
				pcall(ensure_attached, self)
				pcall(Attach.keep_hidden, self)
			end)
			mod:hook(C, "destroy", function (func, self, ...)
				pcall(despawn, self)
				tracked[self] = nil
				return func(self, ...)
			end)
			mod:info("[umatide][hook] hooked CLASS.%s (init/update/_update_item_visibility/destroy)", cname)
		else
			mod:info("[umatide][hook] CLASS.%s not found, channel not hooked", cname)
		end
	end
	return hooked
end

-- per frame: the package arrives asynchronously, so retry here and keep the hide applied
Attach.tick = function ()
	for ext in pairs(tracked) do
		pcall(ensure_attached, ext)
		if alive(ext.__umatide_unit) then
			pcall(Attach.keep_hidden, ext)
			local v = ext.__umatide_verify_in
			if type(v) == "number" then
				if v <= 0 then
					ext.__umatide_verify_in = nil
					pcall(verify_once, ext)
				else
					ext.__umatide_verify_in = v - 1
				end
			end
			local f = ext.__umatide_follow_in
			if type(f) == "number" then
				if f <= 0 then
					ext.__umatide_follow_in = nil
					pcall(follow_sample, ext)
				else
					ext.__umatide_follow_in = f - 1
				end
			end
		else
			tracked[ext] = nil
		end
	end

	diag.tick = diag.tick + 1
	if diag.tick == 1 or diag.tick == 600 then
		local lp = local_player_unit()
		local n_ext = 0
		for _ in pairs(tracked) do
			n_ext = n_ext + 1
		end
		mod:info("[umatide][diag] tick=%d | level_world=%s | local_player=%s (alive=%s) | ext_seen=%d | attached=%d | pkg_ready=%s",
			diag.tick,
			tostring(Managers.world ~= nil and Managers.world:world("level_world") ~= nil),
			tostring(lp), tostring(lp ~= nil and Unit.alive(lp)),
			n_ext, attached_n, tostring(diag.ready_seen))
	end
	if diag.tick == 1800 then
		diag_report("tick 1800 (about 30 s)")
	end
end

-- recompute after a setting change / toggle (no restart needed)
Attach.refresh = function ()
	for ext in pairs(tracked) do
		pcall(function ()
			if not mod.umatide_model_on() then
				despawn(ext)
				set_body_objects_visible(ext._unit, true)
			else
				ensure_attached(ext)
			end
		end)
	end
end

function Attach.install()
	hook_item_visibility()
	hook_spawn_body()
	local n = hook_extensions()
	if n == 0 then
		mod:info("[umatide] neither visual loadout extension class was found, cannot attach")
		return false
	end
	return true
end

mod.UmatideAttach = Attach
return Attach
