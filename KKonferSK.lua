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

local MAJOR= "KKonferSK"
local MINOR = tonumber ("@revision@")
local MINOR = 1 -- @debug-delete@
local K,KM = LibStub:GetLibrary("KKore")
local H = LibStub:GetLibrary("KKoreHash")
local DB = LibStub:GetLibrary("KKoreDB")
local KUI = LibStub:GetLibrary("KKoreUI")

if (not K) then
  error ("KahLua KonferSK: could not find KahLua Kore.", 2)
end

if (tonumber(KM) < 731) then
  error ("KahLua KonferSK: outdated KahLua Kore. Please update all KahLua addons.")
end

if (not H) then
  error ("KahLua KonferSK: could not find KahLua Kore Hash library.", 2)
end

if (not KUI) then
  error ("KahLua KonferSK: could not find KahLua Kore UI library.", 2)
end

local L = K:GetI18NTable("KKonferSK", false)

ksk = K:NewAddon(nil, MAJOR, MINOR, L["Suicide Kings loot distribution system."], L["MODNAME"], L["CMDNAME"] )
if (not ksk) then
  error ("KahLua KonferSK: addon creation failed.")
end

ksk.version = MINOR
ksk.protocol = 8        -- Protocol version
ksk.dbversion = 16
ksk.L = L
ksk.CHAT_MSG_PREFIX = "KSK"
ksk.initialised = false
ksk.allclasses = "111111111111"
ksk.maxlevel = K.maxlevel

ksk.KUI = KUI
local MakeFrame = KUI.MakeFrame

-- Local aliases for global or Lua library functions
local _G = _G
local tinsert = table.insert
local tremove = table.remove
local tsort = table.sort
local setmetatable = setmetatable
local tconcat = table.concat
local tostring = tostring
local GetTime = GetTime
local min = math.min
local max = math.max
local strfmt = string.format
local strsub = string.sub
local strlen = string.len
local strfind = string.find
local strlower = string.lower
local gmatch = string.gmatch
local match = string.match
local xpcall, pcall = xpcall, pcall
local pairs, next, type = pairs, next, type
local select, assert, loadstring = select, assert, loadstring
local printf = K.printf

local admin_hooks_registered = nil
local ml_hooks_registered = nil
local chat_filters_installed = nil

ksk.LISTS_TAB = 1
ksk.LISTS_MEMBERS_TAB = 1
ksk.LISTS_CONFIG_TAB = 2
ksk.LOOT_TAB = 2
ksk.LOOT_ASSIGN_TAB = 1
ksk.LOOT_ITEMS_TAB = 2
ksk.LOOT_HISTORY_TAB = 3
ksk.USERS_TAB = 3
ksk.SYNC_TAB = 4
ksk.CONFIG_TAB = 5
ksk.CONFIG_LOOT_TAB = 1
ksk.CONFIG_ROLLS_TAB = 2
ksk.CONFIG_ADMIN_TAB = 3
ksk.NON_ADMIN_THRESHOLD = ksk.USERS_TAB
ksk.NON_ADMIN_CONFIG_THRESHOLD = ksk.CONFIG_ROLLS_TAB
ksk.CFGTYPE_GUILD = 1
ksk.CFGTYPE_PUG = 2

local ucolor = K.ucolor
local ecolor = K.ecolor
local icolor = K.icolor

local function debug(lvl,...)
  K.debug(L["MODNAME"], lvl, ...)
end

local function err(msg, ...)
  local str = L["MODTITLE"] .. " " .. L["error: "] .. strfmt(msg, ...)
  K.printf (K.ecolor, "%s", str)
end

local function info(msg, ...)
  local str = L["MODTITLE"] .. ": " .. strfmt(msg, ...)
  K.printf (K.icolor, "%s", str)
end

ksk.debug = debug
ksk.err = err
ksk.info = info

_G["KKonfer"] = _G["KKonfer"] or {}
local KKonfer = _G["KKonfer"]
KKonfer["..."] = KKonfer["..."] or {}

local me = KKonfer["ksk"] or {}
KKonfer["ksk"] = me
me.modname = L["MODNAME"]
me.modtitle = L["MODTITLE"]
me.desc = L["Suicide Kings loot distribution system."]
me.cmdname = L["CMDNAME"]
me.version = MINOR
me.suspendcmd = L["CMD_SUSPEND"]
me.resumecmd = L["CMD_RESUME"]
me.IsSuspended = function () return ksk.suspended or false end
me.SetSuspended = function (onoff)
  ksk.suspended = onoff or nil
  ksk.frdb.suspended = ksk.suspended
  local ds = L["KONFER_SUSPENDED"]
  if (not ksk.suspended) then
    ksk:FullRefresh (true)
    ds = L["KONFER_ACTIVE"]
    ksk:CheckForOtherKonferMods ( strfmt ("%s (v%s) - %s", me.modtitle,
      me.version, me.desc))
  end
  K.printf (K.icolor, "%s: |cffffffff%s|r.", L["MODTITLE"], ds)
end
me.OpenOnLoot = function ()
  if (ksk.settings and ksk.settings.auto_bid) then
    return true
  end
  return false
end
me.raid = true
me.party = false

local function create_konfer_dialogs ()
  local kchoice = KKonfer["..."]
  assert (kchoice)
  KKonfer["..."] = kchoice
  local ks = "|cffff2222<" .. K.KAHLUA ..">|r"

  local arg = {
    x = "CENTER", y = "MIDDLE", name = "KKonferModuleSelector",
    title = strfmt (L["KONFER_SEL_TITLE"], ks),
    canmove = true,
    canresize = false,
    escclose = true,
    xbutton = false,
    width = 450,
    height = 180,
    framelevel = 64,
    titlewidth = 300,
    border = true,
  }
  kchoice.seldialog = KUI:CreateDialogFrame (arg)

  arg = {
    x = "CENTER", y = 0, width = 400, height = 96, autosize = false,
    font = "GameFontNormal",
    text = strfmt (L["KONFER_SEL_HEADER"], ks),
  }
  kchoice.seldialog.header = KUI:CreateStringLabel (arg, kchoice.seldialog)

  arg = {
    name = "KKonferModSelDD",
    x = 35, y = -105, dwidth = 350, justifyh = "CENTER",
    mode = "SINGLE", itemheight = 16, items = KUI.emptydropdown,
  }
  kchoice.seldialog.seldd = KUI:CreateDropDown (arg, kchoice.seldialog)
  kchoice.seldialog.seldd:Catch ("OnValueChanged", function (this, evt, val, usr)
    if (not usr) then
      return
    end
    local kkonfer = _G["KKonfer"]
    assert (kkonfer)
    for k,v in pairs (kkonfer) do
      if (k ~= "..." and k ~= val) then
        v.SetSuspended (true)
      end
    end
    kkonfer[val].SetSuspended (false)
    kkonfer["..."].seldialog:Hide ()
  end)

  kchoice.seldialog.RefreshList = function (party, raid)
    local kkonfer = _G["KKonfer"] or {}
    local items = {}
    local kd = kkonfer["..."].seldialog.seldd

    tinsert (items, {
      text = L["KONFER_SEL_DDTITLE"], value = "", title = true,
    })
    for k,v in pairs (kkonfer) do
      if (k ~= "...") then
        if ((party and v.party) or (raid and v.raid)) then
          local item = {
            text = strfmt ("%s (v%s) - %s", v.modtitle, v.version,
              v.desc),
            value = k, checked = false,
          }
          tinsert (items, item)
        end
      end
    end
    kd:UpdateItems (items)
    kd:SetValue ("", true)
  end

  arg = {
    x = "CENTER", y = "MIDDLE", name = "KKonferModuleDisable",
    title = strfmt (L["KONFER_SEL_TITLE"], ks),
    canmove = true,
    canresize = false,
    escclose = false,
    xbutton = false,
    width = 450,
    height = 240,
    framelevel = 64,
    titlewidth = 300,
    border = true,
    okbutton = {},
    cancelbutton = {},
  }
  kchoice.actdialog = KUI:CreateDialogFrame (arg)
  kchoice.actdialog:Catch ("OnAccept", function (this, evt)
    for k,v in pairs (KKonfer) do
      if (k ~= "..." and k ~= this.mod) then
        v.SetSuspended (true)
      end
    end
  end)

  arg = {
    x = "CENTER", y = 0, autosize = false, border = true,
    width = 400, font = "GameFontHighlight", justifyh = "CENTER",
  }
  kchoice.actdialog.which = KUI:CreateStringLabel (arg, kchoice.actdialog)

  arg = {
    x = "CENTER", y = -24, width = 400, height = 128, autosize = false,
    font = "GameFontNormal",
    text = strfmt (L["KONFER_SUSPEND_OTHERS"], ks),
  }
  kchoice.actdialog.msg = KUI:CreateStringLabel (arg, kchoice.actdialog)
end

local function check_for_other_konfer (sel)
  local kchoice = KKonfer["..."]
  assert (kchoice)

  if (not sel and kchoice.selected and kchoice.selected ~= "ksk") then
    me.SetSuspended (true)
    return
  end

  local nactive = 0

  for k,v in pairs (KKonfer) do
    if (k ~= "...") then
      if (not v.IsSuspended ()) then
        if (v.raid and v.OpenOnLoot ()) then
          nactive = nactive + 1
        end
      end
    end
  end

  if (nactive <= 1) then
    return
  end

  --
  -- We have more than one KahLua Konfer module that is active for raids
  -- and set to auto-open on loot. We need to select which one is going to
  -- be the active one. Pop up the Konfer selection dialog.
  --
  if (not kchoice.seldialog) then
    create_konfer_dialogs ()
  end
  if (sel) then
    kchoice.actdialog.which:SetText (sel)
    kchoice.actdialog.mod = "ksk"
    kchoice.seldialog:Hide ()
    kchoice.actdialog:Show ()
  else
    kchoice.seldialog.RefreshList (me.party, me.raid)
    kchoice.actdialog:Hide ()
    kchoice.seldialog:Show ()
  end
end

function ksk:CheckForOtherKonferMods (nm)
  check_for_other_konfer (nm)
end

ksk.rolenames = ksk.rolenames or {}
ksk.rolenames[0] = L["Not Set"]
ksk.rolenames[1] = L["Healer"]
ksk.rolenames[2] = L["Melee DPS"]
ksk.rolenames[3] = L["Ranged DPS"]
ksk.rolenames[4] = L["Spellcaster"]
ksk.rolenames[5] = L["Tank"]

