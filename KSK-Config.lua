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

if (not K) then
  error ("KahLua KonferSK: could not find KahLua Kore.", 2)
end

local ksk = K:GetAddon ("KKonferSK")
local L = ksk.L
local KUI = ksk.KUI
local MakeFrame = KUI.MakeFrame

-- Local aliases for global or LUA library functions
local _G = _G
local tinsert = table.insert
local tremove = table.remove
local setmetatable = setmetatable
local tconcat = table.concat
local tsort = table.sort
local tostring = tostring
local strlower = string.lower
local GetTime = GetTime
local min = math.min
local max = math.max
local strfmt = string.format
local strsub = string.sub
local strlen = string.len
local strfind = string.find
local xpcall, pcall = xpcall, pcall
local pairs, next, type = pairs, next, type
local select, assert, loadstring = select, assert, loadstring
local printf = K.printf

local ucolor = K.ucolor
local ecolor = K.ecolor
local icolor = K.icolor
local white = ksk.white
local class = ksk.class
local aclass = ksk.aclass
local debug = ksk.debug
local info = ksk.info
local err = ksk.err

local admincfg
local sortedconfigs
local coadsel
local sortedadmins
local initdone = false

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

local function config_setenabled (onoff)
  if (ksk.qf.cfgopts) then
    if (ksk.qf.cfgopts.cfgowner) then
      ksk.qf.cfgopts.cfgowner:SetEnabled (onoff)
    end
    if (ksk.qf.cfgopts.tethered) then
      ksk.qf.cfgopts.tethered:SetEnabled (onoff)
    end
    if (ksk.qf.cfgopts.cfgtype) then
      ksk.qf.cfgopts.cfgtype:SetEnabled (onoff)
    end
  end
  if (ksk.qf.cfgdelbutton) then
    ksk.qf.cfgdelbutton:SetEnabled (onoff)
  end
  if (ksk.qf.cfgrenbutton) then
    ksk.qf.cfgrenbutton:SetEnabled (onoff)
  end
  if (ksk.qf.cfgcopybutton) then
    ksk.qf.cfgcopybutton:SetEnabled (onoff)
  end
  if (ksk.qf.coadadd) then
    ksk.qf.coadadd:SetEnabled (onoff)
  end
end

local function config_selectitem (objp, idx, slot, btn, onoff)
  if (onoff) then
    config_setenabled (true)
    admincfg = sortedconfigs[idx].id
    local lcf = ksk.frdb.configs[admincfg]
    ksk.qf.cfgopts.cfgowner:SetValue (lcf.owner)
    ksk.qf.cfgopts.tethered:SetChecked (lcf.tethered)
    ksk.qf.cfgopts.cfgtype:SetValue (lcf.cfgtype)
    local en = ksk.csdata[admincfg].isadmin == 2 and true or false
    ksk.qf.cfgopts.cfgowner:SetEnabled (en)
    ksk.qf.cfgopts.tethered:SetEnabled (en)
    ksk.qf.coadadd:SetEnabled (en and lcf.nadmins < 36)
    ksk.qf.cfgrenbutton:SetEnabled (en)
    local foo = ksk:CanChangeConfigType ()
    if (not foo) then
      en = false
    end
    ksk.qf.cfgopts.cfgtype:SetEnabled (en)
    if (ksk.frdb.nconfigs > 1) then
      ksk.qf.cfgdelbutton:SetEnabled (true)
    else
      ksk.qf.cfgdelbutton:SetEnabled (false)
    end
    ksk:RefreshCoadmins ()
  else
    config_setenabled (false)
    admincfg = nil
    if (initdone) then
      ksk.qf.coadminscroll.itemcount = 0
      ksk.qf.coadminscroll:UpdateList ()
    end
  end
end

local function coad_setenabled (onoff)
  if (ksk.qf.coaddel) then
    ksk.qf.coaddel:SetEnabled (onoff)
  end
end

local function clist_selectitem (objp, idx, slot, btn, onoff)
  if (onoff) then
    coad_setenabled (true)
    coadsel = sortedadmins[idx]
    local lcf = ksk.frdb.configs[admincfg]
    local en = ksk.csdata[admincfg].isadmin == 2 and true or false
    if (coadsel == lcf.owner) then
      en = false
    end
    ksk.qf.coaddel:SetEnabled (en)
  else
    coad_setenabled (false)
    coadsel = nil
  end
end

local function new_space_button()
  local box

  if (not ksk.newconfig) then
    ksk.newconfig, box = ksk:SingleStringInputDialog ("KSKSetupNewSpace",
      L["Create Configuration"], L["NEWMSG"], 400, 165)

    local function verify_with_create (objp, val)
      if (strlen (val) < 1) then
        err (L["invalid configuration space name. Please try again."])
        objp:Show ()
        objp.ebox:SetFocus ()
        return true
      end
      ksk:CreateNewConfig (val, false)
      ksk.newconfig:Hide ()
      ksk.mainwin:Show ()
      return false
    end

    ksk.newconfig:Catch ("OnAccept", function (this, evt)
      local rv = verify_with_create (this, this.ebox:GetText ())
      return rv
    end)

    ksk.newconfig:Catch ("OnCancel", function (this, evt)
      ksk.newconfig:Hide ()
      ksk.mainwin:Show ()
      return false
    end)

    box:Catch ("OnEnterPressed", function (this, evt, val)
      local rv = verify_with_create (this, val)
      return rv
    end)
  else
    box = ksk.newconfig.ebox
  end

  box:SetText("")

  ksk.mainwin:Hide ()
  ksk.newconfig:Show ()
  box:SetFocus ()
end

local function rename_space_button (cfgid)
  local function rename_helper (newname, old)
    local found = false
    local lname = string.lower (newname)

    for k,v in pairs (ksk.frdb.configs) do
      if (string.lower(ksk.frdb.configs[k].name) == lname) then
        found = true
      end
    end

    if (found) then
      err (L["configuration %q already exists. Try again."], white (newname))
      return true
    end

    local rv = ksk:RenameConfig (old, newname)
    if (rv) then
      return true
    end

    return false
  end

  ksk:RenameDialog (L["Rename Configuration"], L["Old Name"],
    ksk.frdb.configs[cfgid].name, L["New Name"], 32, rename_helper,
    cfgid, true)

  ksk.mainwin:Hide ()
  ksk.renamedlg:Show ()
  ksk.renamedlg.input:SetFocus ()
end

