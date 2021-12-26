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
local MakeFrame = KUI.MakeFrame

-- Local aliases for global or Lua library functions
local _G = _G
local tinsert = table.insert
local tremove = table.remove
local tsort = table.sort
local tostring = tostring
local strfmt = string.format
local strfind = string.find
local strlower = string.lower
local pairs, ipairs, next = pairs, ipairs, next
local assert = assert

local info = ksk.info
local err = ksk.err
local white = ksk.white
local green = ksk.green
local red = ksk.red
local class = ksk.class
local aclass = ksk.aclass
local shortaclass = ksk.shortaclass
local debug = ksk.debug

local createuserdlg = nil
local selected_user = nil
local umemlist = nil
local uinfo = {}
local qf = {}

local HIST_WHEN = ksk.HIST_WHEN
local HIST_WHAT = ksk.HIST_WHAT
local HIST_WHO = ksk.HIST_WHO
local HIST_HOW = ksk.HIST_HOW

--
-- This file contains all of the UI handling code for the users panel,
-- as well as all user manipulation functions.
--
local function changed(res)
  local res = res or false
  if (not selected_user) then
    res = true
  end
  qf.userupdbtn:SetEnabled(not res)
end

local function hide_popup()
  if (ksk.popupwindow) then
    ksk.popupwindow:Hide()
    ksk.popupwindow = nil
  end
end

local function setup_uinfo(self)
  if (not selected_user) then
    return
  end

  uinfo = {}
  uinfo.role = self:UserRole(selected_user) or 0
  uinfo.enchanter = self:UserIsEnchanter(selected_user) or false
  local isalt, altidx, _, _, altname = self:UserIsAlt(selected_user)
  uinfo.isalt = isalt or false
  uinfo.main = altname or ""
  uinfo.mainid = altidx
  uinfo.frozen = self:UserIsFrozen(selected_user) or false
  if (self.cfg.users[selected_user].alts) then
    uinfo.ismain = true
  else
    uinfo.ismain = false
  end
end

