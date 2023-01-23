--[[
   KahLua Kore - loot distribution handling.
     WWW: http://kahluamod.com/kore
     Git: https://github.com/kahluamods/kore
     IRC: #KahLua on irc.freenode.net
     E-mail: me@cruciformer.com

   Please refer to the file LICENSE.txt for the Apache License, Version 2.0.

   Copyright 2008-2021 James Kean Johnston. All rights reserved.

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
]]

local KKORELOOT_MAJOR = "KKoreLoot"
local KKORELOOT_MINOR = 4
local KLD, oldminor = LibStub:NewLibrary(KKORELOOT_MAJOR, KKORELOOT_MINOR)

if (not KLD) then
  return
end

KLD.debug_id = KKORELOOT_MAJOR

local K, KM = LibStub:GetLibrary("KKore")
assert (K, "KKoreLoot requires KKore")
assert (tonumber(KM) >= 4, "KKoreLoot requires KKore r4 or later")
K:RegisterExtension (KLD, KKORELOOT_MAJOR, KKORELOOT_MINOR)

local KRP, KM = LibStub:GetLibrary("KKoreParty")
assert (KRP, "KKoreLoot requires KKoreParty")
assert (tonumber(KM) >= 4, "KKoreLoot requires KKoreParty r4 or later")

local L = LibStub("AceLocale-3.0"):GetLocale("KKore")

--
-- Constants for easy representation of the various armor and weapon types
-- that a character can equip. This uses the Blizzard localised strings as
-- much as possible.
--
K.INV_HEAD              = 1
K.INV_NECK              = 2
K.INV_SHOULDER          = 3
K.INV_BODY              = 4
K.INV_CHEST             = 5
K.INV_WAIST             = 6
K.INV_LEGS              = 7
K.INV_FEET              = 8
K.INV_WRIST             = 9
K.INV_HANDS             = 10
K.INV_FINGER            = 11
K.INV_TRINKET           = 12
K.INV_1HWEAPON          = 13
K.INV_SHIELD            = 14
K.INV_RANGED            = 15
K.INV_BACK              = 16
K.INV_2HWEAPON          = 17
K.INV_BAG               = 18
K.INV_TABARD            = 19
K.INV_ROBE              = 20
K.INV_MHWEAPON          = 21
K.INV_OHWEAPON          = 22
K.INV_HOLDABLE          = 23
K.INV_AMMO              = 24
K.INV_THROWN            = 25
K.INV_RANGEDRIGHT       = 26
K.INV_QUIVER            = 27
K.INV_RELIC             = 28

K.InvSlotNames = {
  [K.INV_HEAD]          = INVTYPE_HEAD,
  [K.INV_NECK]          = INVTYPE_NECK,
  [K.INV_SHOULDER]      = INVTYPE_SHOULDER,
  [K.INV_BODY]          = INVTYPE_BODY,
  [K.INV_CHEST]         = INVTYPE_CHEST,
  [K.INV_WAIST]         = INVTYPE_WAIST,
  [K.INV_LEGS]          = INVTYPE_LEGS,
  [K.INV_FEET]          = INVTYPE_FEET,
  [K.INV_WRIST]         = INVTYPE_WRIST,
  [K.INV_HANDS]         = INVTYPE_HAND,
  [K.INV_FINGER]        = INVTYPE_FINGER,
  [K.INV_TRINKET]       = INVTYPE_TRINKET,
  [K.INV_1HWEAPON]      = INVTYPE_WEAPON .. " " .. WEAPON,
  [K.INV_SHIELD]        = L["Shield"],
  [K.INV_RANGED]        = INVTYPE_RANGED .. " " .. WEAPON,
  [K.INV_BACK]          = INVTYPE_CLOAK,
  [K.INV_2HWEAPON]      = INVTYPE_2HWEAPON .. " " .. WEAPON,
  [K.INV_BAG]           = INVTYPE_BAG,
  [K.INV_TABARD]        = INVTYPE_TABARD,
  [K.INV_ROBE]          = INVTYPE_ROBE,
  [K.INV_MHWEAPON]      = INVTYPE_WEAPONMAINHAND .. " " .. WEAPON,
  [K.INV_OHWEAPON]      = INVTYPE_WEAPONOFFHAND .. " " .. WEAPON,
  [K.INV_HOLDABLE]      = INVTYPE_HOLDABLE,
  [K.INV_AMMO]          = INVTYPE_AMMO,
  [K.INV_THROWN]        = INVTYPE_THROWN .. " " .. WEAPON,
  [K.INV_RANGEDRIGHT]   = INVTYPE_RANGEDRIGHT,
  [K.INV_QUIVER]        = INVTYPE_QUIVER,
  [K.INV_RELIC]         = INVTYPE_RELIC,
}

