--[[
   KahLua KonferSK - a suicide kings loot distribution addon.
     WWW: http://kahluamod.com/ksk
     SVN: http://kahluamod.com/svn/konfersk
     IRC: #KahLua on irc.freenode.net
     E-mail: cruciformer@gmail.com
   Please refer to the file LICENSE.txt for the Apache License, Version 2.0.

   Copyright 2008-2017 James Kean Johnston. All rights reserved.

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
  error ("KahLua KonferSK: could not find KahLua Kore.", 2)
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
local green = ksk.green
local red = ksk.red
local class = ksk.class
local aclass = ksk.aclass

local seluser = nil
local umemlist = nil
local uinfo = {}

--
-- This file contains all of the UI handling code for the users panel,
-- as well as all user manipulation functions.
--
local function changed (res, user)
  if (not user) then
    return
  end

  res = res or false
  if (not seluser) then
    res = true
  end
  if (ksk.qf.userupdbtn) then
    ksk.qf.userupdbtn:SetEnabled (not res)
  end
end

local function setup_uinfo()
  if (not seluser) then
    return
  end

  uinfo = {}
  uinfo.role = ksk:UserRole (seluser) or 0
  uinfo.enchanter = ksk:UserIsEnchanter (seluser) or false
  local isalt, altidx, _, _, altname = ksk:UserIsAlt (seluser)
  uinfo.isalt = isalt or false
  uinfo.main = altname or ""
  uinfo.mainid = altidx
  uinfo.frozen = ksk:UserIsFrozen (seluser) or false
  if (ksk.users[seluser].alts) then
    uinfo.ismain = true
  else
    uinfo.ismain = false
  end
end

local function enable_selected (en)
  if (ksk.qf.usertopbar) then
    ksk.qf.usertopbar.seluser:SetShown (en)
  end
  if (ksk.qf.useropts.userrole) then
    ksk.qf.useropts.userrole:SetEnabled (en)
  end
  if (ksk.qf.useropts.enchanter) then
    ksk.qf.useropts.enchanter:SetEnabled (en)
  end
  if (ksk.qf.useropts.isalt) then
    ksk.qf.useropts.isalt:SetEnabled (en)
  end
  if (ksk.qf.useropts.mainname) then
    ksk.qf.useropts.mainname:SetEnabled (en)
  end
  if (ksk.qf.useropts.frozen) then
    ksk.qf.useropts.frozen:SetEnabled (en)
  end
  if (ksk.qf.useropts.isalt) then
    ksk.qf.useropts.isalt:SetEnabled (en)
  end
  if (ksk.qf.useropts.mainsel) then
    ksk.qf.useropts.mainsel:SetEnabled (en)
  end
  if (ksk.qf.userbuttons) then
    if (ksk.qf.userbuttons.deletebutton) then
      ksk.qf.userbuttons.deletebutton:SetEnabled (en)
    end
    if (ksk.qf.userbuttons.renamebutton) then
      ksk.qf.userbuttons.renamebutton:SetEnabled (en)
    end
  end
end

local function users_selectitem (objp, idx, slot, btn, onoff)
  if (onoff) then
    seluser = ksk.sortedusers[idx].id
    enable_selected (true)

    if (ksk.popupwindow and ksk.popupwindow.seluser ~= ksk.seluser) then
      ksk.popupwindow:Hide ()
      ksk.popupwindow = nil
    end

    setup_uinfo ()

    ksk.qf.usertopbar.SetCurrentUser (seluser)
    ksk.qf.useropts.userrole:SetValue (uinfo.role)
    ksk.qf.useropts.enchanter:SetChecked (uinfo.enchanter)
    ksk.qf.useropts.isalt:SetChecked (uinfo.isalt)
    ksk.qf.useropts.mainname:SetText (uinfo.main)
    ksk.qf.useropts.frozen:SetChecked (uinfo.frozen)
    ksk.qf.useropts.isalt:SetEnabled (not uinfo.ismain)
    ksk.qf.useropts.mainsel:SetEnabled (uinfo.isalt)
    ksk:RefreshMembership ()
  else
    seluser = nil
    enable_selected (false)
    if (initdone) then
      ksk:RefreshMembership ()
    end
  end

  changed (true, true)
end

function ksk.CreateRoleListDropdown (name, x, y, parent, w)
  local arg = {
    name = name, mode = "SINGLE", itemheight = 16,
    x = x, y = y, dwidth = w or 150,
    label =  { text = L["User Role"], pos = "LEFT" },
    items = {
      { text = ksk.rolenames[0], value = 0 },
      { text = ksk.rolenames[1], value = 1 },
      { text = ksk.rolenames[2], value = 2 },
      { text = ksk.rolenames[3], value = 3 },
      { text = ksk.rolenames[4], value = 4 },
      { text = ksk.rolenames[5], value = 5 },
    },
    tooltip = { title = "$$", text = L["TIP071"] },
  }
  return KUI:CreateDropDown (arg, parent)
end

local function create_user_button()
  if (not ksk.createuserdlg) then
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
      okbutton = { text = K.ACCEPTSTR },
      cancelbutton = { text = K.CANCELSTR },
    }

    local ret = KUI:CreateDialogFrame (arg)

    arg = {
      x = 0, y = 0, len = 16,
      label = { text = L["User Name"], pos = "LEFT" },
      tooltip = { title = "$$", text = L["TIP072"] },
    }
    ret.username = KUI:CreateEditBox (arg, ret)
    ret.username:SetFocus ()

    arg = {
      x = 0, y = -30, dwidth = 125, mode = "SINGLE", itemheight = 16,
      label = { text = L["User Class"], pos = "LEFT" },
      items = {}, name = "KSKCreateUserClassDD",
      tooltip = { title = "$$", text = L["TIP073"] },
    }
    for k,v in pairs(K.IndexClass) do
      if (v.c) then
        tinsert (arg.items, { text = v.c, value = k, color = K.ClassColorsRGBPerc[k] })
      end
    end
    ret.userclass = KUI:CreateDropDown (arg, ret)
    ret.userclass.cset = nil
    ret.userclass:Catch ("OnValueChanged", function (this, evt, newv)
      this.cset = newv
    end)

    ret.userrole = ksk.CreateRoleListDropdown ("CreateUserRoleDD", 0, -60, ret)
    ret.userrole.rset = 0
    ret.userrole:Catch ("OnValueChanged", function (this, evt, newv)
      this.rset = newv
    end)

    ret.OnCancel = function (this)
      this:Hide ()
      ksk.mainwin:Show ()
    end

    ret.OnAccept = function (this)
      if (not this.username:GetText() or this.username:GetText() == "") then
        err (L["you must specify a character name."])
        this.username:SetFocus ()
        return true
      end
      if (not this.userclass.cset) then
        err (L["you must set a user class."])
        return true
      end
      local uid = ksk:CreateNewUser (this.username:GetText (), this.userclass.cset)
      if (uid) then
        ksk:SetUserRole (uid, this.userrole.rset)
        this:Hide ()
        ksk.mainwin:Show ()
        return false
      end
    end

    ksk.createuserdlg = ret
    ksk.createuserdlg.userclass:SetValue (0)
  end

  ksk.mainwin:Hide ()
  ksk.createuserdlg:Show ()
  ksk.createuserdlg.username:SetText ("")
  ksk.createuserdlg.username:SetFocus ()
end

local function delete_user_button (uid)
  ksk:DeleteUserCmd (uid)
end

local function rename_user_button (uid)
  local function rename_helper (newname, old)
    local found = nil
    local cname = strlower (newname)

    for k,v in pairs (ksk.users) do
      if (strlower (v.name) == cname) then
        found = ksk.users[k]
      end
    end

    if (found) then
      err (L["user %q already exists. Try again."], aclass (found))
      return true
    end

    local rv = ksk:RenameUser (old, cname)
    if (rv) then
      return true
    end

    return false
  end

  ksk:RenameDialog (L["Rename User"], L["Old Name"],
    ksk.users[uid].name, L["New Name"], 48, rename_helper,
    uid, true)

  ksk.mainwin:Hide ()
  ksk.renamedlg:Show ()
  ksk.renamedlg.input:SetText ("")
  ksk.renamedlg.input:SetFocus ()
end

local function guild_import_button (shown)
  local arg = {
    x = "CENTER", y = "MIDDLE",
    name = "KSKGuildImportDlg",
    title = L["Import Guild Users"],
    border = true,
    width = 240,
    height = (K.guild.numranks * 28) + 92,
    canmove = true,
    canresize = false,
    escclose = true,
    okbutton = { text = K.ACCEPTSTR },
    cancelbutton = {text = K.CANCELSTR },
  }

  local y = 24

  local ret = KUI:CreateDialogFrame (arg)

  arg = {
    y = 0, width = 170, height = 24
  }
  for i = 1, K.guild.numranks do
    y = y - 24
    local cbn = "rankcb" .. tostring(i)
    arg.y = y
    arg.x = 10
    arg.label = { text = K.guild.ranks[i] }
    ret[cbn] = KUI:CreateCheckBox (arg, ret)
  end

  y = y - 24

  arg = {
    x = 10, y = y, minval = 1, maxval = ksk.maxlevel, initialvalue = 100,
    step = 1, label = { text = L["Minimum Level"], },
    tooltip = { title = "$$", text = L["TIP074"] },
  }
  ret.minlevel = KUI:CreateSlider (arg, ret)

  ret.isshown = shown
  
  ret.OnCancel = function (this)
    this:Hide ()
    if (this.isshown) then
      ksk.mainwin:Show ()
    end
  end

  local function do_rank (r, minlev)
    local rv = 0
    local ngm = K.guild.numroster
    for i = 1, ngm do
      if (K.guild.roster.id[i].rankidx == r and K.guild.roster.id[i].level >= minlev) then
        local nm = K.guild.roster.id[i].name
        local uid = ksk:FindUser (nm)
        if (not uid) then
          local kcl = K.guild.roster.id[i].class
          uid = ksk:CreateNewUser (nm, kcl, nil, true)
          if (uid) then
            rv = rv + 1
          else
            err ("error adding user %q!", white (nm))
          end
        end
      end
    end
    return rv
  end

  ret.OnAccept = function (this)
    local cas,ccs
    local tadd = 0
    local minlev = this.minlevel:GetValue ()
    for i = 1, K.guild.numranks do
      ccs = "rankcb" .. tostring(i)
      if (this[ccs]:GetChecked ()) then
        tadd = tadd + do_rank (i - 1, minlev)
      end
    end
    ksk:RefreshUsers ()
    ksk:RefreshRaid ()
    ksk.SendAM ("RFUSR", "ALERT", true)
    this:Hide ()
    if (this.isshown) then
      ksk.mainwin:Show ()
    end
    info (L["added %d user(s)."], tadd)
  end

  ksk.mainwin:Hide ()
  ret:Show ()
end

function ksk:ImportGuildUsers (shown)
  guild_import_button (shown)
end

local selmain_popup

local function select_main(btn, lbl)
  if (not seluser) then
    return
  end

  if (ksk.popupwindow) then
    ksk.popupwindow:Hide ()
    ksk.popupwindow = nil
  end

  local ulist = {}

  for k,v in pairs (ksk.users) do
    if (k ~= seluser and not ksk:UserIsAlt (k, v.flags)) then
      local ti = { text = aclass (v), value = k }
      tinsert (ulist, ti)
    end
  end
  tsort (ulist, function (a,b)
    return ksk.users[a.value].name < ksk.users[b.value].name
  end)

  local function pop_func (puid)
    local ulist = selmain_popup.selectionlist
    changed (nil, true)
    ksk.qf.useraltnamebox:SetText (aclass (ksk.users[puid]))
    ksk.popupwindow:Hide ()
    ksk.popupwindow = nil
    uinfo.isalt = true
    uinfo.main = ksk.users[puid].name
    uinfo.mainid = puid
  end

  if (not selmain_popup) then
    selmain_popup = ksk:PopupSelectionList ("KSKMainSelPopup", ulist,
      nil, 205, 400, ksk.mainwin.tabs[ksk.USERS_TAB].content, 16, pop_func,
      nil, 20)
    local arg = {
      x = 0, y = 2, len = 48, font = "ChatFontSmall", width = 170,
      tooltip = { title = L["User Search"], text = L["TIP099"] },
      parent = selmain_popup.footer,
    }
    selmain_popup.usearch = KUI:CreateEditBox (arg, selmain_popup.footer)
    selmain_popup.usearch.toplevel = selmain_popup
    ksk.qf.selmainsearch = selmain_popup.usearch
    selmain_popup.usearch:Catch ("OnEnterPressed", function (this)
      this:SetText ("")
    end)
    selmain_popup.usearch:HookScript ("OnEnter", function (this)
      this.toplevel:StopTimeoutCounter ()
    end)
    selmain_popup.usearch:HookScript ("OnLeave", function (this)
      this.toplevel:StartTimeoutCounter ()
    end)
    selmain_popup.usearch:Catch ("OnValueChanged", function (this, evt, newv, user)
      if (not ksk.users or not this.toplevel.selectionlist or this.toplevel.slist.itemcount < 1) then
        return
      end
      if (user and newv and newv ~= "") then
        local lnv = strlower (newv)
        local tln
        for k,v in pairs (this.toplevel.selectionlist) do
          tln = strlower (ksk.users[v.value].name)
          if (strfind (tln, lnv, 1, true)) then
            this.toplevel.slist:SetSelected (k, true)
            return
          end
        end
      end
    end)
  else
    selmain_popup:UpdateList (ulist)
  end
  selmain_popup:ClearAllPoints ()
  selmain_popup:SetPoint ("TOPLEFT", btn, "TOPRIGHT", 0, 0)
  selmain_popup:Show ()
  ksk.popupwindow = selmain_popup
end

--
-- If we are in raid, add all of the current users who are missing to the
-- users database.
--
local function add_missing_button ()
  if (not ksk.inraid or not ksk.csd.isadmin or not ksk.nmissing or ksk.nmissing == 0) then
    return
  end

  while (ksk.nmissing > 0) do
    local _, v = next(ksk.missing)
    ksk:CreateNewUser (v.name, v.class, nil, true, true)
  end
  ksk:RefreshUsers ()
  ksk:RefreshRaid ()
  ksk.SendAM ("RFUSR", "ALERT", true)
end

function ksk:InitialiseUsersGUI ()
  local arg

  --
  -- Users tab. We have no sub-tabs so there is only one set of things
  -- to do here.
  --
  local ypos = 0

  local cf = ksk.mainwin.tabs[ksk.USERS_TAB].content
  local tbf = ksk.mainwin.tabs[ksk.USERS_TAB].topbar
  local ls = cf.vsplit.leftframe
  local rs = cf.vsplit.rightframe

  arg = {
    x = 0, y = -18, text = "", autosize = false, width = 250,
    font = "GameFontNormalSmall",
  }
  tbf.seluser = KUI:CreateStringLabel (arg, tbf)

  ksk.qf.usertopbar = tbf
  tbf.SetCurrentUser = function (userid)
    if (userid) then
      tbf.seluser:SetText (L["Currently Selected: "]..aclass(ksk.users[userid]))
    else
      tbf.seluser:SetText ("")
    end
  end

  --
  -- Create the horizontal split for the buttons at the bottom
  --
  arg = {
    inset = 0, height = 75,
    leftsplit = true, name = "KSKUserAdminRHSplit",
  }
  rs.hsplit = KUI:CreateHSplit (arg, rs)
  local tr = rs.hsplit.topframe
  local br = rs.hsplit.bottomframe
  ksk.qf.userbuttons = br

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
  tr.hsplit = KUI:CreateHSplit (arg, tr)
  ksk.qf.useropts = tr.hsplit.topframe

  local ttr = ksk.qf.useropts
  local tmr = tr.hsplit.bottomframe

  arg = {
    inset = 0, height = 20, name = "KSKUserAdminLSSplit",
    rightsplit = true
  }
  ls.hsplit = KUI:CreateHSplit (arg, ls)
  local tls = ls.hsplit.topframe
  local bls = ls.hsplit.bottomframe

  --
  -- The main contents window on the left side needs to be a scrolling
  -- list to accomodate all of the users.
  --
  local function ulist_och (this)
    local idx = this:GetID ()
    assert (ksk.sortedusers[idx])
    ksk.qf.usersearch:SetText ("")
    ksk.qf.usersearch:ClearFocus ()
    local nid = ksk.sortedusers[idx].id
    ksk.userid = nid
    seluser = nid
    setup_uinfo ()
    this:GetParent():GetParent():SetSelected (idx, false, true)
    return true
  end

  arg = {
    name = "KSKUsersScrollList",
    itemheight = 16,
    newitem = function (objp, num)
        return KUI.NewItemHelper (objp, num, "KSKUsersButton", 155, 16,
          nil, ulist_och, nil, nil)
      end,
    setitem = function (objp, idx, slot, btn)
        return KUI.SetItemHelper (objp, btn, idx,
          function (op, ix)
            assert (ksk.sortedusers[ix])
            local uid = ksk.sortedusers[ix].id
            local tu = ksk.users[uid]
            local alt = ksk:UserIsAlt (uid)
            return (alt and "  - " or "") .. aclass(tu)
          end)
      end,
    selectitem = users_selectitem,
    highlightitem = KUI.HighlightItemHelper,
  }
  tls.slist = KUI:CreateScrollList (arg, tls)
  ksk.qf.userlist = tls.slist

  local bdrop = {
    bgFile = KUI.TEXTURE_PATH .. "TDF-Fill",
    tile = true,
    tileSize = 32,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
  }
  tls.slist:SetBackdrop (bdrop)

  arg = {
    x = 0, y = 2, len = 16, font = "ChatFontSmall",
    width = 170, tooltip = { title = L["User Search"], text = L["TIP099"] },
  }
  bls.searchbox = KUI:CreateEditBox (arg, bls)
  ksk.qf.usersearch = bls.searchbox
  bls.searchbox:Catch ("OnEnterPressed", function (this, evt, newv, user)
    this:SetText ("")
  end)
  bls.searchbox:Catch ("OnValueChanged", function (this, evt, newv, user)
    if (not ksk.users) then
      return
    end
    if (user and newv and newv ~= "") then
      local lnv = strlower (newv)
      local tln
      for k,v in pairs (ksk.users) do
        tln = strlower (v.name)
        if (strfind (tln, lnv, 1, true)) then
          for kk,vv in ipairs (ksk.sortedusers) do
            if (ksk.users[vv.id].name == v.name) then
              ksk.qf.userlist:SetSelected (kk, true)
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
  ttr.userrole = ksk.CreateRoleListDropdown ("KSKUserRoleDropdown", 0, ypos, ttr)
  ttr.userrole:Catch ("OnValueChanged", function (this, evt, newv, user)
    changed (nil, user)
    uinfo.role = newv
  end)
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, label = { text = L["User is an Enchanter"] },
    tooltip = { title = "$$", text = L["TIP075"] },
  }
  ttr.enchanter = KUI:CreateCheckBox (arg, ttr)
  ttr.enchanter:Catch ("OnValueChanged", function (this, evt, val, user)
    changed (nil, user)
    uinfo.enchanter = val
  end)
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, label = { text = L["User is an Alt of"] },
    tooltip = { title = "$$", text = L["TIP076"] },
  }
  ttr.isalt = KUI:CreateCheckBox (arg, ttr)
  ttr.isalt:Catch ("OnValueChanged", function (this, evt, val, user)
    changed (nil, user)
    ttr.mainsel:SetEnabled (val)
    if (not val) then
      uinfo.isalt = val
      uinfo.main = ""
      uinfo.mainid = ""
      ttr.mainname:SetText ("")
    end
    if (ksk.popupwindow) then
      ksk.popupwindow:Hide ()
      ksk.popupwindow = nil
    end
  end)
  ypos = ypos - 24

  arg = {
    x = 24, y = ypos, border = true, height = 20, width = 140,
    autosize = false,
  }
  ttr.mainname = KUI:CreateStringLabel (arg, ttr)
  ksk.qf.useraltnamebox = ttr.mainname

  arg = {
    x = 1, y = ypos, text = L["Select"], width = 80,
    tooltip = { title = "$$", text = L["TIP077"] },
  }
  ttr.mainsel = KUI:CreateButton (arg, ttr)
  ttr.mainsel:ClearAllPoints ()
  ttr.mainsel:SetPoint ("TOPLEFT", ttr.mainname, "TOPRIGHT", 8, 2)
  ttr.mainsel:Catch ("OnClick", function (this, evt)
    select_main (this)
  end)
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, label = { text = L["User is Frozen"] },
    tooltip = { title = "$$", text = L["TIP078"] },
  }
  ttr.frozen = KUI:CreateCheckBox (arg, ttr)
  ttr.frozen:Catch ("OnValueChanged", function (this, evt, val, user)
    changed (nil, user)
    uinfo.frozen = val
  end)
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, text = L["Update"], enabled = false,
    tooltip = { title = "$$", text = L["TIP080"] },
  }
  ttr.updatebtn = KUI:CreateButton (arg, ttr)
  ksk.qf.userupdbtn = ttr.updatebtn
  ttr.updatebtn:Catch ("OnClick", function (this, evt)
    ksk:SetUserRole (seluser, uinfo.role, nil, true)
    ksk:SetUserEnchanter (seluser, uinfo.enchanter, nil, true)
    ksk:SetUserFrozen (seluser, uinfo.frozen, nil, true)
    -- Must be last! It does refreshes which will erase uinfo.
    ksk:SetUserIsAlt (seluser, uinfo.isalt, uinfo.mainid, nil, true)

    ksk:RefreshMemberList ()

    local es = strfmt ("%s:%d:%s:%s:%s:%s:%s", seluser, uinfo.role,
      uinfo.enchanter and "Y" or "N", uinfo.frozen and "Y" or "N",
      "N", uinfo.isalt and "Y" or "N",
      uinfo.mainid and uinfo.mainid or "")
    ksk.AddEvent (ksk.currentid, "MDUSR", es, true)
    ttr.updatebtn:SetEnabled (false)
  end)

  --
  -- The middle right frame is used to display all of the roll lists,
  -- and what position the user occupies on that list, if any. We create
  -- a title label and then a frame to cover the rest of the frame, which
  -- will house the scrolling list.
  --
  arg = {
    x = "CENTER", y = 0, width = 280, height = 24, autosize = false,
    text = strfmt (L["User %s / %s lists"], green (L["on"]), red (L["not on"])),
    font = "GameFontNormal", border = true, justifyh = "CENTER",
  }
  tmr.title = KUI:CreateStringLabel (arg, tmr)

  local tm = MakeFrame ("Frame", nil, tmr)
  tm:ClearAllPoints ()
  tm:SetPoint ("TOPLEFT", tmr, "TOPLEFT", 0, -24)
  tm:SetPoint ("BOTTOMRIGHT", tmr, "BOTTOMRIGHT", 0, 0)

  arg = {
    name = "KSKUserInWhichScrollList",
    itemheight = 16,
    newitem = function (objp, num)
        return KUI.NewItemHelper (objp, num, "KSKUmemButton", 200, 16,
          nil, function () return end, nil, nil)
      end,
    setitem = function (objp, idx, slot, btn)
        return KUI.SetItemHelper (objp, btn, idx, function (op, ix)
            return umemlist[ix]
          end)
      end,
    selectitem = function (objp, idx, slot, btn, onoff)
        return KUI.SelectItemHelper (objp, idx, slot, btn, onoff,
          function () return nil end)
      end,
    highlightitem = function (objp, idx, slot, btn, onoff)
      return KUI.HighlightItemHelper (objp, idx, slot, btn, onoff)
    end,
  }
  tm.slist = KUI:CreateScrollList (arg, tm)
  ksk.qf.umemlist = tm.slist
  tm.slist:SetBackdrop (bdrop)

  --
  -- The command buttons at the bottom of the left hand side to add and
  -- delete users.
  --
  arg = {
    x = 0, y = 0, width = 100, height = 24, text = L["Create"],
    tooltip = { title = "$$", text = L["TIP081"] },
  }
  br.createbutton = KUI:CreateButton (arg, br)
  br.createbutton:Catch ("OnClick", function (this, evt)
    create_user_button ()
  end)

  arg = {
    x = 105, y = 0, width = 100, height = 24, text = L["Delete"],
    tooltip = { title = "$$", text = L["TIP082"] },
  }
  br.deletebutton = KUI:CreateButton (arg, br)
  br.deletebutton:Catch ("OnClick", function (this, evt)
    delete_user_button (seluser)
  end)

  arg = {
    x = 0, y = -25, width = 100, height = 24, text = L["Rename"],
    tooltip = { title = "$$", text = L["TIP083"] },
  }
  br.renamebutton = KUI:CreateButton (arg, br)
  br.renamebutton:Catch ("OnClick", function (this, evt)
    rename_user_button (seluser)
  end)

  arg = {
    x = 105, y = -25, width = 100, height = 24, text = L["Guild Import"],
    tooltip = { title = "$$", text = L["TIP084"] },
  }
  br.guildimp = KUI:CreateButton (arg, br)
  br.guildimp:Catch ("OnClick", function (this, evt)
    guild_import_button (true)
  end)

  local bx = 56

  arg = {
    x = bx, y = -50, width = 100, height = 24, text = L["Add Missing"],
    tooltip = { title = "$$", text = L["TIP086"] },
  }
  br.addmissing = KUI:CreateButton (arg, br)
  br.addmissing:Catch ("OnClick", function (this, evt)
    add_missing_button ()
  end)
