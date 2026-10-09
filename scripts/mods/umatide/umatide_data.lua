--[[
	umatide_data.lua —— DMF mod metadata

★ This file deliberately declares **no settings table**. Reason (project rule, original wording
  in ModelForge_defaults.lua header):

  · author's ruling: "the DMF UI carries test content ... you are adding and changing buttons on
    your own"; "once the replacement takes effect the original model is meant to be hidden, that
    is the default handling and needs no button"; "from now on I will only do the enable UI
    inside the workshop"
  · measured accident (2026-10-04, ModelForge): a key with no widget in the UI was persisted as
    false; once the key was wired up, that historical false took effect immediately and the local
    player was silently skipped.
  ⇒ The missing invariant: "no widget" must mean "take a written-down default",
    not "read a historical garbage value".

★ 2026-10-08, same trap hit again (first version of this mod):
    data declared settings = { { setting_id = "rig_replace", default_value = true, ... } }
    ⇒ DMF had not registered the setting ⇒ mod:get("rig_replace") returned nil
    ⇒ treated as "off" ⇒ the replacement was never registered.
  Fix: behaviour defaults live in the DEFAULTS table in umatide.lua and fall back through cfg();
  no widgets.

★ 2026-10-09 (this version): the probe / experiment channels were removed together with the
  retired scripts (rig_replace / body_repoint / trace_chain now live in
  _staging\umatide_retired_scripts\). The mod has one channel (attach) and the localization file
  only carries the strings for it.

★ Naming rule (global human ruling 2026-09-14):
  `moisten` carries no meaning; it was a temporary discriminator from the early test period and
  is to be retired. New mod ids / directory names / identifiers must not use it. This mod uses
  `umatide`.
]]

local mod = get_mod("umatide")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
}