local strmatch = string.match
local printf = K.printf
local tinsert = table.insert
local pairs = pairs

local function debug(lvl,...)
  K.debug("kore", lvl, ...)
end

local LOOT_METHOD_UNKNOWN     = KRP.LOOT_METHOD_UNKNWON
local LOOT_METHOD_FREEFORALL  = KRP.LOOT_METHOD_FREEFORALL
local LOOT_METHOD_ROUNDROBIN  = KRP.LOOT_METHOD_ROUNDROBIN
local LOOT_METHOD_MASTER      = KRP.LOOT_METHOD_MASTER
local LOOT_METHOD_GROUP       = KRP.LOOT_METHOD_GROUP
local LOOT_METHOD_NEEDB4GREED = KRP.LOOT_METHOD_NEEDB4GREED
local LOOT_METHOD_PERSONAL    = KRP.LOOT_METHOD_PERSONAL

KLD.addons = {}

KLD.valid_callbacks = {
  ["ml_candidate"] = true,
  ["loot_item"] = true,
  ["start_loot_info"] = true,
  ["end_loot_info"] = true,
  ["looting_ready"] = true,
  ["loot_assigned"] = true,
}

KLD.initialised = false

-- Name of the unit being looted or nil if none.
KLD.unit_name = nil

-- GUID of the unit being looted or nil if none.
KLD.unit_guid = nil

-- Whether or not KLD.unit_guid is a real GUID (if set at all).
KLD.unit_realguid = false

-- Name of the chest or item being opened or nil if none
KLD.chest_name = nil

-- Number of loot items on the current corpse / chest or 0 if there is no
-- such current corpse or there are no items that match the threshold.
KLD.num_items = 0

-- State variable to indicate if we should skip populating loot this time.
KLD.skip_loot = false

-- Table of items on the current corpse or nil if there is no current corpse.
-- Each element in this table is a table with the following members:
--   name - name of the item
--   ilink - the full item link
--   itemid - the item ID
--   lootslot - the loot slot number
--   quantity - how many of the item
--   quality - the item quality
--   locked - whether or not the item is locked
--   candidates - list of possible candidates if we are master looting
KLD.items = nil

local disenchant_name = GetSpellInfo(13262)
local herbalism_name = GetSpellInfo(11993)
local mining_name = GetSpellInfo(32606)
-- local skinning_name = GetSpellInfo(75644)

--
-- Function: get_ml_candidates(slot)
-- Purpose : Returns the list of valid candidates for the provided
--           loot slot item, or nil if there is no current loot slot or
--           we are not using master looting.
-- Callback: Calls ml_candidate for each candidate.
--
local function get_ml_candidates(slot)
  if (not KLD.initialised) then
    return nil
  end

  if (not KRP.master_looter) then
    return nil
  end

  local candidates = {}
  local count = 0
  for i = 1, MAX_RAID_MEMBERS do
    local name = GetMasterLootCandidate(slot, i)
    if (name) then
      name = K.CanonicalName(name, nil)
      if (not name) then
        return nil
      end

      local cinfo = {}
      cinfo["index"] = i
      cinfo["lootslot"] = slot
      candidates[name] = cinfo
      KLD:DoCallbacks("ml_candidate", candidates[name])
      count = count + 1
    end
  end

  if (count > 0) then
    return candidates
  else
    return nil
  end
end

local function reset_items()
  KLD.items = nil
  KLD.num_items = 0
end

-- Actually retrieve all of the loot slot item info.
local function populate_items()
  local nitems = GetNumLootItems()
  local items = {}
  local count = 0

  KLD:DoCallbacks("start_loot_info")

  for i = 1, nitems do
    if (LootSlotHasItem(i)) then
      local icon, name, quant, _, qual, locked  = GetLootSlotInfo(i)
      local ilink = GetLootSlotLink(i)
      local itemid = nil
      local item = {}

      if (icon and qual >= KRP.loot_threshold) then
        item["name"] = name
        if (ilink and ilink ~= "") then
          item["ilink"] = ilink
          itemid = strmatch(ilink, "item:(%d+)")
        end

        item["itemid"] = itemid
        item["lootslot"] = i
        item["quantity"] = quant
        item["quality"] = qual
        item["locked"] = locked or false
        item["candidates"] = get_ml_candidates(i) or {}

        items[i] = item
        count = count + 1
      end
    end
  end

  KLD.num_items = count
  if (KLD.num_items > 0) then
    KLD.items = items
    -- Only do callbacks once all items are in the list.
    for k, v in pairs(KLD.items) do
      KLD:DoCallbacks("loot_item", v)
    end
  else
    KLD.items = nil
  end

  KLD:DoCallbacks("end_loot_info")