end

function ksk:RefreshUsers()
  ksk.sortedusers = {}
  local olduser = seluser or ""
  local oldidx = nil
  ksk.cfg = ksk.frdb.configs[ksk.currentid]
  ksk.users = ksk.cfg.users

  seluser = nil
  for k,v in pairs (ksk.users) do
    if (not ksk:UserIsAlt (k, v.flags)) then
      local ent = { id = k }
      tinsert (ksk.sortedusers, ent)
    end
  end
  tsort (ksk.sortedusers, function (a, b)
    return ksk.users[a.id].name < ksk.users[b.id].name
  end)
  for i = #ksk.sortedusers, 1, -1 do
    local usr = ksk.users[ksk.sortedusers[i].id]
    if (usr.alts) then
      for j = 1, #usr.alts do
        local ent = {id = usr.alts[j]}
        tinsert (ksk.sortedusers, i+j, ent)
      end
    end
  end

  for k,v in ipairs(ksk.sortedusers) do
    if (v.id == olduser) then
      oldidx = k
    end
  end

  ksk.qf.userlist.itemcount = ksk.cfg.nusers
  ksk.qf.userlist:UpdateList ()

  ksk.qf.userlist:SetSelected (oldidx)
  changed (true, true)
  ksk:RefreshCSData ()
