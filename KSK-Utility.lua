--[[
   KahLua KonferSK - a suicide kings loot distribution addon.
     WWW: http://kahluamod.com/ksk
     Git: https://github.com/kahluamods/konfersk
     IRC: #KahLua on irc.freenode.net
     E-mail: cruciformer@gmail.com

   Please refer to the file LICENSE.txt for the Apache License, Version 2.0.

   Copyright 2008-2020 James Kean Johnston. All rights reserved.

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

local K = LibStub:GetLibrary("KKore")
local H = LibStub:GetLibrary("KKoreHash")

if (not K) then
  return
end

local ksk = K:GetAddon("KKonferSK")
local L = ksk.L
local KUI = ksk.KUI
local DB = ksk.DB

-- Local aliases for global or Lua library functions
local _G = _G
local tinsert = table.insert
local tremove = table.remove
local tonumber = tonumber
local strfmt = string.format
local strsub = string.sub
local gmatch = string.gmatch
local gsub = string.gsub
local strfind = string.find
local pairs, ipairs = pairs, ipairs
local bxor = bit.bxor
local debug = ksk.debug

--
-- This file contains general purpose utility functions used throughout KSK.
--

--
-- Returns true if the user is thought to be a guild master, false
-- if we cant tell or can tell if they are not.
--
function ksk.UserIsRanked(cfg, name)
  if (not K.player.is_guilded or not K.guild) then
    return false
  end

  if (name == K.guild.gmname) then
    return true
  end

  if (not ksk.frdb.configs[cfg]) then
    return false
  end

  if (not K.guild.roster.name[name]) then
    return false
  end

  return false
end

--
-- If we have tethered alts, and the alt is in the raid, we need to store
-- the UID of the alt's main, else they will not be suicided.
--
function ksk.CreateRaidList(listid)
  local raiders = {}
  for k,v in ipairs(ksk.lists[listid].users) do
    if (ksk.UserIsReserved(v)) then
      tinsert(raiders, v)
    elseif (ksk.group.users[v]) then
      tinsert(raiders, v)
    elseif (ksk.cfg.tethered and ksk.users[v].alts) then
      for ak,av in pairs(ksk.users[v].alts) do
        if (ksk.group.users[av]) then
          tinsert(raiders, v)
          break
        end
      end
    end 
  end
  return raiders
end

function ksk.SplitRaidList(raidlist)
  local raiders = {}
  for w in gmatch(raidlist, "....") do
    tinsert(raiders, w)
  end
  return raiders
end

--
-- Suicide the user specified by UID on the list LISTID in configuration
-- CFGID. The list of raiders affected by the move is in RLIST. Modifies
-- the list in place. Does not record or transmit events. That is handled
-- elsewhere.
-- Here is how we do suicides. First thing is we find the user being
-- suicided in the raiders list. Any users "above" the user are not
-- subject to moving, so we discount those. Once we have found the user
-- we add their current position to the "movers" list, and add all
-- users below them into the the said movers list. Thus the movers list
-- will contain the full list of people actually affected by the move,
-- and the position they currently occupy in the list. Once we have this
-- it is a simple matter of moving the first user to the bottom of the
-- list and moving everyone else up one slot. The only wrinkle that comes
-- into play is if the user is "frozen". If they are it means that their
-- position in the list needs to remain static, even if they were in the
-- raid. If they were not in the raid they are not affected by moves and
-- will remain static anyway. However, if they are frozen then their
-- position must not change. The easiest way to achieve that is to simply
-- remove any frozen users from the movers list before we suicide the
-- current player, Again, there is a slight exception. If the player being
-- suicided is themselves frozen, we simply pretend that they are not, and
-- move them to the bottom of the list.
--
function ksk.SuicideUserLowLevel(listid, rlist, uid, cfgid, ilink)
  cfgid = cfgid or ksk.currentid

  if (not ksk.configs[cfgid]) then
    return
  end

  if (not ksk.configs[cfgid].lists[listid]) then
    return
  end

  local wl = ksk.configs[cfgid].lists[listid]
  local lu = wl.users
  local found = false
  local movers = {}

  for i = 1, #rlist do
    if (rlist[i] == uid) then
      found = true
      break
    end
  end

  --
  -- This should never happen but hey, whats a simple check.
  --
  if (not found) then
    return
  end

  local foundfirst = false
  for i = 1, #lu do
    found = false
    local j = 1
    while (j <= #rlist) do
      if (lu[i] == rlist[j]) then
        found = true
        break
      end
      j = j + 1
    end

    if (found) then
      if (lu[i] == uid) then
        foundfirst = true
      end
      if (foundfirst) then
        if (lu[i] == uid or not ksk.UserIsFrozen(lu[i], nil, cfgid)) then
          tinsert(movers, i)
        end
      end
    end
  end

  --
  -- This checks to ensure that the first user in the movers list is actually
  -- the userid being suicided. If not, it means that for some reason the user
  -- was not in the list and we therefore have nothing to do. If we only have
  -- one entry in movers, it means the user was not in any actual raid but
  -- was manually suicided by a list admin outside the bounds of a raid. This
  -- is a special case, and in this case the user is moved to the extreme
  -- bottom of the list and everyone except for frozen users is moved up one
  -- slot.
  --
  if (lu[movers[1]] ~= uid) then
    return
  end

  if (#movers == 1) then
    --
    -- Add every user that isn't frozen after the user's current position to
    -- the movers list. This will effectively move the user to the bottom of
    -- the list and move everyone else (that is unfrozen) up one slot. If
    -- there are no users below the user being suicided it means they are
    -- already at the bottom of the list and we have nothing to do.
    --
    local p = movers[1]
    if (p == #lu) then
      return
    end
    for i = p+1, #lu do
      if (not ksk.UserIsFrozen(lu[i], nil, cfgid)) then
        tinsert(movers, i)
      end
    end
  end

  --
  -- Final step. Adjust the actual list users array according to movers.
  -- But first create the undo record.
  --
  local undo = {
    n = #movers, movers = {}, listid = listid, uid = uid, ilink = ilink,
  }
  for i = 1, undo.n do
    undo.movers[i] = lu[movers[i]]
  end
  if (not ksk.csdata[cfgid].undo) then
    ksk.csdata[cfgid].undo = {}
  end
  tinsert(ksk.csdata[cfgid].undo, 1, undo)
  if (ksk.AmIML() and cfgid == ksk.currentid) then
    ksk.qf.undobutton:SetEnabled(true)
  end
  local nmove = undo.n - 1
  for i = 1, nmove do
    lu[movers[i]] = lu[movers[i+1]]
  end
  lu[movers[nmove+1]] = uid
  ksk.RefreshAllMemberLists()
end

function ksk.AddEvent(cfgid, event, estr, ufn)
  local cfgid = cfgid or ksk.currentid

  --
  -- If I am an admin, but not the owner, and I am not syncing yet, do
  -- not even bother adding the event. Its meaningless, as the owner
  -- and other users cant sync with us until we have established a sync
  -- relationship.
  --
  local myuid = ksk.csdata[cfgid].myuid
  local ov = ksk.csdata[cfgid].is_admin

  if (ov == 1 and not ksk.configs[cfgid].syncing) then
    return
  end

  local cfg = ksk.configs[cfgid]

  --
  -- This event will change our config checksum. We need to get the CRC for
  -- the event string, and xor it with our current config checksum. We then
  -- need to add it to all co-admins who are currently syncing with us. We
  -- then broadcast the event to the raid or guild. Those syncers that are
  -- on and up to date will perform the action, and remain up to date.
  -- Those that are not online will simply have the event queued for when
  -- they are. Pretty simple really.
  --
  local crc = H:CRC32(estr)
  local oldsum = cfg.cksum
  local newsum = bxor(oldsum, crc)
  local oldeid = cfg.lastevent
  local eid = ksk.GetEventID(cfgid)
  local scrc = strfmt("0x%s", K.hexstr(crc))

  cfg.cksum = newsum
  if (ksk.qf.synctopbar) then
    ksk.qf.synctopbar:SetCurrentCRC()
  end

  if (cfg.syncing) then
    for k,v in pairs(cfg.admins) do
      if (k ~= myuid) then
        if (not v.sync) then
          v.sync = {}
        end
        tinsert(v.sync, strfmt("%s\8%014.0f\8%s\8%s", event, eid, scrc, estr))
      end
    end
  end

  ksk:CSendAM(cfgid, event, "ALERT", estr, scrc, eid, oldeid, ufn or false)
end

function ksk.RepairDatabases(users, lists)
  if (users == nil) then
    users = true
  end
  if (lists == nil) then
    lists = true
  end

  -- Repair config list count. Also remove sync data added for the admin by
  -- themselves. This means they have co-admins badly configured and they
  -- have an alt on the same account that has written sync data.
  ksk.frdb.nconfigs = 0
  for k,v in pairs(ksk.frdb.configs) do
    ksk.frdb.nconfigs = ksk.frdb.nconfigs + 1
    local to = v.owner
    if (v.admins[to]) then
      if (v.admins[to].sync) then
        v.admins[to].sync = nil
      end
    end
  end

  if (users) then
    for k,v in pairs(ksk.frdb.configs) do
      -- First remove any alts whose main was removed
      for uk, uv in pairs(v.users) do
        if (uv.main and not v.users[uv.main]) then
          ksk.DeleteUser(uk, k, false, true)
        end
      end
      -- Now calculate the correct number of users
      v.nusers = 0
      for uk, uv in pairs(v.users) do
        v.nusers = v.nusers + 1
      end
    end
  end

  if (lists) then
    for k,v in pairs(ksk.frdb.configs) do
      v.nlists = 0
      for lk,lv in pairs(v.lists) do
        v.nlists = v.nlists + 1
        if (not lv.sortorder) then
          lv.sortorder = 1
        end
        if (not lv.strictcfilter) then
          lv.strictcfilter = false
        end
        if (not lv.strictrfilter) then
          lv.strictrfilter = false
        end
        if (not lv.extralist) then
          lv.extralist = "0"
        end
        if (not lv.users) then
          lv.users = {}
          lv.nusers = 0
        end
        if (strfind(lv.name, ":")) then
          lv.name = gsub(lv.name, ":", "-")
        end
        local lui = 1
        while (lui <= #lv.users) do
          local uid = lv.users[lui]
          if (not v.users[uid]) then
            tremove(lv.users, lui)
          else
            lui = lui + 1
          end
        end
        lv.nusers = #lv.users
      end
    end
  end
end

function ksk.UpdateDatabaseVersion()
  local ret = false

  if (not ksk.frdb.dbversion) then
    ksk.frdb.dbversion = ksk.dbversion
    return ret
  end

  if (ksk.frdb.dbversion == 1) then
    --
    -- Version 2 removed the "guild" config type. Find all such configs
    -- and remove the cfgtype from the config. We also changed the storage
    -- format of the history items.
    --
    for k,v in pairs(ksk.frdb.configs) do
      v.cfgtype = nil
      v.settings.def_rank = nil
      v.settings.use_ranks = nil
      v.settings.rank_prio = nil
      local newhist = {}
      for kk,vv in pairs(v.history) do
        local when,what,who,how = strsplit("\7", vv)
        local otm = {}
        otm.year = tonumber(strsub(when, 1, 4))
        otm.month = tonumber(strsub(when, 5,6))
        otm.day = tonumber(strsub(when, 7, 8))
        otm.hour = tonumber(strsub(when, 9, 10))
        otm.min = tonumber(strsub(when, 11, 12))
        otm.sec = 0
        when = time(otm) - K.utcdiff
        tinsert(newhist, { tonumber(when), what, who, how })
      end
      v.history = newhist
    end
    ret = true
  end

  --
  -- Fix a potential error with co-admins
  --
  for k,v in pairs(ksk.frdb.configs) do
    for kk,vv in pairs(v.admins) do
      if (vv.active == true) then
        if (vv.lastevent == nil) then
          vv.lastevent = 0
        end
      end
    end
  end

  -- Somehow, tempcfg survives an initial broadcast.
  if (ksk.frdb.defconfig ~= "1") then
    ksk.frdb.tempcfg = nil
  end

  ksk.frdb.dbversion = ksk.dbversion
  return ret
end