ksk.white = function (str)
  return "|cffffffff" .. str .. "|r"
end

ksk.red = function (str)
  return strfmt ("|cffff0000%s|r", str)
end

ksk.green = function (str)
  return strfmt ("|cff00ff00%s|r", str)
end

ksk.yellow = function (str)
  return strfmt ("|cff00ffff%s|r", str)
end

ksk.class = function (str, class)
  local sn
  if (type(str) == "table") then
    sn = str.name
    class = str.class
  else
    sn = str
  end

  if (ksk.inraid) then
    local uid = ksk:FindUser (sn)
    if (uid and ksk.raid and ksk.raid.users and ksk.raid.users[uid]) then
      return K.ClassColorsEsc[class] .. sn .. "|r"
    else
      return "|cff808080" .. sn .. "|r"
    end
  end

  return K.ClassColorsEsc[class] .. sn .. "|r"
end

ksk.aclass = function (str, class)
  local sn
  if (type (str) == "table") then
    sn = str.name
    class = str.class
  else
    sn = str
  end
  return K.ClassColorsEsc[class] .. sn .. "|r"
end

local white = ksk.white
local class = ksk.class
local aclass = ksk.aclass

function ksk:TimeStamp ()
  local _, mo, dy, yr = CalendarGetDate ()
  local hh, mm = GetGameTime ()
  return strfmt ("%04d%02d%02d%02d%02d", yr, mo, dy, hh, mm), yr, mo, dy, hh, mm
end

local function get_my_ids (cfg)
  local cfg = cfg or ksk.currentid
  local uid = ksk:FindUser (K.player.player, cfg)
  if (not uid) then
    return nil, nil
  end
  local ia, main = ksk:UserIsAlt (uid, nil, cfg)
  if (ia) then
    return uid, main
  else
    return uid, uid
  end
end

function ksk:UpdateUserSecurity ()
  local cfg = ksk.configs[ksk.currentid]
  ksk.csd.myuid, ksk.csd.mymainid = get_my_ids ()
  ksk.csd.isadmin = nil
  if (ksk.csd.myuid) then
    if (cfg.owner == ksk.csd.myuid or cfg.owner == ksk.csd.mymainid) then
      ksk.csd.isadmin = 2
    elseif (ksk:UserIsCoadmin (ksk.csd.myuid, nil)) then
      ksk.csd.isadmin = 1
    elseif (ksk:UserIsCoadmin (ksk.csd.mymainid, nil)) then
      ksk.csd.isadmin = 1
    end
  end
  ksk:SendMessage ("KSK_CONFIG_ADMIN", ksk.csd.isadmin ~= nil)
end

function ksk:IsAdmin (uid, cfg)
  local cfg = cfg or ksk.currentid
  if (not cfg) then
    return nil
  end
  if (not ksk.configs[cfg]) then
    return nil
  end

  local uid = uid or ksk:FindUser (K.player.player, cfg)

  if (not uid) then
    return nil
  end

  if (ksk.frdb.configs[cfg].owner == uid) then
    return 2, uid
  end
  if (ksk:UserIsCoadmin (uid, cfg)) then
    return 1, uid
  end

  local isalt, main = ksk:UserIsAlt (uid, nil, cfg)
  if (isalt) then
    if (ksk.frdb.configs[cfg].owner == main) then
      return 2, main
    end
    if (ksk:UserIsCoadmin (main, cfg)) then
      return 1, main
    end
  end
  return nil
end

local ts_datebase = nil
local ts_evtcount = 0

local function get_server_base_time ()
  local _, mo, d, y = CalendarGetDate()
  local h, m = GetGameTime ()
  return strfmt ("%02d%02d%02d%02d%02d0000", y-2000, mo, d, h, m)
end

function ksk:GetEventID (cfg)
  local cfg = cfg or ksk.currentid
  if (not ts_datebase or ts_evtcount >= 9999) then
    ts_datebase = tonumber (get_server_base_time ())
    ts_evtcount = 0
    while ((ts_datebase + ts_evtcount) < (ksk.configs[cfg].lastevent or 0)) do
      ts_evtcount = ts_evtcount + 100
    end
  end
  ts_evtcount = ts_evtcount + 1
  ksk.configs[cfg].lastevent = ts_datebase + ts_evtcount
  return ksk.configs[cfg].lastevent
end

function ksk:GetEventIDStr (ts, cfg)
  local cfg = cfg or ksk.currentid
  local ts = ts or ksk:GetEventID (cfg)
  return strfmt ("%014.0f", ts)
end

ksk.defaults = {
  auto_bid = true,
  silent_bid = false,
  tooltips = true,
  announce_where = 0,
  def_list = "0",
  def_rank = 999,
  auto_loot = true,
  boe_to_ml = true,   -- Assign BoE items to Master-Looter
  disenchant = true,  -- Assign to disenchanter
  use_decay = false,
  chat_filter = true, -- Enable chat message filter
  history = true,     -- Record loot history
  roll_timeout = 10,
  roll_extend = 5,
  try_roll = false,
  bid_threshold = 0,
  disenchant_below = false,
  offspec_rolls = true,
  suicide_rolls = false,
  ann_bidchanges = true,
  ann_winners_raid = true,
  ann_winners_guild = true,
  ann_bid_progress = true,
  ann_bid_usage = true,
  ann_roll_usage = true,
  ann_countdown = true,
  ann_roll_ties = true,
  ann_cancel = true,
  ann_no_bids = true,
  ann_missing = true,
  hide_absent = false,
  use_ranks = false,
  rank_prio = {},
  denchers = {},
}

local function check_config ()
  if (ksk.frdb.tempcfg) then
    info (strfmt (L["no active configuration. Either create one with %s or wait for a guild admin to broadcast the guild list."], white (strfmt ("/%s %s", L["CMDNAME"], L["CMD_CREATECONFIG"]))))
    return true
  end
  return false
end

local function ksk_version ()
  printf (ucolor, L["%s<%s>%s %s (version %d) - %s"],
    "|cffff2222", K.KAHLUA, "|r", L["MODTITLE"], MINOR,
    L["Suicide Kings loot distribution system."])
end

local function ksk_versioncheck ()
  ksk.vcreplies = {}
  ksk_version ()
  if (K.player.isguilded) then
    ksk.SendGuildAM ("VCHEK", nil)
  end
  if (ksk.inraid) then
    ksk.SendRaidAM ("VCHEK", nil)
  end
end

local function ksk_usage ()
  ksk_version ()
  printf (ucolor, L["Usage: "] .. white(strfmt(L["/%s [command [arg [arg...]]]"], L["CMDNAME"])))
    printf (ucolor, white(strfmt("/%s [%s]", L["CMDNAME"], L["CMD_LISTS"])))
    printf (ucolor, L["  Open the list management window."])

    printf (ucolor, white(strfmt("/%s %s", L["CMDNAME"], L["CMD_USERS"])))
    printf (ucolor, L["  Opens the user list management window."])

    printf (ucolor, white(strfmt("/%s %s [%s | %s]", L["CMDNAME"], L["CMD_LOOT"], L["SUBCMD_ASSIGN"], L["SUBCMD_ITEMS"])))
    printf (ucolor, L["  Opens the loot management window."])

    printf (ucolor, white(strfmt("/%s %s", L["CMDNAME"], L["CMD_SYNC"])))
    printf (ucolor, L["  Opens the sync manager window."])

    printf (ucolor, white(strfmt("/%s %s", L["CMDNAME"], L["CMD_SUSPEND"])))
    printf (ucolor, strfmt (L["  Suspend %s (no auto-open on loot, no missing member warnings etc)."], L["MODTITLE"]))

    printf (ucolor, white(strfmt("/%s %s", L["CMDNAME"], L["CMD_RESUME"])))
    printf (ucolor, strfmt (L["  Resume normal %s operations."], L["MODTITLE"]))

    printf (ucolor, white(strfmt("/%s %s [%s | %s]", L["CMDNAME"], L["CMD_CONFIG"], L["SUBCMD_LOOT"], L["SUBCMD_ADMIN"])))
    printf (ucolor, L["  Set up various options and manage configurations."])

    printf (ucolor, white(strfmt(L["/%s %s name"], L["CMDNAME"], L["CMD_SELECTCONFIG"])))
    printf (ucolor, L["  Selects the specified configuration as the current one."])
    printf (ucolor, white(strfmt(L["/%s %s name"], L["CMDNAME"], L["CMD_CREATECONFIG"])))
    printf (ucolor, L["  Create the specified configuration."])
    printf (ucolor, white(strfmt(L["/%s %s name"], L["CMDNAME"], L["CMD_DELETECONFIG"])))
    printf (ucolor, L["  Delete the specified configuration."])
    printf (ucolor, white(strfmt(L["/%s %s oldname newname"], L["CMDNAME"], L["CMD_COPYCONFIG"])))
    printf (ucolor, L["  Copies the specified configuration to a new one, with options."])
    printf (ucolor, white(strfmt(L["/%s %s oldname newname"], L["CMDNAME"], L["CMD_RENAMECONFIG"])))
    printf (ucolor, L["  Renames the specified configuration."])

    -- User list management commands
    printf (ucolor, white(strfmt(L["/%s %s name class"], L["CMDNAME"], L["CMD_CREATEUSER"])))
    printf (ucolor,L["  Adds a new user to the users list."])
    printf (ucolor, white(strfmt(L["/%s %s name"], L["CMDNAME"], L["CMD_DELETEUSER"])))
    printf (ucolor,L["  Removes a user from the users list."])
    printf (ucolor, white(strfmt(L["/%s %s oldname newname"], L["CMDNAME"], L["CMD_RENAMEUSER"])))
    printf (ucolor,L["  Renames a user after a paid name change."])
    printf (ucolor,white(strfmt(L["/%s %s [itemid | itemlink]"], L["CMDNAME"], L["CMD_ADDITEM"])))
    printf (ucolor,L["  Adds a new item to the item list."])
    printf (ucolor,white(strfmt(L["/%s %s [itemid | itemlink]"], L["CMDNAME"], L["CMD_ADDLOOT"])))
    printf (ucolor,L["  Adds a new item to the loot list."])
end

