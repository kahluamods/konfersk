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

if (not K) then
  return
end

local ksk = K:GetAddon("KKonferSK")
local L = ksk.L
local KUI = ksk.KUI
local KRP = ksk.KRP
local KK = ksk.KK
local MakeFrame = KUI.MakeFrame

-- Local aliases for global or LUA library functions
local _G = _G
local tinsert = table.insert
local tconcat = table.concat
local tsort = table.sort
local strlower = string.lower
local strfmt = string.format
local strsub = string.sub
local strlen = string.len
local pairs, ipairs, next = pairs, ipairs, next
local assert = assert

local white = ksk.white
local aclass = ksk.aclass
local info = ksk.info
local err = ksk.err
local debug = ksk.debug

local CFGTYPE_GUILD = KK.CFGTYPE_GUILD
local CFGTYPE_PUG   = KK.CFGTYPE_PUG

--[[
This file implements the configuration UI and provides functions for
manipulating various config options and refreshing the data. Most of
this code can only be run by an administrator although anyone can switch
active configurations.

The main UI creation function is ksk:InitialiseConfigUI() and it creates the
config tab contents and the three pages. The main data refresh function is
ksk:RefreshConfigUI(). However, there are a number of sub refresh functions
which reset only portions of the UI or stored data, all of which are called by
ksk:RefreshConfigUI().

ksk:RefreshConfigLootUI(reset)
  Refreshes the loot distribution options page of the config tab.

ksk:RefreshConfigRollUI(reset)
  Refreshes the loot rolling options page of the config tab.

ksk:RefreshConfigAdminUI(reset)
  Refreshes the config admin page of the config tab.
]]

local admincfg = nil
local sortedconfigs = nil
local coadmin_selected = nil
local sortedadmins = nil
local newcfgdlg = nil
local copycfgdlg = nil
local orankdlg = nil
local rankpriodlg = nil
local coadmin_popup = nil
local silent_delete = nil

local qf = {}

--
-- We have a finite number of admins, in order to ensure that unique user
-- ID's will be created by each admin, so there is no clash when syncing.
-- This is the list of admin "prefixes" for the admins. Everything else is
-- in lower case in the system so we preserve that, using lower case letters
-- and numbers, making the total possible number of admins 36. This is the
-- numbering sequence for the admin ID.
--
local adminidseq = "0123456789abcdefghijklmnopqrstuvwxyz"

--
-- This file contains all of the UI handling code for the config panel,
-- as well as all config space manipulation functions. Since this code
-- deals with config spaces themselves, its data model is slightly
-- different. All of the main config options etc use the standard data
-- model but the admin screen has a different notion of the "current"
-- configuration. For that screen and that screen only, the configuration
-- it works with is dictated by the local variable admincfg, which is set
-- when a configuration space is selected in the left hand panel.
--

local function refresh_coadmins(self)
  if (not admincfg) then
    qf.coadminscroll.itemcount = 0
    qf.coadminscroll:UpdateList()
    return
  end

  local newadmins = {}
  local ownerlist = {}
  local tc = self.frdb.configs[admincfg]
  local ul = self.frdb.configs[admincfg].users

  coadmin_selected = nil

  for k,v in pairs(tc.admins) do
    tinsert(newadmins, k)
  end
  tsort(newadmins, function(a, b)
    return ul[a].name < ul[b].name
  end)

  for k,v in pairs(newadmins) do
    tinsert(ownerlist, { text = aclass(ul[v]), value = v })
  end

  sortedadmins = newadmins

  qf.coadminscroll.itemcount = #sortedadmins
  qf.coadminscroll:UpdateList()
  qf.coadminscroll:SetSelected(nil)

  -- UpdateItems in case we are now a co-admin and the color of the config
  -- dropdown line item changes.
  qf.cfgownerdd:UpdateItems(ownerlist)

  -- Don't throw an OnValueChanged event as that could have been what called us
  -- and we don't want to create an infinite loop.
  qf.cfgownerdd:SetValue(tc.owner, true)
end

--
-- This is a helper function for when a configuration is selected from the
-- list of possible configurations in the admin screen. It updates and
-- populates the admin options on the right side panel.
--
local function config_selectitem(objp, idx, slot, btn, onoff)
  local onoff = onoff or false
  local en = false

  if (onoff and K.player.is_guilded and K.player.is_gm) then
    en = true
  end

  qf.cfgopts.cfgowner:SetEnabled(onoff)
  qf.cfgopts.cfgtype:SetEnabled(en)
  qf.cfgopts.orankedit:SetEnabled(en)
  qf.cfgdelbutton:SetEnabled(onoff)
  qf.cfgrenbutton:SetEnabled(onoff)
  qf.cfgcopybutton:SetEnabled(onoff)
  qf.coadadd:SetEnabled(onoff)

  if (onoff) then
    admincfg = sortedconfigs[idx].id
    local lcf = ksk.frdb.configs[admincfg]

    qf.cfgopts.cfgowner:SetValue(lcf.owner)
    qf.cfgopts.cfgtype:SetValue(lcf.cfgtype)

    en = ksk.csdata[admincfg].is_admin == 2 and true or false

    if (lcf.nadmins > 1) then
      qf.cfgopts.cfgowner:SetEnabled(en)
    else
      qf.cfgopts.cfgowner:SetEnabled(false)
    end

    if (lcf.cfgtype ~= CFGTYPE_GUILD) then
      qf.cfgopts.orankedit:SetEnabled(false)
    end

    qf.coadadd:SetEnabled(en and lcf.nadmins < 36)
    qf.cfgrenbutton:SetEnabled(en)

    if (not ksk:CanChangeConfigType()) then
      en = false
    end
    qf.cfgopts.cfgtype:SetEnabled(en)

    if (ksk.frdb.nconfigs > 1) then
      qf.cfgdelbutton:SetEnabled(true)
    else
      qf.cfgdelbutton:SetEnabled(false)
    end
  else
    admincfg = nil
  end

  refresh_coadmins(ksk)
end

--
-- Helper function for dealing with the selected item in the coadmin scroll
-- list.
--
local function coadmin_list_selectitem(objp, idx, slot, btn, onoff)
  local en = false
  local onoff = onoff or false

  if (onoff and admincfg) then
    local lcf = ksk.frdb.configs[admincfg]

    coadmin_selected = sortedadmins[idx]

    if (coadmin_selected ~= lcf.owner) then
      en = ksk.csdata[admincfg].is_admin == 2 and true or false
    end
  else
    coadmin_selected = nil
  end

  qf.coaddel:SetEnabled(en)
end

-- Low level helper function to add a new co-admin
local function add_coadmin(this, uid, cfgid)
  local pcc = this.frdb.configs[cfgid]

  if (not pcc) then
    return
  end

  local newid
  for i = 1, 36 do
    local id = strsub(adminidseq, i, i)
    local found = false
    for k,v in pairs(pcc.admins) do
      if (v.id == id) then
        found = true
        break
      end
    end
    if (not found) then
      newid = id
      break
    end
  end
  assert(newid, "fatal logic bug somewhere!")

  -- Must add the event BEFORE we add the admin
  this:AdminEvent(cfgid, "MKADM", uid, newid)
  pcc.nadmins = pcc.nadmins + 1
  pcc.admins[uid] = { id = newid }
end

local function new_space_button(this)
  local box

  if (not newcfgdlg) then
    newcfgdlg, box = K.SingleStringInputDialog(this, "KSKSetupNewSpace",
      L["Create Configuration"], L["NEWMSG"], 400, 165)

    local function verify_with_create(objp, val)
      if (strlen(val) < 1) then
        err(L["invalid configuration space name. Please try again."])
        objp:Show()
        objp.ebox:SetFocus()
        return true
      end
      local err = this:CreateNewConfig(val, false)
      if (err) then
        objp:Show()
        objp.ebox:SetFocus()
        return true
      end
      newcfgdlg:Hide()
      this.mainwin:Show()
      return false
    end

    newcfgdlg:Catch("OnAccept", function(t, evt)
      return verify_with_create(this, t.ebox:GetText())
    end)

    newcfgdlg:Catch("OnCancel", function(t, evt)
      newcfgdlg:Hide()
      this.mainwin:Show()
      return false
    end)

    box:Catch("OnEnterPressed", function(t, evt, val)
      return verify_with_create(this, val)
    end)
  else
    box = newcfgdlg.ebox
  end

  box:SetText("")

  this.mainwin:Hide()
  newcfgdlg:Show()
  box:SetFocus()
end

local function rename_space_button(this, cfgid)
  local function rename_helper(newname, old)
    local rv = this:RenameConfig(old, newname)
    if (rv) then
      return true
    end

    return false
  end

  K.RenameDialog(this, L["Rename Configuration"], L["Old Name"],
    this.frdb.configs[cfgid].name, L["New Name"], 32, rename_helper,
    cfgid, true, this.mainwin)
