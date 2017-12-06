--[[
   KahLua KonferSK - a suicide kings loot distribution addon.
     WWW: http://kahluamod.com/ksk
     SVN: http://kahluamod.com/svn/konfersk
     IRC: #KahLua on irc.freenode.net
     E-mail: cruciformer@gmail.com
   Please refer to the file LICENSE.txt for the Apache License, Version 2.0.

   Copyright 2008-2010 James Kean Johnston. All rights reserved.

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
local LibDeformat = LibStub:GetLibrary ("LibDeformat-3.0")

if (not K) then
  error ("KahLua KonferSK: could not find KahLua Kore.", 2)
end

if (not LibDeformat) then
  error ("KahLua KonferSK: could not find LibDeformat.", 2)
end

local ksk = K:GetAddon ("KKonferSK")
local L = ksk.L
local KUI = ksk.KUI
local MakeFrame = KUI.MakeFrame

-- Local aliases for global or Lua library functions
local _G = _G
local tinsert = table.insert
local tremove = table.remove
local setmetatable = setmetatable
local tconcat = table.concat
local tsort = table.sort
local tostring = tostring
local GetTime = GetTime
local min = math.min
local max = math.max
local strfmt = string.format
local strsub = string.sub
local strlen = string.len
local strfind = string.find
local strlower = string.lower
local gsub = string.gsub
local xpcall, pcall = xpcall, pcall
local pairs, next, type = pairs, next, type
local select, assert, loadstring = select, assert, loadstring
local printf = K.printf

local ucolor = K.ucolor
local ecolor = K.ecolor
local icolor = K.icolor
local debug = ksk.debug
local info = ksk.info
local err = ksk.err
local white = ksk.white
local class = ksk.class
local aclass = ksk.aclass

--
-- This file contains all of the UI handling code for the loot panel,
-- as well as all loot manipulation functions.
--

local members
local realmemberid
local initdone = false
local iinfo = {}

--
-- Check to see if any of the current raiders are not on the currently
-- selected list.
--
local function check_missing_members ()
  if (not ksk.cfg.settings.ann_missing or not ksk.inraid) then
    return
  end
  local missing = {}

  for k,v in pairs (ksk.raid.members) do
    if (v.unknown) then
      tinsert (missing, aclass (v.unknown))
    else
      if (not ksk:UserInList (v.uid, ksk.lootlistid)) then
        tinsert (missing, aclass (ksk.users[v.uid]))
      end
    end
  end

  if (#missing == 0) then
    return
  end
  info (L["%s: users not on the %q list: %s"], L["MODTITLE"], ksk.lootlist.name, tconcat (missing, ", "))
end

local function changed (res, user)
  if (not user) then
    return
  end

  if (res == nil) then
    res = false
  end
  if (not ksk.itemid) then
    res = true
  end
  if (ksk.qf.itemupdbtn) then
    ksk.qf.itemupdbtn:SetEnabled (not res)
  end
end

local function enable_ui_elements (val)
  if (not initdone) then
    return
  end
  local onoff = (ksk.csd.isadmin ~= nil) and (ksk.isml == true) and val
  ksk.qf.lootrules.warrior:SetEnabled (onoff)
  ksk.qf.lootrules.paladin:SetEnabled (onoff)
  ksk.qf.lootrules.deathknight:SetEnabled (onoff)
  ksk.qf.lootrules.hunter:SetEnabled (onoff)
  ksk.qf.lootrules.shaman:SetEnabled (onoff)
  ksk.qf.lootrules.druid:SetEnabled (onoff)
  ksk.qf.lootrules.monk:SetEnabled (onoff)
  ksk.qf.lootrules.rogue:SetEnabled (onoff)
  ksk.qf.lootrules.mage:SetEnabled (onoff)
  ksk.qf.lootrules.warlock:SetEnabled (onoff)
  ksk.qf.lootrules.priest:SetEnabled (onoff)
  ksk.qf.lootrules.demonhunter:SetEnabled (onoff)
  ksk.qf.lootrules.role:SetEnabled (onoff)
  ksk.qf.lootrules.rank:SetEnabled (onoff)
  ksk.qf.lootrules.nextrank:SetEnabled (onoff)
  ksk.qf.lootrules.strictarmour:SetEnabled (onoff)
  ksk.qf.lootrules.strictrole:SetEnabled (onoff)
end

local function enable_bid_buttons (val)
  if (not initdone) then
    return
  end
  local onoff = (ksk.csd.isadmin ~= nil) and (ksk.isml == true) and val
  ksk.qf.lootwin.oclbids:SetEnabled (onoff)
  ksk.qf.lootwin.orpause:SetEnabled (onoff)
  ksk.qf.lootwin.remcancel:SetEnabled (onoff)
  ksk.qf.bidders.forcebid:SetEnabled (onoff)
  ksk.qf.bidders.forceret:SetEnabled (onoff)
  ksk.qf.bidders.mybid:SetEnabled (onoff)
end

local function verify_user_class (user, class, what)
  local w = K.IndexClass[class].w
  if (not ksk.qf.lootrules[w]:GetChecked ()) then
    local clist = {}
    for k,v in pairs (K.IndexClass) do
      if (v.w) then
        if (ksk.qf.lootrules[v.w]:GetChecked ()) then
          tinsert (clist, v.c)
        end
      end
    end
    ksk.SendWhisper (strfmt (L["%s: you do not meet the current class restrictions (%s) - %s ignored."], L["MODTITLE"], tconcat (clist, ", "), what), user)
    return false
  end
  return true
end

local function set_autoloot_win (name)
  ksk.qf.autoassign_item:SetText (ksk.lootitem.loot.ilink)
  ksk.qf.autoloot.slot = ksk.bossloot[ksk.selectedloot].slot
  ksk.qf.autoloot.target = nil
  if (ksk.qf.autoloot.slot ~= 0) then
    if (ksk.numlooters and ksk.numlooters > 0 and ksk.looters[name]) then
      ksk.qf.autoloot.target = ksk.looters[name].mlidx
    end
  end
  ksk.qf.autoloot.loot = ksk.selectedloot
  ksk.qf.autoloot.announce = false
  ksk.qf.autoloot.leaveloot = false
  ksk.qf.autoloot.denched = false
  ksk.qf.autoloot.rolled = false
  ksk.qf.autoloot.ilink = nil
  ksk.qf.autoloot.uid = nil
  ksk.qf.lootrules:Hide ()
  ksk.qf.lootroll:Hide ()
  ksk.qf.autoloot:Show ()
  ksk.qf.lootwin.oclbids:SetEnabled (false)
  ksk.qf.lootwin.orpause:SetEnabled (false)
  ksk.qf.lootwin.remcancel:SetEnabled (false)
end

--
-- Start an open roll or pause one that is currently in progress. Called when
-- the Open Roll / Pause button is pressed.
--
local function open_roll_or_pause ()
  local tr = ksk.qf.lootwin

  if (ksk.rolling) then
    if (ksk.rolling == 1) then
      local rem = floor (ksk.lootroll.endtime - GetTime()) + 1
      tr.orpause:SetText (L["Resume"])
      ksk.rolling = 2
      if (rem < 6) then
        rem = ksk.cfg.settings.roll_extend + 1
      end
      ksk.lootroll.resume = rem
    else
      local etime = GetTime() + ksk.lootroll.resume
      ksk.lootroll.endtime = etime
      ksk.lootroll.lastwarn = nil
      ksk.lootroll.resume = nil
      tr.orpause:SetText (L["Pause"])
      ksk.rolling = 1
    end
  else
    local sroll = ksk.cfg.settings.suicide_rolls
    if (IsShiftKeyDown ()) then
      sroll = not sroll
    end
    ksk.rolling = 1
    tr.orpause:SetText (L["Pause"])
    tr.remcancel:SetText (K.CANCEL_STR)
    if (sroll) then
      ksk.SendRaidWarning (strfmt (L["Suicide Roll (on list %q) for %s within %d seconds."], ksk.lootlist.name, ksk.lootitem.loot.ilink, ksk.cfg.settings.roll_timeout))
    else
      ksk.SendRaidWarning (strfmt (L["Roll for %s within %d seconds."], ksk.lootitem.loot.ilink, ksk.cfg.settings.roll_timeout))
    end
    if (ksk.settings.ann_roll_usage) then
      if (ksk.settings.offspec_rolls) then
        ksk.SendRaidMsg (strfmt (L["%s: type '/roll' for main spec, '/roll 101-200' for off-spec or '/roll 1-1' to cancel a roll."], L["MODABBREV"]))
      else
        ksk.SendRaidMsg (strfmt (L["%s: type '/roll' for main spec or '/roll 1-1' to cancel a roll."], L["MODABBREV"]))
      end
    end
    ksk.qf.lootrules:Hide ()
    ksk.qf.autoloot:Hide ()
    ksk.qf.lootroll:Show ()
    ksk.qf.lootroll.StartRoll (sroll)
  end
end

local function boe_to_ml_or_de (isroll)
  ksk:ResetBidders (true)
  if (ksk.lootitem.loot.boe) then
    if (ksk.settings.boe_to_ml) then
      ksk:AddLootHistory (nil, ksk:TimeStamp (), ksk.lootitem.loot.ilink, ksk.csd.myuid, "B")
      if (ksk.lootitem.loot.slot ~= 0 and ksk.looters[ksk.mlname]) then
        local tgt = ksk.looters[ksk.mlname].mlidx
        GiveMasterLoot (ksk.lootitem.loot.slot, tgt)
      end
    end
    ksk:RemoveItemByIdx (ksk.selectedloot)
    ksk.SendRaidAM ("BIREM", "ALERT", ksk.selectedloot)
    ksk.qf.lootroll:Hide ()
    ksk.qf.autoloot:Hide ()
    ksk.qf.lootrules:Show ()
    return true
  else
    if (not isroll and ksk.settings.try_roll) then
      open_roll_or_pause ()
      return true
    end
    if (ksk.settings.disenchant) then
      if (#ksk.raid.denchers > 0) then
        --
        -- Must see if the denchers are eligible for loot. They may not
        -- have been present for the boss kill.
        --
        for de = 1, 6 do
          if (ksk.raid.denchers[de]) then
            local thisde = ksk.raid.denchers[de]
            local tname = ksk.users[thisde].name
            local vtarget = false
            local rs = ""
            if (ksk.lootitem.loot.slot == 0 or not ksk.numlooters or not ksk.looters[tname]) then
              rs = "\n\n" .. white (L["Note: player will need to pick item up manually."])
              if (UnitInRange (tname) == 1) then
                vtarget = true
              end
            else
              if (ksk.looters[tname]) then
                vtarget = true
              end
            end
            if (vtarget) then
              local cname = aclass (ksk.users[thisde])
              if (isroll) then
                ksk.qf.autoassign_msg:SetText (strfmt (L["AUTODENCHNR"], cname, cname) .. rs)
              else
                ksk.qf.autoassign_msg:SetText (strfmt (L["AUTODENCH"], cname, cname) .. rs)
              end
              set_autoloot_win (tname)
              ksk.qf.autoloot.uid = thisde
              ksk.qf.autoloot.denched = true
              ksk.qf.autoloot.leaveloot = not isroll
              ksk.qf.autoloot.ilink = ksk.lootitem.loot.ilink
              return true
            end
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
local function auto_loot_ok ()
  local li = ksk.qf.autoloot
  local lh = li.listid
  if (li.slot ~= 0 and li.target) then
    GiveMasterLoot (li.slot, li.target)
  end
  if (li.announce) then
    local pos = ""
    if (li.suicide) then
      local il, lp = ksk:UserInList (li.uid, li.suicide)
      if (il) then
        pos = strfmt ("[%d]", lp)
      end
    end
    if (ksk.settings.ann_winners_raid) then
      ksk.SendRaidMsg (strfmt (L["%s: %s%s (group %d) won %s. Grats!"],
        L["MODABBREV"], li.uname, pos, li.party, li.ilink))
    end
    if (ksk.settings.ann_winners_guild) then
      ksk.SendGuildMsg (strfmt (L["%s: %s%s won %s. Grats!"],
        L["MODABBREV"], li.uname, pos, li.ilink))
    end
  end
  if (li.suicide) then
    lh = li.suicide
    local sulist = ksk:CreateRaidList (li.suicide)
    ksk:SuicideUser (li.suicide, sulist, li.uid, ksk.currentid, li.ilink, true)
    li.suicide = nil
  end
  if (li.autodel) then
    li.autodel = nil
    ksk:DeleteItem (ksk.lootitem.itemid)
  end
  if (li.uid) then
    if (li.denched) then
      lh = "D"
    elseif (li.rolled) then
      lh = "R"
    elseif (not lh) then
      lh = "A"
    end
    ksk:AddLootHistory (nil, ksk:TimeStamp (), li.ilink, li.uid, lh)
  end
  ksk:RemoveItemByIdx (li.loot)
  ksk.SendRaidAM ("BIREM", "ALERT", li.loot)
  ksk:ResetBidders (true)
  ksk.qf.autoloot:Hide ()
  ksk.qf.lootroll:Hide ()
  ksk.qf.lootrules:Show ()
end

--
-- Called when a user presses 'Cancel' in the autoloot panel.
--
local function auto_loot_cancel ()
  local li = ksk.qf.autoloot
  if (not li.announce and not li.leaveloot) then
    if (li.uid) then
      local lh = li.listid
      if (li.denched) then
        lh = "D"
      elseif (li.rolled) then
        lh = "R"
      elseif (not lh) then
        lh = "A"
      end
      ksk:AddLootHistory (nil, ksk:TimeStamp (), li.ilink, li.uid, lh)
    end
    ksk:RemoveItemByIdx (li.loot)
    ksk.SendRaidAM ("BIREM", "ALERT", li.loot)
    ksk:ResetBidders (true)
  end
  ksk.qf.autoloot:Hide ()
  ksk.qf.lootroll:Hide ()
  ksk.qf.lootrules:Show ()
  ksk.qf.lootwin.oclbids:SetEnabled (true)
  ksk.qf.lootwin.orpause:SetEnabled (true)
  ksk.qf.lootwin.remcancel:SetEnabled (true)
end

--
-- OnUpdate script handler for the open roll timer bar. This needs to examine
-- the remaining time, move the bar and set its color accordingly (it changes
-- from green to red gradually as the timeout gets closer and closer) and
-- deals with the timer expiring.
--
local function rolltimer_onupdate()
  local rlf = ksk.qf.lootroll
  if (not ksk.lootroll) then
    rlf.timerbar:SetScript ("OnUpdate", nil)
    return
  end
  if (ksk.rolling == 2) then
    return
  end
  local now = GetTime ()
  if (now > ksk.lootroll.endtime) then
    rlf.timerbar:SetScript ("OnUpdate", nil)
    ksk.rolling = 0
    local topmain = {}
    local topalts = {}
    local nummain = 0
    local numalts = 0
    if (not ksk.lootroll.sorted) then
      ksk.lootroll.sorted = {}
    end
    for i = 1, #ksk.lootroll.sorted do
      local nm = ksk.lootroll.sorted[i]
      local ru = ksk.lootroll.rollers[nm]
      if (ru.minr == 1 and nummain < 5) then
        tinsert (topmain, aclass (nm, ru.class) .. " [" .. ru.roll .. "]")
        nummain = nummain + 1
      elseif (ru.minr == 101 and numalts < 5) then
        tinsert (topalts, aclass (nm, ru.class) .. " [" .. ru.roll .. "]")
        numalts = numalts + 1
      end
    end

    if (nummain > 0 ) then
      info (L["top main spec rollers: %s"], tconcat (topmain, ", "))
    end
    if (numalts > 0 ) then
      info (L["top off-spec rollers: %s"], tconcat (topalts, ", "))
    end
    topmain = nil
    topalts = nil

    local winner = ksk.lootroll.sorted[1]
    if (winner) then
      -- Deal with ties here.
      local nwinners = 1
      local winners = {}
      local winnames = {}
      winners[winner] = ksk.lootroll.rollers[winner].class
      tinsert (winnames, winner)
      local winroll = ksk.lootroll.rollers[winner].roll
      for i = 2, #ksk.lootroll.sorted do
        local nm = ksk.lootroll.sorted[i]
        local ru = ksk.lootroll.rollers[nm]
        if (ru.roll == winroll) then
          winners[nm] = ru.class
          tinsert (winnames, nm)
          nwinners = nwinners + 1
        end
      end

      if (nwinners > 1) then
        if (ksk.settings.ann_roll_ties) then
          ksk.SendRaidMsg (strfmt (L["%s: the following users tied with %d: %s. Roll again."], L["MODABBREV"], winroll, tconcat (winnames, ", ")))
        end
        winnames = nil
        ksk.lootroll.rollers = {}
        ksk.lootroll.sorted = nil
        ksk.lootroll.restrict = winners
        for i = 1,5 do
          rlf["pos"..i]:SetText ("")
          rlf["rem"..i]:SetEnabled (false)
        end
        ksk.lootroll.endtime = GetTime () + ksk.cfg.settings.roll_timeout + 1
        ksk.lootroll.lastwarn = nil
        ksk.rolling = 1
        rlf.timerbar:SetScript ("OnUpdate", rolltimer_onupdate)
        return
      end

      local winclass = ksk.lootroll.rollers[winner].class
      local rid = ksk.raid.players[winner]
      local party = ksk.raid.members[rid].party
      local ilink = ksk.lootitem.loot.ilink
      local uid = ksk.raid.members[rid].uid
      if (ksk.raid.members[rid].unkuser) then
        uid = ksk.raid.members[rid].unkuser.name
      end
      local suicide = nil
      local gpos = ""

      if (ksk.lootroll.suicide and not ksk.raid.members[rid].unkuser) then
        local il, lp = ksk:UserInList (uid, suicide)
        if (il) then
          gpos = strfmt ("[%d]", lp)
        end
        suicide = ksk.lootlistid
        local sulist = ksk:CreateRaidList (ksk.lootlistid)
        ksk:SuicideUser (suicide, sulist, uid, ksk.currentid, ilink, true)
        ksk:AddLootHistory (nil, ksk:TimeStamp (), ilink, uid, suicide)
      end

      local ts = strfmt (L["%s: %s%s (group %d) won %s. Grats!"], L["MODABBREV"], winner, gpos, party, ilink)
      if (ksk.settings.ann_winners_raid) then
        ksk.SendRaidMsg (ts)
      end
      printf (icolor, "%s", ts)
      if (ksk.settings.ann_winners_guild) then
        ksk.SendGuildMsg (strfmt (L["%s: %s%s won %s. Grats!"], L["MODABBREV"], winner, gpos, ilink))
      end

      if (ksk.lootitem.loot.slot ~= 0 and ksk.settings.auto_loot and ksk.numlooters and ksk.numlooters > 0) then
        local cname = aclass (winner, winclass)
        ksk.qf.autoassign_msg:SetText (strfmt (L["AUTOLOOT"], cname, cname, cname))
        set_autoloot_win (winner)
        ksk.qf.autoloot.uid = uid
        ksk.qf.autoloot.rolled = true
        ksk.qf.autoloot.ilink = ilink
        return
      else
        if (not suicide) then
          ksk:AddLootHistory (nil, ksk:TimeStamp (), ilink, uid, "R")
        end
        ksk:RemoveItemByIdx (ksk.selectedloot)
        ksk.SendRaidAM ("BIREM", "ALERT", ksk.selectedloot)
        ksk:ResetBidders (false)
      end
    else -- No winner because no-one rolled
      info (strfmt (L["no-one rolled for %s."], ksk.lootitem.loot.ilink))
      if (boe_to_ml_or_de (true)) then
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
      ksk:RemoveItemByIdx (ksk.selectedloot)
      ksk.SendRaidAM ("BIREM", "ALERT", ksk.selectedloot)
      ksk:ResetBidders (false)
    end

    ksk.qf.lootroll:Hide () -- Calls cleanup in OnHide handler
    ksk.qf.lootrules:Show ()
    return
  end

  local remt = ksk.lootroll.endtime - now
  local warnt = floor(remt)
  local pct = remt / (ksk.cfg.settings.roll_timeout + 1)
  rlf.timerbar:SetStatusBarColor (1-pct, pct, 0)
  rlf.timerbar:SetValue (pct)
  rlf.timertext:SetText (strfmt (L["Roll closing in %s"], ("%.1f)"):format (remt)))
  rlf.timerspark:ClearAllPoints ()
  rlf.timerspark:SetPoint ("CENTER", rlf.timerbar, "LEFT", pct * 200, 0)

  if (warnt < 5) then
    if (not ksk.lootroll.lastwarn or warnt ~= ksk.lootroll.lastwarn) then
      ksk.lootroll.lastwarn = warnt
      if (ksk.settings.ann_countdown) then
        ksk.SendRaidMsg (strfmt (L["%s: roll closing in: %d"], L["MODABBREV"], warnt+1))
      end
    end
  end
end

--
-- This is called when a valid player has typed /roll. 
--
local function player_rolled (player, roll, minr, maxr)
  if (not ksk.rolling) then
    return
  end
  local rp
  if (ksk.lootroll.rollers[player]) then
    --
    -- If they had rolled before but were using a different min and max,
    -- recheck things, as they may be correcting a main spec versus offspec
    -- roll. Seems like /roll 101-200 is really hard for people to do right
    -- the first time!
    --
    rp = ksk.lootroll.rollers[player]
    if ((rp.minr == minr) and (rp.maxr == maxr)) then
      ksk.SendWhisper (strfmt (L["%s: you already rolled %d. New roll ignored."], L["MODTITLE"], ksk.lootroll.rollers[player].roll), player)
      return
    end

    --
    -- We dont actually accept the new roll value. Rather, we either add
    -- or subtract 100 from the original roll, so that the user doesn't
    -- end up with two chances to roll and improve their scrore.
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
    if (ksk.lootroll.restrict) then
      if (not ksk.lootroll.restrict[player]) then
        ksk.SendWhisper (strfmt (L["%s: sorry you are not allowed to roll right now."], L["MODTITLE"]), player)
        return
      end
      class = ksk.lootroll.restrict[player]
      if (minr == 101) then
        minr = 1
        maxr = 100
        roll = roll - 100
      end
    else
      --
      -- Check to see if they are eligible for loot. We may have a case here
      -- where no-one is marked as a master loot candidate because the
      -- raid leader had loot set incorerctly, and subsequently changed it
      -- to master looting. In this case we don't want to block the user
      -- from bidding.
      --
      if (ksk.numlooters and ksk.numlooters > 0 and not ksk.looters[player]) then
        ksk.SendWhisper (strfmt (L["%s: you are not eligible to receive loot - %s ignored."], L["MODTITLE"], L["roll"]), player)
        return
      end

      local uid = ksk:FindUser (player) or "0fff"
      if (uid == "0fff") then
        for k,v in pairs (ksk.missing) do
          if (v.name == player) then
            class = v.class
            break
          end
        end
      else
        class = ksk.users[uid].class
      end

      assert (class)

      --
      -- Verify that they meet the class requirements
      --
      if (not verify_user_class (player, class, L["roll"])) then
        return
      end
    end

    ksk.lootroll.rollers[player] = {}
    rp = ksk.lootroll.rollers[player]
    rp.roll = roll
    rp.minr = minr
    rp.maxr = maxr
    rp.class = class
  end

  --
  -- Create the sorted list of rollers
  --
  ksk.lootroll.sorted = {}
  for k,v in pairs (ksk.lootroll.rollers) do
    if (v.maxr ~= 1) then
      tinsert (ksk.lootroll.sorted, k)
    end
  end
  tsort (ksk.lootroll.sorted, function (a,b)
    if (ksk.lootroll.rollers[a].minr > ksk.lootroll.rollers[b].minr) then
      return false
    elseif (ksk.lootroll.rollers[a].minr < ksk.lootroll.rollers[b].minr) then
      return true
    elseif (ksk.lootroll.rollers[a].roll > ksk.lootroll.rollers[b].roll) then
      return true
    end
    return false
  end)

  --
  -- Display the top 5 in the dialog
  --
  local rlf = ksk.qf.lootroll
  for i = 1,5 do
    rlf["pos"..i]:SetText ("")
    rlf["rem"..i]:SetEnabled (false)
  end
  for i = 1,5 do
    local nm = ksk.lootroll.sorted[i]
    if (nm) then
      local ru = ksk.lootroll.rollers[nm]
      rlf["pos"..i]:SetText (aclass (nm, ru.class) .. " [" .. tostring(ru.roll) .. "]")
      rlf["rem"..i]:SetEnabled (true)
    end
  end

  --
  -- If this roll arrived within 5 seconds of the timeout reset the timeout
  -- back up to 5 seconds.
  --
  local now = GetTime ()
  local rem = floor (ksk.lootroll.endtime - now) + 1
  if (rem < 6) then
    ksk.lootroll.endtime = now + ksk.cfg.settings.roll_extend + 1
  end
end

--
-- Either remove an item or cancel a bid / roll.
--
local function remove_or_cancel ()
  local tr = ksk.qf.lootwin
  if (ksk.rolling) then
    if (ksk.settings.ann_cancel) then
      ksk.SendRaidWarning (strfmt (L["%s: %s cancelled!"], L["MODABBREV"], L["roll"]))
    end
    ksk.rolling = 0
    ksk.qf.lootroll:Hide ()
    ksk.qf.lootrules:Show ()
    ksk.rolling = nil
    return
  end

  if (ksk.biditem) then
    if (ksk.settings.ann_cancel) then
      ksk.SendRaidWarning (strfmt (L["%s: %s cancelled!"], L["MODABBREV"], L["bid"]))
    end
    ksk:ResetBidders (false)
    ksk.qf.lootwin.orpause:SetEnabled (true)
    ksk.SendRaidAM ("BICAN", "ALERT", ksk.biditem)
    return
  end

  if (ksk.selectedloot) then
    ksk:RemoveItemByIdx (ksk.selectedloot)
    ksk.SendRaidAM ("BIREM", "ALERT", ksk.selectedloot)
  end
end

local function rlist_newitem (objp, num)
  local rf = KUI.NewItemHelper (objp, num, "KSKLListButton", 155, 16, nil, nil, nil, nil)
  rf:SetScript ("OnClick", function (this)
    if (not ksk.isml) then
      return
    end
    local idx = this:GetID ()
    if (ksk.lootlistid ~= ksk.sortedlists[idx].id) then
      ksk.lootlistid = ksk.sortedlists[idx].id
      ksk.lootlist = ksk.cfg.lists[ksk.lootlistid]
      this:GetParent():GetParent():SetSelected (idx)
      --
      -- Be careful to only reset bidders when we have actually switched
      -- to a different list by clicking on it.
      --
      ksk:ResetBidList ()
      ksk.SendRaidAM ("LLSEL", "ALERT", ksk.lootlistid, true)
      if ((ksk.biditem or (ksk.lootroll and ksk.lootroll.suicide)) and ksk.settings.ann_bidchanges) then
        ksk.SendRaidWarning (strfmt (L["Bid list changed to %q for %s."], ksk.lootlist.name, ksk.lootitem.loot.ilink))
      end
      check_missing_members ()

    end
  end)
  return rf
end

local function rlist_setitem (objp, idx, slot, btn)
  btn:SetText (ksk.lists[ksk.sortedlists[idx].id].name)
  btn:SetID (idx)
  btn:Show ()
end

local function rlist_selectitem (objp, idx, slot, btn, onoff)
  if (onoff) then
    ksk:RefreshLootMembers ()
    --
    -- If this list has a default rank, set it now, unless its "None".
    -- Otherwise, set it to the global one if its not None.
    --
    if (ksk.lootlist.def_rank and ksk.lootlist.def_rank ~= 999) then
      ksk.qf.lootrules.rank:SetValue (ksk.lootlist.def_rank)
    else
      if (ksk.settings.def_rank and ksk.settings.def_rank ~= 999) then
        ksk.qf.lootrules.rank:SetValue (ksk.settings.def_rank)
      end
    end
    --
    -- Set the strict enforcing options
    --
    ksk.qf.lootrules.strictarmour:SetChecked (ksk.lootlist.strictcfilter)
    ksk.qf.lootrules.strictrole:SetChecked (ksk.lootlist.strictrfilter)
  end
end

local function mlist_newitem (objp, num)
  local bname = "KSKLMListButton" .. tostring(num)
  local rf = MakeFrame ("Button", bname, objp.content)
  local nfn = "GameFontNormalSmallLeft"
  local htn = "Interface/QuestFrame/UI-QuestTitleHighlight"

  rf:SetWidth (155)
  rf:SetHeight (16)
  rf:SetHighlightTexture (htn, "ADD")

  local text = rf:CreateFontString (nil, "ARTWORK", nfn)
  text:ClearAllPoints ()
  text:SetPoint ("TOPLEFT", rf, "TOPLEFT", 8, -2)
  text:SetPoint ("BOTTOMRIGHT", rf, "BOTTOMRIGHT", -48, 2)
  text:SetJustifyH ("LEFT")
  text:SetJustifyV ("TOP")
  rf.text = text

  local si = rf:CreateFontString (nil, "ARTWORK", "GameFontNormalSmall")
  si:ClearAllPoints ()
  si:SetPoint ("TOPLEFT", text, "TOPRIGHT", 0, 0)
  si:SetPoint ("BOTTOMRIGHT", text, "BOTTOMRIGHT", 40, 0)
  si:SetJustifyH ("RIGHT")
  si:SetJustifyV ("TOP")
  rf.indicators = si

  rf.SetText = function (self, txt, ench, frozen, res)
    self.text:SetText (txt)
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
    self.indicators:SetText (st .. is .. et)
  end

  rf:SetScript ("OnClick", function (this)
    if (not ksk.isml) then
      return
    end
    ksk.qf.membersearch:SetText ("")
    ksk.qf.membersearch:ClearFocus ()
    local idx = this:GetID ()
    this:GetParent():GetParent():SetSelected (idx)
  end)

  return rf
end

local function mlist_setitem (objp, idx, slot, btn)
  local uid = members[idx].id
  local ench, frozen, res
  local uc = uid
  local at = strfmt ("%d: ", members[idx].idx)
  local bm = true

  --
  -- If we are tethered, we only care about the main character being frozen
  -- or reserved, but we do care about any of the alts being enchanters.
  -- Also, if we are thethered, then members points to a different array that
  -- has different info we care about.
  --
  if (ksk.cfg.tethered and not ksk.settings.hide_absent) then
    if (members[idx].isalt) then
      uc = members[idx].main
      at = "    - "
      bm = false
    end
  end

  ench = ksk:UserIsEnchanter (uid)
  frozen = ksk:UserIsFrozen (uc) and bm
  res = ksk:UserIsReserved (uc) and bm

  btn:SetText (at .. class (ksk.users[uid]), ench, frozen, res)
  btn:SetID (idx)
  btn:Show ()
end

local function mlist_selectitem (objp, idx, slot, btn, onoff)
  local en = false
  if (onoff) then
    local mid = members[idx].id
    ksk.lootmemberid = members[idx].id
    realmemberid = members[idx].id
    if (ksk.cfg.tethered) then
      if (members[idx].isalt) then
        ksk.lootmemberid = members[idx].main
      end
    end
    en = true
  elseif (onoff == nil) then
    ksk.lootmemberid = nil
    realmemberid = nil
    en = false
  end

  if (initdone and en ~= nil) then
    ksk.qf.bidders.forcebid:SetEnabled (en and (ksk.biditem ~= nil))
  end
end

local function llist_newitem (objp, num)
  local bname = "KSKBLListButton" .. tostring(num)
  local rf = MakeFrame ("Button", bname, objp.content)
  local nfn = "GameFontNormalSmallLeft"
  local htn = "Interface/QuestFrame/UI-QuestTitleHighlight"

  rf:SetWidth (270)
  rf:SetHeight (16)
  rf:SetHighlightTexture (htn, "ADD")

  local text = rf:CreateFontString (nil, "ARTWORK", nfn)
  text:ClearAllPoints ()
  text:SetPoint ("TOPLEFT", rf, "TOPLEFT", 8, -2)
  text:SetPoint ("BOTTOMRIGHT", rf, "BOTTOMRIGHT", -8, 2)
  text:SetJustifyH ("LEFT")
  text:SetJustifyV ("TOP")
  rf.text = text

  rf:SetScript ("OnEnter", function (this, evt, ...)
    if (not ksk.isml or ksk.settings.tooltips) then
      local idx = this:GetID ()
      GameTooltip:SetOwner (this, "ANCHOR_TOPLEFT", 150)
      GameTooltip:SetHyperlink (ksk.bossloot[idx].ilink)
      GameTooltip:Show ()
    end
  end)
  rf:SetScript ("OnLeave", function (this, evt, ...)
    GameTooltip:Hide ()
  end)

  rf.SetText = function (self, txt)
    self.text:SetText (txt)
  end

  rf:SetScript ("OnClick", function (this)
    local idx = this:GetID ()
    if (IsModifiedClick ("CHATLINK")) then
      ChatEdit_InsertLink ( ksk.bossloot[idx].ilink)
      return
    end
    if (not ksk.isml) then
      return
    end
    --
    -- If we have a current bid or roll in progress, ignore this attempt to
    -- change the item. If they want to cancel a bid or roll they can now
    -- press Cancel and that will take care of things.
    --
    if (ksk.rolling or ksk.biditem) then
      return
    end

    --
    -- Ok we have a new loot item. Process it. Note that this could be
    -- the same item that was previously selected. We want to process
    -- it all over again in case they had messed with ranks, armor
    -- class filters etc. By clicking on it we make the assumption the
    -- user wanted to reset everything.
    --
    local loot = ksk.bossloot[idx]
    local itemid = loot.itemid
    local slot = loot.slot
    local cf = nil
    local role = 0
    local slist = nil
    local rank = 999
    if (ksk.iitems[itemid]) then
      local ii = ksk.iitems[itemid]
      cf = ii.cfilter or cf
    end
    if (ksk.items[itemid]) then
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
      local ii = ksk.items[itemid]
      cf = ii.cfilter or cf
      role = ii.role or role
      slist = ii.list or slist
      rank = ii.rank or rank
    end
    if (not slist and ksk.settings.def_list and ksk.settings.def_list ~= "0") then
      slist = ksk.settings.def_list
    end
    if (slist ~= nil) then
      if (rank == 999 and ksk.lists[slist].def_rank and ksk.lists[slist].def_rank ~= 999) then
        rank = ksk.lists[slist].def_rank
      end
      if (rank == 999 and ksk.settings.def_rank and ksk.settings.def_rank ~= 999) then
        rank = ksk.settings.def_rank
      end
    else
      if (ksk.lootlist) then
        slist = ksk.lootlistid
        if (rank == 999) then
          rank = ksk.lootlist.def_rank
        end
      end
    end

    if (not cf) then
      if (ksk.qf.lootrules.strictarmour:GetChecked ()) then
        cf = loot.strict
      else
        cf = loot.relaxed
      end
    end
    if (slot ~= 0) then
      ksk:SetMLCandidates (slot)
    end
    ksk:SelectLootItem (idx, itemid, cf, role, slist, rank)
    ksk.SendRaidAM("LISEL", "ALERT", idx, itemid, cf, role, slist, rank)
    check_missing_members ()
  end)

  return rf
end

local function llist_setitem (objp, idx, slot, btn)
  btn:SetText (ksk.bossloot[idx].ilink)
  btn:SetID (idx)
  btn:Show ()
end

local function llist_selectitem (objp, idx, slot, btn, onoff)
  if (onoff) then
    if (not ksk.selectedloot) then
      return
    end
  elseif (onoff == nil) then
    if (initdone) then
      enable_ui_elements (false)
      enable_bid_buttons (false)
    end
  end
end

local function blist_selectitem (objp, idx, slot, btn, onoff)
  local en = false
  if (onoff) then
    ksk.selectedbidder = idx
    en = true
  else
    ksk.selectedbidder = nil
  end

  if (initdone) then
    ksk.qf.bidders.forceret:SetEnabled (en)
  end
end

local function setup_iinfo ()
  if (ksk.itemid == nil) then
    return
  end

  local dcf = ""
  local ii = ksk.items[ksk.itemid]
  if (ksk.iitems[ksk.itemid]) then
    if (ksk.iitems[ksk.itemid].cfilter) then
      dcf = ksk.iitems[ksk.itemid].cfilter
    end
  end
  iinfo = { ilink = ii.ilink}
  iinfo.cfilter = {}
  local ics = ksk.items[ksk.itemid].cfilter or dcf
  for k,v in pairs (K.IndexClass) do
    local n = tonumber(k)
    if (string.sub (ics, n, n) == "1") then
      iinfo.cfilter[k] = true
    else
      iinfo.cfilter[k] = false
    end
  end
  iinfo.ignore = ii.ignore or false
  iinfo.list = ii.list or "0"
  iinfo.rank = ii.rank or 999
  iinfo.role = ii.role or 0
  iinfo.nextuser = ii.user or nil
  iinfo.nextdrop = iinfo.nextuser ~= nil
  iinfo.autodel = ii.del or false
  iinfo.suicide = ii.suicide or "0"
  iinfo.autodench = ii.autodench or false
  iinfo.automl = ii.automl or false
end

local function ilist_setitem (objp, idx, slot, btn)
  local ilink = ksk.sorteditems[idx].link
  btn:SetText (ilink)
  btn:SetID (idx)
  btn:Show ()
end

local function enable_uvalues (io, en)
  io.speclist:SetEnabled (en)
  io.defrank:SetEnabled (en)
  io.warrior:SetEnabled (en)
  io.paladin:SetEnabled (en)
  io.deathknight:SetEnabled (en)
  io.hunter:SetEnabled (en)
  io.shaman:SetEnabled (en)
  io.druid:SetEnabled (en)
  io.monk:SetEnabled (en)
  io.rogue:SetEnabled (en)
  io.mage:SetEnabled (en)
  io.warlock:SetEnabled (en)
  io.priest:SetEnabled (en)
  io.demonhunter:SetEnabled (en)
  io.role:SetEnabled (en)
  io.nextdrop:SetEnabled (en)
  io.nextuser:SetEnabled (en and iinfo.nextdrop)
  io.seluser:SetEnabled (en and iinfo.nextdrop)
  io.autodel:SetEnabled (en and iinfo.nextdrop)
  io.suicidelist:SetEnabled (en and iinfo.nextdrop)
end

local function ilist_selectitem (objp, idx, slot, btn, onoff)
  local io = ksk.qf.itemopts
  local en = false

  if (onoff) then
    en = true
  end

  local kids = { io:GetChildren () }
  for k,v in pairs (kids) do
    if (v.SetEnabled) then
      v:SetEnabled (en)
    end
  end

  if (onoff) then
    ksk.itemid = ksk.sorteditems[idx].id
    setup_iinfo ()

    if (ksk.popupwindow) then
      ksk.popupwindow:Hide ()
      ksk.popupwindow = nil
    end


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
    enable_uvalues (io, en)
    if (iinfo.nextdrop) then
      slist = iinfo.suicide or "0"
      if (iinfo.nextuser) then
        nuser = aclass(ksk.users[iinfo.nextuser])
      end
    end
    io.autodench:SetChecked (iinfo.autodench)
    io.automl:SetChecked (iinfo.automl)
    if (iinfo.autodench) then
      io.automl:SetEnabled (false)
    end
    if (iinfo.automl) then
      io.autodench:SetEnabled (false)
    end
    io.suicidelist:SetValue (slist)
    io.autodel:SetChecked (iinfo.autodel)
    io.nextuser:SetText (nuser)
    io.nextdrop:SetChecked (iinfo.nextdrop)
    io.role:SetValue (iinfo.role)
    io.priest:SetChecked (iinfo.cfilter[K.CLASS_PRIEST])
    io.warlock:SetChecked (iinfo.cfilter[K.CLASS_WARLOCK])
    io.mage:SetChecked (iinfo.cfilter[K.CLASS_MAGE])
    io.rogue:SetChecked (iinfo.cfilter[K.CLASS_ROGUE])
    io.druid:SetChecked (iinfo.cfilter[K.CLASS_DRUID])
    io.monk:SetChecked (iinfo.cfilter[K.CLASS_MONK])
    io.shaman:SetChecked (iinfo.cfilter[K.CLASS_SHAMAN])
    io.hunter:SetChecked (iinfo.cfilter[K.CLASS_HUNTER])
    io.deathknight:SetChecked (iinfo.cfilter[K.CLASS_DEATHKNIGHT])
    io.paladin:SetChecked (iinfo.cfilter[K.CLASS_PALADIN])
    io.warrior:SetChecked (iinfo.cfilter[K.CLASS_WARRIOR])
    io.demonhunter:SetChecked (iinfo.cfilter[K.CLASS_DEMONHUNTER])
    io.speclist:SetValue (iinfo.list)
    io.defrank:SetValue (iinfo.rank)
    io.ignore:SetChecked (iinfo.ignore)
    io.deletebtn:SetEnabled (true)
    changed (true, true)
  end
end

local function hlist_newitem (objp, num)
  local bname = "KSKHistListButton" .. tostring(num)
  local rf = MakeFrame ("Button", bname, objp.content)
  local nfn = "GameFontNormalSmallLeft"
  local hfn = "GameFontHighlightSmallLeft"
  local htn = "Interface/QuestFrame/UI-QuestTitleHighlight"

  rf:SetWidth (470)
  rf:SetHeight (16)
  rf:SetHighlightTexture (htn, "ADD")

  local when = rf:CreateFontString (nil, "BORDER", nfn)
  when:ClearAllPoints ()
  when:SetPoint ("TOPLEFT", rf, "TOPLEFT", 0, -2)
  when:SetPoint ("BOTTOMLEFT", rf, "BOTTOMLEFT", 0, -2)
  when:SetWidth (70)
  when:SetJustifyH ("LEFT")
  when:SetJustifyV ("TOP")
  rf.when = when

  local what = rf:CreateFontString (nil, "BORDER", nfn)
  what:ClearAllPoints ()
  what:SetPoint ("TOPLEFT", when, "TOPRIGHT", 4, 0)
  what:SetPoint ("BOTTOMLEFT", when, "BOTTOMRIGHT", 4, 0)
  what:SetWidth (170)
  what:SetJustifyH ("LEFT")
  what:SetJustifyV ("TOP")
  rf.what = what

  local who = rf:CreateFontString (nil, "BORDER", nfn)
  who:ClearAllPoints ()
  who:SetPoint ("TOPLEFT", what, "TOPRIGHT", 4, 0)
  who:SetPoint ("BOTTOMLEFT", what, "BOTTOMRIGHT", 4, 0)
  who:SetWidth (100)
  who:SetJustifyH ("LEFT")
  who:SetJustifyV ("TOP")
  rf.who = who

  local how = rf:CreateFontString (nil, "BORDER", nfn)
  how:ClearAllPoints ()
  how:SetPoint ("TOPLEFT", who, "TOPRIGHT", 4, 0)
  how:SetPoint ("BOTTOMLEFT", who, "BOTTOMRIGHT", 4, 0)
  how:SetWidth (110)
  how:SetJustifyH ("LEFT")
  how:SetJustifyV ("TOP")
  rf.how = how

  rf.SetText = function (self, whn, wht, wo, ho)
    self.when:SetText (whn)
    self.what:SetText (wht)
    self.who:SetText (wo)
    self.how:SetText (ho)
    self.whatlink = wht
  end

  rf:SetScript ("OnEnter", function (this, evt, ...)
    if (this.whatlink) then
      GameTooltip:SetOwner (this, "ANCHOR_BOTTOMLEFT", 0, 18)
      GameTooltip:SetHyperlink (this.whatlink)
      GameTooltip:Show ()
    end
  end)

  rf:SetScript ("OnLeave", function (this, evt, ...)
    GameTooltip:Hide ()
  end)

  rf:SetScript ("OnClick", function (this)
    if (IsModifiedClick ("CHATLINK")) then
      ChatEdit_InsertLink (this.whatlink)
    end
  end)

  return rf
end

local function hlist_setitem (objp, idx, slot, btn)
  local hitem = ksk.cfg.history[idx]
  local when,what,who,how = strsplit ("\7", hitem)
  local usr = who
  if (ksk.users[who]) then
    usr = aclass (ksk.users[who])
  else
    local name,cls = strsplit("/", who)
    if (cls) then
      usr = aclass (name, cls)
    end
  end
  local hs
  if (how == "D") then
    hs = L["Disenchanted"]
  elseif (how == "R") then
    hs = L["Won Roll"]
  elseif (how == "B") then
    hs = L["BoE assigned to ML"]
  elseif (how == "A") then
    hs = L["Auto-assigned"]
  elseif (how == "U") then
    hs = L["Undo"]
  else
    if (ksk.lists[how]) then
      hs = strfmt (L["Bid: %s"], white (ksk.lists[how].name))
    else
      hs = strfmt (L["Bid: %s"], white ("???"))
    end
  end

  local ws = strsub (when, 5, 6) .."-" .. strsub (when, 7, 8) .. " " .. strsub (when, 9, 10) .. ":" .. strsub(when, 11,12)

  btn:SetText (ws, what, usr, hs)
  btn:SetID (idx)
  btn:Show ()
end

local function iclass_filter_func (which, evt, val, cls, user)
  changed (nil, user)
  iinfo.cfilter = iinfo.cfilter or {}
  iinfo.cfilter[cls] = val
end

local function class_filter_func (which, evt, val, cls, user)
  ksk.lootitem.cfilter = ksk.lootitem.cfilter or {}
  ksk.lootitem.cfilter[cls] = val
  if (ksk.isml and user) then
    ksk.SendRaidAM ("FLTCH", "ALERT", "C", cls, val)
  end
end

local nextuser_popup
local function select_next(btn, lbl)
  if (not ksk.itemid) then
    return
  end

  if (ksk.popupwindow) then
    ksk.popupwindow:Hide ()
    ksk.popupwindow = nil
  end

  local ulist = {}

  for k,v in pairs (ksk.users) do
    tinsert (ulist, { text = aclass (v), value = k } )
  end
  tsort (ulist, function (a,b)
    return strlower(ksk.users[a.value].name) < strlower(ksk.users[b.value].name)
  end)

  local function pop_func (puid)
    local ulist = nextuser_popup.selectionlist
    changed (nil, true)
    ksk.qf.ienextuserlbl:SetText (aclass (ksk.users[puid]))
    ksk.popupwindow:Hide ()
    ksk.popupwindow = nil
    iinfo.nextdrop = true
    iinfo.nextuser = puid
  end

  if (not nextuser_popup) then
    nextuser_popup = ksk:PopupSelectionList ("KSKNextUserPopup",
      ulist, nil, 220, 400, ksk.mainwin.tabs[ksk.LOOT_TAB].content,
      16, pop_func)
  else
    nextuser_popup:UpdateList (ulist)
  end
  nextuser_popup:ClearAllPoints ()
  nextuser_popup:SetPoint ("TOPLEFT", btn, "TOPRIGHT", 0, nextuser_popup:GetHeight() / 2)
  ksk.popupwindow = nextuser_popup
  nextuser_popup:Show ()
end

--
-- This is what 95% of the mod is all about, the dealing with bids. So I will
-- take a little time here explaining what happens. We can only reach this
-- code if we have a loot item selected. At the time the loot master (LM)
-- starts the loot we assume that the entry conditions for looting have been
-- correctly set (correct roll list, correct armor, role and guild rank
-- filters etc). We also have a list of people who are eligible for loot
-- stored in ksk.looters. The list of people in the raid is in ksk.raid.
-- We create the ksk.currentbid entry and set the number of bidders to the
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
local function open_close_bids ()
  if (ksk.rolling) then
    ksk.rolling = 1
    ksk.lootroll.endtime = GetTime() - 1
    return
  end

  if (ksk.biditem) then
    -- We have an existing bid open. It is now being closed.
    ksk.qf.lootwin.oclbids:SetText (L["Open Bids"])
    ksk.qf.lootwin.remcancel:SetText (L["Remove"])
    ksk.qf.lootwin.orpause:SetEnabled (true)
    ksk.qf.lootwin.remcancel:SetEnabled (true)
    ksk.SendRaidAM ("BIDND", "ALERT", ksk.biditem, timeout)
    ksk.qf.bidders.mybid:SetEnabled (false)
    ksk.qf.bidders.forcebid:SetEnabled (false)
    ksk.qf.bidders.forceret:SetEnabled (false)
    ksk.qf.bidders.mybid:SetText (L["Bid"])
    ksk.qf.bidders.mybid.retract = nil

    --
    -- Lets see if we had any bidders. If we did, the highest one wins and
    -- we suicide them. If not we check the config options for what to do
    -- with the item.
    --
    local n = ksk.qf.bidscroll.itemcount
    if (n > 0) then
      -- We have a winning bidder. Suicide them on the list they won on.
      -- In order to suicide properly we need to build up the ordered list
      -- of users who are in the raid on that list. We also need to include
      -- any users marked as reserved. This gets sent to the whole guild so
      -- all mod users can update their lists, but it is also stored as an
      -- event in the event log, and send to any / all co-admins.
      local sulist = ksk:CreateRaidList (ksk.lootlistid)
      local winname, winuid = ksk.bidders[1].name, ksk.bidders[1].uid
      local wincls = ksk.bidders[1].class
      local party = ksk.raid.members[ksk.raid.users[winuid]].party
      local ilink = ksk.lootitem.loot.ilink
      local gpos = ""
      local il, lp = ksk:UserInList (winuid, ksk.lootlistid)
      if (il) then
        gpos = strfmt ("[%d]", lp)
      end
      ksk:SuicideUser (ksk.lootlistid, sulist, winuid, ksk.currentid, ilink, true)
      ksk:AddLootHistory (nil, ksk:TimeStamp (), ilink, winuid, ksk.lootlistid)

      local ts = strfmt (L["%s: %s%s (group %d) won %s. Grats!"], L["MODABBREV"], winname, gpos, party, ilink) 
      if (ksk.settings.ann_winners_raid) then
        ksk.SendRaidMsg (ts)
      end
      printf (icolor, "%s", ts)
      if (ksk.settings.ann_winners_guild) then
        ksk.SendGuildMsg (strfmt (L["%s: %s%s won %s. Grats!"], L["MODABBREV"], winname, gpos, ilink))
      end

      if (ksk.lootitem.loot.slot ~= 0 and ksk.settings.auto_loot and ksk.numlooters and ksk.numlooters > 0) then
        local cname = aclass (winname, wincls)
        ksk.qf.autoassign_msg:SetText (strfmt (L["AUTOLOOT"], cname, cname, cname))
        set_autoloot_win (winname)
      else
        ksk:RemoveItemByIdx (ksk.selectedloot)
        ksk.SendRaidAM ("BIREM", "ALERT", ksk.selectedloot)
      end
      ksk:ResetBidders (true)
      return
    else
      if (ksk.settings.ann_no_bids) then
        ksk.SendRaidMsg (strfmt (L["%s: no successful bids for %s."], L["MODABBREV"], ksk.lootitem.loot.ilink))
      end
      if (boe_to_ml_or_de ()) then
        return
      end
    end
    ksk:RemoveItemByIdx (ksk.selectedloot)
    ksk.SendRaidAM ("BIREM", "ALERT", ksk.selectedloot)
    ksk:ResetBidders (true)
  else
    if (not ksk.lootlist) then
      return
    end
    -- We are starting a new bid.
    ksk.biditem = ksk.selectedloot
    ksk.bidders = {}
    ksk.qf.bidders.mybid:SetEnabled (true)
    ksk.qf.bidders.forcebid:SetEnabled (realmemberid ~= nil)
    ksk.SendRaidAM ("BIDOP", "ALERT", ksk.biditem, timeout)
    ksk.qf.lootwin.oclbids:SetText (L["Close Bids"])
    ksk.qf.lootwin.remcancel:SetText (K.CANCEL_STR)
    ksk.qf.lootwin.orpause:SetEnabled (false)
    ksk.qf.lootwin.remcancel:SetEnabled (true)
    ksk.SendRaidWarning (strfmt (L["Bids now open for %s on the %q list."], ksk.lootitem.loot.ilink, ksk.lootlist.name))
    if (ksk.settings.ann_bid_usage) then
      ksk.SendRaidMsg (strfmt (L["%s: to bid on %s, whisper %s the word %q. For general help using %s, whisper an admin the word %q."], L["MODABBREV"], ksk.lootitem.loot.ilink, K.player.player, L["WHISPERCMD_BID"], L["MODABBREV"], L["WHISPERCMD_HELP"]))
    end
  end
end

function ksk:MakeCHITM (itemid, ii, cfg, send)
  local es = itemid .. ":"

  if (ii.ignore) then
    es = es .. "Y:::::::::"
  else
    es = es .. "N:"
    if (ii.cfilter) then
      es = es .. ii.cfilter
    end
  end
  es = es .. ":"
  if (ii.role and ii.role ~= 0) then
    es = es .. tostring (ii.role)
  end
  es = es .. ":"
  if (ii.list and ii.list ~= "" and ii.list ~= "0") then
    es = es .. ii.list
  end
  es = es .. ":"
  if (ii.rank and ii.rank ~= 999) then
    es = es .. tostring (ii.rank)
  end
  es = es .. ":"
  if (ii.user) then
    es = es .. ii.user .. ":"
    if (ii.suicide) then
      es = es .. ii.suicide
    end
    es = es .. ":"
    if (ii.del) then
      es = es .. "Y"
    end
  else
    es = es .. "::N"
  end
  es = es .. ":"
  if (ii.autodench) then
    es = es .. "Y"
  end
  es = es .. ":"
  if (ii.automl) then
    es = es .. "Y"
  end

  if (send) then
    ksk.AddEvent (cfg or ksk.currentid, "CHITM", es)
  end
  return es
end

local function export_history_button ()
  if (not ksk.exphistdlg) then
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
      okbutton = { text = K.ACCEPTSTR },
      cancelbutton = { text = K.CANCELSTR },
    }
    local ret = KUI:CreateDialogFrame (arg)

    arg = {
      x = 0, y = ypos, len = 99999,
      label = { text = L["Export string"], pos = "LEFT" },
      tooltip = { title = "$$", text = L["TIP050"], },
    }
    ret.expstr = KUI:CreateEditBox (arg, ret)
    ret.expstr:Catch ("OnValueChanged", function (this, evt, newv)
      this:HighlightText ()
      this:SetCursorPosition (0)
      if (newv ~= "") then
        this:SetFocus ()
        ksk.exphistdlg.copymsg:Show ()
      else
        this:ClearFocus ()
        ksk.exphistdlg.copymsg:Hide ()
      end
    end)
    ypos = ypos - 30

    arg = {
      x = 16, y = ypos, width = 300,
      text = L["Press Ctrl+C to copy the export string"],
    }
    ret.copymsg = KUI:CreateStringLabel (arg, ret)
    ypos = ypos - 24

    ret.OnAccept = function (this)
      ksk.exphistdlg:Hide ()
      ksk.mainwin:Show ()
    end

    ret.OnCancel = function (this)
      ksk.exphistdlg:Hide ()
      ksk.mainwin:Show ()
    end

    ksk.exphistdlg = ret
  end

  local _, mo, dy, yr = CalendarGetDate ()
  local hh, mm = GetGameTime ()
  local dstr = strfmt ("%04d-%02d-%02d", yr, mo, dy)
  local tstr = strfmt ("%02d:%02d", hh, mm)
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

  tinsert (classes, '<c id="00" v="unkclass"/>')
  for k,v in pairs (K.IndexClass) do
    if (v.u) then
      tinsert (classes, strfmt ("<c id=%q v=%q/>", tostring (k), strlower (tostring(v.u))))
    end
  end

  tinsert (llist, strfmt ('<l id="D" n="%s"/>', L["Disenchanted"]))
  tinsert (llist, strfmt ('<l id="R" n="%s"/>', L["Won Roll"]))
  tinsert (llist, strfmt ('<l id="B" n="%s"/>', L["BoE assigned to ML"]))
  tinsert (llist, strfmt ('<l id="A" n="%s"/>', L["Auto-assigned"]))
  tinsert (llist, strfmt ('<l id="U" n="%s"/>', L["Undo"]))
  tinsert (llist, strfmt ('<l id="u" n="???"/>'))
  lul["D"] = true
  lul["R"] = true
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
  for k,v in pairs (iqual) do
    tinsert (iql, strfmt ('<q id=%q v=%q/>', v.id, v.v))
  end

  for k,v in pairs (ksk.cfg.history) do
    local when, what, who, how = strsplit ("\7", v)
    local uid = nil
    local cls = nil
    local name = nil

    if (ksk.users[who]) then
      uid = who
      cls = ksk.users[who].class
      name = ksk.users[uid].name
    else
      name, cls = strsplit ("/", who)
      uid = name
      if (not cls) then
        cls = "00"
      end
    end

    if (not uul[uid]) then
      uul[uid] = true
      tinsert (ulist, strfmt ("<u id=%q n=%q c=%q/>", uid, name, cls))
    end

    if (strlen (how) > 1) then
      if (not ksk.lists[how]) then
        how = "u"
      end
    end

    if (not lul[how]) then
      lul[how] = true
      tinsert (llist, strfmt ("<l id=%q n=%q/>", how, ksk.lists[how].name))
    end

    yr = strsub (when, 1, 4)
    mo = strsub (when, 5, 6)
    dy = strsub (when, 7, 8)
    hh = strsub (when, 9, 10)
    mm = strsub (when, 11, 12)

    local iqv = iqual[strsub (what, 5, 10)].id
    local iname = string.match (what, "|h%[(.*)%]|h")
    local itemid = string.match (what, "item:(%d+)")

    if (not (iil[itemid])) then
      iil[itemid] = true
      tinsert (ilist, strfmt ("<i id=%q n=%q q=%q/>", itemid, iname, iqv))
    end

    tinsert (ehl, strfmt ('<h d="%s-%s-%s" t="%s:%s" id=%q u=%q w=%q/>',
      yr, mo, dy, hh, mm, itemid, uid, how))
  end

  local fstr = strfmt ("<ksk date=%q time=%q><classes>%s</classes><users>%s</users><quals>%s</quals><items>%s</items><lists>%s</lists><history>%s</history></ksk>", dstr, tstr, tconcat (classes, ""), tconcat (ulist, ""), tconcat (iql, ""), tconcat (ilist, ""), tconcat (llist, ""), tconcat (ehl, ""))
  ksk.exphistdlg.expstr:SetText (fstr)

  ksk.mainwin:Hide ()
  ksk.exphistdlg:Show ()
end

local function undo_button ()
  if (not ksk.undodlg) then
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
      okbutton = { text = K.ACCEPTSTR },
      cancelbutton = { text = K.CANCELSTR },
    }
    local ret = KUI:CreateDialogFrame (arg)
    arg = {
      x = 0, y = ypos, text = L["Are you absolutely sure you want to undo this suicide?"],
      autosize = true, font = "GameFontNormal", width = 400,
    }
    ret.str1 = KUI:CreateStringLabel (arg, ret)
    ypos = ypos - 24
    local sypos = ypos
    arg.y = ypos
    arg.width = nil
    arg.text = L["User"]
    arg.autosize = false
    arg.width = 64
    arg.justifyh = "RIGHT"
    ret.str2 = KUI:CreateStringLabel (arg, ret)
    ypos = ypos - 24
    arg.y = ypos
    arg.text = L["List"]
    ret.str3 = KUI:CreateStringLabel (arg, ret)
    ypos = ypos - 24
    arg.y = ypos
    arg.text = L["Item"]
    ret.str4 = KUI:CreateStringLabel (arg, ret)

    ypos = sypos
    arg = {
      x = 70, y = ypos, width = 300, border = true, autosize = false,
      justifyh = "LEFT", height = 20,
    }
    ret.user = KUI:CreateStringLabel (arg, ret)
    ypos = ypos - 24
    arg.y = ypos
    ret.list = KUI:CreateStringLabel (arg, ret)
    ypos = ypos - 24
    arg.y = ypos
    ret.item = KUI:CreateStringLabel (arg, ret)

    ret.OnAccept = function (this)
      ksk.undodlg:Hide ()
      ksk.mainwin:Show ()

      local cid = ksk.currentid
      local csd = ksk.csdata[cid]
      urec = tremove (csd.undo, 1)
      if (#csd.undo < 1) then
        csd.undo = nil
        ksk.qf.undobutton:SetEnabled (false)
      end
      ksk:UndoSuicide (cid, urec.listid, urec.movers, urec.uid, urec.ilink, false)
    end

    ret.OnCancel = function (this)
      ksk.undodlg:Hide ()
      ksk.mainwin:Show ()
    end

    ksk.undodlg = ret
  end

  local cid = ksk.currentid
  if (not ksk.csdata[cid].undo) then
    return
  end
  if (#ksk.csdata[cid].undo < 1) then
    return
  end

  ksk.mainwin:Hide ()
  ksk.undodlg:Show ()

  local ui = ksk.csdata[cid].undo[1]

  ksk.undodlg.user:SetText (aclass (ksk.users[ui.uid]))
  ksk.undodlg.list:SetText (ksk.lists[ui.listid].name)
  ksk.undodlg.item:SetText (ui.ilink)
end

function ksk:InitialiseLootGUI ()
  local arg

  --
  -- Loot tab, Loot Assignment panel.
  --
  local ypos = 0

  local cf = ksk.mainwin.tabs[ksk.LOOT_TAB].tabs[ksk.LOOT_ASSIGN_TAB].content
  local tbf = ksk.mainwin.tabs[ksk.LOOT_TAB].topbar
  local ls = cf.vsplit.leftframe
  local rs = cf.vsplit.rightframe

  arg = {
    inset = 0, height = 128,
    rightsplit = true, name = "KSKLootLSplit", topanchor = true,
  }
  ls.hsplit = KUI:CreateHSplit (arg, ls)
  local tl = ls.hsplit.topframe
  local bl = ls.hsplit.bottomframe

  arg = {
    inset = 0, height = 20, name = "KSKLootLLHSplit", rightsplit = true,
  }
  bl.hsplit = KUI:CreateHSplit (arg, bl)
  local tbl = bl.hsplit.topframe
  local bbl = bl.hsplit.bottomframe

  arg = {
    name = "KSKLootListsScrollList",
    itemheight = 16,
    newitem = rlist_newitem,
    setitem = rlist_setitem,
    selectitem = rlist_selectitem,
    highlightitem = function (objp, idx, slot, btn, onoff)
      return KUI.HighlightItemHelper (objp, idx, slot, btn, onoff)
    end,
  }
  tl.slist = KUI:CreateScrollList (arg, tl)
  ksk.qf.lootlists = tl.slist

  local bdrop = {
    bgFile = KUI.TEXTURE_PATH .. "TDF-Fill",
    tile = true,
    tileSize = 32,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
  }
  tl.slist:SetBackdrop (bdrop)

  arg = {
    name = "KSKLootMembersScrollList",
    itemheight = 16,
    newitem = mlist_newitem,
    setitem = mlist_setitem,
    selectitem = mlist_selectitem,
    highlightitem = function (objp, idx, slot, btn, onoff)
      return KUI.HighlightItemHelper (objp, idx, slot, btn, onoff)
    end,
  }
  tbl.slist = KUI:CreateScrollList (arg, tbl)
  ksk.qf.lootmembers = tbl.slist
  tbl.slist:SetBackdrop (bdrop)

  arg = {
    x = 0, y = 2, len = 16, font = "ChatFontSmall",
    width = 170, tooltip = { title = L["User Search"], text = L["TIP099"] },
  }
  bbl.searchbox = KUI:CreateEditBox (arg, bbl)
  ksk.qf.membersearch = bbl.searchbox
  bbl.searchbox:Catch ("OnEnterPressed", function (this, evt, newv, user)
    this:SetText ("")
  end)
  bbl.searchbox:Catch ("OnValueChanged", function (this, evt, newv, user)
    if (not members) then
      return
    end
    if (user and newv and newv ~= "") then
      local lnv = strlower (newv)
      for k,v in pairs (members) do
        local tln = strlower (ksk.users[v.id].name)
        if (strfind (tln, lnv, 1, true)) then
          local its = v.id
          if (v.isalt) then
            its = v.main
          end
          for kk,vv in ipairs (members) do
            if (vv.id == its) then
              ksk.qf.lootmembers:SetSelected (kk, true)
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
  rs.hsplit = KUI:CreateHSplit (arg, rs)
  local tr = rs.hsplit.topframe
  local br = rs.hsplit.bottomframe
  ksk.qf.lootwin = tr

  arg = {
    inset = 0, height = 180, name = "KSKLootFilterHSplit",
    leftsplit = true, topanchor = true,
  }
  br.hsplit = KUI:CreateHSplit (arg, br)
  local bmf = br.hsplit.topframe
  local bb = br.hsplit.bottomframe

  --
  -- The loot rules frame doubles as both the loot rules and the "popup"
  -- frame when we auto-assign loot to someone. We do this so that we do
  -- not need to hide the main window and the loot master can see who is
  -- in the raid and loot at the loot lists etc. So when we have an item
  -- that is auto-assigned to a user in the item database or when a user
  -- has one a bid and we are auto-assigning loot, we hide the loot rules
  -- window and display the loot assignment window in its place. We need
  -- to be careful when showing the window again however. If the master
  -- looter closes the main KSK window, when they re-open it, we need the
  -- original loot rules window back. They can always assign loot through
  -- the traditional Blizzard interface.
  --
  local bm = MakeFrame ("Frame", nil, bmf)
  bm:ClearAllPoints ()
  bm:SetPoint ("TOPLEFT", bmf, "TOPLEFT", 0, 0)
  bm:SetPoint ("BOTTOMRIGHT", bmf, "BOTTOMRIGHT", 0, 0)

  local alf = MakeFrame ("Frame", nil, bmf)
  alf:ClearAllPoints ()
  alf:SetPoint ("TOPLEFT", bmf, "TOPLEFT", 0, 0)
  alf:SetPoint ("BOTTOMRIGHT", bmf, "BOTTOMRIGHT", 0, 0)
  alf:Hide ()

  local rlf = MakeFrame ("Frame", nil, bmf)
  rlf:ClearAllPoints ()
  rlf:SetPoint ("TOPLEFT", bmf, "TOPLEFT", 0, 0)
  rlf:SetPoint ("BOTTOMRIGHT", bmf, "BOTTOMRIGHT", 0, 0)
  rlf:Hide ()

  ksk.qf.lootrules = bm
  ksk.qf.autoloot = alf
  ksk.qf.lootroll = rlf
  ksk.qf.bidders = bb

  --
  -- Populate the auto-assign frame first. Its pretty simple.
  --
  arg = {
    x = "CENTER", y = 0, height = 24, width = 265, autosize = false,
    font = "GameFontNormal", text = "",
    color = {r = 1, g = 1, b = 1, a = 1 }, border = true,
    justifyh = "CENTER",
  }
  alf.item = KUI:CreateStringLabel (arg, alf)
  ksk.qf.autoassign_item = alf.item

  arg = {
    x = 0, y = 0, width = 1, height = 1, autosize = false,
    color = {r = 1, g = 0, b = 0, a = 1 }, text = "",
    font = "GameFontNormal", justifyv = "TOP",
  }
  alf.str = KUI:CreateStringLabel (arg, alf)
  alf.str:ClearAllPoints ()
  alf.str:SetPoint ("TOPLEFT", alf, "TOPLEFT", 4, -30)
  alf.str:SetPoint ("BOTTOMRIGHT", alf, "BOTTOMRIGHT", -4, 28)
  alf.str.label:SetPoint ("TOPLEFT", alf.str, "TOPLEFT", 0, 0)
  alf.str.label:SetPoint ("BOTTOMRIGHT", alf.str, "BOTTOMRIGHT", 0, 0)
  ksk.qf.autoassign_msg = alf.str

  arg = {
    x = 40, y = -154, width = 90, text = K.OK_STR,
  }
  alf.ok = KUI:CreateButton (arg, alf)
  alf.ok:Catch ("OnClick", function (this, evt, ...)
    auto_loot_ok ()
  end)

  arg = {
    x = 160, y = -154, width = 90, text = K.CANCEL_STR,
  }
  alf.cancel = KUI:CreateButton (arg, alf)
  alf.cancel:Catch ("OnClick", function (this, evt, ...)
    auto_loot_cancel ()
  end)

  --
  -- Next do the loot roll frame, also pretty simple.
  --
  local function rem_onclick (this, evt)
    local w = this.which
    local nm = ksk.lootroll.sorted[w]
    player_rolled (nm, 1, 1, 1)
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
  rlf.pos1 = KUI:CreateStringLabel (arg, rlf)
  rlf.rem1 = KUI:CreateButton (arg2, rlf)
  rlf.rem1.which = 1
  rlf.rem1:Catch ("OnClick", rem_onclick)
  ypos = ypos - 20
  arg.y = ypos
  arg2.y = ypos
  rlf.pos2 = KUI:CreateStringLabel (arg, rlf)
  rlf.rem2 = KUI:CreateButton (arg2, rlf)
  rlf.rem2.which = 2
  rlf.rem2:Catch ("OnClick", rem_onclick)
  ypos = ypos - 20
  arg.y = ypos
  arg2.y = ypos
  rlf.pos3 = KUI:CreateStringLabel (arg, rlf)
  rlf.rem3 = KUI:CreateButton (arg2, rlf)
  rlf.rem3.which = 3
  rlf.rem3:Catch ("OnClick", rem_onclick)
  ypos = ypos - 20
  arg.y = ypos
  arg2.y = ypos
  rlf.pos4 = KUI:CreateStringLabel (arg, rlf)
  rlf.rem4 = KUI:CreateButton (arg2, rlf)
  rlf.rem4.which = 4
  rlf.rem4:Catch ("OnClick", rem_onclick)
  ypos = ypos - 20
  arg.y = ypos
  arg2.y = ypos
  rlf.pos5 = KUI:CreateStringLabel (arg, rlf)
  rlf.rem5 = KUI:CreateButton (arg2, rlf)
  rlf.rem5.which = 5
  rlf.rem5:Catch ("OnClick", rem_onclick)
  ypos = ypos - 20
  arg.y = ypos
  arg2.y = ypos
  arg.border = false
  arg.autosize = true
  arg.color = {r = 1, g = 0, b = 0, a = 1 }
  arg.text = L["Note: only top 5 rolls shown."]
  rlf.str1 = KUI:CreateStringLabel (arg, rlf)
  ypos = ypos - 20

  rlf.timerbarframe = MakeFrame ("Frame", "KSKLootRollTimerFrame", rlf)
  rlf.timerbarframe:ClearAllPoints ()
  rlf.timerbarframe:SetPoint ("TOPLEFT", rlf.str1, "BOTTOMLEFT", 0, -4)
  rlf.timerbarframe:SetWidth (210)
  rlf.timerbarframe:SetHeight (30)
  rlf.timerbarframe:SetBackdrop ( {
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    })
  rlf.timerbarframe:SetBackdropBorderColor (0.4, 0.4, 0.4)
  rlf.timerbarframe:SetBackdropColor (0, 0, 0, 0)

  rlf.timerbar = MakeFrame ("StatusBar", nil, rlf.timerbarframe)
  rlf.timerbar:SetWidth (200)
  rlf.timerbar:SetHeight (20)
  rlf.timerbar:ClearAllPoints ()
  rlf.timerbar:SetPoint ("CENTER", rlf.timerbarframe, "CENTER")
  rlf.timerbar:SetStatusBarTexture ("Interface/TargetingFrame/UI-StatusBar")
  rlf.timerbar:SetStatusBarColor (0, 1, 0)
  rlf.timerbar:SetMinMaxValues (0, 1)

  rlf.timertext = rlf.timerbar:CreateFontString (nil, "OVERLAY", "GameFontNormal")
  rlf.timertext:ClearAllPoints ()
  rlf.timertext:SetPoint ("TOPLEFT", rlf.timerbar, "TOPLEFT", 0, 0)
  rlf.timertext:SetWidth (180)
  rlf.timertext:SetHeight (16)
  rlf.timertext:SetTextColor (1,1,1,1)
  rlf.timertext:SetJustifyH ("CENTER")
  rlf.timertext:SetJustifyV ("MIDDLE")

  rlf.timerspark = rlf.timerbar:CreateTexture (nil, "OVERLAY")
  rlf.timerspark:SetTexture ("Interface/CastingBar/UI-CastingBar-Spark")
  rlf.timerspark:SetBlendMode ("ADD")
  rlf.timerspark:SetWidth (20)
  rlf.timerspark:SetHeight (44)

  local function rlf_onevent (this, evt, arg1, ...)
    if (evt == "CHAT_MSG_SYSTEM") then
      local plr, roll, minr, maxr = LibDeformat.Deformat (arg1, RANDOM_ROLL_RESULT)
      if (plr and (not strfind (plr, "-", 1, true))) then
        local ds = plr .. "-"
        local ss, se
        for k, v in pairs (ksk.raid.members) do
          ss, se = strfind (v.name, ds, 1, true)
          if (ss == 1) then
            plr = v.name
            break
          end
        end
      end
      local player = K.CanonicalName (plr, nil)
      if (player and (not ksk.raid.players[player])) then
        player = nil
      end
      if (player and roll and minr and maxr) then
        if ((minr == 1 and maxr == 100) or
            (ksk.settings.offspec_rolls and (minr == 101 and maxr == 200)) or
            (minr == 1 and maxr == 1)) then
          player_rolled (player, roll, minr, maxr)
        else
          if (ksk.settings.offspec_rolls) then
            ksk.SendWhisper (strfmt (L["%s: invalid roll. Use '/roll' for main spec, '/roll 101-200' for off-spec or '/roll 1-1' to cancel a roll."], L["MODTITLE"]), player)
          else
            ksk.SendWhisper (strfmt (L["%s: invalid roll. Use '/roll' for main spec or '/roll 1-1' to cancel a roll."], L["MODTITLE"]), player)
          end
          return
        end
      end
    end
  end

  rlf.StartRoll = function (sroll)
    --
    -- We want to disable other roll trackers. This is the place to do it.
    -- Currently I only know about LootHog. Add others here.
    --
    ksk.lootroll = {}
    if (loothog_settings) then
      if (loothog_settings["enable"]) then
        if (loothog_turnoff) then
          ksk.lootroll.lhdisabled = true
          loothog_turnoff()
        end
      end
    end

    -- Blank out any previous rollers
    for i = 1,5 do
      rlf["pos"..i]:SetText ("")
      rlf["rem"..i]:SetEnabled (false)
    end

    ksk.lootroll.endtime = GetTime () + ksk.cfg.settings.roll_timeout + 1
    ksk.lootroll.rollers = {}
    ksk.lootroll.suicide = sroll
    rlf.timerbarframe:SetScript ("OnUpdate", rolltimer_onupdate)
    ksk.qf.lootwin.oclbids:SetText (L["End Roll"])
    ksk.qf.lootwin.oclbids:SetEnabled (true)
    ksk.qf.lootwin.remcancel:SetText (K.CANCEL_STR)
    ksk.qf.lootwin.remcancel:SetEnabled (true)
    rlf:RegisterEvent ("CHAT_MSG_SYSTEM")
    rlf:SetScript ("OnEvent", rlf_onevent)
    ksk:StartOpenRoll (ksk.lootitem.loot.ilink, ksk.cfg.settings.roll_timeout)
    ksk.SendRaidAM ("OROLL", "ALERT", ksk.lootitem.loot.ilink, ksk.cfg.settings.roll_timeout)
  end

  local function rlf_onhide ()
    if (ksk.rolling == 0) then
      ksk:CleanupLootRoll ()
    elseif (ksk.rolling == 1) then
      open_roll_or_pause ()
    elseif (ksk.rolling == 2) then
      ksk.rolling = 3
    end
  end

  local function rlf_onshow ()
    if (ksk.rolling == 2) then
      open_roll_or_pause ()
    elseif (ksk.rolling == 3) then
      ksk.rolling = 2
    end
  end
  rlf:SetScript ("OnHide", rlf_onhide)
  rlf:SetScript ("OnShow", rlf_onshow)

  --
  -- Now populate the actual loot rules frame
  --

  ypos = 0
  arg = {
    x = 0, y = ypos, text = L["Class Filter"],
    font = "GameFontNormal",
  }
  bm.cflabel = KUI:CreateStringLabel (arg, bm)
  ypos = ypos - 16

  arg = {
    x = 0, y = ypos, label = { text = K.IndexClass[K.CLASS_WARRIOR].c },
    font = "GameFontHighlightSmall", height = 16,
  }
  bm.warrior = KUI:CreateCheckBox (arg, bm)
  bm.warrior:Catch ("OnValueChanged", function (this, evt, val, user)
    class_filter_func (this, evt, val, K.CLASS_WARRIOR, user)
  end)

  arg = {
    x = 88, y = ypos, label = { text = K.IndexClass[K.CLASS_PALADIN].c },
    font = "GameFontHighlightSmall", height = 16,
  }
  bm.paladin = KUI:CreateCheckBox (arg, bm)
  bm.paladin:Catch ("OnValueChanged", function (this, evt, val, user)
    class_filter_func (this, evt, val, K.CLASS_PALADIN, user)
  end)

  arg = {
    x = 176, y = ypos, label = { text = K.IndexClass[K.CLASS_DEATHKNIGHT].c },
    font = "GameFontHighlightSmall", height = 16,
  }
  bm.deathknight = KUI:CreateCheckBox (arg, bm)
  bm.deathknight:Catch ("OnValueChanged", function (this, evt, val, user)
    class_filter_func (this, evt, val, K.CLASS_DEATHKNIGHT, user)
  end)
  ypos = ypos - 16

  arg = {
    x = 0, y = ypos, label = { text = K.IndexClass[K.CLASS_HUNTER].c },
    font = "GameFontHighlightSmall", height = 16,
  }
  bm.hunter = KUI:CreateCheckBox (arg, bm)
  bm.hunter:Catch ("OnValueChanged", function (this, evt, val, user)
    class_filter_func (this, evt, val, K.CLASS_HUNTER, user)
  end)

  arg = {
    x = 88, y = ypos, label = { text = K.IndexClass[K.CLASS_SHAMAN].c },
    font = "GameFontHighlightSmall", height = 16,
  }
  bm.shaman = KUI:CreateCheckBox (arg, bm)
  bm.shaman:Catch ("OnValueChanged", function (this, evt, val, user)
    class_filter_func (this, evt, val, K.CLASS_SHAMAN, user)
  end)

  arg = {
    x = 176, y = ypos, label = { text = K.IndexClass[K.CLASS_DRUID].c },
    font = "GameFontHighlightSmall", height = 16,
  }
  bm.druid = KUI:CreateCheckBox (arg, bm)
  bm.druid:Catch ("OnValueChanged", function (this, evt, val, user)
    class_filter_func (this, evt, val, K.CLASS_DRUID, user)
  end)
  ypos = ypos - 16

  arg = {
    x = 0, y = ypos, label = { text = K.IndexClass[K.CLASS_ROGUE].c },
    font = "GameFontHighlightSmall", height = 16,
  }
  bm.rogue = KUI:CreateCheckBox (arg, bm)
  bm.rogue:Catch ("OnValueChanged", function (this, evt, val, user)
    class_filter_func (this, evt, val, K.CLASS_ROGUE, user)
  end)

  arg = {
    x = 88, y = ypos, label = { text = K.IndexClass[K.CLASS_MAGE].c },
    font = "GameFontHighlightSmall", height = 16,
  }
  bm.mage = KUI:CreateCheckBox (arg, bm)
  bm.mage:Catch ("OnValueChanged", function (this, evt, val, user)
    class_filter_func (this, evt, val, K.CLASS_MAGE, user)
  end)

  arg = {
    x = 176, y = ypos, label = { text = K.IndexClass[K.CLASS_WARLOCK].c },
    font = "GameFontHighlightSmall", height = 16,
  }
  bm.warlock = KUI:CreateCheckBox (arg, bm)
  bm.warlock:Catch ("OnValueChanged", function (this, evt, val, user)
    class_filter_func (this, evt, val, K.CLASS_WARLOCK, user)
  end)
  ypos = ypos - 16

  arg = {
    x = 0, y = ypos, label = { text = K.IndexClass[K.CLASS_PRIEST].c },
    font = "GameFontHighlightSmall", height = 16,
  }
  bm.priest = KUI:CreateCheckBox (arg, bm)
  bm.priest:Catch ("OnValueChanged", function (this, evt, val, user)
    class_filter_func (this, evt, val, K.CLASS_PRIEST, user)
  end)

  arg = {
    x = 88, y = ypos, label = { text = K.IndexClass[K.CLASS_MONK].c },
    font = "GameFontHighlightSmall", height = 16,
  }
  bm.monk = KUI:CreateCheckBox (arg, bm)
  bm.monk:Catch ("OnValueChanged", function (this, evt, val, user)
    class_filter_func (this, evt, val, K.CLASS_MONK, user)
  end)

  arg = {
    x = 176, y = ypos, label = { text = K.IndexClass[K.CLASS_DEMONHUNTER].c },
    font = "GameFontHighlightSmall", height = 16,
  }
  bm.demonhunter = KUI:CreateCheckBox (arg, bm)
  bm.demonhunter:Catch ("OnValueChanged", function (this, evt, val, user)
    class_filter_func (this, evt, val, K.CLASS_DEMONHUNTER, user)
  end)

  ypos = ypos - 20

  arg = {
    x = 0, y = ypos, text = L["Other Filters"],
    font = "GameFontNormal",
  }
  bm.aflabel = KUI:CreateStringLabel (arg, bm)
  ypos = ypos - 16

  bm.role = ksk.CreateRoleListDropdown ("LootRoleFilter", 0, ypos, bm)
  bm.role:SetEnabled (false)
  ksk.loot_role = 0
  bm.role:Catch ("OnValueChanged", function (this, evt, newv, user)
    ksk.loot_role = newv
    if (ksk.isml and user) then
      ksk.SendRaidAM ("FLTCH", "ALERT", "R", newv)
    end
  end)
  ypos = ypos - 30
  bm.role:SetValue (0)

  arg = {
    x = 0, y = ypos, mode = "SINGLE", itemheight = 16,
    name = "KSKLootRankFilter", dwidth = 150, items = KUI.emptydropdown,
    label = { text = L["Guild Rank"], pos = "LEFT" },
    tooltip = { title = "$$", text = L["TIP051"], },
  }
  bm.rank = KUI:CreateDropDown (arg, bm)
  ksk.loot_rank = 999
  bm.rank:Catch ("OnValueChanged", function (this, evt, newv, user)
    ksk.loot_rank = newv
    if (ksk.isml and user) then
      ksk.SendRaidAM ("FLTCH", "ALERT", "G", newv)
    end
  end)
  ksk.qf.lootrank = bm.rank

  arg = {
    x = 350, y = ypos, width = 16, height = 16, text = "-",
  }
  bm.nextrank = KUI:CreateButton (arg, bm)
  bm.nextrank:ClearAllPoints ()
  bm.nextrank:SetPoint ("TOPLEFT", bm.rank.button, "TOPRIGHT", 2, -4)
  bm.nextrank:Catch ("OnClick", function (this, evt, ...)
    if (ksk.loot_rank ~= 999) then
      if (ksk.loot_rank < K.guild.numranks) then
        ksk.loot_rank = ksk.loot_rank + 1
        bm.rank:SetValue (ksk.loot_rank)
        if (ksk.isml) then
          ksk.SendRaidAM ("FLTCH", "ALERT", "G", ksk.loot_rank)
        end
      end
    end
  end)

  ypos = ypos - 30

  arg = {
    x = 0, y = ypos, label = { text = L["Strict Class Armor"] },
    font = "GameFontHighlightSmall", height = 16,
    tooltip = { title = "$$", text = L["TIP039"], }, 
  }
  bm.strictarmour = KUI:CreateCheckBox (arg, bm)
  bm.strictarmour:Catch ("OnValueChanged", function (this, evt, val, user)
    ksk.strictca = val
    if (ksk.isml and user) then
      ksk.SendRaidAM ("FLTCH", "ALERT", "A", val)
    end
  end)

  arg = {
    x = 150, y = ypos, label = { text = L["Strict Role Filter"] },
    font = "GameFontHighlightSmall", height = 16,
    tooltip = { title = "$$", text = L["TIP040"], }, 
  }
  bm.strictrole = KUI:CreateCheckBox (arg, bm)
  bm.strictrole:Catch ("OnValueChanged", function (this, evt, val, user)
    ksk.strictrf = val
    if (ksk.isml and user) then
      ksk.SendRaidAM ("FLTCH", "ALERT", "L", val)
    end
  end)
  ypos = ypos - 20

  --
  -- Set up the buttons for controlling loot, as well as the scrolling list
  -- of loot itself. First create the frame that will contain the scrolling
  -- list of loot, as it occupies a full frame. Next to that frame we will
  -- have the loot control buttons.
  --
  tr.sframe = MakeFrame ("Frame", nil, tr)
  tr.sframe:ClearAllPoints ()
  tr.sframe:SetPoint ("TOPLEFT", tr, "TOPLEFT", 0, 0)
  tr.sframe:SetPoint ("TOPRIGHT", tr, "TOPRIGHT", 0, 0)
  tr.sframe:SetHeight (98)

  arg = {
    name = "KSKBossLootScrollList",
    itemheight = 16,
    newitem = llist_newitem,
    setitem = llist_setitem,
    selectitem = llist_selectitem,
    highlightitem = function (objp, idx, slot, btn, onoff)
      return KUI.HighlightItemHelper (objp, idx, slot, btn, onoff)
    end,
  }
  tr.slist = KUI:CreateScrollList (arg, tr.sframe)
  ksk.qf.lootscroll = tr.slist

  ypos = -100
  arg = {
    x = 0, y = ypos, width = 90, text = L["Open Bids"],
    tooltip = { title = L["TIP052.0"], text = L["TIP052"], },
    enabled = false,
  }
  tr.oclbids = KUI:CreateButton (arg, tr)
  tr.oclbids:Catch ("OnClick", function (this, evt, ...)
    open_close_bids ()
  end)

  arg = {
    x = 100, y = ypos, width = 90, text = L["Open Roll"],
    tooltip = { title = L["TIP053.0"], text = L["TIP053"], },
    enabled = false,
  }
  tr.orpause = KUI:CreateButton (arg, tr)
  tr.orpause:Catch ("OnClick", function (this, evt, ...)
    open_roll_or_pause ()
  end)

  arg = {
    x = 200, y = ypos, width = 90, text = L["Remove"],
    tooltip = { title = L["TIP054.0"], text = L["TIP054"], },
    enabled = false,
  }
  tr.remcancel = KUI:CreateButton (arg, tr)
  tr.remcancel:Catch ("OnClick", function (this, evt, ...)
    remove_or_cancel ()
  end)

  --
  -- Set up the buttons for controlling bidders, as well as the scrolling list
  -- of bidders. First create the frame that will contain the scrolling
  -- list of bidders, as it occupies a full frame. Next to that frame we will
  -- have the bid control buttons.
  --
  bb.sframe = MakeFrame ("Frame", nil, bb)
  bb.sframe:ClearAllPoints ()
  bb.sframe:SetPoint ("TOPLEFT", bb, "TOPLEFT", 0, 0)
  bb.sframe:SetPoint ("BOTTOMLEFT", bb, "BOTTOMLEFT", 0, 0)
  bb.sframe:SetWidth (180)

  arg = {
    name = "KSKBiddersScrollList",
    itemheight = 16,
    newitem = function (objp, num)
      return KUI.NewItemHelper (objp, num, "KSKBLBidButton", 155, 16, nil, nil,
        function (this, idx)
          if (not ksk.isml) then
            return true
          end
        end, nil)
      end,
    setitem = function (objp, idx, slot, btn)
        return KUI.SetItemHelper (objp, btn, idx, function (op, ix)
          return aclass (ksk.bidders[ix])
        end)
      end,
    selectitem = blist_selectitem,
    highlightitem = function (objp, idx, slot, btn, onoff)
      return KUI.HighlightItemHelper (objp, idx, slot, btn, onoff)
    end,
  }
  bb.slist = KUI:CreateScrollList (arg, bb.sframe)
  ksk.qf.bidscroll = bb.slist

  ypos = 0
  local xpos = 190
  arg = {
    x = xpos, y = ypos, width = 100, text = L["Bid"],
    tooltip = { title = L["TIP055.0"], text = L["TIP055"], },
  }
  bb.mybid = KUI:CreateButton (arg, bb)
  bb.mybid:Catch ("OnClick", function (this, evt, ...)
    if (ksk.rolling) then
      RandomRoll (1, 100)
    elseif (bb.mybid.retract) then
      if (ksk.isml) then
        ksk:RetractBidder (K.player.player, ksk.biditem)
      else
        assert (ksk.mlname)
        ksk.SendWhisperAM (ksk.mlname, "BIDRT", "ALERT", ksk.biditem)
      end
    else
      if (ksk.isml) then
        ksk:NewBidder (K.player.player)
      else
        assert (ksk.mlname)
        ksk.SendWhisperAM (ksk.mlname, "BIDME", "ALERT", ksk.biditem)
      end
    end
  end)
  ypos = ypos - 24

  arg = {
    x = xpos, y = ypos, width = 100, text = L["Force Bid"],
    tooltip = { title = "$$", text = L["TIP056"], },
    enabled = false,
  }
  bb.forcebid = KUI:CreateButton (arg, bb)
  bb.forcebid:Catch ("OnClick", function (this, evt, ...)
    if (ksk.rolling) then
      RandomRoll (101, 200)
    else
      ksk:NewBidder (ksk.users[realmemberid].name)
    end
  end)
  ypos = ypos - 24

  arg = {
    x = xpos, y = ypos, width = 100, text = L["Force Retract"],
    tooltip = { title = "$$", text = L["TIP057"], },
    enabled = false,
  }
  bb.forceret = KUI:CreateButton (arg, bb)
  bb.forceret:Catch ("OnClick", function (this, evt, ...)
    if (ksk.rolling) then
      RandomRoll (1, 1)
    else
      ksk:RetractBidder (ksk.bidders[ksk.selectedbidder].name)
    end
  end)
  ypos = ypos - 24

  arg = {
    x = xpos, y = ypos, width = 100, text = L["Undo"], enabled = false,
    tooltip = { title = "$$", text = L["TIP058"], },
    enabled = false,
  }
  bb.undo = KUI:CreateButton (arg, bb)
  bb.undo:Catch ("OnClick", function (this, evt, ...)
    undo_button ()
  end)
  ypos = ypos - 24
  ksk.qf.undobutton = bb.undo

  --
  -- Item editor tab. The left side is the scrolling list of loot items,
  -- and the right hand side contains the options for that item.
  --
  local cf = ksk.mainwin.tabs[ksk.LOOT_TAB].tabs[ksk.LOOT_ITEMS_TAB].content
  local ls = cf.vsplit.leftframe
  local rs = cf.vsplit.rightframe
  ksk.qf.itemopts = rs

  arg = {
    name = "KSKItemScrollList",
    itemheight = 16,
    newitem = function (objp, num)
        local rf = KUI.NewItemHelper (objp, num, "KSKIListButton", 200, 16,
          nil, nil, function (this, ix)
            this:GetParent():GetParent():SetSelected (ix, false, true)
            return true
          end, nil)
        rf:SetScript ("OnEnter", function (this, evt, ...)
          local idx = this:GetID ()
          GameTooltip:SetOwner (this, "ANCHOR_BOTTOMLEFT", 0, 25)
          GameTooltip:SetHyperlink (ksk.items[ksk.sorteditems[idx].id].ilink)
          GameTooltip:Show ()
        end)
        rf:SetScript ("OnLeave", function (this, evt, ...)
          GameTooltip:Hide ()
        end)
        return rf
      end,
    setitem = ilist_setitem,
    selectitem = ilist_selectitem,
    highlightitem = function (objp, idx, slot, btn, onoff)
      return KUI.HighlightItemHelper (objp, idx, slot, btn, onoff)
    end,
  }
  ls.ilist = KUI:CreateScrollList (arg, ls)
  ksk.qf.itemlist = ls.ilist

  local function reset_uvalues (io)
    io.suicidelist:SetValue ("0")
    io.autodel:SetChecked (false)
    io.nextuser:SetText ("")
    io.nextdrop:SetChecked (false)
    io.role:SetValue (0)
    io.priest:SetChecked (false)
    io.warlock:SetChecked (false)
    io.mage:SetChecked (false)
    io.rogue:SetChecked (false)
    io.druid:SetChecked (false)
    io.monk:SetChecked (false)
    io.shaman:SetChecked (false)
    io.hunter:SetChecked (false)
    io.deathknight:SetChecked (false)
    io.paladin:SetChecked (false)
    io.warrior:SetChecked (false)
    io.demonhunter:SetChecked (false)
    io.defrank:SetValue (999)
    io.speclist:SetValue ("0")
  end

  ypos = 0
  arg = {
    x = 0, y = ypos, label = { text = L["Ignore Item"] },
    tooltip = { title = "$$", text = L["TIP059"], },
    enabled = false,
  }
  rs.ignore = KUI:CreateCheckBox (arg, rs)
  rs.ignore:Catch ("OnValueChanged", function (this, evt, val, user)
    local io = ksk.qf.itemopts
    if (not val) then
      iinfo.ignore = nil
    else
      local ilink = iinfo.ilink
      iinfo = { ilink = ilink, ignore = true }
      io.autodench:SetChecked (false)
      io.automl:SetChecked (false)
      reset_uvalues (io)
    end
    changed (nil, user)
    if (user) then
      local en = not val
      io.autodench:SetEnabled (en)
      io.automl:SetEnabled (en)
      enable_uvalues (io, en)
    end
  end)
  ypos = ypos - 16

  arg = {
    x = 0, y = ypos, label = { text = L["Auto-assign to Enchanter"] },
    tooltip = { title = "$$", text = L["TIP097"] },
    enabled = false,
  }
  rs.autodench = KUI:CreateCheckBox (arg, rs)
  rs.autodench:Catch ("OnValueChanged", function (this, evt, val, user)
    local io = ksk.qf.itemopts
    if (not val) then
      iinfo.autodench = nil
    else
      local ilink = iinfo.ilink
      iinfo = { ilink = ilink, autodench = true }
      io.automl:SetChecked (false)
      reset_uvalues (io)
    end
    changed (nil, user)
    if (user) then
      local en = not val
      io.automl:SetEnabled (en)
      enable_uvalues (io, en)
    end
  end)
  ypos = ypos - 16

  arg = {
    x = 0, y = ypos, label = { text = L["Auto-assign to Master Looter"] },
    tooltip = { title = "$$", text = L["TIP098"] },
    enabled = false,
  }
  rs.automl = KUI:CreateCheckBox (arg, rs)
  rs.automl:Catch ("OnValueChanged", function (this, evt, val, user)
    local io = ksk.qf.itemopts
    if (not val) then
      iinfo.automl = nil
    else
      local ilink = iinfo.ilink
      iinfo = { ilink = ilink, automl = true }
      io.autodench:SetChecked (false)
      reset_uvalues (io)
    end
    changed (nil, user)
    if (user) then
      local en = not val
      io.autodench:SetEnabled (en)
      enable_uvalues (io, en)
    end
  end)
  ypos = ypos - 20

  arg = {
    x = 0, y = ypos, name = "KSKItemSpecificList", dwidth = 200,
    mode = "SINGLE", itemheight = 16, items = KUI.emptydropdown,
    label = { text = L["Roll on Specific List"], pos = "TOP" },
    enabled = false,
    tooltip = { title = "$$", text = L["TIP060"], },
  }
  rs.speclist = KUI:CreateDropDown (arg, rs)
  rs.speclist:SetValue ("0")
  rs.speclist:Catch ("OnValueChanged", function (this, evt, newv, user)
    changed (nil, user)
    iinfo.list = newv
  end)
  ksk.qf.itemlistdd = rs.speclist
  ypos = ypos - 48

  arg = {
    x = 0, y = ypos, name = "KSKItemRankDropdown",
    dwidth = 200, mode = "SINGLE", itemheight = 16, items = KUI.emptydropdown,
    label = { text = L["Initial Guild Rank Filter"], },
    enabled = false,
    tooltip = { title = "$$", text = L["TIP061"], },
  }
  rs.defrank = KUI:CreateDropDown (arg, rs)
  ksk.qf.itemrankdd = rs.defrank
  rs.defrank:Catch ("OnValueChanged", function (this, evt, nv, user)
    changed (nil, user)
    iinfo.rank = nv
  end)
  ypos = ypos - 48

  arg = {
    x = 0, y = ypos, text = L["Class Restriction"],
    font = "GameFontNormal",
  }
  rs.cflabel = KUI:CreateStringLabel (arg, rs)
  ypos = ypos - 16

  arg = {
    x = 0, y = ypos, label = { text = K.IndexClass[K.CLASS_WARRIOR].c },
    font = "GameFontHighlightSmall", height = 16,
    enabled = false,
  }
  rs.warrior = KUI:CreateCheckBox (arg, rs)
  rs.warrior:Catch ("OnValueChanged", function (this, evt, val, user)
    iclass_filter_func (this, evt, val, K.CLASS_WARRIOR, user)
  end)

  arg = {
    x = 120, y = ypos, label = { text = K.IndexClass[K.CLASS_PALADIN].c },
    font = "GameFontHighlightSmall", height = 16,
    enabled = false,
  }
  rs.paladin = KUI:CreateCheckBox (arg, rs)
  rs.paladin:Catch ("OnValueChanged", function (this, evt, val, user)
    iclass_filter_func (this, evt, val, K.CLASS_PALADIN, user)
  end)
  ypos = ypos - 16

  arg = {
    x = 0, y = ypos, label = { text = K.IndexClass[K.CLASS_DEATHKNIGHT].c },
    font = "GameFontHighlightSmall", height = 16,
    enabled = false,
  }
  rs.deathknight = KUI:CreateCheckBox (arg, rs)
  rs.deathknight:Catch ("OnValueChanged", function (this, evt, val, user)
    iclass_filter_func (this, evt, val, K.CLASS_DEATHKNIGHT, user)
  end)

  arg = {
    x = 120, y = ypos, label = { text = K.IndexClass[K.CLASS_HUNTER].c },
    font = "GameFontHighlightSmall", height = 16,
    enabled = false,
  }
  rs.hunter = KUI:CreateCheckBox (arg, rs)
  rs.hunter:Catch ("OnValueChanged", function (this, evt, val, user)
    iclass_filter_func (this, evt, val, K.CLASS_HUNTER, user)
  end)
  ypos = ypos - 16

  arg = {
    x = 0, y = ypos, label = { text = K.IndexClass[K.CLASS_SHAMAN].c },
    font = "GameFontHighlightSmall", height = 16,
    enabled = false,
  }
  rs.shaman = KUI:CreateCheckBox (arg, rs)
  rs.shaman:Catch ("OnValueChanged", function (this, evt, val, user)
    iclass_filter_func (this, evt, val, K.CLASS_SHAMAN, user)
  end)

  arg = {
    x = 120, y = ypos, label = { text = K.IndexClass[K.CLASS_DRUID].c },
    font = "GameFontHighlightSmall", height = 16,
    enabled = false,
  }
  rs.druid = KUI:CreateCheckBox (arg, rs)
  rs.druid:Catch ("OnValueChanged", function (this, evt, val, user)
    iclass_filter_func (this, evt, val, K.CLASS_DRUID, user)
  end)
  ypos = ypos - 16

  arg = {
    x = 0, y = ypos, label = { text = K.IndexClass[K.CLASS_ROGUE].c },
    font = "GameFontHighlightSmall", height = 16,
    enabled = false,
  }
  rs.rogue = KUI:CreateCheckBox (arg, rs)
  rs.rogue:Catch ("OnValueChanged", function (this, evt, val, user)
    iclass_filter_func (this, evt, val, K.CLASS_ROGUE, user)
  end)

  arg = {
    x = 120, y = ypos, label = { text = K.IndexClass[K.CLASS_MAGE].c },
    font = "GameFontHighlightSmall", height = 16,
    enabled = false,
  }
  rs.mage = KUI:CreateCheckBox (arg, rs)
  rs.mage:Catch ("OnValueChanged", function (this, evt, val, user)
    iclass_filter_func (this, evt, val, K.CLASS_MAGE, user)
  end)
  ypos = ypos - 16

  arg = {
    x = 0, y = ypos, label = { text = K.IndexClass[K.CLASS_WARLOCK].c },
    font = "GameFontHighlightSmall", height = 16,
    enabled = false,
  }
  rs.warlock = KUI:CreateCheckBox (arg, rs)
  rs.warlock:Catch ("OnValueChanged", function (this, evt, val, user)
    iclass_filter_func (this, evt, val, K.CLASS_WARLOCK, user)
  end)

  arg = {
    x = 120, y = ypos, label = { text = K.IndexClass[K.CLASS_PRIEST].c },
    font = "GameFontHighlightSmall", height = 16,
    enabled = false,
  }
  rs.priest = KUI:CreateCheckBox (arg, rs)
  rs.priest:Catch ("OnValueChanged", function (this, evt, val, user)
    iclass_filter_func (this, evt, val, K.CLASS_PRIEST, user)
  end)
  ypos = ypos -16

  arg = {
    x = 0, y = ypos, label = { text = K.IndexClass[K.CLASS_MONK].c },
    font = "GameFontHighlightSmall", height = 16,
    enabled = false,
  }
  rs.monk = KUI:CreateCheckBox (arg, rs)
  rs.monk:Catch ("OnValueChanged", function (this, evt, val, user)
    iclass_filter_func (this, evt, val, K.CLASS_MONK, user)
  end)

  arg = {
    x = 120, y = ypos, label = { text = K.IndexClass[K.CLASS_DEMONHUNTER].c },
    font = "GameFontHighlightSmall", height = 16,
    enabled = false,
  }
  rs.demonhunter = KUI:CreateCheckBox (arg, rs)
  rs.demonhunter:Catch ("OnValueChanged", function (this, evt, val, user)
    iclass_filter_func (this, evt, val, K.CLASS_DEMONHUNTER, user)
  end)

  ypos = ypos - 18

  rs.role = ksk.CreateRoleListDropdown ("ItemRoleFilter", 0, ypos, rs)
  ksk.item_role = 0
  rs.role:Catch ("OnValueChanged", function (this, evt, newv, user)
    changed (nil, user)
    iinfo.role = newv
  end)
  ypos = ypos - 26
  rs.role:SetValue (0)
  rs.role:SetEnabled (false)

  arg = {
    x = 0, y = ypos, label = { text = L["Assign Next Drop to User"] },
    enabled = false,
    tooltip = { title = "$$", text = L["TIP062"], },
  }
  rs.nextdrop = KUI:CreateCheckBox (arg, rs)
  rs.nextdrop:Catch ("OnValueChanged", function (this, evt, val, user)
    changed (nil, user)
    local io = ksk.qf.itemopts
    io.nextuser:SetEnabled (val)
    io.seluser:SetEnabled (val)
    io.autodel:SetEnabled (val)
    io.suicidelist:SetEnabled (val)
    if (not val) then
      io.nextuser:SetText ("")
      io.autodel:SetChecked (false)
      io.suicidelist:SetValue ("0")
      iinfo.nextdrop = false
      iinfo.autodel = false
      iinfo.suicide = "0"
      iinfo.nextuser = nil
      if (ksk.popupwindow) then
        ksk.popupwindow:Hide ()
        ksk.popupwindow = nil
      end
    else
      iinfo.nextdrop = true
      io.autodel:SetChecked (iinfo.autodel)
    end
  end)
  ypos = ypos - 24

  arg = {
    x = 24, y = ypos, border = true, height = 20, width = 150, text = "",
    enabled = false, autosize = false,
  }
  rs.nextuser = KUI:CreateStringLabel (arg, rs)
  ksk.qf.ienextuserlbl = rs.nextuser

  arg = {
    x = 180, y = ypos+2, width = 65, height = 24, text = L["Select"],
    enabled = false,
    tooltip = { title = "$$", text = L["TIP063"], },
  }
  rs.seluser = KUI:CreateButton (arg, rs)
  rs.seluser:Catch ("OnClick", function (this, evt)
    select_next (this)
  end)
  ypos = ypos - 20

  arg = {
    x = 24, y = ypos, label = { text = L["Auto-Remove When Assigned"] },
    enabled = false,
    tooltip = { title = "$$", text = L["TIP064"], },
  }
  rs.autodel = KUI:CreateCheckBox (arg, rs)
  rs.autodel:Catch ("OnValueChanged", function (this, evt, val, user)
    changed (nil, user)
    iinfo.autodel = val
  end)
  ypos = ypos - 20

  arg = {
    x = 24, y = ypos, name = "KSKItemUserSuicideList", dwidth = 150,
    mode = "SINGLE", itemheight = 16, items = KUI.emptydropdown,
    label = { text = L["Suicide User on List"], pos = "TOP" },
    enabled = false,
    tooltip = { title = "$$", text = L["TIP065"], },
  }
  rs.suicidelist = KUI:CreateDropDown (arg, rs)
  rs.suicidelist:Catch ("OnValueChanged", function (this, evt, newv, user)
    changed (nil, user)
    iinfo.suicide = newv
  end)
  ksk.qf.suicidelistdd = rs.suicidelist
  ypos = ypos - 48

  arg = {
    x = 0, y = ypos, text = L["Update"], enabled = false,
  }
  rs.updatebtn = KUI:CreateButton (arg, rs)
  ksk.qf.itemupdbtn = rs.updatebtn
  rs.updatebtn:Catch ("OnClick", function (this, evt)
    --
    -- Copy from the iinfo structure back to the stored item list in the
    -- configure structure. Do it manually as we check values as we go.
    --
    local ilink = iinfo.ilink
    if (iinfo.ignore and iinfo.ignore == true) then
      ksk.items[ksk.itemid] = { ilink = ilink, ignore = true }
    else
      ksk.items[ksk.itemid] = { ilink = ilink }
      local cs = {}
      local ns = 0
      for k,v in pairs (K.IndexClass) do
        local n = tonumber (k)
        if (iinfo.cfilter[k] == true) then
          cs[n] = "1"
          ns = ns + 1
        else
          cs[n] = "0"
        end
      end
      local fcs = tconcat (cs)
      if (ns > 0) then
        ksk.items[ksk.itemid].cfilter = fcs
      end

      if (iinfo.role and iinfo.role ~= 0) then
        ksk.items[ksk.itemid].role = iinfo.role
      end

      if (iinfo.list and iinfo.list ~= "" and iinfo.list ~= "0") then
        ksk.items[ksk.itemid].list = iinfo.list
      end

      if (iinfo.rank and iinfo.rank ~= 999) then
        ksk.items[ksk.itemid].rank = iinfo.rank
      end

      if (iinfo.nextdrop and iinfo.nextdrop ~= false and iinfo.nextuser and iinfo.nextuser ~= "" and iinfo.nextuser ~= 0) then
        ksk.items[ksk.itemid].user = iinfo.nextuser
        if (iinfo.suicide and iinfo.suicide ~= "0") then
          ksk.items[ksk.itemid].suicide = iinfo.suicide
        end
        if (iinfo.autodel and iinfo.autodel == true) then
          ksk.items[ksk.itemid].del = true
        end
      end

      if (iinfo.autodench and iinfo.autodench ~= false) then
        ksk.items[ksk.itemid].autodench = true
      end

      if (iinfo.automl and iinfo.automl ~= false) then
        ksk.items[ksk.itemid].automl = true
      end
    end
    ksk:MakeCHITM (ksk.itemid, ksk.items[ksk.itemid], ksk.currentid, true)
    ksk.qf.itemupdbtn:SetEnabled (false)
  end)

  arg.x = 100
  arg.text = L["Delete"]
  arg.tooltip = { title = "$$", text = L["TIP066"] }
  rs.deletebtn = KUI:CreateButton (arg, rs)
  ksk.qf.itemdelbtn = rs.deletebtn
  rs.deletebtn:Catch ("OnClick", function (this, evt)
    ksk:DeleteItem (ksk.itemid)
  end)
  ypos = ypos - 24

  --
  -- History tab. We have a header, then the rest of the panel is a big
  -- scrolling list of loot history.
  --
  local cf = ksk.mainwin.tabs[ksk.LOOT_TAB].tabs[ksk.LOOT_HISTORY_TAB].content
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
  bf.clearall = KUI:CreateButton (arg, bf)
  bf.clearall:Catch ("OnClick", function (this, evt, ...)
    ksk.cfg.history = {}
    ksk:RefreshHistory ()
  end)

  arg = {
    x = 85, y = ypos, width = 200, text = L["Clear all except last week"],
    tooltip = { title = "$$", text = L["TIP068"], },
  }
  bf.clearweek = KUI:CreateButton (arg, bf)
  bf.clearweek:Catch ("OnClick", function (this, evt, ...)
    local _, y, m, d = ksk:TimeStamp ()
    if (d >= 7) then
      d = d - 6
    else
      if (m == 1) then
        y = y - 1
        m = 12
      else
        m = m - 1
      end
      d = 23 + d
    end
    local ts = tonumber (strfmt ("%04d%02d%02d0101", y, m, d))
    local i = 1
    while (i <= #ksk.cfg.history) do
      if (tonumber (strsub (ksk.cfg.history[i], 1, 12)) < ts) then
        tremove (ksk.cfg.history, i)
      else
        i = i + 1
      end
    end
    ksk:RefreshHistory ()
  end)

  arg = {
    x = 280, y = ypos, width = 200, text = L["Clear all except last month"],
    tooltip = { title = "$$", text = L["TIP069"], },
  }
  bf.clearmonth = KUI:CreateButton (arg, bf)
  bf.clearmonth:Catch ("OnClick", function (this, evt, ...)
    local _, y, m, d = ksk:TimeStamp ()
    if (m == 1) then
      y = y - 1
      m = 12
    else
      m = m - 1
    end
    local ts = tonumber (strfmt ("%04d%02d%02d0101", y, m, d))
    local i = 1
    while (i <= #ksk.cfg.history) do
      if (tonumber (strsub (ksk.cfg.history[i], 1, 12)) < ts) then
        tremove (ksk.cfg.history, i)
      else
        i = i + 1
      end
    end
    ksk:RefreshHistory ()
  end)
  ypos = ypos - 24

  arg = {
    x = "CENTER", y = ypos, text = L["Export"],
    tooltip = { title = "$$", text = L["TIP070"], },
  }
  bf.export = KUI:CreateButton (arg, bf)
  bf.export:Catch ("OnClick", function (this, evt, ...)
    export_history_button ()
  end)

  arg = {
    x = 0, y = 0, text = L["When"], font = "GameFontNormalSmall",
  }
  tf.str1 = KUI:CreateStringLabel (arg, tf)

  arg.x = 75
  arg.text = L["What"]
  tf.str2 = KUI:CreateStringLabel (arg, tf)

  arg.x = 248
  arg.text = L["Who"]
  tf.str3 = KUI:CreateStringLabel (arg, tf)

  arg.x = 350
  arg.text = L["How"]
  tf.str4 = KUI:CreateStringLabel (arg, tf)

  tf.sframe = MakeFrame ("Frame", nil, tf)
  tf.sframe:ClearAllPoints ()
  tf.sframe:SetPoint ("TOPLEFT", tf, "TOPLEFT", 0, -18)
  tf.sframe:SetPoint ("BOTTOMRIGHT", tf, "BOTTOMRIGHT", 0, 0)

  arg = {
    name = "KSKHistoryScrollList",
    itemheight = 16,
    newitem = hlist_newitem,
    setitem = hlist_setitem,
    selectitem = function (objp, idx, slot, btn, onoff) return end,
    highlightitem = function (objp, idx, slot, btn, onoff)
      return KUI.HighlightItemHelper (objp, idx, slot, btn, onoff)
    end,
  }
  tf.slist = KUI:CreateScrollList (arg, tf.sframe)
  ksk.qf.histscroll = tf.slist

  initdone = true
  ksk:RefreshLootLists ()
  ksk:RefreshHistory ()
  ksk:ResetBossLoot ()
end

function ksk:RefreshLootLists ()
  if (not initdone) then
    return
  end

  local vt = {}

  local oldlist = ksk.lootlistid or ""
  local oldidx = 0

  ksk.lootlistid = nil
  for k,v in ipairs (ksk.sortedlists) do
    if (v.id ==  oldlist) then
      oldidx = k
    end
  end
  if (oldidx == 0) then
    oldidx = 1
  end

  ksk.qf.lootlists.itemcount = ksk.cfg.nlists
  if (ksk.qf.lootlists.itemcount > 0) then
    ksk.qf.lootlists:UpdateList ()
    ksk.lootlistid = ksk.sortedlists[oldidx].id
    ksk.lootlist = ksk.lists[ksk.lootlistid]
    ksk.qf.lootlists:SetSelected (oldidx)
  else
    ksk.lootlistid = nil
    ksk.lootlist = nil
    ksk.qf.lootlists:UpdateList ()
  end

  ksk:RefreshLootMembers ()
end

function ksk:RefreshItemList ()
  if (not initdone) then
    return
  end

  local kids = { ksk.qf.itemopts:GetChildren () }
  for k,v in pairs (kids) do
    if (v.SetEnabled) then
      v:SetEnabled (false)
    end
  end
  ksk.qf.itemopts.cflabel:SetEnabled (true)

  local vt = {}
  local olditem = ksk.itemid or ""
  local oldidx = 0
  ksk.sorteditems = {}
  ksk.itemid = nil

  local istr = ""

  for k,v in pairs (ksk.items) do
    local ilink = v.ilink
    local iname = string.match (v.ilink, ".*|h%[(.*)%]|h")
    local ent = { id = k, link = ilink }
    vt[k] = strlower (iname)
    tinsert (ksk.sorteditems, ent)
  end
  tsort (ksk.sorteditems, function (a,b)
    return vt[a.id] < vt[b.id]
  end)
  vt = nil

  for k,v in pairs (ksk.sorteditems) do
    if (v.id == olditem) then
      oldidx = k
    end
  end

  ksk.qf.itemlist.itemcount = ksk.cfg.nitems
  ksk.qf.itemlist:UpdateList ()
  ksk.qf.itemlist:SetSelected (nil)

  if (oldidx ~= 0) then
    ksk.itemid = ksk.sorteditems[oldidx].id
    ksk.qf.itemlist:SetSelected (oldidx)
  end
end

function ksk:RefreshLootMembers ()
  if (not initdone) then
    return
  end

  members = nil

  if (not ksk.lootlistid) then
    ksk.lootmemberid = nil
    realmemberid = nil
    ksk.qf.lootmembers.itemcount = 0
    ksk.qf.lootmembers:UpdateList ()
  else
    if (ksk.lootlist.nusers > 0) then
      local oldmember = ksk.lootmemberid or ""
      local oldidx = 0
      ksk.lootmemberid = nil
      realmemberid = nil
      ksk.lootmembers = ksk.lootlist.users

      members = {}
      for k,v in ipairs(ksk.lootmembers) do
        local usr = ksk.users[v]

        if (ksk.inraid and ksk.settings.hide_absent) then
          if (ksk.raid.users[v]) then
            tinsert (members, {id = v, idx = k})
          end
        else
          tinsert (members, {id = v, idx = k})
        end

        if (ksk.cfg.tethered and usr.alts) then
          for kk,vv in pairs (usr.alts) do
            if (ksk.inraid and ksk.settings.hide_absent) then
              if (ksk.raid.users[vv]) then
                tinsert (members, {id = vv, idx = k, isalt = true, main = v})
              end
            else
              tinsert (members, {id = vv, idx = k, isalt = true, main = v})
            end
          end
        end
      end

      for k,v in ipairs (members) do
        if (v.id == oldmember) then
          oldidx = k
        end
      end

      ksk.qf.lootmembers.itemcount = #members
      ksk.qf.lootmembers:UpdateList ()
      if (oldidx > 0) then
        ksk.lootmemberid = members[oldidx].id
        realmemberid = ksk.lootmemberid
        ksk.qf.lootmembers:SetSelected (oldidx)
      else
        ksk.qf.lootmembers:SetSelected (nil)
      end
    else
      ksk.lootmemberid = nil
      realmemberid = nil
      ksk.qf.lootmembers.itemcount = 0
      ksk.qf.lootmembers:UpdateList ()
      ksk.qf.lootmembers:SetSelected (nil)
    end
  end
end

function ksk:ResetBidList ()
  ksk.bidders = {}
  ksk.selectedbidder = nil
  ksk.qf.bidscroll.itemcount = 0
  ksk.qf.bidscroll:UpdateList ()
  ksk.qf.bidscroll:SetSelected (nil)
  ksk.qf.bidders.mybid:SetText (L["Bid"])
  ksk.qf.bidders.mybid.retract = nil
end

function ksk:ResetBidders (send)
  if (ksk.isml and send and ksk.biditem) then
    ksk.SendRaidAM ("BIDCL", "ALERT", ksk.biditem)
  end
  ksk:ResetBidList ()
  ksk.bidders = nil
  ksk.biditem = nil
  ksk.qf.lootwin.oclbids:SetText (L["Open Bids"])
  ksk.qf.lootwin.orpause:SetText (L["Open Roll"])
  ksk.qf.lootwin.remcancel:SetText (L["Remove"])
  ksk.qf.bidders.mybid:SetEnabled (false)
  ksk.qf.lootmembers:SetSelected (nil)
end

function ksk:ResetBossLoot ()
  ksk:ResetBidders ()
  ksk.selectedloot = nil
  ksk.qf.lootscroll.itemcount = 0
  ksk.qf.lootscroll:UpdateList ()
  ksk.bossloot = nil
  enable_ui_elements (false)
  enable_bid_buttons (false)
  ksk.qf.autoloot:Hide ()
  ksk.qf.lootroll:Hide ()
  ksk.qf.lootrules:Show ()
end

function ksk:SelectLootListByID (list)
  local lid = 0

  for k,v in ipairs (ksk.sortedlists) do
    if (v.id == list) then
      lid = k
      break
    end
  end
  if (lid ~= 0) then
    if (ksk.lootlistid ~= list) then
      ksk.lootlistid = list
      ksk.lootlist = ksk.cfg.lists[list]
      ksk.qf.lootlists:SetSelected (lid)
    end
    ksk:RefreshLootMembers ()
    return true
  else
    return false
  end
end

function ksk:SetClassesFromFilter (filter)
  for k,v in pairs (K.ClassIndex) do
    local wn = strlower (k)
    local n = tonumber (v)
    local val = false
    if (strsub (filter, n, n) == "1") then
      val = true
    end
    ksk.qf.lootrules[wn]:SetChecked (val)
  end

end

function ksk:SelectLootItem (idx, itemid, filter, role, list, rank)
  ksk.selectedloot = idx
  ksk.qf.lootscroll:SetSelected (idx)
  ksk.lootitem = { idx = idx, itemid = itemid, filter = filter, role = role, list = list, rank = rank}
  ksk.lootitem.loot = ksk.bossloot[ksk.selectedloot]
  local loot = ksk.bossloot[ksk.selectedloot]

  --
  -- If the item specified a specific list, then select that list now.
  --
  if (list and list ~= "0") then
    if (not ksk:SelectLootListByID (list)) then
      if (ksk.isml) then
        printf (ecolor, "item %s wanted non-existent list %q", loot.ilink, tostring(list))
      end
    end
  end

  rank = rank or 999
  -- Set up the various filters
  ksk.qf.lootrules.role:SetValue (role)
  ksk.qf.lootrules.rank:SetValue (rank)
  ksk:SetClassesFromFilter (filter)

  --
  -- Before we set up the bidding buttons, check to see if the item is
  -- intended to be auto-looted to a given user (if that user is in the
  -- raid). If so, give the ML the opportunity to confirm the looting,
  -- and if they verify it, assign the item now and remove it from the
  -- list of items to be bid on.
  local autoloot = false
  if (ksk.isml and ksk.items[itemid]) then
    local ii = ksk.items[itemid]
    if (ii.user and ksk.raid and ksk.raid.users[ii.user]) then
      if (ksk.numlooters and ksk.numlooters > 0) then
        if (ksk.looters[ksk.users[ii.user].name]) then
          autoloot = true
        end
      else
        autoloot = true
      end
    end
    if (autoloot) then
      local cuser = class (ksk.users[ii.user])
      local uname = ksk.users[ii.user].name
      local ts = strfmt (L["AUTOASSIGN"], cuser, cuser)
      if (ii.suicide) then
        ts = ts .. " " .. strfmt (L["AUTOSUICIDE"], cuser, white (ksk.lists[ii.suicide].name))
      end
      if (not ksk.numlooters or ksk.numlooters == 0) then
        ts = ts .. "\n\n" .. white (L["Note: player will need to pick item up manually."])
        ksk.qf.autoloot.target = nil
      else
        ksk.qf.autoloot.target = ksk.looters[uname].mlidx
      end
      ksk.qf.autoassign_msg:SetText (ts)
      ksk.qf.autoassign_item:SetText (ksk.lootitem.loot.ilink)
      ksk.qf.autoloot.slot = ksk.bossloot[ksk.selectedloot].slot
      ksk.qf.autoloot.loot = ksk.selectedloot
      ksk.qf.autoloot.uname = uname
      ksk.qf.autoloot.uid = ii.user
      ksk.qf.autoloot.party = ksk.raid.members[ksk.raid.users[ii.user]].party
      ksk.qf.autoloot.ilink = ksk.lootitem.loot.ilink
      ksk.qf.autoloot.suicide = ii.suicide
      ksk.qf.autoloot.autodel = ii.del
      ksk.qf.autoloot.announce = true
      ksk.qf.autoloot.leaveloot = false
      ksk.qf.autoloot.denched = false
      ksk.qf.autoloot.rolled = false
    end
  end

  if (ksk.isml == true) then
    enable_ui_elements (true)
    local en

    if (autoloot) then
      ksk.qf.lootrules:Hide ()
      ksk.qf.lootroll:Hide ()
      ksk.qf.autoloot:Show ()
      en = false
    else
      ksk.qf.autoloot:Hide ()
      ksk.qf.lootroll:Hide ()
      ksk.qf.lootrules:Show ()
      en = true
    end

    ksk.qf.lootwin.oclbids:SetEnabled (en)
    ksk.qf.lootwin.orpause:SetEnabled (en)
    ksk.qf.lootwin.remcancel:SetEnabled (en)
  end
end

function ksk:RemoveItemByIdx (idx)
  ksk.qf.lootscroll:SetSelected (nil)
  if (ksk.selectedloot == idx) then
    ksk.selectedloot = nil
    ksk.lootitem = nil
  end
  tremove (ksk.bossloot, idx)
  ksk.qf.lootscroll.itemcount = #ksk.bossloot
  ksk.qf.lootscroll:UpdateList ()
end

function ksk:RefreshBidders()
  ksk.selectedbidder = nil
  ksk.qf.bidscroll.itemcount = 0
  if (ksk.bidders) then
    ksk.qf.bidscroll.itemcount = #ksk.bidders
  end
  ksk.qf.bidscroll:UpdateList ()
  ksk.qf.bidscroll:SetSelected (nil)
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
function ksk:NewBidder (u)
  -- First check. Am I the master looter?
  if (not ksk.isml) then
    if (ksk.mlname) then
      ksk.SendWhisper (strfmt (L["%s: I am not the master looter - %q is."], L["MODTITLE"], ksk.mlname), u)
    else
      ksk.SendWhisper (strfmt (L["%s: I am not the master looter."], L["MODTITLE"]), u)
    end
    return
  end

  local uid = ksk:FindUser (u)
  if (not uid) then
    ksk.SendWhisper (strfmt (L["%s: you were not found in the user list. Contact an admin for help."], L["MODTITLE"]), u)
    return
  end
  local usr = ksk.users[uid]

  -- Second check. Do we even have a current bid going?
  if (not ksk.biditem) then
    ksk.SendWhisper (strfmt (L["%s: there is no item currently open for bids."], L["MODTITLE"]), u)
    return
  end

  --
  -- Third check. Are they eligible to receive loot?
  -- Need to take into account that we may have no eligible looters because
  -- the raid leader had the wrong loot type set and has just changed it
  -- to master looter.
  --
  if (ksk.numlooters and ksk.numlooters > 0 and  not ksk.looters[u]) then
    ksk.SendWhisper (strfmt (L["%s: you are not eligible to receive loot - %s ignored."], L["MODTITLE"], L["bid"]), u)
    return
  end
  local found = false
  local minfo = nil
  for k,v in pairs (members) do
    if (v.id == uid) then
      found = true
      minfo = members[k]
      break
    end
  end
  if (not found) then
    info (L["%q attempted to bid on the %q list but is not a member."],
      aclass (ksk.users[uid]), white (ksk.lootlist.name))
    ksk.SendWhisper (strfmt (L["%s: you are not a member of the %q list - bid ignored."], L["MODTITLE"], ksk.lootlist.name), u)
    return
  end

  -- Fourth check. Have they already bid?
  for k,v in pairs (ksk.bidders) do
    if (v.uid == uid) then
      ksk.SendWhisper (strfmt (L["%s: you have already bid on that item. Whisper %s the word %q to retract your bid."], L["MODTITLE"], ksk.mlname, L["WHISPERCMD_RETRACT"]), u)
      return
    end
  end

  -- Fifth check. Verify the user matches the currently selected class
  -- and role and rank filters. They are individual checks but we clump
  -- them together.
  if (not verify_user_class (u, usr.class, L["bid"])) then
    return
  end

  local grprio = 1
  if (ksk.cfg.cfgtype == ksk.CFGTYPE_GUILD) then
    local rquery = "raid" .. tostring (ksk.raid.players[u])
    local gn, _, ri = GetGuildInfo (rquery)
    --
    -- If the GetGuildInfo() call fails for some reason (and I have seen it
    -- fail in testing) we don't really have much choice but to assume the
    -- user is in the guild. As to what we do with rank, we will just assume
    -- the user is the lowest rank. Also PUG members who are not in the
    -- guild will also be assumed to be of the lowest rank.
    --
    if (not gn or gn ~= K.player.guild) then
      ri = K.guild.numranks - 1
    end

    if (ksk.loot_rank ~= 999) then
      if (ri > (ksk.loot_rank - 1)) then
        ksk.SendWhisper (strfmt (L["%s: you do not meet the current guild rank requirement (%q) - %s ignored."], L["MODTITLE"], K.guild.ranks[ksk.loot_rank], L["bid"]), u)
        return
      end
    end

    grprio = ksk.settings.rank_prio[ri+1] or 1
  end

  if (ksk.qf.lootrules.strictrole:GetChecked ()) then
    if (ksk.loot_role > 0) then
      if (usr.role ~= ksk.loot_role) then
        if (usr.role ~= 0) then
          ksk.SendWhisper (strfmt (L["%s: you do not meet the current role requirement (%q). Your current role is %q - %s ignored."], L["MODTITLE"], ksk.rolenames[ksk.loot_role], ksk.rolenames[usr.role], L["bid"]), u)
          return
        else
          info (L["%s: user %q has no role defined - permitting %s."], L["MODTITLE"], aclass (usr), L["bid"])
        end
      end
    end
  end

  --
  -- All seems to be in order. Register the user's bid. If we have silent
  -- bidding enabled, simply issue a raid message letting people know that
  -- a bid has taken place (but not who has bid). Otherwise, broadcast to the
  -- raid the bidder info so uses can update their mod's view of the bidders.
  --
  ksk:AddBidder (usr.name, usr.class, minfo.idx, uid, grprio, ksk.cfg.cfgtype == ksk.CFGTYPE_GUILD and ksk.settings.use_ranks, true)
end

function ksk:AddBidder (name, cls, idx, uid, prio, useprio, announce)
  --
  -- Ignore the IDX value passed in and recalculate it from the current
  -- loot members list. Helps prevent a timing issue where a user may
  -- have pressed the bid button before they receive a list change
  -- notification if the ML changes the bid list.
  --
  if (members) then
    for k,v in pairs (members) do
      if (v.id == uid) then
        idx = v.idx
        break
      end
    end
  end

  local ti = { name = name, class = cls, idx = idx, uid = uid, prio = prio }
  tinsert (ksk.bidders, ti)
  tsort (ksk.bidders, function (a, b)
    if (not useprio) then
      return (a.idx < b.idx)
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

  ksk:RefreshBidders ()

  --
  -- If it was me that was just added as a bidder, change my bid button to
  -- retract in case I want to do that.
  --
  if (name == K.player.player) then
    ksk.qf.bidders.mybid:SetText (L["Retract"])
    ksk.qf.bidders.mybid.retract = true
  end

  if (ksk.isml) then
    info (strfmt (L["%s %s on %s on the %s list."], aclass (name, cls), L["bid"], ksk.lootitem.loot.ilink, white (ksk.lists[ksk.lootlistid].name)))
  end

  if (not announce) then
    return
  end

  if (ksk.settings.silent_bid) then
    if (ksk.settings.ann_bid_progress) then
      ksk.SendRaidMsg (strfmt (L["%s: new bid received. Number of bidders: %d."], L["MODTITLE"], #ksk.bidders))
    end
  else
    if (ksk.settings.ann_bid_progress) then
      ksk.SendRaidMsg (strfmt (L["%s: %s (position %d) has bid (highest bidder is %s)."], L["MODABBREV"], name, idx, ksk.bidders[1].name))
    end
    ksk.SendRaidAM ("BIDER", "ALERT", name, cls, idx, uid, prio, useprio)
  end
end

function ksk:RetractBidder (u)
  local found

  if (ksk.rolling) then
    --
    -- If we are rolling for an item and someone retracts, we need to remove
    -- them from the list of rollers.
    --
    return
  end

  for k,v in ipairs (ksk.bidders) do
    if (v.name == u) then
      found = k
      break
    end
  end

  if (found) then
    ksk:DeleteBidder (u, true)
  end
end

function ksk:DeleteBidder (name, announce)
  local class
  if (not ksk.bidders) then
    return
  end
  for k,v in ipairs (ksk.bidders) do
    if (v.name == name) then
      class = v.class
      tremove (ksk.bidders, k)
      break
    end
  end

  ksk:RefreshBidders ()

  --
  -- If it was me that just retracted, change my rettract button to
  -- bid in case I want to do that again.
  --
  if (name == K.player.player) then
    ksk.qf.bidders.mybid:SetText (L["Bid"])
    ksk.qf.bidders.mybid.retract = nil
  end

  if (not class) then
    return
  end

  if (ksk.isml) then
    info (strfmt (L["%s %s on %s on the %s list."], aclass (name, class), L["retracted"], ksk.lootitem.loot.ilink, white (ksk.lootlist.name)))
  end

  if (not announce) then
    return
  end

  if (ksk.settings.silent_bid) then
    if (ksk.settings.ann_bid_progress) then
      ksk.SendRaidMsg (strfmt (L["%s: bid retracted. Number of bidders: %d."], L["MODTITLE"], #ksk.bidders))
    end
  else
    if (ksk.qf.bidscroll.itemcount > 0) then
      if (ksk.settings.ann_bid_progress) then
        ksk.SendRaidMsg (strfmt (L["%s: %s has retracted (highest bidder is %s)."], L["MODABBREV"], name, ksk.bidders[1].name))
      end
    else
      if (ksk.settings.ann_bid_progress) then
        ksk.SendRaidMsg (strfmt (L["%s: %s has retracted (no other bidders)."], L["MODABBREV"], name))
      end
    end
    ksk.SendRaidAM ("BIDRM", "ALERT", name)
  end
end

function ksk:SuicideUser (listid, rlist, uid, cfgid, ilink, chain)
  local cfgid = cfgid or ksk.currentid
  local ia, ruid = ksk:UserIsAlt (uid, nil, cfgid)
  if (not ia or not ksk.configs[cfgid].tethered) then
    ruid = uid
  end
  ksk:SuicideUserLowLevel (listid, rlist, ruid, cfgid, ilink)

  local es = strfmt ("%s:%s:%s", listid, tconcat (rlist, ""), ruid)
  ksk.AddEvent (cfgid, "SULST", es, true)

  if (chain) then
    local ll = ksk.configs[cfgid].lists[listid]
    if (ll.extralist and ll.extralist ~= "0") then
      local trlist = ksk:CreateRaidList (ll.extralist)
      ksk:SuicideUserLowLevel (ll.extralist, trlist, ruid, cfgid, ilink)
      local es = strfmt ("%s:%s:%s", ll.extralist, tconcat (trlist, ""), ruid)
      ksk.AddEvent (cfgid, "SULST", es, true)
    end
  end
end

function ksk:DeleteItem (itemid, cfgid, nocmd)
  local cfg = cfgid or ksk.currentid
  if (not ksk.configs[cfg]) then
    return
  end

  local il = ksk.configs[cfg].items
  if (not il[itemid]) then
    return
  end

  il[itemid] = nil
  ksk.configs[cfg].nitems = ksk.configs[cfg].nitems - 1
  if (cfg == ksk.currentid) then
    if (ksk.itemid == itemid) then
      ksk.itemid = nil
    end
    ksk:RefreshItemList ()
  end

  if (not nocmd) then
    ksk.AddEvent (cfg, "RMITM", itemid)
  end
end

function ksk:AddItem (itemid, itemlink, cfgid, nocmd)
  local cfg = cfgid or ksk.currentid

  if (not ksk.configs[cfg]) then
    return
  end

  local il = ksk.configs[cfg].items
  if (il[itemid]) then
    return
  end

  local ifs = ksk.GetItemClassFilter (itemlink)
  if (ifs == ksk.allclasses) then
    local _, _, _, _, _, _, _, _, slot, _, _, icls, isubcls = GetItemInfo (itemlink)
    if (icls == ksk.classfilters.weapon) then
      ifs = ksk.classfilters.weapons[isubcls]
    elseif (icls == ksk.classfilters.armor) then
      ifs = ksk.classfilters.strict[isubcls]
      if (slot == "INVTYPE_CLOAK") then
        ifs = ksk.classfilters.relaxed[isubcls]
      end
    end
  end

  il[itemid] = { ilink = itemlink, cfilter = ifs }
  ksk.configs[cfg].nitems = ksk.configs[cfg].nitems + 1

  if (not nocmd) then
    local es = strfmt ("%s:%s", itemid, gsub (itemlink, ":", "\7"))
    ksk.AddEvent (cfg, "MKITM", es)
  end

  if (cfg == ksk.currentid) then
    ksk:RefreshItemList ()
  end
end

function ksk:RefreshHistory ()
  ksk.qf.histscroll.itemcount = 0
  if (ksk.cfg.history) then
    ksk.qf.histscroll.itemcount = #ksk.cfg.history
  end
  if (ksk.qf.histscroll.itemcount > 0) then
    -- Resort the list as we may have receieved new loot info
    tsort (ksk.cfg.history, function (a, b)
      return tonumber(strsub (a, 1, 12)) > tonumber(strsub (b, 1, 12))
    end)
  end
  ksk.qf.histscroll:UpdateList ()
  ksk.qf.histscroll:SetSelected (nil)
end

function ksk:AddLootHistory (cfg, when, what, who, how, norefresh, nocmd)
  local cfg = cfg or ksk.currentid
  --
  -- IMPORTANT: If this changes, change KSK-Users.lua too in DeleteUser
  --
  local ts = strfmt ("%s\7%s\7%s\7%s", when, what, who, how)

  if (ksk.configs[cfg].settings.history) then
    tinsert (ksk.configs[cfg].history, ts)
  end

  if (not norefresh and cfg == ksk.currentid) then
    ksk:RefreshHistory ()
  end

  if (not nocmd) then
    ksk.AddEvent (cfg, "LHADD", strfmt ("%s:%s:%s:%s", when,
      gsub (what, ":", "\7"), who, how))
  end
end

function ksk:AddLoot (ilink, nocmd)
  local added = false
  if (ksk.bossloot) then
    added = true
  end
  ksk:AddItemToBossLoot (ilink, 1)
  ksk.qf.lootscroll.itemcount = #ksk.bossloot
  ksk.qf.lootscroll:UpdateList ()

  if (not added) then
    --
    -- This is the only item. Possibly open the loot window and send out
    -- a faked OLOOT event (if we are sending events)
    --
    if (not nocmd) then
      ksk.SendRaidAM ("OLOOT", "ALERT", K.player.player, "0", false, { { ilink, 1 } })
      if (not ksk.mainwin:IsVisible ()) then
        ksk.autoshown = true
      end
      ksk.mainwin:Show ()
      ksk.mainwin:SetTab (ksk.LOOT_TAB, ksk.LOOT_ASSIGN_TAB)
    end
  else
    if (not nocmd) then
      ksk.SendRaidAM ("ALOOT", "ALERT", ilink)
    end
  end
end

function ksk:UndoSuicide (cfg, listid, movers, uid, ilink, nocmd)
  ksk:AddLoot (ilink, nocmd)
  ksk:AddLootHistory (cfg, ksk:TimeStamp (), ilink, uid, "U")
  local mpos = {}
  for k,v in ipairs (movers) do
    local il, lp = ksk:UserInList (v, listid)
    assert (il)
    tinsert (mpos, lp)
  end

  --
  -- The movers array has all of the appropriate people that moved, in order,
  -- *before* they moved. But their position is calculated now, which is
  -- *after* the move. The first user in the movers array should always be
  -- the same as uid, and we assert that here. We walk backwards through
  -- the position array moving everyone down one position, and then put
  -- the UID at the top. This effectively undoes the suicide.
  --
  assert (movers[1] == uid)

  local ncount = #movers
  local lu = ksk.configs[cfg].lists[listid].users
  for i = ncount, 2, -1 do
    lu[mpos[i-1]] = movers[i]
  end
  lu[mpos[ncount]] = uid
  ksk:RefreshLists ()

  if (not nocmd) then
    local es = strfmt ("%s:%s:%s:%s", listid, tconcat (movers, ""), uid, gsub (ilink, ":", "\7"))
    ksk.AddEvent (cfg, "SUNDO", es)
  end
end

function ksk:CleanupLootRoll ()
  if (ksk.rolling) then
    ksk:EndOpenRoll ()
    ksk.SendRaidAM ("EROLL", "ALERT")
  end
  local rlf = ksk.qf.lootroll
  rlf:UnregisterEvent ("CHAT_MSG_SYSTEM")
  rlf:SetScript ("OnEvent", nil)
  rlf.timerbar:SetScript ("OnUpdate", nil)
  if (ksk.lootroll and ksk.lootroll.lhdisabled) then
    loothog_turnoff()
  end
  ksk.rolling = nil
  ksk.lootroll = nil
  ksk.qf.lootwin.oclbids:SetText (L["Open Bids"])
  ksk.qf.lootwin.orpause:SetText (L["Open Roll"])
  ksk.qf.lootwin.remcancel:SetText (L["Remove"])
  local en = false
  if (ksk.csd.isadmin ~= nil) and (ksk.isml == true) and ksk.selectedloot then
    en = true
  end
  ksk.qf.lootwin.oclbids:SetEnabled (en)
  ksk.qf.lootwin.orpause:SetEnabled (en)
  ksk.qf.lootwin.remcancel:SetEnabled (en)
end

function ksk:StartOpenRoll (ilink)
  ksk.qf.bidders.mybid:SetEnabled (true)
  ksk.qf.bidders.forcebid:SetEnabled (true)
  ksk.qf.bidders.forceret:SetEnabled (true)
  ksk.qf.bidders.forcebid:SetShown (true)
  ksk.qf.bidders.forceret:SetShown (true)
  ksk.qf.bidders.mybid:SetText (L["Roll (main)"])
  ksk.qf.bidders.forcebid:SetText (L["Roll (offspec)"])
  ksk.qf.bidders.forceret:SetText (L["Cancel Roll"])
end

function ksk:EndOpenRoll ()
  local en = false
  if (ksk.csd.isadmin) then
    en = true
  end
  ksk.qf.bidders.mybid:SetEnabled (false)
  ksk.qf.bidders.forcebid:SetEnabled (false)
  ksk.qf.bidders.forceret:SetEnabled (false)
  ksk.qf.bidders.forcebid:SetShown (en)
  ksk.qf.bidders.forceret:SetShown (en)
  ksk.qf.bidders.mybid:SetText (L["Bid"])
  ksk.qf.bidders.forcebid:SetText (L["Force Bid"])
  ksk.qf.bidders.forceret:SetText (L["Force Retract"])
end

