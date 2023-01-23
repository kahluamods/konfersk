--[[
   KahLua Kore - party and raid monitoring.
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

local KKOREPARTY_MAJOR = "KKoreParty"
local KKOREPARTY_MINOR = 4
local KRP, oldminor = LibStub:NewLibrary(KKOREPARTY_MAJOR, KKOREPARTY_MINOR)

if (not KRP) then
  return
end

local assert = assert
local GetNumRaidMembers = GetNumGroupMembers or GetNumRaidMembers
local GetNumPartyMembers = GetNumSubgroupMembers or GetNumPartyMembers

KRP.debug_id = KKOREPARTY_MAJOR

local K, KM = LibStub:GetLibrary("KKore")
assert(K, "KKoreParty requires KKore")
assert(tonumber(KM) >= 4, "KKoreParty requires KKore r4 or later")
K:RegisterExtension(KRP, KKOREPARTY_MAJOR, KKOREPARTY_MINOR)

local printf = K.printf
local tinsert = table.insert

local function debug(lvl,...)
  K.debug("kore", lvl, ...)
end

KRP.initialised = false

--
-- Whenever a user is in a raid they are automatically in a party too, which
-- is their raid group. It may be useful to know who the current group members
-- are so we will maintain both lists.
--
-- KRP.in_party therefore doubles as what we used to call KRP.in_either
-- because it is also set when a user in in a raid. Thus KRP.in_party is
-- true when a user is in a party, raid or BG, if they are in a raid, and
-- in_bg if they are in a battleground.
--

-- Is the player in a party
KRP.in_party = false

-- Is the player in a raid
KRP.in_raid = false

-- Is the player in a battleground
KRP.in_bg = false

-- The number of players in the party or raid (including ourselves)
KRP.num_party = 0
KRP.num_raid = 0

-- The raid sub-group the player is in, or 0 if not in a raid.
KRP.subgroup = 0

-- The raid ID for the player. This is the X in unit name "raidX". 0 if not
-- in a raid.
KRP.raidid = 0

-- Is the player both in a party and the party leader
KRP.is_pl = false

-- Is the player both in a raid and the raid leader
KRP.is_rl = false

-- Is the player both in a raid and the raid leader OR an assistant
KRP.is_aorl = false

-- Is the player both in a party / raid and the master looter
KRP.is_ml = false

-- Which party member (0 for player) is the master looter, or nil if none.
KRP.party_mlid = nil

-- Which raid member is the master looter, or nil if none.
KRP.raid_mlid = nil

-- Full name of the current master looter or nil if none.
KRP.master_looter = nil

-- Full name of the current party or raid leader or nil if none.
KRP.leader = nil

-- The list of players in the party or raid, or nil if not in one.
-- Each element in the table is indexed by the full player name, and is itself
-- a table with the following members:
--   .name - same as the index - the full player name
--   .level - the player level
--   .class - the player's class (K.ClassIndex)
--   .faction - players faction
--   .is_guilded - true if the player is in our guild
--   .guildrankidx - guild rank index if in our guild
--   .is_gm - true if the player is our guild GM
--   .unitid - the unit ID (party3, raid17, player etc)
--   .subgroup - the raid subgroup or 0 if we're in a party not a raid
--   .raidid - the X in raidX if we are in a raid
--   .partyid - the X in partyX, 0 for ourselves 
--   .is_pl - true if player is the party leader, false otherwise
--   .is_rl - true if the player is the raid leader, false otherwise
--   .is_aorl - true if player is raid leader OR assist, false otherwise
--   .is_ml - true if the player is the master looter
--   .group_role - GROUP_ROLE_NONE for party members, or NONE, TANK or ASSIST
--   .online - true if the player is online otherwise false
--   .dead - true if the player is dead false otherwise
--   .afk - true if teh player is AFK false otherwise
--   .guid - unit GUID
--   .maxhp - player's max HP
--   .powertype - player's power type (MANA, RAGE, ENERGY etc)
--   .maxpower - players maximum power
--   .cantrade - true if they are within trading distance otherwise false
--   .inrange - true if unit is in range
KRP.players = nil

-- The list of player names in the players party. Includes us.
KRP.party = nil

-- The list of players in the raid or nil if not in a raid.
KRP.raid = nil

-- The list of players in the various raid groups or nil if not in a raid.
-- This is an array of 8 tables when it is non-nil.
KRP.raidgroups = nil

KRP.LOOT_METHOD_UNKNOWN     = 0
KRP.LOOT_METHOD_FREEFORALL  = 1
KRP.LOOT_METHOD_ROUNDROBIN  = 2
KRP.LOOT_METHOD_MASTER      = 3
KRP.LOOT_METHOD_GROUP       = 4
KRP.LOOT_METHOD_NEEDB4GREED = 5
KRP.LOOT_METHOD_PERSONAL    = 6

local LOOT_METHOD_UNKNOWN     = KRP.LOOT_METHOD_UNKNWON
local LOOT_METHOD_FREEFORALL  = KRP.LOOT_METHOD_FREEFORALL
local LOOT_METHOD_ROUNDROBIN  = KRP.LOOT_METHOD_ROUNDROBIN
local LOOT_METHOD_MASTER      = KRP.LOOT_METHOD_MASTER
local LOOT_METHOD_GROUP       = KRP.LOOT_METHOD_GROUP
local LOOT_METHOD_NEEDB4GREED = KRP.LOOT_METHOD_NEEDB4GREED
local LOOT_METHOD_PERSONAL    = KRP.LOOT_METHOD_PERSONAL

local method_to_number = {
  ["unknown"]         = LOOT_METHOD_UNKNOWN,
  ["freeforall"]      = LOOT_METHOD_FREEFORALL,
  ["roundrobin"]      = LOOT_METHOD_ROUNDROBIN,
  ["master"]          = LOOT_METHOD_MASTER,
  ["group"]           = LOOT_METHOD_GROUP,
  ["needbeforegreed"] = LOOT_METHOD_NEEDB4GREED,
  ["personalloot"]    = LOOT_METHOD_PERSONAL,
}

-- Party or raid loot method
KRP.loot_method = LOOT_METHOD_UNKNOWN

-- Loot threshold
KRP.loot_threshold = 0

KRP.GROUP_ROLE_NONE   = 0
KRP.GROUP_ROLE_TANK   = 1
KRP.GROUP_ROLE_ASSIST = 2

local GROUP_ROLE_NONE   = KRP.GROUP_ROLE_NONE
local GROUP_ROLE_TANK   = KRP.GROUP_ROLE_TANK
local GROUP_ROLE_ASSIST = KRP.GROUP_ROLE_ASSIST

local group_role_to_number = {
  ["NONE"]       = GROUP_ROLE_NONE,
  ["MAINTANK"]   = GROUP_ROLE_TANK,
  ["MAINASSIST"] = GROUP_ROLE_ASSIST,
}

KRP.RC_NOCHECK  = 0
KRP.RC_READY    = 1
KRP.RC_NOTREADY = 2
KRP.RC_WAITING  = 3
KRP.RC_AWAY     = 4

local RC_NOCHECK  = KRP.RC_NOCHECK
local RC_READY    = KRP.RC_READY
local RC_NOTREADY = KRP.RC_NOTREADY
local RC_WAITING  = KRP.RC_WAITING
local RC_AWAY     = KRP.RC_AWAY

local rc_to_number = {
  ["none"]     = RC_NOCHECK,
  ["ready"]    = RC_READY,
  ["notready"] = RC_NOTREADY,
  ["waiting"]  = RC_WAITING,
  ["away"]     = RC_AWAY,
}

KRP.ready_checking = false

-------------------------------------------------------------------------------

KRP.addons = {}
KRP.valid_callbacks = {
  ["new_player"] = true,
  ["update_group_start"] = true,
  ["update_group_end"] = true,
  ["in_group_changed"] = true,
  ["loot_method"] = true,
  ["leader_changed"] = true,
  ["role_changed"] = true,
  ["in_party_changed"] = true,
  ["in_raid_changed"] = true,
  ["in_bg_changed"] = true,
  ["readycheck_start"] = true,
  ["readycheck_reply"] = true,
  ["readycheck_end"] = true,
}

--
-- Reset ready check related variables
--
local function reset_ready()
  KRP.ready_checking = false
  KRP.ready = nil
  KRP.ready_timeout = nil
  KRP.ready_start = nil
end

--
-- Utility function to reset loot method related variables.
--
local function reset_loot_method()
  KRP.is_ml = false
  KRP.master_looter = nil
  KRP.party_mlid = nil
  KRP.raid_mlid = nil
  KRP.loot_method = LOOT_METHOD_UNKNOWN
  KRP.loot_threshold = 0
end

--
-- Utility function to reset leader related variables.
--
local function reset_group_leader()
  KRP.is_pl = false
  KRP.is_rl = false
  KRP.is_aorl = false
  KRP.leader = nil
end

--
-- Utility function to reset role related variables.
--
local function reset_role()
  KRP.group_role = GROUP_ROLE_NONE
end

--
-- Utility function to reset group related variables.
--
local function reset_group()
  reset_group_leader()
  reset_loot_method()
  reset_role()
  reset_ready()
  KRP.in_party = false
  KRP.in_raid = false
  KRP.in_bg = false
  KRP.num_party = 0
  KRP.num_raid = 0
  KRP.subgroup = 0
  KRP.raidid = 0
  KRP.raid = nil
  KRP.party = nil
  KRP.players = nil
  KRP.raidgroups = nil
end

local function update_loot_method_internal()
  reset_loot_method()

  if ((not KRP.in_party) or KRP.in_bg) then
    return
  end

  local lm, pmlid, rmlid = GetLootMethod()
  local mlname = nil

  KRP.party_mlid = pmlid
  KRP.raid_mlid = rmlid
  KRP.loot_method = method_to_number[lm or "unknown"] or LOOT_METHOD_UNKNOWN

  if (KRP.loot_method == LOOT_METHOD_MASTER) then
    if (pmlid ~= nil) then
      if (pmlid == 0) then
        mlname = K.player.name
      else
        mlname = K.FullUnitName("party" .. pmlid)
      end
    end
    if (rmlid ~= nil) then
      mlname = K.FullUnitName("raid" .. rmlid)
    end

    if (mlname and KRP.players) then
      for k, v in pairs(KRP.players) do
        if (v.is_ml) then
          if (k ~= mlname) then
            v.is_ml = false
          end
        end
        if (k == mlname) then
          v.is_ml = true
        end
      end
    end
  end

  if (mlname and mlname == K.player.name) then
    KRP.is_ml = true
  else
    KRP.is_ml = false
  end
  KRP.master_looter = mlname
  KRP.loot_threshold = GetLootThreshold()
end

--
-- Function: KRP.UpdateLootMethod()
-- Purpose : Updates the various loot method related settings, namely:
--           loot_method, party_mlid, raid_mlid, master_looter, is_ml
-- Fires   : LOOT_METHOD_UPDATED(new_method_id)
--
function KRP.UpdateLootMethod(evtonly)
  if (not KRP.initialised) then
    return false
  end

  if (not evtonly) then
    update_loot_method_internal()
  end

  KRP:DoCallbacks("loot_method", KRP.loot_method)
end

local function update_leader_internal()
  local old_leader = KRP.leader
  local prn

  reset_group_leader()

  if (not KRP.in_party and not KRP.in_bg) then
    return
  end

  if (UnitIsGroupAssistant("player")) then
    KRP.is_aorl = true
  end

  if (UnitIsGroupLeader("player")) then
    if (KRP.in_party) then
      KRP.is_pl = true
    end
    if (KRP.in_raid) then
      KRP.is_pl = false
      KRP.is_rl = true
      KRP.is_aorl = true
    end
    if (KRP.is_pl or KRP.is_rl) then
      KRP.leader = K.player.name
    end
  else
    if (KRP.in_party and not KRP.in_raid and not KRP.in_bg) then
      local npm = GetNumPartyMembers()
      for i = 1, npm do
        prn = "party" .. i
        if (UnitExists(prn)) then
          if (UnitIsGroupLeader(prn)) then
            KRP.leader = K.FullUnitName(prn)
          end
        end
      end
    end

    if (KRP.in_raid) then
      local num_raiders = KRP.num_raid
      for i = 1, num_raiders do
        prn = "raid" .. i
        if (UnitExists(prn)) then
          if (UnitIsGroupLeader(prn)) then
            KRP.leader = K.FullUnitName(prn)
          end
        end
      end
    end
  end

  if (KRP.players) then
    if (old_leader and KRP.players[old_leader]) then
      KRP.players[old_leader].is_rl = false
      KRP.players[old_leader].is_pl = false
      KRP.players[old_leader].is_aorl = false
      if (KRP.in_raid) then
        prn = "raid" .. KRP.players[old_leader].raidid
        if (UnitIsGroupAssistant(prn)) then
          KRP.players[old_leader].is_aorl = true
        end
      end
    end

    prn = KRP.leader
    if (KRP.players[prn]) then
      KRP.players[prn].is_pl = true
      KRP.players[prn].is_rl = false
      KRP.players[prn].is_aorl = false
      if (KRP.in_raid) then
        KRP.players[prn].is_pl = false
        KRP.players[prn].is_rl = true
        KRP.players[prn].is_aorl = true
      end
    end
  end
end

--
-- Function: KRP.UpdateLeader()
-- Purpose : Updates the various group leader related settings, namely:
--           is_pl, is_rl, is_aorl, leader.
-- Fires   : LEADER_CHANGED()
--
function KRP.UpdateLeader(evtonly)
  if (not KRP.initialised) then
    return false
  end

  local old_leader = KRP.leader

  if (not evtonly) then
    update_leader_internal()
  end

  if (old_leader ~= KRP.leader) then
    KRP:DoCallbacks("leader_changed")
  end
end

local function update_role_internal()
  reset_role()

  if (not KRP.in_party and not KRP.in_bg) then
    return
  end

  if (GetPartyAssignment("MAINTANK", "player")) then
    KRP.group_role = GROUP_ROLE_TANK
  elseif (GetPartyAssignment("MAINASSIST", "player")) then
    KRP.group_role = GROUP_ROLE_ASSIST
  else
    KRP.group_role = GROUP_ROLE_NONE
  end

  if (KRP.players and KRP.players[K.player.name]) then
    KRP.players[K.player.name].group_role = KRP.group_role
  end
end

--
-- Function: KRP.UpdateRole()
-- Purpose : Updates the group role variable: group_role.
-- Fires   : ROLE_CHANGED(role)
--
function KRP.UpdateRole(evtonly)
  if (not KRP.initialised) then
    return false
  end

  local old_role = KRP.group_role

  if (not evtonly) then
    update_role_internal()
  end

  if (KRP.group_role ~= old_role) then
    KRP:DoCallbacks("role_changed")
  end
end

local krp_flag_events = false

--
-- This function updates various unit flags. Some small amount of code from
-- UpdateLeader() is duplicated here. This function is called from two places
-- with very different data access requirements, hence the long argument list.
-- First, it is called from the populate_unit() closure, during which time none
-- of the group variables are valid yet. Secondly it is called from an event
-- handler for UNIT_FLAGS, when the group variables ARE in place.
--
local function update_unit_flags(unm, pt, in_party, in_raid, players)
  local urn

  local inparty = in_party or KRP.in_party
  local inraid = in_raid or KRP.in_raid
  local plist = players or KRP.players

  if (pt) then
    urn = pt.name
  else
    urn = K.FullUnitName(unm)
  end

  if (not urn or urn == "" or urn == "Unknown") then
    return
  end

  if (not pt) then
    if (not plist or not plist[urn]) then
      return
    end
  end

  local ptbl = pt or plist[urn]
  if (not ptbl) then
    return
  end

  if (UnitExists(unm)) then
    if (UnitIsConnected(unm)) then
      ptbl.online = true
    else
      ptbl.online = false
    end
    if (UnitIsDeadOrGhost(unm)) then
      ptbl.dead = true
    else
      ptbl.dead = false
    end
    if (UnitIsAFK(unm)) then
      ptbl.afk = true
    else
      ptbl.afk = false
    end
    ptbl.guid = UnitGUID(unm)
    ptbl.maxhp = UnitHealthMax(unm) or 0
    local _, powertype = UnitPowerType(unm)
    ptbl.powertype = powertype or "MANA" -- Fall back to mana as a default
    ptbl.maxpower = UnitPowerMax(unm) or 0
    ptbl.cantrade = CheckInteractDistance(unm, 2) or false
    local irange, rced = UnitInRange(unm)
    if (rced and not irange) then
      ptbl.inrange = false
    else
      ptbl.inrange = true
    end
    ptbl.is_aorl = false
    ptbl.is_pl = false
    ptbl.is_rl = false
    if (UnitIsGroupLeader(unm)) then
      if (inparty) then
        ptbl.is_pl = true
      end
      if (inraid) then
        ptbl.is_pl = false
        ptbl.is_rl = true
        ptbl.is_aorl = true
        if (UnitIsGroupAssistant(unm)) then
          ptbl.is_aorl = true
        end
      end
    end
  end
end

local function update_group_internal(fire_party, fire_raid, fire_bg)
  if (not KRP.initialised) then
    return false
  end

  local old_inparty = KRP.in_party
  local old_inraid = KRP.in_raid
  local old_inbg = KRP.in_bg
  local in_party, in_raid, in_bg = false, false, false
  local changed = false
  local players, party, raid, raidgroups
  local nrm = GetNumRaidMembers()
  local npm = GetNumPartyMembers()
  local _, itype = IsInInstance()
  local prn

  if (not K.local_realm or K.local_realm == "") then
    return false
  end

  KRP:DoCallbacks("update_group_start", old_inparty, old_inraid, old_inbg)

  if (IsInGroup()) then
    in_party = true
  end

  if (IsInRaid()) then
    in_raid = true
    in_party = true
  end

  if ((itype == "pvp") or (itype == "arena") or UnitInBattleground("player")) then
    in_bg = true
  end

  if (not in_bg and not in_party) then
    if (krp_flag_events) then
      KRP:UnregisterEvent("PLAYER_FLAGS_CHANGED")
      krp_flag_events = false
    end
    reset_group()
    KRP:DoCallbacks("in_group_changed", in_party, in_raid, in_bg)
    KRP:DoCallbacks("update_group_end", in_party, in_raid, in_bg)
    return true
  end

  players = {}

  --
  -- When we are in either a party or a raid, we build up a list of players
  -- that are in that party or raid. We retrieve certain useful values for
  -- those players such as their class, level and a bunch of other things.
  -- We also give all registered addons a chance to add extra information
  -- to each player entry via the "new_player" callback. The callback is
  -- passed the player table we are adding and if it needs to add any members
  -- to the table the member names should begin with an addon-specific prefix.
  -- For example, KSK may add a variable "ksk_userid" to the player.
  --
  -- After all this had been done the players table will contain the full list
  -- of players in the party or raid. Other tables such as the party or raid
  -- table will simply contain player references into this players table
  -- indexed by the player full name (Name-realm).
  --
  -- Also note that our own name always appears in the players list if we
  -- are in either a raid or party.
  --
  -- To a large degree this table can simply be thought of as a cache for
  -- the info returned by GetRaidRosterInfo() or an amalgmation of other
  -- calls getting the same info if we are just in a party.
  --

  local player = {}

  local function populate_unit(ptbl, unm)
    ptbl.name = K.FullUnitName(unm)
    if (not ptbl.name or ptbl.name == "Unknown" or ptbl.name == "") then
      ptbl.name = nil
      return
    end

    ptbl.level = UnitLevel(unm)
    ptbl.class = K.ClassIndex[select(2, UnitClass(unm))]
    ptbl.faction = UnitFactionGroup(unm)
    if (K.player.is_guilded and UnitIsInMyGuild(unm)) then
      ptbl.is_guilded = true
      local kgi = K.guild.roster.name[ptbl.name]
      if (kgi) then
        local kri = K.guild.roster.id[kgi]
        ptbl.guildrankidx = kri.rank
        if (ptbl.guildrankidx == 1) then
          ptbl.is_gm = true
        else
          ptbl.is_gm = false
        end
      else
        ptbl.guildrankidx = 0
        ptbl.is_gm = false
      end
    else
      ptbl.is_guilded = false
      ptbl.guildrankidx = 0
      ptbl.is_gm = false
    end
  end

  -- Always add ourselves to the players list
  populate_unit(player, "player")
  if (not player.name) then
    return false
  end
  player.unitid = "player"
  player.is_ml = KRP.is_ml
  player.subgroup = 0
  player.raidid = 0
  player.partyid = 0
  player.group_role = GROUP_ROLE_NONE

  players[player.name] = player
  update_unit_flags("player", player, in_party, in_raid, players)
  players[player.name] = player
  KRP:DoCallbacks("new_player", players[player.name])

  if (in_party) then
    party = {}
    party[0] = player.name

    for i = 1, npm do
      prn = "party" .. i
      if (UnitExists(prn)) then
        player = {}
        player.partyid = i
        player.unitid = prn
        player.is_ml = false
        -- If we're in raid then dont do this check else each raid party
        -- will erroneous get this party member number marked as master looter.
        if (not in_raid) then
          if (KRP.party_mlid and KRP.party_mlid == i) then
            player.is_ml = true
          end
        end
        player.subgroup = 0
        player.raidid = 0
        player.group_role = GROUP_ROLE_NONE
        populate_unit(player, prn)
        if (player.name) then
          players[player.name] = player
          update_unit_flags(prn, player, in_party, in_raid, players)
          players[player.name] = player
          KRP:DoCallbacks("new_player", players[player.name])
          party[i] = player.name
        else
          return false
        end
      end
    end
  end

  --
  -- It is possible, even probable that we may end up calculating player info
  -- for a player that was already processed during party processing above.
  -- That's OK but addons need to be aware of this and never use any form of
  -- index other than the name into tables.
  --
  if (in_raid) then
    raid = {}
    raidgroups = {}
    for i = 1, NUM_RAID_GROUPS do
      raidgroups[i] = {}
    end

    for i = 1, nrm do
      prn = "raid" .. i
      if (UnitExists(prn)) then
        local nm, rank, subgrp, _, _, _, _, _, _, role, ml = GetRaidRosterInfo(i)
        if (nm) then
          player = {}
          player.unitid = prn
          player.subgroup = subgrp
          player.raidid = i
          player.group_role = group_role_to_number[role or "NONE"] or GROUP_ROLE_NONE
          populate_unit(player, prn)
          if (player.name) then
            players[player.name] = player
            update_unit_flags(prn, player, in_party, in_raid, players)
            -- Overwrite is_rl and is_aorl computed during update_unit_flags().
            if (rank == 2) then
              player.is_rl = true
            else
              player.is_rl = false
            end
            if (rank > 0) then
              player.is_aorl = true
            else
              player.is_aorl = false
            end
            if (ml) then
              player.is_ml = true
            else
              player.is_ml = false
            end
            players[player.name] = player
            KRP:DoCallbacks("new_player", players[player.name])
            raid[i] = player.name
            tinsert(raidgroups[subgrp], player.name)
          else
            return false
          end
        end
      end
    end
  end

  -- Update all of the table members, setting the in_party or in_raid stuff
  -- last so that the party and raid tables can be in place before we change
  -- those settings.
  reset_group()

  KRP.players = players
  KRP.party = party
  KRP.raid = raid
  KRP.raidgroups = raidgroups
  KRP.num_raid = nrm
  KRP.num_party = npm

  KRP.in_party = in_party
  KRP.in_raid = in_raid
  KRP.in_bg = in_bg

  player = players[K.player.name]

  KRP.subgroup = player.subgroup
  KRP.raidid = player.raidid

  update_loot_method_internal()
  update_leader_internal()
  update_role_internal()

  -- Send out all of the change events
  if (fire_party or old_inparty ~= KRP.in_party) then
    KRP:DoCallbacks("in_party_changed", in_party)
    changed = true
  end

  if (fire_raid or old_inraid ~= KRP.in_raid) then
    KRP:DoCallbacks("in_raid_changed", in_raid)
    changed = true
  end

  if (fire_bg or old_inbg ~= KRP.in_bg) then
    KRP:DoCallbacks("in_bg_changed", in_bg)
    changed = true
  end

  if (changed) then
    KRP:DoCallbacks("in_group_changed", in_party, in_raid, in_bg)
  end

  --
  -- We need to register for certain events if we haven't already.
  --
  if (not krp_flag_events) then
    KRP:RegisterEvent("PLAYER_FLAGS_CHANGED", function(evt, unitid)
      update_unit_flags(unitid, nil, nil, nil, nil)
    end)
    krp_flag_events = true
  end

  KRP:DoCallbacks("update_group_end", in_party, in_raid, in_bg)

  return true
end

--
-- Function: KRP.UpdateGroup(fire_party, fire_raid, fire_bg)
--           fire_XXX - fire the specified change event even if the state
--           hasn't changed. This is most commonly done when you want to
--           refresh the raid data and have all of the various callbacks
--           run after information that the callbacks may use has changed.
-- Purpose : Updates the various group related settings, namely:
--           in_party, in_raid, in_bg, subgroup, num_party, num_raid,
--           raid, party, players
-- Fires   : IN_RAID_CHANGED(is_in_raid)
--           IN_PARTY_CHANGED(is_in_party)
--           IN_BATTLEGROUND_CHANGED(is_in_bg)
--           Callback in_group_changed(in_party, in_raid, in_bg)
--
function KRP.UpdateGroup(fire_party, fire_raid, fire_bg)
  if (fire_party == nil) then
    fire_party = true
  end
  if (fire_raid == nil) then
    fire_raid = true
  end
  if (fire_bg == nil) then
    fire_bg = true
  end

  if (not KRP.initialised) then
    return false
  end

  if (not update_group_internal(fire_party, fire_raid, fire_bg)) then
    K:ScheduleTimer(function()
      update_group_internal(fire_party, fire_raid, fire_bg)
    end, 1.0)
    return false
  end
  return true
end

-- Function to deal with the start of a readycheck. This will mark all users
-- in the raid as unknown, except for the person who initiated the readycheck.
local function ready_check_start(evt, started_by, timeout, ...)
  if (not KRP.initialised) then
    return
  end

  local nm = K.FullUnitName(started_by)

  if (not nm or not KRP.in_party or not KRP.players or not KRP.players[nm]) then
    reset_ready()
    return
  end

  KRP.ready_start = time()
  KRP.ready_timeout = tonumber(timeout)
  KRP.ready_checking = true
  KRP.ready = {}
  for k, v in pairs(KRP.players) do
    KRP.ready[k] = RC_WAITING
  end
  KRP.ready[nm] = RC_READY

  KRP:DoCallbacks("readycheck_start")
end

-- Function to deal with a reply to a ready check
local function ready_check_confirm(evt, unit, status, ...)
  if (not KRP.initialised or not KRP.ready_checking or not KRP.ready) then
    return
  end

  local nm = K.FullUnitName(unit)

  if (not nm or nm == "" or not KRP.ready or not KRP.ready[nm]) then
    return
  end

  if (status) then
    KRP.ready[nm] = RC_READY
  else
    KRP.ready[nm] = RC_NOTREADY
  end
  KRP:DoCallbacks("readycheck_reply", nm, KRP.ready[nm])
end

-- And finally a function to deal with the end of a ready check
local function ready_check_ended(evt, ...)
  if (not KRP.initialised or not KRP.ready_checking or not KRP.ready) then
    return
  end

  KRP.ready_checking = false
  KRP.ready_timeout = nil
  KRP.ready_start = nil

  for k, v in pairs(KRP.ready) do
    if (v == RC_WAITING) then
      KRP.ready[k] = RC_AWAY
    end
  end

  KRP:DoCallbacks("readycheck_end")
end

local function krp_refresh(fire_party, fire_raid, fire_bg)
  if (not KRP.initialised) then
    return
  end

  if (KRP.UpdateGroup(fire_party, fire_raid, fire_bg)) then
    KRP.UpdateLootMethod(true)
    KRP.UpdateLeader(true)
    KRP.UpdateRole(true)
  end
end

function KRP:OnLateInit()
  if (KRP.initialised) then
    return
  end

  K:RegisterEvent("PARTY_LOOT_METHOD_CHANGED", function(evt)
    KRP.UpdateLootMethod(false)
  end)
  K:RegisterEvent("PARTY_LEADER_CHANGED", function(evt)
    KRP.UpdateLeader(false)
  end)
  K:RegisterEvent("PLAYER_ROLES_ASSIGNED", function(evt)
    KRP.UpdateRole(false)
  end)
  K:RegisterEvent("GROUP_ROSTER_UPDATE", function(evt)
    KRP.UpdateGroup(false, false, false)
  end)
  K:RegisterEvent("RAID_ROSTER_UPDATE", function(evt)
    KRP.UpdateGroup(false, false, false)
  end)
  K:RegisterEvent("READY_CHECK", ready_check_start)
  K:RegisterEvent("READY_CHECK_CONFIRM", ready_check_confirm)
  K:RegisterEvent("READY_CHECK_FINISHED", ready_check_ended)

  KRP.initialised = true

  krp_refresh()
end

K:RegisterMessage("PLAYER_INFO_UPDATED", function(evt, ...)
  krp_refresh(true, true, true)
end)

--
-- When an addon is suspended or resumed, we need to do a refresh because
-- the addon may have callbacks that have either been populated and now
-- need to be removed (addon suspended) or needs to add new data via the
-- callbacks (addon resumed). So we trap these two events and use them to
-- schedule a refresh.
--
function KRP:OnActivateAddon(name, onoff)
  krp_refresh(true, true, true)
end

--
-- Utility functions that more than one mod will likely need.
--
function KRP.ClassString(str, class)
  local sn
  if (type(str) == "table") then
    sn = str.name
    class = str.class
  else
    sn = str
  end

  if (KRP.in_party and KRP.players) then
    local pinfo = KRP.players[sn]
    if (pinfo) then
      if (class == nil) then
        return "|cff808080" .. sn .. "|r"
      end
      return K.ClassColorsEsc[class] .. sn .. "|r"
    else
      return "|cff808080" .. sn .. "|r"
    end
  end

  return K.ClassColorsEsc[class] .. sn .. "|r"
end

function KRP.ShortClassString(str, class)
  local sn
  if (type(str) == "table") then
    sn = str.name
    class = str.class
  else
    sn = str
  end

  if (KRP.in_party and KRP.players) then
    local pinfo = KRP.players[sn]
    sn = Ambiguate(sn, "guild")
    if (pinfo) then
      if (class == nil) then
        return "|cff808080" .. sn .. "|r"
      end
      return K.ClassColorsEsc[class] .. sn .. "|r"
    else
      return "|cff808080" .. sn .. "|r"
    end
  end

  sn = Ambiguate(sn, "guild")

  if (class == nil) then
    return "|cff808080" .. sn .. "|r"
  end
  return K.ClassColorsEsc[class] .. sn .. "|r"
end

function KRP.AlwaysClassString(str, class)
  local sn, class = str, class
  if (type(str) == "table") then
    sn = str.name
    class = str.class
  end

  if (class == nil) then
    return "|cff808080" .. sn .. "|r"
  end
  return K.ClassColorsEsc[class] .. sn .. "|r"
end

function KRP.ShortAlwaysClassString(str, class)
  local sn, class = str, class
  if (type(str) == "table") then
    sn = str.name
    class = str.class
  end

  sn = Ambiguate(sn, "guild")

  if (class == nil) then
    return "|cff808080" .. sn .. "|r"
  end
  return K.ClassColorsEsc[class] .. sn .. "|r"
end