end

local function reset_loot_target()
  KLD.unit_name = nil
  KLD.unit_guid = nil
  KLD.unit_realguid = false
end

local function populate_loot_target()
  local uname = UnitName("target")
  local uguid = UnitGUID("target")
  local realguid = true

  if (not uname or uname == "") then
    if (KLD.chest_name and KLD.chest_name ~= "") then
      uname = KLD.chest_name
    else
      uname = L["Chest"]
    end
  end

  if (not uguid or uguid == "") then
    uguid = 0
    realguid = false
    if (KLD.chest_name and KLD.chest_name ~= "") then
      uguid = KLD.chest_name
    end
  end

  KLD.unit_name = uname
  KLD.unit_guid = uguid
  KLD.unit_realguid = realguid
end

--
-- Function: KLD.RefreshLoot()
-- Purpose : Refresh the internal view of the loot items on the current
--           corpse. This should only ever be called when we know that
--           we have a valid corpse and that loot is not being skipped.
-- Fires   : ITEMS_UPDATED
--
function KLD.RefreshLoot()
  if (KLD.initialised) then
    return
  end

  reset_loot_target()
  reset_items()

  populate_loot_target()
  populate_items()
end

--
-- Function: KLD.GiveMasterLoot(slot, target)
-- Purpose : Give the loot in KLD.items[slot] to the specified target. If
--           master looting is not active, or the slot is invalid, returns
--           1. If the slot and the target are valid but the target is not
--           in the list of valid recipients for the item, returns 2. If
--           there was no error, return 0.
-- Fires   : LOOT_ASSIGNED(slot, target)
--
function KLD.GiveMasterLoot(slot, target)
  if (not KLD.initialised or not KRP.is_ml or not slot or slot < 1
      or not target or target == "" or not KLD.items
      or KLD.num_items < 1 or not KLD.items[slot]) then
    return 1
  end

  local cand = KLD.items[slot].candidates

  if (not cand or not cand[target]) then
    return 2
  end

  GiveMasterLoot(slot, cand[target].index)

  KLD:DoCallbacks("loot_assigned", slot, target)
  return 0
end

local function loot_ready_evt()
  if (not KLD.initialised) then
    return
  end

  if (KLD.skip_loot) then
    KLD.skip_loot = nil
    return
  end

  reset_items()
  reset_loot_target()

  populate_loot_target()
  populate_items()

  KLD:DoCallbacks("looting_ready")
end

local function loot_closed_evt()
  if (not KLD.initialised) then
    return
  end

  reset_items()
  reset_loot_target()

  KLD.chest_name = nil

  KLD:DoCallbacks("looting_ended")
end

local function unit_spellcast_succeeded(evt, caster, sname, rank, tgt)
  if (caster == "player") then
    if (sname == OPENING) then
      KLD.chest_name = tgt
      return
    end

    if ((sname == disenchant_name) or (sname == herbalism_name) or
        (sname == mining_name)) then
      KLD.skip_loot = true
    end
  end
end

local function kld_do_refresh(evt, ...)
  if (not KLD.initialised) then
    return
  end
  KLD.RefreshLoot()
  KLD:DoCallbacks("looting_ready")
end

--
-- When an addon is suspended or resumed, we need to do a refresh because
-- the addon may have callbacks that have either been populated and now
-- need to be removed (addon suspended) or needs to add new data via the
-- callbacks (addon resumed). So we trap these two events and use them to
-- schedule a refresh.
--
function KLD:OnActivateAddon(name, onoff)
  kld_do_refresh()
end

function KLD:OnLateInit()
  if (KLD.initialised) then
    return
  end

  KLD:RegisterEvent("LOOT_READY", loot_ready_evt)
  KLD:RegisterEvent("LOOT_CLOSED", loot_closed_evt)
  KLD:RegisterEvent("UPDATE_MASTER_LOOT_LIST", function()
    KLD:RefreshLoot()
  end)
  KLD:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", unit_spellcast_succeeded)

  KLD.initialised = true
end
