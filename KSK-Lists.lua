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
local H = LibStub:GetLibrary("KKoreHash")
local DB = LibStub:GetLibrary("KKoreDB")
local KUIBase = LibStub:GetLibrary("KKoreUI")

if (not K) then
  error ("KahLua KonferSK: could not find KahLua Kore.", 2)
end

if (not H) then
  error ("KahLua KonferSK: could not find KahLua Kore Hash library.", 2)
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
local strgsub = string.gsub
local strlen = string.len
local strfind = string.find
local strsplit = string.split
local xpcall, pcall = xpcall, pcall
local pairs, next, type = pairs, next, type
local select, assert, loadstring = select, assert, loadstring
local strlower = string.lower
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

local initdone = false
local members
local linfo = {}

--
-- This file contains all of the UI handling code for the lists panel,
-- as well as all list manipulation functions.
--
local function changed (res)
  res = res or false
  if (not ksk.listid) then
    res = true
  end
  if (ksk.qf.listupdbtn) then
    ksk.qf.listupdbtn:SetEnabled (not res)
  end
end

local function setup_linfo ()
  if (not ksk.list) then
    return
  end

  linfo = {}
  linfo.sortorder = ksk.list.sortorder
  linfo.def_rank = ksk.list.def_rank
  linfo.strictcfilter = ksk.list.strictcfilter
  linfo.strictrfilter = ksk.list.strictrfilter
  linfo.extralist = ksk.list.extralist
end

--
-- Handling the members list is a bit tricky if the configuration has
-- tethered alts. Without tethered alts, the display is a direct 1-1
-- mapping from the members list to what is displayed. However, if there
-- are tethered users, it is more useful to display the alts of the user
-- underneath their main, and have things like "Move Up" and "Move Down"
-- move all those users as a block. This is purely a visual thing, as in
-- the actual member list database there is only one entry, for the users
-- main character. The easiest way to deal with this is to do all manipulations
-- such as suiciding, moving users up and down etc on the raw members list
-- data, and then to create a for-display array that is refreshed from that
-- raw data each time a change is made.
--

local function rl_setenabled (onoff)
  if (not ksk.qf.listconf) then
    return
  end
  if (ksk.qf.listconf.sortorder) then
    ksk.qf.listconf.sortorder:SetEnabled (onoff)
  end
  if (ksk.qf.listconf.defrank) then
    ksk.qf.listconf.defrank:SetEnabled (onoff)
  end
  if (ksk.qf.listconf.cfilter) then
    ksk.qf.listconf.cfilter:SetEnabled (onoff)
  end
  if (ksk.qf.listconf.rfilter) then
    ksk.qf.listconf.rfilter:SetEnabled (onoff)
  end
  if (ksk.qf.listconf.slistdd) then
    ksk.qf.listconf.slistdd:SetEnabled (onoff)
  end
end

local function rlist_selectitem (objp, idx, slot, btn, onoff)
  if (ksk.popupwindow) then
    ksk.popupwindow:Hide ()
    ksk.popupwindow = nil
  end

  if (onoff) then
    rl_setenabled (true)
    ksk.listid = ksk.sortedlists[idx].id
    ksk.list = ksk.cfg.lists[ksk.listid]
    setup_linfo ()
    ksk:RefreshMemberList ()
    ksk.qf.listconf.sortorder:SetValue (ksk.list.sortorder)
    ksk.qf.listconf.defrank:SetValue (ksk.list.def_rank)
    ksk.qf.listconf.cfilter:SetChecked (ksk.list.strictcfilter)
    ksk.qf.listconf.rfilter:SetChecked (ksk.list.strictrfilter)
    ksk.qf.listconf.slistdd:SetValue (ksk.list.extralist)
  else
    rl_setenabled (false)
    ksk.listid = nil
    ksk.list = nil
  end

  changed(true)
end