local function copy_space_button (cfgid, newname, newid, shown)
  if (not ksk.copyspacedlg) then
    local ypos = 0
    local arg = {
      x = "CENTER", y = "MIDDLE",
      name = "KSKCopyConfigDialog",
      title = L["Copy Configuration"],
      border = true,
      width = 450,
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
      x = 0, y = ypos, width = 200, height = 20, autosize = false,
      justifyh = "RIGHT", font = "GameFontNormal",
      text = L["Source Configuration"],
    }
    ret.str1 = KUI:CreateStringLabel (arg, ret)
    arg.justifyh = "LEFT"
    arg.text = ""
    arg.border = true
    arg.color = {r = 1, g = 1, b = 1, a = 1 }
    ret.str2 = KUI:CreateStringLabel (arg, ret)
    ret.str2:ClearAllPoints ()
    ret.str2:SetPoint ("TOPLEFT", ret.str1, "TOPRIGHT", 12, 0)
    arg = {}
    ypos = ypos - 24

    arg = {
      x = 0, y = ypos, width = 200, height = 20, autosize = false,
      justifyh = "RIGHT", font = "GameFontNormal",
      text = L["Destination Configuration"],
    }
    ret.str3 = KUI:CreateStringLabel (arg, ret)
    arg.justifyh = "LEFT"
    arg.text = ""
    arg.border = true
    arg.color = {r = 1, g = 1, b = 1, a = 1 }
    ret.str4 = KUI:CreateStringLabel (arg, ret)
    ret.str4:ClearAllPoints ()
    ret.str4:SetPoint ("TOPLEFT", ret.str3, "TOPRIGHT", 12, 0)
    arg = {}

    arg = {
      x = 0, y = ypos, width = 200, height = 20, len = 32,
    }
    ret.dest = KUI:CreateEditBox (arg, ret)
    ret.dest:ClearAllPoints ()
    ret.dest:SetPoint ("TOPLEFT", ret.str3, "TOPRIGHT", 12, 0)
    ret.dest:Catch ("OnValueChanged", function (this, evt, newv)
      ksk.copyspacedlg.newname = newv
    end)
    arg = {}
    ypos = ypos - 24

    local xpos = 90
    arg = {
      x = xpos, y = ypos, name = "KSKCopyListDD",
      dwidth = 175, items = KUI.emptydropdown, itemheight = 16,
      title = { text = L["Roll Lists to Copy"] }, mode = "MULTI",
    }
    ret.ltocopy = KUI:CreateDropDown (arg, ret)
    arg = {}
    ypos = ypos - 32

    arg = {
      x = xpos, y = ypos, label =  { text = L["Copy Co-admins"] },
    }
    ret.copyadm = KUI:CreateCheckBox (arg, ret)
    ret.copyadm:Catch ("OnValueChanged", function (this, evt, val)
      ksk.copyspacedlg.do_copyadm = val
    end)
    arg = {}
    ypos = ypos - 24

    arg = {
      x = xpos, y = ypos, label = { text = L["Copy All User Flags"] },
    }
    ret.copyflags = KUI:CreateCheckBox (arg, ret)
    ret.copyflags:Catch ("OnValueChanged", function (this, evt, val)
      ksk.copyspacedlg.do_copyflags = val
    end)
    arg = {}
    ypos = ypos - 24

    arg = {
      x = xpos, y = ypos, label = { text = L["Copy Configuration Options"] },
    }
    ret.copycfg = KUI:CreateCheckBox (arg, ret)
    ret.copycfg:Catch ("OnValueChanged", function (this, evt, val)
      ksk.copyspacedlg.do_copycfg = val
    end)
    arg = {}
    ypos = ypos - 24

    arg = {
      x = xpos, y = ypos, label = { text = L["Copy Item Options"] },
    }
    ret.copyitem = KUI:CreateCheckBox (arg, ret)
    ret.copyitem:Catch ("OnValueChanged", function (this, evt, val)
      ksk.copyspacedlg.do_copyitems = val
    end)
    arg = {}
    ypos = ypos - 24

    ksk.copyspacedlg = ret

    ret.OnAccept = function (this)
      --
      -- First things first, see if we need to create the new configuration
      -- or if we are copying into it.
      --
      if (not ksk.copyspacedlg.newname or ksk.copyspacedlg.newname == "") then
        err (L["invalid configuration name. Please try again."])
        return
      end
      if (ksk.copyspacedlg.newid == 0) then
        ksk.copyspacedlg.newid = ksk:FindConfig (ksk.copyspacedlg.newname) or 0
      end

      if (ksk.copyspacedlg.newid == 0) then
        local rv, ni = ksk:CreateNewConfig (ksk.copyspacedlg.newname, false)
        if (rv) then
          return
        end
        ksk.copyspacedlg.newid = ni
      end

      local newid = ksk.copyspacedlg.newid
      local cfgid = ksk.copyspacedlg.cfgid
      assert (ksk.frdb.configs[newid])

      local dc = ksk.frdb.configs[newid]
      local sc = ksk.frdb.configs[cfgid]

      --
      -- First things first, copy the users. We cannot do a blind copy of
      -- the user ID's as the user may already exist in the configuration
      -- with a different ID, so we have to search the new configuration
      -- for each user. We go through the list twice, the first time
      -- skipping alts, the second time just dealing with alts. For the
      -- various user flags, we have to do them individually, as we may
      -- need to send out events for each change to the new user.
      --
      for k,v in pairs (sc.users) do
        if (not v.main) then
          local du = ksk:FindUser (v.name, newid)
          if (not du) then
            du = ksk:CreateNewUser (v.name, v.class, newid, true, true)
          end
          if (ksk.copyspacedlg.do_copyflags) then
            local fs
            fs = ksk:UserIsEnchanter (k, v.flags, cfgid)
            ksk:SetUserEnchanter (du, fs, newid)
            fs = ksk:UserIsFrozen (k, v.flags, cfgid)
            ksk:SetUserFrozen (du, fs, newid)
          end
        end
      end

      for k,v in pairs (sc.users) do
        if (v.main) then
          local du = ksk:FindUser (v.name, newid)
          if (not du) then
            du = ksk:CreateNewUser (v.name, v.class, newid, true, true)
          end
          if (copyflags) then
            local fs
            fs = ksk:UserIsEnchanter (k, v.flags, cfgid)
            ksk:SetUserEnchanter (du, fs, newid)
            fs = ksk:UserIsFrozen (k, v.flags, cfgid)
            ksk:SetUserFrozen (du, fs, newid)
          end
          local mu = ksk:FindUser (sc.users[v.main].name, newid)
          assert (mu)
          ksk:SetUserIsAlt (du, true, mu, newid)
        end
      end

      --
      -- Now copy the roll lists (if any) we have been asked to copy.
      --
      for k,v in pairs (ksk.copyspacedlg.copylist) do
        if (v == true) then
          --
          -- We can use the handy SMLST event to set the member list.
          -- That event was originally intended for the CSV import
          -- function but it serves our purposes perfectly as we can
          -- set the entire member list with one event. No need to
          -- recreate lists or anything like that.
          --
          local sl = sc.lists[k]
          local dlid = ksk:FindList (sl.name, newid)
          if (not dlid) then
            --
            -- Need to create the list
            --
            local rv, ri = ksk:CreateNewList (sl.name, newid)
            assert (not rv)
            dlid = ri
          end
          local dul = {}
          for kk,vv in ipairs (sl.users) do
            -- Find the user in the new config
            local du = ksk:FindUser (sc.users[vv].name, newid)
            assert (du)
            tinsert (dul, du)
          end
          local dus = tconcat (dul, "")
          ksk:SetMemberList (dus, dlid, newid)

          --
          -- Copy the list options and prepare a CHLST event
          --
          if (ksk.copyspacedlg.do_copycfg) then
            local dl = dc.lists[dlid]
            dl.sortorder = sl.sortorder
            dl.def_rank = sl.def_rank
            dl.strictcfilter = sl.strictcfilter
            dl.strictrfilter = sl.strictrfilter
            if (sl.extralist ~= "0") then
              dl.extralist = ksk:FindList (sc.lists[sl.extralist].name, newid) or "0"
            end
            -- If this changes MUST change in KSK-Comms.lua(CHLST)
            local es = strfmt ("%s:%d:%d:%s:%s:%s", dlid,
              dl.sortorder, dl.def_rank, dl.strictcfilter and "Y" or "N",
              dl.strictrfilter and "Y" or "N", dl.extralist)
            ksk.AddEvent (newid, "CHLST", es)
          end
        end
      end

      --
      -- Next up are the item options, if we have been asked to copy them.
      -- We only copy items that do not exist. If the item exists in the
      -- new config we leave it completely untouched.
      --
      if (ksk.copyspacedlg.do_copyitems) then
        local sil = sc.items
        local dil = dc.items

        for k,v in pairs (sil) do
          if (not dil[k]) then
            local es = k .. ":"
            ksk:AddItem (k, v.ilink, newid)
            K.CopyTable (v, dil[k])
            --
            -- Obviously the UID for assign to next user will be
            -- different, so we adjust for that.
            --
            if (v.user) then
              dil[k].user = ksk:FindUser (sc.users[v.user].name, newid)
              assert (dil[k].user)
            end
            ksk:MakeCHITM (k, dil[k], newid, true)
          end
        end
      end

      --
      -- If we have been asked to preserve all of the config options then
      -- copy them over now, but we will have to adjust the disenchanter
      -- UIDs.
      --
      if (ksk.copyspacedlg.do_copycfg) then
        K.CopyTable (sc.settings, dc.settings)
        for k,v in pairs (sc.settings.denchers) do
          if (v) then
            dc.settings.denchers[k] = ksk:FindUser (sc.users[v].name, newid)
          end
        end
        dc.tethered = sc.tethered
        dc.cfgtype = sc.cfgtype
        dc.owner = ksk:FindUser (sc.users[sc.owner].name, newid)
      end

      --
      -- If they want to copy co-admins do so now.
      --
      if (ksk.copyspacedlg.do_copyadm) then
        for k,v in pairs (sc.admins) do
          local uid = ksk:FindUser (sc.users[k].name, newid)
          assert (uid)
          if (not dc.admins[uid]) then
            ksk:AddAdmin (uid, newid)
          end
        end
      end

      ksk:FullRefresh ()

      ksk.copyspacedlg:Hide ()
      if (ksk.copyspacedlg.isshown) then
        ksk.mainwin:Show ()
      end
    end

    ret.OnCancel = function (this)
      ksk.copyspacedlg:Hide ()
      if (ksk.copyspacedlg.isshown) then
        ksk.mainwin:Show ()
      end
    end
  end

  ksk.copyspacedlg.do_copyadm = false
  ksk.copyspacedlg.do_copyflags = true
  ksk.copyspacedlg.do_copycfg = true
  ksk.copyspacedlg.do_copyraid = false
  ksk.copyspacedlg.do_copyitems = false
  ksk.copyspacedlg.copylist = {}
  ksk.copyspacedlg.newname = newname or ""
  ksk.copyspacedlg.newid = newid or 0
  ksk.copyspacedlg.cfgid = cfgid

  --
  -- Each time we are called we need to populate the dropdown list so that
  -- it has the correct list of lists.
  --
  local function set_list (btn)
    ksk.copyspacedlg.copylist[btn.value] = btn.checked
  end

  local items = {}
  for k,v in pairs (ksk.frdb.configs[cfgid].lists) do
    local ti = { text = v.name, value = k, keep = true, func = set_list }
    ti.checked = function ()
      return ksk.copyspacedlg.copylist[k]
    end
    tinsert (items, ti)
  end
  tsort (items, function (a,b)
    return strlower (a.text) < strlower (b.text)
  end)
  ksk.copyspacedlg.ltocopy:UpdateItems (items)

  ksk.copyspacedlg.copyadm:SetChecked (ksk.copyspacedlg.do_copyadm)
  ksk.copyspacedlg.copyflags:SetChecked (ksk.copyspacedlg.do_copyflags)
  ksk.copyspacedlg.copycfg:SetChecked (ksk.copyspacedlg.do_copycfg)
  ksk.copyspacedlg.copyitem:SetChecked (ksk.copyspacedlg.do_copyitems)

  ksk.copyspacedlg.isshown = shown
  ksk.mainwin:Hide ()
  ksk.copyspacedlg:Show ()


  if (not ksk.copyspacedlg.newid or ksk.copyspacedlg.newid == 0) then
    ksk.copyspacedlg.str4:Hide ()
    ksk.copyspacedlg.dest:Show ()
    ksk.copyspacedlg.dest:SetText (ksk.copyspacedlg.newname)
  else
    ksk.copyspacedlg.dest:Hide ()
    ksk.copyspacedlg.str4:Show ()
    ksk.copyspacedlg.str4:SetText (ksk.copyspacedlg.newname)
  end
  ksk.copyspacedlg.str2:SetText (ksk.frdb.configs[cfgid].name)