end

function ksk:FindUser (name, cfgid)
  if (not ksk.configs or ksk.frdb.tempcfg) then
    return nil
  end

  assert (name)

  cfgid = cfgid or ksk.currentid
  name = strlower (name)

  for k,v in pairs(ksk.configs[cfgid].users) do
    if (strlower (v.name) == name) then
      return k
    end
  end
  return nil
end

function ksk:GetUserFlags (userid, cfgid)
  cfgid = cfgid or ksk.currentid
  if (not cfgid or cfgid == "" or not userid or userid == "") then
    return
  end
  if (not ksk.configs[cfgid]) then
    return
  else
    if (not ksk.configs[cfgid].users[userid]) then
      return
    end
  end
  return ksk.configs[cfgid].users[userid].flags or ""
end

local function find_flag (userid, flags, flag, cfgid)
  local fs = flags or ksk:GetUserFlags (userid, cfgid)
  if (not fs) then
    return false
  end
  if (string.find (fs, flag) ~= nil) then
    return true
  end
  return false
end

local function set_flag (userid, flag, onoff, cfgid, arg, nocmd)
  cfgid = cfgid or ksk.currentid
  local user = ksk.frdb.configs[cfgid].users[userid]
  if (not nocmd) then
    local es = strfmt ("%s:%s:%s:%s", userid, flag, onoff and "Y" or "N",
      arg and tostring(arg) or "")
    ksk.AddEvent (cfgid, "CHUSR", es, true)
  end

  if (onoff) then
    if (not user.flags) then
      user.flags = ""
    end
    if (string.find(user.flags, flag)) then
      return true
    end
    user.flags = user.flags .. flag
    return true
  else
    if (string.find(user.flags or "", flag)) then
      local nf = string.gsub(user.flags, flag, "")
      user.flags = nf
    end
    return true
  end