local function mlist_newitem (objp, num)
  local bname = "KSKMListButton" .. tostring(num)
  local rf = MakeFrame ("Button", bname, objp.content)
  local nfn = "GameFontNormalSmallLeft"
  local htn = "Interface/QuestFrame/UI-QuestTitleHighlight"

  rf:SetWidth (165)
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
    local idx = this:GetID ()
    this:GetParent():GetParent():SetSelected (idx)
    ksk.qf.listmemsearch:SetText ("")
    ksk.qf.listmemsearch:ClearFocus ()
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
  if (ksk.cfg.tethered) then
    if (members[idx].isalt) then
      uc = members[idx].main
      at = "    - "
      bm = false
    else
      at = strfmt ("%d: ", members[idx].idx)
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
  if (ksk.popupwindow) then
    ksk.popupwindow:Hide ()
    ksk.popupwindow = nil
  end

  if (onoff) then
    ksk.memberid = members[idx].id
    ksk.member = ksk.members[ksk.memberid]
    ksk.userid = ksk.memberid
    local ridx = idx
    if (ksk.cfg.tethered) then
      ridx = members[idx].idx
      if (members[idx].isalt) then
        ksk.memberid = members[idx].main
      end
    end
    local ee = (ridx > 1 and ksk.csd.isadmin ~= nil)
    local ef = (ridx < #ksk.list.users and ksk.csd.isadmin ~= nil)
    ksk.qf.king:SetEnabled (ee)
    ksk.qf.moveup:SetEnabled (ee)
    ksk.qf.movedown:SetEnabled (ef)
    ksk.qf.suicide:SetEnabled (ef)
    if (ksk:UserIsReserved (ksk.memberid)) then
      ksk.qf.resunres:SetText (L["Unreserve"])
    else
      ksk.qf.resunres:SetText (L["Reserve"])
    end
    ksk.qf.resunres:SetEnabled (ksk.csd.isadmin ~= nil)
    ksk.qf.listbuttons.deletebutton:SetEnabled (ksk.csd.isadmin ~= nil)
  else
    ksk.memberid = nil
    ksk.member = nil
    if (initdone) then
      ksk.qf.king:SetEnabled (false)
      ksk.qf.moveup:SetEnabled (false)
      ksk.qf.movedown:SetEnabled (false)
      ksk.qf.suicide:SetEnabled (false)
      ksk.qf.resunres:SetEnabled (false)
      ksk.qf.listbuttons.deletebutton:SetEnabled (false)
    end
  end
end

local function create_list_button ()
  local box

  if (not ksk.newlistdlg) then
    ksk.newlistdlg, box = ksk:SingleStringInputDialog ("KSKSetupNewList",
      L["Create Roll List"], L["NEWLIST"], 400, 175)

    local function verify_with_create (objp, val)
      if (strlen (val) < 1) then
        err (L["invalid roll list name. Please try again."])
        objp:Show ()
        objp.ebox:SetFocus ()
        return true
      end
      ksk:CreateNewList (val)
      ksk.newlistdlg:Hide ()
      ksk.mainwin:Show ()
      return false
    end

    ksk.newlistdlg:Catch ("OnAccept", function (this, evt)
      local rv = verify_with_create (this:GetParent(), this.ebox:GetText ())
      return rv
    end)

    ksk.newlistdlg:Catch ("OnCancel", function (this, evt)
      ksk.newlistdlg:Hide ()
      ksk.mainwin:Show ()
      return false
    end)

    box:Catch ("OnEnterPressed", function (this, evt, val)
      local rv = verify_with_create (this:GetParent(), val)
      return rv
    end)
  else
    box = ksk.newlistdlg.ebox
  end

  box:SetText ("")
  ksk.mainwin:Hide ()
  ksk.newlistdlg:Show ()
  box:SetFocus ()
end

local function delete_list_button (lid)
  ksk:DeleteListCmd (lid)
end

local function rename_list_button (lid)
  if (ksk.popupwindow) then
    ksk.popupwindow:Hide ()
    ksk.popupwindow = nil
  end

  local function rename_helper (newname, old)
    local found = false
    local lname = strlower (newname)

    for k,v in pairs (ksk.lists) do
      if (strlower(ksk.lists[k].name) == lname) then
        found = true
      end
    end

    if (found) then
      err (L["roll list %q already exists. Try again."], white (newname))
      return true
    end

    local rv = ksk:RenameList (old, newname)
    if (rv) then
      return true
    end

    return false
  end

  ksk:RenameDialog (L["Rename Roll List"], L["Old Name"],
    ksk.lists[lid].name, L["New Name"], 32, rename_helper,
    lid, true)

  ksk.mainwin:Hide ()
  ksk.renamedlg:Show ()
  ksk.renamedlg.input:SetText ("")
  ksk.renamedlg.input:SetFocus ()
end

local function copy_list_button (lid)
  if (ksk.popupwindow) then
    ksk.popupwindow:Hide ()
    ksk.popupwindow = nil
  end

  local function copy_helper (newname, old)
    local found = false
    local lname = strlower (newname)

    for k,v in pairs (ksk.lists) do
      if (strlower(ksk.lists[k].name) == lname) then
        found = true
      end
    end

    if (found) then
      err (L["roll list %q already exists. Try again."], white (newname))
      return true
    end

    local rv = ksk:CopyList (old, newname)
    if (rv) then
      return true
    end

    return false
  end

  ksk:RenameDialog (L["Copy Roll List"], L["Source List"],
    ksk.lists[lid].name, L["Destination List"], 32, copy_helper,
    lid, true)

  ksk.mainwin:Hide ()
  ksk.renamedlg:Show ()
  ksk.renamedlg.input:SetText ("")
  ksk.renamedlg.input:SetFocus ()
end

local insert_popup
local random_insert = false

local function insert_member (btn)
  local ulist = {}
  local pdef = nil

  if (ksk.popupwindow) then
    ksk.popupwindow:Hide ()
    ksk.popupwindow = nil
  end

  for k,v in pairs (ksk.users) do
    if (not ksk:UserInList (k)) then
      local doit = false
      local ti = nil
      if (ksk.cfg.tethered) then
        if (not ksk:UserIsAlt (k, v.flags)) then
          doit = true
        end
      else
        doit = true
      end
      if (doit) then
        ti = { value = k, text = class (v.name, v.class), }
        tinsert (ulist, ti)
      end
    end
  end

  tsort (ulist, function (a,b)
    return strlower (ksk.users[a.value].name) < strlower (ksk.users[b.value].name)
  end)

  if (ksk.cfg.tethered) then
    for i = #ulist, 1, -1 do
      if (ksk.users[ulist[i].value].alts) then
        for k,v in pairs (ksk.users[ulist[i].value].alts) do
          local usr = ksk.users[v]
          local ti = { value = ulist[i].value, text = "  - "..class (usr) }
          tinsert (ulist, i+1, ti)
        end
      end
    end
  end

  local function pop_func (puid)
    if (ksk.cfg.tethered) then
      if (ksk:UserIsAlt (puid)) then
        id = ksk.users[puid].main
      end
    end

    ksk.popupwindow:Hide ()
    ksk.popupwindow = nil

    --
    -- If we've been asked to insert this at a random position, pick the
    -- position now. Otherwise, just insert at the bottom.
    --
    local rlist = ksk.lists[ksk.listid]
    local pos = rlist.nusers + 1
    if (random_insert) then
      pos = math.random (pos)
    end
    ksk:InsertMember (puid, ksk.listid, pos)
    info (L["added %s to list %q at position %s."], aclass (ksk.users[puid]),
      white(rlist.name), white(tostring(pos)))
  end

  if (not insert_popup) then
    insert_popup = ksk:PopupSelectionList ("KSKInsertMemberPopup",
      ulist, nil, 205, 300, ksk.mainwin.tabs[ksk.LISTS_TAB].content, 16,
      pop_func, 20, 20)
    local arg = {
      x = 0, y = 2, width = 150, parent = insert_popup.header,
      initialvalue = false, label = { text = L["Insert Randomly"] },
    }
    insert_popup.randpos = KUI:CreateCheckBox (arg, insert_popup.header)
    insert_popup.randpos.toplevel = insert_popup
    insert_popup.randpos:HookScript ("OnEnter", function (this)
      this.toplevel:StopTimeoutCounter ()
    end)
    insert_popup.randpos:HookScript ("OnLeave", function (this)
      this.toplevel:StartTimeoutCounter ()
    end)
    insert_popup.randpos:SetFrameLevel (insert_popup.header:GetFrameLevel () + 1)
    insert_popup.randpos:Catch ("OnValueChanged", function (this, evt, val)
      random_insert = val
    end)

    arg = {
      x = 0, y = 2, len = 16, font = "ChatFontSmall", width = 170,
      tooltip = { title = L["User Search"], text = L["TIP099"] },
      parent = insert_popup.footer,
    }
    insert_popup.usearch = KUI:CreateEditBox (arg, insert_popup.footer)
    insert_popup.usearch.toplevel = insert_popup
    ksk.qf.inssearch = insert_popup.usearch
    insert_popup.usearch:Catch ("OnEnterPressed", function (this)
      this:SetText ("")
    end)
    insert_popup.usearch:HookScript ("OnEnter", function (this)
      this.toplevel:StopTimeoutCounter ()
    end)
    insert_popup.usearch:HookScript ("OnLeave", function (this)
      this.toplevel:StartTimeoutCounter ()
    end)
    insert_popup.usearch:Catch ("OnValueChanged", function (this, evt, newv, user)
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
    insert_popup:UpdateList (ulist)
  end
  insert_popup:ClearAllPoints ()
  insert_popup:SetPoint ("TOPLEFT", btn, "TOPRIGHT", 0, 0)
  insert_popup:Show ()
  ksk.popupwindow = insert_popup
end

local function move_member (btn, dir)
  if (ksk.popupwindow) then
    ksk.popupwindow:Hide ()
    ksk.popupwindow = nil
  end

  local c = ksk.qf.memberlist:GetSelected ()
  if (not c) then
    return
  end
  local uid = members[c].id
  if (ksk.cfg.tethered and members[c].isalt) then
    uid = members[c].main
  end

  --
  -- We need to check if the "direction" is suicide, and if we are in a
  -- raid, issue a propper suicide command. This is because 99 times out
  -- of a hundred, when you manually adjust a member while in a raid it
  -- is to deal with a miss-loot of an item, and the user would have been
  -- suicided normally if there was no mistake. Doing repairs to the list
  -- outside of the raid, however, we can assume that pressing suicide
  -- wants to send the user to the extreme bottom of the list, and we use
  -- the MoveMember function.
  --
  if (dir == 0 and ksk.inraid) then
    local sulist = ksk:CreateRaidList (ksk.listid)
    ksk:SuicideUser (ksk.listid, sulist, uid, ksk.currentid)
  else
    local es = strfmt ("%s:%s:%d", uid, ksk.listid, dir)
    ksk.AddEvent (ksk.currentid, "MMLST", es, true)
    ksk:MoveMember (uid, ksk.listid, dir, ksk.currentid)
  end
end

local function resunres_member (btn)
  if (ksk.popupwindow) then
    ksk.popupwindow:Hide ()
    ksk.popupwindow = nil
  end

  local ir = ksk:UserIsReserved (ksk.memberid) or false
  ksk:ReserveUser (ksk.memberid, not ir)
end

local function delete_member (btn)
  if (ksk.popupwindow) then
    ksk.popupwindow:Hide ()
    ksk.popupwindow = nil
  end

  local c = ksk.qf.memberlist:GetSelected ()
  local uid = members[c].id
  if (ksk.cfg.tethered and members[c].isalt) then
    uid = members[c].main
  end
  ksk:DeleteMember (uid, ksk.listid, ksk.currentid)
end

local function import_list_button ()
  local osklist = ""
  local insrand = true
  local imprank = ""
  local csvstr = ""
  local csvopt = 1

  if (not ksk.implistdlg) then
    local ypos = 0
    local arg = {
      x = "CENTER", y = "MIDDLE",
      name = "KSKImportListDialog",
      title = L["Import List Members"],
      border = true,
      width = 400,
      height = 280,
      canmove = true,
      canresize = false,
      escclose = true,
      okbutton = { text = K.ACCEPTSTR },
      cancelbutton = { text = K.CANCELSTR },
    }
    local ret = KUI:CreateDialogFrame (arg)
    arg = {}

    arg = {
      x = "CENTER", y = ypos, width = 200, border = true, autosize = false,
      justifyh = "CENTER",
    }
    ret.curlist = KUI:CreateStringLabel (arg, ret)
    ypos = ypos - 32

    arg = {
      x = 0, y = ypos, dwidth = 175, mode = "SINGLE", itemheight = 16,
      items = KUI.emptydropdown, name = "KSKListImpRanks",
      label = { text = L["Guild Rank to Import"], pos = "LEFT" },
    }
    ret.grank = KUI:CreateDropDown (arg, ret)
    ret.grank:Catch ("OnValueChanged", function (this, evt, newv)
      ksk.implistdlg.insrand:SetEnabled (newv ~= "")
      ksk.implistdlg.csvimp:SetEnabled (newv == "")
      imprank = newv
    end)
    ypos = ypos - 24
    arg = {}

    arg = {
      x = 20, y = ypos, checked = true,
      label = { text = L["Insert Randomly"] },
    }
    ret.insrand = KUI:CreateCheckBox (arg, ret)
    ret.insrand:Catch ("OnValueChanged", function (this, evt, val)
      insrand = val
    end)
    arg = {}
    ypos = ypos - 24

    arg = {
      x = 0, y = ypos, len = 9999,
      label = { text = L["CSV Import"], pos = "LEFT" },
    }
    ret.csvimp = KUI:CreateEditBox (arg, ret)
    ret.csvimp:Catch ("OnValueChanged", function (this, evt, newv)
      ksk.implistdlg.grank:SetEnabled (newv == "" and K.player.isguilded)
      ksk.implistdlg.insrand:SetEnabled (newv == "" and imprank ~= "" and K.player.isguilded)
      ksk.implistdlg.csvopts:SetEnabled (newv ~= "" and imprank == "")
      csvstr = newv
    end)
    ypos = ypos - 30
    arg = {}

    arg = {
      x = 16, y = ypos, dwidth = 250, mode = "SINGLE", items = {
        { text = L["Set List to Imported Values"], value = 1 },
        { text = L["Add to Existing Members"], value = 2 },
        { text = L["Randomly Add to Existing Members"], value = 3 },
      }, name = "KSKCSVImpOpts", enabled = false, initialvalue = 1,
      itemheight = 16,
    }
    ret.csvopts = KUI:CreateDropDown (arg, ret)
    ret.csvopts:Catch ("OnValueChanged", function (this, evt, newv)
      csvopt = newv
    end)

    ret.OnAccept = function (this)
      if (imprank ~= "") then
        -- Import a guild rank (possibly randomly)
        local oldoff = GetGuildRosterShowOffline ()
        SetGuildRosterShowOffline (true)
        GuildRoster()
        SortGuildRoster ("rank")
        local rusers = {}
        local nrank = 0
        local ngm = GetNumGuildMembers ()
        for i = 1,ngm do
          local nm, _, ri, lvl, _, _, _, _, _, _, cl = GetGuildRosterInfo (i)
          if (ri == imprank-1) then
            local uid = ksk:FindUser (nm)
            if (not uid) then
              uid = ksk:CreateNewUser (nm, K.ClassIndex[cl], nil, false, true)
            end
            tinsert (rusers, uid)
            nrank = nrank + 1
          end
        end
        SetGuildRosterShowOffline (oldoff)

        for k,v in pairs (rusers) do
          local pos = nil
          if (not ksk:UserInList (v)) then
            if (insrand) then
              pos = math.random (ksk.list.nusers + 1)
            end
            ksk:InsertMember (v, ksk.listid, pos)
          end
        end
        ksk:RefreshLists ()
      elseif (csvstr ~= "") then
        --
        -- Import from a CSV string. First thing we do is remove any spaces,
        -- and then split the string on the comma delimiter. We then have
        -- to search the user list for each user, to ensure the string is
        -- valid. If any user is missing, report it and bail.
        --
        local wstr = strgsub (csvstr, " ", "")
        local utbl = { strsplit (",", wstr) }
        local musr = {}
        local ilist = {}
        for k,v in pairs (utbl) do
          v = K.CapitaliseName (v)
          local uid = ksk:FindUser (v)
          if (not uid) then
            tinsert (musr, v)
          else
            tinsert (ilist, uid)
          end
        end
        if (#musr > 0) then
          err (L["The following users are missing from the user list: %s"], tconcat (musr, ", "))
          err (L["Import from the CSV string cannot continue until these users are added."])
          return
        end
        if (csvopt == 1) then
          ksk:SetMemberList (tconcat (ilist, ""))
        else
          for k,v in pairs (ilist) do
            local pos = nil
            if (not ksk:UserInList (v)) then
              if (csvopt == 3) then
                pos = math.random (ksk.list.nusers + 1)
              end
              ksk:InsertMember (v, ksk.listid, pos)
            end
          end
        end
      end
      ksk.implistdlg:Hide ()
      ksk:FullRefresh (true)
      ksk.mainwin:Show ()
    end

    ret.OnCancel = function (this)
      ksk.implistdlg:Hide ()
      ksk.mainwin:Show ()
    end

    ksk.implistdlg = ret
  end

  local ild = ksk.implistdlg

  local gitems = {}
  tinsert (gitems, { text = L["None"], value = "" })
  if (K.player.isguilded) then
    ild.grank:SetEnabled (true)
    for i = 1, K.guild.numranks do
      local iv = { text = K.guild.ranks[i].name, value = i }
      tinsert (gitems, iv)
    end
  else
    ild.grank:SetEnabled (false)
    ild.insrand:SetEnabled (false)
  end
  ild.grank:UpdateItems (gitems)
  ild.grank:SetValue ("")

  ksk.mainwin:Hide ()
  ild.csvimp:SetText ("")
  ksk.implistdlg.curlist:SetText (ksk.lists[ksk.listid].name)
  ksk.implistdlg:Show ()
end

local function export_list_button ()
  local what = 0
  local thestring = ""
  local lststring = ""
  local uu = {}
  local uv = {}

  if (not ksk.explistdlg) then
    local ypos = 0
    local arg = {
      x = "CENTER", y = "MIDDLE",
      name = "KSKExportListDialog",
      title = L["Export List Members"],
      border = true,
      width = 400,
      height = 175,
      canmove = true,
      canresize = false,
      escclose = true,
      okbutton = { text = K.ACCEPTSTR },
      cancelbutton = { text = K.CANCELSTR },
    }
    local ret = KUI:CreateDialogFrame (arg)

    arg = {
      x = 0, y = ypos, width = 300, font = "GameFontNormal",
      text = "",
    }
    ret.clistmsg = KUI:CreateStringLabel (arg, ret)
    ypos = ypos - 24

    arg = {
      label = { text = L["Select"], pos = "LEFT" },
      name = "KSKWhatToExport", mode = "SINGLE",
      x = 0, y = ypos, dwidth = 250, items = {
        { text = L["Nothing"], value = 0 },
        { text = L["Export current list as CSV"], value = 1 },
        { text = L["Export current list as XML"], value = 2 },
        { text = L["Export current list as BBcode"], value = 3 },
        { text = L["Export all lists as XML"], value = 4 },
        { text = L["Export all lists as BBcode"], value = 5 },
      }, initialvalue = 0, itemheight = 16,
    }
    ret.what = KUI:CreateDropDown (arg, ret)
    ret.what:Catch ("OnValueChanged", function (this, evt, newv)
      what = newv
      local function do_xml_list (listid)
        lststring = lststring .. strfmt ("<list id=%q n=%q>", listid, ksk.lists[listid].name)
        local ll = ksk.lists[listid]
        local lul = {}
        for k,v in ipairs (ll.users) do
          local up=ksk.users[v]
          if (not uu[v]) then
            uu[v] = true
            tinsert (uv, strfmt ("<u id=%q n=%q c=%q/>", v, up.name, up.class))
          end
          tinsert (lul, strfmt ("<u id=%q/>", tostring(v)))
        end
        lststring = lststring .. tconcat (lul, "") .. "</list>"
      end

      local function do_bbcode_list (listid)
        lststring = lststring .. strfmt ("[center][b]List: %q[/b][/center]\n[list]", ksk.lists[listid].name)
        local ll = ksk.lists[listid]
        local lul = {}
        for k,v in ipairs (ll.users) do
          local up=ksk.users[v]
          tinsert (lul, strfmt ("[*][color=#%s]%s[/color]\n", K.ClassColorsHex[up.class], up.name))
        end
        lststring = lststring .. tconcat (lul, "") .. "[/list]\n"
      end

      local function final_xml_string ()
        local _, mo, dy, yr = CalendarGetDate ()
        local hh, mm = GetGameTime ()
        local dstr = strfmt ("%04d-%02d-%02d", yr, mo, dy)
        local tstr = strfmt ("%02d:%02d", hh, mm)
        local cs = ""
        for k,v in pairs (K.IndexClass) do
          if (v.u) then
            cs = cs .. strfmt ("<c id=%q v=%q/>", tostring (k), strlower (tostring(v.u)))
          end
        end
        thestring = strfmt ("<ksk date=%q time=%q><classes>%s</classes><users>%s</users><lists>%s</lists></ksk>", dstr, tstr, cs, tconcat (uv, ""), lststring)
      end

      local function final_bbcode_string ()
        local _, mo, dy, yr = CalendarGetDate ()
        local hh, mm = GetGameTime ()
        local dstr = strfmt ("%04d-%02d-%02d", yr, mo, dy)
        local tstr = strfmt ("%02d:%02d", hh, mm)
        thestring = strfmt ("[center][b]KSK Lists as of %s %s[/b][/center]\n", dstr, tstr) .. lststring
      end

      if (what == 1 and ksk.listid) then
        local tt = {}
        for k,v in ipairs (ksk.list.users) do
          tinsert (tt, ksk.users[v].name)
        end
        thestring = tconcat (tt, ",")
      elseif (what == 2 and ksk.listid) then
        uu = {}
        uv = {}
        lststring = ""
        do_xml_list (ksk.listid)
        final_xml_string ()
        lststring = ""
      elseif (what == 3 and ksk.listid) then
        uu = {}
        uv = {}
        lststring = ""
        do_bbcode_list (ksk.listid)
        final_bbcode_string ()
        lststring = ""
      elseif (what == 4) then
        uu = {}
        uv = {}
        lststring = ""
        for k,v in ipairs (ksk.sortedlists) do
          do_xml_list (v.id)
        end
        final_xml_string ()
      elseif (what == 5) then
        uu = {}
        uv = {}
        lststring = ""
        for k,v in ipairs (ksk.sortedlists) do
          do_bbcode_list (v.id)
        end
        final_bbcode_string ()
      else
        thestring = ""
      end
      ksk.explistdlg.expstr:SetText (thestring)
    end)
    ypos = ypos - 32

    arg = {
      x = 0, y = ypos, len = 99999,
      label = { text = L["Export string"], pos = "LEFT" },
    }
    ret.expstr = KUI:CreateEditBox (arg, ret)
    ret.expstr:Catch ("OnValueChanged", function (this, evt, newv, user)
      this:HighlightText ()
      this:SetCursorPosition (0)
      if (newv ~= "") then
        this:SetFocus ()
        ksk.explistdlg.copymsg:Show ()
      else
        this:ClearFocus ()
        ksk.explistdlg.copymsg:Hide ()
      end
    end)
    ypos = ypos - 24

    arg = {
      x = 16, y = ypos, width = 300,
      text = L["Press Ctrl+C to copy the export string"],
    }
    ret.copymsg = KUI:CreateStringLabel (arg, ret)
    ypos = ypos - 24

    ret.OnAccept = function (this)
      ksk.explistdlg:Hide ()
      ksk.mainwin:Show ()
    end

    ret.OnCancel = function (this)
      ksk.explistdlg:Hide ()
      ksk.mainwin:Show ()
    end

    ksk.explistdlg = ret
  end

  what = 0
  ksk.explistdlg.what:SetValue (what)
  ksk.explistdlg.expstr:SetText ("")
  ksk.explistdlg.clistmsg:SetText (strfmt (L["Current list: %s"], white(ksk.list.name)))

  ksk.mainwin:Hide ()
  ksk.explistdlg:Show ()
end

local function add_missing_button ()
  local insrandom
  local what

  if (not ksk.addmissingdlg) then
    local ypos = 0
    local arg = {
      x = "CENTER", y = "MIDDLE",
      name = "KSKAddMissingDialog",
      title = L["Add Missing Members"],
      border = true,
      width = 400,
      height = 175,
      canmove = true,
      canresize = false,
      escclose = true,
      okbutton = { text = K.ACCEPTSTR },
      cancelbutton = { text = K.CANCELSTR },
    }
    local ret = KUI:CreateDialogFrame (arg)
    arg = {}

    arg = {
      x = 0, y = ypos, width = 300, font = "GameFontNormal",
      text = "",
    }
    ret.clistmsg = KUI:CreateStringLabel (arg, ret)
    arg = {}
    ypos = ypos - 24

    arg = {
      label = { text = L["Select"], pos = "LEFT" },
      name = "KSKWhoMissingToAdd", mode = "SINGLE",
      x = 4, y = ypos, dwidth = 250, items = {
        { text = L["Add Missing Raid Members"], value = 1 },
        { text = L["Add All Missing Members"], value = 2 },
      }, initialvalue = 1, itemheight = 16,
    }
    ret.what = KUI:CreateDropDown (arg, ret)
    ret.what:Catch ("OnValueChanged", function (this, evt, newv)
      what = newv
    end)
    ypos = ypos - 32
    arg = {}

    arg = {
      x = 0, y = ypos, label = { text = L["Insert Randomly"] },
    }
    ret.insrandom = KUI:CreateCheckBox (arg, ret)
    ret.insrandom:Catch ("OnValueChanged", function (this, evt, val)
      insrandom = val
    end)
    arg = {}
    ypos = ypos - 24

    ret.OnAccept = function (this)
      if (what == 1) then
        if (ksk.inraid) then
          for k,v in pairs (ksk.raid.users) do
            local uid = k
            if (ksk.cfg.tethered) then
              if (ksk:UserIsAlt (uid)) then
                uid = ksk.users[uid].main
              end
            end
            if (not ksk:UserInList (uid)) then
              local pos = ksk.lists[ksk.listid].nusers + 1
              if (insrandom) then
                pos = math.random (pos)
              end
              ksk:InsertMember (uid, ksk.listid, pos)
              info (L["added %s to list %q at position %s."],
                aclass (ksk.users[uid]), white(ksk.lists[ksk.listid].name),
                white(tostring(pos)))
            end
          end
        end
      elseif (what == 2) then
        for k,v in pairs (ksk.users) do
          local doit = false
          if (ksk.cfg.tethered) then
            if (not ksk:UserIsAlt (k, v.flags)) then
              doit = true
            end
          else
            doit = true
          end
          if (doit) then
            if (not ksk:UserInList (k)) then
              local pos = ksk.lists[ksk.listid].nusers + 1
              if (insrandom) then
                pos = math.random (pos)
              end
              ksk:InsertMember (k, ksk.listid, pos)
              info (L["added %s to list %q at position %s."], aclass (v),
                white(ksk.lists[ksk.listid].name), white(tostring(pos)))
            end
          end
        end
      end
      ksk.addmissingdlg:Hide ()
      ksk.mainwin:Show ()
    end

    ret.OnCancel = function (this)
      ksk.addmissingdlg:Hide ()
      ksk.mainwin:Show ()
    end

    ksk.addmissingdlg = ret
  end

  insrandom = false
  what = 1
  ksk.addmissingdlg.what:SetValue (what)
  ksk.addmissingdlg.insrandom:SetChecked (false)
  ksk.addmissingdlg.clistmsg:SetText (strfmt (L["Current list: %s"], white(ksk.list.name)))

  ksk.mainwin:Hide ()
  ksk.addmissingdlg:Show ()
end

local function announce_list_button (isall, shifted)
  if (not ksk.list or not members or (not shifted and not ksk.inraid)) then
    return
  end
  local ts = strfmt (L["%s: relative positions of all currrent raiders for the %q list (ordered highest to lowest): "], L["MODTITLE"], ksk.list.name)
  if (isall) then
    ts = strfmt (L["%s: members of the %q list (ordered highest to lowest): "], L["MODTITLE"], ksk.list.name)
  end
  local sendfn = ksk.SendRaidMsg
  if (shifted and K.player.isguilded) then
    sendfn = ksk.SendGuildMsg
  end

  local uid, as, al
  local np = 0
  local len = strlen (ts)
  for i = 1, #members do
    uid = members[i].id
    as = nil
    if (not isall and ksk.raid.users[uid]) then
      np = np + 1
      as = strfmt ("%s(%d) ", ksk.users[uid].name, members[i].idx)
    elseif (isall) then
      np = np + 1
      as = ksk.users[uid].name .. " "
    end
    if (as) then
      al = strlen (as)
      if (len + al > 240) then
        sendfn (ts)
        ts = strfmt ("%s: ", L["MODTITLE"])
        len = strlen (ts)
      end
      ts = ts .. as
      len = len + al
    end
  end
  if (np > 0) then
    sendfn (ts)
  end
end

function ksk:InitialiseListsGUI ()
  local arg

  local cf = ksk.mainwin.tabs[ksk.LISTS_TAB].content
  local tbf = ksk.mainwin.tabs[ksk.LISTS_TAB].topbar
  local ls = cf.vsplit.leftframe
  local rs = cf.vsplit.rightframe

  --
  -- The left-hand side panel remains invariant regardless of which top tab
  -- is selected. It is the list of lists, and the buttons which control that
  -- list. We do that bit first.
  --
  arg = {
    inset = 2, height = 40,
    rightsplit = true, name = "KSKListsLHHSplit",
  }
  ls.hsplit = KUI:CreateHSplit (arg, ls)
  arg = {}
  local tl = ls.hsplit.topframe
  local bl = ls.hsplit.bottomframe
  ksk.qf.listctl = bl

  local ypos = 6
  arg = {
    x = "CENTER", y = ypos, width = 165, height = 24, text = L["Announce"],
    tooltip = { title = "$$", text = L["TIP029"], },
  }
  bl.announcebutton = KUI:CreateButton (arg, bl)
  bl.announcebutton:Catch ("OnClick", function (this, evt)
    announce_list_button (false, IsShiftKeyDown ())
  end)
  arg = {}
  ypos = ypos - 24

  arg = {
    x = "CENTER", y = ypos, width = 165, height = 24, text = L["Announce All"],
    tooltip = { title = "$$", text = L["TIP094"], },
  }
  bl.announceallbutton = KUI:CreateButton (arg, bl)
  bl.announceallbutton:Catch ("OnClick", function (this, evt)
    announce_list_button (true, IsShiftKeyDown ())
  end)
  arg = {}
  ypos = ypos - 24
  -- Now for the actual scroll list of roll lists
  local function rlist_och (this)
    local idx = this:GetID ()
    if (ksk.qf.memberlist) then
      ksk.qf.memberlist.itemcount = 0
      ksk.qf.memberlist:UpdateList ()
    end
    this:GetParent():GetParent():SetSelected (idx, false, true)
    ksk:RefreshListDropDowns ()
    return true
  end

  arg = {
    name = "KSKRollListScrollList",
    itemheight = 16,
    newitem = function (objp, num)
      return KUI.NewItemHelper (objp, num, "KSKRListButton", 155, 16,
        nil, rlist_och, nil, nil)
      end,
    setitem = function (objp, idx, slot, btn)
      return KUI.SetItemHelper (objp, btn, idx,
        function (op, ix)
          return ksk.lists[ksk.sortedlists[ix].id].name
        end)
      end,
    selectitem = rlist_selectitem,
    highlightitem = function (objp, idx, slot, btn, onoff)
      return KUI.HighlightItemHelper (objp, idx, slot, btn, onoff)
    end,
  }
  tl.slist = KUI:CreateScrollList (arg, tl)
  arg = {}
  ksk.qf.lists = tl.slist

  local bdrop = {
    bgFile = KUI.TEXTURE_PATH .. "TDF-Fill",
    tile = true,
    tileSize = 32,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
  }
  tl.slist:SetBackdrop (bdrop)

  --
  -- Lists panel, Members tab
  --

  local cf = ksk.mainwin.tabs[ksk.LISTS_TAB].tabs[ksk.LISTS_MEMBERS_TAB].content
  ksk.qf.listbuttons = cf

  --
  -- We need to create a frame anchored to the left side of the split, that
  -- will contain the scrolling list of users. The buttons appear to the
  -- right of the list. The scrolling list code requires a complete frame
  -- to take over so we create that first.
  --
  cf.sframe = MakeFrame ("Frame", nil, cf)
  cf.sframe:ClearAllPoints ()
  cf.sframe:SetPoint ("TOPLEFT", cf, "TOPLEFT", 0, 0)
  cf.sframe:SetPoint ("BOTTOMLEFT", cf, "BOTTOMLEFT", 0, 25)
  cf.sframe:SetWidth (190)

  arg = {
    x = 0, y = 2, len = 16, font = "ChatFontSmall",
    width = 150, tooltip = { title = L["User Search"], text = L["TIP099"] },
  }
  cf.searchbox = KUI:CreateEditBox (arg, cf)
  cf.searchbox:ClearAllPoints ()
  cf.searchbox:SetPoint ("BOTTOMLEFT", cf, "BOTTOMLEFT", 8, 0)
  cf.searchbox:SetWidth (160)
  cf.searchbox:SetHeight (20)
  ksk.qf.listmemsearch = cf.searchbox
  cf.searchbox:Catch ("OnEnterPressed", function (this, evt, newv, user)
    this:SetText ("")
  end)
  cf.searchbox:Catch ("OnValueChanged", function (this, evt, newv, user)
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
              ksk.qf.memberlist:SetSelected (kk, true)
              break
            end
          end
          return
        end
      end
    end
  end)


  arg = {
    name = "KSKMembersScrollList",
    itemheight = 16,
    newitem = mlist_newitem,
    setitem = mlist_setitem,
    selectitem = mlist_selectitem,
    highlightitem = function (objp, idx, slot, btn, onoff)
      return KUI.HighlightItemHelper (objp, idx, slot, btn, onoff)
    end,
  }
  cf.slist = KUI:CreateScrollList (arg, cf.sframe)
  arg = {}
  ksk.qf.memberlist = cf.slist
  cf.slist:SetBackdrop (bdrop)

  ypos = 0
  arg = { x = 195, y = ypos, width = 95, height = 24,
    text = L["Insert"],
    tooltip = { title = "$$", text = L["TIP030"], },
  }
  cf.insertbutton = KUI:CreateButton (arg, cf)
  cf.insertbutton:Catch ("OnClick", function (this, evt)
    insert_member (this)
  end)
  ypos = ypos - 24

  arg.y = ypos
  arg.text = L["Delete"]
  arg.tooltip = { title = "$$", text = L["TIP031"], }
  cf.deletebutton = KUI:CreateButton (arg, cf)
  cf.deletebutton:Catch ("OnClick", function (this, evt)
    delete_member (this)
  end)
  ypos = ypos - 24

  arg.y = ypos
  arg.text = L["King"]
  arg.tooltip = { title = "$$", text = L["TIP032"], }
  cf.kingbutton = KUI:CreateButton (arg, cf)
  ksk.qf.king = cf.kingbutton
  cf.kingbutton:Catch ("OnClick", function (this, evt)
    move_member (this, 3)
  end)
  ypos = ypos - 24

  arg.y = ypos
  arg.text = L["Move Up"]
  arg.tooltip = { title = "$$", text = L["TIP033"], }
  cf.upbutton = KUI:CreateButton (arg, cf)
  cf.upbutton:Catch ("OnClick", function (this, evt)
    move_member (this, 2)
  end)
  ksk.qf.moveup = cf.upbutton
  ypos = ypos - 24

  arg.y = ypos
  arg.text = L["Move Down"]
  arg.tooltip = { title = "$$", text = L["TIP034"], }
  cf.downbutton = KUI:CreateButton (arg, cf)
  cf.downbutton:Catch ("OnClick", function (this, evt)
    move_member (this, 1)
  end)
  ksk.qf.movedown = cf.downbutton
  ypos = ypos - 24

  arg.y = ypos
  arg.text = L["Suicide"]
  arg.tooltip = { title = "$$", text = L["TIP035"], }
  cf.suicidebutton = KUI:CreateButton (arg, cf)
  ksk.qf.suicide = cf.suicidebutton
  cf.suicidebutton:Catch ("OnClick", function (this, evt)
    move_member (this, 0)
  end)
  ypos = ypos - 24

  arg.y = ypos
  arg.text = L["Reserve"]
  arg.tooltip = { title = "$$", text = L["TIP036"], }
  cf.reservebutton = KUI:CreateButton (arg, cf)
  cf.reservebutton:Catch ("OnClick", function (this, evt)
    resunres_member (this)
  end)
  ksk.qf.resunres = cf.reservebutton
  ypos = ypos - 24
  arg = {}

  --
  -- Lists panel, Config tab
  --

  --
  -- Create the horizontal split at the bottom for the buttons
  --

  local cf = ksk.mainwin.tabs[ksk.LISTS_TAB].tabs[ksk.LISTS_CONFIG_TAB].content
  arg = {
    inset = 2, height = 75, leftsplit = true, name = "KSKListCfgRSplit",
  }
  cf.hsplit = KUI:CreateHSplit (arg, cf)
  local tr = cf.hsplit.topframe
  local br = cf.hsplit.bottomframe

  ksk.qf.listconf = tr
  ksk.qf.listcfgbuttons = br

  ypos = 0
  arg = {
    x = 0, y = ypos, label = { text = L["Sort Order"] },
    width = 200, minval = 1, maxval = 64,
    tooltip = { title = "$$", text = L["TIP037"] },
  }
  tr.sortorder = KUI:CreateSlider (arg, tr)
  tr.sortorder:Catch ("OnValueChanged", function (this, evt, newv, user)
    if (user) then
      changed ()
    end
    linfo.sortorder = tonumber (newv)
  end)
  arg = {}
  ypos = ypos - 48

  arg = {
    x = 0, y = ypos, name = "KSKDefRankDropdown", itemheight = 16,
    dwidth = 175, items = KUI.emptydropdown, mode = "SINGLE",
    label = { text = L["Initial Guild Rank Filter"], },
    tooltip = { title = "$$", text = L["TIP038"] },
  }
  tr.defrank = KUI:CreateDropDown (arg, tr)
  ksk.qf.defrankdd = tr.defrank
  tr.defrank:Catch ("OnValueChanged", function (this, evt, nv, user)
    if (user) then
      changed ()
    end
    linfo.def_rank = tonumber (nv)
  end)
  arg = {}
  ypos = ypos - 48

  arg = {
    x = 0, y = ypos, label = { text = L["Strict Class Armor Filtering"] },
    tooltip = { title = "$$", text = L["TIP039"] },
  }
  tr.cfilter = KUI:CreateCheckBox (arg, tr)
  tr.cfilter:Catch ("OnValueChanged", function (this, evt, val, user)
    if (user) then
      changed ()
    end
    linfo.strictcfilter = val
  end)
  arg = {}
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, label = { text = L["Strict Role Filtering"] },
    tooltip = { title = "$$", text = L["TIP040"] },
  }
  tr.rfilter = KUI:CreateCheckBox (arg, tr)
  tr.rfilter:Catch ("OnValueChanged", function (this, evt, val, user)
    if (user) then
      changed ()
    end
    linfo.strictrfilter = val
  end)
  arg = {}
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, name = "KSKAdditionalSuicideDD", itemheight = 16,
    dwidth = 175, mode = "SINGLE", items = KUI.emptydropdown,
    label = { text = L["Suicide on Additional List"] },
    tooltip = { title = "$$", text = L["TIP041"] },
  }
  tr.slistdd = KUI:CreateDropDown (arg, tr)
  ksk.qf.extralist = tr.slistdd
  tr.slistdd:Catch ("OnValueChanged", function (this, evt, newv, user)
    if (user) then
      changed ()
    end
    linfo.extralist = newv
  end)
  arg = {}
  ypos = ypos - 48

  arg = {
    x = 0, y = ypos, text = L["Update"], enabled = false,
    tooltip = { title = "$$", text = L["TIP042"] },
  }
  tr.updatebtn = KUI:CreateButton (arg, tr)
  ksk.qf.listupdbtn = tr.updatebtn
  tr.updatebtn:Catch ("OnClick", function (this, evt, ...)
    K.CopyTable (linfo, ksk.list)
    ksk:RefreshLists ()
    tr.updatebtn:SetEnabled (false)
    -- If this changes MUST change CHLST is KSK-Config.lua
    local es = strfmt ("%s:%d:%d:%s:%s:%s", ksk.listid,
      linfo.sortorder, linfo.def_rank, linfo.strictcfilter and "Y" or "N",
      linfo.strictrfilter and "Y" or "N", linfo.extralist)
    ksk.AddEvent (ksk.currentid, "CHLST", es)
  end)

  --
  -- List control buttons at the bottom right
  --
  ypos = 0
  arg = {
    x = 0, y = ypos, width = 90, height = 24, text = L["Create"],
    tooltip = { title = "$$", text = L["TIP043"] },
  }
  br.createbutton = KUI:CreateButton (arg, br)
  br.createbutton:Catch ("OnClick", function (this, evt)
    create_list_button ()
  end)
  arg = {}

  arg = {
    x = 90, y = ypos, width = 90, height = 24, text = L["Delete"],
    tooltip = { title = "$$", text = L["TIP044"] },
  }
  br.deletebutton = KUI:CreateButton (arg, br)
  br.deletebutton:Catch ("OnClick", function (this, evt)
    delete_list_button (ksk.listid)
  end)
  arg = {}

  arg = {
    x = 180, y = ypos, width = 90, height = 24, text = L["Rename"],
    tooltip = { title = "$$", text = L["TIP045"] },
  }
  br.renamebutton = KUI:CreateButton (arg, br)
  br.renamebutton:Catch ("OnClick", function (this, evt)
    rename_list_button (ksk.listid)
  end)
  arg = {}
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, width = 90, height = 24, text = L["Copy"],
    tooltip = { title = "$$", text = L["TIP046"] },
  }
  br.copybutton = KUI:CreateButton (arg, br)
  br.copybutton:Catch ("OnClick", function (this, evt)
    copy_list_button (ksk.listid)
  end)
  arg = {}

  arg = {
    x = 90, y = ypos, width = 90, height = 24, text = L["Import"],
    tooltip = { title = "$$", text = L["TIP047"] },
  }
  br.importbutton = KUI:CreateButton (arg, br)
  br.importbutton:Catch ("OnClick", function (this, evt)
    import_list_button ()
  end)
  arg = {}

  arg = {
    x = 180, y = ypos, width = 90, height = 24, text = L["Export"],
    tooltip = { title = "$$", text = L["TIP048"] },
  }
  br.exportbutton = KUI:CreateButton (arg, br)
  br.exportbutton:Catch ("OnClick", function (this, evt)
    export_list_button ()
  end)
  arg = {}
  ypos = ypos - 24

  arg = {
    x = 75, y = ypos, width = 120, height = 24, text = L["Add Missing"],
    tooltip = { title = "$$", text = L["TIP049"] },
  }
  br.addmissingbutton = KUI:CreateButton (arg, br)
  br.addmissingbutton:Catch ("OnClick", function (this, evt)
    add_missing_button ()
  end)
  arg = {}

  initdone = true
  ksk:RefreshLists ()
