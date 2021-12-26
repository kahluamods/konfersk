--[[
   KahLua KonferSK - a suicide kings loot distribution addon.
     WWW: http://kahluamod.com/ksk
     Git: https://github.com/kahluamods/konfersk
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

local K = LibStub:GetLibrary("KKore")
local H = LibStub:GetLibrary("KKoreHash")

if (not K) then
  return
end

local ksk = K:GetAddon("KKonferSK")
local L = ksk.L
local KUI = ksk.KUI
local DB = ksk.DB
local KK = ksk.KK
local LS = ksk.LS
local ZL = ksk.ZL

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
local HIST_POS = ksk.HIST_POS

--
-- This file contains general purpose utility functions used throughout KSK.
--

--
-- Returns true if the user is thought to be a guild master, false
-- if we cant tell or can tell if they are not.
--
function ksk:UserIsRanked(cfg, name)
  if (K.UserIsRanked(name)) then
    return true
  end

  if (not K.player.is_guilded or not K.guild) then
    return false
  end

  if (name == K.guild.gmname) then
    return true
  end

  if (not self.frdb.configs[cfg]) then
    return false
  end

  if (not K.guild.roster.name[name]) then
    return false
  end

  local gi = K.guild.roster.name[name]
  local gu = K.guild.roster.id[gi]
  local ri = gu.rank
  if (strsub(self.frdb.configs[cfg].oranks, ri, ri) == "1") then
    return true
  end

  return false
end

--
-- If we have tethered alts, and the alt is in the raid, we need to store
-- the UID of the alt's main, else they will not be suicided.
--
function ksk:CreateRaidList(listid)
  local raiders = {}
  local ll = self.cfg.lists[listid]
  for k,v in ipairs(ll.users) do
    if (self:UserIsReserved(v)) then
      tinsert(raiders, v)
    elseif (self.users[v]) then
      tinsert(raiders, v)
    elseif (ll.tethered and self.cfg.users[v].alts) then
      for ak,av in pairs(self.cfg.users[v].alts) do
        if (self.users[av]) then
          tinsert(raiders, v)
          break
        end
      end
    end 
  end
  return raiders
end

function ksk:SplitRaidList(raidlist)
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
function ksk:SuicideUserLowLevel(listid, rlist, uid, cfgid, ilink)
  cfgid = cfgid or self.currentid

  if (not self.configs[cfgid]) then
    return
  end

  if (not self.configs[cfgid].lists[listid]) then
    return
  end

  local wl = self.configs[cfgid].lists[listid]
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
        if (lu[i] == uid or not self:UserIsFrozen(lu[i], nil, cfgid)) then
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
      if (not self:UserIsFrozen(lu[i], nil, cfgid)) then
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
  if (not self.csdata[cfgid].undo) then
    self.csdata[cfgid].undo = {}
  end
  tinsert(self.csdata[cfgid].undo, 1, undo)
  if (self:AmIML() and cfgid == self.currentid) then
    self.qf.undobutton:SetEnabled(true)
  end
  local nmove = undo.n - 1
  for i = 1, nmove do
    lu[movers[i]] = lu[movers[i+1]]
  end
  lu[movers[nmove+1]] = uid
  self:RefreshAllMemberLists()
end

local function get_event_id(this, cfg)
  local cfg = cfg or this.currentid

  if (not ts_datebase or ts_evtcount >= 9999) then
    local now = K.time()
    ts_datebase = tonumber(date("%y%m%d%H%M", now) .. "0000")
    ts_evtcount = 0
    while ((ts_datebase + ts_evtcount) < (this.configs[cfg].lastevent or 0)) do
      ts_evtcount = ts_evtcount + 100
    end
  end

  ts_evtcount = ts_evtcount + 1
  this.configs[cfg].lastevent = ts_datebase + ts_evtcount

  return this.configs[cfg].lastevent
end

--
-- This function is the central processing point for adding an event.
-- Adding events happens when an admin makes a change that results in the running CRC changing
-- and is shared with all admins. This is where the event string is computed. The code in
-- KSK-Comms.lua is used to process the events on receipt, and is the code that breaks apart
-- the event string and processes it.
--
local function lowlevel_add_event(self, cfgid, eventname, userevent, ...)
  local cfgid = cfgid or self.currentid

  --
  -- If I am an admin, but not the owner, and I am not syncing yet, do not even bother adding
  -- the event. Its meaningless, as the owner and other users cant sync with us until we have
  -- established a sync relationship.
  --
  local myuid = self.csdata[cfgid].myuid
  local ov = self.csdata[cfgid].is_admin

  if (ov == 1 and not self.configs[cfgid].syncing) then
    return
  end

  local cfg = self.configs[cfgid]

  local serialised = LS:Serialize(...)
  assert(serialised)
  local encoded = ZL:EncodeForWoWAddonChannel(serialised)
  assert(encoded)

  --
  -- Each event changes the config checksum. Since we are using XOR to change this running
  -- checksum, the exact order doesn't matter, as a user could sync with other admins in
  -- any random order, but as long as any two admins have both processed the exact same set
  -- of events, their shecksum will be the same.
  --
  -- The event is broadcast to the current raid (for a PUG config) or guild (for a guild
  -- config) and those admins that are currently online and fully synced with us will
  -- process the event immediately. If an admin is not online, or hasn't synced with us,
  -- then we simply queue the event for that admin.
  --
  local crc = H:CRC32(encoded)
  local oldsum = cfg.cksum
  local newsum = bxor(oldsum, crc)
  local oldeid = cfg.lastevent
  local eid = get_event_id(self, cfgid)
  local scrc, ocrc = K.hexstr(crc), K.hexstr(oldsum)

  cfg.cksum = newsum
  if (self.qf.synctopbar) then
    self.qf.synctopbar:SetCurrentCRC()
  end

  if (cfg.syncing) then
    for k,v in pairs(cfg.admins) do
      if (k ~= myuid) then
        if (not v.sync) then
          v.sync = {}
        end
        tinsert(v.sync, strfmt("%s\8%014.0f\8%s\8%s", eventname, eid, scrc, encoded))
      end
    end
  end

  self:CSendAM(cfgid, eventname, "ALERT", scrc, ocrc, eid, oldeid, userevent or false, encoded)
end

--
-- self:AddEvent(cfgid, eventname, ...)
-- self:AdminEvent(cfgid, eventname, ...)
-- The variadic portion is first serialised with LibSerialise, and then encoded for WoW. This
-- is the portion that is CRCed - the encoded, serialised portion. We do not compress any part
-- of the payload as the low level transmit funmction in KKore will do that for us for all
-- traffic. USEREVENT must be set to true if this event is intended for normal, non-admin
-- users to process as well, for example when a loot box is opened or a new item is being
-- rolled for etc.
--
function ksk:AdminEvent(cfgid, eventname, ...)
  lowlevel_add_event(self, cfgid, eventname, false, ...)
end

function ksk:AddEvent(cfgid, eventname, ...)
  lowlevel_add_event(self, cfgid, eventname, true, ...)
end

function ksk:RepairDatabases(users, lists)
  if (users == nil) then
    users = true
  end
  if (lists == nil) then
    lists = true
  end

  -- Repair config list count. Also remove sync data added for the admin by
  -- themselves. This means they have co-admins badly configured and they
  -- have an alt on the same account that has written sync data.
  self.frdb.nconfigs = 0
  for k,v in pairs(self.frdb.configs) do
    self.frdb.nconfigs = self.frdb.nconfigs + 1
    local to = v.owner
    if (v.admins[to]) then
      if (v.admins[to].sync) then
        v.admins[to].sync = nil
      end
    end
  end

  if (users) then
    for k,v in pairs(self.frdb.configs) do
      -- First remove any alts whose main was removed
      for uk, uv in pairs(v.users) do
        if (uv.main and not v.users[uv.main]) then
          self:DeleteUser(uk, k, false, true)
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
    for k,v in pairs(self.frdb.configs) do
      v.nlists = 0
      for lk,lv in pairs(v.lists) do
        v.nlists = v.nlists + 1
        if (not lv.sortorder) then
          lv.sortorder = 1
        end
        if (not lv.def_rank) then
          lv.def_rank = 0
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

function ksk:UpdateDatabaseVersion()
  local ret = false

  if (not self.frdb.dbversion) then
    self.frdb.dbversion = self.dbversion
    return ret
  end

  if (self.frdb.dbversion == 1) then
    --
    -- Version 2 removed the "guild" config type. Find all such configs
    -- and remove the cfgtype from the config. We also changed the storage
    -- format of the history items.
    --
    for k,v in pairs(self.frdb.configs) do
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

      --
      -- We also dont use Name-Realm names to disambiguate things as that is
      -- not supported in classic WoW and prevents certain API calls like
      -- UnitInRange() from working correctly.
      --
      for kk,vv in pairs(v.users) do
        vv.name = K.CanonicalName(vv.name)
      end
    end

    ret = true
    self.frdb.dbversion = 2
  end

  if (self.frdb.dbversion == 2) then
    --
    -- Version 3 added back the config type. We sneakily changed the version 1
    -- mod code above to not remove it. So if we have a value we leave it alone
    -- otherwise we have to add it back and we default to a PUG config.
    --
    for k,v in pairs(self.frdb.configs) do
      if (v.cfgtype == nil) then
        v.cfgtype = KK.CFGTYPE_PUG
      end
      if (v.oranks == nil) then
        v.oranks = "1000000000"
      end
      if (v.settings.def_rank == nil) then
        v.settings.def_rank = 0
      end
      if (v.settings.use_ranks == nil) then
        v.settings.use_ranks = false
      end
      if (v.settings.rank_prio == nil) then
        v.settings.rank_prio = {}
      end
    end

    ret = true
    self.frdb.dbversion = 3
  end

  if (self.frdb.dbversion == 3) then
    --
    -- Version 4 made alts being tethered to mains a list option not a global
    -- one. So pick up the current setting and change all of the lists. If
    -- we are the owner of a config also send out CHLST events with the new
    -- setting so that all admins have the same value.
    --
    for k,v in pairs(self.frdb.configs) do
      for kk,vv in pairs(v.lists) do
        vv.tethered = v.tethered
      end
      v.tethered = nil
    end

    ret = true
    self.frdb.dbversion = 4
  end

  if (self.frdb.dbversion == 4) then
    --
    -- Version 5 added the list position to the loot history if the user
    -- suicided on a list.
    --
    for k,v in pairs(self.frdb.configs) do
      for kk,vv in pairs(v.history) do
        vv[HIST_POS] = 0
      end
    end
  end

  if (self.frdb.dbversion == 5) then
    --
    -- Version 6 added the alt display option to lists. It also changes the way
    -- events are stored for co-admins so we actually remove all co-admins from
    -- the lists and force the owners to re-create them.
    --
    for k,v in pairs(self.frdb.configs) do
      for kk,vv in pairs(v.lists) do
        vv.altdisp = true
      end

      local owner = v.owner
      local ownerid = v.admins[owner].id
      v.nadmins = 1
      v.admins = { }
      v.admins[owner] = { }
      v.admins[owner]["id"] = ownerid
    end
  end

  -- Somehow, tempcfg survives an initial broadcast.
  if (self.frdb.defconfig ~= "1") then
    self.frdb.tempcfg = nil
  end

  self.frdb.dbversion = self.dbversion
  return ret
end