end

function ksk:UserIsEnchanter (userid, flags, cfg)
  return find_flag (userid, flags, "E", cfg)
end

function ksk:UserIsFrozen (userid, flags, cfg)
  return find_flag (userid, flags, "F", cfg)
end

function ksk:UserIsCoadmin (userid, cfgid)
  cfgid = cfgid or ksk.currentid
  if (ksk.configs[cfgid].admins[userid] or ksk.configs[cfgid].owner == userid) then
    return true
  end
  return false
end

function ksk:UserIsAlt (userid, flags, cfg)
  cfg = cfg or ksk.currentid
  local rv = find_flag (userid, flags, "A", cfg)
  if (rv == true) then
    local mid, ts, ts2, ts3
    mid = ksk.frdb.configs[cfg].users[userid].main
    if (ksk.frdb.configs[cfg].users[mid]) then
      ts = class(ksk.frdb.configs[cfg].users[mid])
      ts2 = aclass(ksk.frdb.configs[cfg].users[mid])
      ts3 = ksk.frdb.configs[cfg].users[mid].name
    end
    return rv, mid, ts, ts2, ts3
  end
  return rv, nil, nil, nil, nil
end

function ksk:UserRole (userid, cfg)
  cfg = cfg or ksk.currentid
  return ksk.configs[cfg].users[userid].role or 0