local function common_verify_input (input, cmd, exist, bypass, tbl, nexmsg, exmsg)
  if (not bypass and ksk:CheckPerm ()) then
    return true
  end

  local found = false
  local nname, pos
  local retid = 0
  local kcmd = L["CMDNAME"]

  if (not input or input == "") then
    err (L["Usage: "] .. white (strfmt (L["/%s %s name"], kcmd, cmd)))
    return true
  end

  nname, pos = K.GetArgs (input)
  if (not nname or nname == "") then
    err (L["Usage: "] .. white (strfmt (L["/%s %s name"], kcmd, cmd)))
    return true
  end

  if (pos ~= 1e9) then
    err (L["Usage: "] .. white (strfmt (L["/%s %s name"], kcmd, cmd)))
    return true
  end

  if (type(tbl) == "string" and tbl == "special") then
    return false, nname
  end

  local low = strlower (nname)
  if (tbl) then
    for k,v in pairs (tbl) do
      if (strlower(v.name) == low) then
        found = true
        retid = k
      end
    end
  end

  if (exist) then
    if (not found) then
      err (nexmsg, white(nname))
      return true
    end
  else
    if (found) then
      err (exmsg, white(nname))
      return true
    end
  end

  return false, nname, found, retid
end

local function common_verify_input2 (input, cmd, exist, bypass, tbl, nexmsg, exmsg)
  if (not bypass and ksk:CheckPerm ()) then
    return true
  end

  if (not tbl) then
    return true
  end

  local oldname, newname, pos
  local found = 0
  local retid = 0
  local kcmd = L["CMDNAME"]

  if (not input or input == "") then
    err (L["Usage: "] .. white(strfmt(L["/%s %s oldname newname"], kcmd, cmd)))
    return true
  end

  oldname, newname, pos = K.GetArgs (input, 2)
  if (not oldname or oldname == "") then
    err (L["Usage: "] .. white(strfmt(L["/%s %s oldname newname"], kcmd, cmd)))
    return true
  end

  if (not newname or newname == "") then
    err (L["Usage: "] .. white(strfmt(L["/%s %s oldname newname"], kcmd, cmd)))
    return true
  end

  if (pos ~= 1e9) then
    err (L["Usage: "] .. white(strfmt(L["/%s %s oldname newname"], kcmd, cmd)))
    return true
  end

  if (oldname == newname) then
    return true
  end

  if (type(tbl) == "string" and tbl == "special") then
    return false, oldname, newname
  end

  local lnew = strlower(newname)
  local lold = strlower(oldname)

  if (tbl) then
    for k,v in pairs (tbl) do
      if (strlower(v.name) == lnew) then
        found = k
      end
      if (strlower(v.name) == lold) then
        retid = k
      end
    end
  end

  if (retid == 0) then
    err (nexmsg, white (oldname))
    return true
  end

  if (not exist) then
    if (found ~= 0) then
      err (exmsg, white (newname))
      return true
    end
  end

  return false, oldname, newname, retid, found
end

local function ksk_createconfig(input)
  local cmd = L["CMD_CREATECONFIG"]
  local rv, nname, _, cfgid = common_verify_input (input, cmd, false, true,
    ksk.configs, nil,
    L["configuration %q already exists. Try again."])

  if (rv) then
    return true
  end

  return ksk:CreateNewConfig (nname, false)
end

local function ksk_selectconfig(input)
  local cmd = L["CMD_SELECTCONFIG"]
  local rv, nname, _, cfgid = common_verify_input (input, cmd, true, false,
    ksk.configs,
    L["configuration %q does not exist. Try again."], nil)

  if (rv) then
    return true
  end

  ksk:SetDefaultConfig (cfgid)
  return false
end

local function ksk_deleteconfig(input)
  local cmd = L["CMD_DELETECONFIG"]
  local rv, nname, _, cfgid = common_verify_input (input, cmd, true, true,
    ksk.configs,
    L["configuration %q does not exist. Try again."], nil)

  if (rv) then
    return true
  end

  ksk:DeleteConfig (cfgid)
  return false
end

local function ksk_renameconfig(input)
  local cmd = L["CMD_RENAMECONFIG"]
  local rv, _, newname, cfgid, _ = common_verify_input2 (input, cmd, true,
    false, ksk.configs,
    L["configuration %q does not exist. Try again."],
    L["configuration %q already exists. Try again."])

  if (rv) then
    return true
  end

  return ksk:RenameConfig (cfgid, newname)
end

local function ksk_copyconfig(input)
  local cmd = L["CMD_COPYCONFIG"]
  local rv, _, newname, cfgid, newid = common_verify_input2 (input, cmd, true,
    false, ksk.configs,
    L["configuration %q does not exist. Try again."],
    L["configuration %q already exists. Try again."])

  if (rv) then
    return true
  end

  return ksk:CopyConfigSpace (cfgid, newname, newid)
end

local function ksk_createuser (input)
  if (ksk:CheckPerm ()) then
    return true
  end

  local kcmd = L["CMDNAME"]
  local cmd = L["CMD_CREATEUSER"]
  local nname, nclass, pos
  local classid

  if (not input or input == "") then
    err (L["Usage: "] .. white (strfmt (L["/%s %s name class"], kcmd, cmd)))
    return true
  end

  nname, nclass, pos = K.GetArgs (input, 2)
  if (not nname or nname == "") then
    err (L["Usage: "] .. white (strfmt (L["/%s %s name class"], kcmd, cmd)))
    return true
  end

  if (not nclass or nclass == "") then
    err (L["Usage: "] .. white (strfmt (L["/%s %s name class"], kcmd, cmd)))
    return true
  end

  if (pos ~= 1e9) then
    err (L["Usage: "] .. white (strfmt (L["/%s %s name class"], kcmd, cmd)))
    return true
  end

  local lclass = strlower(nclass)
  for k,v in pairs(K.IndexClass) do
    if (v.l == lclass) then
      classid = k
    end
  end

  if (not classid) then
    err (L["invalid class %q specified. Valid classes are:"], white (lclass))
    for k,v in pairs(K.IndexClass) do
      if (v.l) then
        printf ("    |cffffffff%s|r", v.l)
      end
    end
    return true
  end

  if (not ksk:CreateNewUser (nname, classid)) then
    return true
  end
  return false
end

local function ksk_deleteuser (input)
  local cmd = L["CMD_DELETEUSER"]
  local rv, nname, _, userid = common_verify_input (input, cmd, true, false,
    ksk.users, L["user %q does not exist. Try again."], nil)

  if (rv) then
    return true
  end

  if (not ksk:DeleteUserCmd (userid)) then
    return true
  end
  return false
end

local function ksk_renameuser(input)
  if (not ksk.users) then
    return false
  end

  local cmd = L["CMD_RENAMEUSER"]
  local rv, _, newname, userid, found = common_verify_input2 (input, cmd, true,
    false, ksk.users,
    L["user %q does not exist. Try again."],
    L["user %q already exists. Try again."])

  if (rv) then
    return true
  end

  return ksk:RenameUser (userid, newname)
end

local function ksk_config(input)
  if (ksk:CheckPerm ()) then
    return true
  end
  local tab = ksk.CONFIG_TAB

  local subpanel = ksk.CONFIG_LOOT_TAB

  if (input == L["SUBCMD_LOOT"] or input == "" or not input) then
    subpanel = ksk.CONFIG_LOOT_TAB
  elseif (input == L["SUBCMD_ROLLS"]) then
    subpanel = ksk.CONFIG_ROLLS_TAB
  elseif (input == L["SUBCMD_ADMIN"]) then
    subpanel = ksk.CONFIG_ADMIN_TAB
  elseif (input == L["CMD_LISTS"]) then
    tab = ksk.LISTS_TAB
    subpanel = ksk.LISTS_CONFIG_TAB
  else
    printf (ucolor,L["Usage: "] .. white(strfmt("/%s %s [%s | %s | %s | %s]", L["CMDNAME"], L["CMD_CONFIG"], L["SUBCMD_LOOT"], L["SUBCMD_ROLLS"], L["SUBCMD_ADMIN"], L["CMD_LISTS"])))
    printf (ucolor,L["  %s - set up loot related options"], white (L["SUBCMD_LOOT"]))
    printf (ucolor,L["  %s - set up roll related options"], white (L["SUBCMD_ROLL"]))
    printf (ucolor,L["  %s - set up config spaces and permissions options"], white (L["SUBCMD_ADMIN"]))
    printf (ucolor,L["  %s - configure lists and list options"], white (L["CMD_LISTS"]))
    return
  end

  ksk.mainwin:Show ()
  ksk.mainwin:SetTab (tab, subpanel)
end

local function ksk_main()
  ksk.mainwin:Show ()
  ksk.mainwin:SetTab (ksk.LISTS_TAB, ksk.LISTS_MEMBERS_TAB)
end

local function ksk_users()
  if (ksk:CheckPerm ()) then
    return true
  end

  ksk.mainwin:Show ()
  ksk:RefreshUsers ()
  ksk.mainwin:SetTab (ksk.USERS_TAB, nil)
end

local function ksk_importgusers()
  if (ksk:CheckPerm ()) then
    return true
  end

  ksk:ImportGuildUsers (ksk.mainwin:IsShown ())
end

local function ksk_show()
  ksk.mainwin:Show ()
end

local function ksk_createlist(input)
  local cmd = L["CMD_CREATELIST"]
  local rv, nname, _, listid = common_verify_input (input, cmd, false, false,
    ksk.cfg.lists, nil,
    L["roll list %q already exists. Try again."])

  if (rv) then
    return true
  end

  return ksk:CreateNewList (nname)
end

local function ksk_selectlist(input)
  local cmd = L["CMD_SELECTLIST"]
  local rv, nname, _, listid = common_verify_input (input, cmd, true, false,
    ksk.cfg.lists,
    L["roll list %q does not exist. Try again."], nil)

  if (rv) then
    return true
  end

  ksk:SelectList (listid)
  return false
end

local function ksk_deletelist(input)
  local cmd = L["CMD_DELETELIST"]
  local rv, nname, _, listid = common_verify_input (input, cmd, true, false,
    ksk.cfg.lists,
    L["roll list %q does not exist. Try again."], nil)

  if (rv) then
    return true
  end

  ksk:DeleteListCmd (listid)
  return false
end

local function ksk_renamelist(input)
  local cmd = L["CMD_RENAMELIST"]
  local rv, _, newname, listid, _ = common_verify_input2 (input, cmd, true,
    false, ksk.cfg.lists,
    L["roll list %q does not exist. Try again."],
    L["roll list %q already exists. Try again."])

  if (rv) then
    return true
  end

  return ksk:RenameList (listid, newname)
end