end

function ksk:RefreshMemberList ()
  ksk.members = nil
  members = nil

  if (not ksk.listid) then
    ksk.memberid = nil
    ksk.qf.memberlist.itemcount = 0
    ksk.qf.memberlist:UpdateList ()
  else
    ksk.cfg = ksk.frdb.configs[ksk.currentid]
    ksk.lists = ksk.cfg.lists
    ksk.list = ksk.lists[ksk.listid]
    if (ksk.list.nusers > 0) then
      local oldmember = ksk.memberid or ""
      local oldidx = nil
      ksk.memberid = nil
      ksk.members = ksk.list.users
      ksk.users = ksk.cfg.users

      members = {}
      for k,v in ipairs(ksk.members) do
        local ti = {id = v, idx=k }
        tinsert (members, ti)
      end

      if (ksk.cfg.tethered) then
        for i = #members, 1, -1 do
          local usr = ksk.users[members[i].id]
          if (usr.alts) then
            for j = 1, #usr.alts do
              local ti = { id = usr.alts[j], isalt = true,
                main = members[i].id, idx = members[i].idx }
              tinsert (members, i+j, ti)
            end
          end
        end
      end

      for k,v in ipairs (members) do
        if (v.id == oldmember) then
          oldidx = k
        end
      end

      ksk.qf.memberlist.itemcount = #members
      ksk.qf.memberlist:UpdateList ()
      if (oldidx) then
        ksk.memberid = members[oldidx].id
      end
      ksk.qf.memberlist:SetSelected (oldidx)
    else
      ksk.memberid = nil
      ksk.qf.memberlist.itemcount = 0
      ksk.qf.memberlist:UpdateList ()
      ksk.qf.memberlist:SetSelected (nil)
    end
  end

  local en = true
  if (not ksk.csd.isadmin or ksk.qf.lists.itemcount < 1) then
    en = false
  end
  ksk.qf.listbuttons.insertbutton:SetEnabled (en)

  if ((ksk.qf.memberlist.itemcount < 1) or not ksk.memberid) then
    en = false
  end
  ksk.qf.listbuttons.deletebutton:SetEnabled (en)
  ksk.qf.listbuttons.reservebutton:SetEnabled (en)

  ksk:RefreshMembership ()
  ksk:RefreshLootMembers ()