end

function ksk:CopyConfigSpace (cfgid, newname, newid)
  copy_space_button (cfgid, newname, newid, ksk.mainwin:IsShown ())
end

local dencher_popup
local which_dencher
local which_dench_lbl

local function select_dencher (btn, lbl, num)
  if (ksk.popupwindow) then
    ksk.popupwindow:Hide ()
    ksk.popupwindow = nil
  end
  local ulist = {}

  which_dencher = num
  which_dench_lbl = lbl

  tinsert (ulist, { value = 0, text = L["None"] })
  for k,v in ipairs (ksk.sortedusers) do
    local ok = true
    for i = 1,6 do
      if (ksk.settings.denchers[i] == v.id) then
        ok = false
      end
    end
    if (ok and ksk:UserIsEnchanter (v.id)) then
      local ti = { value = v.id, text = aclass (ksk.users[v.id]) }
      tinsert (ulist, ti)
    end
  end

  local function pop_func (uid)
    if (uid == 0) then
      ksk.settings.denchers[which_dencher] = nil
      which_dench_lbl:SetText ("")
    else
      which_dench_lbl:SetText (aclass (ksk.users[uid]))
      if (ksk.settings.denchers[which_dencher] ~= uid) then
        ksk.settings.denchers[which_dencher] = uid
      end
    end

    --
    -- If we're in raid, refresh the raid's notion of possible denchers.
    --
    if (ksk.inraid) then
      ksk.raid.denchers = {}
      for i = 1,6 do
        local duid = ksk.settings.denchers[i]
        if (duid) then
          if (ksk.raid.users[duid]) then
            tinsert (ksk.raid.denchers, duid)
          end
        end
      end
    end
    ksk.popupwindow:Hide ()
    ksk.popupwindow = nil
  end

  if (not dencher_popup) then
    dencher_popup = ksk:PopupSelectionList ("KSKDencherPopup",
      ulist, L["Select Enchanter"], 225, 400, btn, 16, 
      function (idx) pop_func (idx) end)
  end
  dencher_popup:UpdateList (ulist)
  dencher_popup:ClearAllPoints ()
  dencher_popup:SetPoint ("TOPLEFT", btn, "TOPRIGHT", 0, dencher_popup:GetHeight() /2)
  dencher_popup:Show ()
  ksk.popupwindow = dencher_popup
end

local function change_cfg (which, val)
  if (ksk.settings[which] ~= val) then
    ksk.settings[which] = val
  end
end

local function rank_editor ()
  if (not ksk.rankpriodialog) then
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
      okbutton = { text = K.ACCEPTSTR },
      cancelbutton = { text = K.CANCELSTR },
    }
    local ret = KUI:CreateDialogFrame (arg)
    arg = {}

    arg = {
      x = 8, y = 0, height = 20, text = L["Guild Rank"],
      font = "GameFontNormal",
    }
    ret.glbl = KUI:CreateStringLabel (arg, ret)
  
    arg.x = 225
    arg.text = L["Priority"]
    ret.plbl = KUI:CreateStringLabel (arg, ret)
    arg = {}

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
      ret[rlbl] = KUI:CreateStringLabel (arg, ret)
      earg.x = 225
      earg.y = earg.y - 24
      ret[rpe] = KUI:CreateEditBox (earg, ret)
      ret[rlbl]:Hide ()
      ret[rpe]:Hide ()
    end

    ret.OnCancel = function (this)
      this:Hide ()
      ksk.mainwin:Show ()
    end

    ret.OnAccept = function (this)
      ksk.settings.rank_prio = {}
      for i = 1, K.guild.numranks do
        local rpe = "rankprio" .. tostring(i)
        local tv = ret[rpe]:GetText ()
        if (tv == "") then
          tv = "1"
        end
        local rrp = tonumber (tv)
        if (rrp < 1) then
          rrp = 1
        end
        if (rrp > 10) then
          rrp = 10
        end
        ksk.settings.rank_prio[i] = rrp
      end
      this:Hide ()
      ksk.mainwin:Show ()
    end

    ksk.rankpriodialog = ret
  end

  local rp = ksk.rankpriodialog
  rp:SetHeight (((K.guild.numranks + 1) * 28) + 50)

  for i = 1, 10 do
    local rlbl = "ranklbl" .. tostring(i)
    local rpe = "rankprio" .. tostring(i)
    rp[rlbl]:Hide ()
    rp[rpe]:Hide ()
  end

  for i = 1, K.guild.numranks do
    local rlbl = "ranklbl" .. tostring(i)
    local rpe = "rankprio" .. tostring(i)
    rp[rlbl]:SetText (K.guild.ranks[i].name)
    rp[rpe]:SetText (tostring (ksk.settings.rank_prio[i] or 1))
    rp[rlbl]:Show ()
    rp[rpe]:Show ()
  end

  rp:Show ()