local function ksk_copylist(input)
  local cmd = L["CMD_COPYLIST"]
  local rv, _, newname, listid, _ = common_verify_input2 (input, cmd, true,
    false, ksk.cfg.lists,
    L["roll list %q does not exist. Try again."],
    L["roll list %q already exists. Try again."])

  if (rv) then
    return true
  end

  return ksk:CopyList (listid, newname, ksk.currentid)
end

local function ksk_loot (input)
  local subpanel = ksk.LOOT_ASSIGN_TAB

  if (input == L["SUBCMD_ASSIGN"] or input == "" or not input) then
    subpanel = ksk.LOOT_ASSIGN_TAB
  elseif (input == L["SUBCMD_ITEMS"]) then
    if (ksk:CheckPerm ()) then
      return true
    end
    subpanel = ksk.LOOT_ITEMS_TAB
  elseif (input == L["SUBCMD_HISTORY"]) then
    if (ksk:CheckPerm ()) then
      return true
    end
    subpanel = ksk.LOOT_HISTORY_TAB
  else
    printf (ucolor,L["Usage: "] .. white(strfmt("/%s %s [%s | %s | %s]", L["CMDNAME"], L["CMD_LOOT"], L["SUBCMD_ASSIGN"], L["SUBCMD_ITEMS"], L["SUBCMD_HISTORY"])))
    printf (ucolor,L["  %s - open the loot assignment window"], white (L["SUBCMD_ASSIGN"]))
    printf (ucolor,L["  %s - open the item editor window"], white (L["SUBCMD_ITEMS"]))
    printf (ucolor,L["  %s - open the item history window"], white (L["SUBCMD_HISTORY"]))
    return
  end

  ksk.mainwin:Show ()
  ksk.mainwin:SetTab (ksk.LOOT_TAB, subpanel)
end

local function ksk_lists (input)
  ksk.mainwin:Show ()
  ksk.mainwin:SetTab (ksk.LISTS_TAB, ksk.LISTS_MEMBERS_TAB)
end

local function ksk_sync (input)
  if (ksk:CheckPerm ()) then
    return true
  end

  ksk.mainwin:Show ()
  ksk.mainwin:SetTab (ksk.SYNC_TAB)
end

local function ksk_items (input)
  if (ksk:CheckPerm ()) then
    return true
  end

  ksk.mainwin:Show ()
  ksk.mainwin:SetTab (ksk.LOOT_TAB, ksk.LOOT_ITEMS_TAB)
end

local function ksk_history (input)
  if (ksk:CheckPerm ()) then
    return true
  end

  ksk.mainwin:Show ()
  ksk.mainwin:SetTab (ksk.LOOT_TAB, ksk.LOOT_HISTORY_TAB)
end

local function ksk_additem (input)
  if (ksk:CheckPerm ()) then
    return true
  end

  if (not input or input == "" or input == L["CMD_HELP"]) then
    err (L["Usage: "] ..  white (strfmt (L["/%s %s [itemid | itemlink]"], L["CMDNAME"], L["CMD_ADDITEM"])))
    return true
  end

  local itemid, pos = K.GetArgs (input)
  if (itemid ~= "") then
    -- Convert to numeric itemid if an item link was specified
    local ii = tonumber (itemid)
    if (ii == nil) then
      itemid = string.match (itemid, "item:(%d+)")
    end
  end
  if ((not itemid) or (itemid == "") or (pos ~= 1e9) or (tonumber(itemid) == nil)) then
    err (L["Usage: "] ..  white (strfmt (L["/%s %s [itemid | itemlink]"], L["CMDNAME"], L["CMD_ADDITEM"])))
    return true
  end

  if (ksk.items[itemid]) then
    err (L["item %s already exists."], ksk.items[itemid].ilink)
    return true
  end

  local iname, ilink = GetItemInfo (tonumber(itemid))
  if (iname == nil or iname == "") then
    err (L["item %d is an invalid item."], itemid)
    return true
  end

  ksk:AddItem (itemid, ilink)
end

local function ksk_addloot (input)
  if (ksk:CheckPerm ()) then
    return true
  end

  if (not ksk.inraid or not ksk.isml) then
    err (L["can only add items when in a raid and you are the master looter."])
    return true
  end

  if (not input or input == "" or input == L["CMD_HELP"]) then
    err (L["Usage: "] ..  white (strfmt (L["/%s %s [itemid | itemlink]"], L["CMDNAME"], L["CMD_ADDLOOT"])))
    return true
  end

  local itemid, pos = K.GetArgs (input)
  if (itemid ~= "") then
    -- Convert to numeric itemid if an item link was specified
    local ii = tonumber (itemid)
    if (ii == nil) then
      itemid = string.match (itemid, "item:(%d+)")
    end
  end
  if ((not itemid) or (itemid == "") or (pos ~= 1e9) or (tonumber(itemid) == nil)) then
    err (L["Usage: "] ..  white (strfmt (L["/%s %s [itemid | itemlink]"], L["CMDNAME"], L["CMD_ADDLOOT"])))
    return true
  end

  local iname, ilink = GetItemInfo (tonumber(itemid))
  if (iname == nil or iname == "") then
    err (L["item %d is an invalid item."], itemid)
    return true
  end

  ksk:AddLoot (ilink)
end

local function ksk_test (input)
end

local function ksk_debug (input)
  input = input or "1"
  if (input == "") then
    input = "1"
  end
  local dl = tonumber (input)
  if (dl == nil) then
    dl = 0
  end
  K.debugging[L["MODNAME"]] = dl
end

local function ksk_status (input)
  local rs = ""
  if (ksk.raid) then
    rs=strfmt (" ksk.raid:yes kr.nraiders:%d kr.ml:%s kr.threshold:%s myid:%s numlooters=%s", ksk.raid.numraiders, tostring (ksk.raid.masterloot), tostring (ksk.raid.threshold), ksk.myraidid, tostring(ksk.numlooters))
    if (ksk.looters) then
      for k,v in pairs (ksk.looters) do
        rs = rs .. "\nlooter[%s]=%d (%s)", k, v.mlidx, v.uid and v.uid or "none"
      end
    end
  end
  printf ("init=%s susp=%s inraid:%s isml:%s isaorl:%s mlname=%q ahr=%s mhr=%s" .. rs, tostring(ksk.initialised), tostring(ksk.suspended), tostring(ksk.inraid), tostring (ksk.isml), tostring (ksk.isaorl), tostring(ksk.mlname), tostring(admin_hooks_registered), tostring(ml_hooks_registered))
end

local function ksk_resetpos (input)
  if (ksk.mainwin) then
    ksk.mainwin:SetPoint ("TOPLEFT", UIParent, "TOPLEFT", 100, -100)
  end
end

local function ksk_repair (input)
  ksk:RepairDatabases (true, true)
  ReloadUI ()
end

local function ksk_suspend (input)
  me.SetSuspended (true)
end

local function ksk_resume (input)
  me.SetSuspended (false)
end

local function ksk_refresh (input)
  ksk:RefreshRaid ()
end

K.debugging[L["MODNAME"]] = 9   -- @debug-delete@

local kcmdtab = {}
kcmdtab["debug"] = ksk_debug
kcmdtab["status"] = ksk_status
kcmdtab["refresh"] = ksk_refresh
kcmdtab[L["CMD_RESETPOS"]] = ksk_resetpos
kcmdtab[L["CMD_REPAIR"]] = ksk_repair
kcmdtab[L["CMD_VERSION"]] = ksk_version
kcmdtab[L["CMD_VERSIONCHECK"]] = ksk_versioncheck
kcmdtab["vc"] = ksk_versioncheck
kcmdtab[L["CMD_SHOW"]] = ksk_show
kcmdtab[L["CMD_LISTS"]] = ksk_lists
kcmdtab[L["CMD_USERS"]] = ksk_users
kcmdtab[L["CMD_LOOT"]] = ksk_loot
kcmdtab[L["CMD_CONFIG"]] = ksk_config
kcmdtab[L["CMD_SYNC"]] = ksk_sync
kcmdtab[L["CMD_SUSPEND"]] = ksk_suspend
kcmdtab[L["CMD_RESUME"]] = ksk_resume

kcmdtab[L["SUBCMD_ITEMS"]] = ksk_items
kcmdtab[L["SUBCMD_HISTORY"]] = ksk_history
kcmdtab[L["CMD_ADDITEM"]] = ksk_additem
kcmdtab[L["CMD_ADDLOOT"]] = ksk_addloot

kcmdtab[L["CMD_SELECTCONFIG"]] = ksk_selectconfig
kcmdtab[L["CMD_CREATECONFIG"]] = ksk_createconfig
kcmdtab[L["CMD_DELETECONFIG"]] = ksk_deleteconfig
kcmdtab[L["CMD_RENAMECONFIG"]] = ksk_renameconfig
kcmdtab[L["CMD_COPYCONFIG"]] = ksk_copyconfig

kcmdtab[L["CMD_CREATEUSER"]] = ksk_createuser
kcmdtab[L["CMD_DELETEUSER"]] = ksk_deleteuser
kcmdtab[L["CMD_RENAMEUSER"]] = ksk_renameuser
kcmdtab[L["CMD_IMPORTGUILDUSERS"]] = ksk_importgusers
kcmdtab["igu"] = ksk_importgusers

kcmdtab[L["CMD_SELECTLIST"]] = ksk_selectlist
kcmdtab[L["CMD_CREATELIST"]] = ksk_createlist
kcmdtab[L["CMD_DELETELIST"]] = ksk_deletelist
kcmdtab[L["CMD_RENAMELIST"]] = ksk_renamelist
kcmdtab[L["CMD_COPYLIST"]] = ksk_copylist

kcmdtab["test"] = ksk_test

function ksk:OnSlashCommand (input)
  if (not input or input == "") then
    if (check_config ()) then
      return true
    end

    ksk_main()
    return
  end

  local cmd, pos = K.GetArgs (input)
  if (not cmd or cmd == "") then
    if (check_config ()) then
      return true
    end

    ksk_main()
    return
  end

  strlower(cmd)

  if (cmd == L["CMD_HELP"] or cmd == "?") then
    ksk_usage()
    return
  end

  if (not kcmdtab[cmd]) then
    err (L["%q is not a valid command. Type %s for help."], white (cmd), white (strfmt ("/%s %s", L["CMDNAME"], L["SUBCMD_HELP"])))
    return
  end

  local arg
  if (pos == 1e9) then
    arg = ""
  else
    arg = strsub(input, pos)
  end

  if (cmd ~= L["CMD_CREATECONFIG"] and cmd ~= L["CMD_VERSION"] and cmd ~= L["CMD_VERSIONCHECK"] and cmd ~= "vc" and cmd ~= "debug" and cmd ~= "status" and check_config ()) then
    return true
  end

  kcmdtab[cmd](arg)