end

local function copy_space_button(this, cfgid, newname, newid, shown)
  if (not copycfgdlg) then
    local ypos = 0
    local arg = {
      x = "CENTER", y = "MIDDLE",
      name = "KSKCopyConfigDialog",
      title = L["Copy Configuration"],
      border = true,
      width = 450,
      height = 245,
      canmove = true,
      canresize = false,
      escclose = true,
      blackbg = true,
      okbutton = { text = K.ACCEPTSTR },
      cancelbutton = { text = K.CANCELSTR },
    }
    local ret = KUI:CreateDialogFrame(arg)

    arg = {
      x = 0, y = ypos, width = 200, height = 20, autosize = false,
      justifyh = "RIGHT", font = "GameFontNormal",
      text = L["Source Configuration"],
    }
    ret.str1 = KUI:CreateStringLabel(arg, ret)

    arg.justifyh = "LEFT"
    arg.text = ""
    arg.border = true
    arg.color = {r = 1, g = 1, b = 1, a = 1 }
    ret.str2 = KUI:CreateStringLabel(arg, ret)
    ret.str2:ClearAllPoints()
    ret.str2:SetPoint("TOPLEFT", ret.str1, "TOPRIGHT", 12, 0)
    ypos = ypos - 24

    arg = {
      x = 0, y = ypos, width = 200, height = 20, autosize = false,
      justifyh = "RIGHT", font = "GameFontNormal",
      text = L["Destination Configuration"],
    }
    ret.str3 = KUI:CreateStringLabel(arg, ret)

    arg.justifyh = "LEFT"
    arg.text = ""
    arg.border = true
    arg.color = {r = 1, g = 1, b = 1, a = 1 }
    ret.str4 = KUI:CreateStringLabel(arg, ret)
    ret.str4:ClearAllPoints()
    ret.str4:SetPoint("TOPLEFT", ret.str3, "TOPRIGHT", 12, 0)

    arg = {
      x = 0, y = ypos, width = 200, height = 20, len = 32,
    }
    ret.dest = KUI:CreateEditBox(arg, ret)
    ret.dest:ClearAllPoints()
    ret.dest:SetPoint("TOPLEFT", ret.str3, "TOPRIGHT", 12, 0)
    ret.dest:Catch("OnValueChanged", function(t, evt, newv)
      copycfgdlg.newname = newv
    end)
    ypos = ypos - 24

    local xpos = 90
    arg = {
      x = xpos, y = ypos, name = "KSKCopyListDD",
      dwidth = 175, items = KUI.emptydropdown, itemheight = 16,
      title = { text = L["Roll Lists to Copy"] }, mode = "MULTI",
    }
    ret.ltocopy = KUI:CreateDropDown(arg, ret)
    ypos = ypos - 32

    arg = {
      x = xpos, y = ypos, label =  { text = L["Copy Co-admins"] },
    }
    ret.copyadm = KUI:CreateCheckBox(arg, ret)
    ret.copyadm:Catch("OnValueChanged", function(t, evt, val)
      copycfgdlg.do_copyadm = val
    end)
    ypos = ypos - 24

    arg = {
      x = xpos, y = ypos, label = { text = L["Copy All User Flags"] },
    }
    ret.copyflags = KUI:CreateCheckBox(arg, ret)
    ret.copyflags:Catch("OnValueChanged", function(t, evt, val)
      copycfgdlg.do_copyflags = val
    end)
    ypos = ypos - 24

    arg = {
      x = xpos, y = ypos, label = { text = L["Copy Configuration Options"] },
    }
    ret.copycfg = KUI:CreateCheckBox(arg, ret)
    ret.copycfg:Catch("OnValueChanged", function(t, evt, val)
      copycfgdlg.do_copycfg = val
    end)
    ypos = ypos - 24

    arg = {
      x = xpos, y = ypos, label = { text = L["Copy Item Options"] },
    }
    ret.copyitem = KUI:CreateCheckBox(arg, ret)
    ret.copyitem:Catch("OnValueChanged", function(t, evt, val)
      copycfgdlg.do_copyitems = val
    end)
    ypos = ypos - 24

    copycfgdlg = ret

    ret.OnAccept = function(t)
      --
      -- First things first, see if we need to create the new configuration
      -- or if we are copying into it.
      --
      if (not copycfgdlg.newname or copycfgdlg.newname == "") then
        err(L["invalid configuration name. Please try again."])
        return
      end
      if (copycfgdlg.newid == 0) then
        copycfgdlg.newid = this:FindConfig(copycfgdlg.newname) or 0
      end

      if (copycfgdlg.newid == 0) then
        local rv, ni = this:CreateNewConfig(copycfgdlg.newname, false)
        if (rv) then
          return
        end
        copycfgdlg.newid = ni
      end

      local newid = copycfgdlg.newid
      local cfgid = copycfgdlg.cfgid

      local dc = this.frdb.configs[newid]
      local sc = this.frdb.configs[cfgid]

      --
      -- Copy the users. We cannot do a blind copy of the user ID's as the user
      -- may already exist in the configuration with a different ID, so we have
      -- to search the new configuration for each user. We go through the list
      -- twice, the first time skipping alts, the second time just dealing with
      -- alts. For the various user flags, we have to do them individually, as
      -- we may need to send out events for each change to the new user.
      --
      for k,v in pairs(sc.users) do
        if (not v.main) then
          local du = this:FindUser(v.name, newid)
          if (not du) then
            du = this:CreateNewUser(v.name, v.class, newid, true, true, nil, true)
          end
          if (copycfgdlg.do_copyflags) then
            local fs
            fs = this:UserIsEnchanter(k, v.flags, cfgid)
            this:SetUserEnchanter(du, fs, newid)
            fs = this:UserIsFrozen(k, v.flags, cfgid)
            this:SetUserFrozen(du, fs, newid)
          end
        end
      end

      for k,v in pairs(sc.users) do
        if (v.main) then
          local du = this:FindUser(v.name, newid)
          if (not du) then
            du = this:CreateNewUser(v.name, v.class, newid, true, true)
          end
          if (copyflags) then
            local fs
            fs = this:UserIsEnchanter(k, v.flags, cfgid)
            this:SetUserEnchanter(du, fs, newid)
            fs = this:UserIsFrozen(k, v.flags, cfgid)
            this:SetUserFrozen(du, fs, newid)
          end
          local mu = this:FindUser(sc.users[v.main].name, newid)
          this:SetUserIsAlt(du, true, mu, newid)
        end
      end

      --
      -- Now copy the roll lists (if any) we have been asked to copy.
      --
      for k,v in pairs(copycfgdlg.copylist) do
        if (v == true) then
          --
          -- We can use the handy SMLST event to set the member list.
          -- That event was originally intended for the CSV import
          -- function but it serves our purposes perfectly as we can
          -- set the entire member list with one event. No need to
          -- recreate lists or anything like that.
          --
          local sl = sc.lists[k]
          local dlid = this:FindList(sl.name, newid)
          if (not dlid) then
            --
            -- Need to create the list
            --
            local rv, ri = this:CreateNewList(sl.name, newid)
            assert(not rv)
            dlid = ri
          end
          local dul = {}
          for kk,vv in ipairs(sl.users) do
            -- Find the user in the new config
            local du = this:FindUser(sc.users[vv].name, newid)
            assert(du)
            tinsert(dul, du)
          end
          local dus = tconcat(dul, "")
          this:SetMemberList(dus, dlid, newid)

          --
          -- Copy the list options and prepare a CHLST event
          --
          if (copycfgdlg.do_copycfg) then
            local dl = dc.lists[dlid]
            dl.sortorder = sl.sortorder
            dl.def_rank = sl.def_rank
            dl.strictcfilter = sl.strictcfilter
            dl.strictrfilter = sl.strictrfilter
            if (sl.extralist ~= "0") then
              dl.extralist = this:FindList(sc.lists[sl.extralist].name, newid) or "0"
            end
            dl.tethered = sl.tethered
            -- If this changes MUST change in KSK-Comms.lua(CHLST)
            this:AdminEvent(newid, "CHLST", dlid, tonumber(dl.sortorder), tonumber(dl.def_rank),
              dl.strictcfilter and true or false, dl.strictrfilter and true or false,
              dl.extralist, dl.tethered and true or false, dl.altdisp and true or false)
          end
        end
      end

      --
      -- Next up are the item options, if we have been asked to copy them.
      -- We only copy items that do not exist. If the item exists in the
      -- new config we leave it completely untouched.
      --
      if (copycfgdlg.do_copyitems) then
        local sil = sc.items
        local dil = dc.items

        for k,v in pairs(sil) do
          if (not dil[k]) then
            this:AddItem(k, v.ilink, newid)
            K.CopyTable(v, dil[k])
            --
            -- Obviously the UID for assign to next user will be
            -- different, so we adjust for that.
            --
            if (v.user) then
              dil[k].user = this:FindUser(sc.users[v.user].name, newid)
              assert(dil[k].user)
            end
            this:SendCHITM(k, dil[k], newid)
          end
        end
      end

      --
      -- If we have been asked to preserve all of the config options then
      -- copy them over now, but we will have to adjust the disenchanter
      -- UIDs.
      --
      if (copycfgdlg.do_copycfg) then
        K.CopyTable(sc.settings, dc.settings)
        for k,v in pairs(sc.settings.denchers) do
          if (v) then
            dc.settings.denchers[k] = this:FindUser(sc.users[v].name, newid)
          end
        end
        dc.cfgtype = sc.cfgtype
        dc.owner = this:FindUser(sc.users[sc.owner].name, newid)
        dc.oranks = sc.oranks
      end

      --
      -- If they want to copy co-admins do so now.
      --
      if (copycfgdlg.do_copyadm) then
        for k,v in pairs(sc.admins) do
          local uid = this:FindUser(sc.users[k].name, newid)
          if (not dc.admins[uid]) then
            add_coadmin(this, uid, newid)
          end
        end
      end

      this:FullRefresh(true)

      copycfgdlg:Hide()
      if (copycfgdlg.isshown) then
        this.mainwin:Show()
      end
    end

    ret.OnCancel = function(t)
      copycfgdlg:Hide()
      if (copycfgdlg.isshown) then
        this.mainwin:Show()
      end
    end
  end

  copycfgdlg.do_copyadm = false
  copycfgdlg.do_copyflags = true
  copycfgdlg.do_copycfg = true
  copycfgdlg.do_copyraid = false
  copycfgdlg.do_copyitems = false
  copycfgdlg.copylist = {}
  copycfgdlg.newname = newname or ""
  copycfgdlg.newid = newid or 0
  copycfgdlg.cfgid = cfgid

  --
  -- Each time we are called we need to populate the dropdown list so that
  -- it has the correct list of lists.
  --
  local function set_list(btn)
    copycfgdlg.copylist[btn.value] = btn.checked
  end

  local items = {}
  for k,v in pairs(this.frdb.configs[cfgid].lists) do
    local ti = { text = v.name, value = k, keep = true, func = set_list }
    ti.checked = function()
      return copycfgdlg.copylist[k]
    end
    tinsert(items, ti)
  end
  tsort(items, function(a,b)
    return strlower(a.text) < strlower(b.text)
  end)
  copycfgdlg.ltocopy:UpdateItems(items)

  copycfgdlg.copyadm:SetChecked(copycfgdlg.do_copyadm)
  copycfgdlg.copyflags:SetChecked(copycfgdlg.do_copyflags)
  copycfgdlg.copycfg:SetChecked(copycfgdlg.do_copycfg)
  copycfgdlg.copyitem:SetChecked(copycfgdlg.do_copyitems)

  if (not copycfgdlg.newid or copycfgdlg.newid == 0) then
    copycfgdlg.str4:Hide()
    copycfgdlg.dest:Show()
    copycfgdlg.dest:SetText(copycfgdlg.newname)
  else
    copycfgdlg.dest:Hide()
    copycfgdlg.str4:Show()
    copycfgdlg.str4:SetText(copycfgdlg.newname)
  end
  copycfgdlg.str2:SetText(this.frdb.configs[cfgid].name)

  copycfgdlg.isshown = shown
  this.mainwin:Hide()
  copycfgdlg:Show()
