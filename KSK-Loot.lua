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
local LibDeformat = LibStub:GetLibrary("LibDeformat-3.0")

if (not K or not LibDeformat) then
  return
end

local dfmt = LibDeformat.Deformat
local ksk = K:GetAddon("KKonferSK")
local L = ksk.L
local KUI = ksk.KUI
local KRP = ksk.KRP
local KLD = ksk.KLD
local KK = ksk.KK
local MakeFrame = KUI.MakeFrame

-- Local aliases for global or Lua library functions
local _G = _G
local tinsert = table.insert
local tremove = table.remove
local tconcat = table.concat
local tsort = table.sort
local tostring, tonumber = tostring, tonumber
local strfmt = string.format
local strsub = string.sub
local strlen = string.len
local strfind = string.find
local strlower = string.lower
local strmatch = string.match
local gsub = string.gsub
local pairs, ipairs = pairs, ipairs
local assert = assert
local printf = K.printf
local unpack = unpack
local GetTime = GetTime

local icolor = K.icolor
local info = ksk.info
local err = ksk.err
local white = ksk.white
local class = ksk.class
local shortclass = ksk.shortclass
local aclass = ksk.aclass
local shortaclass = ksk.shortaclass
local debug = ksk.debug

local HIST_WHEN = ksk.HIST_WHEN
local HIST_WHAT = ksk.HIST_WHAT
local HIST_WHO  = ksk.HIST_WHO
local HIST_HOW  = ksk.HIST_HOW

local HIST_EXP_XML  = 1
local HIST_EXP_JSON = 2

--
-- This file contains all of the UI handling code for the loot panel,
-- as well as all loot manipulation functions. This is a fairly complicated UI
-- with lots of moving parts so it's a good idea to understand what is going
-- on here.
--
-- We have 3 panels - loot distribution (qf.assign), the item editor
-- (qf.itemedit) and the loot history page (qf.history). Only the first two
-- are vaguely interesting. The history page is just a list with a few simple
-- buttons.
--
-- The loot page is divided into 5 main regions:
-- top left - the list of roll lists (qf.lists)
-- bottom left - the list of members of the selected list (qf.members)
-- top right - the loot selection list (qf.lootwin is the frame,
--   qf.lootwin.slist and ksk.qf.lootscroll is the actual scroll list). It also
--   contains all of the buttons for controlling loot distribution. These are
--   only displayed for the master looter. These buttons are all children of
--   qf.lootwin. .oclbids is for open / close bids. It toggles between the two.
--   .orpause either starts an open roll or pauses one in progress. And last
--   .remcancel is either the button to remove a bid item or to cancel a bid
--   or open roll.
-- middle right is the loot rules frame, the open roll timer frame and the
--   auto loot assignment confirmation frame. This is also known as the ALF
--   frame and one of those three pages is selected with select_alf().
--   qf.lootrules, qf.lootroll and qf.autoloot are the shortcuts for these
--   3 frames, only one of which can ever be visible at a time.
-- bottom right - the bidders / rollers frame. This is where the list of
--   bidders or rollers is displayed, along with buttons for both normal users
--   and the master looter to control those bidders / bids. qf.bidders is the
--   encosing frame. This has two portions - the actual scroll list of bidders
--   on the left (qf.bidscroll) and several buttons on the right. These are
--   not encosed in their own frame but are direct children of qf.bidders.
--   .mybid is the button used by users to bid on an item. When they press it
--   it will change into the retract button to retract a bid. If we are rolling
--   on an item it becomes the "main spec" roll button. .forcebid is only
--   enabled for the master looter and it forces the selected member to bid as
--   if they has pressed bid themselves. If we are rolling then this becomes
--   the "offspec roll" button, if that feature is enabled in the config UI.
--   .forceret is the "force retract" button for the ML. If we are rolling it
--   becomes the "cancel roll" button. .undo (qf.undobutton) is for the ML
--   only and does an undo of the last suicide on the list.
--
-- The ALF frame is the middle right frame and it is used for 3 different
-- things using select_alf():
-- ALF_LOOT - the loot rules frame. This is the frame shown while bids are
--   open or before open rolls are started. This contains all of the class
--   specific check boxes (for class filtering), the role filter, the guild
--   rank filter, and the strict armor / class checkboxes. The containing
--   frame is qf.lootrules and has the following children:
--   .warrior, .paladin, .druid etc for all 12 classes
--   .role - the drop down for the user role
--   .rank - the dropdown for the guild rank
--   .nextrank - the button for moving to the next lower rank
--   .strictarmor - checkbox for strict armor filtering
--   .strictrole - checkbox for string role filtering
-- ALF_CONFIRM - the auto-loot confirmation frame. This is displayed when an
--   item is about to be assigned to a user, for whatever reason. It is always
--   displayed before the mod assigns loot (except under very special cases
--   too complex to describe here). This frame has both UI elements and loot
--   related variables (non UI widgets) associated with it. Its base is
--   qf.autoloot and the widget children are:
--   .item (and qf.autoassign_item) - a text label designed to hold the name of
--     the item being assigned. This is almost always an item link.
--   .str (and qf.autoassign_msg) - a text string that contains any assignment
--     message instructions.
--   .ok - a button that will perform the assignment
--   .cancel - a button that closes the ALF window but doesn't assign the item.
--   Data items set on qf.autoloot and used by the Ok and cancel button
--   handlers are:
--   .slot - the slot number on the corpse of the item to be assigned
--   .bosslootidx - the boss loot index number of the item being awarded.
--   .uid - the KSK internal user ID of the user to receive the item
--   .name - full player name
--   .party - the raid party the winner is in
--   .announce - a boolean true if we are to announce the asignment
--   .suicide - the list on which the user will be suicided (if any)
--   .ilink - the item being awarded
--   .autodel - true if the item should be removed from the items database.
--     This is set when there is a once-off assignment of an item setup in the
--     items database, for a specific user, and this is that assignment. Since
--     the assignment has now been done it can be removed from the database.
--   .denched - true if the item is being assigned to a dencher for mats.
--   .rolled - true if the item was won by a roll not a bid.
--   .leaveloot - only used by the cancel button and indicates that the loot
--     should be left in the loot list. The default is to remove it.
--

local lootlistid = nil
local members = nil
local memberid = nil
local biditem = nil
local selitemid = nil
local iinfo = {}

-- The index into ksk.bossloot of the currently selected loot item.
local selectedloot = nil

-- Data table of the currently selected loot item.
--  idx - same as selectedloot above.
--  itemid - the item ID
--  filter - the class filter
--  role - the role filter
--  list - the desired roll list
--  rank - the rank filter
--  loot - ksk.bossloot[selectedloot]
--     slot - the loot slot index for Blizzard API functions
--     itemid - the item ID
--     ilink - the item link text
--     quant - the number of this item on the corpse
--     boe - true if the item is BoE
--     strict - the strict class filter
--     relaxed - the relaxed class filter
local lootitem = nil

local lootroll = nil

-- Table of people who have bid on the current item.
local bidders = nil
-- Index into bidders of the currently selected bidder and that user's uid.
local selectedbidder = nil
local selectedbiduid = nil

local qf = {}
local exphistdlg = nil
local undodlg = nil

--
-- This can have 4 possible values:
-- nil - No rolling taking place
-- 1   - roll actively underway.
-- 2   - active roll paused.
-- 3   - roll paused and window closed.
local rolling = nil

--
-- The top right division of the loot assignment page serves 3 main purposes:
-- loot selection, assignment confirmation and open rolls. Only one of these
-- can be active at a time as they all overlay each other. This function
-- ensures that only one of these three frames is active.
--
local ALF_LOOT    = 1
local ALF_CONFIRM = 2
local ALF_ROLL    = 3

local function select_alf(which)
  if (which == ALF_CONFIRM) then
    qf.lootrules:Hide()
    qf.lootroll:Hide()
    qf.autoloot:Show()
  elseif (which == ALF_ROLL) then
    qf.lootrules:Hide()
    qf.autoloot:Hide()
    qf.lootroll:Show()
  else
    qf.autoloot:Hide()
    qf.lootroll:Hide()
    qf.lootrules:Show()
  end
end

local function hide_popup()
  if (ksk.popupwindow) then
    ksk.popupwindow:Hide()
    ksk.popupwindow = nil
  end
end

--
-- We have a few places where we have very similar widgets, such as the
-- class filtering stuff. All of the containing widgets have sub-widgets of
-- the same name and all of them have the same requirement of needing to
-- either be enabled/disabled or have their value set according to a filter
-- string. These three functions are helpers for those cases and do the busy
-- work in this one place rather than repeating it in several places.
--
local function classes_setenabled(tbl, onoff)
  local onoff = onoff or false

  for k, v in pairs(K.IndexClass) do
    if (v.w and tbl[v.w]) then
      tbl[v.w]:SetEnabled(onoff)
    end
  end
end

local function classes_setchecked(tbl, onoff)
  local onoff = onoff or false

  for k, v in pairs(K.IndexClass) do
    if (v.w and tbl[v.w]) then
      tbl[v.w]:SetChecked(onoff)
    end
  end
end

local function classes_cfilter(tbl, cfilter)
  for k, v in pairs(K.IndexClass) do
    if (v.w and tbl[v.w]) then
      tbl[v.w]:SetChecked(cfilter[k])
    end
  end
end