end

function ksk:CreateNewID (strtohash)
  local _, y, mo, d, h, m = ksk:TimeStamp ()
  local ts = strfmt ("%02d%02d%02d", y-2000, mo, d)
  local crc = H:CRC32(ts, nil, false)
  crc = H:CRC32(tostring(h), crc, false)
  crc = H:CRC32(tostring(m), crc, false)
  crc = H:CRC32(strtohash, crc, true)
  ts = ts .. K.hexstr (crc)
  return ts
end

function ksk:RefreshCSData ()
  for k,v in pairs(ksk.configs) do
    if (not ksk.csdata[k]) then
      ksk.csdata[k] = {}
      ksk.csdata[k].reserved = {}
    end
    local csd = ksk.csdata[k]
    csd.myuid, csd.mymainid = get_my_ids (k)
    csd.isadmin = nil
    if (csd.myuid) then
      if (v.owner == csd.myuid or v.owner == csd.mymainid) then
        csd.isadmin = 2
      elseif (ksk:UserIsCoadmin (csd.myuid, k)) then
        csd.isadmin = 1
      elseif (ksk:UserIsCoadmin (csd.mymainid, k)) then
        csd.isadmin = 1
      end
    end
  end

  for k,v in pairs (ksk.csdata) do
    if (not ksk.configs[k]) then
      ksk.csdata[k] = nil
    end
  end

  if (ksk.currentid) then
    ksk.csd = ksk.csdata[ksk.currentid]
    ksk:SendMessage ("KSK_CONFIG_ADMIN", ksk.csd.isadmin ~= nil)
  end
end

local function ksk_initialisation (self)
  if (ksk.initialised) then
    return
  end

  self.db = DB:New("KKonferSKDB", nil, "Default")
  self.frdb = self.db.factionrealm
  self.list = nil
  self.members = nil
  self.listid = nil
  self.memberid = nil
  self.userid = nil
  self.itemid = nil
  self.lootitem = {}
  self.qf = {}
  self.csdata = {}
  self.missing = {}
  self.nmissing = 0
  if (not self.frdb.configs) then
    self.frdb.nconfigs = 0
    self.frdb.configs = {}
    self.configs = self.frdb.configs
    --
    -- NOTE: We used to create a default config here that was the guild name
    -- if the user was the GM. However, this is bad, because they will be
    -- marked as the owner (which is probably right) but with a completely
    -- empty config (which is probably wrong if they lost their WTF and want
    -- to recover). So now we only ever create a temporary config which gives
    -- a user recovering from a crash a chance to accept a recovery command
    -- from another user.
    --
    self.frdb.tempcfg = true
    self:CreateNewConfig (" ", true, true, true, "1")
    self.frdb.dbversion = ksk.dbversion
  end
  self.configs = self.frdb.configs
  self.currentid = self.frdb.defconfig
  self.cfg = self.frdb.configs[self.currentid]
  self.users = self.frdb.configs[self.currentid].users
  self.settings = self.frdb.configs[self.currentid].settings
  self.lists = self.frdb.configs[self.currentid].lists
  self.items = self.frdb.configs[self.currentid].items
  self:RefreshCSData ()
  self.csd = self.csdata[self.currentid]
  self:UpdateUserSecurity ()
  self:UpdateDatabaseVersion ()
  ksk.suspended = self.frdb.suspended or nil

  ksk:InitialiseUI ()
  K.comm.RegisterComm (self, self.CHAT_MSG_PREFIX)

  self:SendMessage ("KSK_INITIALISED")
end

function ksk:OnLateInit ()
  ksk_initialisation (self)
  check_for_other_konfer ()
end

function ksk:CheckPerm (cfg)
  local cfg = cfg or ksk.currentid
  if (not ksk.configs[cfg] or not ksk.csdata[cfg] or not ksk.csdata[cfg].isadmin) then
    err (L["you do not have permission to do that in this configuration."])
    return true
  end
  return false
end

function ksk:CanChangeConfigType ()
  K:UpdatePlayerAndGuild ()
  if (K.player.isguilded == false) then
     return false
  else
    if (K.player.isgm == true) then
      return true
    end
  end
  return false
end

function ksk:UpdateAllConfigSettings()
  ksk:UpdateUserSecurity ()
  local settings = ksk.configs[ksk.currentid].settings
  ksk.mainwin.cfgselector:SetValue (ksk.currentid)
  ksk.qf.synctopbar:SetCurrentCRC ()

  local cf = ksk.qf.lootopts
  cf.autobid:SetChecked (settings.auto_bid)
  cf.silentbid:SetChecked (settings.silent_bid)
  cf.tooltips:SetChecked (settings.tooltips)
  cf.chatfilter:SetChecked (settings.chat_filter)
  cf.history:SetChecked (settings.history)
  cf.announcewhere:SetValue (settings.announce_where)
  cf.deflist:SetValue (settings.def_list)
  cf.gdefrank:SetValue (settings.def_rank)
  cf.autoloot:SetChecked (settings.auto_loot)
  cf.boetoml:SetChecked (settings.boe_to_ml)
  cf.tryroll:SetChecked (settings.try_roll)
  cf.hideabsent:SetChecked (settings.hide_absent)
  cf.rankprio:SetChecked (settings.use_ranks)
  cf.dench:SetChecked (settings.disenchant)
  cf.threshold:SetValue (settings.bid_threshold)
  cf.denchbelow:SetChecked (settings.disenchant_below)
  for i = 1, 6 do
    if (settings.denchers[i]) then
      cf["dencher"..i]:SetText (aclass (ksk.users[settings.denchers[i]]))
    else
      cf["dencher"..i]:SetText ("")
    end
  end

  local en = true
  if (not ksk.csd.isadmin) then
    en = false
    if ((ksk.mainwin.currenttab >= ksk.NON_ADMIN_THRESHOLD) or
        (ksk.mainwin.currenttab == ksk.LISTS_TAB and ksk.mainwin.tabs[ksk.LISTS_TAB].currenttab > ksk.LISTS_MEMBERS_TAB) or
        (ksk.mainwin.currenttab == ksk.LOOT_TAB and ksk.mainwin.tabs[ksk.LOOT_TAB].currenttab > ksk.LOOT_ASSIGN_TAB))
    then
      ksk.mainwin:SetTab (ksk.LOOT_TAB, ksk.LOOT_ASSIGN_TAB)
      ksk.mainwin:SetTab (ksk.LISTS_TAB, ksk.LISTS_MEMBERS_TAB)
    end
  end

  local cf = ksk.qf.rollopts
  cf.rolltimeout:SetValue (settings.roll_timeout)
  cf.rollextend:SetValue (settings.roll_extend)
  cf.enableoffspec:SetChecked (settings.offspec_rolls)
  cf.suicideroll:SetChecked (settings.suicide_rolls)
  cf.rollusage:SetChecked (settings.ann_roll_usage)
  cf.countdown:SetChecked (settings.ann_countdown)
  cf.ties:SetChecked (settings.ann_roll_ties)

  ksk.qf.userstab:SetShown (en)
  ksk.qf.synctab:SetShown (en)
  ksk.qf.configtab:SetShown (en)
  ksk.qf.iedittab:SetShown (en)
  ksk.qf.listcfgtab:SetShown (en)

  if (ksk.cfg.cfgtype == ksk.CFGTYPE_GUILD or ksk.inraid) then
    ksk.qf.bcastbutton:SetEnabled (en)
  else
    ksk.qf.bcastbutton:SetEnabled (false)
  end

  -- Only the config owner can see most of the config tab
  local cen = false
  if (ksk.csd.isadmin ~= 2) then
    if (ksk.mainwin.currenttab == ksk.CONFIG_TAB and ksk.mainwin.tabs[ksk.CONFIG_TAB].currenttab > ksk.NON_ADMIN_CONFIG_THRESHOLD) then
      ksk.mainwin:SetTab (ksk.CONFIG_TAB, ksk.CONFIG_LOOT_TAB)
    end
  else
    cen = true
  end
  ksk.qf.cfgadmintab:SetShown (cen)

  ksk.qf.bidders.forcebid:SetShown (en)
  ksk.qf.bidders.forceret:SetShown (en)
  ksk.qf.bidders.undo:SetShown (en)

  ksk.qf.listbuttons.insertbutton:SetShown (en)
  ksk.qf.listbuttons.deletebutton:SetShown (en)
  ksk.qf.listbuttons.suicidebutton:SetShown (en)
  ksk.qf.listbuttons.kingbutton:SetShown (en)
  ksk.qf.listbuttons.upbutton:SetShown (en)
  ksk.qf.listbuttons.downbutton:SetShown (en)
  ksk.qf.listbuttons.reservebutton:SetShown (en)

  ksk.qf.listcfgbuttons.createbutton:SetEnabled (en)
  if (not ksk.list) then
    en = false
  end
  ksk.qf.listcfgbuttons.deletebutton:SetEnabled (en)
  ksk.qf.listcfgbuttons.renamebutton:SetEnabled (en)
  ksk.qf.listcfgbuttons.copybutton:SetEnabled (en)
  ksk.qf.listcfgbuttons.importbutton:SetEnabled (en)
  ksk.qf.listcfgbuttons.exportbutton:SetEnabled (en)
  ksk.qf.listcfgbuttons.addmissingbutton:SetEnabled (en)
  ksk.qf.listctl.announcebutton:SetEnabled (en)
  ksk.qf.listctl.announceallbutton:SetEnabled (en)

  if (ksk.inraid and ksk.nmissing > 0 and ksk.csd.isadmin) then
    ksk.qf.userbuttons.addmissing:SetEnabled (true)
  else
    ksk.qf.userbuttons.addmissing:SetEnabled (false)
  end
  ksk.qf.userbuttons.guildimp:SetEnabled (K.player.isguilded and ksk.csd.isadmin ~= nil)
  ksk:RefreshSyncers ()
end

function ksk:FullRefresh (checkraid)
  ksk:RefreshUsers ()
  ksk:UpdateUserSecurity ()
  ksk:RefreshConfigSpaces ()
  ksk:RefreshLists ()
  ksk:RefreshItemList ()
  ksk:RefreshHistory ()
  ksk:UpdateAllConfigSettings ()
  K:UpdatePlayerAndGuild ()
  if (ksk.inraid) then
    ksk:RefreshRaid (checkraid)
  end