end

function ksk:CopyConfigSpace(cfgid, newname, newid)
  copy_space_button(self, cfgid, newname, newid, self.mainwin:IsShown())
end

local dencher_popup
local which_dencher
local which_dench_lbl

local function select_dencher(this, btn, lbl, num)
  if (this.popupwindow) then
    this.popupwindow:Hide()
    this.popupwindow = nil
  end
  local ulist = {}

  which_dencher = num
  which_dench_lbl = lbl

  tinsert(ulist, { value = 0, text = L["None"] })
  for k,v in ipairs(this.sortedusers) do
    local ok = true
    for i = 1, this.MAX_DENCHERS do
      if (this.cfg.settings.denchers[i] == v.id) then
        ok = false
      end
    end
    if (ok and this:UserIsEnchanter(v.id)) then
      local ti = { value = v.id, text = aclass(this.cfg.users[v.id]) }
      tinsert(ulist, ti)
    end
  end

  local function pop_func(uid)
    if (uid == 0) then
      this.cfg.settings.denchers[which_dencher] = nil
      which_dench_lbl:SetText("")
    else
      which_dench_lbl:SetText(aclass(this.cfg.users[uid]))
      this.cfg.settings.denchers[which_dencher] = uid
    end

    --
    -- If we're in raid, refresh the raid's notion of possible denchers.
    --
    if (this.users) then
      this:UpdateDenchers()
    end
    this.popupwindow:Hide()
    this.popupwindow = nil
  end

  if (not dencher_popup) then
    dencher_popup = K.PopupSelectionList(this, "KSKDencherPopup",
      ulist, L["Select Enchanter"], 225, 400, btn, 16, 
      function(val) pop_func(val) end)
  end
  dencher_popup:UpdateList(ulist)
  dencher_popup:ClearAllPoints()
  dencher_popup:SetPoint("TOPLEFT", btn, "TOPRIGHT", 0, dencher_popup:GetHeight() /2)
  dencher_popup:Show()
  this.popupwindow = dencher_popup
end

local function change_cfg(this, which, val)
  if (this.cfg and this.cfg.settings) then
    this.cfg.settings[which] = val
  end
end

local function rank_editor(this)
  if (not rankpriodlg) then
    local ypos = 0
    local arg = {
      x = "CENTER", y = "MIDDLE",
      name = "KSKRankEditorDialog",
      title = L["Edit Rank Priorities"],
      border = true,
      width = 320,
      height = ((K.guild.numranks +1) * 28) + 70,
      canmove = true,
      canresize = false,
      escclose = true,
      blackbg = true,
      okbutton = { text = K.ACCEPTSTR },
      cancelbutton = { text = K.CANCELSTR },
    }
    local ret = KUI:CreateDialogFrame(arg)

    arg = {
      x = 8, y = 0, height = 20, text = L["Guild Rank"],
      font = "GameFontNormal",
    }
    ret.glbl = KUI:CreateStringLabel(arg, ret)

    arg.x = 225
    arg.text = L["Priority"]
    ret.plbl = KUI:CreateStringLabel(arg, ret)

    arg = {
      x = 8, y = 0, width = 215, text = "",
    }
    earg = {
      x = 225, y = 0, width = 36, initialvalue = "1", numeric = true, len = 2,
    }
    for i = 1, 10 do
      local rlbl = "ranklbl" .. tostring(i)
      local rpe = "rankprio" .. tostring(i)
      arg.y = arg.y - 24
      ret[rlbl] = KUI:CreateStringLabel(arg, ret)
      earg.x = 225
      earg.y = earg.y - 24
      ret[rpe] = KUI:CreateEditBox(earg, ret)
      ret[rlbl]:Hide()
      ret[rpe]:Hide()
    end

    ret.OnCancel = function(t)
      t:Hide()
      this.mainwin:Show()
    end

    ret.OnAccept = function(t)
      this.cfg.settings.rank_prio = {}
      for i = 1, K.guild.numranks do
        local rpe = "rankprio" .. tostring(i)
        local tv = ret[rpe]:GetText()
        if (tv == "") then
          tv = "1"
        end
        local rrp = tonumber(tv)
        if (rrp < 1) then
          rrp = 1
        end
        if (rrp > 10) then
          rrp = 10
        end
        this.cfg.settings.rank_prio[i] = rrp
      end
      t:Hide()
      this.mainwin:Show()
    end

    rankpriodlg = ret
  end

  local rp = rankpriodlg
  rp:SetHeight(((K.guild.numranks + 1) * 28) + 50)

  for i = 1, 10 do
    local rlbl = "ranklbl" .. tostring(i)
    local rpe = "rankprio" .. tostring(i)
    rp[rlbl]:Hide()
    rp[rpe]:Hide()
  end

  for i = 1, K.guild.numranks do
    local rlbl = "ranklbl" .. tostring(i)
    local rpe = "rankprio" .. tostring(i)
    rp[rlbl]:SetText(K.guild.ranks[i])
    rp[rpe]:SetText(tostring(this.cfg.settings.rank_prio[i] or 1))
    rp[rlbl]:Show()
    rp[rpe]:Show()
  end

  rp:Show()
