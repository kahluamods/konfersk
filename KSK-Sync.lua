--[[
   KahLua KonferSK - a suicide kings loot distribution addon.
     WWW: http://kahluamod.com/ksk
     Git: https://github.com/kahluamods/konfersk
     IRC: #KahLua on irc.freenode.net
     E-mail: me@cruciformer.com
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

if (not K) then
  return
end

local ksk = K:GetAddon("KKonferSK")
local L = ksk.L
local KUI = ksk.KUI
local MakeFrame = KUI.MakeFrame

-- Local aliases for global or Lua library functions
local _G = _G
local tinsert = table.insert
local tremove = table.remove
local tsort = table.sort
local tostring, tonumber = tostring, tonumber
local strfmt = string.format
local pairs = pairs
local assert = assert
local debug = ksk.debug

local info = ksk.info
local white = ksk.white
local red = ksk.red
local green = ksk.green
local aclass = ksk.aclass
local shortaclass = ksk.shortaclass

local selsyncer
local sortedsyncers
local repliers
local busy_with_sync = nil
local recovery = nil
local qf = {}

local function clear_syncers_list()
  qf.syncers.itemcount = 0
  qf.syncers:UpdateList()
  qf.syncers:SetSelected(nil)
  repliers = nil
end

--
-- This file contains all of the code for syncing lists between users. It also
-- has all of the code for broadcasting lists to raids / guilds and most other
-- sync related functions, as well as all of the UI handling code for the
-- sync tab.
--

local function slist_selectitem(objp, idx, slot, btn, onoff)
  local onoff = onoff or false
  local mask = true

  if (ksk.csd.is_admin == 2 and not ksk.cfg.syncing) then
    mask = false
  end

  if (onoff) then
    local en = true
    qf.reqsyncbutton:SetEnabled(en and mask)
    if (ksk.csd.is_admin == 2) then
      en = true
    else
      en = false
    end
    qf.recoverbutton:SetEnabled(en)
  else
    qf.reqsyncallbutton:SetEnabled(mask)
    qf.reqsyncbutton:SetEnabled(false)
    qf.recoverbutton:SetEnabled(false)
  end
end

local function rlist_newitem(objp, num)
  local bname = "KSKSyncRepButton" .. tostring(num)
  local rf = MakeFrame("Button", bname, objp.content)
  local nfn = "GameFontNormalSmallLeft"
  local htn = "Interface/QuestFrame/UI-QuestTitleHighlight"

  rf:SetWidth(260)
  rf:SetHeight(48)
  rf:SetHighlightTexture(htn, "ADD")

  local sb = MakeFrame("Button", bname .. "SB", rf, "UIPanelButtonTemplate")
  sb:SetHeight(20)
  sb:SetWidth(95)
  sb:ClearAllPoints()
  sb:SetPoint("TOPLEFT", rf, "TOPLEFT", 165, 0)
  sb:GetFontString():SetText(L["Sync"])
  sb:Disable()
  sb:SetScript("OnClick", function(this)
    local idx = this:GetParent():GetID()
    if (busy_with_sync) then
      info(L["busy syncing with %q. Please try again when complete."], busy_with_sync)
      return
    end
    local rp = repliers[idx]
    busy_with_sync = shortaclass(ksk.cfg.users[rp.theiruid])

    ksk:SendWhisperAM(ksk.cfg.users[rp.theiruid].name, "GSYNC", "ALERT", rp.mylast, false, ksk.cfg.lastevent, ksk.cfg.cksum)
    this:Disable()
    rp.synced = true
  end)
  rf.syncbutton = sb

  local user = rf:CreateFontString(nil, "ARTWORK", nfn)
  user:ClearAllPoints()
  user:SetPoint("TOPLEFT", rf, "TOPLEFT", 8, -2)
  user:SetPoint("BOTTOMRIGHT", rf, "TOPLEFT", 152, -14)
  user:SetJustifyH("LEFT")
  user:SetJustifyV("TOP")
  rf.user = user

  local cks = rf:CreateFontString(nil, "ARTWORK", nfn)
  cks:ClearAllPoints()
  cks:SetPoint("TOPLEFT", user, "BOTTOMLEFT", 0, -2)
  cks:SetPoint("BOTTOMRIGHT", user, "BOTTOMRIGHT", 0, -14)
  cks:SetJustifyH("LEFT")
  cks:SetJustifyV("TOP")
  rf.cks = cks

  local tss = rf:CreateFontString(nil, "ARTWORK", nfn)
  tss:ClearAllPoints()
  tss:SetPoint("TOPLEFT", cks, "BOTTOMLEFT", 0, -2)
  tss:SetPoint("BOTTOMRIGHT", cks, "BOTTOMRIGHT", 100, -14)
  tss:SetJustifyH("LEFT")
  tss:SetJustifyV("TOP")
  rf.tss = tss

  rf.SetText = function(self, idx)
    local rp = repliers[idx]
    self.user:SetText(rp.name)
    local fn = green
    if (not rp.active) then
      self.cks:SetText(red(L["Not active!"]))
    else
      if (rp.cksum ~= ksk.cfg.cksum) then
        fn = red
      end
      self.cks:SetText(fn(strfmt(L["Checksum: 0x%s"], K.hexstr(rp.cksum))))
    end
    if (rp.mylast ~= rp.last) then
      fn = red
      self.syncbutton:Enable()
    else
      fn = green
      self.syncbutton:Disable()
    end
    if (rp.synced) then
      self.syncbutton:Disable()
    end
    self.tss:SetText(fn(strfmt("%014.0f / %014.0f", rp.mylast, rp.last)))
  end

  rf:SetScript("OnClick", function(this)
  end)

  return rf
end

local function rlist_setitem(objp, idx, slot, btn)
  btn:SetText(idx)
  btn:SetID(idx)
  btn:Show()
end

local function rlist_selectitem(objp, idx, slot, btn, onoff)
end

--
-- This function will prepare the table to be broadcast for a specified
-- config.
-- a table suitable for transmission with the following values:
--   v=4 (version 4 broadcast)
--   c=cfgid:name:type:tethered:ownerid:oranks:crc
--   u={numusers,userlist}
--     Each element in userlist is name:class:role:ench:frozen:exempt:alt:main
--   a={numadmins,adminlist}
--     Each element in adminlist is uid:adminid
--   l={numlists,listinfo}
--     Each element in listinfo is
--       listid:name:order:strictc:strictr:xlist:tout:next:nusers:ulist
--   s=syncers data (for FSYNC)
--   i=item database (for FSYNC)
--   e=last event ID (for FSYNC)
--   d=my userid (for FSYNC)
--
local function prepare_broadcast(cfg)
  local cfg = cfg or ksk.currentid
  local ci = {}
  local tc = ksk.configs[cfg]

  ci.v = 4
  ci.c = strfmt("%s:%s:%d:%s:%s:%s:0x%s", cfg, tc.name, tc.cfgtype,
    tc.tethered and "Y" or "N", tc.owner, tc.oranks, K.hexstr(tc.cksum))

  local ulist = {}
  for k,v in pairs(tc.users) do
    local alts=""
    local isalt
    if (v.main) then
      isalt = "Y"
      alts = v.main
    else
      isalt = "N"
      if (v.alts) then
        for kk,vv in pairs(v.alts) do
          alts = alts .. vv
        end
      else
        alts = "0"
      end
    end
    local us = strfmt("%s:%s:%s:%d:%s:%s:%s", k, v.name, v.class, v.role,
      v.flags, isalt, alts)
    tinsert(ulist, us)
  end
  ci.u = { #ulist, ulist }

  local alist = {}
  for k,v in pairs(ksk.cfg.admins) do
    if (v.id) then
      local us = strfmt("%s:%s", k, v.id)
      tinsert(alist, us)
    end
  end
  ci.a = { #alist, alist }

  local llist = {}
  for k,v in pairs(tc.lists) do
    local ulist = ""
    for kk,vv in pairs(v.users) do
      ulist = ulist .. vv
    end
    local ls = strfmt("%s:%s:%d:%d:%s:%s:%s:%d:%s", k, v.name,
      v.sortorder, v.def_rank, v.strictcfilter and "Y" or "N",
      v.strictrfilter and "Y" or "N", tostring(v.extralist),
      v.nusers, ulist)
    tinsert(llist, ls)
  end

  ci.l = { tc.nlists, llist }

  return ci
end

local function broadcast_config(isshifted)
  debug(1, "broadcast called")
  local ci = prepare_broadcast(nil)
  if (ishshifted and K.player.is_guilded) then
    ksk:SendGuildAM("BCAST", "ALERT", ci)
  else
    ksk:SendAM("BCAST", "ALERT", ci)
  end
end

function ksk.RecoverConfig(sender, cfg, cfgid, rdata)
  if (not recovery) then
    return
  end

  if (sender ~= ksk.cfg.users[recovery.uid].name) then
    return
  end

  local current_cfgid = ksk.FindConfig(cfg.name)
  assert(current_cfgid)

  --
  -- We need to make some slight adjustments to the recovery data and do some
  -- simple checks. Since this is such a drastic action it is very important
  -- we get everything exactly right.
  --
  cfg.history = {}
  if (ksk.configs[cfgid]) then
    --
    -- Attempt to preserve any local history and settings
    --
    K.CopyTable(ksk.configs[cfgid].settings, cfg.settings)
    K.CopyTable(ksk.configs[cfgid].history, cfg.history)
  end

  for k,v in pairs(rdata.s) do
    local adm, le = strsplit(":", v)
    if (adm == cfg.owner) then
      cfg.lastevent = tonumber(le)
      cfg.admins[adm] = { id = "0" }
    else
      if (adm == rdata.d) then
        cfg.admins[adm].lastevent = rdata.e
      else
        cfg.admins[adm].lastevent = tonumber(le)
      end
      cfg.admins[adm].sync = {}
      cfg.admins[adm].active = true
    end
  end

  cfg.syncing = true
  ksk.frdb.configs[cfgid] = cfg
  if (current_cfgid ~= cfgid) then
    ksk.frdb.configs[current_cfgid] = nil
    if (ksk.frdb.defconfig == current_cfgid) then
      ksk.frdb.defconfig = cfgid
    end
  end
  if (ksk.frdb.defconfig == cfgid) then
    ksk.SetDefaultConfig(cfgid, true, true)
  end
  ksk.FullRefresh(true)
  ksk.SyncUpdateReplier()
  ksk.RefreshSyncUI(true)
  info("recovery from user %s complete.", shortaclass(cfg.users[rdata.d]))
  recovery = nil
  ksk.mainwin:Show()
end

local function recover_config()
  ksk.mainwin:Hide()

  local function real_recover(arg)
    --
    -- All we need to do to start the recovery process is to record which
    -- user and config we have requested the recovery from, and send them
    -- the request. If we get back any reply that does not match we silently
    -- ignore it.
    --
    recovery = { cfg = arg.cfg, uid = arg.uid }
    ksk:CSendWhisperAM(arg.cfg, ksk.cfg.users[arg.uid].name, "RCOVR", "ALERT", ksk.cfg.name)
    info(L["waiting for recovery reply from %s. Do not use KSK until recovery is complete."], shortaclass(ksk.cfg.users[arg.uid]))
  end

  K.ConfirmationDialog(ksk, L["Recover Configuration"],
    strfmt(L["RECOVERMSG"], aclass(ksk.cfg.users[selsyncer]),
      aclass(ksk.cfg.users[selsyncer])),
    ksk.cfg.name, real_recover,
    { cfg = ksk.currentid, uid = selsyncer}, false, 250)
  return
end

function ksk.InitialiseSyncUI()
  local arg

  --
  -- Sync tab
  --
  local ypos = 0

  local cf = ksk.mainwin.tabs[ksk.SYNC_TAB].content
  local tbf = ksk.mainwin.tabs[ksk.SYNC_TAB].topbar
  local ls = cf.vsplit.leftframe
  local rs = cf.vsplit.rightframe

  arg = {
    x = 0, y = -18, text = "", autosize = false, width = 250,
    font = "GameFontNormalSmall",
  }
  tbf.mycksum = KUI:CreateStringLabel(arg, tbf)
  arg = {}

  -- Must preserve this in ksk.qf its used in many places.
  ksk.qf.synctopbar = tbf
  tbf.SetCurrentCRC = function()
    tbf.mycksum:SetText(strfmt(L["My checksum: %s"], white(strfmt("0x%s", K.hexstr(ksk.cfg.cksum)))))
  end

  arg = {
    inset = 2, height = 50,
    leftsplit = true, name = "KSKSyncRSplit",
  }
  rs.hsplit = KUI:CreateHSplit(arg, rs)
  arg = {}
  local tr = rs.hsplit.topframe
  local br = rs.hsplit.bottomframe
  -- Usable tr width = 260 (its 285 in total - 25 for the scroll bar)

  arg = {
    name = "KSKAdminSyncScrollList",
    itemheight = 16,
    newitem = function(objp, num)
      return KUI.NewItemHelper(objp, num, "KSKSyncOwnerButton", 160, 16,
        nil, nil, function(this, idx) selsyncer = sortedsyncers[idx] end, nil)
      end,
    setitem = function(objp, idx, slot, btn)
      return KUI.SetItemHelper(objp, btn, idx,
        function(op, ix)
          return shortaclass(ksk.cfg.users[sortedsyncers[ix]])
        end)
      end,
    selectitem = function(objp, idx, slot, btn, onoff)
      return KUI.SelectItemHelper(objp, idx, slot, btn, onoff,
        function()
          if (not selsyncer) then return nil end
          if (selsyncer ~= sortedsyncers[idx]) then return false end
          return true
        end, slist_selectitem, nil, slist_selectitem)
      end,
    highlightitem = KUI.HighlightItemHelper,
  }
  ls.olist = KUI:CreateScrollList(arg, ls)
  arg = {}
  qf.syncerslist = ls.olist

  local bdrop = {
    bgFile = KUI.TEXTURE_PATH .. "TDF-Fill",
    tile = true,
    tileSize = 32,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
  }
  ls.olist:SetBackdrop(bdrop)

  arg = {
    x = 0, y = ypos, text = L["Request Sync"], width = 140,
    enabled = false,
    tooltip = { title = "$$", text = L["TIP087"] },
  }
  br.rsync = KUI:CreateButton(arg, br)
  br.rsync:Catch("OnClick", function(this, evt)
    clear_syncers_list()
    ksk:SendWhisperAM(ksk.cfg.users[selsyncer].name, "RSYNC", "ALERT")
  end)
  arg = {}
  qf.reqsyncbutton = br.rsync

  arg = {
    x = 145, y = ypos, text = L["Request Sync (All)"], width = 140,
    enabled = false,
    tooltip = { title = "$$", text = L["TIP088"] },
  }
  br.rsyncall = KUI:CreateButton(arg, br)
  br.rsyncall:Catch("OnClick", function(this, evt)
    clear_syncers_list()
    ksk:SendAM("RSYNC", "ALERT")
  end)
  arg = {}
  qf.reqsyncallbutton = br.rsyncall
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, text = L["Broadcast"], width = 140,
    enabled = false,
    tooltip = { title = "$$", text = L["TIP089"] },
  }
  br.bcast = KUI:CreateButton(arg, br)
  br.bcast:Catch("OnClick", function(this, evt)
    broadcast_config(IsShiftKeyDown())
  end)
  arg = {}
  -- Keep this in ksk.qf as its accessed from KKonferSK.lua
  ksk.qf.bcastbutton = br.bcast

  arg = {
    x = 145, y = ypos, text = L["Recover"], width = 140,
    enabled = false,
    tooltip = { title = "$$", text = L["TIP090"] },
  }
  br.recover = KUI:CreateButton(arg, br)
  br.recover:Catch("OnClick", function(this, evt)
    if (ksk.csd.is_admin == 2) then
      recover_config()
    end
  end)
  qf.recoverbutton = br.recover

  arg = {
    name = "KSKSyncReplyScrollList",
    itemheight = 48,
    newitem = rlist_newitem,
    setitem = rlist_setitem,
    selectitem = rlist_selectitem,
    highlightitem = function(objp, idx, slot, btn, onoff)
      return nil
    end,
  }
  tr.rlist = KUI:CreateScrollList(arg, tr)
  arg = {}
  qf.syncers = tr.rlist
  tr.rlist:SetBackdrop(bdrop)
end

function ksk.RefreshSyncUI(reset)
  if (ksk.frdb.tempcfg) then
    return
  end

  sortedsyncers = {}
  selsyncer = nil

  local ia, maid = ksk.IsAdmin(ksk.csd.myuid)

  for k,v in pairs(ksk.cfg.admins) do
    if (k ~= maid) then
      tinsert(sortedsyncers, k)
    end
  end
  tsort(sortedsyncers, function(a,b)
    return ksk.cfg.users[a].name < ksk.cfg.users[b].name
  end)

  qf.syncerslist.itemcount = #sortedsyncers
  qf.syncerslist:UpdateList()
  qf.syncerslist:SetSelected(nil)

  if (reset) then
    repliers = nil
    qf.syncers.itemcount = 0
    qf.syncers:UpdateList()
    qf.syncers:SetSelected(nil)
    return
  end

  --
  -- Rather than clearing out the entire replies list, simply make sure
  -- that any repliers that are currently extant are still syncers.
  --
  if (repliers) then
    local i = 1
    while (i <= #repliers) do
      local v = repliers[i]
      if (not ksk.cfg.admins[v.cktheiruid]) then
        tremove(repliers, i)
      else
        i = i + 1
      end
    end
    qf.syncers.itemcount = #repliers
    qf.syncers:UpdateList()
    qf.syncers:SetSelected(nil)
  end
end

--
-- This is called from the MSYNC handler to update a replier now that
-- we are done processing a sync. Simply give us the new EID for the
-- syncer so we can colorise and set the text correctly. We also mark
-- that we are no longer busy syncing so that other sync buttons become
-- active again.
--
function ksk.SyncUpdateReplier(theiruid, theireid)
  busy_with_sync = nil
  if (not theiruid or not repliers) then
    return
  end
  for k,v in pairs(repliers) do
    if (v.theiruid == theiruid) then
      v.mylast = theireid
    end
  end
end

--
-- This function is called when a user responds to a request for sync data.
-- They respond with their highest event number and checksum.
-- We only use the event number currently. If we already have
-- a sync relationship with this user, and they have events higher than our
-- last recorded event from them, we request all events after the latest
-- one we have. If we have never synced with them before we obviously
-- request all info from them. We have a corner case we need to cover here
-- though. If we are a newly-appointed admin and we have never synced
-- with anyone before we will request a "full sync" where they simply send
-- us their entire config, as well as who they are synced up with and to
-- what point.
-- Note that this function actually just sets up all of the info for the
-- syncer display in the right hand panel. If there is data to sync,
-- an active sync button will be displayed that when pressed, does the
-- actual sync request.
--
function ksk.ProcessSyncAck(cfg, myuid, theiruid, cktheiruid, lastevt, cksum)
  repliers = repliers or {}

  if (not ksk.configs[cfg].syncing) then
    --
    -- If we are not syncing with anyone yet, then we only accept replies
    -- from the config owner. So even if others respond, we ignore the
    -- response for now. If it is the owner responding, we don't even bother
    -- displaying the reply we just immediately request a full sync from the
    -- owner. After we have processed the full sync from the owner we will
    -- send out another guild / raid RSYNC to start the syncing relationship
    -- with other owners.
    if (theiruid ~= ksk.configs[cfg].owner) then
      return
    end
    ksk:CSendWhisperAM(cfg, ksk.configs[cfg].users[theiruid].name, "GSYNC", "ALERT", 0, true, 0, 0)
    return
  end

  local mylast = ksk.configs[cfg].admins[cktheiruid].lastevent
  if (not mylast) then
    mylast = 0
  end

  local active = ksk.configs[cfg].admins[cktheiruid].active or false

  tinsert(repliers, { name = shortaclass(ksk.cfg.users[theiruid]),
    theiruid = theiruid, myuid = myuid, mylast = mylast,
    last = lastevt, cksum = cksum, active = active, cktheiruid = cktheiruid,
  })

  qf.syncers.itemcount = #repliers
  qf.syncers:UpdateList()
  qf.syncers:SetSelected(nil)
end

function ksk.SendFullSync(cfg, dest, isrecover)
  if (not cfg or not ksk.configs[cfg]) then
    return
  end

  local ci = prepare_broadcast(cfg)

  --
  -- Add in the syncer information and the item database.
  --
  local cf = ksk.configs[cfg]
  ci.s = {}
  for k,v in pairs(cf.admins) do
    if (cf.users[k].name ~= dest or isrecover) then
      local us = strfmt("%s:%014.0f", k, v.lastevent or 0)
      tinsert(ci.s, us)
    elseif (not isrecover) then
      --
      -- We are now in an active syncing relationship with this user.
      -- Mark it as such. We can also clear out any events we may have
      -- stored for this user, because they have them all, as of this
      -- very moment.
      --
      v.active = true
      v.sync = {}
      v.lastevent = 0
    end
  end
  local idb = {}
  ci.i = { cf.nitems, cf.items }
  ci.e = ksk.configs[cfg].lastevent or 0

  --
  -- I may be on an alt. We need to set this to the real main ID not the
  -- alt ID.
  --
  local ia,aid = ksk.IsAdmin(ksk.csdata[cfg].myuid, cfg)
  ci.d = aid

  if (not isrecover) then
    ksk.configs[cfg].syncing = true
    qf.reqsyncallbutton:SetEnabled(true)
    ksk:CSendWhisperAM(cfg, dest, "FSYNC", "ALERT", ci)
  else
    ksk:CSendWhisperAM(cfg, dest, "RCACK", "ALERT", ci)
  end
end

--
-- This function is called when the mod very first starts up. The assumption
-- (which is as close to correct as we're ever going to get) is that the
-- saved variables files are saved and flushed to disk, and therefore, the
-- data we currently have is "safe". Therefore, any events that we have already
-- processed from a given user need no longer be stored. We send this out to
-- the guild for all guild lists, and to the raid (if we are in one) for all
-- PUG lists. The recipient checks to see if they are admins in any of those
-- configs, and whether or not they have sync data stored for the sender. If
-- they do, they can safely remove any events that are <= the event ID that
-- we have. This helps keep memory usage down to the barest minimum.
--
function ksk.SyncCleanup()
  local gsend = {}
  local psend = {}

  for k,v in pairs(ksk.frdb.configs) do
    if (v.syncing) then
      local sps = ""
      local ntc = 0
      for ak,av in pairs(v.admins) do
        if (av.active) then
          local aps = strfmt("%s%014.0f", ak, av.lastevent or 0)
          sps = sps .. aps
          ntc = ntc + 1
        end
      end
      if (ntc > 0) then
        if (K.player.is_guilded) then
          tinsert(gsend, strfmt("%s:%d:%s", k, ntc, sps))
        end
        if (ksk.users) then
          tinsert(psend, strfmt("%s:%d:%s", k, ntc, sps))
        end
      end
    end
  end

  if (#gsend > 0) then
    ksk:SendGuildAM("CSYNC", "BULK", gsend)
  end

  if (#psend > 0) then
    ksk:SendAM("CSYNC", "BULK", psend)
  end
end