end

function ksk:SetUserEnchanter (userid, onoff, cfg, nocmd)
  cfg = cfg or ksk.currentid
  set_flag (userid, "E", onoff, cfg, nil, nocmd)
  --
  -- If this user is no longer an enchanter, check the config to see if they
  -- are assigned as one of the target enchanters for loot distribution. If
  -- they are we need to remove them.
  --
  if (not onoff) then
    local doit = false
    for i = 1,6 do
      if (ksk.configs[cfg].settings.denchers[i] == userid) then
        ksk.configs[cfg].settings.denchers[i] = nil
        doit = true
      end
    end
    if (doit) then
      ksk:UpdateAllConfigSettings ()
    end
  end
end

function ksk:SetUserFrozen (userid, onoff, cfg, nocmd)
  return set_flag (userid, "F", onoff, cfg, nil, nocmd)
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
function ksk:SetUserIsAlt (userid, onoff, main, cfg, nocmd)
  cfg = cfg or ksk.currentid
  if (not main or main == "") then
    onoff = false
  end
  set_flag (userid, "A", onoff, cfg, main, nocmd)
  if (ksk.memberid == userid) then
    ksk.memberid = nil
  end
  if (ksk.lootmemberid == userid) then
    ksk.lootmemberid = nil
  end
  local usr = ksk.frdb.configs[cfg].users[userid]
  if (onoff) then
    if (usr.main) then
      --
      -- We were previous assigned as an alt of another main. We need to
      -- remove this userid from that old main's list of alts. If that
      -- will leave the old main with no alts, set their alts entry to nil.
      --
      local oldm = ksk.frdb.configs[cfg].users[usr.main]
      for k,v in pairs (oldm.alts) do
        if (v == userid) then
          tremove (oldm.alts, k)
          break
        end
      end
      if (not next (oldm.alts)) then
        oldm.alts = nil
      end
    end

    --
    -- Now add this user to the new main's list of alts if we are not already
    -- in the list (which we never should be).
    --
    local musr = ksk.frdb.configs[cfg].users[main]
    local found = false
    usr.main = main
    if (not musr.alts) then
      musr.alts = {}
    end
    for k,v in pairs (musr.alts) do
      if (v == userid) then
        found = true
        break
      end
    end
    if (not found) then
      tinsert (musr.alts, userid)
      tsort (musr.alts, function (a,b)
        return ksk.frdb.configs[cfg].users[a].name < ksk.frdb.configs[cfg].users[b].name
      end)
    end
    ksk:FixupLists (cfg)
  else
    if (usr.main) then
      local musr = ksk.frdb.configs[cfg].users[usr.main]
      for k,v in ipairs(musr.alts) do
        if (v == userid) then
          tremove (musr.alts, k)
          break
        end
      end
      if (not next(musr.alts)) then
        musr.alts = nil
      end
    end
    usr.main = nil
  end

  ksk:RefreshUsers ()
  ksk:RefreshLists ()
  return true