end

local function orank_edit_button(self)
  if (not orankdlg) then
    local arg = {
      x = "CENTER", y = "MIDDLE",
      name = "KSKiOfficerRankEditDlg",
      title = L["Set Guild Officer Ranks"],
      border = true,
      width = 240,
      height = 372,
      canmove = true,
      canresize = false,
      escclose = true,
      blackbg = true,
      okbutton = { text = K.ACCEPTSTR },
      cancelbutton = {text = K.CANCELSTR },
    }

    local y = 24

    local ret = KUI:CreateDialogFrame(arg)

    arg = {
      width = 170, height = 24
    }
    for i = 1, 10 do
      y = y - 24
      local cbn = "orankcb" .. tostring(i)
      arg.y = y
      arg.x = 10
      arg.label = { text = " " }
      ret[cbn] = KUI:CreateCheckBox(arg, ret)
    end

    ret.OnCancel = function(this)
      this:Hide()
      self.mainwin:Show()
    end

    ret.OnAccept = function(this)
      local ccs
      local oranks = ""
      for i = 1, K.guild.numranks do
        ccs = "orankcb" .. tostring(i)
        if (this[ccs]:GetChecked()) then
          oranks = oranks .. "1"
        else
          oranks = oranks .. "0"
        end
      end
      oranks = strsub(oranks .. "0000000000", 1, 10)
      self.frdb.configs[admincfg].oranks = oranks
      self:SendAM("ORANK", "ALERT", oranks)
      this:Hide()
      self.mainwin:Show()
    end

    orankdlg = ret
  end

  local rp = orankdlg
  local lcf = self.frdb.configs[admincfg]
  rp:SetHeight(((K.guild.numranks + 1) * 28) + 10)

  for i = 1, 10 do
    local rcb = "orankcb" .. tostring(i)
    if (K.guild.ranks[i]) then
      rp[rcb]:SetText(K.guild.ranks[i])
      rp[rcb]:Show()
      rp[rcb]:SetChecked(strsub(lcf.oranks, i, i) == "1")
    else
      rp[rcb]:Hide()
    end
  end

  self.mainwin:Hide()
  rp:Show()
end