end

local coadmin_popup

function ksk:InitialiseConfigGUI ()
  local arg

  --
  -- Config panel, loot tab
  --
  local ypos = 0

  local cf = ksk.qf.lootopts
  local tbf = ksk.mainwin.tabs[ksk.CONFIG_TAB].topbar

  arg = {
    x = 0, y = ypos,
    label = { text = L["Auto-open Bid Panel When Corpse Looted"] },
    tooltip = { title = "$$", text = L["TIP001"] },
  }
  cf.autobid = KUI:CreateCheckBox (arg, cf)
  cf.autobid:Catch ("OnValueChanged", function (this, evt, val)
    change_cfg ("auto_bid", val)
  end)
  arg = {}
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, label = { text = L["Silent Bidding"] },
    tooltip = { title = "$$", text = L["TIP002"] },
  }
  cf.silentbid = KUI:CreateCheckBox (arg, cf)
  cf.silentbid:Catch ("OnValueChanged", function (this, evt, val)
    change_cfg ("silent_bid", val)
  end)
  arg = {}

  arg = {
    x = 225, y = ypos, label = { text = L["Display Tooltips in Loot List"] },
    tooltip = { title = "$$", text = L["TIP003"] },
  }
  cf.tooltips = KUI:CreateCheckBox (arg, cf)
  cf.tooltips:Catch ("OnValueChanged", function (this, evt, val)
    change_cfg ("tooltips", val)
  end)
  arg = {}
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, label = { text = L["Enable Chat Message Filter"] },
    tooltip = { title = "$$", text = L["TIP004"] },
  }
  cf.chatfilter = KUI:CreateCheckBox (arg, cf)
  cf.chatfilter:Catch ("OnValueChanged", function (this, evt, val)
    change_cfg ("chat_filter", val)
    -- This will cause the chat filters to be reset
    ksk:UpdateUserSecurity ()
  end)
  arg = {}

  arg = {
    x = 225, y = ypos, label = { text = L["Record Loot Assignment History"] },
    tooltip = { title = "$$", text = L["TIP005"] },
  }
  cf.history = KUI:CreateCheckBox (arg, cf)
  cf.history:Catch ("OnValueChanged", function (this, evt, val, usr)
    change_cfg ("history", val)
    if (usr and not val) then
      ksk.cfg.history = {}
      ksk:RefreshHistory ()
    end
  end)
  arg = {}
  ypos = ypos - 24

  arg = {
    x = 4, y = ypos, name = "KSKAnnounceWhereDropDown",
    label = { text = L["Announce Loot"], pos = "LEFT" },
    itemheight = 16, mode = "SINGLE",
    dwidth = 125, items = {
      { text = L["Nowhere"], value = 0,
        tooltip = { title = "$$", text = L["TIP006.1"] },
      },
      { text = L["In Guild Chat"], value = 1,
        tooltip = { title = "$$", text = L["TIP006.2"] },
      },
      { text = L["In Raid Chat"], value = 2,
        tooltip = { title = "$$", text = L["TIP006.3"] },
      },
    },
    tooltip = { title = "$$", text = L["TIP006"] },
  }
  cf.announcewhere = KUI:CreateDropDown (arg, cf)
  cf.announcewhere:Catch ("OnValueChanged", function (this, evt, newv)
    change_cfg ("announce_where", newv)
  end)
  arg = {}

  local function oaf_checked (this)
    return ksk.settings[this.value]
  end

  local function oaf_func (this)
    change_cfg (this.value, this.checked)
  end

  arg = {
    x = 275, y = ypos, name = "KSKAnnouncementsDropDown", itemheight = 16,
    dwidth = 175, mode = "MULTI", title = { text = L["Other Announcements"],},
    tooltip = { title = "$$", text = L["TIP007"] },
    items = {
      { 
        text = L["Announce Bid List Changes"],
        value = "ann_bidchanges", checked = oaf_checked, func = oaf_func,
        tooltip = { title = "$$", text = L["TIP007.1"] },
      },
      { 
        text = L["Announce Winners in Raid"],
        value = "ann_winners_raid", checked = oaf_checked, func = oaf_func,
        tooltip = { title = "$$", text = L["TIP007.2"] },
      },
      { 
        text = L["Announce Winners in Guild Chat"],
        value = "ann_winners_guild", checked = oaf_checked, func = oaf_func,
        tooltip = { title = "$$", text = L["TIP007.3"] },
      },
      { 
        text = L["Announce Bid Progression"],
        value = "ann_bid_progress", checked = oaf_checked, func = oaf_func,
        tooltip = { title = "$$", text = L["TIP007.4"] },
      },
      { 
        text = L["Usage Message When Bids Open"],
        value = "ann_bid_usage", checked = oaf_checked, func = oaf_func,
        tooltip = { title = "$$", text = L["TIP007.5"] },
      },
      { 
        text = L["Announce Bid / Roll Cancelation"],
        value = "ann_cancel", checked = oaf_checked, func = oaf_func,
        tooltip = { title = "$$", text = L["TIP007.9"] },
      },
      { 
        text = L["Announce When No Successful Bids"],
        value = "ann_no_bids", checked = oaf_checked, func = oaf_func,
        tooltip = { title = "$$", text = L["TIP007.10"] },
      },
      { 
        text = L["Raiders Not on Current List"],
        value = "ann_missing", checked = oaf_checked, func = oaf_func,
        tooltip = { title = "$$", text = L["TIP007.11"] },
      },
    },
  }
  cf.otherannounce = KUI:CreateDropDown (arg, cf)
  arg = {}
  ypos = ypos - 30

  arg = {
    x = 4, y = ypos, name = "KSKDefListDropdown", mode = "SINGLE",
    dwidth = 175, items = KUI.emptydropdown, itemheight = 16,
    label = { text = L["Use Default Roll List"], pos = "LEFT" },
    tooltip = { title = "$$", text = L["TIP010"] },
  }
  cf.deflist = KUI:CreateDropDown (arg, cf)
  ksk.qf.deflistdd = cf.deflist
  cf.deflist:Catch ("OnValueChanged", function (this, evt, nv)
    change_cfg ("def_list", nv)
  end)
  arg = {}
  ypos = ypos - 28

  arg = {
    x = 4, y = ypos, name = "KSKGDefRankDropdown", mode = "SINGLE",
    dwidth = 175, items = KUI.emptydropdown, itemheight = 16,
    label = { text = L["Initial Guild Rank Filter"], pos = "LEFT" },
    tooltip = { title = "$$", text = L["TIP011"] },
  }
  cf.gdefrank = KUI:CreateDropDown (arg, cf)
  ksk.qf.gdefrankdd = cf.gdefrank
  cf.gdefrank:Catch ("OnValueChanged", function (this, evt, nv)
    change_cfg ("def_rank", nv)
  end)
  arg = {}
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, label = {text = L["Hide Absent Members in Loot Lists"] },
    tooltip = { title = "$$", text = L["TIP012"] },
  }
  cf.hideabsent = KUI:CreateCheckBox (arg, cf)
  cf.hideabsent:Catch ("OnValueChanged", function (this, evt, val)
    change_cfg ("hide_absent", val)
    ksk:RefreshLootMembers ()
  end)
  arg = {}
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, label = { text = L["Auto-assign Loot When Bids Close"] },
  }
  cf.autoloot = KUI:CreateCheckBox (arg, cf)
  cf.autoloot:Catch ("OnValueChanged", function (this, evt, val)
    change_cfg ("auto_loot", val)
  end)
  arg = {}
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, name = "KSKBidThresholdDropDown",
    label = { text = L["Bid / Roll Threshold"], pos = "LEFT" },
    itemheight = 16, mode = "COMPACT", dwidth = 135, items = {
      { text = L["None"], value = 0 },
      { text = ITEM_QUALITY2_DESC, value = 2, color = ITEM_QUALITY_COLORS[2] },
      { text = ITEM_QUALITY3_DESC, value = 3, color = ITEM_QUALITY_COLORS[3] },
      { text = ITEM_QUALITY4_DESC, value = 4, color = ITEM_QUALITY_COLORS[4] },
    },
    tooltip = { title = "$$", text = L["TIP095"] },
  }
  cf.threshold = KUI:CreateDropDown (arg, cf)
  cf.threshold:Catch ("OnValueChanged", function (this, evt, newv, usr)
    change_cfg ("bid_threshold", newv)
    cf.denchbelow:SetEnabled (newv ~= 0)
  end)
  ypos = ypos - 30

  arg = {
    x = 0, y = ypos,
    label = { text = L["Auto-disenchant Items Below Threshold"] },
    tooltip = { title = "$$", text = L["TIP096"] },
  }
  cf.denchbelow = KUI:CreateCheckBox (arg, cf)
  cf.denchbelow:Catch ("OnValueChanged", function (this, evt, val)
    change_cfg ("disenchant_below", val)
  end)
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, label = { text = L["Use Guild Rank Priorities"] },
    tooltip = { title = "$$", text = L["TIP013"] },
  }
  cf.rankprio = KUI:CreateCheckBox (arg, cf)
  cf.rankprio:Catch ("OnValueChanged", function (this, evt, val)
    change_cfg ("use_ranks", val)
    cf.rankedit:SetEnabled (val)
  end)
  arg = {}

  arg = {
    x = 180, y = ypos+2, width = 50, height = 24, text = L["Edit"],
    enabled = false,
    tooltip = { title = "$$", text = L["TIP014"] },
  }
  cf.rankedit = KUI:CreateButton (arg, cf)
  cf.rankedit:ClearAllPoints ()
  cf.rankedit:SetPoint ("TOPLEFT", cf.rankprio, "TOPRIGHT", 16, 0)
  cf.rankedit:Catch ("OnClick", function (this, evt)
    ksk.mainwin:Hide ()
    K:UpdatePlayerAndGuild ()
    rank_editor ()
  end)
  arg = {}
  ypos = ypos - 30

  arg = {
    x = 4, y = ypos, width = 300, font="GameFontNormal",
    text = L["When there are no successful bids ..."],
  }
  cf.nobidlbl = KUI:CreateStringLabel (arg, cf)
  arg = {}
  ypos = ypos - 20

  arg = {
    x = 0, y = ypos, label = { text = L["Assign BoE Items to Master Looter"] },
    tooltip = { title = "$$", text = L["TIP015"] },
  }
  cf.boetoml = KUI:CreateCheckBox (arg, cf)
  cf.boetoml:Catch ("OnValueChanged", function (this, evt, val)
    change_cfg ("boe_to_ml", val)
  end)
  arg = {}

  arg = {
    x = 275, y = ypos, label = { text = L["Try Open Roll"] },
    tooltip = { title = "$$", text = L["TIP016"] },
  }
  cf.tryroll = KUI:CreateCheckBox (arg, cf)
  cf.tryroll:Catch ("OnValueChanged", function (this, evt, val)
    change_cfg ("try_roll", val)
  end)
  arg = {}
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, label = { text = L["Assign To Enchanter"] },
    tooltip = { title = "$$", text = L["TIP017"] },
  }
  cf.dench = KUI:CreateCheckBox (arg, cf)
  cf.dench:Catch ("OnValueChanged", function (this, evt, val)
    change_cfg ("disenchant", val)
    cf.dencher1:SetEnabled (val)
    cf.denchbut1:SetEnabled (val)
    cf.dencher2:SetEnabled (val)
    cf.denchbut2:SetEnabled (val)
    cf.dencher3:SetEnabled (val)
    cf.denchbut3:SetEnabled (val)
    cf.dencher4:SetEnabled (val)
    cf.denchbut4:SetEnabled (val)
    cf.dencher5:SetEnabled (val)
    cf.denchbut5:SetEnabled (val)
    cf.dencher6:SetEnabled (val)
    cf.denchbut6:SetEnabled (val)
  end)
  arg = {}
  ypos = ypos - 24

  arg = { x = 25, y = ypos, border = true, autosize = false,
    height=20, width = 150, text = "", enabled = false,
  }
  local barg = {
    x = 180, y = ypos+2, width = 50, height = 24, text = L["Select"],
    enabled = false,
    tooltip = { title = L["Assign To Enchanter"],  text = L["TIP018"] },
  }
  cf.dencher1 = KUI:CreateStringLabel (arg, cf)
  cf.denchbut1 = KUI:CreateButton (barg, cf)
  cf.denchbut1:Catch ("OnClick", function (this, evt)
    select_dencher (this, cf.dencher1, 1)
  end)

  arg.x = 250
  barg.x = 405
  cf.dencher2 = KUI:CreateStringLabel (arg, cf)
  cf.denchbut2 = KUI:CreateButton (barg, cf)
  cf.denchbut2:Catch ("OnClick", function (this, evt)
    select_dencher (this, cf.dencher2, 2)
  end)

  ypos = ypos - 24
  arg.x = 25
  arg.y = ypos
  barg.x = 180
  barg.y = ypos+2
  cf.dencher3 = KUI:CreateStringLabel (arg, cf)
  cf.denchbut3 = KUI:CreateButton (barg, cf)
  cf.denchbut3:Catch ("OnClick", function (this, evt)
    select_dencher (this, cf.dencher3, 3)
  end)

  arg.x = 250
  barg.x = 405
  cf.dencher4 = KUI:CreateStringLabel (arg, cf)
  cf.denchbut4 = KUI:CreateButton (barg, cf)
  cf.denchbut4:Catch ("OnClick", function (this, evt)
    select_dencher (this, cf.dencher4, 4)
  end)

  ypos = ypos - 24
  arg.x = 25
  arg.y = ypos
  barg.x = 180
  barg.y = ypos+2
  cf.dencher5 = KUI:CreateStringLabel (arg, cf)
  cf.denchbut5 = KUI:CreateButton (barg, cf)
  cf.denchbut5:Catch ("OnClick", function (this, evt)
    select_dencher (this, cf.dencher5, 5)
  end)

  arg.x = 250
  barg.x = 405
  cf.dencher6 = KUI:CreateStringLabel (arg, cf)
  cf.denchbut6 = KUI:CreateButton (barg, cf)
  cf.denchbut6:Catch ("OnClick", function (this, evt)
    select_dencher (this, cf.dencher6, 6)
  end)
  arg = {}
  barg = {}
  ypos = ypos - 24

  --
  -- Config panel, admin tab
  --
  local cf = ksk.qf.rollopts
  ypos = 0

  arg = {
    label = { text = L["Open Roll Timeout"] },
    x = 0, y = ypos, minval = 10, maxval = 60,
    tooltip = { title = "$$", text = L["TIP008"] },
  }
  cf.rolltimeout = KUI:CreateSlider (arg, cf)
  cf.rolltimeout:Catch ("OnValueChanged", function (this, evt, newv)
    change_cfg ("roll_timeout", newv)
  end)

  arg = {
    label = { text = L["Roll Timeout Extension"] },
    x = 225, y = ypos, minval = 5, maxval = 30,
    tooltip = { title = "$$", text = L["TIP009"] },
  }
  cf.rollextend = KUI:CreateSlider (arg, cf)
  cf.rollextend:Catch ("OnValueChanged", function (this, evt, newv)
    change_cfg ("roll_extend", newv)
  end)
  ypos = ypos - 48

  arg = {
    x = 0, y = ypos, label = {text = L["Enable Off-spec (101-200) Rolls"] },
    tooltip = { title = "$$", text = L["TIP092"] },
  }
  cf.enableoffspec = KUI:CreateCheckBox (arg, cf)
  cf.enableoffspec:Catch ("OnValueChanged", function (this, evt, val)
    change_cfg ("offspec_rolls", val)
  end)
  arg = {}
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, label = {text = L["Enable Suicide Rolls by Default"] },
    tooltip = { title = "$$", text = L["TIP093"] },
  }
  cf.suicideroll = KUI:CreateCheckBox (arg, cf)
  cf.suicideroll:Catch ("OnValueChanged", function (this, evt, val)
    change_cfg ("suicide_rolls", val)
  end)
  arg = {}
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, label = {text = L["Usage Message When Rolls Open"] },
    tooltip = { title = "$$", text = L["TIP007.6"] },
  }
  cf.rollusage = KUI:CreateCheckBox (arg, cf)
  cf.rollusage:Catch ("OnValueChanged", function (this, evt, val)
    change_cfg ("ann_roll_usage", val)
  end)
  arg = {}
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, label = {text = L["Announce Open Roll Countdown"] },
    tooltip = { title = "$$", text = L["TIP007.7"] },
  }
  cf.countdown = KUI:CreateCheckBox (arg, cf)
  cf.countdown:Catch ("OnValueChanged", function (this, evt, val)
    change_cfg ("ann_countdown", val)
  end)
  arg = {}
  ypos = ypos - 24

  arg = {
    x = 0, y = ypos, label = {text = L["Announce Open Roll Ties"] },
    tooltip = { title = "$$", text = L["TIP007.8"] },
  }
  cf.ties = KUI:CreateCheckBox (arg, cf)
  cf.ties:Catch ("OnValueChanged", function (this, evt, val)
    change_cfg ("ann_roll_ties", val)
  end)
  arg = {}
  ypos = ypos - 24

  --
  -- Config panel, admin tab
  --
  local cf = ksk.qf.cfgadmin
  local ls = cf.vsplit.leftframe
  local rs = cf.vsplit.rightframe

  arg = {
    height = 50,
    rightsplit = true,
    name = "KSKCfgAdminLSHSplit",
  }
  ls.hsplit = KUI:CreateHSplit (arg, ls)
  arg = {}
  local tl = ls.hsplit.topframe
  local bl = ls.hsplit.bottomframe

  arg = {
    height = 105,
    name = "KSKCfgAdminRSHSplit",
    leftsplit = true,
    topanchor = true,
  }
  rs.hsplit = KUI:CreateHSplit (arg, rs)
  arg = {}
  local tr = rs.hsplit.topframe
  local br = rs.hsplit.bottomframe
  ksk.qf.cfgopts = tr

  arg = {
    height = 35,
    name = "KSKCfgAdminRSHSplit2",
    leftsplit = true,
  }
  br.hsplit = KUI:CreateHSplit (arg, br)
  arg = {}
  local about = br.hsplit.bottomframe
  local coadmins = br.hsplit.topframe
  ksk.qf.coadmins = coadmins

  arg = {
    x = 0, y = 0, width = 80, height = 24, text = L["Create"],
    tooltip = { title = "$$", text = L["TIP019"] },
  }
  bl.createbutton = KUI:CreateButton (arg, bl)
  bl.createbutton:Catch ("OnClick", function (this, evt)
    new_space_button ()
  end)
  arg = {}

  arg = {
    x = 95, y = 0, width = 80, height = 24, text = L["Delete"],
    tooltip = { title = "$$", text = L["TIP020"] },
  }
  bl.deletebutton = KUI:CreateButton (arg, bl)
  bl.deletebutton:Catch ("OnClick", function (this, evt)
    ksk:DeleteConfig (admincfg, true)
  end)
  arg = {}
  ksk.qf.cfgdelbutton = bl.deletebutton

  arg = {
    x = 0, y = -25, width = 80, height = 24, text = L["Rename"],
    tooltip = { title = "$$", text = L["TIP021"] },
  }
  bl.renamebutton = KUI:CreateButton (arg, bl)
  bl.renamebutton:Catch ("OnClick", function (this, evt)
    rename_space_button (admincfg)
  end)
  arg = {}
  ksk.qf.cfgrenbutton = bl.renamebutton

  arg = {
    x = 95, y = -25, width = 80, height = 24, text = L["Copy"],
    tooltip = { title = "$$", text = L["TIP022"] },
  }
  bl.copybutton = KUI:CreateButton (arg, bl)
  bl.copybutton:Catch ("OnClick", function (this, evt)
    copy_space_button (admincfg, nil, nil, true)
  end)
  arg = {}
  ksk.qf.cfgcopybutton = bl.copybutton

  --
  -- We make the config space panel a scrolling list in case they have lots
  -- of configs (unlikely but hey, you never know).
  --
  arg = {
    name = "KSKConfigScrollList",
    itemheight = 16,
    newitem = function (objp, num)
      return KUI.NewItemHelper (objp, num, "KSKConfigButton", 160, 16,
        nil, nil, nil, nil)
      end,
    setitem = function (objp, idx, slot, btn)
      return KUI.SetItemHelper (objp, btn, idx,
        function (op, ix)
          return ksk.frdb.configs[sortedconfigs[ix].id].name
        end)
      end,
    selectitem = config_selectitem,
    highlightitem = function (objp, idx, slot, btn, onoff)
      return KUI.HighlightItemHelper (objp, idx, slot, btn, onoff)
    end,
  }
  tl.slist = KUI:CreateScrollList (arg, tl)
  ksk.qf.cfglist = tl.slist
  arg = {}

  local bdrop = {
    bgFile = KUI.TEXTURE_PATH .. "TDF-Fill",
    tile = true,
    tileSize = 32,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
  }
  tl.slist:SetBackdrop (bdrop)

  --
  -- These are the actual configurable options for a config space. They
  -- are shown in the top right panel. Below them is some version information
  -- and contact information.
  --
  arg = {
    x = 0, y = 0, name = "KSKConfigOWnerDD", itemheight = 16,
    dwidth = 125, mode = "SINGLE", items = KUI.emptydropdown,
    label = { pos = "LEFT", text = L["Config Owner"] },
    tooltip = { title = "$$", text = L["TIP023"] },
  }
  tr.cfgowner = KUI:CreateDropDown (arg, tr)
  ksk.qf.cfgownerdd = tr.cfgowner
  tr.cfgowner:Catch ("OnValueChanged", function (this, evt, newv, user)
    if (user) then
      local lcf = ksk.frdb.configs[admincfg]
      lcf.owner = nuid
      ksk:UpdateUserSecurity ()
      ksk:RefreshCSData ()
      local en = ksk.csdata[admincfg].isadmin == 2 and true or false
      tr.cfgowner:SetEnabled (en)
      tr.tethered:SetEnabled (en)
      if (not ksk:CanChangeConfigType ()) then
        en = false
      end
      tr.cfgtype:SetEnabled (en)
      ksk:RefreshConfigSpaces ()
    end
  end)
  arg = {}

  arg = {
    x = 0, y = -30, label = { text = L["Alts Tethered to Mains"] },
    tooltip = { title = "$$", text = L["TIP024"] },
  }
  tr.tethered = KUI:CreateCheckBox (arg, tr)
  tr.tethered:Catch ("OnValueChanged", function (this, evt, val)
    local lcf = ksk.frdb.configs[admincfg]
    lcf.tethered = val
    ksk:FixupLists (admincfg)
    ksk:RefreshLists ()
  end)
  arg = {}

  arg = {
    name = "KSKCfgTypeDropDown", enabled = false, itemheight = 16,
    x = 4, y = -58, label = { text = L["Config Type"], pos = "LEFT" },
    dwidth = 100, mode = "SINGLE", width = 75,
    tooltip = { title = "$$", text = L["TIP025"] },
    items = {
      { text = L["Guild"], value = ksk.CFGTYPE_GUILD },
      { text = L["PUG"], value = ksk.CFGTYPE_PUG },
    },
  }
  tr.cfgtype = KUI:CreateDropDown (arg, tr)
  tr.cfgtype:Catch ("OnValueChanged", function (this, evt, newv)
    local lcf = ksk.frdb.configs[admincfg]
    lcf.cfgtype = newv
  end)
  arg = {}

  arg = {
    x = 0, y = 2, height = 12, font = "GameFontNormalSmall",
    autosize = false, width = 290, text = L["ABOUT1"],
  }
  about.str1 = KUI:CreateStringLabel (arg, about)

  arg = {
    x = 0, y = -10, height = 12, font = "GameFontNormalSmall",
    autosize = false, width = 290,
    text = strfmt(L["ABOUT2"], white ("cruciformer@gmail.com"))
  }
  about.str2 = KUI:CreateStringLabel (arg, about)

  arg = {
    x = 0, y = -22, height = 12, font = "GameFontNormalSmall",
    autosize = false, width = 290,
    text = strfmt(L["ABOUT3"], white ("http://kahluamod.com/ksk"))
  }
  about.str2 = KUI:CreateStringLabel (arg, about)

  arg = {
    x = "CENTER", y = 0, font = "GameFontNormal", text = L["Co-admins"],
    border = true, width = 125, justifyh = "CENTER",
  }
  coadmins.str1 = KUI:CreateStringLabel (arg, coadmins)
  arg = {}

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
  coadmins.add = KUI:CreateButton (arg, coadmins)
  coadmins.add:Catch ("OnClick", function (this, evt, ...)
    local ulist = {}
    local cc = ksk.frdb.configs[admincfg]
    local cul = ksk.frdb.configs[admincfg].users
    if (cc.nadmins == 36) then
      err (L["maximum number of co-admins (36) reached"])
      return
    end
    if (ksk.popupwindow) then
      ksk.popupwindow:Hide ()
      ksk.popupwindow = nil
    end
    for k,v in pairs (cul) do
      if (not cc.admins[k] and k ~= cc.owner) then
        tinsert (ulist, { value = k, text = aclass (cul[k]) })
      end
    end
    tsort (ulist, function (a, b)
      return cul[a.value].name < cul[b.value].name
    end)
    if (#ulist == 0) then
      return
    end

    local function pop_func (cauid)
      ksk:AddAdmin (cauid, admincfg)
      ksk.popupwindow:Hide ()
      ksk.popupwindow = nil
      ksk:RefreshCoadmins ()
    end

    if (not coadmin_popup) then
      coadmin_popup = ksk:PopupSelectionList ("KSKCoadminAddPopup",
        ulist, L["Select Co-admin"], 200, 400, this, 16, pop_func)
    else
      coadmin_popup:UpdateList (ulist)
    end
    coadmin_popup:ClearAllPoints ()
    coadmin_popup:SetPoint ("TOPLEFT", this, "TOPRIGHT", 0, coadmin_popup:GetHeight() / 2)
    ksk.popupwindow = coadmin_popup
    coadmin_popup:Show ()
  end)
  arg = {}
  ksk.qf.coadadd = coadmins.add

  arg = {
    x = 200, y = -48, text = L["Delete"], width = 90, height = 24,
    tooltip = { title = "$$", text = L["TIP027"] },
    enabled = false,
  }
  coadmins.del = KUI:CreateButton (arg, coadmins)
  coadmins.del:Catch ("OnClick", function (this, evt, ...)
    if (not coadsel or not admincfg) then
      return
    end
    ksk:DeleteAdmin (coadsel, admincfg)
  end)
  arg = {}
  ksk.qf.coaddel = coadmins.del

  local sframe = MakeFrame ("Frame", nil, coadmins)
  coadmins.sframe = sframe
  sframe:ClearAllPoints ()
  sframe:SetPoint ("TOPLEFT", coadmins, "TOPLEFT", 0, -24)
  sframe:SetPoint ("BOTTOMLEFT", coadmins, "BOTTOMLEFT", 0, 0)
  sframe:SetWidth (190)

  arg = {
    name = "KSKCoadminScrollList",
    itemheight = 16,
    newitem = function (objp, num)
      return KUI.NewItemHelper (objp, num, "KSKCoadminButton", 160, 16,
        nil, nil, nil, nil)
      end,
    setitem = function (objp, idx, slot, btn)
      return KUI.SetItemHelper (objp, btn, idx,
        function (op, ix)
          local ul = ksk.frdb.configs[admincfg].users
          return aclass(ul[sortedadmins[ix]])
        end)
      end,
    selectitem = clist_selectitem,
    highlightitem = function (objp, idx, slot, btn, onoff)
      return KUI.HighlightItemHelper (objp, idx, slot, btn, onoff)
    end,
  }
  coadmins.slist = KUI:CreateScrollList (arg, coadmins.sframe)
  arg = {}
  ksk.qf.coadminscroll = coadmins.slist

  initdone = true
end

function ksk:RefreshCoadmins ()
  if (not initdone) then
    return
  end
  if (not admincfg) then
    ksk.qf.coadminscroll.itemcount = 0
    ksk.qf.coadminscroll:UpdateList ()
    return
  end

  sortedadmins = {}
  ownerlist = {}
  coadsel = nil

  local tc = ksk.frdb.configs[admincfg]
  local ul = ksk.frdb.configs[admincfg].users

  for k,v in pairs (tc.admins) do
    tinsert (sortedadmins, k)
  end
  tsort (sortedadmins, function (a, b)
    return ul[a].name < ul[b].name
  end)

  for k,v in pairs (sortedadmins) do
    tinsert (ownerlist, { text = aclass (ul[v]), value = v })
  end

  ksk.qf.coadminscroll.itemcount = #sortedadmins
  ksk.qf.coadminscroll:UpdateList ()
  ksk.qf.coadminscroll:SetSelected (nil)

  ksk.qf.cfgownerdd:UpdateItems (ownerlist)
  ksk.qf.cfgownerdd:SetValue (tc.owner)
  ksk:RefreshSyncers ()
end

function ksk:RefreshConfigSpaces ()
  local vt = {}
  sortedconfigs = {}
  ksk.frdb.configs = ksk.frdb.configs
  ksk.currentid = ksk.frdb.defconfig
  ksk.cfg = ksk.frdb.configs[ksk.currentid]
  ksk.users = ksk.frdb.configs[ksk.currentid].users
  ksk.settings = ksk.frdb.configs[ksk.currentid].settings
  ksk.lists = ksk.frdb.configs[ksk.currentid].lists
  ksk.items = ksk.frdb.configs[ksk.currentid].items
  ksk:RefreshCSData ()
  ksk.csd = ksk.csdata[ksk.currentid]
  ksk:UpdateUserSecurity ()

  local oldid = admincfg or ""
  local oldidx = nil
  admincfg = nil

  for k,v in pairs(ksk.frdb.configs) do
    local ent = {id = k }
    tinsert (sortedconfigs, ent)
  end
  tsort (sortedconfigs, function (a, b)
    return strlower(ksk.frdb.configs[a.id].name) < strlower(ksk.frdb.configs[b.id].name)
  end)

  for k,v in ipairs(sortedconfigs) do
    vt[k] = { text = ksk.frdb.configs[v.id].name, value = v.id }
    if (ksk.csdata[v.id].isadmin == 2) then
      vt[k].color = {r = 0, g = 1, b = 0 }
    else
      vt[k].color = {r = 1, g = 1, b = 1 }
    end
    if (v.id == oldid) then
      oldidx = k
    end
  end

  ksk.qf.cfgsel:UpdateItems (vt)
  vt = nil

  ksk.qf.cfglist.itemcount = ksk.frdb.nconfigs
  ksk.qf.cfglist:UpdateList ()
  ksk.qf.cfglist:SetSelected (oldidx)

  for k,v in pairs (ksk.csdata) do
    if (not ksk.frdb.configs[k]) then
      ksk.csdata[k] = nil
    end
  end

  ksk:SetDefaultConfig (ksk.currentid, true, true)
  --
  -- This will cause ksk:SetDefaultConfig() to be called. However, it does
  -- not "force" the config change, so SetDefaultConfig will bail early
  -- since we just called it above with force set.
  --
  ksk.qf.cfgsel:SetValue (ksk.currentid)
end

function ksk:SetDefaultConfig (cfgid, silent, force)
  if (ksk.frdb.defconfig ~= cfgid or force) then
    ksk.frdb.defconfig = cfgid
    ksk.currentid = cfgid
    ksk.cfg = ksk.frdb.configs[cfgid]
    ksk.settings = ksk.frdb.configs[cfgid].settings
    if (ksk.initialised) then
      ksk.qf.synctopbar:SetCurrentCRC ()
    end
    ksk.settings = ksk.frdb.configs[cfgid].settings
    ksk.users = ksk.frdb.configs[cfgid].users
    ksk.lists = ksk.frdb.configs[cfgid].lists
    ksk.items = ksk.frdb.configs[cfgid].items
    ksk.list = nil
    ksk.members = nil
    ksk.listid = nil
    ksk.memberid = nil
    ksk.userid = nil
    ksk.itemid = nil
    ksk.lootmemberid = nil
    ksk.lootmembers = nil
    ksk.lootlistid = nil
    ksk.lootlist = nil
    ksk.sortedlists = nil
    ksk:RefreshCSData ()
    ksk.csd = ksk.csdata[cfgid]
    ksk:UpdateUserSecurity ()
    ksk.missing = {}
    ksk.nmissing = 0

    if (ksk.initialised) then
      if (not silent) then
        ksk.info (L["NOTICE: default configuration changed to %q."],
          white (ksk.frdb.configs[cfgid].name))
      end

      ksk:RefreshUsers ()
      ksk:UpdateUserSecurity ()
      ksk:RefreshLists ()
      ksk:RefreshItemList ()
      ksk:RefreshHistory ()
      ksk:UpdateAllConfigSettings ()
      ksk:RefreshMembership ()
      ksk:RefreshSyncers (true)
      ksk:RefreshRaid (true)
      if (not ksk.csd.isadmin) then
        if (not silent) then
          ksk.info (L["you are not an administrator of this configuration. Your access to it is read-only."])
        end
      end
    end
  end
end

local silent_delete = false

local function real_delete_config (cfgid)
  if (not silent_delete) then
    info (L["configuration %q deleted."], white (ksk.frdb.configs[cfgid].name))
  end

  ksk.frdb.configs[cfgid] = nil
  ksk.csdata[cfgid] = nil
  ksk.frdb.nconfigs = ksk.frdb.nconfigs - 1
  if (ksk.frdb.defconfig == cfgid) then
    local nid = next(ksk.frdb.configs)
    ksk:SetDefaultConfig (nid, ksk.frdb.tempcfg)
    admincfg = nid
  end

  if (admincfg == cfgid) then
    admincfg = nil
  end
  ksk:FullRefresh ()
end

function ksk:DeleteConfig (cfgid, show, private)
  if (ksk.frdb.nconfigs == 1 and not private) then
    err (L["cannot delete configuration %q - KonferSK requires at least one configuration."], white (ksk.frdb.configs[cfgid].name))
    return true
  end

  if (private) then
    local oldsilent = silent_delete
    silent_delete = true
    real_delete_config (cfgid)
    silent_delete = oldsilent
    return
  end

  local isshown = show or ksk.mainwin:IsShown ()
  ksk.mainwin:Hide ()

  ksk:ConfirmationDialog (L["Delete Configuration"], L["DELMSG"],
    ksk.frdb.configs[cfgid].name, real_delete_config, cfgid, isshown)

  return false
end

function ksk:CreateNewConfig (name, initial, new, nouser, mykey)
  local lname = strlower(name)

  if (strfind (name, ":")) then
    err (L["invalid configuration name. Please try again."])
    return true
  end

  for k,v in pairs (ksk.frdb.configs) do
    if (strlower(v.name) == lname) then
      err (L["configuration %q already exists. Try again."], white (name))
      return true
    end
  end

  ksk.frdb.nconfigs = ksk.frdb.nconfigs + 1

  local newkey
  if (mykey) then
    newkey = mykey
  else
    newkey = ksk:CreateNewID (name)
  end
  ksk.frdb.configs[newkey] = {}
  ksk.csdata[newkey] = {}
  ksk.csdata[newkey].reserved = {}
  local sp = ksk.frdb.configs[newkey]
  sp.name = name
  sp.tethered = false
  sp.cfgtype = ksk.CFGTYPE_PUG
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

  K.CopyTable (self.defaults, sp.settings)
  if (not nouser) then
    sp.nusers = 1
    sp.users["0001"] = { name = K.player.player, class = K.player.class,
      role = 0, flags = "" }
    sp.owner = "0001"
    ksk.csdata[newkey].myuid = uid
    ksk.info (L["configuration %q created."], white (name))
    sp.nadmins = 1
    sp.admins["0001"] = { id = "0" }
  end

  if (new) then
    ksk:SetDefaultConfig (newkey, ksk.frdb.tempcfg)
  end

  if (initial) then
    return false, newkey
  end

  if (ksk.frdb.tempcfg) then
    ksk:SetDefaultConfig (newkey, true, true)
    silent_delete = true
    real_delete_config ("1")
    silent_delete = false
    ksk.frdb.tempcfg = nil
  end

  --
  -- If we have no guild configs, and we are the GM or an officer, make this
  -- a guild config initially. They can change it immediately if this is wrong.
  --
  if (K.player.isgm or K.player.isofficer) then
    local ng = 0
    for k,v in pairs (ksk.frdb.configs) do
      if (v.cfgtype == ksk.CFGTYPE_GUILD) then
        ng = ng + 1
      end
    end
    if (ng == 0) then
      sp.cfgtype = ksk.CFGTYPE_GUILD
    end
  end

  ksk:FullRefresh ()
  return false, newkey
end

function ksk:RenameConfig (cfgid, newname)
  if (ksk:CheckPerm ()) then
    return true
  end

  if (not ksk.frdb.configs[cfgid]) then
    return true
  end

  local oldname = ksk.frdb.configs[cfgid].name
  info (L["NOTICE: configuration %q renamed to %q."], white (oldname),
    white (newname))
  ksk.frdb.configs[cfgid].name = newname
  ksk:FullRefresh ()

  return false
end

function ksk:FindConfig (name)
  local lname = strlower(name)
  for k,v in pairs (ksk.frdb.configs) do
    if (strlower(v.name) == lname) then
      return k
    end
  end
  return nil
end

function ksk:AddAdmin (uid, cfgid, nocmd)
  assert (uid)
  assert (cfgid)

  local pcc = ksk.frdb.configs[cfgid]
  local newid
  for i = 1, 36 do
    local id = strsub (adminidseq, i, i)
    local found = false
    for k,v in pairs (pcc.admins) do
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
  assert (newid, "fatal logic bug somewhere!")

  -- Must add the event BEFORE we add the admin
  ksk.AddEvent (cfgid, "MKADM", uid, newid)
  pcc.nadmins = pcc.nadmins + 1
  pcc.admins[uid] = { id = newid }
end

function ksk:DeleteAdmin (uid, cfg, nocmd)
  local cfg = cfg or ksk.currentid
  local cp = ksk.frdb.configs[cfg]

  if (not cp.admins[uid]) then
    return
  end
  cp.nadmins = cp.nadmins - 1
  cp.admins[uid] = nil
  if (cp.nadmins == 1) then
    cp.syncing = nil
    cp.lastevent = 0
    cp.admins[cp.owner].lastevent = nil
    cp.admins[cp.owner].sync = nil
  end

  if (not nocmd) then
    ksk.AddEvent (cfg, "RMADM", uid, true)
  end

  ksk:RefreshCoadmins ()
end