end

function ksk:SetUserRole (userid, value, cfg, nocmd)
  cfg = cfg or ksk.currentid
  if (not nocmd) then
    local es = strfmt ("%s:R:Y:%s", userid, tostring (value))
    ksk.AddEvent (cfg, "CHUSR", es, true)
  end
  ksk.configs[cfg].users[userid].role = value
end

function ksk:GetNextUID (cfgid)
  cfgid = cfgid or ksk.currentid
  local myuid = ksk.csdata[cfgid].myuid
  assert (myuid, "I was not found in the user lists.")

  local ia, am = ksk:IsAdmin (myuid, cfgid)
  assert (ia ~= nil, "I am not an admin")

  if (ksk.configs[cfgid].nusers == 4094) then
    error ("Terribly sorry but KonferSK has a limit of 4094 users :(", 2)
    return nil
  end

  for i = 1, 4094 do
    local is = strfmt ("%s%03x", ksk.configs[cfgid].admins[am].id, i)
    if (not ksk.configs[cfgid].users[is]) then
      return is
    end
  end

  assert (false, "Logic error!")
end

function ksk:CreateNewUser (name, cls, cfgid, norefresh, bypass, myid, nocmd)
  assert (name, "CreateNewUser: no name!")
  assert (cls, "CreateNewUser: no class!")
  assert (K.IndexClass[cls], "CreateUser: invalid class " .. strfmt("%q", tostring(cls)))

  cfgid = cfgid or ksk.currentid
  name = K.CanonicalName (name, nil)

  if (not bypass and ksk:CheckPerm (cfgid)) then
    return nil
  end

  local uid = ksk:FindUser (name, cfgid)
  if (uid and not nocmd) then
    err (L["user %q already exists. Try again."], aclass (ksk.frdb.configs[cfgid].users[uid]))
    return nil
  end

  uid = myid or ksk:GetNextUID (cfgid)
  if (not uid) then
    return
  end
  ksk.configs[cfgid].nusers = ksk.configs[cfgid].nusers + 1
  ksk.configs[cfgid].users[uid] = {
    name = name,
    class = cls,
    role = 0,
    flags = ""
  }
  if (ksk.initialised and not nocmd) then
    info (L["user %q created."], aclass (name, cls))
  end
  if (name == K.player.player) then
    ksk.csdata[cfgid].myuid = uid
    ksk.csdata[cfgid].isadmin = nil
  end
  if (not norefresh) then
    ksk:RefreshUsers ()
  end

  --
  -- If the config we are adding this user to is the current config, and we
  -- are in a raid, we need to scan the list of missing members to see if
  -- this user was in that list, and if so, remove them from it.
  --
  if (ksk.inraid and cfgid == ksk.currentid) then
    local olduid = "0fff:" .. cls .. ":" .. name
    if (ksk.missing[olduid]) then
      ksk.nmissing = ksk.nmissing - 1
      ksk.missing[olduid] = nil
      ksk.qf.userbuttons.addmissing:SetEnabled(ksk.csd.isadmin ~= nil and ksk.nmissing > 0)
      if (not norefreh) then
        ksk:RefreshRaid (false)
      end
    end
  end

  if (not nocmd) then
    local es = strfmt ("%s:%s:%s:%s", uid, name, cls, norefresh and "Y" or "N")
    ksk.AddEvent (cfgid, "MKUSR", es, true)
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
function ksk:DeleteUser (uid, cfgid, alts, nocmd)
  local cfg = cfgid or ksk.currentid
  local lcp = ksk.frdb.configs[cfgid]
  local refreshitems = false
  local refreshhistory = false

  local function each_delete (userid, cfg)
    if (not lcp.users[userid]) then
      return
    end

    if (not nocmd) then
      info (L["user %q deleted."], aclass (lcp.users[userid]))
    end
    for i = 1,6 do
      if (lcp.settings.denchers[i] == userid) then
        lcp.settings.denchers[i] = nil
      end
    end

    --
    -- If the user was destined to receive the next drop of an item, remove
    -- that particular option from the item option table.
    --
    for lk,lv in pairs (lcp.items) do
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
    for lk,lv in pairs (lcp.lists) do
      ksk:DeleteMember (userid, lk, cfg, true)
    end

    local isalt = ksk:UserIsAlt (userid, nil, cfg)
    if (isalt) then
      local main = lcp.users[userid].main
      if (main and lcp.users[main]) then
        ksk:SetUserIsAlt (userid, false, nil, cfg, true)
      end
    end

    --
    -- If the user had receieved items and is in the item history
    -- database, we need to convert the userid portion of the string
    -- into the user name and class, so that it can still be
    -- displayed correctly.
    --
    local nwhostr = lcp.users[userid].name .. "/" .. lcp.users[userid].class
    for k,v in pairs (lcp.history) do
      local when,what,who,how = strsplit ("\7", v)
      if (who == userid) then
        who = nwhostr
        lcp.history[k] = strfmt ("%s\7%s\7%s\7%s", when, what, who, how)
        refreshhistory = true
      end
    end

    if (lcp.admins[userid]) then
      ksk:DeleteAdmin (userid, cfg)
    end

    if (cfg == ksk.currentid and userid == seluser) then
      seluser = nil
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
        each_delete (v, cfg)
      else
        ksk:SetUserIsAlt (v, false, nil, cfg, true)
      end
    end
  end

  each_delete (uid, cfg)

  if (not nocmd) then
    local es = strfmt ("%s:%s", uid, alts and "Y" or "N")
    ksk.AddEvent (cfg, "RMUSR", es, true)
  end

  if (not ksk.initialised) then
    return
  end

  ksk:RefreshUsers ()
  ksk:RefreshLists ()
  ksk:RefreshCoadmins ()
  ksk:UpdateAllConfigSettings ()
  if (refreshitems) then
    ksk:RefreshItemList ()
  end
  if (refreshhistory) then
    ksk:RefreshHistory ()
  end
  if (ksk.inraid) then
    ksk:RefreshRaid ()
  end