end

--
-- Event handling stuff. A few are Kore messages we trap but most are the
-- events we care about and are local to Konfer. The only exception is the
-- raid tracking stuff that will need to change to hook Kahlua Killers
-- events when that mod is complete.
--
local function player_info_updated (evt, ...)
  if (ksk.initialised) then
    ksk:UpdateUserSecurity ()
  end
  RequestRaidInfo ()
end

local function guild_info_updated (evt, ...)
  ksk.qf.userbuttons.guildimp:SetEnabled (K.player.isguilded and ksk.csd.isadmin ~= nil)
  local rvals = {}
  if (K.player.isguilded) then
    for i = 1, K.guild.numranks do
      local iv = {text = K.guild.ranks[i], value = i }
      tinsert (rvals, iv)
    end
  end

  oldr = ksk.qf.lootrank:GetValue() or 999
  local iv = { text = L["None"], value = 999 }
  tinsert (rvals, 1, iv)
  ksk.qf.lootrank:UpdateItems (rvals)
  ksk.qf.lootrank:SetValue (oldr)

  oldr = ksk.qf.defrankdd:GetValue() or 999
  ksk.qf.defrankdd:UpdateItems (rvals)
  ksk.qf.defrankdd:SetValue (oldr)

  oldr = ksk.qf.gdefrankdd:GetValue() or 999
  ksk.qf.gdefrankdd:UpdateItems (rvals)
  ksk.qf.gdefrankdd:SetValue (oldr)

  oldr = ksk.qf.itemrankdd:GetValue() or 999
  ksk.qf.itemrankdd:UpdateItems (rvals)
  ksk.qf.itemrankdd:SetValue (oldr)
end

function ksk:RefreshRaid (checkit)
  if (not ksk.initialised) then
    return
  end

  if (ksk.suspended) then
    return
  end

  local nraiders = GetNumGroupMembers ()
  local oldinraid = ksk.inraid or nil
  ksk.inraid = IsInRaid ()
  if (UnitInBattleground ("player")) then
    ksk.inraid = false
  end
  local sendmsg = false

  if (ksk.inraid ~= oldinraid) then
    if (ksk.inraid) then
      ksk.qf.bcastbutton:SetEnabled (true)
      ksk.raid = {}
      ksk.missing = {}
      ksk.nmissing = 0
      ksk.myraidid = 0
      ksk.isml = nil
      ksk.mlname = nil
      ksk.isaorl = nil
      sendmsg = true
      if (not ksk.frdb.tempcfg) then
        if (ksk.csd.isadmin) then
          ksk.SendRaidAM ("REQRS", "BULK")
        end
      end
      K:UpdatePlayerAndGuild ()
    else
      ksk.raid = nil
      ksk.missing = nil
      ksk.myraidid = nil
      ksk.isml = nil
      ksk.mlname = nil
      ksk.isaorl = nil
      ksk.looters = nil
      ksk.numlooters = nil
      if (ksk.cfg.cfgtype == ksk.CFGTYPE_PUG) then
        ksk.qf.bcastbutton:SetEnabled (false)
      end
      ksk.qf.userbuttons.addmissing:SetEnabled (false)
      ksk.qf.listctl.announcebutton:SetEnabled (false)
      ksk.qf.listctl.announceallbutton:SetEnabled (false)
      ksk:ResetBidders (true)
      ksk:ResetBossLoot ()
      ksk:RefreshLists ()
      ksk:SendMessage ("KSK_LEFT_RAID")
      return
    end
  end

  if (ksk.inraid) then
    local lootm, _, mlrid = GetLootMethod ()
    ksk.raid.party = {}
    for i = 1,8 do
      ksk.raid.party[i] = {}
    end
    ksk.raid.members = {}
    ksk.raid.users = {}
    ksk.raid.players = {}
    ksk.raid.denchers = {}
    ksk.raid.numraiders = nraiders
    ksk.raid.threshold = GetLootThreshold ()
    ksk.raid.masterloot = false
    if (lootm == "master") then
      ksk.raid.masterloot = true
    end
    ksk.myraidid = 0
    ksk.isml = false
    ksk.mlname = nil
    ksk.isaorl = false

    for i = 1, GetNumGroupMembers () do
      local nm, rank, party, lvl, _, cls, _, ol, _, role, isml = GetRaidRosterInfo (i)
      if (nm) then
        nm = K.CanonicalName (nm, nil)
        if (isml) then
          ksk.mlname = nm
        end

        if (nm == K.player.player) then
          ksk.myraidid = i
          if (isml) then
            ksk.isml = true
          end
          if (rank > 0) then
            ksk.isaorl = true
          end
        end

        local unkuser = nil
        local uid = ksk:FindUser (nm) or "0fff"
        if (uid == "0fff") then
          local classid = K.ClassIndex[cls]
          uid = uid .. ":" .. classid .. ":" .. nm
          unkuser = { name = nm, class = classid }

          if (not ksk.missing[uid]) then
            ksk.nmissing = ksk.nmissing + 1
            ksk.missing[uid] = unkuser
            if (ksk.csd.isadmin) then
              info (L["NOTICE: user %q is in the raid but not in the user list."], class (nm, classid))
              ksk:SendMessage ("KSK_RAID_MEMBER_MISSING", uid)
            end
          end
          ksk.qf.userbuttons.addmissing:SetEnabled (ksk.csd.isadmin ~= nil)
        else
          ksk.raid.users[uid] = i
          for j = 1, 6 do
            if (ksk.settings.denchers[j] == uid and ol) then
              tinsert (ksk.raid.denchers, uid)
            end
          end
        end

        ksk.raid.players[nm] = i
        ksk.raid.members[i] = { name=nm, uid = uid, party = party, unknown = unkuser, ml = isml, isaorl = rank > 0 }
        local ti = { raidid = i }
        tinsert (ksk.raid.party[party], ti)
      end
    end
    ksk:RefreshLists ()
  end

  if (sendmsg == true) then
    checkit = true
    ksk.qf.listctl.announcebutton:SetEnabled (ksk.listid ~= nil)
    ksk.qf.listctl.announceallbutton:SetEnabled (ksk.listid ~= nil)
    ksk:SendMessage ("KSK_JOINED_RAID", ksk.raid.numraiders)
  end

  if (ksk.cfg.cfgtype == ksk.CFGTYPE_PUG) then
    ksk.qf.bcastbutton:SetEnabled (ksk.isml or ksk.isaorl)
  end

  ksk:SendMessage ("KSK_MASTER_LOOTER", ksk.isml)

  if (checkit == true) then
    if (ksk.isml and not ksk.csd.isadmin and not ksk.frdb.tempcfg) then
      ksk.info (L["you are the master looter but not an administrator of this configuration. You will be unable to loot effectively. Either change master looter or have the owner of the configuration assign you as an administrator."])
    end
  end
end

--
-- Only get these values once
--
local disenchant_name = GetSpellInfo (13262)
local herbalism_name = GetSpellInfo (11993)
local mining_name = GetSpellInfo (32606)

local function unit_spellcast_succeeded (evt, caster, sname, rank, tgt)
  if ((caster == "player") and (sname == OPENING)) then
    ksk.chestname = tgt
    return
  end

  if ((caster == "player") and ((sname == disenchant_name) or
    (sname == herbalism_name) or (sname == mining_name))) then
    ksk.skiploot = true
  end
end

function ksk:AddItemToBossLoot (ilink, quant, lootslot)
  if (not ksk.bossloot) then
    ksk.bossloot = {}
  end

  local lootslot = lootslot or 0
  local itemid = string.match (ilink, "item:(%d+)")
  local _, _, _, _, _, _, _, _, slot, _, _, icls, isubcls = GetItemInfo (ilink)
  local filt, boe = ksk.GetItemClassFilter (ilink)
  local ti = { itemid = itemid, ilink = ilink, slot = lootslot, quant = quant, boe = boe }
  if (icls == ksk.classfilters.weapon) then
    ti.strict = ksk.classfilters.weapons[isubcls]
    ti.relaxed = ti.strict
  elseif (icls == ksk.classfilters.armor) then
    ti.strict = ksk.classfilters.strict[isubcls]
    ti.relaxed = ksk.classfilters.relaxed[isubcls]
    if (slot == "INVTYPE_CLOAK") then
      --
      -- Most cloaks are reported as type cloth, so we dont want to
      -- filter out other classes that can legitimately use the cloak.
      -- So we set cloaks to relaxed, even if we have strict class
      -- armour filtering on.
      --
      ti.strict = ti.relaxed
    end
  else
    ti.strict = filt
    ti.relaxed = filt
  end
  tinsert (ksk.bossloot, ti)
end

function ksk:SetMLCandidates (slot)
  ksk.looters = {}
  ksk.numlooters = 0

  for i = 1, MAX_RAID_MEMBERS do
    local tlc = GetMasterLootCandidate (slot, i)
    if (tlc and tlc ~= "") then
      local lc = K.CanonicalName (tlc, nil)
      local ti = { mlidx = i }
      local uid = ksk:FindUser (lc)
      if (uid) then
        ti.uid = uid
      end
      ksk.looters[lc] = ti
      debug (4, "MLC[%d]: lc=%q uid=%s", i, lc, tostring(uid))
      ksk.numlooters = ksk.numlooters + 1
    end
  end
end