function ksk:InitialiseConfigUI()
  local arg
  local kmt = self.mainwin.tabs[self.CONFIG_TAB]

  -- First set up the quick access frames we will be using.
  qf.lootopts = kmt.tabs[self.CONFIG_LOOT_PAGE].content
  qf.rollopts = kmt.tabs[self.CONFIG_ROLLS_PAGE].content
  qf.cfgadmin = kmt.tabs[self.CONFIG_ADMIN_PAGE].content

  --
  -- Config panel, loot tab
  --
  local ypos = 0

  local cf = qf.lootopts

  arg = {
    x = 0, y = ypos,
    label = { text = L["Auto-open Bid Panel When Corpse Looted"] },
    tooltip = { title = "$$", text = L["TIP001"] },
  }
  cf.autobid = KUI:CreateCheckBox(arg, cf)
  cf.autobid:Catch("OnValueChanged", function(this, evt, val)
    change_cfg(self, "auto_bid", val)
  end)
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, label = { text = L["Silent Bidding"] },
    tooltip = { title = "$$", text = L["TIP002"] },
  }
  cf.silentbid = KUI:CreateCheckBox(arg, cf)
  cf.silentbid:Catch("OnValueChanged", function(this, evt, val)
    change_cfg(self, "silent_bid", val)
  end)

  arg = {
    x = 225, y = ypos, label = { text = L["Display Tooltips in Loot List"] },
    tooltip = { title = "$$", text = L["TIP003"] },
  }
  cf.tooltips = KUI:CreateCheckBox(arg, cf)
  cf.tooltips:Catch("OnValueChanged", function(this, evt, val)
    change_cfg(self, "tooltips", val)
  end)
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, label = { text = L["Enable Chat Message Filter"] },
    tooltip = { title = "$$", text = L["TIP004"] },
  }
  cf.chatfilter = KUI:CreateCheckBox(arg, cf)
  cf.chatfilter:Catch("OnValueChanged", function(this, evt, val)
    change_cfg(self, "chat_filter", val)
    -- This will cause the chat filters to be reset
    self:UpdateUserSecurity()
  end)

  arg = {
    x = 225, y = ypos, label = { text = L["Record Loot Assignment History"] },
    tooltip = { title = "$$", text = L["TIP005"] },
  }
  cf.history = KUI:CreateCheckBox(arg, cf)
  cf.history:Catch("OnValueChanged", function(this, evt, val, usr)
    change_cfg(self, "history", val)
    if (usr and not val) then
      self.cfg.history = {}
      self:RefreshHistory()
    end
  end)
  ypos = ypos - 24

  arg = {
    x = 4, y = ypos, name = "KSKAnnounceWhereDropDown", label = { text = L["Announce Loot"], pos = "LEFT" },
    itemheight = 16, mode = "SINGLE", border = "THIN", dwidth = 125, items = {
      { text = L["Nowhere"], value = 0, tooltip = { title = "$$", text = L["TIP006.1"] }, },
      { text = L["In Guild Chat"], value = 1, tooltip = { title = "$$", text = L["TIP006.2"] }, },
      { text = L["In Raid Chat"], value = 2, tooltip = { title = "$$", text = L["TIP006.3"] }, },
    }, tooltip = { title = "$$", text = L["TIP006"] },
  }
  cf.announcewhere = KUI:CreateDropDown(arg, cf)
  cf.announcewhere:Catch("OnValueChanged", function(this, evt, newv)
    change_cfg(self, "announce_where", newv)
  end)

  local function is_oaf_checked(this)
    if (self.cfg and self.cfg.settings) then
      return self.cfg.settings[this.value]
    end
    return false
  end

  arg = {
    x = 275, y = ypos, name = "KSKAnnouncementsDropDown", itemheight = 16, dwidth = 175, mode = "MULTI",
    title = { text = L["Other Announcements"],}, is_checked = is_oaf_checked,
    tooltip = { title = "$$", text = L["TIP007"] }, border = "THIN",
    items = {
      { text = L["Announce Bid List Changes"], value = "ann_bidchanges", tooltip = { title = "$$", text = L["TIP007.1"] }, },
      { text = L["Announce Winners in Raid"], value = "ann_winners_raid", tooltip = { title = "$$", text = L["TIP007.2"] }, },
      { text = L["Announce Winners in Guild Chat"], value = "ann_winners_guild", tooltip = { title = "$$", text = L["TIP007.3"] }, },
      { text = L["Announce Bid Progression"], value = "ann_bid_progress", tooltip = { title = "$$", text = L["TIP007.4"] }, },
      { text = L["Usage Message When Bids Open"], value = "ann_bid_usage", tooltip = { title = "$$", text = L["TIP007.5"] }, },
      { text = L["Announce Bid / Roll Cancelation"], value = "ann_cancel", tooltip = { title = "$$", text = L["TIP007.9"] }, },
      { text = L["Announce When No Successful Bids"], value = "ann_no_bids", tooltip = { title = "$$", text = L["TIP007.10"] }, },
      { text = L["Raiders Not on Current List"], value = "ann_missing", tooltip = { title = "$$", text = L["TIP007.11"] }, },
    },
  }
  cf.otherannounce = KUI:CreateDropDown(arg, cf)
  cf.otherannounce:Catch("OnItemChecked", function(this, e, b, v, checked)
    change_cfg(self, v, checked)
  end)
  ypos = ypos - 30

  arg = {
    x = 4, y = ypos, name = "KSKDefListDropdown", mode = "SINGLE", border = "THIN",
    dwidth = 200, items = KUI.emptydropdown, itemheight = 16,
    label = { text = L["Use Default Roll List"], pos = "LEFT" },
    tooltip = { title = "$$", text = L["TIP010"] },
  }
  cf.deflist = KUI:CreateDropDown(arg, cf)
  cf.deflist:Catch("OnValueChanged", function(this, evt, nv)
    change_cfg(self, "def_list", nv)
  end)
  qf.deflistdd = cf.deflist
  ypos = ypos - 28

  arg = {
    x = 4, y = ypos, name = "KSKGDefRankDropdown", mode = "SINGLE", border = "THIN",
    dwidth = 175, items = KUI.emptydropdown, itemheight = 16,
    label = { text = L["Initial Guild Rank Filter"], pos = "LEFT" },
    tooltip = { title = "$$", text = L["TIP011"] },
  }
  cf.gdefrank = KUI:CreateDropDown(arg, cf)
  -- Must remain visible in self.qf so it can be updated from main.
  self.qf.gdefrankdd = cf.gdefrank
  cf.gdefrank:Catch("OnValueChanged", function (this, evt, nv)
    change_cfg(self, "def_rank", nv)
  end)
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, label = {text = L["Hide Absent Members in Loot Lists"] },
    tooltip = { title = "$$", text = L["TIP012"] },
  }
  cf.hideabsent = KUI:CreateCheckBox(arg, cf)
  cf.hideabsent:Catch("OnValueChanged", function(this, evt, val)
    change_cfg(self, "hide_absent", val)
    self:RefreshLootMembers()
  end)
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, label = { text = L["Auto-assign Loot When Bids Close"] },
  }
  cf.autoloot = KUI:CreateCheckBox(arg, cf)
  cf.autoloot:Catch("OnValueChanged", function(this, evt, val)
    change_cfg(self, "auto_loot", val)
  end)
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, name = "KSKBidThresholdDropDown",
    label = { text = L["Bid / Roll Threshold"], pos = "LEFT" },
    itemheight = 16, mode = "SINGLE", dwidth = 135, items = {
      { text = L["None"], value = 0 },
      { text = ITEM_QUALITY2_DESC, value = 2, color = ITEM_QUALITY_COLORS[2] },
      { text = ITEM_QUALITY3_DESC, value = 3, color = ITEM_QUALITY_COLORS[3] },
      { text = ITEM_QUALITY4_DESC, value = 4, color = ITEM_QUALITY_COLORS[4] },
    },
    border = "THIN", tooltip = { title = "$$", text = L["TIP095"] },
  }
  cf.threshold = KUI:CreateDropDown(arg, cf)
  cf.threshold:Catch("OnValueChanged", function(this, evt, newv)
    change_cfg(self, "bid_threshold", newv)
    cf.denchbelow:SetEnabled(newv ~= 0)
  end)
  ypos = ypos - 30

  arg = {
    x = 0, y = ypos,
    label = { text = L["Auto-disenchant Items Below Threshold"] },
    tooltip = { title = "$$", text = L["TIP096"] },
  }
  cf.denchbelow = KUI:CreateCheckBox(arg, cf)
  cf.denchbelow:Catch("OnValueChanged", function(this, evt, val)
    change_cfg(self, "disenchant_below", val)
  end)
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, label = { text = L["Use Guild Rank Priorities"] },
    tooltip = { title = "$$", text = L["TIP013"] },
  }
  cf.rankprio = KUI:CreateCheckBox(arg, cf)
  cf.rankprio:Catch("OnValueChanged", function (this, evt, val)
    if (self.cfg.cfgtype == CFGTYPE_PUG) then
      val = false
    end
    change_cfg(self, "use_ranks", val)
    cf.rankedit:SetEnabled(val)
  end)

  arg = {
    x = 180, y = ypos+2, width = 50, height = 24, text = L["Edit"],
    enabled = false,
    tooltip = { title = "$$", text = L["TIP014"] },
  }
  cf.rankedit = KUI:CreateButton(arg, cf)
  cf.rankedit:ClearAllPoints()
  cf.rankedit:SetPoint("TOPLEFT", cf.rankprio, "TOPRIGHT", 16, 0)
  cf.rankedit:Catch("OnClick", function (this, evt)
    self.mainwin:Hide()
    K.UpdatePlayerAndGuild()
    rank_editor(self)
  end)
  ypos = ypos - 30

  arg = {
    x = 4, y = ypos, width = 300, font="GameFontNormal",
    text = L["When there are no successful bids ..."],
  }
  cf.nobidlbl = KUI:CreateStringLabel(arg, cf)
  ypos = ypos - 16

  arg = {
    x = 0, y = ypos, label = { text = L["Assign BoE Items to Master Looter"] },
    tooltip = { title = "$$", text = L["TIP015"] },
  }
  cf.boetoml = KUI:CreateCheckBox(arg, cf)
  cf.boetoml:Catch("OnValueChanged", function(this, evt, val)
    change_cfg(self, "boe_to_ml", val)
  end)

  arg = {
    x = 275, y = ypos, label = { text = L["Try Open Roll"] },
    tooltip = { title = "$$", text = L["TIP016"] },
  }
  cf.tryroll = KUI:CreateCheckBox(arg, cf)
  cf.tryroll:Catch("OnValueChanged", function(this, evt, val)
    change_cfg(self, "try_roll", val)
  end)
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, label = { text = L["Assign To Enchanter"] },
    tooltip = { title = "$$", text = L["TIP017"] },
  }
  cf.dench = KUI:CreateCheckBox(arg, cf)
  cf.dench:Catch("OnValueChanged", function(this, evt, val)
    change_cfg(self, "disenchant", val)
    for i = 1, self.MAX_DENCHERS do
      cf["dencher" .. i]:SetEnabled(val)
      if (not val) then
        cf["dencher" .. i]:SetText("")
        self.cfg.settings.denchers[i] = nil
      end
    end
  end)
  ypos = ypos - 24

  local function dencher_ovc(this, uid, which)
    if (uid == 0) then
      self.cfg.settings.denchers[which] = nil
      this:SetText("")
    else
      self.cfg.settings.denchers[which] = uid
      this:SetText(aclass(self.cfg.users[uid]))
    end
  end

  local function dencher_onclick(this, is_dropped, dnum)
    if (not is_dropped) then
      return
    end

    local elist = {}
    local cval = self.cfg.settings.denchers[dnum]

    tinsert(elist, { value = 0, text = L["None"] })
    if (cval) then
      tinsert(elist, { value = cval, text = aclass(self.cfg.users[cval]), checked = true, enabled = false } )
    end

    for k,v in ipairs(self.sortedusers) do
      local ok = true
      for i = 1, self.MAX_DENCHERS do
        if (self.cfg.settings.denchers[i] == v.id) then
          ok = false
        end
      end
      if (ok and self:UserIsEnchanter(v.id)) then
        local ti = { value = v.id, text = aclass(self.cfg.users[v.id]), checked = false }
        tinsert(elist, ti)
      end
    end
    this:UpdateItems(elist)
    this:SetValue(self.cfg.settings.denchers[dnum] or 0)
    dencher_ovc(this, self.cfg.settings.denchers[dnum] or 0, dnum)
  end

  arg = {
    x = 20, y = ypos, name = "KSKDencher1DD", itemheight = 16, dwidth = 140, mode = "SINGLE",
    border = "THIN", items = KUI.emptydropdown, title = { text = "" },
  }
  cf.dencher1 = KUI:CreateDropDown(arg, cf)
  cf.dencher1:Catch("OnClick", function(this, evt, is_dropped)
    dencher_onclick(this, is_dropped, 1)
  end)
  cf.dencher1:Catch("OnValueChanged", function(this, evt, newv)
    dencher_ovc(this, newv or 0, 1)
  end)

  arg.x = 172
  arg.name = "KSKDencher2DD"
  cf.dencher2 = KUI:CreateDropDown(arg, cf)
  cf.dencher2:Catch("OnClick", function(this, evt, dd,  is_dropped)
    dencher_onclick(this, is_dropped, 2)
  end)
  cf.dencher2:Catch("OnValueChanged", function(this, evt, newv)
    dencher_ovc(this, newv or 0, 2)
  end)

  arg.x = 325
  arg.name = "KSKDencher3DD"
  cf.dencher3 = KUI:CreateDropDown(arg, cf)
  cf.dencher3:Catch("OnClick", function(this, evt, dd,  is_dropped)
    dencher_onclick(this, is_dropped, 3)
  end)
  cf.dencher3:Catch("OnValueChanged", function(this, evt, newv)
    dencher_ovc(this, newv or 0, 3)
  end)

  --
  -- Config panel, roll options tab
  --
  local cf = qf.rollopts
  ypos = 0

  arg = {
    label = { text = L["Open Roll Timeout"] },
    x = 0, y = ypos, minval = 10, maxval = 60,
    tooltip = { title = "$$", text = L["TIP008"] },
  }
  cf.rolltimeout = KUI:CreateSlider(arg, cf)
  cf.rolltimeout:Catch("OnValueChanged", function(this, evt, newv)
    change_cfg(self, "roll_timeout", newv)
  end)

  arg = {
    label = { text = L["Roll Timeout Extension"] },
    x = 225, y = ypos, minval = 5, maxval = 30,
    tooltip = { title = "$$", text = L["TIP009"] },
  }
  cf.rollextend = KUI:CreateSlider(arg, cf)
  cf.rollextend:Catch("OnValueChanged", function(this, evt, newv)
    change_cfg(self, "roll_extend", newv)
  end)
  ypos = ypos - 48

  arg = {
    x = 0, y = ypos, label = {text = L["Enable Off-spec (101-200) Rolls"] },
    tooltip = { title = "$$", text = L["TIP092"] },
  }
  cf.enableoffspec = KUI:CreateCheckBox(arg, cf)
  cf.enableoffspec:Catch("OnValueChanged", function(this, evt, val)
    change_cfg(self, "offspec_rolls", val)
  end)
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, label = {text = L["Enable Suicide Rolls by Default"] },
    tooltip = { title = "$$", text = L["TIP093"] },
  }
  cf.suicideroll = KUI:CreateCheckBox(arg, cf)
  cf.suicideroll:Catch("OnValueChanged", function(this, evt, val)
    change_cfg(self, "suicide_rolls", val)
  end)
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, label = {text = L["Usage Message When Rolls Open"] },
    tooltip = { title = "$$", text = L["TIP007.6"] },
  }
  cf.rollusage = KUI:CreateCheckBox(arg, cf)
  cf.rollusage:Catch("OnValueChanged", function(this, evt, val)
    change_cfg(self, "ann_roll_usage", val)
  end)
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, label = {text = L["Announce Open Roll Countdown"] },
    tooltip = { title = "$$", text = L["TIP007.7"] },
  }
  cf.countdown = KUI:CreateCheckBox(arg, cf)
  cf.countdown:Catch("OnValueChanged", function(this, evt, val)
    change_cfg(self, "ann_countdown", val)
  end)
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, label = {text = L["Announce Open Roll Ties"] },
    tooltip = { title = "$$", text = L["TIP007.8"] },
  }
  cf.ties = KUI:CreateCheckBox(arg, cf)
  cf.ties:Catch("OnValueChanged", function(this, evt, val)
    change_cfg(self, "ann_roll_ties", val)
  end)

  --
  -- Config panel, admin tab
  --
  local cf = qf.cfgadmin
  local ls = cf.vsplit.leftframe
  local rs = cf.vsplit.rightframe

  arg = {
    height = 50,
    rightsplit = true,
    name = "KSKCfgAdminLSHSplit",
  }
  ls.hsplit = KUI:CreateHSplit(arg, ls)
  local tl = ls.hsplit.topframe
  local bl = ls.hsplit.bottomframe

  arg = {
    height = 135,
    name = "KSKCfgAdminRSHSplit",
    leftsplit = true,
    topanchor = true,
  }
  rs.hsplit = KUI:CreateHSplit(arg, rs)
  local tr = rs.hsplit.topframe
  local br = rs.hsplit.bottomframe

  -- Dont set qf.cfgopts to tr just yet. Wait until all of the other child
  -- elements have been added to it.

  arg = {
    height = 35,
    name = "KSKCfgAdminRSHSplit2",
    leftsplit = true,
  }
  br.hsplit = KUI:CreateHSplit(arg, br)
  local about = br.hsplit.bottomframe
  local coadmins = br.hsplit.topframe

  arg = {
    x = 0, y = 0, width = 80, height = 24, text = L["Create"],
    tooltip = { title = "$$", text = L["TIP019"] },
  }
  bl.createbutton = KUI:CreateButton(arg, bl)
  bl.createbutton:Catch("OnClick", function(this, evt)
    new_space_button(self)
  end)

  arg = {
    x = 95, y = 0, width = 80, height = 24, text = L["Delete"],
    tooltip = { title = "$$", text = L["TIP020"] },
  }
  bl.deletebutton = KUI:CreateButton(arg, bl)
  bl.deletebutton:Catch("OnClick", function(this, evt)
    self:DeleteConfig(admincfg, true)
  end)
  qf.cfgdelbutton = bl.deletebutton

  arg = {
    x = 0, y = -25, width = 80, height = 24, text = L["Rename"],
    tooltip = { title = "$$", text = L["TIP021"] },
  }
  bl.renamebutton = KUI:CreateButton(arg, bl)
  bl.renamebutton:Catch("OnClick", function(this, evt)
    rename_space_button(self, admincfg)
  end)
  qf.cfgrenbutton = bl.renamebutton

  arg = {
    x = 95, y = -25, width = 80, height = 24, text = L["Copy"],
    tooltip = { title = "$$", text = L["TIP022"] },
  }
  bl.copybutton = KUI:CreateButton(arg, bl)
  bl.copybutton:Catch("OnClick", function(this, evt)
    copy_space_button(self, admincfg, nil, nil, true)
  end)
  qf.cfgcopybutton = bl.copybutton

  --
  -- We make the config space panel a scrolling list in case they have lots
  -- of configs (unlikely but hey, you never know).
  --
  arg = {
    name = "KSKConfigScrollList",
    itemheight = 16,
    newitem = function(objp, num)
      return KUI.NewItemHelper(objp, num, "KSKConfigButton", 160, 16,
        nil, nil, nil, nil)
      end,
    setitem = function(objp, idx, slot, btn)
      return KUI.SetItemHelper(objp, btn, idx,
        function(op, ix)
          return self.frdb.configs[sortedconfigs[ix].id].name
        end)
      end,
    selectitem = config_selectitem,
    highlightitem = function(objp, idx, slot, btn, onoff)
      return KUI.HighlightItemHelper(objp, idx, slot, btn, onoff)
    end,
  }
  tl.slist = KUI:CreateScrollList(arg, tl)
  qf.cfglist = tl.slist

  local bdrop = {
    bgFile = KUI.TEXTURE_PATH .. "TDF-Fill",
    tile = true,
    tileSize = 32,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
  }
  tl.slist:SetBackdrop(bdrop)

  --
  -- These are the actual configurable options for a config space. They
  -- are shown in the top right panel. Below them is some version information
  -- and contact information.
  --
  ypos = 0
  arg = {
    x = 4, y = ypos, name = "KSKConfigOwnerDD", itemheight = 16,
    dwidth = 150, mode = "SINGLE", items = KUI.emptydropdown, border = "THIN",
    label = { pos = "LEFT", text = L["Config Owner"] },
    tooltip = { title = "$$", text = L["TIP023"] },
  }
  tr.cfgowner = KUI:CreateDropDown(arg, tr)
  qf.cfgownerdd = tr.cfgowner
  tr.cfgowner:Catch("OnValueChanged", function(this, evt, newv)
    local lcf = self.frdb.configs[admincfg]
    lcf.owner = newv
    self:FullRefresh(true)
  end)
  ypos = ypos - 32

  arg = {
    name = "KSKCfgTypeDropDown", enabled = false, itemheight = 16,
    x = 4, y = ypos, label = { text = L["Config Type"], pos = "LEFT" },
    dwidth = 100, mode = "SINGLE", width = 75, border = "THIN",
    tooltip = { title = "$$", text = L["TIP025"] },
    items = {
      { text = L["Guild"], value = CFGTYPE_GUILD },
      { text = L["PUG"], value = CFGTYPE_PUG },
    },
  }
  tr.cfgtype = KUI:CreateDropDown(arg, tr)
  tr.cfgtype:Catch ("OnValueChanged", function(this, evt, newv)
    local lcf = self.frdb.configs[admincfg]
    local en
    lcf.cfgtype = newv
    if (newv == CFGTYPE_GUILD and K.player.is_guilded and K.player.is_gm) then
      qf.cfgopts.orankedit:SetEnabled(true)
    else
      qf.cfgopts.orankedit:SetEnabled(false)
    end
    if (newv == CFGTYPE_PUG) then
      lcf.settings.def_rank = 0
      lcf.settings.use_ranks = false
      lcf.settings.ann_winners_guild = false
      lcf.settings.rank_prio = {}
      for k, v in pairs (lcf.lists) do
        v.def_rank = 0
      end
      self:RefreshConfigLootUI(false)
    end
  end)
  self.qf.cfgtype = tr.cfgtype
  ypos = ypos - 32

  arg = {
    name = "KSKCfgGuildOfficerButton",
    x = 4, y = ypos, width = 160, height = 24,
    text = L["Edit Officer Ranks"], enabled = false,
    tooltip = { title = "$$", text = L["TIP100"] }
  }
  tr.orankedit = KUI:CreateButton(arg, tr)
  tr.orankedit:Catch ("OnClick", function(this, evt)
    local ct = self.frdb.configs[admincfg].cfgtype
    if (ct == CFGTYPE_GUILD and K.player.is_guilded and K.player.is_gm) then
      self.mainwin:Hide()
      K:UpdatePlayerAndGuild()
      orank_edit_button(self)
    end
  end)

  -- NOW we can set qf.cfgopts
  qf.cfgopts = tr

  arg = {
    x = 0, y = 2, height = 12, font = "GameFontNormalSmall",
    autosize = false, width = 290, text = L["ABOUT1"],
  }
  about.str1 = KUI:CreateStringLabel(arg, about)

  arg = {
    x = 0, y = -10, height = 12, font = "GameFontNormalSmall",
    autosize = false, width = 290,
    text = strfmt(L["ABOUT2"], white("me@cruciformer.com"))
  }
  about.str2 = KUI:CreateStringLabel(arg, about)

  arg = {
    x = 0, y = -22, height = 12, font = "GameFontNormalSmall",
    autosize = false, width = 290,
    text = strfmt(L["ABOUT3"], white("http://kahluamod.com/ksk"))
  }
  about.str2 = KUI:CreateStringLabel(arg, about)

  arg = {
    x = "CENTER", y = 0, font = "GameFontNormal", text = L["Co-admins"],
    border = true, width = 125, justifyh = "CENTER",
  }
  coadmins.str1 = KUI:CreateStringLabel(arg, coadmins)

  --
  -- There is a finite list of co-admins. We create a scrolling list in case
  -- some idiots add lots of them. Scrolling lists take up a whole frame so
  -- we need to create the frame and add the buttons for adding and removing
  -- co-admins to the right of the frame.
  --
  arg = {
    x = 200, y = -24, text = L["Add"], width = 90, height = 24,
    tooltip = { title = "$$", text = L["TIP026"] },
  }
  coadmins.add = KUI:CreateButton(arg, coadmins)
  coadmins.add:Catch("OnClick", function(this, evt, ...)
    local ulist = {}
    local cc = self.frdb.configs[admincfg]
    local cul = cc.users

    if (cc.nadmins == 36) then
      err(L["maximum number of co-admins (36) reached"])
      return
    end

    if (self.popupwindow) then
      self.popupwindow:Hide()
      self.popupwindow = nil
    end

    for k,v in pairs(cul) do
      if (not self:UserIsCoadmin(k, admincfg) and
          not self:UserIsAlt(k, nil, admincfg)) then
        tinsert(ulist, { value = k, text = aclass(cul[k]) })
      end
    end
    tsort(ulist, function(a, b)
      return cul[a.value].name < cul[b.value].name
    end)
    if (#ulist == 0) then
      return
    end

    local function pop_func(cauid)
      add_coadmin(self, cauid, admincfg)
      self.popupwindow:Hide()
      self.popupwindow = nil
      self:RefreshConfigAdminUI(false)
    end

    if (not coadmin_popup) then
      coadmin_popup = K.PopupSelectionList(self, "KSKCoadminAddPopup",
        ulist, L["Select Co-admin"], 200, 400, this, 16, pop_func)
    else
      coadmin_popup:UpdateList(ulist)
    end
    coadmin_popup:ClearAllPoints()
    coadmin_popup:SetPoint("TOPLEFT", this, "TOPRIGHT", 0, coadmin_popup:GetHeight() / 2)
    self.popupwindow = coadmin_popup
    coadmin_popup:Show()
  end)
  qf.coadadd = coadmins.add

  arg = {
    x = 200, y = -48, text = L["Delete"], width = 90, height = 24,
    tooltip = { title = "$$", text = L["TIP027"] },
    enabled = false,
  }
  coadmins.del = KUI:CreateButton(arg, coadmins)
  coadmins.del:Catch("OnClick", function(this, evt, ...)
    if (not coadmin_selected or not admincfg) then
      return
    end
    self:DeleteAdmin(coadmin_selected, admincfg)
  end)
  qf.coaddel = coadmins.del

  local sframe = MakeFrame("Frame", nil, coadmins)
  coadmins.sframe = sframe
  sframe:ClearAllPoints()
  sframe:SetPoint("TOPLEFT", coadmins, "TOPLEFT", 0, -24)
  sframe:SetPoint("BOTTOMLEFT", coadmins, "BOTTOMLEFT", 0, 0)
  sframe:SetWidth(190)

  arg = {
    name = "KSKCoadminScrollList",
    itemheight = 16,
    newitem = function(objp, num)
      return KUI.NewItemHelper(objp, num, "KSKCoadminButton", 160, 16,
        nil, nil, nil, nil)
      end,
    setitem = function(objp, idx, slot, btn)
      return KUI.SetItemHelper(objp, btn, idx,
        function(op, ix)
          local ul = self.frdb.configs[admincfg].users
          return aclass(ul[sortedadmins[ix]])
        end)
      end,
    selectitem = coadmin_list_selectitem,
    highlightitem = function(objp, idx, slot, btn, onoff)
      return KUI.HighlightItemHelper(objp, idx, slot, btn, onoff)
    end,
  }
  coadmins.slist = KUI:CreateScrollList(arg, coadmins.sframe)
  qf.coadminscroll = coadmins.slist
end

local function real_delete_config(this, cfgid)
  if (not silent_delete) then
    info(L["configuration %q deleted."], white(this.frdb.configs[cfgid].name))
  end

  this.frdb.configs[cfgid] = nil
  this.csdata[cfgid] = nil
  this.frdb.nconfigs = this.frdb.nconfigs - 1
  if (this.frdb.defconfig == cfgid) then
    local nid = next(this.frdb.configs)
    this:SetDefaultConfig(nid, false, true)
    admincfg = nid
  end

  if (admincfg == cfgid) then
    admincfg = nil
  end
  this:FullRefresh(true)
end

function ksk:DeleteConfig(cfgid, show, private)
  if (self.frdb.nconfigs == 1 and not private) then
    err(L["cannot delete configuration %q - %s requires at least one configuration."],
        white(self.frdb.configs[cfgid].name), L["MODTITLE"])
    return true
  end

  if (private) then
    local oldsilent = silent_delete
    silent_delete = true
    real_delete_config(self, cfgid)
    silent_delete = oldsilent
    return
  end

  local isshown = show or self.mainwin:IsShown()
  self.mainwin:Hide()

  K.ConfirmationDialog(self, L["Delete Configuration"], L["DELMSG"],
    self.frdb.configs[cfgid].name, real_delete_config, cfgid, isshown)

  return false
end

function ksk:CreateNewConfig(name, initial, nouser, mykey)
  local lname = strlower(name)

  for k,v in pairs(self.frdb.configs) do
    if (strlower(v.name) == lname) then
      err(L["configuration %q already exists. Try again."], white(name))
      return true
    end
  end

  self.frdb.nconfigs = self.frdb.nconfigs + 1

  local newkey = mykey or KK.CreateNewID(name)
  self.frdb.configs[newkey] = {}
  self.csdata[newkey] = {}
  self.csdata[newkey].reserved = {}
  local sp = self.frdb.configs[newkey]
  sp.name = name
  sp.cfgtype = CFGTYPE_PUG
  sp.oranks = "1000000000"
  sp.settings = {}
  sp.history = {}
  sp.users = {}
  sp.nusers = 0
  sp.lists = {}
  sp.nlists = 0
  sp.items = {}
  sp.nitems = 0
  sp.admins = {}
  sp.nadmins = 0
  sp.cksum = 0xa49b37d3
  sp.lastevent = 0
  sp.syncing = false

  K.CopyTable(self.defaults, sp.settings)
  if (not nouser) then
    sp.nusers = 1
    sp.users["0001"] = { name = K.player.name, class = K.player.class, role = 0, flags = "" }
    sp.owner = "0001"
    self.csdata[newkey].myuid = uid
    info(L["configuration %q created."], white(name))
    sp.nadmins = 1
    sp.admins["0001"] = { id = "0" }
  end

  if (initial) then
    self:SetDefaultConfig(newkey, self.frdb.tempcfg, self.frdb.tempcfg)
    return false, newkey
  end

  if (self.frdb.tempcfg) then
    self:SetDefaultConfig(newkey, true, true)
    silent_delete = true
    real_delete_config(self, "1")
    silent_delete = nil
    self.frdb.tempcfg = nil
  end

  --
  -- If we have no guild configs, and we are the GM, make this
  -- a guild config initially. They can change it immediately if this is wrong.
  --
  if (K.player.is_gm) then
    local ng = 0
    for k,v in pairs(self.frdb.configs) do
      if (v.cfgtype == CFGTYPE_GUILD) then
        ng = ng + 1
      end
    end
    if (ng == 0) then
      sp.cfgtype = CFGTYPE_GUILD
    end
  end

  self:FullRefresh(true)
  return false, newkey
end

function ksk:RenameConfig(cfgid, newname)
  if (self:CheckPerm(cfgid)) then
    return true
  end

  if (not self.frdb.configs[cfgid]) then
    return true
  end

  local found = false
  local lname = strlower(newname)

  for k,v in pairs(self.frdb.configs) do
    if (strlower(self.frdb.configs[k].name) == lname) then
      found = true
    end
  end

  if (found) then
    err(L["configuration %q already exists. Try again."], white(newname))
    return true
  end

  local oldname = self.frdb.configs[cfgid].name
  info(L["NOTICE: configuration %q renamed to %q."], white(oldname), white(newname))
  self.frdb.configs[cfgid].name = newname
  self:FullRefresh()

  return false
end

function ksk:FindConfig(name)
  local lname = strlower(name)
  for k,v in pairs(self.frdb.configs) do
    if (strlower(v.name) == lname) then
      return k
    end
  end
  return nil
end

function ksk:DeleteAdmin(uid, cfg, nocmd)
  local cfg = cfg or admincfg
  local cp = self.frdb.configs[cfg]

  if (not cp) then
    return
  end

  if (not cp.admins[uid]) then
    return
  end

  -- Must send the event BEFORE removing the admin.
  if (not nocmd) then
    self:AdminEvent(cfg, "RMADM", uid)
  end

  cp.nadmins = cp.nadmins - 1
  cp.admins[uid] = nil
  if (cp.nadmins == 1) then
    cp.syncing = false
    cp.lastevent = 0
    cp.admins[cp.owner].lastevent = nil
    cp.admins[cp.owner].sync = nil
    qf.cfgopts.cfgowner:SetEnabled(false)
  end

  refresh_coadmins(self)
  self:RefreshSyncUI(true)
end

--
-- Function: ksk:SetDefaultConfig(cfgid, silent, force)
-- Purpose : Set up all of the various global aliases and make the specified
--           config the default one. If the current config is already the
--           specified config, do nothing unless FORCE is set to true. If
--           the work should be silent, set SILENT to true, otherwise a
--           message indicating the default change is displayed.
-- Returns : Nothing
--
function ksk:SetDefaultConfig(cfgid, silent, force)
  if (not cfgid or not self.configs or not self.configs[cfgid]) then
    return
  end

  if (not self.csdata or not self.csdata[cfgid]) then
    return
  end

  if (self.frdb.defconfig ~= cfgid or force) then
    self.frdb.defconfig = cfgid
    self.currentid = cfgid

    self:MakeAliases()

    if (self.initialised) then
      -- If we're not initialised yet then this will just have been called.
      self:RefreshCSData()
    end

    if (self.initialised) then
      self.qf.synctopbar:SetCurrentCRC()
    end

    self.sortedlists = nil
    self.missing = {}
    self.nmissing = 0

    self.csdata[self.currentid].warns = {}
    self.csdata[self.currentid].warns.lists = {}

    self:UpdateUserSecurity(cfgid)

    if (self.initialised) then
      self:FullRefresh(true)
      self.mainwin:SetTab(self.LOOT_TAB, self.LOOT_ASSIGN_PAGE)
      self.mainwin:SetTab(self.LISTS_TAB, self.LISTS_MEMBERS_PAGE)

      if (not self.frdb.tempcfg) then
        local sidx = nil
        for k,v in pairs(sortedconfigs) do
          if (v.id == cfgid) then
            sidx = k
            break
          end
        end
        qf.cfglist:SetSelected(sidx, true, true)
      end

      if (not silent) then
        info(L["NOTICE: default configuration changed to %q."],
          white(self.frdb.configs[cfgid].name))
        if (not self.csdata[self.currentid].is_admin) then
          info(L["you are not an administrator of this configuration. Your access to it is read-only."])
        end
      end
    end
  end
end

function ksk:RefreshConfigLists(llist)
  qf.deflistdd:UpdateItems(llist)
  qf.deflistdd:SetValue(self.cfg.settings.def_list or "0")
end

function ksk:RefreshConfigUsers()
end

function ksk:RefreshConfigLootUI(reset)
  local i
  local settings = self.cfg.settings
  local cf = qf.lootopts
  local en = true

  cf.autobid:SetChecked(settings.auto_bid)
  cf.silentbid:SetChecked(settings.silent_bid)
  cf.tooltips:SetChecked(settings.tooltips)
  cf.chatfilter:SetChecked(settings.chat_filter)
  cf.history:SetChecked(settings.history)
  cf.announcewhere:SetValue(settings.announce_where)
  cf.deflist:SetValue(settings.def_list)
  cf.gdefrank:SetValue(settings.def_rank)
  cf.hideabsent:SetChecked(settings.hide_absent)
  cf.autoloot:SetChecked(settings.auto_loot)
  cf.threshold:SetValue(settings.bid_threshold)
  cf.denchbelow:SetChecked(settings.disenchant_below)
  cf.rankprio:SetChecked(settings.use_ranks)
  cf.boetoml:SetChecked(settings.boe_to_ml)
  cf.tryroll:SetChecked(settings.try_roll)
  cf.dench:SetChecked(settings.disenchant)
  cf.otherannounce:UpdateItems(cf.otherannounce.items)

  if (self.cfg.cfgtype == CFGTYPE_PUG) then
    en = false
  end
  cf.gdefrank:SetEnabled(en)
  cf.rankprio:SetEnabled(en)
  self.qf.lootrank:SetEnabled(en)
  self.qf.defrankdd:SetEnabled(en)
  self.qf.gdefrankdd:SetEnabled(en)
  self.qf.itemrankdd:SetEnabled(en)

  for i = 1, self.MAX_DENCHERS do
    if (settings.denchers[i]) then
      cf["dencher"..i]:SetText(aclass(self.cfg.users[settings.denchers[i]]))
    else
      cf["dencher"..i]:SetText("")
    end
  end
end

function ksk:RefreshConfigRollUI(reset)
  local i
  local settings = self.cfg.settings
  local cf = qf.rollopts

  cf.rolltimeout:SetValue(settings.roll_timeout)
  cf.rollextend:SetValue(settings.roll_extend)
  cf.enableoffspec:SetChecked(settings.offspec_rolls)
  cf.suicideroll:SetChecked(settings.suicide_rolls)
  cf.rollusage:SetChecked(settings.ann_roll_usage)
  cf.countdown:SetChecked(settings.ann_countdown)
  cf.ties:SetChecked(settings.ann_roll_ties)
end

function ksk:RefreshConfigAdminUI(reset)
  if (self.frdb.tempcfg) then
    qf.cfglist.itemcount = 0
    qf.cfglist:UpdateList()
    return
  end

  local vt = {}
  local newconfs = {}
  local oldid = admincfg or self.currentid
  local oldidx = nil

  admincfg = nil

  for k,v in pairs(self.frdb.configs) do
    local ent = {id = k }
    tinsert(newconfs, ent)
  end
  tsort(newconfs, function(a, b)
    return strlower(self.configs[a.id].name) < strlower(self.configs[b.id].name)
  end)

  for k,v in ipairs(newconfs) do
    vt[k] = { text = self.frdb.configs[v.id].name, value = v.id }
    if (self.csdata[v.id].is_admin == 2) then
      vt[k].color = {r = 0, g = 1, b = 0 }
    elseif (self.csdata[v.id].is_admin == 1) then
      vt[k].color = {r = 0, g = 1, b = 1 }
    else
      vt[k].color = {r = 1, g = 1, b = 1 }
    end
    if (v.id == oldid) then
      oldidx = k
    end
  end

  sortedconfigs = newconfs

  self.mainwin.cfgselector:UpdateItems(vt)
  -- Don't fire an OnValueChanged event when we set this.
  self.mainwin.cfgselector:SetValue(self.currentid, true)

  qf.cfglist.itemcount = #newconfs
  qf.cfglist:UpdateList()

  --
  -- There is some magic happening here. By forcing the selection (3rd arg
  -- true) we force the widget's selectitem function to run. This results
  -- in config_selectitem() being called. This has a few side effects. The
  -- first and foremost is, it sets the "admincfg" local variable to the
  -- selected configuration (if any). Secondly, it forces a refresh of the
  -- data on the right hand panel that is related to the selected config.
  -- This includes updating the list of coadmins. That leaves us with a choice
  -- on how we want to deal with the co-admin list when we have sync events
  -- or other things changing the coadmin list. We can either have a special
  -- refresh and reset function just for co-admins, or we can leave it up
  -- to this code to result in the refresh. It provides better data protection
  -- and encapsulate usage if we go with the latter, so we no longer have a
  -- special co-admin update function. Instead, if anything changes the list
  -- of co-admins it should call this function (RefreshConfigAdminUI).
  --
  qf.cfglist:SetSelected(oldidx, true, true)
  self:RefreshSyncUI(true)
end

--
-- Refresh the config tab UI elements, optionally resetting all state
-- variables. This will only ever really impact admins as they are the only
-- ones that can see the tab. However, we do this for everybody to simplify
-- the overall logic of the mod. For non-admins this will just be a little
-- bit of busy work that will happen so quickly they won't even notice it.
--
function ksk:RefreshConfigUI(reset)
  if (not self.currentid) then
    return
  end

  self.mainwin.cfgselector:SetValue(self.currentid)

  self:RefreshConfigLootUI(reset)
  self:RefreshConfigRollUI(reset)
  self:RefreshConfigAdminUI(reset)
end