end

local function confirm_delete_user (arg, alts)
  local uid = arg.uid
  local cfg = arg.cfg or ksk.currentid

  ksk:DeleteUser (uid, cfg, alts, false)
end

function ksk:DeleteUserCmd (userid, show, cfg)
  cfg = cfg or ksk.currentid

  if (ksk.configs[cfg].owner == userid) then
    err (L["cannot delete user %q as they are the owner of the configuration."],
      aclass (ksk.configs[cfg].users[userid]))
    return true
  end

  local isshown = show or ksk.mainwin:IsShown ()
  ksk.mainwin:Hide ()

  local alts = nil
  if (ksk.configs[cfg].users[userid].alts) then
    alts = L["Delete All Alts of User"]
  end
  ksk:ConfirmationDialog (L["Delete User"], L["DELUSER"],
    ksk.configs[cfg].users[userid].name, confirm_delete_user,
    { uid=userid, cfg=cfg }, isshown, 210, alts)

  return false
end

function ksk:RenameUser (userid, newname, cfg, nocmd)
  cfg = cfg or ksk.currentid

  local oldname = ksk.configs[cfg].users[userid].name
  local cl = ksk.configs[cfg].users[userid].class
  newname = K.CanonicalName (newname, nil)
  if (not nocmd) then
    info (L["NOTICE: user %q renamed to %q."], aclass (oldname, cl),
      aclass (newname, cl))
  end
  ksk.configs[cfg].users[userid].name = newname

  --
  -- If this user is an alt, we will need to re-sort the main's alt
  -- list so it remains alphabetical.
  --
  local isalt, main = ksk:UserIsAlt (userid, nil, cfg)
  if (isalt) then
    local musr = ksk.configs[cfg].users[main]
    tsort (musr.alts, function (a,b)
      return ksk.configs[cfg].users[a].name < ksk.configs[cfg].users[b].name
    end)
  end

  if (not nocmd) then
    local es = strfmt ("%s:%s", userid, newname)
    ksk.AddEvent (cfg, "MVUSR", es, true)
  end

  ksk:RefreshUsers ()
  ksk:RefreshLists ()
  ksk:UpdateAllConfigSettings ()

  return false