--
-- This is called when a mob is looted. We build up an internal list of the
-- loot items left on the corpse. If we had an existing list, we clear it.
-- If we were in the middle of a bid, we cancel it, as it means the user was
-- drawn away from the mob for some reason and they are re-looting the
-- corpse.
--
-- This code also sends out loot events to the appropriate channel (either
-- raid or guild depending in the configuration type) so that other users
-- of the mod can see what loot is available and use the mod to place or
-- retract bids. If this is the first time we have looted this mob we also
-- send out the initial display event. However, we do not do that on
-- subsequent loots of the same mob so that if a user has already closed the
-- loot window it is not re-opened just because the master looter reacquired
-- the loot table.
--
function ksk:RefreshBossLoot()
  if (ksk.suspended or (not ksk.inraid) or (not ksk.isml) or (not ksk.raid) or (not ksk.raid.masterloot)) then
    return
  end

  ksk.announcedloot = ksk.announcedloot or {}

  if (ksk.skiploot) then
    debug (3, "skiploot set, returning")
    ksk.skiploot = nil
    return
  end

  local lslot = GetNumLootItems ()
  debug (3, "GetNumLootItems() = %d", lslot)

  local ilist = {}
  ksk.bossloot = {}

  for i = 1, lslot do
    if (LootSlotHasItem (i)) then
      local icon, name, quant, qual, locked = GetLootSlotInfo (i)
      local ilink = GetLootSlotLink (i)
      local itemid = nil
      local skipit = false

      ksk:SetMLCandidates (i)

      if (locked) then
        skipit = true
      else
        if ((ilink ~= nil) and (ilink ~= "")) then
          itemid = string.match (ilink, "item:(%d+)")
        else
          skipit = true
        end
      end

      if (qual < ksk.raid.threshold) then
        skipit = true
      end

      local dencher = nil
      if (ksk.raid and ksk.raid.denchers and ksk.raid.denchers[1]) then
        local dus = ksk.users[ksk.raid.denchers[1]].name
        if (ksk.looters[dus]) then
          dencher = ksk.looters[dus].mlidx
        end
      end
      if (not dencher) then
        if (ksk.looters[ksk.mlname]) then
          dencher = ksk.looters[ksk.mlname].mlidx
        end
      end

      if (itemid and ksk.items[itemid]) then
        if (ksk.items[itemid].ignore == true) then
          skipit = true
        elseif (ksk.items[itemid].autodench == true) then
          if (dencher) then
            skipit = true
            GiveMasterLoot (i, dencher)
          end
        elseif (ksk.items[itemid].automl == true) then
          if (ksk.looters[ksk.mlname]) then
            skipit = true
            GiveMasterLoot (i, ksk.looters[ksk.mlname].mlidx)
          end
        end
      elseif (itemid and ksk.iitems[itemid]) then
        if (ksk.iitems[itemid].ignore == true) then
          skipit = true
        end
      end

      local bthresh = ksk.configs[ksk.currentid].settings.bid_threshold
      if (not skipit and dencher and bthresh and bthresh ~= 0) then
        if (qual < bthresh and qual >= ksk.raid.threshold) then
          skipit = true
          GiveMasterLoot (i, dencher)
        end
      end

      debug (3, "RefreshBossLoot: i=%d/%d ilink=%q itemid=%q quant=%d qual=%d threshold=%d skipit=%s", i, lslot, tostring(ilink), tostring(itemid), quant, qual, ksk.raid.threshold, tostring (skipit))

      if (not skipit) then
        ksk:AddItemToBossLoot (ilink, quant, i)
        local tii = { ilink, quant }
        tinsert (ilist, tii)
      end
    end
  end

  debug (3, "ksk.bossloot=%s (%d)", tostring(ksk.bossloot), ksk.bossloot and #ksk.bossloot or 0)

  local uname = UnitName ("target")
  local uguid = UnitGUID ("target")
  local realguid = true
  if (not uname or uname == "") then
    if (ksk.chestname and ksk.chestname ~= "") then
      uname = ksk.chestname
    else
      uname = L["Chest"]
    end
  end
  if (not uguid or uguid == "") then
    uguid = 0
    if (ksk.chestname and ksk.chestname ~= "") then
      uguid = ksk.chestname
      realguid = false
    end
  end

  ksk.qf.lootscroll.itemcount = #ksk.bossloot
  ksk.qf.lootscroll:UpdateList ()

  if (#ksk.bossloot > 0) then
    ksk.sentoloot = true
    ksk.SendRaidAM ("OLOOT", "ALERT", uname, uguid, realguid, ilist)
    if (ksk.settings.auto_bid == true) then
      if (not ksk.mainwin:IsVisible ()) then
        ksk.autoshown = true
      end
      ksk.mainwin:Show ()
      ksk.mainwin:SetTab (ksk.LOOT_TAB, ksk.LOOT_ASSIGN_TAB)
    end

    if (ksk.settings.announce_where ~= 0) then
      ksk.announcedloot = ksk.announcedloot or {}
      local sendfn = ksk.SendGuildMsg
      if (ksk.settings.announce_where == 2) then
        sendfn = ksk.SendRaidMsg
      end

      local dloot = true
      if (uguid ~= 0) then
        if (ksk.announcedloot[uguid]) then
          dloot = false
        end
        ksk.announcedloot[uguid] = true
      else
        ksk.lastannouncetime = ksk.lastannouncetime or time()
        local now = time()
        local elapsed = difftime (now, ksk.lastannounce)
        if (elapsed < 90) then
          dloot = false
        end
      end

      if (dloot == true) then
        sendfn (strfmt (L["Loot from %s: "], uname))
        for k,v in ipairs (ksk.bossloot) do
          sendfn (v.ilink)
        end
        ksk.lastannouncetime = time ()
      end
    end
  else
    ksk.bossloot = nil
  end
end

local function loot_closed (evt, ...)
  ksk:CleanupLootRoll ()
  ksk:ResetBossLoot ()
  ksk.chestname = nil
  if (ksk.autoshown) then
    ksk.autoshown = nil
    ksk.mainwin:Hide ()
  end
  if (ksk.sentoloot) then
    ksk.SendRaidAM ("CLOOT", "ALERT")
  end
  ksk.sentoloot = nil
end

local function party_loot_method_changed (evt, ...)
  local method, mlpi, mlri = GetLootMethod ()
  ksk.mlname = nil
  ksk.isml = nil
  if (ksk.inraid) then
    ksk.raid.masterloot = false
  end

  if (method == "master") then
    local mlname
    if (mlpi) then
      if (mlpi == 0) then
        mlname = K.player.player
      else
        mlname = UnitName ("party"..mlpi)
      end
    end
    if (mlri) then
      if (mlri == 0) then
        mlname = K.player.player
      else
        mlname = UnitName ("raid"..mlri)
      end
    end
    if (ksk.inraid) then
      ksk.raid.masterloot = true
      ksk.mlname = K.CanonicalName (mlname)
      if (ksk.mlname == K.player.player) then
        ksk.isml = true
      else
        ksk.isml = false
      end
      ksk:SendMessage ("KSK_MASTER_LOOTER", ksk.isml)
    end
  end
end

local function extract_cmd (msg)
  local lm = strlower (msg)
  lm = lm:gsub ("^%s*", "")
  lm = lm:gsub ("%s*$", "")

  if ((lm == L["WHISPERCMD_BID"]) or
      (lm == L["WHISPERCMD_RETRACT"]) or
      (lm == L["WHISPERCMD_SUICIDE"]) or
      (lm == L["WHISPERCMD_STANDBY"]) or
      (lm == L["WHISPERCMD_HELP"]) or
      (lm == "bid") or (lm == "retract") or (lm == "suicide") or
      (lm == "standby") or (lm == "help")) then
    return lm
  end
end

local function whisper_filter (self, evt, msg, ...)
  if (extract_cmd (msg)) then
    return true
  end
end

local titlematch = "^" .. L["MODTITLE"] .. ": "
local abbrevmatch = "^" .. L["MODABBREV"] .. ": "
local function reply_filter (self, evt, msg, snd, ...)
  local sender = K.CanonicalName (snd, nil)
  if (strmatch (msg, titlematch)) then
    if (evt == "CHAT_MSG_WHISPER_INFORM") then
      return true
    elseif (sender == K.player.player) then
      return true
    end
  end
  if (strmatch (msg, abbrevmatch)) then
    if (evt == "CHAT_MSG_WHISPER_INFORM") then
      return true
    elseif (sender == K.player.player) then
      return true
    end
  end
end

local function get_user_pos (uid, ulist)
  local cuid = uid
  local rpos = 0
  if (ksk.cfg.tethered) then
    if (ksk.users[uid] and ksk.users[uid].main) then
      cuid = ksk.users[uid].main
    end
  end

  for k,v in ipairs (ulist) do
    if (ksk.inraid) then
      local ir = false
      if (ksk.raid.users[v]) then
        ir = true
      else
        if (ksk.cfg.tethered and ksk.users[v].alts) then
          for kk,vv in pairs (ksk.users[v].alts) do
            if (ksk.raid.users[vv]) then
              ir = true
              break
            end
          end
        end
      end
      if (ir) then
        rpos = rpos + 1
      end
    end
    if (v == cuid) then
      return k, rpos
    end
  end

  return 0, 0
end

local function chat_msg_whisper (evt, msg, snd, ...)
  local sender = K.CanonicalName (snd, nil)
  local cmd = extract_cmd (msg)
  if (cmd) then
    if (cmd == "bid" or cmd == L["WHISPERCMD_BID"]) then
      return ksk:NewBidder (sender)
    elseif (cmd == "retract" or cmd == L["WHISPERCMD_RETRACT"]) then
      return ksk:RetractBidder (sender)
    elseif (cmd == "suicide" or cmd == L["WHISPERCMD_SUICIDE"]) then
      local uid = ksk:FindUser (sender)
      if (not uid) then
        ksk.SendWhisper (strfmt (L["%s: you are not on any roll lists (yet)."], L["MODABBREV"]), sender)
        return
      end
      local sentheader = false
      local ndone = 0
      for k,v in pairs (ksk.sortedlists) do
        local lp = ksk.lists[v.id]
        local apos, rpos = get_user_pos (uid, lp.users)
        if (apos) then
          ndone = ndone + 1
          if (not sentheader) then
            ksk.SendWhisper (strfmt (L["LISTPOSMSG"], L["MODABBREV"], ksk.cfg.name, L["MODTITLE"]), sender)
            sentheader = true
          end
          if (ksk.inraid) then
            ksk.SendWhisper (strfmt (L["%s: %s - #%d (#%d in raid)"], L["MODABBREV"], lp.name, apos, rpos), sender)
          else
            ksk.SendWhisper (strfmt ("%s: %s - #%d", L["MODABBREV"], lp.name, apos), sender)
          end
        end
      end
      if (ndone > 0) then
        ksk.SendWhisper (strfmt (L["%s: (End of list)"], L["MODABBREV"]), sender)
      else
        ksk.SendWhisper (strfmt (L["%s: you are not on any roll lists (yet)."], L["MODABBREV"]), sender)
      end
    elseif (cmd == "help" or cmd == L["WHISPERCMD_HELP"]) then
      ksk.SendWhisper (strfmt (L["HELPMSG1"], L["MODABBREV"], L["MODTITLE"], L["MODABBREV"]), sender)
      ksk.SendWhisper (strfmt (L["HELPMSG2"], L["MODABBREV"], L["WHISPERCMD_BID"]), sender)
      ksk.SendWhisper (strfmt (L["HELPMSG3"], L["MODABBREV"], L["WHISPERCMD_RETRACT"]), sender)
      ksk.SendWhisper (strfmt (L["HELPMSG4"], L["MODABBREV"], L["WHISPERCMD_SUICIDE"]), sender)
      ksk.SendWhisper (strfmt (L["HELPMSG5"], L["MODABBREV"], L["WHISPERCMD_STANDBY"]), sender)
    end
  end
end

local function raid_roster_update (evt,...)
  ksk:RefreshRaid ()
end

ksk:RegisterMessage ("KSK_CONFIG_ADMIN", function (evt, onoff, ...)
  if (onoff and admin_hooks_registered ~= true) then
    admin_hooks_registered = true
    ksk:RegisterEvent ("CHAT_MSG_WHISPER", chat_msg_whisper)
    ksk:RegisterEvent ("UNIT_SPELLCAST_SUCCEEDED", unit_spellcast_succeeded)
    ksk:RegisterEvent ("PARTY_LOOT_METHOD_CHANGED", party_loot_method_changed)
  elseif (not onoff and admin_hooks_registered == true) then
    admin_hooks_registered = false
    ksk:UnregisterEvent ("CHAT_MSG_WHISPER")
    ksk:UnregisterEvent ("UNIT_SPELLCAST_SUCCEEDED")
    ksk:UnregisterEvent ("PARTY_LOOT_METHOD_CHANGED")
    ksk:SendMessage ("KSK_MASTER_LOOTER", false)
  end

  if (onoff) then
    if (chat_filters_installed ~= true) then
      if (ksk.settings.chat_filter) then
        chat_filters_installed = true
        ChatFrame_AddMessageEventFilter ("CHAT_MSG_WHISPER", whisper_filter)
        ChatFrame_AddMessageEventFilter ("CHAT_MSG_WHISPER_INFORM", reply_filter)
        ChatFrame_AddMessageEventFilter ("CHAT_MSG_RAID", reply_filter)
        ChatFrame_AddMessageEventFilter ("CHAT_MSG_GUILD", reply_filter)
        ChatFrame_AddMessageEventFilter ("CHAT_MSG_RAID_LEADER", reply_filter)
      end
    end
  end

  if (not onoff or not ksk.settings.chat_filter) then
    if (chat_filters_installed) then
      chat_filters_installed = false
      ChatFrame_RemoveMessageEventFilter ("CHAT_MSG_WHISPER", whisper_filter)
      ChatFrame_RemoveMessageEventFilter ("CHAT_MSG_WHISPER_INFORM", reply_filter)
      ChatFrame_RemoveMessageEventFilter ("CHAT_MSG_RAID", reply_filter)
      ChatFrame_RemoveMessageEventFilter ("CHAT_MSG_GUILD", reply_filter)
      ChatFrame_RemoveMessageEventFilter ("CHAT_MSG_RAID_LEADER", reply_filter)
    end
  end
end)

ksk:RegisterMessage ("KSK_MASTER_LOOTER", function (evt, onoff, ...)
  if (onoff and ml_hooks_registered ~= true) then
    ksk:RegisterEvent ("LOOT_OPENED", function (evt,...)
      ksk:RefreshBossLoot ()
    end)
    ksk:RegisterEvent ("LOOT_CLOSED", loot_closed)
    ksk:RegisterEvent ("OPEN_MASTER_LOOT_LIST", function (evt, ...)
      local l
      for l = 1, GetNumLootItems() do
        if (LootSlotHasItem (l)) then
          ksk:SetMLCandidates (l)
          return
        end
      end
    end)
    ksk:RegisterEvent ("UPDATE_MASTER_LOOT_LIST", function (evt, ...)
      local l
      for l = 1, GetNumLootItems() do
        if (LootSlotHasItem (l)) then
          ksk:SetMLCandidates (l)
          return
        end
      end
    end)
    ksk:RegisterEvent ("LOOT_SLOT_CHANGED", function (evt, ...)
      ksk:RefreshBossLoot ()
    end)
    ml_hooks_registered = true
  elseif (not onoff and ml_hooks_registered == true) then
    ksk:UnregisterEvent ("LOOT_OPENED")
    ksk:UnregisterEvent ("LOOT_CLOSED")
    ksk:UnregisterEvent ("OPEN_MASTER_LOOT_LIST")
    ksk:UnregisterEvent ("UPDATE_MASTER_LOOT_LIST")
    ml_hooks_registered = false
  end
end)

ksk:RegisterMessage ("KSK_INITIALISED", function (evt, ...)
  ksk.initialised = true
  ksk:RegisterMessage ("GUILD_INFO_UPDATED", guild_info_updated)
  ksk:RegisterMessage ("PLAYER_INFO_UPDATED", player_info_updated)
  ksk:RegisterEvent ("GROUP_ROSTER_UPDATE", raid_roster_update)
  ksk:RefreshRaid ()

  --
  -- One of the things we need to know when looting items is the armour class
  -- of an item. This info is returned by GetItemInfo() but the strings are
  -- localised. So we need to set up a translation table from that localised
  -- string to some constant that has generic meaning to us (and is locale
  -- agnostic). Set up that table now. Please note that this relies heavily
  -- on the fact that some of these functions return values in the same
  -- order for a given UI release. If this proves to be inacurate, this whole
  -- strategy will need to be re-thought.
  --
  ksk.classfilters = {}
  ksk.classfilters.weapon = LE_ITEM_CLASS_WEAPON   -- 2
  ksk.classfilters.armor  = LE_ITEM_CLASS_ARMOR    -- 4

  local ohaxe    = LE_ITEM_WEAPON_AXE1H            -- 0
  local thaxe    = LE_ITEM_WEAPON_AXE2H            -- 1
  local bows     = LE_ITEM_WEAPON_BOWS             -- 2
  local guns     = LE_ITEM_WEAPON_GUNS             -- 3
  local ohmace   = LE_ITEM_WEAPON_MACE1H           -- 4
  local thmace   = LE_ITEM_WEAPON_MACE2H           -- 5
  local poles    = LE_ITEM_WEAPON_POLEARM          -- 6
  local ohsword  = LE_ITEM_WEAPON_SWORD1H          -- 7
  local thsword  = LE_ITEM_WEAPON_SWORD2H          -- 8
  local glaives  = LE_ITEM_WEAPON_WARGLAIVE	   -- 9
  local staves   = LE_ITEM_WEAPON_STAFF            -- 10
  local fist     = LE_ITEM_WEAPON_UNARMED          -- 13
  local miscw    = LE_ITEM_WEAPON_GENERIC          -- 14
  local daggers  = LE_ITEM_WEAPON_DAGGER           -- 15
  local thrown   = LE_ITEM_WEAPON_THROWN           -- 16
  local xbows    = LE_ITEM_WEAPON_CROSSBOW         -- 18
  local wands    = LE_ITEM_WEAPON_WAND             -- 19
  local fish     = LE_ITEM_WEAPON_FISHINGPOLE      -- 20

  local amisc    = LE_ITEM_ARMOR_GENERIC           -- 0
  local cloth    = LE_ITEM_ARMOR_CLOTH             -- 1
  local leather  = LE_ITEM_ARMOR_LEATHER           -- 2
  local mail     = LE_ITEM_ARMOR_MAIL              -- 3
  local plate    = LE_ITEM_ARMOR_PLATE             -- 4
  local cosmetic = LE_ITEM_ARMOR_COSMETIC          -- 5
  local shields  = LE_ITEM_ARMOR_SHIELD            -- 6

  ksk.classfilters.strict = {}
  ksk.classfilters.relaxed = {}
  ksk.classfilters.weapons = {}
  --                                   +------------- Warriors            1
  --                                   |+------------ Paladins            2
  --                                   ||+----------- Hunters             3
  --                                   |||+---------- Rogues              4
  --                                   ||||+--------- Priests             5
  --                                   |||||+-------- Death Knights       6
  --                                   ||||||+------- Shaman              7
  --                                   |||||||+------ Mages               8
  --                                   ||||||||+----- Warlocks            9
  --                                   |||||||||+---- Monks               10
  --                                   ||||||||||+--- Druids              11
  --                                   |||||||||||+-- Demon Hunter        12
  ksk.classfilters.strict[amisc]    = "111111111111"
  ksk.classfilters.strict[cloth]    = "000010011000"
  ksk.classfilters.strict[leather]  = "000100000111"
  ksk.classfilters.strict[mail]     = "001000100000"
  ksk.classfilters.strict[plate]    = "110001000000"
  ksk.classfilters.strict[cosmetic] = "111111111111"
  ksk.classfilters.strict[shields]  = "110000100000"
  ksk.classfilters.relaxed[amisc]   = "111111111111"
  ksk.classfilters.relaxed[cloth]   = "111111111111"
  ksk.classfilters.relaxed[leather] = "111101100111"
  ksk.classfilters.relaxed[mail]    = "111001100000"
  ksk.classfilters.relaxed[plate]   = "110001000000"
  ksk.classfilters.relaxed[cosmetic]= "111111111111"
  ksk.classfilters.relaxed[shields] = "110000100000"
  ksk.classfilters.weapons[ohaxe]   = "111101100101"
  ksk.classfilters.weapons[thaxe]   = "111001100000"
  ksk.classfilters.weapons[bows]    = "101100000000"
  ksk.classfilters.weapons[guns]    = "101100000000"
  ksk.classfilters.weapons[ohmace]  = "110111100110"
  ksk.classfilters.weapons[thmace]  = "110001100010"
  ksk.classfilters.weapons[poles]   = "111001000110"
  ksk.classfilters.weapons[ohsword] = "111101011101"
  ksk.classfilters.weapons[thsword] = "111001000000"
  ksk.classfilters.weapons[staves]  = "101010111110"
  ksk.classfilters.weapons[fist]    = "101100100111"
  ksk.classfilters.weapons[miscw]   = "111111111111"
  ksk.classfilters.weapons[daggers] = "101110111011"
  ksk.classfilters.weapons[thrown]  = "101100000000"
  ksk.classfilters.weapons[xbows]   = "101100000000"
  ksk.classfilters.weapons[wands]   = "000010011000"
  ksk.classfilters.weapons[glaives] = "100101000101"
  ksk.classfilters.weapons[fish]    = "111111111111"

  --
  -- Broadcasts a list of all configurations we have, and the latest events
  -- we have for each user. The recipients of the message use this to trim
  -- old events from their lists to save space.
  --
  ksk:SyncCleanup ()
end)