end

function ksk:RefreshListDropDowns ()
  --
  -- There are several user interface elements that may need to be changed.
  -- The list configuration panel has a "Next List" drop down that will need
  -- to know of any list changes, as well as its "suicide on additional lists"
  -- option. The main configuration also has a "Default List" option and a
  -- "Try Final List" option that all need to be updated to the new list of
  -- lists. Some of these lists (such as the list config panel's Next List
  -- setting) have additional options over and above the list of lists.
  -- However, all of them share the actual basic lists of lists, which we will
  -- calculate first before inserting additional members for other UI elements.
  --
  local llist = {}
  local lc = 0
  local ti
  local dlfound = false
  local flfound = false
  ti = { text = L["None"], value = "0", }
  tinsert (llist, ti)
  for k,v in pairs (ksk.sortedlists) do
    ti = { text = ksk.lists[v.id].name, value = v.id, }
    if (ksk.cfg.settings.def_list == v.id) then
      dlfound = true
    end
    if (ksk.cfg.settings.final_list == v.id) then
      flfound = true
    end
    tinsert (llist, ti)
  end

  if (not dlfound) then
    ksk.cfg.settings.def_list = "0"
  end

  if (not flfound) then
    ksk.cfg.settings.final_list = "0"
  end

  ksk.qf.deflistdd:UpdateItems (llist)
  ksk.qf.deflistdd:SetValue (ksk.cfg.settings.def_list)

  ksk.qf.itemlistdd:UpdateItems (llist)
  if (ksk.itemid) then
    local val = ksk.items[ksk.itemid].speclist or "0"
    ksk.qf.itemlistdd:SetValue (val)
  else
    ksk.qf.itemlistdd:SetValue ("0")
  end

  ksk.qf.suicidelistdd:UpdateItems (llist, true)
  if (ksk.itemid) then
    local val = ksk.items[ksk.itemid].suicide or "0"
    ksk.qf.suicidelistdd:SetValue (val)
  else
    ksk.qf.suicidelistdd:SetValue ("0")
  end

  llist = {}
  ti = { text = L["None"], value = "0", }
  tinsert (llist, ti)
  for k,v in pairs (ksk.sortedlists) do
    if (ksk.listid and ksk.listid ~= v.id) then
      ti = { text = ksk.lists[v.id].name, value = v.id, }
      tinsert (llist, ti)
    end
  end

  ksk.qf.extralist:UpdateItems (llist)
  if (ksk.list) then
    ksk.qf.extralist:SetValue (ksk.list.extralist)
  else
    ksk.qf.extralist:SetValue ("0")
  end