end

--
-- Reserve a user in the roll lists. This data is not stored permanently.
-- We keep one list for each config space, and we do not delete the list
-- when config spaces are switched, only if they are deleted.
--

function ksk:ReserveUser (uid, onoff, cfgid, nocmd)
  cfgid = cfgid or ksk.currentid
  local rd = ksk.csdata[cfgid]

  if (not rd.reserved) then
    rd.reserved = {}
  end

  if (onoff) then
    rd.reserved[uid] = true
  else
    rd.reserved[uid] = nil
  end

  if (not nocmd) then
    ksk.SendRaidAM ("RSUSR", "ALERT", uid, onoff)
  end

  ksk:RefreshMemberList ()
end

function ksk:UserIsReserved (uid, cfgid)
  cfgid = cfgid or ksk.currentid

  local rd = ksk.csdata[cfgid]
  if (not rd.reserved or not rd.reserved[uid]) then
    return false
  end
  return rd.reserved[uid]
end

function ksk:RefreshMembership ()
  if (not ksk.qf.umemlist) then
    return
  end

  if (seluser) then
    local uid = seluser
    if (ksk.cfg.tethered) then
      local up = ksk.users[seluser]
      if (up.main) then
        uid = up.main
      end
    end
    umemlist = {}
    if (ksk.sortedlists and #ksk.sortedlists > 0) then
      for k,v in ipairs (ksk.sortedlists) do
        local il, lp = ksk:UserInList (uid, v.id)
        if (il) then
          tinsert (umemlist, green (strfmt ("%s [%d]", ksk.lists[v.id].name, lp)))
        else
          tinsert (umemlist, red (ksk.lists[v.id].name))
        end
      end
    end
    ksk.qf.umemlist.itemcount = #umemlist
  else
    umemlist = nil
    ksk.qf.umemlist.itemcount = 0
  end
  ksk.qf.umemlist:UpdateList ()
end