-- Refresh the list of lists that the currently selected user is on. This updates
-- umemlist. This changes every time a new user is selected from the user list.
local function refresh_user_membership(self)
  if (selected_user) then
    local uid = selected_user
    umemlist = {}
    if (self.sortedlists and #self.sortedlists > 0) then
      for k,v in ipairs(self.sortedlists) do
        local list = self.cfg.lists[v.id]
        local inlist, luid, pos = self:UserOrAltInList(uid, v.id)
        if (inlist) then
          local ts = green(list.name)

          if (luid ~= uid) then
            ts = ts .. " (" .. shortaclass(self.cfg.users[luid]) .. ")"
          end

          tinsert(umemlist, strfmt("%s [%d]", ts, pos))
        else
          tinsert(umemlist, red(list.name))
        end
      end
    end
    qf.umemlist.itemcount = #umemlist
  else
    umemlist = nil
    qf.umemlist.itemcount = 0
  end
  qf.umemlist:UpdateList()
end

local function enable_selected(en)
  qf.usertopbar.seluser:SetShown(en)
  qf.useropts.userrole:SetEnabled(en)
  qf.useropts.enchanter:SetEnabled(en)
  qf.useropts.isalt:SetEnabled(en)
  qf.useropts.mainname:SetEnabled(en)
  qf.useropts.frozen:SetEnabled(en)
  qf.useropts.isalt:SetEnabled(en)
  qf.useropts.mainsel:SetEnabled(en)
  qf.userbuttons.deletebutton:SetEnabled(en)
  qf.userbuttons.renamebutton:SetEnabled(en)
end

local function users_selectitem(objp, idx, slot, btn, onoff)
  local onoff = onoff or false

  hide_popup()
  enable_selected(onoff)

  if (onoff) then
    selected_user = ksk.sortedusers[idx].id
    setup_uinfo(ksk)

    if (ksk.cfg.owner == selected_user) then
      qf.userbuttons.deletebutton:SetEnabled(false)
    end

    qf.usertopbar.SetCurrentUser(selected_user)
    qf.useropts.userrole:SetValue(uinfo.role)
    qf.useropts.enchanter:SetChecked(uinfo.enchanter)
    qf.useropts.isalt:SetChecked(uinfo.isalt)
    qf.useropts.mainname:SetText(uinfo.main)
    qf.useropts.frozen:SetChecked(uinfo.frozen)
    qf.useropts.isalt:SetEnabled(not uinfo.ismain)
    qf.useropts.mainsel:SetEnabled(uinfo.isalt)
  else
    selected_user = nil
  end

  refresh_user_membership(ksk)
  changed(true)
end

function ksk:CreateRoleListDropdown(name, x, y, parent, w)
  local kk = ksk.KK
  local arg = {
    name = name, mode = "SINGLE", itemheight = 16, x = x, y = y, dwidth = w or 150,
    label =  { text = L["User Role"], pos = "LEFT" }, border = "THIN",
    items = {
      { text = kk.rolenames[kk.ROLE_UNSET], value = kk.ROLE_UNSET },
      { text = kk.rolenames[kk.ROLE_HEALER], value = kk.ROLE_HEALER },
      { text = kk.rolenames[kk.ROLE_MELEE], value = kk.ROLE_MELEE },
      { text = kk.rolenames[kk.ROLE_RANGED], value = kk.ROLE_RANGED },
      { text = kk.rolenames[kk.ROLE_CASTER], value = kk.ROLE_CASTER },
      { text = kk.rolenames[kk.ROLE_TANK], value = kk.ROLE_TANK },
    },
    tooltip = { title = "$$", text = L["TIP071"] },
  }
  return KUI:CreateDropDown(arg, parent)
end

local function create_user_button(self)
  if (not createuserdlg) then
    local arg = {
      x = "CENTER", y = "MIDDLE",
      name = "KSK CreateUserDlg",
      title = L["Create User"],
      border = true,
      width = 350,
      height = 175,
      canmove = true,
      canresize = false,
      escclose = true,
      blackbg = true,
      okbutton = { text = K.ACCEPTSTR },
      cancelbutton = { text = K.CANCELSTR },
    }

    local ret = KUI:CreateDialogFrame(arg)

    arg = {
      x = 5, y = 0, len = 48,
      label = { text = L["User Name"], pos = "LEFT" },
      tooltip = { title = "$$", text = L["TIP072"] },
    }
    ret.username = KUI:CreateEditBox(arg, ret)
    ret.username:SetFocus()

    arg = {
      x = 5, y = -30, dwidth = 125, mode = "SINGLE", itemheight = 16, label = { text = L["User Class"], pos = "LEFT" },
      items = {}, name = "KSKCreateUserClassDD", border = "THIN",
      tooltip = { title = "$$", text = L["TIP073"] },
    }
    for k,v in pairs(K.IndexClass) do
      if (v.c and not v.ign) then
        tinsert(arg.items, { text = v.c, value = k, color = K.ClassColorsRGBPerc[k] })
      end
    end
    ret.userclass = KUI:CreateDropDown(arg, ret)
    ret.userclass.cset = nil
    ret.userclass:Catch("OnValueChanged", function(this, evt, newv)
      this.cset = newv
    end)

    ret.userrole = self:CreateRoleListDropdown("CreateUserRoleDD", 5, -60, ret)
    ret.userrole.rset = 0
    ret.userrole:Catch("OnValueChanged", function(this, evt, newv)
      this.rset = newv
    end)

    ret.OnCancel = function(this)
      this:Hide()
      self.mainwin:Show()
    end

    ret.OnAccept = function(this)
      if (not this.username:GetText() or this.username:GetText() == "") then
        err(L["you must specify a character name."])
        this.username:SetFocus()
        return true
      end
      if (not this.userclass.cset) then
        err(L["you must set a user class."])
        return true
      end
      local uid = self:CreateNewUser(this.username:GetText(), this.userclass.cset)
      if (uid) then
        self:SetUserRole(uid, this.userrole.rset)
        this:Hide()
        self.mainwin:Show()
        return false
      end
    end

    createuserdlg = ret
  end

  self.mainwin:Hide()
  createuserdlg:Show()
  createuserdlg.userclass.cset = nil
  createuserdlg.userclass:SetValue(nil)
  createuserdlg.userrole:SetValue(self.KK.ROLE_UNSET)
  createuserdlg.username:SetText("")
  createuserdlg.username:SetFocus()
end

local function delete_user_button(self, uid)
  self:DeleteUserCmd(uid)
end

local function rename_user_button(self, uid)
  local function rename_helper(newname, old)
    local found = nil
    local cname = strlower(newname)

    for k,v in pairs(self.cfg.users) do
      if (strlower(v.name) == cname) then
        found = self.cfg.users[k]
        break
      end
    end

    if (found) then
      err(L["user %q already exists. Try again."], aclass(found))
      return true
    end

    local rv = self:RenameUser(old, cname)
    if (rv) then
      return true
    end

    return false
  end

  K.RenameDialog(self, L["Rename User"], L["Old Name"],
    self.cfg.users[uid].name, L["New Name"], 48, rename_helper,
    uid, true)
end

local function guild_import_button(self, shown)
  local arg = {
    x = "CENTER", y = "MIDDLE",
    name = "KSKGuildImportDlg",
    title = L["Import Guild Users"],
    border = true,
    width = 250,
    height = (K.guild.numranks * 28) + 92,
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
    y = 0, width = 170, height = 24
  }
  for i = 1, K.guild.numranks do
    y = y - 24
    local cbn = "rankcb" .. tostring(i)
    arg.y = y
    arg.x = 10
    arg.label = { text = K.guild.ranks[i] }
    ret[cbn] = KUI:CreateCheckBox(arg, ret)
  end

  y = y - 24

  arg = {
    x = 10, y = y, minval = 1, maxval = K.maxlevel, initialvalue = K.maxlevel,
    step = 1, label = { text = L["Minimum Level"], },
    tooltip = { title = "$$", text = L["TIP074"] },
  }
  ret.minlevel = KUI:CreateSlider(arg, ret)

  ret.isshown = shown
  
  ret.OnCancel = function(this)
    this:Hide()
    if (this.isshown) then
      self.mainwin:Show()
    end
  end

  local function do_rank(r, minlev)
    local rv = 0
    local ngm = K.guild.numroster
    for i = 1, ngm do
      if (K.guild.roster.id[i].rank == r and K.guild.roster.id[i].level >= minlev) then
        local nm = K.guild.roster.id[i].name
        local uid = self:FindUser(nm)
        if (not uid) then
          local kcl = K.guild.roster.id[i].class
          uid = self:CreateNewUser(nm, kcl, nil, true)
          if (uid) then
            rv = rv + 1
          else
            err("error adding user %q!", white(nm))
          end
        end
      end
    end
    return rv
  end

  ret.OnAccept = function(this)
    local cas,ccs
    local tadd = 0
    local minlev = this.minlevel:GetValue()

    for i = 1, K.guild.numranks do
      ccs = "rankcb" .. tostring(i)
      if (this[ccs]:GetChecked()) then
        tadd = tadd + do_rank(i, minlev)
      end
    end

    if (tadd > 0) then
      self:RefreshUsers()
      self:RefreshRaid()
      self:SendAM("RFUSR", "ALERT", true)
    end

    this:Hide()
    if (this.isshown) then
      self.mainwin:Show()
    end

    info(L["added %d user(s)."], tadd)
  end

  self.mainwin:Hide()
  ret:Show()
end

function ksk:ImportGuildUsers(shown)
  guild_import_button(self, shown)
end

local selmain_popup

local function select_main(self, btn)
  if (not selected_user) then
    return
  end

  hide_popup()

  local ulist = {}

  for k, v in ipairs(self.sortedusers) do
    if (not v.main) then
      tinsert(ulist, { value = v.id, text = aclass(self.cfg.users[v.id]) })
    end
  end

  local function pop_func(puid)
    local ulist = selmain_popup.selectionlist
    changed()
    qf.useraltnamebox:SetText(aclass(self.cfg.users[puid]))
    hide_popup()
    uinfo.isalt = true
    uinfo.main = self.cfg.users[puid].name
    uinfo.mainid = puid
  end

  if (not selmain_popup) then
    selmain_popup = K.PopupSelectionList(self, "KSKMainSelPopup", ulist,
      nil, 205, 400, self.mainwin.tabs[self.USERS_TAB].content, 16, pop_func,
      nil, 20)
    local arg = {
      x = 0, y = 2, len = 48, font = "ChatFontSmall", width = 170,
      tooltip = { title = L["User Search"], text = L["TIP099"] },
      parent = selmain_popup.footer,
    }
    selmain_popup.usearch = KUI:CreateEditBox(arg, selmain_popup.footer)
    selmain_popup.usearch.toplevel = selmain_popup
    qf.selmainsearch = selmain_popup.usearch
    local ulist = selmain_popup.selectionlist
    selmain_popup.usearch:Catch("OnEnterPressed", function(this)
      this:SetText("")
    end)
    selmain_popup.usearch:HookScript("OnEnter", function(this)
      this.toplevel:StopTimeoutCounter()
    end)
    selmain_popup.usearch:HookScript("OnLeave", function(this)
      this.toplevel:StartTimeoutCounter()
    end)
    selmain_popup.usearch:Catch("OnValueChanged", function(this, evt, newv, user)
      if (not self.cfg.users or not ulist or selmain_popup.slist.itemcount < 1) then
        return
      end
      if (user and newv and newv ~= "") then
        local lnv = strlower(newv)
        local tln
        for k,v in pairs(ulist) do
          tln = strlower(self.cfg.users[v.value].name)
          if (strfind(tln, lnv, 1, true)) then
            selmain_popup.slist:SetSelected(k, true)
            return
          end
        end
      end
    end)
  else
    selmain_popup:UpdateList(ulist)
  end
  selmain_popup:ClearAllPoints()
  selmain_popup:SetPoint("TOPLEFT", btn, "TOPRIGHT", 0, 0)
  selmain_popup:Show()
  self.popupwindow = selmain_popup
end

--
-- If we are in raid, add all of the current users who are missing to the
-- users database.
--
local function add_missing_button(self)
  if (not self.users or not self.csdata[self.currentid].is_admin or not self.nmissing or self.nmissing == 0) then
    return
  end

  local added = 0

  while (self.nmissing > 0 and added < 40) do
    local _, v = next(self.missing)
    self:CreateNewUser(v.name, v.class, nil, true, true)
    added = added + 1
  end
  self:RefreshUsers()
  self:RefreshRaid()
  self:SendAM("RFUSR", "ALERT", true)
end

function ksk:InitialiseUsersUI()
  local arg

  --
  -- Users tab. We have no sub-tabs so there is only one set of things
  -- to do here.
  --
  local ypos = 0

  local cf = self.mainwin.tabs[self.USERS_TAB].content
  local tbf = self.mainwin.tabs[self.USERS_TAB].topbar
  local ls = cf.vsplit.leftframe
  local rs = cf.vsplit.rightframe

  arg = {
    x = 0, y = -18, text = "", autosize = false, width = 250,
    font = "GameFontNormalSmall",
  }
  tbf.seluser = KUI:CreateStringLabel(arg, tbf)

  qf.usertopbar = tbf
  tbf.SetCurrentUser = function(userid)
    if (userid) then
      tbf.seluser:SetText(L["Currently Selected: "]..aclass(self.cfg.users[userid]))
    else
      tbf.seluser:SetText("")
    end
  end

  --
  -- Create the horizontal split for the buttons at the bottom
  --
  arg = {
    inset = 0, height = 75,
    leftsplit = true, name = "KSKUserAdminRHSplit",
  }
  rs.hsplit = KUI:CreateHSplit(arg, rs)
  local tr = rs.hsplit.topframe
  local br = rs.hsplit.bottomframe
  self.qf.userbuttons = br
  qf.userbuttons = br

  --
  -- The top portion is split into two, with the top half being the bit
  -- that contains the actual user control buttons, and the bottom bit
  -- being a scrolling list of all of the lists a user is a member of
  -- (or not a member of).
  --
  arg = {
    inset = 0, height = 180, name = "KSKUserAdminRTSplit",
    leftsplit = true, topanchor = true,
  }
  tr.hsplit = KUI:CreateHSplit(arg, tr)
  qf.useropts = tr.hsplit.topframe

  local ttr = qf.useropts
  local tmr = tr.hsplit.bottomframe

  arg = {
    inset = 0, height = 20, name = "KSKUserAdminLSSplit",
    rightsplit = true
  }
  ls.hsplit = KUI:CreateHSplit(arg, ls)
  local tls = ls.hsplit.topframe
  local bls = ls.hsplit.bottomframe

  --
  -- The main contents window on the left side needs to be a scrolling
  -- list to accomodate all of the users.
  --
  local function ulist_och(this)
    local idx = this:GetID()
    local nid = self.sortedusers[idx].id
    qf.usersearch:SetText("")
    qf.usersearch:ClearFocus()
    selected_user = nid
    setup_uinfo(self)
    this:GetParent():GetParent():SetSelected(idx, false, true)
    return true
  end

  arg = {
    name = "KSKUsersScrollList",
    itemheight = 16,
    newitem = function(objp, num)
        return KUI.NewItemHelper(objp, num, "KSKUsersButton", 155, 16,
          nil, ulist_och, nil, nil)
      end,
    setitem = function(objp, idx, slot, btn)
        return KUI.SetItemHelper(objp, btn, idx,
          function(op, ix)
            local uid = self.sortedusers[ix].id
            local tu = self.cfg.users[uid]
            local alt = self:UserIsAlt(uid)
            return(alt and "  - " or "") .. aclass(tu)
          end)
      end,
    selectitem = users_selectitem,
    highlightitem = KUI.HighlightItemHelper,
  }
  tls.slist = KUI:CreateScrollList(arg, tls)
  qf.userlist = tls.slist

  arg = {
    x = 0, y = 2, len = 16, font = "ChatFontSmall",
    width = 170, tooltip = { title = L["User Search"], text = L["TIP099"] },
  }
  bls.searchbox = KUI:CreateEditBox(arg, bls)
  qf.usersearch = bls.searchbox
  bls.searchbox:Catch("OnEnterPressed", function(this, evt, newv, user)
    this:SetText("")
  end)
  bls.searchbox:Catch("OnValueChanged", function(this, evt, newv, user)
    if (not self.cfg.users) then
      return
    end
    if (user and newv and newv ~= "") then
      local lnv = strlower(newv)
      local tln
      for k,v in pairs(self.cfg.users) do
        tln = strlower(v.name)
        if (strfind(tln, lnv, 1, true)) then
          for kk,vv in ipairs(self.sortedusers) do
            if (self.cfg.users[vv.id].name == v.name) then
              qf.userlist:SetSelected(kk, true)
              break
            end
          end
          return
        end
      end
    end
  end)

  --
  -- The actual user options
  --
  ttr.userrole = self:CreateRoleListDropdown("KSKUserRoleDropdown", 5, ypos, ttr)
  ttr.userrole:Catch("OnValueChanged", function(this, evt, newv, user)
    changed()
    uinfo.role = newv
  end)
  ypos = ypos - 24

  arg = {
    x = 5, y = ypos, label = { text = L["User is an Enchanter"] },
    tooltip = { title = "$$", text = L["TIP075"] },
  }
  ttr.enchanter = KUI:CreateCheckBox(arg, ttr)
  ttr.enchanter:Catch("OnValueChanged", function(this, evt, val, user)
    changed()
    uinfo.enchanter = val
  end)
  ypos = ypos - 24

  arg = {
    x = 5, y = ypos, label = { text = L["User is an Alt of"] },
    tooltip = { title = "$$", text = L["TIP076"] },
  }
  ttr.isalt = KUI:CreateCheckBox(arg, ttr)
  ttr.isalt:Catch("OnValueChanged", function(this, evt, val, user)
    changed()
    ttr.mainsel:SetEnabled(val)
    if (not val) then
      uinfo.isalt = val
      uinfo.main = ""
      uinfo.mainid = ""
      ttr.mainname:SetText("")
    end
    if (self.popupwindow) then
      self.popupwindow:Hide()
      self.popupwindow = nil
    end
  end)
  ypos = ypos - 24

  arg = {
    x = 24, y = ypos, border = true, height = 20, width = 140,
    autosize = false,
  }
  ttr.mainname = KUI:CreateStringLabel(arg, ttr)
  qf.useraltnamebox = ttr.mainname

  arg = {
    x = 2, y = ypos, text = L["Select"], width = 80,
    tooltip = { title = "$$", text = L["TIP077"] },
  }
  ttr.mainsel = KUI:CreateButton(arg, ttr)
  ttr.mainsel:ClearAllPoints()
  ttr.mainsel:SetPoint("TOPLEFT", ttr.mainname, "TOPRIGHT", 8, 2)
  ttr.mainsel:Catch("OnClick", function(this, evt)
    select_main(self, this)
  end)
  ypos = ypos - 24

  arg = {
    x = 5, y = ypos, label = { text = L["User is Frozen"] },
    tooltip = { title = "$$", text = L["TIP078"] },
  }
  ttr.frozen = KUI:CreateCheckBox(arg, ttr)
  ttr.frozen:Catch("OnValueChanged", function(this, evt, val, user)
    changed()
    uinfo.frozen = val
  end)
  ypos = ypos - 24

  arg = {
    x = "CENTER", y = ypos, text = L["Update"], enabled = false,
    tooltip = { title = "$$", text = L["TIP080"] },
  }
  ttr.updatebtn = KUI:CreateButton(arg, ttr)
  qf.userupdbtn = ttr.updatebtn
  ttr.updatebtn:Catch("OnClick", function(this, evt)
    self:SetUserRole(selected_user, uinfo.role, nil, true)
    self:SetUserEnchanter(selected_user, uinfo.enchanter, nil, true)
    self:SetUserFrozen(selected_user, uinfo.frozen, nil, true)
    -- Must be last! It does refreshes which will erase uinfo.
    self:SetUserIsAlt(selected_user, uinfo.isalt, uinfo.mainid, nil, true)

    self:RefreshAllMemberLists()

    self:AddEvent(self.currentid, "MDUSR", selected_user, tonumber(uinfo.role),
      uinfo.enchanter and true or false, uinfo.frozen and true or false,
      uinfo.isalt and true or false, uinfo.mainid and uinfo.mainid or "")
    ttr.updatebtn:SetEnabled(false)
  end)

  --
  -- The middle right frame is used to display all of the roll lists,
  -- and what position the user occupies on that list, if any. We create
  -- a title label and then a frame to cover the rest of the frame, which
  -- will house the scrolling list.
  --
  arg = {
    x = "CENTER", y = 0, width = 240, height = 24, autosize = false,
    text = strfmt(L["User %s / %s lists"], green(L["on"]), red(L["not on"])),
    font = "GameFontNormal", border = true, justifyh = "CENTER",
  }
  tmr.title = KUI:CreateStringLabel(arg, tmr)

  local tm = MakeFrame("Frame", nil, tmr)
  tm:ClearAllPoints()
  tm:SetPoint("TOPLEFT", tmr, "TOPLEFT", 0, -24)
  tm:SetPoint("BOTTOMRIGHT", tmr, "BOTTOMRIGHT", 0, 0)

  arg = {
    name = "KSKUserInWhichScrollList",
    itemheight = 16,
    newitem = function(objp, num)
        return KUI.NewItemHelper(objp, num, "KSKUmemButton", 200, 16,
          nil, function() return end, nil, nil)
      end,
    setitem = function(objp, idx, slot, btn)
        return KUI.SetItemHelper(objp, btn, idx, function(op, ix)
            return umemlist[ix]
          end)
      end,
    selectitem = function(objp, idx, slot, btn, onoff)
        return KUI.SelectItemHelper(objp, idx, slot, btn, onoff,
          function() return nil end)
      end,
    highlightitem = function(objp, idx, slot, btn, onoff)
      return KUI.HighlightItemHelper(objp, idx, slot, btn, onoff)
    end,
  }
  tm.slist = KUI:CreateScrollList(arg, tm)
  qf.umemlist = tm.slist

  --
  -- The command buttons at the bottom of the left hand side to add and
  -- delete users.
  --
  arg = {
    x = 25, y = 0, width = 100, height = 24, text = L["Create"],
    tooltip = { title = "$$", text = L["TIP081"] },
  }
  br.createbutton = KUI:CreateButton(arg, br)
  br.createbutton:Catch("OnClick", function(this, evt)
    create_user_button(self)
  end)

  arg = {
    x = 130, y = 0, width = 100, height = 24, text = L["Delete"],
    tooltip = { title = "$$", text = L["TIP082"] },
  }
  br.deletebutton = KUI:CreateButton(arg, br)
  br.deletebutton:Catch("OnClick", function(this, evt)
    delete_user_button(self, selected_user)
  end)

  arg = {
    x = 25, y = -25, width = 100, height = 24, text = L["Rename"],
    tooltip = { title = "$$", text = L["TIP083"] },
  }
  br.renamebutton = KUI:CreateButton(arg, br)
  br.renamebutton:Catch("OnClick", function(this, evt)
    rename_user_button(self, selected_user)
  end)

  arg = {
    x = 130, y = -25, width = 100, height = 24, text = L["Guild Import"],
    tooltip = { title = "$$", text = L["TIP084"] },
  }
  br.guildimp = KUI:CreateButton(arg, br)
  br.guildimp:Catch("OnClick", function(this, evt)
    guild_import_button(self, true)
  end)
  self.qf.guildimp = br.guildimp

  arg = {
    y = -50, width = 100, height = 24, text = L["Add Missing"],
    justifyh = "CENTER", tooltip = { title = "$$", text = L["TIP086"] },
  }
  br.addmissing = KUI:CreateButton(arg, br)
  br.addmissing:Catch("OnClick", function(this, evt)
    add_missing_button(self)
  end)
  self.qf.addmissing = br.addmissing
end

function ksk:RefreshUsers()
  local olduser = selected_user or nil
  local oldidx = nil

  self.sortedusers = {}
  selected_user = nil

  for k,v in pairs(self.cfg.users) do
    if (not self:UserIsAlt(k, v.flags)) then
      local ent = { id = k }
      tinsert(self.sortedusers, ent)
    end
  end

  tsort(self.sortedusers, function(a, b)
    return self.cfg.users[a.id].name < self.cfg.users[b.id].name
  end)

  for i = #self.sortedusers, 1, -1 do
    local uid = self.sortedusers[i].id
    local usr = self.cfg.users[uid]
    if (usr.alts) then
      self.sortedusers[i].hasalts = true
      for j = 1, #usr.alts do
        local ent = { id = usr.alts[j], main = uid }
        tinsert(self.sortedusers, i+j, ent)
      end
    end
  end

  for k,v in ipairs(self.sortedusers) do
    if (v.id == olduser) then
      oldidx = k
      break
    end
  end

  qf.userlist.itemcount = self.cfg.nusers
  qf.userlist:UpdateList()

  qf.userlist:SetSelected(oldidx)
  changed(true)
  self:RefreshCSData()
  self:RefreshConfigUsers()
end

function ksk:FindUser(name, cfgid)
  if (not self.frdb or not self.frdb.configs or self.frdb.tempcfg) then
    return nil
  end

  local name = K.CanonicalName(name)
  assert(name)

  cfgid = cfgid or self.currentid
  name = strlower(name)

  for k,v in pairs(self.frdb.configs[cfgid].users) do
    if (strlower(v.name) == name) then
      return k
    end
  end

  return nil
end

function ksk:GetUserFlags(userid, cfgid)
  local cfgid = cfgid or self.currentid

  if (not cfgid or not userid) then
    return nil
  end

  if (not self.frdb.configs[cfgid]) then
    return nil
  else
    if (not self.frdb.configs[cfgid].users[userid]) then
      return nil
    end
  end
  return self.frdb.configs[cfgid].users[userid].flags or ""
end

local function find_flag(this, userid, flags, flag, cfgid)
  local fs = flags or this:GetUserFlags(userid, cfgid)

  if (not fs) then
    return false
  end

  if (strfind(fs, flag) ~= nil) then
    return true
  end

  return false
end

local function set_flag(this, userid, flag, onoff, cfgid, arg, nocmd)
  local cfgid = cfgid or this.currentid
  local user = this.frdb.configs[cfgid].users[userid]
  local onoff = onoff and true or false

  if (not nocmd) then
    this:AddEvent(cfgid, "CHUSR", userid, flag, onoff, arg and tostring(arg) or "")
  end

  if (onoff) then
    if (not user.flags) then
      user.flags = ""
    end
    if (strfind(user.flags, flag)) then
      return false
    end
    user.flags = user.flags .. flag
    return true
  else
    if (not user.flags) then
      return false
    end

    if (strfind(user.flags, flag)) then
      local nf = string.gsub(user.flags, flag, "")
      user.flags = nf
    end

    return true
  end
end

function ksk:UserIsEnchanter(userid, flags, cfg)
  return find_flag(self, userid, flags, "E", cfg)
end

function ksk:UserIsFrozen(userid, flags, cfg)
  return find_flag(self, userid, flags, "F", cfg)
end

function ksk:UserIsCoadmin(uid, cfgid)
  local cfgid = cfgid or self.currentid

  if (self.frdb.configs[cfgid].admins[uid] or self.frdb.configs[cfgid].owner == uid) then
    return true
  end

  return false
end

function ksk:UserIsAlt(userid, flags, cfg)
  local cfg = cfg or self.currentid
  local rv = find_flag(self, userid, flags, "A", cfg)

  if (rv == true) then
    local mid, ts, ts2, ts3
    local ut = self.frdb.configs[cfg].users

    mid = ut[userid].main
    if (ut[mid]) then
      ts = class(ut[mid])
      ts2 = aclass(ut[mid])
      ts3 = ut[mid].name
    end
    return rv, mid, ts, ts2, ts3
  end

  return rv, nil, nil, nil, nil
end

function ksk:UserRole(userid, cfg)
  local cfg = cfg or self.currentid
  return self.frdb.configs[cfg].users[userid].role or 0
end

function ksk:SetUserEnchanter(userid, onoff, cfg, nocmd)
  local cfg = cfg or self.currentid
  local ret = false
  local onoff = onoff or false

  if (set_flag(self, userid, "E", onoff, cfg, nil, nocmd)) then
    if (cfg == self.currentid) then
      self:RefreshAllMemberLists()
    end
    ret = true
  end

  --
  -- If this user is no longer an enchanter, check the config to see if they
  -- are assigned as one of the target enchanters for loot distribution. If
  -- they are we need to remove them.
  --
  if (not onoff) then
    for i = 1, self.MAX_DENCHERS do
      if (self.frdb.configs[cfg].settings.denchers[i] == userid) then
        self.frdb.configs[cfg].settings.denchers[i] = nil
      end
    end
    if (cfg == self.currentid) then
      self:RefreshConfigLootUI(false)
    end
  end

  return ret
end

function ksk:SetUserFrozen(userid, onoff, cfg, nocmd)
  local cfg = cfg or self.currentid
  local onoff = onoff or false

  if (set_flag(self, userid, "F", onoff, cfg, nil, nocmd)) then
    if (cfg == self.currentid) then
      self:RefreshAllMemberLists()
    end
    return true
  end
  return false
end

--
-- We potentially have a fair bit of processing to do here. If the user was
-- not previously marked as an alt, and any configurations are using tethered
-- alts, we will need to make sure that the user's main is now inserted into
-- the list at the position this alt was, and remove the alt from the roll
-- list. If the users main is already in the roll list, we must simply
-- delete this alt from the roll lists as it will now be tethered to their
-- main.
--
function ksk:SetUserIsAlt(userid, onoff, main, cfg, nocmd)
  local cfg = cfg or self.currentid
  local onoff = onoff or false
  local cfp = self.frdb.configs[cfg]
  local cfu = cfp.users

  if (not main or main == "") then
    onoff = false
  end

  set_flag(self, userid, "A", onoff, cfg, main, nocmd)

  if (self.lootmemberid == userid) then
    self.lootmemberid = nil
  end

  local usr = cfu[userid]

  if (onoff) then
    if (usr.main) then
      --
      -- We were previous assigned as an alt of another main. We need to
      -- remove this userid from that old main's list of alts. If that
      -- will leave the old main with no alts, set their alts entry to nil.
      --
      local oldm = cfu[usr.main]

      for k,v in pairs(oldm.alts) do
        if (v == userid) then
          tremove(oldm.alts, k)
          break
        end
      end

      if (not next(oldm.alts)) then
        oldm.alts = nil
      end
    end

    --
    -- Now add this user to the new main's list of alts if we are not already
    -- in the list(which we never should be).
    --
    local musr = cfu[main]
    local found = false
    usr.main = main
    if (not musr.alts) then
      musr.alts = {}
    end
    for k,v in pairs(musr.alts) do
      if (v == userid) then
        found = true
        break
      end
    end
    if (not found) then
      tinsert(musr.alts, userid)
      tsort(musr.alts, function(a,b)
        return cfu[a].name < cfu[b].name
      end)
    end
  else -- not onoff
    if (usr.main) then
      local musr = cfu[usr.main]
      for k,v in ipairs(musr.alts) do
        if (v == userid) then
          tremove(musr.alts, k)
          break
        end
      end
      if (not next(musr.alts)) then
        musr.alts = nil
      end
    end
    usr.main = nil
  end

  self:FixupLists(cfg)
  if (cfg == self.currentid) then
    self:RefreshUsers()
    self:RefreshAllMemberLists()
  end

  return true
end

function ksk:SetUserRole(userid, value, cfg, nocmd)
  local cfg = cfg or self.currentid

  if (not nocmd) then
    self:AddEvent(cfg, "CHUSR", "R", true, tonumber(value))
  end

  self.frdb.configs[cfg].users[userid].role = value
end

local function get_next_uid(self, cfgid)
  local cfgid = cfgid or self.currentid
  local myuid = self.csdata[cfgid].myuid
  local ia, am = self:IsAdmin(myuid, cfgid)

  if (self.frdb.configs[cfgid].nusers == 4094) then
    error("Terribly sorry but KonferSK has a limit of 4094 users :(", 2)
    return nil
  end

  for i = 1, 4094 do
    local is = strfmt("%s%03x", self.frdb.configs[cfgid].admins[am].id, i)
    if (not self.frdb.configs[cfgid].users[is]) then
      return is
    end
  end
end

function ksk:CreateNewUser(name, cls, cfgid, norefresh, bypass, myid, nocmd)
  local cfgid = cfgid or self.currentid
  local name = K.CanonicalName(name, nil)

  if (not bypass and self:CheckPerm(cfgid)) then
    return nil
  end

  local uid = self:FindUser(name, cfgid)
  if (uid and not nocmd) then
    err(L["user %q already exists. Try again."], aclass(self.frdb.configs[cfgid].users[uid]))
    return nil
  end

  uid = myid or get_next_uid(self, cfgid)
  if (not uid) then
    return
  end

  self.frdb.configs[cfgid].nusers = self.frdb.configs[cfgid].nusers + 1
  self.frdb.configs[cfgid].users[uid] = {
    name = name,
    class = cls,
    role = 0,
    flags = ""
  }

  if (not nocmd) then
    info(L["user %q created."], aclass(name, cls))
  end

  if (name == K.player.player) then
    self.csdata[cfgid].myuid = uid
    self.csdata[cfgid].is_admin = nil
  end

  if (not norefresh and cfgid == self.currentid) then
    self:RefreshUsers()
  end

  --
  -- If the config we are adding this user to is the current config, and we
  -- are in a raid, we need to scan the list of missing members to see if
  -- this user was in that list, and if so, remove them from it.
  --
  if (self.users and cfgid == self.currentid) then
    local olduid = "0fff:" .. cls .. ":" .. name
    if (self.missing[olduid]) then
      self.nmissing = self.nmissing - 1
      self.missing[olduid] = nil
      qf.userbuttons.addmissing:SetEnabled(self.csdata[self.currentid].is_admin and self.nmissing > 0)
      if (not norefreh) then
        self:RefreshRaid()
      end
    end
  end

  if (not nocmd) then
    self:AddEvent(cfgid, "MKUSR", uid, name, cls, norefresh and true or false)
  end

  return uid
end

--
-- Deleting a user is a lot trickier than you'd think. If this is the user
-- doing the actual delete (i.e. nocmd == false) then we have to eject
-- events for removing any alts of the user, or changing the user's main
-- if this user was themselves an alt. However, if this is NOT the original
-- delete command (nocmd == true) then we don't do any of that, as we will
-- have received other events that do it all for us, and all we have to do
-- is delete this actual user. Right? Wrong. If we got the delete user command
-- when two or more admins were out of sync, the admin that issued the delete
-- user command may not know about all of the user's alts, so we have to
-- check for that case and locally delete any alts the user may have had, at
-- the time that we knew about the user.
--
function ksk:DeleteUser(uid, cfgid, alts, nocmd)
  local cfg = cfgid or self.currentid
  local lcp = self.frdb.configs[cfgid]
  local refreshitems = false
  local refreshhistory = false

  local function each_delete(userid, cfg)
    if (not lcp.users[userid]) then
      return
    end

    if (not nocmd and cfg == self.currentid) then
      info(L["user %q deleted."], aclass(lcp.users[userid]))
    end
    for i = 1, self.MAX_DENCHERS do
      if (lcp.settings.denchers[i] == userid) then
        lcp.settings.denchers[i] = nil
      end
    end

    --
    -- If the user was destined to receive the next drop of an item, remove
    -- that particular option from the item option table.
    --
    for lk,lv in pairs(lcp.items) do
      if (lv.nextdrop ~= nil) then
        if (lv.nextdrop.user == userid) then
          lcp.items[lk].nextdrop = nil
          refreshitems = true
        end
      end
    end

    --
    -- Remove the user from all lists
    --
    for lk,lv in pairs(lcp.lists) do
      self:DeleteMember(userid, lk, cfg, true)
    end

    local isalt = self:UserIsAlt(userid, nil, cfg)
    if (isalt) then
      local main = lcp.users[userid].main
      if (main and lcp.users[main]) then
        self:SetUserIsAlt(userid, false, nil, cfg, true)
      end
    end

    --
    -- If the user had receieved items and is in the item history
    -- database, we need to convert the userid portion of the string
    -- into the user name and class, so that it can still be
    -- displayed correctly.
    --
    local nwhostr = lcp.users[userid].name .. "/" .. lcp.users[userid].class
    for k,v in ipairs(lcp.history) do
      if (v[HIST_WHO] == userid) then
        v[HIST_WHO] = nwhostr
        refreshhistory = true
      end
    end

    if (lcp.admins[userid]) then
      self:DeleteAdmin(userid, cfg)
    end

    if (cfg == self.currentid and userid == selected_user) then
      selected_user = nil
    end

    if (lcp.users[userid]) then
      lcp.users[userid] = nil
      lcp.nusers = lcp.nusers - 1
    end
  end

  if (lcp.users[uid].alts) then
    while (lcp.users[uid].alts) do
      local v = lcp.users[uid].alts[1]
      if (alts) then
        each_delete(v, cfg)
      else
        self:SetUserIsAlt(v, false, nil, cfg, true)
      end
    end
  end

  each_delete(uid, cfg)

  if (not nocmd) then
    self:AddEvent(cfg, "RMUSR", uid, alts and true or false)
  end

  if (cfg ~= self.currentid) then
    return
  end

  self:RefreshUsers()
  self:RefreshAllMemberLists()
  self:RefreshConfigAdminUI(false)

  if (refreshitems) then
    self:RefreshItemList()
  end

  if (refreshhistory) then
    self:RefreshHistory()
  end

  if (self.users) then
    self:RefreshRaid()
  end
end

local function confirm_delete_user(self, arg, alts)
  local uid = arg.uid
  local cfg = arg.cfg or self.currentid

  self:DeleteUser(uid, cfg, alts, false)
end

function ksk:DeleteUserCmd(userid, show, cfg)
  local cfg = cfg or self.currentid

  if (self.frdb.configs[cfg].owner == userid) then
    err(L["cannot delete user %q as they are the owner of the configuration."],
      aclass(self.frdb.configs[cfg].users[userid]))
    return true
  end

  local isshown = show or self.mainwin:IsShown()
  self.mainwin:Hide()

  local alts = nil
  if (self.frdb.configs[cfg].users[userid].alts) then
    alts = L["Delete All Alts of User"]
  end
  K.ConfirmationDialog(self, L["Delete User"], L["DELUSER"],
    self.frdb.configs[cfg].users[userid].name, function(s, ag, al) confirm_delete_user(s, ag, al) end,
    { uid=userid, cfg=cfg }, isshown, 210, alts)

  return false
end

function ksk:RenameUser(userid, newname, cfg, nocmd)
  local cfg = cfg or self.currentid

  local oldname = self.frdb.configs[cfg].users[userid].name
  local cl = self.frdb.configs[cfg].users[userid].class
  newname = K.CanonicalName(newname, nil)
  if (not nocmd) then
    info(L["NOTICE: user %q renamed to %q."], aclass(oldname, cl),
      aclass(newname, cl))
  end
  self.frdb.configs[cfg].users[userid].name = newname

  --
  -- If this user is an alt, we will need to re-sort the main's alt
  -- list so it remains alphabetical.
  --
  local isalt, main = self:UserIsAlt(userid, nil, cfg)
  if (isalt) then
    local musr = self.frdb.configs[cfg].users[main]
    tsort(musr.alts, function(a,b)
      return self.frdb.configs[cfg].users[a].name < self.frdb.configs[cfg].users[b].name
    end)
  end

  if (not nocmd) then
    self:AddEvent(cfg, "MVUSR", userid, newname)
  end

  if (cfg == self.currentid) then
    self:RefreshUsers()
    self:RefreshAllMemberLists()
  end

  return false
end

--
-- Reserve a user in the roll lists. This data is not stored permanently.
-- We keep one list for each config space, and we do not delete the list
-- when config spaces are switched, only if they are deleted.
--

function ksk:ReserveUser(uid, onoff, cfgid, nocmd)
  local cfgid = cfgid or self.currentid
  local rd = self.csdata[cfgid]
  local onoff = onoff or false

  if (not rd) then
    return
  end

  if (not rd.reserved) then
    rd.reserved = {}
  end

  if (onoff) then
    rd.reserved[uid] = true
  else
    rd.reserved[uid] = nil
  end

  if (not nocmd) then
    ksk:SendAM("RSUSR", "ALERT", uid, onoff)
  end

  if (cfgid == self.currentid) then
    self:RefreshUsers()
    self:RefreshAllMemberLists()
  end
end

function ksk:UserIsReserved(uid, cfgid)
  local cfgid = cfgid or self.currentid

  local rd = self.csdata[cfgid]
  if (not rd) then
    return false
  end

  if (not rd.reserved or not rd.reserved[uid]) then
    return false
  end
  return rd.reserved[uid]
end

function ksk:RefreshUsersLists()
  refresh_user_membership(self)
end

function ksk:RefreshUsersUI(reset)
  if (reset) then
    selected_user = nil
  end
  self:RefreshUsers()
  self:RefreshUsersLists()
  qf.userbuttons.addmissing:SetEnabled(false)

  if (self.users and self.csdata[self.currentid].is_admin and self.nmissing and self.nmissing > 0) then
    qf.userbuttons.addmissing:SetEnabled(true)
  end

  local en = false
  if (K.player.is_guilded and self.csdata[self.currentid].is_admin) then
    en = true
  end
  self.qf.guildimp:SetEnabled(en)
end