end

function ksk:RefreshLists ()
  local vt = {}
  ksk.sortedlists = {}
  ksk.cfg = ksk.frdb.configs[ksk.currentid]
  ksk.lists = ksk.cfg.lists

  local oldlist = ksk.listid or ""
  local oldidx = 0

  ksk.listid = nil
  for k,v in pairs (ksk.lists) do
    --
    -- Since we're going through the list anyway, check to make sure that our
    -- next and additional suicide lists are still valid. Set them to 0 if
    -- not.
    --
    if (v.extralist ~= "0" and not ksk.lists[v.extralist]) then
      ksk.lists[k].extralist = "0"
    end
    local ent = { id = k }
    tinsert (ksk.sortedlists, ent)
  end
  tsort (ksk.sortedlists, function (a,b)
    if (ksk.lists[a.id].sortorder < ksk.lists[b.id].sortorder) then
      return true
    end
    if (ksk.lists[a.id].sortorder == ksk.lists[b.id].sortorder) then
      return strlower(ksk.lists[a.id].name) < strlower(ksk.lists[b.id].name)
    end
    return false
  end)

  for k,v in ipairs (ksk.sortedlists) do
    if (v.id ==  oldlist) then
      oldidx = k
    end
  end
  if (oldidx == 0) then
    oldidx = 1
  end

  ksk.qf.lists.itemcount = ksk.cfg.nlists
  if (ksk.qf.lists.itemcount > 0) then
    ksk.qf.lists:UpdateList ()
    ksk.listid = ksk.sortedlists[oldidx].id
    ksk.list = ksk.lists[ksk.listid]
    ksk.qf.lists:SetSelected (oldidx)
    setup_linfo ()
  else
    ksk.listid = nil
    ksk.list = nil
    ksk.qf.lists:UpdateList ()
  end

  local en = true
  if (not ksk.listid or not ksk.csd.isadmin or not ksk.inraid) then
    en = false
  end
  ksk.qf.listctl.announcebutton:SetEnabled (en)
  ksk.qf.listctl.announceallbutton:SetEnabled (en)

  if (ksk.initialised) then
    ksk:RefreshListDropDowns ()
    local cfgid = ksk.currentid
    if (ksk.csdata[cfgid].undo and #ksk.csdata[cfgid].undo > 0 and ksk.isml) then
      ksk.qf.undobutton:SetEnabled (true)
    else
      ksk.qf.undobutton:SetEnabled (false)
    end
  end
  ksk:RefreshMemberList ()
  ksk:RefreshLootLists ()
end

function ksk:FindList (name, cfg)
  cfg = cfg or ksk.currentid
  local lowname = strlower(name)

  for k,v in pairs(ksk.configs[cfg].lists) do
    if (strlower(v.name) == lowname) then
      return k
    end
  end
  return nil
end

function ksk:CreateNewList (name, cfg, myid, nocmd)
  cfg = cfg or ksk.currentid

  if (strfind (name, ":")) then
    err (L["invalid list name. Please try again."])
    return true
  end

  local cid = ksk:FindList (name, cfg)
  if (cid) then
    if (not nocmd) then
      err (L["roll list %q already exists. Try again."], white (name))
    end
    return true
  end

  local newkey = myid or ksk:CreateNewID (name)
  ksk.configs[cfg].lists[newkey] = {}
  local rl = ksk.configs[cfg].lists[newkey]

  rl.name = name
  rl.sortorder = 1
  rl.def_rank = 999
  rl.strictcfilter = false
  rl.strictrfilter = false
  rl.extralist = "0"
  rl.users = {}
  rl.nusers = 0

  ksk.configs[cfg].nlists = ksk.configs[cfg].nlists + 1

  if (not myid and not nocmd) then
    info (L["roll list %q created."], white(name))
  end

  if (not nocmd) then
    local es = strfmt ("%s:%s", newkey, name)
    ksk.AddEvent (cfg, "MKLST", es, true)
  end

  ksk:RefreshLists ()
  ksk:UpdateAllConfigSettings ()
  return false, newkey
end

function ksk:DeleteList (listid, cfgid, nocmd)
  local cfg = cfgid or ksk.currentid

  if (not nocmd) then
    info (L["roll list %q deleted."], white(ksk.configs[cfg].lists[listid].name))
  end

  if (ksk.configs[cfg].lists[listid]) then
    ksk.configs[cfg].lists[listid] = nil
    ksk.configs[cfg].nlists = ksk.configs[cfg].nlists - 1
  end

  if (ksk.configs[cfg].settings.def_list == listid) then
    ksk.configs[cfg].settings.def_list = "0"
  end

  if (ksk.configs[cfg].settings.final_list == listid) then
    ksk.configs[cfg].settings.final_list = "0"
  end

  for k,v in pairs(ksk.configs[cfg].lists) do
    if (v.extralist == listid) then
      ksk.configs[cfg].lists[k].extralist = "0"
    end
  end

  for k,v in pairs (ksk.items) do
    if (v.nextdrop ~= nil and v.nextdrop.suicide == listid) then
      ksk.items[k].nextdrop.suicide = nil
    end
    if (v.list and v.list == listid) then
      ksk.items[k].list = nil
    end
    if (v.suicide and v.suicide == listid) then
      ksk.items[k].suicide = nil
    end
  end

  if (ksk.listid == listid) then
    ksk.listid = nil
  end

  if (not nocmd) then
    ksk.AddEvent (cfg, "RMLST", listid, true)
  end

  ksk:RefreshLists ()
  ksk:RefreshUsers ()
  ksk:RefreshItemList ()
  ksk:UpdateAllConfigSettings ()
end

local function real_delete_list (arg)
  local cfg = arg.cfg or ksk.currentid
  local listid = arg.listid

  ksk:DeleteList (listid, cfg, false)
end

function ksk:DeleteListCmd (listid, show, cfg)
  cfg = cfg or ksk.currentid

  local isshown = show or ksk.mainwin:IsShown ()
  ksk.mainwin:Hide ()

  ksk:ConfirmationDialog (L["Delete Roll List"], L["DELLIST"],
    ksk.configs[cfg].lists[listid].name, real_delete_list,
    { cfg=cfg, listid=listid}, isshown, 190)

  return false
end

function ksk:RenameList (listid, newname, cfg, nocmd)
  cfg = cfg or ksk.currentid

  local cid = ksk:FindList (newname, cfg)
  if (cid) then
    if (not nocmd) then
      err (L["roll list %q already exists. Try again."], white (name))
    end
    return true
  end

  local oldname = ksk.configs[cfg].lists[listid].name
  if (not nocmd) then
    info (L["NOTICE: roll list %q renamed to %q."], white (oldname), white (newname))
  end
  ksk.configs[cfg].lists[listid].name = newname
  ksk:RefreshUsers ()
  ksk:RefreshLists ()
  ksk:UpdateAllConfigSettings ()

  if (not nocmd) then
    local es = strfmt ("%s:%s", listid, newname)
    ksk.AddEvent (cfg, "MVLST", es, true)
  end

  return false
end

function ksk:CopyList (listid, newname, cfg, myid, nocmd)
  cfg = cfg or ksk.currentid

  local cid = ksk:FindList (newname, cfg)
  if (cid) then
    if (not nocmd) then
      err (L["roll list %q already exists. Try again."], white (name))
    end
    return true
  end

  local rv
  rv, cid = ksk:CreateNewList (newname, cfg, myid, nocmd)
  if (rv) then
    return true
  end

  local src = ksk.lists[listid]
  local dst = ksk.lists[cid]

  dst.sortorder = src.sortorder
  dst.strictcfilter = src.strictcfilter
  dst.strictrfilter = src.strictrfilter
  dst.nusers = src.nusers
  K.CopyTable (src.users, dst.users)

  if (not nocmd) then
    local es = strfmt ("%s:%s:%s", listid, cid, newname)
    ksk.AddEvent (cfg, "CPLST", es, true)
  end

  ksk:RefreshUsers ()
  ksk:RefreshLists ()
  ksk:UpdateAllConfigSettings ()

  return false
end

function ksk:SelectList (listid)
  for k,v in ipairs (ksk.sortedlists) do
    if (v.id == listid) then
      ksk.mainwin.tabs[ksk.LISTS_TAB].content.vsplit.leftframe.hsplit.topframe.slist:SetSelected (k)
      ksk:RefreshLists ()
      return false
    end
  end
  return true
end

function ksk:UserInList (uid, listid, cfg)
  cfg = cfg or ksk.currentid
  listid = listid or ksk.listid

  if (not ksk.configs[cfg].lists[listid]) then
    return nil
  end

  local rlist = ksk.configs[cfg].lists[listid]
  if (rlist.nusers < 1) then
    return false
  end
  for k,v in ipairs (rlist.users) do
    if (uid == v) then
      return true, k
    end
  end
  return false
end

function ksk:InsertMember (uid, listid, pos, cfg, nocmd)
  cfg = cfg or ksk.currentid
  listid = listid or ksk.listid
  if (not ksk.configs[cfg].lists[listid]) then
    return true
  end
  if (ksk:UserInList (uid, listid, cfg)) then
    return true
  end

  local rl = ksk.configs[cfg].lists[listid]

  rl.nusers = rl.nusers + 1
  pos = pos or rl.nusers
  if (pos > rl.nusers) then
    pos = rl.nusers
  end
  tinsert (rl.users, pos, uid)

  if (not nocmd) then
    local es = strfmt ("%s:%s:%d", uid, listid, pos)
    ksk.AddEvent (cfg, "IMLST", es, true)
  end

  ksk:RefreshMemberList ()
  return false
end

--
-- Sets the member list to exactly the ulist string, which is a concatenated
-- list of user IDs, all of which are assumed to already exist. This is
-- only actually used by the CSV import functionality.
--
function ksk:SetMemberList (ulist, listid, cfg, nocmd)
  cfg = cfg or ksk.currentid
  listid = listid or ksk.listid
  if (not ksk.configs[cfg].lists[listid]) then
    return true
  end
  local ll = ksk.configs[cfg].lists[listid]
  ll.users = ksk:SplitRaidList (ulist)
  ll.nusers = #ll.users

  if (not nocmd) then
    ksk.AddEvent (cfg, "SMLST", strfmt ("%s:%s", listid, ulist), true)
  end

  if (cfg == ksk.currentid) then
    ksk:RefreshLists ()
  end
end

--
-- This can be called from either the user interface or from the sync code.
-- Unlike a normal loot suicide which needs to know which raid members were
-- present in order to move around offline users, moving a user up and down
-- always acts on the full raw list, and it can always move over frozen
-- users, so we don't need to worry about them either. Please note that this
-- is the code that actually implements the moves, it will not record a move
-- event for the sync log. That is handled above in the actual button press
-- handler (which in turn ends up calling this function).
-- The dir parameter is 1 to move them down 1 slot, 2 to move them up 1
-- slot, 0 to suicide them to the extreme bottom of the list or 3 to king
-- them and move them to the extreme top of the list.
--
function ksk:MoveMember (uid, listid, dir, cfg)
  cfg = cfg or ksk.currentid
  listid = listid or ksk.listid

  local rl = ksk.configs[cfg].lists[listid]
  if (not rl) then
    return true
  end

  local ul = rl.users
  local up = nil
  for k,v in ipairs (ul) do
    if (v == uid) then
      up = k
      break
    end
  end

  if (up == nil) then
    return true
  end

  local m = tremove (ul, up)
  if (dir == 0) then
    tinsert (ul, m)
  elseif (dir == 3) then
    tinsert (ul, 1, m)
  elseif (dir == 1) then
    if (up ~= #ul+1) then
      tinsert (ul, up+1, m)
    else
      tinsert (ul, up, m)
    end
  elseif (dir == 2) then
    if (up ~= 1) then
      tinsert (ul, up-1, m)
    else
      tinsert (ul, up, m)
    end
  end

  if (listid == ksk.listid and cfg == ksk.currentid) then
    ksk:RefreshMemberList ()
  end
  return false
end

function ksk:DeleteMember (uid, listid, cfg, nocmd)
  cfg = cfg or ksk.currentid
  listid = listid or ksk.listid

  local rl = ksk.configs[cfg].lists[listid]
  if (not rl) then
    return true
  end

  local ul = rl.users
  local up = nil
  for k,v in ipairs (ul) do
    if (v == uid) then
      up = k
      break
    end
  end

  if (up == nil) then
    return true
  end

  tremove (ul, up)
  rl.nusers = rl.nusers - 1
  if (not nocmd) then
    local es = strfmt ("%s:%s", uid, listid)
    ksk.AddEvent (cfg, "DMLST", es, true)
  end

  if (listid == ksk.listid and cfg == ksk.currentid) then
    ksk:RefreshMemberList ()
  end
  return false
end

--
-- Whenever we change a user's Alt status, or whenever a config space has
-- its "tethered alts" setting changed, we may need to fix up entries in all
-- of the lists. Say for example UserB is an alt of UserA. They are both
-- members in List1. Now the owner decides she wants to enable tethered alts.
-- This means that UserB needs to be removed from List1, because that user
-- will now appear "underneath" UserA in the list. The same situation can
-- occur if tethered alts were already enabled but a user was not correctly
-- marked as an alt. When that is corrected, we need to make sure that the
-- alt is removed from all lists, as it will now be tethered to the main.
-- So we simply need to go through all lists in the configuration and remove
-- any alts. However, if only the alt is in the list, we need to replace that
-- slot position with the main, as it will now be replaced by the main.
--
function ksk:FixupLists (cfg)
  cfg = cfg or ksk.currentid

  if (not ksk.configs[cfg].tethered) then
    return false
  end

  local changed = false

  for k,v in pairs (ksk.configs[cfg].lists) do
    local il = 1
    while (il <= #v.users) do
      local inc = 1
      local vv = v.users[il]
      local ia, mid = ksk:UserIsAlt (vv, nil, cfg)

      if (ia) then
        assert (mid)
        if (not ksk:UserInList (mid, k, cfg)) then
          --
          -- The user is marked as an alt but their main isn't in the list.
          -- This means we have to replace this alt (in the same position)
          -- with the alt's main.
          --
          v.users[il] = mid
          changed = true
        else
          --
          -- The alt's main is already in the list, so we can now safely
          -- remove this alt from the roll list.
          --
          tremove (v.users, il)
          v.nusers = v.nusers - 1
          changed = true
          inc = 0
        end
      end
      il = il + inc
    end
  end

  if (changed) then
    ksk:FixupLists (cfg)
  end

  if (cfg == ksk.currentid) then
    ksk:RefreshLists ()
    ksk:RefreshMemberList ()
  end
  return false
end