--
-- Check to see if any of the current raiders are not on the currently
-- selected list.
--
local function check_missing_members(self)
  if (not self.cfg.settings.ann_missing or not self.users or not lootlistid) then
    return
  end

  if (not self.csdata[self.currentid].warns.lists[lootlistid]) then
    self.csdata[self.currentid].warns.lists[lootlistid] = {}
  end

  local mwarn = self.csdata[self.currentid].warns.lists[lootlistid]
  local missing = {}

  for k,v in pairs(KRP.players) do
    local uid = v["ksk_uid"]
    if (not uid) then
      if (not mwarn[v.name]) then
        mwarn[v.name] = true
        tinsert(missing, shortaclass(v))
      end
    else
      if (not mwarn[v.name]) then
        if (not self:UserInList(uid, lootlistid)) then
          mwarn[v.name] = true
          tinsert(missing, shortaclass(self.cfg.users[uid]))
        end
      end
    end
  end

  if (#missing == 0) then
    return
  end

  local lootlist = self.cfg.lists[lootlistid]
  info(L["users not on the %q list: %s"], lootlist.name, tconcat(missing, ", "))
end

local function changed(res, user)
  if (not user) then
    return
  end

  local res = res or false

  if (not selitemid) then
    res = true
  end

  qf.itemupdbtn:SetEnabled(not res)
end

local function lootrules_setenabled(self, val)
  if (not qf.lootrules) then
    return
  end

  local val = val or false
  local onoff = self:AmIML() and val

  classes_setenabled(qf.lootrules, onoff)
  qf.lootrules.role:SetEnabled(onoff)
  qf.lootrules.rank:SetEnabled(onoff)
  qf.lootrules.nextrank:SetEnabled(onoff)
  qf.lootrules.strictarmour:SetEnabled(onoff)
  qf.lootrules.strictrole:SetEnabled(onoff)

  if (self.cfg.cfgtype == KK.CFGTYPE_PUG) then
    qf.lootrules.rank:SetEnabled(false)
    qf.lootrules.nextrank:SetEnabled(false)
  end
end

local function lootbid_setenabled(val)
  if (not qf.lootwin or not qf.bidders) then
    return
  end

  local val = val or false
  local onoff = ksk:AmIML() and val

  qf.lootwin.oclbids:SetEnabled(onoff)
  qf.lootwin.orpause:SetEnabled(onoff)
  qf.lootwin.remcancel:SetEnabled(onoff)
  qf.bidders.mybid:SetEnabled(onoff)
end

local function verify_user_class(user, class, what)
  local w = K.IndexClass[class].w

  if (not qf.lootrules[w]:GetChecked()) then
    local clist = {}
    for k,v in pairs(K.IndexClass) do
      if (v.w) then
        if (qf.lootrules[v.w]:GetChecked()) then
          tinsert(clist, v.c)
        end
      end
    end
    ksk:SendWhisper(strfmt(L["%s: you do not meet the current class restrictions (%s) - %s ignored."], L["MODTITLE"], tconcat(clist, ", "), what), user)
    return false
  end
  return true
end

--
-- Setup the auto-assign loot confirmation frame. The sole parameter is the
-- name of the person who either won the item or is going to have the item
-- assigned to them (for DE or guild bank).
--
local function set_autoloot_win(name)
  if (not lootitem or not selectedloot or not name or name == "") then
    return
  end

  local uid = KRP.players[name]["ksk_uid"]

  qf.autoassign_item:SetText(lootitem.loot.ilink)
  qf.autoloot.slot = lootitem.loot.slot or nil
  qf.autoloot.bosslootidx = selectedloot
  qf.autoloot.ilink = lootitem.loot.ilink
  qf.autoloot.uid = uid
  qf.autoloot.name = name
  qf.autoloot.party = KRP.players[name].subgroup
  qf.autoloot.announce = false
  qf.autoloot.leaveloot = false
  qf.autoloot.denched = false
  qf.autoloot.rolled = 0
  qf.autoloot.autodel = false
  qf.autoloot.suicide = nil
  lootbid_setenabled(false)
  select_alf(ALF_CONFIRM)
end

function ksk:PauseResumeRoll(pause, timeout)
  if (not lootroll) then
    return
  end

  if (pause) then
    if (rolling == 1) then
      rolling = 2
    end
  else
    if (rolling == 2) then
      rolling = 1
      lootroll.endtime = GetTime() + timeout
    end
  end
end

--
-- Start an open roll or pause one that is currently in progress. Called when
-- the Open Roll / Pause button is pressed.
--
local function open_roll_or_pause(self)
  local tr = qf.lootwin

  if (rolling) then
    if (rolling == 1) then
      local rem = floor(lootroll.endtime - GetTime()) + 1
      tr.orpause:SetText(L["Resume"])
      rolling = 2
      if (rem < 6) then
        rem = self.cfg.settings.roll_extend + 1
      end
      lootroll.resume = rem
      self:SendAM("PROLL", "ALERT", true, 0)
    else
      lootroll.endtime = GetTime() + lootroll.resume
      lootroll.lastwarn = nil
      self:SendAM("PROLL", "ALERT", false, lootroll.resume)
      lootroll.resume = nil
      tr.orpause:SetText(L["Pause"])
      rolling = 1
    end
  else
    local sroll = self.cfg.settings.suicide_rolls
    if (IsShiftKeyDown()) then
      sroll = not sroll
    end

    if (sroll) then
      local lootlist = self.cfg.lists[lootlistid]

      self:SendWarning(strfmt(L["Suicide Roll (on list %q) for %s within %d seconds."],
                       lootlist.name, lootitem.loot.ilink, self.cfg.settings.roll_timeout))
    else
      self:SendWarning(strfmt(L["Roll for %s within %d seconds."],
                       lootitem.loot.ilink, self.cfg.settings.roll_timeout))
    end

    if (self.cfg.settings.ann_roll_usage) then
      if (self.cfg.settings.offspec_rolls) then
        self:SendText(strfmt(L["%s: type '/roll' for main spec, '/roll 101-200' for off-spec or '/roll 1-1' to cancel a roll."], L["MODABBREV"]))
      else
        self:SendText(strfmt(L["%s: type '/roll' for main spec or '/roll 1-1' to cancel a roll."], L["MODABBREV"]))
      end
    end

    qf.lootroll.StartRoll(sroll)
  end
end

local function boe_to_ml_or_de(self, isroll)
  self:ResetBidders(true)

  if (not lootitem or not KLD.items) then
    return false
  end

  local loot = lootitem.loot
  local slot = loot.slot
  local klid = KLD.items[slot]
  local ilink = loot.ilink

  if (loot.boe and self.cfg.settings.boe_to_ml) then
    self:AddLootHistory(nil, K.time(), ilink, self.csdata[self.currentid].myuid, "B", 0)
    KLD.GiveMasterLoot(slot, KRP.master_looter)
    self:RemoveItemByIdx(selectedloot, false)
    select_alf(ALF_LOOT)
    return true
  else
    if (not isroll and self.cfg.settings.try_roll) then
      open_roll_or_pause(self)
      return true
    end

    if (isroll) then
      self:EndOpenRoll(true)
    end

    if (self.cfg.settings.disenchant) then
      local rdenchers = #self.denchers

      if (rdenchers > 0) then
        --
        -- Must see if the denchers are eligible for loot. They may not
        -- have been present for the boss kill.
        --
        for de = 1, rdenchers do
          local tname = self.denchers[de]
          local uid = KRP.players[tname]["ksk_uid"]
          local vtarget = false
          local rs = ""
          if (slot == 0 or not klid.candidates[tname]) then
            rs = "\n\n" .. white(L["Note: player will need to pick item up manually."])
            if (UnitInRange(tname) == 1) then
              vtarget = true
            end
          else
            if (klid.candidates[tname]) then
              vtarget = true
            end
          end
          if (vtarget) then
            local cname = shortaclass(self.cfg.users[uid])
            if (isroll) then
              qf.autoassign_msg:SetText(strfmt(L["AUTODENCHNR"], cname, cname) .. rs)
            else
              qf.autoassign_msg:SetText(strfmt(L["AUTODENCH"], cname, cname) .. rs)
            end
            set_autoloot_win(tname)
            qf.autoloot.denched = true
            qf.autoloot.leaveloot = not isroll
            return true
          end
        end
      end
    end
  end
  return false
end

--
-- This is called when a user presses the 'Ok' button in the autoloot panel
-- in the bidding window. This window is displayed when an item has been
-- won by a bid, a roll, or is being auto-assigned to a disenchanter if no
-- bids or rolls were received.
--
local function auto_loot_ok(self)
  local li = qf.autoloot
  local lh = li.listid
  local uname = li.name
  local pos = ""
  local ipos = 0

  if (li.suicide) then
    local il, lp = self:UserInList(li.uid, li.suicide)
    if (il) then
      pos = strfmt("[%d]", lp)
      ipos = lp
    end
  end

  if (li.slot) then
    KLD.GiveMasterLoot(li.slot, li.name)
  end

  if (li.announce) then
    if (self.cfg.settings.ann_winners_raid) then
      self:SendText(strfmt(L["%s: %s%s (group %d) won %s. Grats!"], L["MODABBREV"], uname, pos, li.party, li.ilink))
    end

    if (self.cfg.settings.ann_winners_guild) then
      self:SendGuildText(strfmt(L["%s: %s%s won %s. Grats!"], L["MODABBREV"], uname, pos, li.ilink))
    end
  end

  if (li.suicide) then
    lh = li.suicide
    local sulist = self:CreateRaidList(li.suicide)
    self:SuicideUser(li.suicide, sulist, li.uid, self.currentid, li.ilink, true)
    li.suicide = nil
  end

  if (li.autodel) then
    li.autodel = nil
    self:DeleteItem(lootitem.loot.itemid)
  end

  if (li.uid) then
    if (li.denched) then
      lh = "D"
    elseif (li.rolled and li.rolled == 1) then
      lh = "M"
    elseif (li.rolled and li.rolled == 101) then
      lh = "O"
    elseif (not lh) then
      lh = "A"
    end
    self:AddLootHistory(nil, K.time(), li.ilink, li.uid, lh, ipos)
  end

  self:RemoveItemByIdx(li.bosslootidx, false)
  self:ResetBidders(true)
  select_alf(ALF_LOOT)
end

--
-- Called when a user presses 'Cancel' in the autoloot panel.
--
local function auto_loot_cancel(self)
  local li = qf.autoloot

  if (not li.announce and not li.leaveloot) then
    if (li.uid) then
      local lh = li.listid
      local ipos = 0
      if (li.suicide) then
        local il, lp = self:UserInList(li.uid, li.suicide)
        if (il) then
          ipos = lp
        end
      end

      if (li.denched) then
        lh = "D"
      elseif (li.rolled and li.rolled == 1) then
        lh = "M"
      elseif (li.rolled and li.rolled == 101) then
        lh = "O"
      elseif (not lh) then
        lh = "A"
      end
      self:AddLootHistory(nil, K.time(), li.ilink, li.uid, lh, ipos)
    end
    self:RemoveItemByIdx(li.bosslootidx, false)
    self:ResetBidders(true)
  end
  select_alf (ALF_LOOT)
end

--
-- OnUpdate script handler for the open roll timer bar. This needs to examine
-- the remaining time, move the bar and set its color accordingly (it changes
-- from green to red gradualy as the timeout gets closer and closer) and
-- deals with the timer expiring. There are actually two versions of this.
-- One is for the master looter and the other for everyone else. The former
-- does all kinds of checking and processing based on the timeout and the
-- latter simply updates the spark.
--
local function rolltimer_onupdate_user()
  local rlf = qf.lootroll

  if (not lootroll) then
    rlf.timerbar:SetScript("OnUpdate", nil)
    return
  end

  if (rolling >= 2) then
    return
  end

  local now = GetTime()
  local remt = lootroll.endtime - now
  local pct = remt / lootroll.timeout
  rlf.timerbar:SetStatusBarColor(1-pct, pct, 0)
  rlf.timerbar:SetValue(pct)
  rlf.timertext:SetText(strfmt(L["Roll closing in %s"], ("%.1f)"):format(remt)))
  rlf.timerspark:ClearAllPoints()
  rlf.timerspark:SetPoint("CENTER", rlf.timerbar, "LEFT", pct * 200, 0)
end

local function rolltimer_onupdate_ml(self)
  local rlf = qf.lootroll

  if (not lootroll) then
    rlf.timerbar:SetScript("OnUpdate", nil)
    return
  end

  if (rolling >= 2) then
    return
  end

  local now = GetTime()
  if (now > lootroll.endtime) then
    rlf.timerbar:SetScript("OnUpdate", nil)
    rolling = nil
    local topmain = {}
    local topalts = {}
    local nummain = 0
    local numalts = 0

    -- Stop the end user's timer spark and reset their UI.
    if (self:AmIML()) then
      self:SendAM("EROLL", "ALERT")
    end

    lootroll.sorted = lootroll.sorted or {}

    for i = 1, #lootroll.sorted do
      local nm = lootroll.sorted[i]
      local ru = lootroll.rollers[nm]
      if (ru.minr == 1 and nummain < 5) then
        tinsert(topmain, shortaclass(nm, ru.class) .. " [" .. ru.roll .. "]")
        nummain = nummain + 1
      elseif (ru.minr == 101 and numalts < 5) then
        tinsert(topalts, shortaclass(nm, ru.class) .. " [" .. ru.roll .. "]")
        numalts = numalts + 1
      end
    end

    if (nummain > 0 ) then
      info(L["top main spec rollers: %s"], tconcat(topmain, ", "))
    end

    if (numalts > 0 ) then
      info(L["top off-spec rollers: %s"], tconcat(topalts, ", "))
    end

    topmain = nil
    topalts = nil

    local winner = lootroll.sorted[1]
    if (winner) then
      local ilink = lootitem.loot.ilink
      local nwinners = 1
      local winners = {}
      local winnames = {}
      winners[winner] = lootroll.rollers[winner].class
      tinsert(winnames, winner)
      local winroll = lootroll.rollers[winner].roll
      for i = 2, #lootroll.sorted do
        local nm = lootroll.sorted[i]
        local ru = lootroll.rollers[nm]
        if (ru.roll == winroll) then
          winners[nm] = ru.class
          tinsert(winnames, nm)
          nwinners = nwinners + 1
        end
      end

      if (nwinners > 1) then
        -- Deal with ties here.
        if (self.cfg.settings.ann_roll_ties) then
          self:SendText(strfmt(L["%s: the following users tied with %d: %s. Roll again."], L["MODABBREV"], winroll, tconcat(winnames, ", ")))
        end
        winnames = nil
        lootroll.rollers = {}
        lootroll.sorted = nil
        lootroll.restrict = winners
        for i = 1,5 do
          rlf["pos"..i]:SetText("")
          rlf["rem"..i]:SetEnabled(false)
        end
        lootroll.endtime = GetTime() + self.cfg.settings.roll_timeout + 1
        lootroll.lastwarn = nil
        rolling = 1
        rlf.timerbar:SetScript("OnUpdate", function() rolltimer_onupdate_ml(self) end)
        self:SendAM("RROLL", "ALERT", ilink, timeout, winners)
        return
      end

      local winclass = lootroll.rollers[winner].class
      local winbase = lootroll.rollers[winner].minr
      local party = KRP.players[winner].subgroup
      local uid = KRP.players[winner]["ksk_uid"] or winner
      local missing = KRP.players[winner]["ksk_missing"]
      local suicide = nil
      local gpos = ""

      if (lootroll.suicide and not missing) then
        local ipos = 0
        local il, lp = self:UserInList(uid, suicide)
        if (il) then
          gpos = strfmt("[%d]", lp)
          ipos = lp
        end
        suicide = lootlistid
        local sulist = self:CreateRaidList(lootlistid)
        self:SuicideUser(suicide, sulist, uid, self.currentid, ilink, true)
        self:AddLootHistory(nil, K.time(), ilink, uid, suicide, ipos)
      end

      local ts = strfmt(L["%s: %s%s (group %d) won %s. Grats!"], L["MODABBREV"], winner, gpos, party, ilink)
      if (self.cfg.settings.ann_winners_raid) then
        self:SendText(ts)
      end
      printf(icolor, "%s", ts)
      if (self.cfg.settings.ann_winners_guild) then
        self:SendGuildText(strfmt(L["%s: %s%s won %s. Grats!"], L["MODABBREV"], winner, gpos, ilink))
      end

      if (lootitem.loot.slot ~= 0 and self.cfg.settings.auto_loot) then
        local cname = shortaclass(winner, winclass)
        qf.autoassign_msg:SetText(strfmt(L["AUTOLOOT"], cname, cname, cname))
        set_autoloot_win(winner)
        qf.autoloot.rolled = winbase
        return
      else
        local lh = "M"
        if (winbase == 101) then
          lh = "O"
        end
        if (not suicide) then
          self:AddLootHistory(nil, K.time(), ilink, uid, lh, 0)
        end
        self:RemoveItemByIdx(selectedloot, false)
        self:ResetBidders(false)
      end
    else -- No winner because no-one rolled
      info(strfmt(L["no-one rolled for %s."], lootitem.loot.ilink))
      if (boe_to_ml_or_de(self, true)) then
        return
      end
      --
      -- No-one rolled and they didn't assign it to a dencher. We don't
      -- really know what they are going to do with it, so we can not
      -- record a loot history event. Yes it would be possible to trap
      -- the loot assignment message in case they manually assign the item,
      -- but that is highly unreliable as it wont be displayed if the
      -- recipient is out of range. No-one ever said this was a perfect
      -- system.
      --
      self:EndOpenRoll()
      self:RemoveItemByIdx(selectedloot, false)
    end

    select_alf(ALF_LOOT)
    return
  end

  local remt = lootroll.endtime - now
  local warnt = floor(remt)
  local pct = remt / (self.cfg.settings.roll_timeout + 1)
  rlf.timerbar:SetStatusBarColor(1-pct, pct, 0)
  rlf.timerbar:SetValue(pct)
  rlf.timertext:SetText(strfmt(L["Roll closing in %s"], ("%.1f)"):format(remt)))
  rlf.timerspark:ClearAllPoints()
  rlf.timerspark:SetPoint("CENTER", rlf.timerbar, "LEFT", pct * 200, 0)

  if (warnt < 5) then
    if (not lootroll.lastwarn or warnt ~= lootroll.lastwarn) then
      lootroll.lastwarn = warnt
      if (self.cfg.settings.ann_countdown) then
        self:SendText(strfmt(L["%s: roll closing in: %d"], L["MODABBREV"], warnt+1))
      end
    end
  end
end

--
-- This is called when a valid player has typed /roll. 
--
local function player_rolled(self, player, roll, minr, maxr)
  if (not rolling) then
    return
  end

  local rp

  if (lootroll.rollers[player]) then
    --
    -- If they had rolled before but were using a different min and max,
    -- recheck things, as they may be correcting a main spec versus offspec
    -- roll. Seems like /roll 101-200 is really hard for people to do right
    -- the first time!
    --
    rp = lootroll.rollers[player]
    if ((rp.minr == minr) and (rp.maxr == maxr)) then
      self:SendWhisper(strfmt(L["%s: you already rolled %d. New roll ignored."], L["MODTITLE"], lootroll.rollers[player].roll), player)
      return
    end

    --
    -- We dont actually accept the new roll value. Rather, we either add
    -- or subtract 100 from the original roll, so that the user doesn't
    -- end up with two chances to roll and improve their score.
    --
    if (rp.minr == 1 and minr == 101) then
      rp.roll = rp.roll + 100
    elseif (rp.minr == 101 and minr == 1) then
      rp.roll = rp.roll - 100
    elseif (rp.maxr == 1) then
      if (rp.roll >= 101) then
        rp.roll = rp.roll - 100
      end
    elseif (minr == 1 and maxr == 1) then
      -- Do nothing
    else
      return
    end
    rp.minr = minr
    rp.maxr = maxr
  else
    if (minr == 1 and maxr == 1) then
      return
    end
    local class
    if (lootroll.restrict) then
      if (not lootroll.restrict[player]) then
        self:SendWhisper(strfmt(L["%s: sorry you are not allowed to roll right now."], L["MODTITLE"]), player)
        return
      end
      class = lootroll.restrict[player]
      if (minr == 101) then
        minr = 1
        maxr = 100
        roll = roll - 100
      end
    else
      --
      -- Check to see if they are eligible for loot. We may have a case here
      -- where no-one is marked as a master loot candidate because the
      -- raid leader had loot set incorrectly, and subsequently changed it
      -- to master looting. In this case we don't want to block the user
      -- from rolling.
      --
      local loot = lootitem.loot
      local slot = loot.slot
      if (slot > 0) then
        -- Slot 0 is for manually added items
        local klid = KLD.items[slot]
        if (not klid.candidates[player]) then
          self:SendWhisper(strfmt(L["%s: you are not eligible to receive loot - %s ignored."], L["MODTITLE"], L["roll"]), player)
          return
        end
      end

      class = KRP.players[player].class
      assert(class)

      --
      -- Verify that they meet the class requirements
      --
      if (not verify_user_class(player, class, L["roll"])) then
        return
      end
    end

    lootroll.rollers[player] = {}
    rp = lootroll.rollers[player]
    rp.roll = roll
    rp.minr = minr
    rp.maxr = maxr
    rp.class = class
  end

  --
  -- Create the sorted list of rollers
  --
  lootroll.sorted = {}
  for k,v in pairs(lootroll.rollers) do
    if (v.maxr ~= 1) then
      tinsert(lootroll.sorted, k)
    end
  end
  tsort(lootroll.sorted, function(a,b)
    if (lootroll.rollers[a].minr > lootroll.rollers[b].minr) then
      return false
    elseif (lootroll.rollers[a].minr < lootroll.rollers[b].minr) then
      return true
    elseif (lootroll.rollers[a].roll > lootroll.rollers[b].roll) then
      return true
    end
    return false
  end)

  --
  -- Display the top 5 in the dialog
  --
  local rlf = qf.lootroll
  for i = 1,5 do
    rlf["pos"..i]:SetText("")
    rlf["rem"..i]:SetEnabled(false)
  end

  local toprolls = {}
  for i = 1,5 do
    local nm = lootroll.sorted[i]
    if (nm) then
      local ru = lootroll.rollers[nm]
      local ts = shortaclass(nm, ru.class) .. "[" .. tostring(ru.roll) .. "]"
      rlf["pos"..i]:SetText(ts)
      rlf["rem"..i]:SetEnabled(true)
      tinsert(toprolls, ts)
    end
  end
  self:SendAM("TROLL", "ALERT", toprolls)

  --
  -- If this roll arrived within 5 seconds of the timeout reset the timeout
  -- back up to 5 seconds.
  --
  local now = GetTime()
  local rem = floor(lootroll.endtime - now) + 1
  if (rem < 6) then
    lootroll.endtime = now + self.cfg.settings.roll_extend + 1
    self:SendAM("XROLL", "ALERT", self.cfg.settings.roll_extend)
  end
end

local function rlf_onevent(self, this, evt, arg1, ...)
  if (evt == "CHAT_MSG_SYSTEM") then
    local plr, roll, minr, maxr = dfmt(arg1, RANDOM_ROLL_RESULT)
    local player = K.CanonicalName(plr, nil)

    if (player and not KRP.players[player]) then
      player = nil
    end

    if (player and roll and minr and maxr) then
      if ((minr == 1 and maxr == 100) or
        (self.cfg.settings.offspec_rolls and (minr == 101 and maxr == 200)) or
        (minr == 1 and maxr == 1)) then
        player_rolled(self, player, roll, minr, maxr)
      else
        if (self.cfg.settings.offspec_rolls) then
          self:SendWhisper(strfmt(L["%s: invalid roll. Use '/roll' for main spec, '/roll 101-200' for off-spec or '/roll 1-1' to cancel a roll."], L["MODTITLE"]), player)
        else
          self:SendWhisper(strfmt(L["%s: invalid roll. Use '/roll' for main spec or '/roll 1-1' to cancel a roll."], L["MODTITLE"]), player)
        end
        return
      end
    end
  end
end

--
-- Either remove an item or cancel a bid / roll.
--
local function remove_or_cancel(self)
  local tr = qf.lootwin

  if (rolling) then
    if (self.cfg.settings.ann_cancel) then
      self:SendWarning(strfmt(L["%s: %s cancelled!"], L["MODABBREV"], L["roll"]))
    end
    self:EndOpenRoll()
    return
  end

  if (biditem) then
    if (self.cfg.settings.ann_cancel) then
      self:SendWarning(strfmt(L["%s: %s cancelled!"], L["MODABBREV"], L["bid"]))
    end
    self:ResetBidders(false)
    lootbid_setenabled(true)
    qf.bidders.mybid:SetEnabled(false)
    self:SendAM("BICAN", "ALERT", biditem)
    return
  end

  if (selectedloot) then
    self:RemoveItemByIdx(selectedloot, false)
  end
end

local function rlist_newitem(objp, num)
  local rf = KUI.NewItemHelper(objp, num, "KSKLListButton", 155, 16, nil, nil, nil, nil)

  rf:SetScript("OnClick", function(this)
    if (not ksk:AmIML()) then
      return
    end

    local idx = this:GetID()
    --
    -- Be careful to only reset bidders when we have actually switched
    -- to a different list by clicking on it.
    --
    if (not lootlistid or lootlistid ~= ksk.sortedlists[idx].id) then
      -- The following will set lootlistid and lootlist and populate the
      -- members scroll list with the list members.
      this:GetParent():GetParent():SetSelected(idx, true, true)
      ksk:ResetBidList()
      ksk:SendAM("LLSEL", "ALERT", lootlistid, true)
      if ((biditem or (lootroll and lootroll.suicide)) and ksk.cfg.settings.ann_bidchanges) then
        local lootlist = ksk.cfg.lists[lootlistid]
        ksk:SendWarning(strfmt(L["Bid list changed to %q for %s."], lootlist.name, lootitem.loot.ilink))
      end
      check_missing_members(ksk)
    end
  end)
  return rf
end

function ksk:RestrictedRoll(ilink, timeout, winners)
  if (not lootroll) then
    return
  end

  for i = 1,5 do
    rlf["pos"..i]:SetText("")
  end

  if (not winners[K.player.name]) then
    qf.bidders.mybid:SetEnabled(false)
    qf.bidders.forcebid:SetEnabled(false)
    qf.bidders.forceret:SetEnabled(false)
  end

  select_alf(ALF_ROLL)
  lootroll.endtime = GetTime() + timeout + 1
  rolling = 1
  qf.lootroll.timerbar:SetScript("OnUpdate", rolltimer_onupdate_user)
end

function ksk:ExtendRoll(timeout)
  if (lootroll and rolling == 1) then
    lootroll.endtime = GetTime() + timeout + 1
  end
end

function ksk:TopRollers(trolls)
  local rlf = qf.lootroll

  for i = 1,5 do
    rlf["pos"..i]:SetText("")
  end

  if (trolls) then
    for k, v in ipairs(trolls) do
      rlf["pos"..k]:SetText(v)
    end
  end
end

local function rlist_setitem(objp, idx, slot, btn)
  btn:SetText(ksk.cfg.lists[ksk.sortedlists[idx].id].name)
  btn:SetID(idx)
  btn:Show()
end

local function rlist_selectitem(objp, idx, slot, btn, onoff)
  local onoff = onoff or false

  hide_popup()

  if (onoff) then
    lootlistid = ksk.sortedlists[idx].id
    local lootlist = ksk.cfg.lists[lootlistid]

    --
    -- If this list has a default rank, set it now, unless its "None".
    -- Otherwise, set it to the global one if its not None.
    --
    if (lootlist.def_rank) then
      qf.lootrules.rank:SetValue(lootlist.def_rank)
    else
      if (ksk.cfg.settings.def_rank) then
        qf.lootrules.rank:SetValue(ksk.cfg.settings.def_rank)
      else
        qf.lootrules.rank:SetValue(0)
      end
    end

    --
    -- Set the strict enforcing options
    --
    qf.lootrules.strictarmour:SetChecked(lootlist.strictcfilter)
    qf.lootrules.strictrole:SetChecked(lootlist.strictrfilter)
  else
    lootlistid = nil
  end

  -- Updates members, memberid
  ksk:RefreshLootMembers()
end

local function mlist_newitem(objp, num)
  local bname = "KSKLMListButton" .. tostring(num)
  local rf = MakeFrame("Button", bname, objp.content)
  local nfn = "GameFontNormalSmallLeft"
  local htn = "Interface/QuestFrame/UI-QuestTitleHighlight"

  rf:SetWidth(155)
  rf:SetHeight(16)
  rf:SetHighlightTexture(htn, "ADD")

  local text = rf:CreateFontString(nil, "ARTWORK", nfn)
  text:ClearAllPoints()
  text:SetPoint("TOPLEFT", rf, "TOPLEFT", 8, -2)
  text:SetPoint("BOTTOMRIGHT", rf, "BOTTOMRIGHT", -48, 2)
  text:SetJustifyH("LEFT")
  text:SetJustifyV("TOP")
  rf.text = text

  local si = rf:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  si:ClearAllPoints()
  si:SetPoint("TOPLEFT", text, "TOPRIGHT", 0, 0)
  si:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", 40, 0)
  si:SetJustifyH("RIGHT")
  si:SetJustifyV("TOP")
  rf.indicators = si

  rf.SetText = function(self, txt, ench, frozen, res)
    self.text:SetText(txt)
    local st = ""
    local et = ""
    local is = ""
    if (ench) then
      is = L["USER_ENCHANTER"]
    end
    if (frozen) then
      is = is .. L["USER_FROZEN"]
    end
    if (res) then
      is = is .. L["USER_RESERVED"]
    end
    if (is ~= "") then
      st = "["
      et = "]"
    end
    self.indicators:SetText(st .. is .. et)
  end

  rf:SetScript("OnClick", function(this)
    qf.membersearch:ClearFocus()
    if (not ksk:AmIML()) then
      return
    end
    qf.membersearch:SetText("")
    local idx = this:GetID()
    this:GetParent():GetParent():SetSelected(idx, true, true)
  end)

  return rf
end

local function mlist_setitem(objp, idx, slot, btn)
  local uid = members[idx].id
  local ench, frozen, res
  local uc = uid
  local at = strfmt("%d: ", members[idx].idx)
  local bm = true

  --
  -- If we are tethered, we only care about the main character being frozen
  -- or reserved, but we do care about any of the alts being enchanters.
  -- Also, if we are tethered, then members points to a different array that
  -- has different info we care about.
  --
  local lootlist = ksk.cfg.lists[lootlistid]
  if (lootlist.tethered and lootlist.altdisp and not ksk.cfg.settings.hide_absent) then
    if (members[idx].isalt) then
      uc = members[idx].main
      at = "    - "
      bm = false
    end
  end

  ench = ksk:UserIsEnchanter(uid)
  frozen = ksk:UserIsFrozen(uc) and bm
  res = ksk:UserIsReserved(uc) and bm

  if (uid and ksk.cfg.users[uid]) then
    btn:SetText(at .. shortclass(ksk.cfg.users[uid]), ench, frozen, res)
  else
    btn:SetText("", ench, frozen, res)
  end
  btn:SetID(idx)
  btn:Show()
end

local function mlist_selectitem(objp, idx, slot, btn, onoff)
  local onoff = onoff or false

  if (onoff) then
    local mid = members[idx].id
    memberid = mid
  else
    memberid = nil
  end

  qf.bidders.forcebid:SetEnabled(ksk:AmIML() and onoff and biditem ~= nil)
end

local function lloot_on_click(self, this)
  local idx = this:GetID()

  if (IsModifiedClick("CHATLINK")) then
    ChatEdit_InsertLink(self.bossloot[idx].ilink)
    return
  end

  if (not self:AmIML()) then
    return
  end

  --
  -- If we have a current bid or roll in progress, ignore this attempt to
  -- change the item. If they want to cancel a bid or roll they can just
  -- press Cancel and that will take care of things.
  --
  if (rolling or biditem) then
    return
  end

  --
  -- Ok we have a new loot item. Process it. Note that this could be
  -- the same item that was previously selected. We want to process
  -- it all over again in case they had messed with ranks, armor
  -- class filters etc. By clicking on it we make the assumption the
  -- user wanted to reset everything.
  --
  local loot = self.bossloot[idx]
  local itemid = loot.itemid
  local slot = loot.slot
  local cf = nil
  local role = 0
  local slist = nil
  local rank = 0
  local strict = nil

  if (self.iitems[itemid]) then
    cf = self.iitems[itemid].cfilter
  end

  local ii = self.cfg.items[itemid]
  if (ii) then
    --
    -- Ignore has already been taken care of, as items that are being
    -- ignored will not make it into the bossloot list in the first
    -- place. What we need to check for here are class loot filters,
    -- role filters, and specific user assignments. We will always
    -- send out a selection event with the filters, but we will deal
    -- with specific user assignments right here and now, giving the
    -- ML the option of actually assigning the loot if the user is
    -- in the raid and eligible to receive the loot.
    --
    cf = ii.cfilter or cf
    role = ii.role or role
    slist = ii.list or slist
    rank = ii.rank or rank
  end

  if (not slist and self.cfg.settings.def_list ~= "0") then
    slist = self.cfg.settings.def_list
  end

  if (slist ~= nil) then
    if (not rank and self.cfg.lists[slist].def_rank) then
      rank = self.cfg.lists[slist].def_rank
    end
  else
    if (lootlistid) then
      slist = lootlistid
      if (not rank) then
        rank = self.cfg.lists[lootlistid].def_rank
      end
    end
  end

  if (not rank and self.cfg.settings.def_rank) then
    rank = self.cfg.settings.def_rank
  end

  if (not cf) then
    if (qf.lootrules.strictarmour:GetChecked()) then
      cf = loot.strict
    else
      cf = loot.relaxed
    end
  end

  --
  -- We start out by enabling the loot control buttons here. However,
  -- SelectLootItem may, in its ML-specific portion, disable them if it
  -- switches to the autoassign panel for example. We also start out with
  -- the main loot frame, which again can be switched out by SelectLootItem.
  --
  select_alf(ALF_LOOT)

  if (slist) then
    lootrules_setenabled(self, true)
    lootbid_setenabled(true)
    qf.bidders.mybid:SetEnabled(false)

    self:SelectLootItem(idx, cf, role, slist, rank)
    self:SendAM("LISEL", "ALERT", idx, cf, role, slist, rank)
    check_missing_members(self)
  end
end

local function llist_newitem(objp, num)
  local bname = "KSKBLListButton" .. tostring(num)
  local rf = MakeFrame("Button", bname, objp.content)
  local nfn = "GameFontNormalSmallLeft"
  local htn = "Interface/QuestFrame/UI-QuestTitleHighlight"

  rf:SetWidth(270)
  rf:SetHeight(16)
  rf:SetHighlightTexture(htn, "ADD")

  local text = rf:CreateFontString(nil, "ARTWORK", nfn)
  text:ClearAllPoints()
  text:SetPoint("TOPLEFT", rf, "TOPLEFT", 8, -2)
  text:SetPoint("BOTTOMRIGHT", rf, "BOTTOMRIGHT", -8, 2)
  text:SetJustifyH("LEFT")
  text:SetJustifyV("TOP")
  rf.text = text

  rf:SetScript("OnEnter", function(this, evt, ...)
    if (not ksk:AmIML() or ksk.cfg.settings.tooltips) then
      local idx = this:GetID()
      GameTooltip:SetOwner(this, "ANCHOR_TOPLEFT", 150)
      GameTooltip:SetHyperlink(ksk.bossloot[idx].ilink)
      GameTooltip:Show()
    end
  end)
  rf:SetScript("OnLeave", function(this, evt, ...)
    GameTooltip:Hide()
  end)

  rf.SetText = function(self, txt)
    self.text:SetText(txt)
  end

  rf:SetScript("OnClick", function(this) lloot_on_click(ksk, this) end)

  return rf
end

local function llist_setitem(objp, idx, slot, btn)
  btn:SetText(ksk.bossloot[idx].ilink)
  btn:SetID(idx)
  btn:Show()
end

local function llist_selectitem(objp, idx, slot, btn, onoff)
  local onoff = onoff or false

  if (not onoff) then
    lootrules_setenabled(ksk, false)
    lootbid_setenabled(false)
  end
end

local function blist_selectitem(objp, idx, slot, btn, onoff)
  local onoff = onoff or false

  if (onoff) then
    selectedbidder = idx
    selectedbiduid = bidders[idx].uid
  else
    selectedbidder = nil
    selectedbiduid = nil
  end

  qf.bidders.forceret:SetEnabled(onoff)
end

local function setup_iinfo(self)
  if (not selitemid) then
    return
  end

  local dcf = ""
  local ii = self.cfg.items[selitemid]

  if (self.iitems[selitemid]) then
    if (self.iitems[selitemid].cfilter) then
      dcf = self.iitems[selitemid].cfilter
    end
  end

  iinfo = { ilink = ii.ilink}
  iinfo.cfilter = {}

  local ics = self.cfg.items[selitemid].cfilter or dcf

  for k,v in pairs(K.IndexClass) do
    local n = tonumber(k)
    if (strsub(ics, n, n) == "1") then
      iinfo.cfilter[k] = true
    else
      iinfo.cfilter[k] = false
    end
  end

  iinfo.ignore = ii.ignore or false
  iinfo.ignorequal = ii.ignorequal or false
  iinfo.list = ii.list or "0"
  iinfo.role = ii.role or 0
  iinfo.rank = ii.rank or 0
  iinfo.nextuser = ii.user or nil
  iinfo.nextdrop = iinfo.nextuser ~= nil
  iinfo.autodel = ii.del or false
  iinfo.suicide = ii.suicide or "0"
  iinfo.autodench = ii.autodench or false
  iinfo.automl = ii.automl or false
end

local function ilist_setitem(objp, idx, slot, btn)
  local ilink = ksk.sorteditems[idx].link
  btn:SetText(ilink)
  btn:SetID(idx)
  btn:Show()
end

local function enable_uvalues(io, en)
  local en = en or false
  classes_setenabled(io, en)
  io.speclist:SetEnabled(en)
  io.defrank:SetEnabled(en)
  io.role:SetEnabled(en)
  io.nextdrop:SetEnabled(en)
  io.nextuser:SetEnabled(en and iinfo.nextdrop)
  io.seluser:SetEnabled(en and iinfo.nextdrop)
  io.autodel:SetEnabled(en and iinfo.nextdrop)
  io.suicidelist:SetEnabled(en and iinfo.nextdrop)

  if (ksk.cfg.cfgtype == KK.CFGTYPE_PUG) then
    io.defrank:SetEnabled(false)
  end
end

local function ilist_selectitem(objp, idx, slot, btn, onoff)
  local io = qf.itemopts
  local onoff = onoff or false

  local kids = { io:GetChildren() }
  for k,v in pairs(kids) do
    if (v.SetEnabled) then
      v:SetEnabled(onoff)
    end
  end

  if (onoff) then
    selitemid = ksk.sorteditems[idx].id
    setup_iinfo(ksk)
    hide_popup()

    --
    -- Set the values from the current iinfo, which is copied when an item
    -- is selected. All UI changes happen against the iinfo until such time
    -- as the "Update" button is pressed, at which time the actual item
    -- database is updated, so that we can send out an item change event
    -- with all of the changes, rather than sending out a change event as
    -- each modification is made.
    --
    local slist = "0"
    local adel = false
    local nuser = ""
    local en = (not iinfo.autodench) and (not iinfo.automl)
    enable_uvalues(io, en)
    if (iinfo.nextdrop) then
      slist = iinfo.suicide or "0"
      if (iinfo.nextuser) then
        nuser = aclass(ksk.cfg.users[iinfo.nextuser])
      end
    end
    io.autodench:SetChecked(iinfo.autodench)
    io.automl:SetChecked(iinfo.automl)
    io.ignorequal:SetChecked(iinfo.ignorequal)
    if (iinfo.autodench) then
      io.ignorequal:SetChecked(false)
      io.automl:SetEnabled(false)
      iinfo.automl = nil
      iinfo.ignorequal = nil
    end
    if (iinfo.automl) then
      io.ignorequal:SetChecked(false)
      io.autodench:SetEnabled(false)
      iinfo.autodench = nil
      iinfo.ignorequal = nil
    end
    classes_cfilter(io, iinfo.cfilter)
    io.suicidelist:SetValue(slist)
    io.autodel:SetChecked(iinfo.autodel)
    io.nextuser:SetText(nuser)
    io.nextdrop:SetChecked(iinfo.nextdrop)
    io.role:SetValue(iinfo.role)
    io.speclist:SetValue(iinfo.list)
    io.defrank:SetValue(iinfo.rank)
    io.ignore:SetChecked(iinfo.ignore)
    io.deletebtn:SetEnabled(true)
    changed(true, true)
  end
end

local function hlist_newitem(objp, num)
  local bname = "KSKHistListButton" .. tostring(num)
  local rf = MakeFrame("Button", bname, objp.content)
  local nfn = "GameFontNormalSmallLeft"
  local hfn = "GameFontHighlightSmallLeft"
  local htn = "Interface/QuestFrame/UI-QuestTitleHighlight"

  rf:SetWidth(470)
  rf:SetHeight(16)
  rf:SetHighlightTexture(htn, "ADD")

  local when = rf:CreateFontString(nil, "BORDER", nfn)
  when:ClearAllPoints()
  when:SetPoint("TOPLEFT", rf, "TOPLEFT", 0, -2)
  when:SetPoint("BOTTOMLEFT", rf, "BOTTOMLEFT", 0, -2)
  when:SetWidth(70)
  when:SetJustifyH("LEFT")
  when:SetJustifyV("TOP")
  rf.when = when

  local what = rf:CreateFontString(nil, "BORDER", nfn)
  what:ClearAllPoints()
  what:SetPoint("TOPLEFT", when, "TOPRIGHT", 4, 0)
  what:SetPoint("BOTTOMLEFT", when, "BOTTOMRIGHT", 4, 0)
  what:SetWidth(150)
  what:SetJustifyH("LEFT")
  what:SetJustifyV("TOP")
  rf.what = what

  local who = rf:CreateFontString(nil, "BORDER", nfn)
  who:ClearAllPoints()
  who:SetPoint("TOPLEFT", what, "TOPRIGHT", 4, 0)
  who:SetPoint("BOTTOMLEFT", what, "BOTTOMRIGHT", 4, 0)
  who:SetWidth(100)
  who:SetJustifyH("LEFT")
  who:SetJustifyV("TOP")
  rf.who = who

  local how = rf:CreateFontString(nil, "BORDER", nfn)
  how:ClearAllPoints()
  how:SetPoint("TOPLEFT", who, "TOPRIGHT", 4, 0)
  how:SetPoint("BOTTOMLEFT", who, "BOTTOMRIGHT", 4, 0)
  how:SetWidth(130)
  how:SetJustifyH("LEFT")
  how:SetJustifyV("TOP")
  rf.how = how

  rf.SetText = function(self, whn, wht, wo, ho)
    self.when:SetText(whn)
    self.what:SetText(wht)
    self.who:SetText(wo)
    self.how:SetText(ho)
    self.whatlink = wht
  end

  rf:SetScript("OnEnter", function(this, evt, ...)
    if (this.whatlink) then
      GameTooltip:SetOwner(this, "ANCHOR_BOTTOMLEFT", 0, 18)
      GameTooltip:SetHyperlink(this.whatlink)
      GameTooltip:Show()
    end
  end)

  rf:SetScript("OnLeave", function(this, evt, ...)
    GameTooltip:Hide()
  end)

  rf:SetScript("OnClick", function(this)
    if (IsModifiedClick("CHATLINK")) then
      ChatEdit_InsertLink(this.whatlink)
    end
  end)

  return rf
end

local histhow = {
  ["D"] = L["Disenchanted"],
  ["R"] = L["Won Roll"],
  ["M"] = L["Main Spec Roll"],
  ["O"] = L["Off Spec Roll"],
  ["B"] = L["BoE assigned to ML"],
  ["A"] = L["Auto-assigned"],
  ["U"] = L["Undo"],
}

local function hlist_setitem(objp, idx, slot, btn)
  local when, what, who, how, ipos = unpack(ksk.cfg.history[idx])
  local usr = who
  if (ksk.cfg.users[who]) then
    usr = shortaclass(ksk.cfg.users[who])
  else
    local name,cls = strsplit("/", who)
    if (cls) then
      usr = aclass(name, cls)
    end
  end

  local hs = histhow[how] or nil
  if (not hs) then
    if (ksk.cfg.lists[how]) then
      local ps = ""
      if (ipos and tonumber(ipos) > 0) then
        ps = strfmt("[%s] ", tostring(ipos))
      end
      hs = ps .. white(ksk.cfg.lists[how].name)
    else
      hs = white("???")
    end
  end

  when = when + K.utcdiff -- Display date in local time
  local ws = date("%m-%d %H:%M", when)

  btn:SetText(ws, what, usr, hs)
  btn:SetID(idx)
  btn:Show()
end

local function iclass_filter_func(which, evt, val, cls, user)
  changed(nil, user)
  iinfo.cfilter = iinfo.cfilter or {}
  iinfo.cfilter[cls] = val
end

local function class_filter_func(which, evt, val, cls, user)
  lootitem.cfilter = lootitem.cfilter or {}
  lootitem.cfilter[cls] = val
  if (ksk:AmIML() and user) then
    ksk:SendAM("FLTCH", "ALERT", "C", cls, val)
  end
end

local nextuser_popup

local function select_next(self, btn)
  if (not selitemid) then
    return
  end

  hide_popup()

  local ulist = {}

  for k,v in pairs(self.cfg.users) do
    tinsert(ulist, { text = shortaclass(v), value = k } )
  end
  tsort(ulist, function(a,b)
    local ul = self.cfg.users
    return strlower(ul[a.value].name) < strlower(ul[b.value].name)
  end)

  local function pop_func(puid)
    local ulist = nextuser_popup.selectionlist
    changed(nil, true)
    qf.ienextuserlbl:SetText(shortaclass(self.cfg.users[puid]))
    hide_popup()
    iinfo.nextdrop = true
    iinfo.nextuser = puid
  end

  if (not nextuser_popup) then
    nextuser_popup = K.PopupSelectionList(self, "KSKNextUserPopup",
      ulist, nil, 220, 400, self.mainwin.tabs[self.LOOT_TAB].content,
      16, pop_func)
  else
    nextuser_popup:UpdateList(ulist)
  end
  nextuser_popup:ClearAllPoints()
  nextuser_popup:SetPoint("TOPLEFT", btn, "TOPRIGHT", 0, nextuser_popup:GetHeight() / 2)
  self.popupwindow = nextuser_popup
  nextuser_popup:Show()
end

--
-- This is what 95% of the mod is all about, the dealing with bids, so I will
-- take a little time here explaining what happens. We can only reach this
-- code if we have a loot item selected. At the time the loot master (LM)
-- starts the loot we assume that the entry conditions for looting have been
-- correctly set (correct roll list, correct armor, role and guild rank
-- filters etc).
-- We create the self.currentbid entry and set the number of bidders to the
-- empty list. We then announce the opening of the bid in raid chat and
-- wait for bids to come in. While a bid is active the ML can change the
-- current roll list (which resets the list of bidders), change the guild
-- rank filter (which doesn't) or the role filter (which does). At some
-- point in time, either when people have bid or no-one is bidding, the ML
-- closes the bid. If there were bidders, the highest person in the list
-- receives the loot. When bids open, the "Open Bid" button changes to
-- "Close Bid" and the "Remove" button changes to "Next List". The "Next
-- List" button will clear any bidders (although why an ML would press it if
-- there were bidders is not clear) and move on to the next list (if there
-- is one). If there is no next list, the option is greyed out. The next list
-- is set in one of two places. First, in the roll list config, there is an
-- option for "Next List after Bid Timeout". If this is set to anything other
-- than "None" and this was the active roll list, move on to the list
-- specified. If "None" was selected in the next list field, the global
-- config option "Try final roll list" if set is used. If none of those are
-- set the "next list" button is greyed out.
--
-- At some point if no bidders have bid on the item the ML can either press
-- the "Close Bid" or "Open Roll" button. If they press "Open Roll" it gives
-- the users an opportunity to roll on the loot. If no-one rolls or if the
-- ML presses "Close Bids" the options set in the config for "When there are
-- no successful bidders" are obeyed. If the item is a BoE item and the
-- option is set, the item is assigned to the ML. If it is not BoE and there
-- are enchanters specified and the enchanters are in the raid and eligible to
-- receive the loot, the item is assigned to that enchanter to be DE'd.
--
local function open_close_bids(self)
  if (rolling) then
    rolling = 1
    lootroll.endtime = GetTime() - 1
    return
  end

  if (biditem) then
    --
    -- Lets see if we had any bidders. If we did, the highest one wins and
    -- we suicide them. If not we check the config options for what to do
    -- with the item.
    --
    if (qf.bidscroll.itemcount > 0) then
      -- We have a winning bidder. Suicide them on the list they won on.
      -- In order to suicide properly we need to build up the ordered list
      -- of users who are in the raid on that list. We also need to include
      -- any users marked as reserved. This gets sent to the whole guild so
      -- all mod users can update their lists, but it is also stored as an
      -- event in the event log, and send to any / all co-admins.
      local sulist = self:CreateRaidList(lootlistid)
      local winname, winuid, wincls = bidders[1].name, bidders[1].uid, bidders[1].class
      local party = KRP.players[winname].subgroup
      local ilink = lootitem.loot.ilink
      local gpos = ""
      local ipos = 0
      local il, lp = self:UserInList(winuid, lootlistid)

      if (il) then
        ipos = lp
        gpos = strfmt("[%d]", lp)
      end

      self:SuicideUser(lootlistid, sulist, winuid, self.currentid, ilink, true)
      self:AddLootHistory(nil, K.time(), ilink, winuid, lootlistid, ipos)

      local ts = strfmt(L["%s: %s%s (group %d) won %s. Grats!"], L["MODABBREV"], winname, gpos, party, ilink) 

      if (self.cfg.settings.ann_winners_raid) then
        self:SendText(ts)
      end

      printf(icolor, "%s", ts)

      if (self.cfg.settings.ann_winners_guild) then
        self:SendGuildText(strfmt(L["%s: %s%s won %s. Grats!"], L["MODABBREV"], winname, gpos, ilink))
      end

      if (lootitem.loot.slot ~= 0 and self.cfg.settings.auto_loot) then
        local cname = shortaclass(winname, wincls)
        qf.autoassign_msg:SetText(strfmt(L["AUTOLOOT"], cname, cname, cname))
        set_autoloot_win(winname)
      else
        self:RemoveItemByIdx(selectedloot, false)
      end

      self:ResetBidders(true)
      return
    else -- No bidders
      if (self.cfg.settings.ann_no_bids) then
        self:SendText(strfmt(L["%s: no successful bids for %s."], L["MODABBREV"], lootitem.loot.ilink))
      end

      if (boe_to_ml_or_de(self, false)) then
        return
      end
    end
    self:RemoveItemByIdx(selectedloot, false)
    self:ResetBidders(true)
  else
    -- We are starting a new bid.
    if (not lootlistid) then
      return
    end

    local lootlist = self.cfg.lists[lootlistid]

    self:ResetBidders(true)
    self:OpenBid(selectedloot)

    qf.bidders.forcebid:SetEnabled(memberid ~= nil and true or false)
    qf.lootwin.oclbids:SetText(L["Close Bids"])
    qf.lootwin.remcancel:SetText(K.CANCEL_STR)
    lootbid_setenabled(true)

    self:SendAM("BIDOP", "ALERT", biditem, timeout)

    self:SendWarning(strfmt(L["Bids now open for %s on the %q list."], lootitem.loot.ilink, lootlist.name))

    if (self.cfg.settings.ann_bid_usage) then
      self:SendText(strfmt(L["%s: to bid on %s, whisper %s the word %q. For general help using %s, whisper an admin the word %q."], L["MODABBREV"], lootitem.loot.ilink, K.player.name, L["WHISPERCMD_BID"], L["MODABBREV"], L["WHISPERCMD_HELP"]))
    end
  end
end

function ksk:SendCHITM(itemid, ii, cfg)
  local cfg = cfg or self.currentid

  local ignore = ii.ignore or false

  local cfilter = ""
  if (not ii.ignore and ii.cfilter) then
    cfilter = ii.cfilter
  end

  local role = 0
  if (not ii.ignore and ii.role and ii.role ~= 0) then
    role = ii.role
  end

  local list = ""
  if (not ii.ignore and ii.list and ii.list ~= "0") then
    list = ii.list
  end

  local rank = 0
  if (not ii.ignore and ii.rank) then
    rank = ii.rank
  end

  local user = ""
  if (not ii.ignore and ii.user) then
    user = ii.user
  end

  local suicide = false
  if (not ii.ignore and ii.user and ii.suicide) then
    suicide = ii.suicide
  end

  local delete = false
  if (not ii.ignore and ii.user and ii.del) then
    delete = true
  end

  local autodench = false
  if (not ii.ignore and ii.autodench) then
    autodench = true
  end

  local automl = false
  if (not ii.ignore and ii.automl) then
    automl = true
  end

  local ignorequal = false
  if (not ii.ignore and ii.ignorequal) then
    ignorequal = true
  end

  self:AdminEvent(cfg, "CHITM", itemid, ignore, cfilter, role, list, rank, user, suicide, delete, autodench, automl, ignorequal)
end

local function make_xml_string(self)
  local dstr, tstr
  local classes = {}
  local ulist = {}
  local llist = {}
  local ilist = {}
  local uul = {}
  local lul = {}
  local iil = {}
  local iqual = {}
  local iql = {}
  local ehl = {}

  tinsert(classes, '<c id="00" v="unkclass"/>')
  for k,v in pairs(K.IndexClass) do
    if (v.u) then
      tinsert(classes, strfmt("<c id=%q v=%q/>", tostring(k), strlower(tostring(v.u))))
    end
  end

  tinsert(llist, strfmt('<l id="D" n="%s"/>', L["Disenchanted"]))
  tinsert(llist, strfmt('<l id="R" n="%s"/>', L["Won Roll"]))
  tinsert(llist, strfmt('<l id="M" n="%s"/>', L["Main Spec Roll"]))
  tinsert(llist, strfmt('<l id="O" n="%s"/>', L["Off Spec Roll"]))
  tinsert(llist, strfmt('<l id="B" n="%s"/>', L["BoE assigned to ML"]))
  tinsert(llist, strfmt('<l id="A" n="%s"/>', L["Auto-assigned"]))
  tinsert(llist, strfmt('<l id="U" n="%s"/>', L["Undo"]))
  tinsert(llist, strfmt('<l id="u" n="???"/>'))
  lul["D"] = true
  lul["R"] = true
  lul["M"] = true
  lul["O"] = true
  lul["B"] = true
  lul["A"] = true
  lul["U"] = true
  lul["u"] = true

  iqual["9d9d9d"] = { id="0", v="poor" }
  iqual["ffffff"] = { id="1", v="common" }
  iqual["1eff00"] = { id="2", v="uncommon" }
  iqual["0070dd"] = { id="3", v="rare" }
  iqual["a335ee"] = { id="4", v="epic" }
  iqual["ff8000"] = { id="5", v="legendary" }
  iqual["e6cc80"] = { id="6", v="artifact" }
  for k,v in pairs(iqual) do
    tinsert(iql, strfmt('<q id=%q v=%q/>', v.id, v.v))
  end

  for k,v in pairs(self.cfg.history) do
    local when, what, who, how = unpack(v)
    local uid = nil
    local cls = nil
    local name = nil

    if (self.cfg.users[who]) then
      uid = who
      cls = self.cfg.users[who].class
      name = self.cfg.users[uid].name
    else
      name, cls = strsplit("/", who)
      uid = name
      if (not cls) then
        cls = "00"
      end
    end

    if (not uul[uid]) then
      uul[uid] = true
      tinsert(ulist, strfmt("<u id=%q n=%q c=%q/>", uid, name, cls))
    end

    if (strlen(how) > 1) then
      if (not self.cfg.lists[how]) then
        how = "u"
      end
    end

    if (not lul[how]) then
      lul[how] = true
      tinsert(llist, strfmt("<l id=%q n=%q/>", how, self.cfg.lists[how].name))
    end

    dstr = K.YMDStamp(when)
    tstr = K.HMStamp(when)

    local iqv = iqual[strsub(what, 5, 10)].id
    local iname = strmatch(what, "|h%[(.*)%]|h")
    local itemid = strmatch(what, "item:(%d+)")

    if (not (iil[itemid])) then
      iil[itemid] = true
      tinsert(ilist, strfmt("<i id=%q n=%q q=%q/>", itemid, iname, iqv))
    end

    tinsert(ehl, strfmt('<h d="%s" t="%s" id=%q u=%q w=%q/>',
      dstr, tstr, itemid, uid, how))
  end

  dstr = K.YMDStamp()
  tstr = K.HMStamp()

  return strfmt("<ksk_history date=%q time=%q><classes>%s</classes><users>%s</users><quals>%s</quals><items>%s</items><lists>%s</lists><history>%s</history></ksk_history>", dstr, tstr, tconcat(classes, ""), tconcat(ulist, ""), tconcat(iql, ""), tconcat(ilist, ""), tconcat(llist, ""), tconcat(ehl, ""))
end

local function make_json_string(self)
  local dstr, tstr
  local cs = '{"id": "00", "v": "unkclass" }'
  local ulist = {}
  local llist = {}
  local ilist = {}
  local uul = {}
  local lul = {}
  local iil = {}
  local iqual = {}
  local iql = {}
  local ehl = {}

  for k,v in pairs(K.IndexClass) do
    if (v.u) then
      cs = cs .. strfmt(',\n{"id": %q, "v": %q}', tostring(k), strlower(tostring(v.u)))
    end
  end

  tinsert(llist, strfmt('{ "id": "D", "n": %q }', L["Disenchanted"]))
  tinsert(llist, strfmt('{ "id": "R", "n": %q }', L["Won Roll"]))
  tinsert(llist, strfmt('{ "id": "M", "n": %q }', L["Main Spec Roll"]))
  tinsert(llist, strfmt('{ "id": "O", "n": %q }', L["Off Spec Roll"]))
  tinsert(llist, strfmt('{ "id": "B", "n": %q }', L["BoE assigned to ML"]))
  tinsert(llist, strfmt('{ "id": "A", "n": %q }', L["Auto-assigned"]))
  tinsert(llist, strfmt('{ "id": "U", "n": %q }', L["Undo"]))
  tinsert(llist, strfmt('{ "id": "u", "n": "???" }'))
  lul["D"] = true
  lul["R"] = true
  lul["M"] = true
  lul["O"] = true
  lul["B"] = true
  lul["A"] = true
  lul["U"] = true
  lul["u"] = true

  iqual["9d9d9d"] = { id="0", v="poor" }
  iqual["ffffff"] = { id="1", v="common" }
  iqual["1eff00"] = { id="2", v="uncommon" }
  iqual["0070dd"] = { id="3", v="rare" }
  iqual["a335ee"] = { id="4", v="epic" }
  iqual["ff8000"] = { id="5", v="legendary" }
  iqual["e6cc80"] = { id="6", v="artifact" }
  for k,v in pairs(iqual) do
    tinsert(iql, strfmt('{ "id": %q, "v": %q }', v.id, v.v))
  end

  for k,v in pairs(self.cfg.history) do
    local when, what, who, how = unpack(v)
    local uid = nil
    local cls = nil
    local name = nil

    if (self.cfg.users[who]) then
      uid = who
      cls = self.cfg.users[who].class
      name = self.cfg.users[uid].name
    else
      name, cls = strsplit("/", who)
      uid = name
      if (not cls) then
        cls = "00"
      end
    end

    if (not uul[uid]) then
      uul[uid] = true
      tinsert(ulist, strfmt('{ "id": %q, "n": %q, "c": %q }', uid, name, cls))
    end

    if (strlen(how) > 1) then
      if (not self.cfg.lists[how]) then
        how = "u"
      end
    end

    if (not lul[how]) then
      lul[how] = true
      tinsert(llist, strfmt('{ "id": %q, "n": %q }',
        how, self.cfg.lists[how].name))
    end

    dstr = K.YMDStamp(when)
    tstr = K.HMStamp(when)

    local iqv = iqual[strsub(what, 5, 10)].id
    local iname = strmatch(what, "|h%[(.*)%]|h")
    local itemid = strmatch(what, "item:(%d+)")

    if (not (iil[itemid])) then
      iil[itemid] = true
      tinsert(ilist, strfmt('{ "id": %q, "n": %q, "q": %q }',
        itemid, iname, iqv))
    end

    tinsert(ehl, strfmt('{ "d": %q, "t": %q, "id": %q, "u": %q, "w": %q}',
      dstr, tstr, itemid, uid, how))
  end

  dstr = K.YMDStamp()
  tstr = K.HMStamp()

  return strfmt('{"ksk_history": { "date": %q, "time": %q, "classes": [%s], "users": [%s], "quals": [%s], "items": [%s], "lists": [%s], "history": [%s] }}', dstr, tstr, cs, tconcat(ulist, ","), tconcat(iql, ","), tconcat(ilist, ",\n"), tconcat(llist, ",\n"), tconcat(ehl, ",\n"))
end

local function export_history_button(self, fmt)
  if (not exphistdlg) then
    local ypos = 0
    local arg = {
      x = "CENTER", y = "MIDDLE",
      name = "KSKExportHistoryDialog",
      title = L["Export Loot History"],
      border = true,
      width = 400,
      height = 125,
      canmove = true,
      canresize = false,
      escclose = true,
      blackbg = true,
      okbutton = { text = K.ACCEPTSTR },
      cancelbutton = { text = K.CANCELSTR },
    }
    local ret = KUI:CreateDialogFrame(arg)

    arg = {
      x = 0, y = ypos, len = 99999,
      label = { text = L["Export string"], pos = "LEFT" },
      tooltip = { title = "$$", text = L["TIP050"], },
    }
    ret.expstr = KUI:CreateEditBox(arg, ret)
    ret.expstr:Catch("OnValueChanged", function(this, evt, newv)
      this:HighlightText()
      this:SetCursorPosition(0)
      if (newv ~= "") then
        this:SetFocus()
        exphistdlg.copymsg:Show()
      else
        this:ClearFocus()
        exphistdlg.copymsg:Hide()
      end
    end)
    ypos = ypos - 30

    arg = {
      x = 16, y = ypos, width = 300,
      text = L["Press Ctrl+C to copy the export string"],
    }
    ret.copymsg = KUI:CreateStringLabel(arg, ret)
    ypos = ypos - 24

    ret.OnAccept = function(this)
      exphistdlg:Hide()
      self.mainwin:Show()
    end

    ret.OnCancel = function(this)
      exphistdlg:Hide()
      self.mainwin:Show()
    end

    exphistdlg = ret
  end

  local fstr
  if (fmt == HIST_EXP_XML) then
    fstr = make_xml_string(self)
  elseif (fmt == HIST_EXP_JSON) then
    fstr = make_json_string(self)
  else
    fstr = ""
  end

  self.mainwin:Hide()
  exphistdlg:Show()
  exphistdlg.expstr:SetText(fstr)
end

local function undo_button(self)
  if (not undodlg) then
    local ypos = 0
    local arg = {
      x = "CENTER", y = "MIDDLE",
      name = "KSKUndoDialog",
      title = L["Undo"],
      border = true,
      width = 420,
      height = 160,
      canmove = true,
      canresize = false,
      escclose = true,
      blackbg = true,
      okbutton = { text = K.ACCEPTSTR },
      cancelbutton = { text = K.CANCELSTR },
    }
    local ret = KUI:CreateDialogFrame(arg)
    arg = {
      x = 0, y = ypos, text = L["Are you absolutely sure you want to undo this suicide?"],
      autosize = true, font = "GameFontNormal", width = 400,
    }
    ret.str1 = KUI:CreateStringLabel(arg, ret)
    ypos = ypos - 24
    local sypos = ypos
    arg.y = ypos
    arg.width = nil
    arg.text = L["User"]
    arg.autosize = false
    arg.width = 64
    arg.justifyh = "RIGHT"
    ret.str2 = KUI:CreateStringLabel(arg, ret)
    ypos = ypos - 24
    arg.y = ypos
    arg.text = L["List"]
    ret.str3 = KUI:CreateStringLabel(arg, ret)
    ypos = ypos - 24
    arg.y = ypos
    arg.text = L["Item"]
    ret.str4 = KUI:CreateStringLabel(arg, ret)

    ypos = sypos
    arg = {
      x = 70, y = ypos, width = 300, border = true, autosize = false,
      justifyh = "LEFT", height = 20,
    }
    ret.user = KUI:CreateStringLabel(arg, ret)
    ypos = ypos - 24
    arg.y = ypos
    ret.list = KUI:CreateStringLabel(arg, ret)
    ypos = ypos - 24
    arg.y = ypos
    ret.item = KUI:CreateStringLabel(arg, ret)

    ret.OnAccept = function(this)
      undodlg:Hide()
      self.mainwin:Show()

      local cid = self.currentid
      local csd = self.csdata[cid]
      urec = tremove(csd.undo, 1)
      if (#csd.undo < 1) then
        csd.undo = nil
        qf.undobutton:SetEnabled(false)
      end
      self:UndoSuicide(cid, urec.listid, urec.movers, urec.uid, urec.ilink, false)
    end

    ret.OnCancel = function(this)
      undodlg:Hide()
      self.mainwin:Show()
    end

    undodlg = ret
  end

  local cid = self.currentid
  if (not self.csdata[cid].undo) then
    return
  end
  if (#self.csdata[cid].undo < 1) then
    return
  end

  self.mainwin:Hide()
  undodlg:Show()

  local ui = self.csdata[cid].undo[1]

  undodlg.user:SetText(aclass(self.cfg.users[ui.uid]))
  undodlg.list:SetText(self.cfg.lists[ui.listid].name)
  undodlg.item:SetText(ui.ilink)
end

local function refresh_loot_lists(self)
  local oldlist = lootlistid or nil
  local oldidx = nil

  lootlistid = nil
  for k,v in ipairs(self.sortedlists) do
    if (v.id == oldlist) then
      oldidx = k
    end
  end

  qf.lists.itemcount = self.cfg.nlists
  qf.lists:UpdateList()
  -- This will also update the members list.
  qf.lists:SetSelected(oldidx, true, true)
end

local function set_classes_from_filter(filter)
  for k,v in pairs(K.IndexClass) do
    local n = tonumber(k)
    local val = false
    if (strsub(filter, n, n) == "1") then
      val = true
    end
    qf.lootrules[v.w]:SetChecked(val)
  end
end

function ksk:InitialiseLootUI()
  local arg
  local kmt = self.mainwin.tabs[self.LOOT_TAB]

  kmt.onclick = function(this, main, sub)
    qf.membersearch:SetEnabled(self:AmIML())
  end

  -- First set up the quick access frames we will be using.
  qf.assign = kmt.tabs[self.LOOT_ASSIGN_PAGE].content
  qf.itemedit = kmt.tabs[self.LOOT_ITEMS_PAGE].content
  qf.history = kmt.tabs[self.LOOT_HISTORY_PAGE].content

  --
  -- Loot tab, Loot Assignment page.
  --
  local ypos = 0

  local cf = qf.assign
  local tbf = kmt.topbar
  local ls = cf.vsplit.leftframe
  local rs = cf.vsplit.rightframe

  arg = {
    inset = 0, height = 128,
    rightsplit = true, name = "KSKLootLSplit", topanchor = true,
  }
  ls.hsplit = KUI:CreateHSplit(arg, ls)
  local tl = ls.hsplit.topframe
  local bl = ls.hsplit.bottomframe

  arg = {
    inset = 0, height = 20, name = "KSKLootLLHSplit", rightsplit = true,
  }
  bl.hsplit = KUI:CreateHSplit(arg, bl)
  local tbl = bl.hsplit.topframe
  local bbl = bl.hsplit.bottomframe

  arg = {
    name = "KSKLootListsScrollList",
    itemheight = 16,
    newitem = rlist_newitem,
    setitem = rlist_setitem,
    selectitem = rlist_selectitem,
    highlightitem = function(objp, idx, slot, btn, onoff)
      return KUI.HighlightItemHelper(objp, idx, slot, btn, onoff)
    end,
  }
  tl.slist = KUI:CreateScrollList(arg, tl)
  qf.lists = tl.slist

  local bdrop = {
    bgFile = KUI.TEXTURE_PATH .. "TDF-Fill",
    tile = true,
    tileSize = 32,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
  }
  tl.slist:SetBackdrop(bdrop)

  arg = {
    name = "KSKLootMembersScrollList",
    itemheight = 16,
    newitem = mlist_newitem,
    setitem = mlist_setitem,
    selectitem = mlist_selectitem,
    highlightitem = function(objp, idx, slot, btn, onoff)
      return KUI.HighlightItemHelper(objp, idx, slot, btn, onoff)
    end,
  }
  tbl.slist = KUI:CreateScrollList(arg, tbl)
  qf.members = tbl.slist
  tbl.slist:SetBackdrop(bdrop)

  arg = {
    x = 0, y = 2, len = 16, font = "ChatFontSmall",
    width = 170, tooltip = { title = L["User Search"], text = L["TIP099"] },
  }
  bbl.searchbox = KUI:CreateEditBox(arg, bbl)
  qf.membersearch = bbl.searchbox
  bbl.searchbox:Catch("OnEnterPressed", function(this, evt, newv, user)
    this:SetText("")
  end)
  bbl.searchbox:Catch("OnValueChanged", function(this, evt, newv, user)
    if (not members) then
      return
    end
    if (user and newv and newv ~= "") then
      local lnv = strlower(newv)
      for k,v in pairs(members) do
        local tln = strlower(self.cfg.users[v.id].name)
        if (strfind(tln, lnv, 1, true)) then
          local its = v.id
          if (v.isalt) then
            its = v.main
          end
          for kk,vv in ipairs(members) do
            if (vv.id == its) then
              qf.members:SetSelected(kk, true, true)
              break
            end
          end
          return
        end
      end
    end
  end)

  --
  -- Right-hand side panel which has the loot list, filter controls and
  -- current bidders.
  --
  arg = {
    inset = 0, height = 128, name = "KSKLootListHSplit",
    leftsplit = true, topanchor = true,
  }
  rs.hsplit = KUI:CreateHSplit(arg, rs)
  local tr = rs.hsplit.topframe
  local br = rs.hsplit.bottomframe
  qf.lootwin = tr

  arg = {
    inset = 0, height = 180, name = "KSKLootFilterHSplit",
    leftsplit = true, topanchor = true,
  }
  br.hsplit = KUI:CreateHSplit(arg, br)
  local bmf = br.hsplit.topframe
  local bb = br.hsplit.bottomframe

  --
  -- The loot rules frame doubles as both the loot rules and the "popup"
  -- frame when we auto-assign loot to someone. We do this so that we do
  -- not need to hide the main window and the loot master can see who is
  -- in the raid and look at the loot lists etc. So when we have an item
  -- that is auto-assigned to a user in the item database or when a user
  -- has won a bid and we are auto-assigning loot, we hide the loot rules
  -- window and display the loot assignment window in its place. We need
  -- to be careful when showing the window again however. If the master
  -- looter closes the main KSK window, when they re-open it, we need the
  -- original loot rules window back. They can always assign loot through
  -- the traditional Blizzard interface.
  --
  local bm = MakeFrame("Frame", nil, bmf)
  bm:ClearAllPoints()
  bm:SetPoint("TOPLEFT", bmf, "TOPLEFT", 0, 0)
  bm:SetPoint("BOTTOMRIGHT", bmf, "BOTTOMRIGHT", 0, 0)

  local alf = MakeFrame("Frame", nil, bmf)
  alf:ClearAllPoints()
  alf:SetPoint("TOPLEFT", bmf, "TOPLEFT", 0, 0)
  alf:SetPoint("BOTTOMRIGHT", bmf, "BOTTOMRIGHT", 0, 0)
  alf:Hide()

  local rlf = MakeFrame("Frame", nil, bmf)
  rlf:ClearAllPoints()
  rlf:SetPoint("TOPLEFT", bmf, "TOPLEFT", 0, 0)
  rlf:SetPoint("BOTTOMRIGHT", bmf, "BOTTOMRIGHT", 0, 0)
  rlf:Hide()

  qf.lootrules = bm
  qf.autoloot = alf
  qf.lootroll = rlf
  qf.bidders = bb

  --
  -- Populate the auto-assign frame first. Its pretty simple.
  --
  arg = {
    x = "CENTER", y = 0, height = 24, width = 265, autosize = false,
    font = "GameFontNormal", text = "",
    color = {r = 1, g = 1, b = 1, a = 1 }, border = true,
    justifyh = "CENTER",
  }
  alf.item = KUI:CreateStringLabel(arg, alf)
  qf.autoassign_item = alf.item

  arg = {
    x = 0, y = 0, width = 1, height = 1, autosize = false,
    color = {r = 1, g = 0, b = 0, a = 1 }, text = "",
    font = "GameFontNormal", justifyv = "TOP",
  }
  alf.str = KUI:CreateStringLabel(arg, alf)
  alf.str:ClearAllPoints()
  alf.str:SetPoint("TOPLEFT", alf, "TOPLEFT", 4, -30)
  alf.str:SetPoint("BOTTOMRIGHT", alf, "BOTTOMRIGHT", -4, 28)
  alf.str.label:SetPoint("TOPLEFT", alf.str, "TOPLEFT", 0, 0)
  alf.str.label:SetPoint("BOTTOMRIGHT", alf.str, "BOTTOMRIGHT", 0, 0)
  qf.autoassign_msg = alf.str

  arg = {
    x = 40, y = -154, width = 90, text = K.OK_STR,
  }
  alf.ok = KUI:CreateButton(arg, alf)
  alf.ok:Catch("OnClick", function(this, evt, ...)
    auto_loot_ok(self)
  end)

  arg = {
    x = 160, y = -154, width = 90, text = K.CANCEL_STR,
  }
  alf.cancel = KUI:CreateButton(arg, alf)
  alf.cancel:Catch("OnClick", function(this, evt, ...)
    auto_loot_cancel(self)
  end)

  --
  -- Next do the loot roll frame, also pretty simple.
  --
  local function rem_onclick(this, evt)
    local w = this.which
    local nm = lootroll.sorted[w]
    player_rolled(self, nm, 1, 1, 1)
  end

  local ypos = 0
  arg = {
    x = 5, y = ypos, width = 180, height = 20, border = true,
    font = "GameFontNormal", text = "", autosize = false,
  }
  local arg2 = {
    x = 185, y = ypos, width = 105, height = 20, text = L["Remove"],
    enabled = false, tooltip = { title = "$$", text = L["TIP091"] },
  }
  rlf.pos1 = KUI:CreateStringLabel(arg, rlf)
  rlf.rem1 = KUI:CreateButton(arg2, rlf)
  rlf.rem1.which = 1
  rlf.rem1:Catch("OnClick", rem_onclick)
  ypos = ypos - 20
  arg.y = ypos
  arg2.y = ypos
  rlf.pos2 = KUI:CreateStringLabel(arg, rlf)
  rlf.rem2 = KUI:CreateButton(arg2, rlf)
  rlf.rem2.which = 2
  rlf.rem2:Catch("OnClick", rem_onclick)
  ypos = ypos - 20
  arg.y = ypos
  arg2.y = ypos
  rlf.pos3 = KUI:CreateStringLabel(arg, rlf)
  rlf.rem3 = KUI:CreateButton(arg2, rlf)
  rlf.rem3.which = 3
  rlf.rem3:Catch("OnClick", rem_onclick)
  ypos = ypos - 20
  arg.y = ypos
  arg2.y = ypos
  rlf.pos4 = KUI:CreateStringLabel(arg, rlf)
  rlf.rem4 = KUI:CreateButton(arg2, rlf)
  rlf.rem4.which = 4
  rlf.rem4:Catch("OnClick", rem_onclick)
  ypos = ypos - 20
  arg.y = ypos
  arg2.y = ypos
  rlf.pos5 = KUI:CreateStringLabel(arg, rlf)
  rlf.rem5 = KUI:CreateButton(arg2, rlf)
  rlf.rem5.which = 5
  rlf.rem5:Catch("OnClick", rem_onclick)
  ypos = ypos - 20
  arg.y = ypos
  arg2.y = ypos
  arg.border = false
  arg.autosize = true
  arg.color = {r = 1, g = 0, b = 0, a = 1 }
  arg.text = L["Note: only top 5 rolls shown."]
  rlf.str1 = KUI:CreateStringLabel(arg, rlf)
  ypos = ypos - 20

  rlf.timerbarframe = MakeFrame("Frame", "KSKLootRollTimerFrame", rlf)
  rlf.timerbarframe:ClearAllPoints()
  rlf.timerbarframe:SetPoint("TOPLEFT", rlf.str1, "BOTTOMLEFT", 0, -4)
  rlf.timerbarframe:SetWidth(210)
  rlf.timerbarframe:SetHeight(30)
  rlf.timerbarframe:SetBackdrop( {
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    })
  rlf.timerbarframe:SetBackdropBorderColor(0.4, 0.4, 0.4)
  rlf.timerbarframe:SetBackdropColor(0, 0, 0, 0)

  rlf.timerbar = MakeFrame("StatusBar", nil, rlf.timerbarframe)
  rlf.timerbar:SetWidth(200)
  rlf.timerbar:SetHeight(20)
  rlf.timerbar:ClearAllPoints()
  rlf.timerbar:SetPoint("CENTER", rlf.timerbarframe, "CENTER")
  rlf.timerbar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
  rlf.timerbar:SetStatusBarColor(0, 1, 0)
  rlf.timerbar:SetMinMaxValues(0, 1)

  rlf.timertext = rlf.timerbar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  rlf.timertext:ClearAllPoints()
  rlf.timertext:SetPoint("TOPLEFT", rlf.timerbar, "TOPLEFT", 0, 0)
  rlf.timertext:SetWidth(180)
  rlf.timertext:SetHeight(16)
  rlf.timertext:SetTextColor(1,1,1,1)
  rlf.timertext:SetJustifyH("CENTER")
  rlf.timertext:SetJustifyV("MIDDLE")

  rlf.timerspark = rlf.timerbar:CreateTexture(nil, "OVERLAY")
  rlf.timerspark:SetTexture("Interface/CastingBar/UI-CastingBar-Spark")
  rlf.timerspark:SetBlendMode("ADD")
  rlf.timerspark:SetWidth(20)
  rlf.timerspark:SetHeight(44)

  rlf.StartRoll = function(sroll)
    qf.lootwin.oclbids:SetText(L["End Roll"])
    qf.lootwin.oclbids:SetEnabled(true)
    qf.lootwin.orpause:SetText(L["Pause"])
    qf.lootwin.orpause:SetEnabled(true)
    qf.lootwin.remcancel:SetText(K.CANCEL_STR)
    qf.lootwin.remcancel:SetEnabled(true)

    self:StartOpenRoll(lootitem.loot.ilink, self.cfg.settings.roll_timeout, self.cfg.settings.offspec_rolls)
    lootroll.suicide = sroll
  end

  local function rlf_onhide()
    if (rolling == 1) then
      open_roll_or_pause(self)
    end
  end

  rlf:SetScript("OnHide", rlf_onhide)

  --
  -- Now populate the actual loot rules frame
  --

  ypos = 0
  arg = {
    x = 0, y = ypos, text = L["Class Filter"],
    font = "GameFontNormal",
  }
  bm.cflabel = KUI:CreateStringLabel(arg, bm)
  ypos = ypos - 16

  arg = {
    x = 0, y = ypos, label = { text = K.IndexClass[K.CLASS_WARRIOR].c },
    font = "GameFontHighlightSmall", height = 16,
  }
  bm.warrior = KUI:CreateCheckBox(arg, bm)
  bm.warrior:Catch("OnValueChanged", function(this, evt, val, user)
    class_filter_func(this, evt, val, K.CLASS_WARRIOR, user)
  end)

  arg = {
    x = 88, y = ypos, label = { text = K.IndexClass[K.CLASS_PALADIN].c },
    font = "GameFontHighlightSmall", height = 16,
  }
  bm.paladin = KUI:CreateCheckBox(arg, bm)
  bm.paladin:Catch("OnValueChanged", function(this, evt, val, user)
    class_filter_func(this, evt, val, K.CLASS_PALADIN, user)
  end)

  arg = {
    x = 176, y = ypos, label = { text = K.IndexClass[K.CLASS_HUNTER].c },
    font = "GameFontHighlightSmall", height = 16,
  }
  bm.hunter = KUI:CreateCheckBox(arg, bm)
  bm.hunter:Catch("OnValueChanged", function(this, evt, val, user)
    class_filter_func(this, evt, val, K.CLASS_HUNTER, user)
  end)
  ypos = ypos - 16

  arg = {
    x = 0, y = ypos, label = { text = K.IndexClass[K.CLASS_SHAMAN].c },
    font = "GameFontHighlightSmall", height = 16,
  }
  bm.shaman = KUI:CreateCheckBox(arg, bm)
  bm.shaman:Catch("OnValueChanged", function(this, evt, val, user)
    class_filter_func(this, evt, val, K.CLASS_SHAMAN, user)
  end)

  arg = {
    x = 88, y = ypos, label = { text = K.IndexClass[K.CLASS_DRUID].c },
    font = "GameFontHighlightSmall", height = 16,
  }
  bm.druid = KUI:CreateCheckBox(arg, bm)
  bm.druid:Catch("OnValueChanged", function(this, evt, val, user)
    class_filter_func(this, evt, val, K.CLASS_DRUID, user)
  end)

  arg = {
    x = 176, y = ypos, label = { text = K.IndexClass[K.CLASS_ROGUE].c },
    font = "GameFontHighlightSmall", height = 16,
  }
  bm.rogue = KUI:CreateCheckBox(arg, bm)
  bm.rogue:Catch("OnValueChanged", function(this, evt, val, user)
    class_filter_func(this, evt, val, K.CLASS_ROGUE, user)
  end)
  ypos = ypos - 16

  arg = {
    x = 0, y = ypos, label = { text = K.IndexClass[K.CLASS_MAGE].c },
    font = "GameFontHighlightSmall", height = 16,
  }
  bm.mage = KUI:CreateCheckBox(arg, bm)
  bm.mage:Catch("OnValueChanged", function(this, evt, val, user)
    class_filter_func(this, evt, val, K.CLASS_MAGE, user)
  end)

  arg = {
    x = 88, y = ypos, label = { text = K.IndexClass[K.CLASS_WARLOCK].c },
    font = "GameFontHighlightSmall", height = 16,
  }
  bm.warlock = KUI:CreateCheckBox(arg, bm)
  bm.warlock:Catch("OnValueChanged", function(this, evt, val, user)
    class_filter_func(this, evt, val, K.CLASS_WARLOCK, user)
  end)

  arg = {
    x = 176, y = ypos, label = { text = K.IndexClass[K.CLASS_PRIEST].c },
    font = "GameFontHighlightSmall", height = 16,
  }
  bm.priest = KUI:CreateCheckBox(arg, bm)
  bm.priest:Catch("OnValueChanged", function(this, evt, val, user)
    class_filter_func(this, evt, val, K.CLASS_PRIEST, user)
  end)

  ypos = ypos - 16

  arg = {
    x = 0, y = ypos, label = { text = K.IndexClass[K.CLASS_DEATHKNIGHT].c },
    font = "GameFontHighlightSmall", height = 16,
  }
  bm.deathknight = KUI:CreateCheckBox(arg, bm)
  bm.deathknight:Catch("OnValueChanged", function(this, evt, val, user)
    class_filter_func(this, evt, val, K.CLASS_DEATHKNIGHT, user)
  end)

  ypos = ypos - 20

  arg = {
    x = 0, y = ypos, text = L["Other Filters"],
    font = "GameFontNormal",
  }
  bm.aflabel = KUI:CreateStringLabel(arg, bm)
  ypos = ypos - 16

  bm.role = self:CreateRoleListDropdown("LootRoleFilter", 0, ypos, bm)
  bm.role:SetEnabled(false)
  bm.role:Catch("OnValueChanged", function(this, evt, newv, user)
    if (lootitem) then
      lootitem.role = newv
    end
    if (self:AmIML() and user) then
      self:SendAM("FLTCH", "ALERT", "R", newv)
    end
  end)
  ypos = ypos - 30
  bm.role:SetValue(0)

  arg = {
    x = 0, y = ypos, mode = "SINGLE", itemheight = 16, border = "THIN",
    name = "KSKLootRankFilter", dwidth = 150, items = KUI.emptydropdown,
    label = { text = L["Guild Rank"], pos = "LEFT" },
    tooltip = { title = "$$", text = L["TIP051"], },
  }
  bm.rank = KUI:CreateDropDown(arg, bm)
  bm.rank:Catch("OnValueChanged", function (this, evt, newv, user)
    if (lootitem) then
      lootitem.rank = newv
    end

    if (self:AmIML() and user) then
      self:SendAM("FLTCH", "ALERT", "G", newv)
    end
  end)
  -- Must remain visible in self.qf so the ranks can be updated from main.
  self.qf.lootrank = bm.rank

  arg = {
    x = 350, y = ypos, width = 16, height = 16, text = "-",
  }
  bm.nextrank = KUI:CreateButton(arg, bm)
  bm.nextrank:ClearAllPoints()
  bm.nextrank:SetPoint("TOPLEFT", bm.rank.button, "TOPRIGHT", 2, -4)
  bm.nextrank:Catch("OnClick", function (this, evt, ...)
    if (self:AmIML() and lootitem and lootitem.rank) then
      if (lootitem.rank < K.guild.numranks) then
        lootitem.rank = lootitem.rank + 1
        bm.rank:SetValue (lootitem.rank)
        self:SendAM("FLTCH", "ALERT", "G", lootitem.rank)
      end
    end
  end)
  ypos = ypos - 30

  arg = {
    x = 0, y = ypos, label = { text = L["Strict Class Armor"] },
    font = "GameFontHighlightSmall", height = 16,
    tooltip = { title = "$$", text = L["TIP039"], }, 
  }
  bm.strictarmour = KUI:CreateCheckBox(arg, bm)
  bm.strictarmour:Catch("OnValueChanged", function(this, evt, val, user)
    if (self:AmIML() and user) then
      if (val) then
        set_classes_from_filter(lootitem.loot.strict)
      else
        set_classes_from_filter(lootitem.loot.relaxed)
      end
      self:SendAM("FLTCH", "ALERT", "A", val)
      lootitem.strictarmor = val
    end
  end)

  arg = {
    x = 150, y = ypos, label = { text = L["Strict Role Filter"] },
    font = "GameFontHighlightSmall", height = 16,
    tooltip = { title = "$$", text = L["TIP040"], }, 
  }
  bm.strictrole = KUI:CreateCheckBox(arg, bm)
  bm.strictrole:Catch("OnValueChanged", function(this, evt, val, user)
    if (self:AmIML() and user) then
      self:SendAM("FLTCH", "ALERT", "L", val)
      lootitem.strictrole = val
    end
  end)
  ypos = ypos - 20

  --
  -- Set up the buttons for controlling loot, as well as the scrolling list
  -- of loot itself. First create the frame that will contain the scrolling
  -- list of loot, as it occupies a full frame. Next to that frame we will
  -- have the loot control buttons.
  --
  tr.sframe = MakeFrame("Frame", nil, tr)
  tr.sframe:ClearAllPoints()
  tr.sframe:SetPoint("TOPLEFT", tr, "TOPLEFT", 0, 0)
  tr.sframe:SetPoint("TOPRIGHT", tr, "TOPRIGHT", 0, 0)
  tr.sframe:SetHeight(98)

  arg = {
    name = "KSKBossLootScrollList",
    itemheight = 16,
    newitem = llist_newitem,
    setitem = llist_setitem,
    selectitem = llist_selectitem,
    highlightitem = function(objp, idx, slot, btn, onoff)
      return KUI.HighlightItemHelper(objp, idx, slot, btn, onoff)
    end,
  }
  tr.slist = KUI:CreateScrollList(arg, tr.sframe)
  -- Must expose in self.qf because it is accessed in KKonferSK.lua at the
  -- very least, possibly elsewhere.
  self.qf.lootscroll = tr.slist

  ypos = -100
  arg = {
    x = 0, y = ypos, width = 90, text = L["Open Bids"],
    tooltip = { title = L["TIP052.0"], text = L["TIP052"], },
    enabled = false,
  }
  tr.oclbids = KUI:CreateButton(arg, tr)
  tr.oclbids:Catch("OnClick", function(this, evt, ...)
    open_close_bids(self)
  end)

  arg = {
    x = 100, y = ypos, width = 90, text = L["Open Roll"],
    tooltip = { title = L["TIP053.0"], text = L["TIP053"], },
    enabled = false,
  }
  tr.orpause = KUI:CreateButton(arg, tr)
  tr.orpause:Catch("OnClick", function(this, evt, ...)
    open_roll_or_pause(self)
  end)

  arg = {
    x = 200, y = ypos, width = 90, text = L["Remove"],
    tooltip = { title = L["TIP054.0"], text = L["TIP054"], },
    enabled = false,
  }
  tr.remcancel = KUI:CreateButton(arg, tr)
  tr.remcancel:Catch("OnClick", function(this, evt, ...)
    remove_or_cancel(self)
  end)

  --
  -- Set up the buttons for controlling bidders, as well as the scrolling list
  -- of bidders. First create the frame that will contain the scrolling
  -- list of bidders, as it occupies a full frame. Next to that frame we will
  -- have the bid control buttons.
  --
  bb.sframe = MakeFrame("Frame", nil, bb)
  bb.sframe:ClearAllPoints()
  bb.sframe:SetPoint("TOPLEFT", bb, "TOPLEFT", 0, 0)
  bb.sframe:SetPoint("BOTTOMLEFT", bb, "BOTTOMLEFT", 0, 0)
  bb.sframe:SetWidth(180)

  arg = {
    name = "KSKBiddersScrollList",
    itemheight = 16,
    newitem = function(objp, num)
      return KUI.NewItemHelper(objp, num, "KSKBLBidButton", 155, 16, nil, nil,
        function(this, idx)
          if (not self:AmIML()) then
            return true
          end
        end, nil)
      end,
    setitem = function(objp, idx, slot, btn)
        return KUI.SetItemHelper(objp, btn, idx, function(op, ix)
          return (strfmt("[%d] %s", bidders[ix].pos, shortaclass(bidders[ix])))
        end)
      end,
    selectitem = blist_selectitem,
    highlightitem = function(objp, idx, slot, btn, onoff)
      return KUI.HighlightItemHelper(objp, idx, slot, btn, onoff)
    end,
  }
  bb.slist = KUI:CreateScrollList(arg, bb.sframe)
  qf.bidscroll = bb.slist

  ypos = 0
  local xpos = 190
  arg = {
    x = xpos, y = ypos, width = 100, text = L["Bid"],
    tooltip = { title = L["TIP055.0"], text = L["TIP055"], },
  }
  bb.mybid = KUI:CreateButton(arg, bb)
  bb.mybid:Catch("OnClick", function(this, evt, ...)
    if (rolling) then
      RandomRoll(1, 100)
    elseif (bb.mybid.retract) then
      if (self:AmIML()) then
        self:RetractBidder(K.player.name)
      else
        assert(KRP.master_looter)
        self:SendWhisperAM(KRP.master_looter, "BIDRT", "ALERT", biditem)
      end
    else
      if (self:AmIML()) then
        self:NewBidder(K.player.name)
      else
        assert(KRP.master_looter)
        self:SendWhisperAM(KRP.master_looter, "BIDME", "ALERT", biditem)
      end
    end
  end)
  ypos = ypos - 24

  arg = {
    x = xpos, y = ypos, width = 100, text = L["Force Bid"],
    tooltip = { title = "$$", text = L["TIP056"], },
    enabled = false,
  }
  bb.forcebid = KUI:CreateButton(arg, bb)
  bb.forcebid:Catch("OnClick", function(this, evt, ...)
    if (rolling) then
      RandomRoll(101, 200)
    else
      self:NewBidder(self.cfg.users[memberid].name)
    end
  end)
  ypos = ypos - 24

  arg = {
    x = xpos, y = ypos, width = 100, text = L["Force Retract"],
    tooltip = { title = "$$", text = L["TIP057"], },
    enabled = false,
  }
  bb.forceret = KUI:CreateButton(arg, bb)
  bb.forceret:Catch("OnClick", function(this, evt, ...)
    if (rolling) then
      RandomRoll(1, 1)
    else
      self:RetractBidder(self.cfg.users[selectedbiduid].name)
    end
  end)
  ypos = ypos - 24

  arg = {
    x = xpos, y = ypos, width = 100, text = L["Undo"], enabled = false,
    tooltip = { title = "$$", text = L["TIP058"], },
    enabled = false,
  }
  bb.undo = KUI:CreateButton(arg, bb)
  bb.undo:Catch("OnClick", function(this, evt, ...)
    undo_button(self)
  end)
  ypos = ypos - 24
  qf.undobutton = bb.undo
  self.qf.undobutton = bb.undo

  --
  -- Item editor tab. The left side is the scrolling list of loot items,
  -- and the right hand side contains the options for that item.
  --
  local cf = qf.itemedit
  local ls = cf.vsplit.leftframe
  local rs = cf.vsplit.rightframe
  qf.itemopts = rs

  arg = {
    name = "KSKItemScrollList",
    itemheight = 16,
    newitem = function(objp, num)
        local rf = KUI.NewItemHelper(objp, num, "KSKIListButton", 200, 16,
          nil, nil, function(this, ix)
            this:GetParent():GetParent():SetSelected(ix, false, true)
            return true
          end, nil)
        rf:SetScript("OnEnter", function(this, evt, ...)
          local idx = this:GetID()
          GameTooltip:SetOwner(this, "ANCHOR_BOTTOMLEFT", 0, 25)
          GameTooltip:SetHyperlink(self.cfg.items[self.sorteditems[idx].id].ilink)
          GameTooltip:Show()
        end)
        rf:SetScript("OnLeave", function(this, evt, ...)
          GameTooltip:Hide()
        end)
        return rf
      end,
    setitem = ilist_setitem,
    selectitem = ilist_selectitem,
    highlightitem = function(objp, idx, slot, btn, onoff)
      return KUI.HighlightItemHelper(objp, idx, slot, btn, onoff)
    end,
  }
  ls.ilist = KUI:CreateScrollList(arg, ls)
  qf.itemlist = ls.ilist

  local function reset_uvalues(io)
    io.suicidelist:SetValue("0")
    io.autodel:SetChecked(false)
    io.nextuser:SetText("")
    io.nextdrop:SetChecked(false)
    io.role:SetValue(0)
    classes_setchecked(io, false)
    io.defrank:SetValue(0)
    io.speclist:SetValue("0")
  end

  ypos = 0
  arg = {
    x = 0, y = ypos, label = { text = L["Ignore Item"] },
    tooltip = { title = "$$", text = L["TIP059"], },
    enabled = false,
  }
  rs.ignore = KUI:CreateCheckBox(arg, rs)
  rs.ignore:Catch("OnValueChanged", function(this, evt, val, user)
    local io = qf.itemopts
    if (not val) then
      iinfo.ignore = nil
    else
      local ilink = iinfo.ilink
      iinfo = { ilink = ilink, ignore = true }
      io.autodench:SetChecked(false)
      io.automl:SetChecked(false)
      reset_uvalues(io)
    end
    changed(nil, user)
    if (user) then
      local en = not val
      io.ignorequal:SetEnabled(en)
      io.autodench:SetEnabled(en)
      io.automl:SetEnabled(en)
      enable_uvalues(io, en)
    end
  end)
  ypos = ypos - 16

  arg = {
    x = 0, y = ypos, label = { text = L["Ignore Item Quality"] },
    tooltip = { title = "$$", text = L["TIP097.1"] },
    enabled = false,
  }
  rs.ignorequal = KUI:CreateCheckBox(arg, rs)
  rs.ignorequal:Catch("OnValueChanged", function(this, evt, val, user)
    local io = qf.itemopts
    if (not val) then
      iinfo.ignorequal = nil
    else
      iinfo.ignorequal = true
    end
    changed (nil, user)
  end)
  ypos = ypos - 16

  arg = {
    x = 0, y = ypos, label = { text = L["Auto-assign to Enchanter"] },
    tooltip = { title = "$$", text = L["TIP097"] },
    enabled = false,
  }
  rs.autodench = KUI:CreateCheckBox(arg, rs)
  rs.autodench:Catch("OnValueChanged", function(this, evt, val, user)
    local io = qf.itemopts
    if (not val) then
      iinfo.autodench = nil
    else
      local ilink = iinfo.ilink
      iinfo = { ilink = ilink, autodench = true }
      io.automl:SetChecked(false)
      reset_uvalues(io)
    end
    changed (nil, user)
    if (user) then
      local en = not val
      io.automl:SetEnabled(en)
      io.ignorequal:SetEnabled(en)
      enable_uvalues(io, en)
    end
  end)
  ypos = ypos - 16

  arg = {
    x = 0, y = ypos, label = { text = L["Auto-assign to Master Looter"] },
    tooltip = { title = "$$", text = L["TIP098"] },
    enabled = false,
  }
  rs.automl = KUI:CreateCheckBox(arg, rs)
  rs.automl:Catch("OnValueChanged", function(this, evt, val, user)
    local io = qf.itemopts
    if (not val) then
      iinfo.automl = nil
    else
      iinfo.automl = true
      io.autodench:SetChecked(false)
      reset_uvalues(io)
    end
    changed (nil, user)
    if (user) then
      local en = not val
      io.autodench:SetEnabled(en)
      io.ignorequal:SetEnabled(en)
      enable_uvalues(io, en)
    end
  end)
  ypos = ypos - 20

  arg = {
    x = 0, y = ypos, name = "KSKItemSpecificList", dwidth = 200,
    mode = "SINGLE", itemheight = 16, items = KUI.emptydropdown,
    label = { text = L["Roll on Specific List"], pos = "TOP" },
    enabled = false, border = "THIN",
    tooltip = { title = "$$", text = L["TIP060"], },
  }
  rs.speclist = KUI:CreateDropDown(arg, rs)
  rs.speclist:SetValue("0")
  rs.speclist:Catch("OnValueChanged", function(this, evt, newv, user)
    changed(nil, user)
    iinfo.list = newv
  end)
  --
  -- The list items are updated by self:RefreshAllLists() in KSK-Lists.lua.
  -- This in turn calls self:RefreshItemList() below.
  --
  qf.itemlistdd = rs.speclist
  ypos = ypos - 48

  arg = {
    x = 0, y = ypos, name = "KSKItemRankDropdown",
    dwidth = 200, mode = "SINGLE", itemheight = 16, items = KUI.emptydropdown,
    label = { text = L["Initial Guild Rank Filter"], },
    enabled = false, border = "THIN",
    tooltip = { title = "$$", text = L["TIP061"], },
  }
  rs.defrank = KUI:CreateDropDown(arg, rs)
  -- Must remain visible in self.qf so it can be updated from main.
  self.qf.itemrankdd = rs.defrank
  rs.defrank:Catch("OnValueChanged", function (this, evt, nv, user)
    changed(nil, user)
    iinfo.rank = nv
  end)
  ypos = ypos - 48

  arg = {
    x = 0, y = ypos, text = L["Class Restriction"],
    font = "GameFontNormal",
  }
  rs.cflabel = KUI:CreateStringLabel(arg, rs)
  ypos = ypos - 16

  arg = {
    x = 0, y = ypos, label = { text = K.IndexClass[K.CLASS_WARRIOR].c },
    font = "GameFontHighlightSmall", height = 16,
    enabled = false,
  }
  rs.warrior = KUI:CreateCheckBox(arg, rs)
  rs.warrior:Catch("OnValueChanged", function(this, evt, val, user)
    iclass_filter_func(this, evt, val, K.CLASS_WARRIOR, user)
  end)

  arg = {
    x = 120, y = ypos, label = { text = K.IndexClass[K.CLASS_PALADIN].c },
    font = "GameFontHighlightSmall", height = 16,
    enabled = false,
  }
  rs.paladin = KUI:CreateCheckBox(arg, rs)
  rs.paladin:Catch("OnValueChanged", function(this, evt, val, user)
    iclass_filter_func(this, evt, val, K.CLASS_PALADIN, user)
  end)
  ypos = ypos - 16

  arg = {
    x = 0, y = ypos, label = { text = K.IndexClass[K.CLASS_HUNTER].c },
    font = "GameFontHighlightSmall", height = 16,
    enabled = false,
  }
  rs.hunter = KUI:CreateCheckBox(arg, rs)
  rs.hunter:Catch("OnValueChanged", function(this, evt, val, user)
    iclass_filter_func(this, evt, val, K.CLASS_HUNTER, user)
  end)

  arg = {
    x = 120, y = ypos, label = { text = K.IndexClass[K.CLASS_SHAMAN].c },
    font = "GameFontHighlightSmall", height = 16,
    enabled = false,
  }
  rs.shaman = KUI:CreateCheckBox(arg, rs)
  rs.shaman:Catch("OnValueChanged", function(this, evt, val, user)
    iclass_filter_func(this, evt, val, K.CLASS_SHAMAN, user)
  end)
  ypos = ypos - 16

  arg = {
    x = 0, y = ypos, label = { text = K.IndexClass[K.CLASS_DRUID].c },
    font = "GameFontHighlightSmall", height = 16,
    enabled = false,
  }
  rs.druid = KUI:CreateCheckBox(arg, rs)
  rs.druid:Catch("OnValueChanged", function(this, evt, val, user)
    iclass_filter_func(this, evt, val, K.CLASS_DRUID, user)
  end)

  arg = {
    x = 120, y = ypos, label = { text = K.IndexClass[K.CLASS_ROGUE].c },
    font = "GameFontHighlightSmall", height = 16,
    enabled = false,
  }
  rs.rogue = KUI:CreateCheckBox(arg, rs)
  rs.rogue:Catch("OnValueChanged", function(this, evt, val, user)
    iclass_filter_func(this, evt, val, K.CLASS_ROGUE, user)
  end)
  ypos = ypos - 16

  arg = {
    x = 0, y = ypos, label = { text = K.IndexClass[K.CLASS_MAGE].c },
    font = "GameFontHighlightSmall", height = 16,
    enabled = false,
  }
  rs.mage = KUI:CreateCheckBox(arg, rs)
  rs.mage:Catch("OnValueChanged", function(this, evt, val, user)
    iclass_filter_func(this, evt, val, K.CLASS_MAGE, user)
  end)

  arg = {
    x = 120, y = ypos, label = { text = K.IndexClass[K.CLASS_WARLOCK].c },
    font = "GameFontHighlightSmall", height = 16,
    enabled = false,
  }
  rs.warlock = KUI:CreateCheckBox(arg, rs)
  rs.warlock:Catch("OnValueChanged", function(this, evt, val, user)
    iclass_filter_func(this, evt, val, K.CLASS_WARLOCK, user)
  end)
  ypos = ypos - 16

  arg = {
    x = 0, y = ypos, label = { text = K.IndexClass[K.CLASS_PRIEST].c },
    font = "GameFontHighlightSmall", height = 16,
    enabled = false,
  }
  rs.priest = KUI:CreateCheckBox(arg, rs)
  rs.priest:Catch("OnValueChanged", function(this, evt, val, user)
    iclass_filter_func(this, evt, val, K.CLASS_PRIEST, user)
  end)

  arg = {
  x = 120, y = ypos, label = { text = K.IndexClass[K.CLASS_DEATHKNIGHT].c },
  font = "GameFontHighlightSmall", height = 16,
  enabled = false,
  }
  rs.deathknight = KUI:CreateCheckBox(arg, rs)
  rs.deathknight:Catch("OnValueChanged", function(this, evt, val, user)
  iclass_filter_func(this, evt, val, K.CLASS_DEATHKNIGHT, user)
  end)
  

  ypos = ypos - 18

  rs.role = self:CreateRoleListDropdown("ItemRoleFilter", 0, ypos, rs)
  self.item_role = 0
  rs.role:Catch("OnValueChanged", function(this, evt, newv, user)
    changed(nil, user)
    iinfo.role = newv
  end)
  ypos = ypos - 26
  rs.role:SetValue(0)
  rs.role:SetEnabled(false)

  arg = {
    x = 0, y = ypos, label = { text = L["Assign Next Drop to User"] },
    enabled = false,
    tooltip = { title = "$$", text = L["TIP062"], },
  }
  rs.nextdrop = KUI:CreateCheckBox(arg, rs)
  rs.nextdrop:Catch("OnValueChanged", function(this, evt, val, user)
    changed(nil, user)
    local io = qf.itemopts
    io.nextuser:SetEnabled(val)
    io.seluser:SetEnabled(val)
    io.autodel:SetEnabled(val)
    io.suicidelist:SetEnabled(val)
    if (not val) then
      io.nextuser:SetText("")
      io.autodel:SetChecked(false)
      io.suicidelist:SetValue("0")
      iinfo.nextdrop = false
      iinfo.autodel = false
      iinfo.suicide = "0"
      iinfo.nextuser = nil
      hide_popup()
    else
      iinfo.nextdrop = true
      io.autodel:SetChecked(iinfo.autodel)
    end
  end)
  ypos = ypos - 24

  arg = {
    x = 24, y = ypos, border = true, height = 20, width = 150, text = "",
    enabled = false, autosize = false,
  }
  rs.nextuser = KUI:CreateStringLabel(arg, rs)
  qf.ienextuserlbl = rs.nextuser

  arg = {
    x = 180, y = ypos+2, width = 65, height = 24, text = L["Select"],
    enabled = false,
    tooltip = { title = "$$", text = L["TIP063"], },
  }
  rs.seluser = KUI:CreateButton(arg, rs)
  rs.seluser:Catch("OnClick", function(this, evt)
    select_next(self, this)
  end)
  ypos = ypos - 20

  arg = {
    x = 24, y = ypos, label = { text = L["Auto-Remove When Assigned"] },
    enabled = false,
    tooltip = { title = "$$", text = L["TIP064"], },
  }
  rs.autodel = KUI:CreateCheckBox(arg, rs)
  rs.autodel:Catch("OnValueChanged", function(this, evt, val, user)
    changed(nil, user)
    iinfo.autodel = val
  end)
  ypos = ypos - 20

  arg = {
    x = 24, y = ypos, name = "KSKItemUserSuicideList", dwidth = 200,
    mode = "SINGLE", itemheight = 16, items = KUI.emptydropdown,
    label = { text = L["Suicide User on List"], pos = "TOP" },
    enabled = false, border = "THIN",
    tooltip = { title = "$$", text = L["TIP065"], },
  }
  rs.suicidelist = KUI:CreateDropDown(arg, rs)
  rs.suicidelist:Catch("OnValueChanged", function(this, evt, newv, user)
    changed(nil, user)
    iinfo.suicide = newv
  end)
  --
  -- The list items are updated by self:RefreshAllLists() in KSK-Lists.lua.
  -- This in turn calls self:RefreshItemList() below.
  --
  qf.suicidelistdd = rs.suicidelist
  ypos = ypos - 48

  arg = {
    x = 0, y = ypos, text = L["Update"], enabled = false,
  }
  rs.updatebtn = KUI:CreateButton(arg, rs)
  qf.itemupdbtn = rs.updatebtn
  rs.updatebtn:Catch("OnClick", function(this, evt)
    --
    -- Copy from the iinfo structure back to the stored item list in the
    -- configure structure. Do it manually as we check values as we go.
    --
    local ilink = iinfo.ilink
    if (iinfo.ignore) then
      self.cfg.items[selitemid] = { ilink = ilink, ignore = true }
    else
      self.cfg.items[selitemid] = { ilink = ilink }
      local cs = {}
      local ns = 0
      for k,v in pairs(K.IndexClass) do
        local n = tonumber(k)
        if (iinfo.cfilter[k]) then
          cs[n] = "1"
          ns = ns + 1
        else
          cs[n] = "0"
        end
      end
      for k,v in pairs(K.UnsupClasses) do
        local n = tonumber(v)
        cs[n] = "0"
      end
      local fcs = tconcat(cs)
      if (ns > 0) then
        self.cfg.items[selitemid].cfilter = fcs
      end

      if (iinfo.role and iinfo.role ~= 0) then
        self.cfg.items[selitemid].role = iinfo.role
      end

      if (iinfo.list and iinfo.list ~= "" and iinfo.list ~= "0") then
        self.cfg.items[selitemid].list = iinfo.list
      end

      if (iinfo.rank) then
        self.cfg.items[selitemid].rank = iinfo.rank
      end

      if (iinfo.nextdrop and iinfo.nextdrop ~= false and iinfo.nextuser and iinfo.nextuser ~= "" and iinfo.nextuser ~= 0) then
        self.cfg.items[selitemid].user = iinfo.nextuser
        if (iinfo.suicide and iinfo.suicide ~= "0") then
          self.cfg.items[selitemid].suicide = iinfo.suicide
        end
        if (iinfo.autodel) then
          self.cfg.items[selitemid].del = true
        end
      end

      if (iinfo.autodench and iinfo.autodench ~= false) then
        self.cfg.items[selitemid].autodench = true
      end

      if (iinfo.automl and iinfo.automl ~= false) then
        self.cfg.items[selitemid].automl = true
      end
    end
    self:SendCHITM(selitemid, self.cfg.items[selitemid], self.currentid)
    qf.itemupdbtn:SetEnabled(false)
  end)

  arg.x = 100
  arg.text = L["Delete"]
  arg.tooltip = { title = "$$", text = L["TIP066"] }
  rs.deletebtn = KUI:CreateButton(arg, rs)
  qf.itemdelbtn = rs.deletebtn
  rs.deletebtn:Catch("OnClick", function(this, evt)
    self:DeleteItem(selitemid)
  end)
  ypos = ypos - 24

  --
  -- History tab. We have a header, then the rest of the panel is a big
  -- scrolling list of loot history.
  --
  local cf = qf.history
  local tf = cf.hsplit.topframe
  local bf = cf.hsplit.bottomframe
  ypos = 0

  --
  -- Do the buttons at the bottom first
  --
  arg = {
    x = 0, y = ypos, width = 85, text = L["Clear All"],
    tooltip = { title = "$$", text = L["TIP067"], },
  }
  bf.clearall = KUI:CreateButton(arg, bf)
  bf.clearall:Catch("OnClick", function(this, evt, ...)
    self.cfg.history = {}
    self:RefreshHistory()
  end)

  arg = {
    x = 85, y = ypos, width = 195, text = L["Clear all except last week"],
    tooltip = { title = "$$", text = L["TIP068"], },
  }
  bf.clearweek = KUI:CreateButton(arg, bf)
  bf.clearweek:Catch("OnClick", function(this, evt, ...)
    local now = K.time()
    local cutoff = now - 604800 -- One week in seconds
    local i = 1
    while (i <= #self.cfg.history) do
      local te = self.cfg.history[i]
      if (te[HIST_WHEN] < cutoff) then
        tremove(self.cfg.history, i)
      else
        i = i + 1
      end
    end
    self:RefreshHistory()
  end)

  arg = {
    x = 280, y = ypos, width = 200, text = L["Clear all except last month"],
    tooltip = { title = "$$", text = L["TIP069"], },
  }
  bf.clearmonth = KUI:CreateButton(arg, bf)
  bf.clearmonth:Catch("OnClick", function(this, evt, ...)
    local now = K.time()
    local cutoff = now - 2678400 -- One month in seconds
    local i = 1
    while (i <= #self.cfg.history) do
      local te = self.cfg.history[i]
      if (te[HIST_WHEN] < cutoff) then
        tremove(self.cfg.history, i)
      else
        i = i + 1
      end
    end
    self:RefreshHistory()
  end)
  ypos = ypos - 24

  arg = {
    x = 50, y = ypos, text = L["Export as XML"], width = 180,
    tooltip = { title = "$$", text = L["TIP070.1"], },
  }
  bf.export = KUI:CreateButton(arg, bf)
  bf.export:Catch("OnClick", function(this, evt, ...)
    export_history_button(self, HIST_EXP_XML)
  end)

  arg = {
    x = 250, y = ypos, text = L["Export as JSON"], width = 180,
    tooltip = { title = "$$", text = L["TIP070.2"], },
  }
  bf.export = KUI:CreateButton(arg, bf)
  bf.export:Catch("OnClick", function(this, evt, ...)
    export_history_button(self, HIST_EXP_JSON)
  end)

  arg = {
    x = 0, y = 0, text = L["When"], font = "GameFontNormalSmall",
  }
  tf.str1 = KUI:CreateStringLabel(arg, tf)

  arg.x = 75
  arg.text = L["What"]
  tf.str2 = KUI:CreateStringLabel(arg, tf)

  arg.x = 228
  arg.text = L["Who"]
  tf.str3 = KUI:CreateStringLabel(arg, tf)

  arg.x = 330
  arg.text = L["How"]
  tf.str4 = KUI:CreateStringLabel(arg, tf)

  tf.sframe = MakeFrame("Frame", nil, tf)
  tf.sframe:ClearAllPoints()
  tf.sframe:SetPoint("TOPLEFT", tf, "TOPLEFT", 0, -18)
  tf.sframe:SetPoint("BOTTOMRIGHT", tf, "BOTTOMRIGHT", 0, 0)

  arg = {
    name = "KSKHistoryScrollList",
    itemheight = 16,
    newitem = hlist_newitem,
    setitem = hlist_setitem,
    selectitem = function(objp, idx, slot, btn, onoff) return end,
    highlightitem = function(objp, idx, slot, btn, onoff)
      return KUI.HighlightItemHelper(objp, idx, slot, btn, onoff)
    end,
  }
  tf.slist = KUI:CreateScrollList(arg, tf.sframe)
  qf.histscroll = tf.slist
end

function ksk:RefreshItemList()
  local kids = { qf.itemopts:GetChildren() }
  for k,v in pairs(kids) do
    if (v.SetEnabled) then
      v:SetEnabled(false)
    end
  end
  qf.itemopts.cflabel:SetEnabled(true)

  local vt = {}
  local olditem = selitemid or 0
  local oldidx = nil

  self.sorteditems = {}
  selitemid = nil

  local istr = ""

  for k,v in pairs(self.cfg.items) do
    local ilink = v.ilink
    local iname = strmatch(v.ilink, ".*|h%[(.*)%]|h")
    local ent = { id = k, link = ilink }
    vt[k] = strlower(iname)
    tinsert(self.sorteditems, ent)
  end
  tsort(self.sorteditems, function(a,b)
    return vt[a.id] < vt[b.id]
  end)
  vt = nil

  for k,v in pairs(self.sorteditems) do
    if (v.id == olditem) then
      oldidx = k
      break
    end
  end

  qf.itemlist.itemcount = self.cfg.nitems
  qf.itemlist:UpdateList()
  qf.itemlist:SetSelected(oldidx, true, true)
end

--
-- Refreshes the bid scroll list. Attempts to preserve the currently selected
-- bidder. Checks to make sure that all bidders are actually members of the
-- current list, as this could have changed. Removes any bidders that aren't.
--
local function refresh_bidders(self)
  local olduid = selectedbiduid or nil

  selectedbidder = nil
  selectedbiduid = nil

  qf.bidscroll.itemcount = 0
  if (bidders) then
    local newbidders = {}
    local ll = self.cfg.lists[lootlistid]

    for k,v in ipairs(bidders) do
      local ison, _, pos = self:UserOrAltInList(v.uid, lootlistid, nil)

      if (ison) then
        v.pos = pos
        tinsert(newbidders, v)
      end
    end

    bidders = newbidders
    qf.bidscroll.itemcount = #bidders

    if (olduid) then
      for k,v in ipairs(bidders) do
        if (v.uid == olduid) then
          selectedbidder = k
          break
        end
      end
    end
  end

  qf.bidscroll:UpdateList()
  qf.bidscroll:SetSelected(selectedbidder, true, true)
end

function ksk:RefreshLootMembers()
  local oldmember = memberid or nil
  local oldidx = nil

  memberid = nil
  members = nil

  if (lootlistid) then
    local lootlist = self.cfg.lists[lootlistid]

    if (lootlist.nusers > 0) then
      members = {}
      for k,v in ipairs(lootlist.users) do
        local usr = self.cfg.users[v]

        if (self.users and self.cfg.settings.hide_absent) then
          if (self.users[v]) then
            tinsert(members, {id = v, idx = k})
          end
        else
          tinsert(members, {id = v, idx = k})
        end

        if (lootlist.tethered and usr.alts) then
          for kk,vv in pairs(usr.alts) do
            if (self.users and self.cfg.settings.hide_absent) then
              if (self.users[vv]) then
                tinsert(members, {id = vv, idx = k, isalt = true, main = v})
              end
            else
              tinsert(members, {id = vv, idx = k, isalt = true, main = v})
            end
          end
        end
      end

      for k,v in ipairs(members) do
        if (v.id == oldmember) then
          oldidx = k
          break
        end
      end
    end
  end

  if (members) then
    qf.members.itemcount = #members
  else
    qf.members.itemcount = 0
  end
  qf.members:UpdateList()

  qf.members:SetSelected(oldidx, true, true)
  refresh_bidders(self)
end

function ksk:ResetBidList()
  bidders = nil
  selectedbidder = nil
  selectedbiduid = nil
  qf.bidscroll.itemcount = 0
  qf.bidscroll:UpdateList()
  qf.bidscroll:SetSelected(nil, false, true)
  qf.bidders.mybid:SetText(L["Bid"])
  qf.bidders.mybid.retract = nil
end

function ksk:ResetBidders(send)
  if (self:AmIML() and send and biditem) then
    self:SendAM("BIDCL", "ALERT", biditem)
  end

  self:ResetBidList()

  biditem = nil

  qf.lootwin.oclbids:SetText(L["Open Bids"])
  qf.lootwin.orpause:SetText(L["Open Roll"])
  qf.lootwin.remcancel:SetText(L["Remove"])
  lootbid_setenabled(false)
  qf.bidders.mybid:SetEnabled(false)
  qf.bidders.forcebid:SetEnabled(false)
  qf.bidders.forceret:SetEnabled(false)
end

function ksk:RefreshBossLoot(idx)
  self.qf.lootscroll.itemcount = 0
  if (self.bossloot) then
    self.qf.lootscroll.itemcount = #self.bossloot
  end
  self.qf.lootscroll:UpdateList()
  self.qf.lootscroll:SetSelected(idx, true, true)
end

function ksk:ResetBossLoot()
  self:EndOpenRoll()
  self:ResetBidders(true)
  selectedloot = nil
  lootitem = nil
  self.bossloot = nil
  self:RefreshBossLoot(nil)
  lootrules_setenabled(self, false)
  lootbid_setenabled(false)
  select_alf(ALF_LOOT)
end

function ksk:SelectLootListByID(list)
  local lid = nil

  for k,v in ipairs(self.sortedlists) do
    if (v.id == list) then
      lid = k
      break
    end
  end

  if (lootlistid ~= list) then
    qf.lists:SetSelected(lid, true, true)
  end

  if (lid) then
    return true
  else
    return false
  end
end

--
-- Called by the OnClick handler for the loot list. Also called from the
-- comms module in response to an LISEL. Sets up selectedloot and lootitem.
-- Because this can be called from comms, this is the wrong place to enable
-- or disable the loot buttons. The enabling of the loot control buttons
-- should be done in the onclick handler, which is only run by the ML.
--
function ksk:SelectLootItem(idx, filter, role, list, rank)
  local loot = self.bossloot[idx]

  selectedloot = idx
  lootitem = { idx = idx, filter = filter, role = role, list = list, rank = rank, loot = loot }

  self.qf.lootscroll:SetSelected(idx, true, true)

  --
  -- If the item specified a specific list, then select that list now.
  --
  if (list and list ~= "0") then
    if (not self:SelectLootListByID(list)) then
      if (self:AmIML()) then
        err("item %s wanted non-existent list %q", loot.ilink, tostring(list))
      end
      list = lootlistid
      lootitem.list = list
    end
  end

  lootitem.strictarmor = self.cfg.lists[list].strictcfilter
  lootitem.strictrole = self.cfg.lists[list].strictrfilter

  -- Set up the various filters
  set_classes_from_filter(filter)
  qf.lootrules.role:SetValue(role)
  qf.lootrules.rank:SetValue(rank)

  qf.bidders.mybid:SetText(L["Bid"])
  qf.bidders.mybid.retract = nil
  qf.bidders.forcebid:SetText(L["Force Bid"])
  qf.bidders.forceret:SetText(L["Force Retract"])

  -- Everything else is only relevant to the master looter.
  if (not self:AmIML()) then
    lootrules_setenabled(self, false)
    lootbid_setenabled(false)
    return
  end

  --
  -- Before we set up the bidding buttons, check to see if the item is
  -- intended to be auto-looted to a given user (if that user is in the
  -- raid). If so, give the ML the opportunity to confirm the looting,
  -- and if they verify it, assign the item now and remove it from the
  -- list of items to be bid on.
  local autoloot = false
  local uname = nil

  if (loot.slot and selitemid and self.cfg.items[selitemid]) then
    local ii = self.cfg.items[selitemid]
    if (ii.user and self.users and self.users[ii.user]) then
      uname = self.users[ii.user]
      if (KLD.items[loot.slot].candidates[uname]) then
        autoloot = true
      end
    end

    if (autoloot) then
      local cuser = shortclass(self.cfg.users[ii.user])
      local ts = strfmt(L["AUTOASSIGN"], cuser, cuser)

      if (ii.suicide) then
        ts = ts .. " " .. strfmt(L["AUTOSUICIDE"], cuser, white(self.cfg.lists[ii.suicide].name))
      end

      set_autoloot_win(uname) -- Changes to ALF_CONFIRM
      lootrules_setenabled(self, false)
      lootbid_setenabled(false)
      qf.autoassign_msg:SetText(ts)
      qf.autoloot.autodel = ii.del
      qf.autoloot.announce = true
      return
    end
  end

  lootrules_setenabled(self, true)
  lootbid_setenabled(true)
  qf.bidders.mybid:SetEnabled(false)
end

function ksk:RemoveItemByIdx(idx, nocmd)
  self.qf.lootscroll:SetSelected(nil, false, true)

  if (selectedloot == idx) then
    selectedloot = nil
    lootitem = nil
  end

  tremove(self.bossloot, idx)
  self.qf.lootscroll.itemcount = #self.bossloot
  self.qf.lootscroll:UpdateList()
  self.qf.lootscroll:SetSelected(nil, false, true)

  if (not nocmd) then
    self:SendAM("BIREM", "ALERT", idx)
  end
end

function ksk:OpenBid(idx)
  biditem = idx
  bidders = {}
  qf.bidscroll.itemcount = 0
  qf.bidscroll:UpdateList()
  qf.bidscroll:SetSelected(nil, false, true)
  qf.bidders.mybid:SetText(L["Bid"])
  qf.bidders.mybid:SetEnabled(true)
end

--
-- Called when either a user whispers us the word bid or when the user presses
-- the bid button in their UI (and we receieved the message via the addon
-- channel). This verifies that the user is eligible to bid on the current
-- item and that they meet the filter requirements. If the bidder is allowed
-- to bid, sends the NUBID message to the raid so other people watching bidders
-- can see who is bidding (it adds them to the bidders list in the correct
-- order). If the user fails any of the filter requirements or is not eligible
-- to receive loot, whisper them that fact (and why).
--
function ksk:NewBidder(u)
  -- First check. Am I the master looter?
  if (not self:AmIML()) then
    if (KRP.master_looter) then
      self:SendWhisper(strfmt(L["%s: I am not the master looter - %q is."], L["MODTITLE"], KRP.master_looter), u)
    else
      self:SendWhisper(strfmt(L["%s: I am not the master looter."], L["MODTITLE"]), u)
    end
    return
  end

  -- Second check. Do we even have a current bid going?
  if (not biditem) then
    self:SendWhisper(strfmt(L["%s: there is no item currently open for bids."], L["MODTITLE"]), u)
    return
  end

  local uid = self:FindUser(u)

  if (not uid) then
    self:SendWhisper(strfmt(L["%s: you were not found in the user list. Contact an admin for help."], L["MODTITLE"]), u)
    return
  end

  local usr = self.cfg.users[uid]

  --
  -- Third check. Are they eligible to receive loot?
  -- Need to take into account that we may have no eligible looters because
  -- the raid leader had the wrong loot type set and has just changed it
  -- to master looter.
  --
  local slot = self.bossloot[biditem].slot

  --
  -- If the loot was added manually with /ksk addloot it will have a slot of
  -- 0, which the API never returns. So we need to check for that here and
  -- avoid looking in KLD for the item because it isn't there. The other
  -- alternative is to change the KLD API to allow us to manually add things
  -- to the loot table, but that's more complicated so working around this
  -- for now.
  --
  local klid = nil

  if (slot > 0) then
    klid = KLD.items[slot]

    if (not klid or not klid.candidates[u]) then
      self:SendWhisper(strfmt(L["%s: you are not eligible to receive loot - %s ignored."], L["MODTITLE"], L["bid"]), u)
      return
    end
  end

  local found = false
  for k,v in ipairs(members) do
    if (v.id == uid) then
      found = true
      break
    end
  end

  if (not found) then
    local lootlist = self.cfg.lists[lootlistid]

    info(L["%q attempted to bid on the %q list but is not a member."],
      shortaclass(self.cfg.users[uid]), white(lootlist.name))
    self:SendWhisper(strfmt(L["%s: you are not a member of the %q list - bid ignored."], L["MODTITLE"], lootlist.name), u)
    return
  end

  -- Fourth check. Have they already bid?
  for k,v in pairs(bidders) do
    if (v.uid == uid) then
      self:SendWhisper(strfmt(L["%s: you have already bid on that item. Whisper %s the word %q to retract your bid."], L["MODTITLE"], KRP.master_looter, L["WHISPERCMD_RETRACT"]), u)
      return
    end
  end

  -- Fifth check. Verify the user matches the currently selected class
  -- and role and rank filters. They are individual checks but we clump them together.
  if (not verify_user_class(u, usr.class, L["bid"])) then
    return
  end

  local grprio = 1

  if (self.cfg.cfgtype == KK.CFGTYPE_GUILD and K.player.is_guilded) then
    local gi = K.guild.roster.name[u]
    local ri = K.guild.numranks

    if (gi) then
      ri = K.guild.roster.id[gi].rank
    end

    if (lootitem.rank and lootitem.rank > 0 and (ri > lootitem.rank)) then
      self:SendWhisper(strfmt(L["%s: you do not meet the current guild rank requirement (%q) - %s ignored."], L["MODTITLE"], K.guild.ranks[lootitem.rank], L["bid"]), u)
      return
    end

    grprio = self.cfg.settings.rank_prio[ri] or 1
  end

  if (lootitem.strictrole and lootitem.role ~= self.KK.ROLE_UNSET) then
    if (usr.role ~= lootitem.role) then
      if (usr.role ~= self.KK.ROLE_UNSET) then
        self:SendWhisper(strfmt(L["%s: you do not meet the current role requirement (%q). Your current role is %q - %s ignored."], L["MODTITLE"], self.KK.rolenames[lootitem.role], self.KK.rolenames[usr.role], L["bid"]), u)
        return
      else
        info(L["user %q has no role defined - permitting %s."], shortaclass (usr), L["bid"])
      end
    end
  end

  --
  -- All seems to be in order. Register the user's bid. If we have silent
  -- bidding enabled, simply issue a raid message letting people know that
  -- a bid has taken place (but not who has bid). Otherwise, broadcast to the
  -- raid the bidder info so uses can update their mod's view of the bidders.
  --
  self:AddBidder(usr.name, usr.class, 0, uid, grprio,
    self.cfg.cfgtype == KK.CFGTYPE_GUILD and self.cfg.settings.use_ranks, true)
end

function ksk:AddBidder(name, cls, idx, uid, prio, useprio, announce)
  --
  -- Ignore the IDX value passed in and recalculate it from the current
  -- loot members list. Helps prevent a timing issue where a user may
  -- have pressed the bid button before they receive a list change
  -- notification if the ML changes the bid list.
  --
  if (members) then
    for k,v in pairs(members) do
      if (v.id == uid) then
        idx = v.idx
        break
      end
    end
  end

  local ti = { name = name, class = cls, idx = idx, uid = uid, prio = prio }

  tinsert(bidders, ti)
  tsort(bidders, function(a, b)
    if (not useprio) then
      return(a.idx < b.idx)
    end
    if (a.prio < b.prio) then
      return true
    end
    if (a.prio > b.prio) then
      return false
    end
    if (a.idx < b.idx) then
      return true
    end
    return false
  end)

  refresh_bidders(self)

  --
  -- If it was me that was just added as a bidder, change my bid button to
  -- retract in case I want to do that.
  --
  if (name == K.player.name) then
    qf.bidders.mybid:SetText(L["Retract"])
    qf.bidders.mybid.retract = true
  end

  if (self:AmIML()) then
    local lootlist = self.cfg.lists[lootlistid]

    info(strfmt(L["%s %s on %s on the %s list."], shortaclass(name, cls), L["bid"], lootitem.loot.ilink, white(lootlist.name)))
  end

  if (not announce) then
    return
  end

  if (self.cfg.settings.silent_bid) then
    if (self.cfg.settings.ann_bid_progress) then
      self:SendText(strfmt(L["%s: new bid received. Number of bidders: %d."], L["MODTITLE"], #bidders))
    end
  else
    if (self.cfg.settings.ann_bid_progress) then
      self:SendText(strfmt(L["%s: %s (position %d) has bid (highest bidder is %s)."], L["MODABBREV"], K.ShortName(name), idx, K.ShortName(bidders[1].name)))
    end
    self:SendAM("BIDER", "ALERT", name, cls, idx, uid, prio, useprio)
  end
end

function ksk:RetractBidder(u)
  local found = nil

  if (not self:AmIML()) then
    return
  end

  if (rolling) then
    --
    -- If we are rolling for an item and someone retracts, we need to remove
    -- them from the list of rollers.
    --
    return
  end

  for k,v in ipairs(bidders) do
    if (v.name == u) then
      found = k
      break
    end
  end

  if (found) then
    self:DeleteBidder(u, true)
  end
end

function ksk:DeleteBidder(name, announce)
  local class

  if (not bidders) then
    return
  end

  for k,v in ipairs(bidders) do
    if (v.name == name) then
      class = v.class
      tremove(bidders, k)
      break
    end
  end

  refresh_bidders(self)

  --
  -- If it was me that just retracted, change my retract button to
  -- bid in case I want to do that again.
  --
  if (name == K.player.name) then
    qf.bidders.mybid:SetText(L["Bid"])
    qf.bidders.mybid.retract = nil
  end

  if (not class) then
    return
  end

  if (self:AmIML()) then
    local lootlist = self.cfg.lists[lootlistid]

    info(strfmt(L["%s %s on %s on the %s list."], shortaclass(name, class), L["retracted"], lootitem.loot.ilink, white(lootlist.name)))
  end

  if (not announce) then
    return
  end

  if (self.cfg.settings.silent_bid) then
    if (self.cfg.settings.ann_bid_progress) then
      self:SendText(strfmt(L["%s: bid retracted. Number of bidders: %d."], L["MODTITLE"], #bidders))
    end
  else
    if (qf.bidscroll.itemcount > 0) then
      if (self.cfg.settings.ann_bid_progress) then
        self:SendText(strfmt(L["%s: %s has retracted (highest bidder is %s)."], L["MODABBREV"], name, bidders[1].name))
      end
    else
      if (self.cfg.settings.ann_bid_progress) then
        self:SendText(strfmt(L["%s: %s has retracted (no other bidders)."], L["MODABBREV"], name))
      end
    end
    self:SendAM("BIDRM", "ALERT", name)
  end
end

function ksk:SuicideUser(listid, rlist, uid, cfgid, ilink, chain)
  local cfgid = cfgid or self.currentid
  local ll = self.configs[cfgid].lists[listid]

  local ia, ruid = self:UserIsAlt(uid, nil, cfgid)

  if (not ia or not ll.tethered) then
    ruid = uid
  end

  self:SuicideUserLowLevel(listid, rlist, ruid, cfgid, ilink)
  self:AddEvent(cfgid, "SULST", listid, ruid, tconcat(rlist, ""))

  if (chain) then
    if (ll.extralist and ll.extralist ~= "0") then
      local trlist = self:CreateRaidList(ll.extralist)
      self:SuicideUserLowLevel(ll.extralist, trlist, ruid, cfgid, ilink)
      self:AddEvent(cfgid, "SULST", ll.extralist, ruid, tconcat(trlist, ""))
    end
  end
end

function ksk:DeleteItem(itemid, cfgid, nocmd)
  local cfg = cfgid or self.currentid

  if (not self.configs[cfg]) then
    return
  end

  local il = self.configs[cfg].items
  if (not il[itemid]) then
    return
  end

  il[itemid] = nil
  self.configs[cfg].nitems = self.configs[cfg].nitems - 1
  if (cfg == self.currentid) then
    if (itemid == selitemid) then
      selitemid = nil
    end
    self:RefreshItemList()
  end

  if (not nocmd) then
    self:AdminEvent(cfg, "RMITM", itemid)
  end
end

function ksk:AddItem(itemid, itemlink, cfgid, nocmd)
  local cfg = cfgid or self.currentid

  if (not self.configs[cfg]) then
    return
  end

  local il = self.configs[cfg].items
  if (il[itemid]) then
    return
  end

  local ifs = K.GetItemClassFilter(itemlink)
  if (ifs == K.classfilters.allclasses) then
    local _, _, _, _, _, _, _, _, slot, _, _, icls, isubcls = GetItemInfo(itemlink)
    if (icls == K.classfilters.weapon) then
      ifs = K.classfilters.weapons[isubcls]
    elseif (icls == K.classfilters.armor) then
      ifs = K.classfilters.strict[isubcls]
      if (slot == "INVTYPE_CLOAK") then
        ifs = K.classfilters.relaxed[isubcls]
      end
    end
  end

  il[itemid] = { ilink = itemlink, cfilter = ifs }
  self.configs[cfg].nitems = self.configs[cfg].nitems + 1

  if (not nocmd) then
    self:AdminEvent(cfg, "MKITM", itemid, itemlink)
  end

  if (cfg == self.currentid) then
    self:RefreshItemList()
  end
end

function ksk:RefreshHistory()
  qf.histscroll.itemcount = 0

  if (self.cfg.history) then
    qf.histscroll.itemcount = #self.cfg.history
  end

  if (qf.histscroll.itemcount > 0) then
    -- Resort the list as we may have receieved new loot info
    tsort(self.cfg.history, function(a, b)
      return a[HIST_WHEN] > b[HIST_WHEN]
    end)
  end
  qf.histscroll:UpdateList()
  qf.histscroll:SetSelected(nil, false, true)
end

function ksk:AddLootHistory(cfg, when, what, who, how, spos, norefresh, nocmd)
  local cfg = cfg or self.currentid
  --
  -- IMPORTANT: If this changes, change KSK-Users.lua too in DeleteUser
  --
  local ts = { tonumber(when), what, who, how, spos }

  if (self.configs[cfg].settings.history) then
    tinsert(self.configs[cfg].history, ts)
  end

  if (not norefresh and cfg == self.currentid) then
    self:RefreshHistory()
  end

  if (not nocmd) then
    self:AdminEvent(cfg, "LHADD", when, what, who, how, spos)
  end
end

function ksk:AddLoot(ilink, nocmd)
  local added = false

  if (self.bossloot) then
    added = true
  end

  self:AddItemToBossLoot(ilink, 1, 0)
  self:RefreshBossLoot(selectedloot)

  if (not added) then
    --
    -- This is the only item. Possibly open the loot window and send out
    -- a faked OLOOT event (if we are sending events)
    --
    if (not nocmd) then
      self:SendAM("OLOOT", "ALERT", K.player.name, "0", false, { { ilink, 1 } })
      if (not self.mainwin:IsVisible()) then
        self.autoshown = true
      end
      self.mainwin:Show()
      self.mainwin:SetTab(self.LOOT_TAB, self.LOOT_ASSIGN_PAGE)
    end
  else
    if (not nocmd) then
      self:SendAM("ALOOT", "ALERT", ilink)
    end
  end
end

function ksk:UndoSuicide(cfg, listid, movers, uid, ilink, nocmd)
  self:AddLoot(ilink, nocmd)
  self:AddLootHistory(cfg, K.time(), ilink, uid, "U", 0)

  local mpos = {}
  for k,v in ipairs(movers) do
    local il, lp = self:UserInList(v, listid)
    assert(il)
    tinsert(mpos, lp)
  end

  --
  -- The movers array has all of the appropriate people that moved, in order,
  -- *before* they moved. But their position is calculated now, which is
  -- *after* the move. The first user in the movers array should always be
  -- the same as uid, and we assert that here. We walk backwards through
  -- the position array moving everyone down one position, and then put
  -- the UID at the top. This effectively undoes the suicide.
  --
  assert(movers[1] == uid)

  local ncount = #movers
  local lu = self.configs[cfg].lists[listid].users

  for i = ncount, 2, -1 do
    lu[mpos[i-1]] = movers[i]
  end

  lu[mpos[ncount]] = uid

  if (cfg == self.currentid) then
    self:RefreshAllMemberLists()
  end

  if (not nocmd) then
    self:AddEvent(cfg, "SUNDO", listid, tconcat(movers, ""), uid, ilink)
  end
end

function ksk:StartOpenRoll(ilink, timeout, allowos)
  local isml = self:AmIML()

  if (isml and biditem) then
    self:SendAM("BIDCL", "ALERT", biditem)
  end

  self:ResetBidList()

  biditem = nil

  lootroll = {}
  lootroll.rollers = {}

  rolling = 1

  qf.bidders.mybid:SetEnabled(true)
  qf.bidders.forcebid:SetEnabled(allowos)
  qf.bidders.forceret:SetEnabled(true)
  qf.bidders.mybid:SetText(L["Roll (main)"])
  qf.bidders.forcebid:SetText(L["Roll (offspec)"])
  qf.bidders.forceret:SetText(L["Cancel Roll"])

  -- Blank out any previous rollers
  for i = 1,5 do
    qf.lootroll["pos"..i]:SetText("")
    qf.lootroll["rem"..i]:SetEnabled(false)
    if (isml) then
      qf.lootroll["rem"..i]:SetShown(true)
    else
      qf.lootroll["rem"..i]:SetShown(false)
    end
  end

  lootroll.timeout = timeout
  lootroll.endtime = GetTime() + timeout + 1

  if (isml) then
    qf.lootroll:RegisterEvent("CHAT_MSG_SYSTEM")
    qf.lootroll:SetScript("OnEvent", function(this, evt, arg1, ...) rlf_onevent(self, this, evt, arg1, ...) end)
    qf.lootroll.timerbar:SetScript("OnUpdate", function() rolltimer_onupdate_ml(self) end)
    self:SendAM("OROLL", "ALERT", lootitem.loot.ilink, timeout, self.cfg.settings.offspec_rolls)
  else
    qf.lootroll.timerbar:SetScript("OnUpdate", rolltimer_onupdate_user)
  end

  select_alf(ALF_ROLL)
end

function ksk:EndOpenRoll(noswitch)
  if (rolling) then
    if (self:AmIML()) then
      self:SendAM("EROLL", "ALERT")
    end
  end

  rolling = nil
  lootroll = nil

  qf.bidders.mybid:SetEnabled(false)
  qf.bidders.forcebid:SetEnabled(false)
  qf.bidders.forceret:SetEnabled(false)

  qf.lootwin.oclbids:SetText(L["Open Bids"])
  qf.lootwin.orpause:SetText(L["Open Roll"])
  qf.lootwin.remcancel:SetText(L["Remove"])
  qf.bidders.mybid:SetText(L["Bid"])
  qf.bidders.forcebid:SetText(L["Force Bid"])
  qf.bidders.forceret:SetText(L["Force Retract"])

  qf.lootroll:UnregisterEvent("CHAT_MSG_SYSTEM")
  qf.lootroll:SetScript("OnEvent", nil)
  qf.lootroll.timerbar:SetScript("OnUpdate", nil)

  local en = false
  if (self:AmIML() and selectedloot) then
    en = true
  end

  qf.lootwin.oclbids:SetEnabled(en)
  qf.lootwin.orpause:SetEnabled(en)
  qf.lootwin.remcancel:SetEnabled(en)

  if (not noswitch) then
    select_alf(ALF_LOOT)
  end
end

function ksk:ChangeLootFilter(what, v1, v2)
  if (what == "C") then
    local w = K.IndexClass[v1].w
    qf.lootrules[w]:SetChecked(v2)
  elseif (what == "R") then
    qf.lootrules.role:SetValue(v1)
  elseif (what == "G") then
    qf.lootrules.rank:SetValue(v1)
  elseif (what == "A") then
    qf.lootrules.strictarmour:SetChecked(v1)
  elseif (what == "L") then
    qf.lootrules.strictrole:SetChecked(v1)
  end
end

--
-- Called when the list of possible loot lists has changed. We will need to
-- change any dropdowns that contain a list of lists, as well as the list
-- scroll itself. If the current list that is selected has been removed we
-- will need to clear the members list and bidders list too.
--
function ksk:RefreshLootLists(llist, reset)
  qf.itemlistdd:UpdateItems(llist)
  qf.suicidelistdd:UpdateItems(llist)

  local val

  if (reset) then
    selitemid = nil
  end

  val = "0"
  if (selitemid) then
    val = self.cfg.items[selitemid].speclist or "0"
  end
  qf.itemlistdd:SetValue(val)

  val = "0"
  if (selitemid) then
    val = self.cfg.items[selitemid].suicide or "0"
  end
  qf.suicidelistdd:SetValue(val)

  refresh_loot_lists(self)
end

function ksk:CloseLoot()
  self:EndOpenRoll()
  self:RefreshLootUI(true)
end

function ksk:RefreshLootUI(reset)
  if (reset) then
    lootlistid = nil
    members = nil
    memberid = nil
    selitemid = nil
    lootroll = nil
    selectedbidder = nil
    selectedbiduid = nil

    hide_popup()
    select_alf(ALF_LOOT)

    self:ResetBossLoot()
  end

  refresh_loot_lists(self)
  refresh_bidders(self)
  self:RefreshHistory()
  self:RefreshItemList()
  self:RefreshLootMembers()
  self:RefreshBossLoot(selectedloot)

  if (self.csdata[self.currentid].undo and #self.csdata[self.currentid].undo > 0 and self:AmIML()) then
    qf.undobutton:SetEnabled(true)
  else
    qf.undobutton:SetEnabled(false)
  end
end
