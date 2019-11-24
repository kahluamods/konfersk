--[[
   KahLua KonferSK - a suicide kings loot distribution addon.
     WWW: http://kahluamod.com/ksk
     Git: https://github.com/kahluamods/konfersk
     IRC: #KahLua on irc.freenode.net
     E-mail: cruciformer@gmail.com
   Please refer to the file LICENSE.txt for the Apache License, Version 2.0.

   Copyright 2008-2019 James Kean Johnston. All rights reserved.

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
local KRP = LibStub:GetLibrary("KKoreParty")
local KLD = LibStub:GetLibrary("KKoreLoot")

if (not K) then
  error ("KahLua KonferSK: could not find KahLua Kore.", 2)
end

if (tonumber(KM) < 3) then
  error ("KahLua KonferSK: outdated KahLua Kore. Please update all KahLua addons.")
end

if (not H) then
  error ("KahLua KonferSK: could not find KahLua Kore Hash library.", 2)
end

if (not DB) then
  error ("KahLua KonferSK: could not find KahLua Kore Database library.", 2)
end

if (not KUI) then
  error ("KahLua KonferSK: could not find KahLua Kore UI library.", 2)
end

if (not KRP) then
  error ("KahLua KonferSK: could not find KahLua Kore Raid/Party library.", 2)
end

if (not KLD) then
  error ("KahLua KonferSK: could not find KahLua Kore Loot Distribution library.", 2)
end

local L = K:GetI18NTable("KKonferSK", false)

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

local LOOT_METHOD_UNKNOWN    = KRP.LOOT_METHOD_UNKNWON
local LOOT_METHOD_FREEFORALL = KRP.LOOT_METHOD_FREEFORALL
local LOOT_METHOD_GROUP      = KRP.LOOT_METHOD_GROUP
local LOOT_METHOD_PERSONAL   = KRP.LOOT_METHOD_PERSONAL
local LOOT_METHOD_MASTER     = KRP.LOOT_METHOD_MASTER

ksk = K:NewAddon(nil, MAJOR, MINOR, L["Suicide Kings loot distribution system."], L["MODNAME"], L["CMDNAME"] )
if (not ksk) then
  error ("KahLua KonferSK: addon creation failed.")
end

_G["KSK"] = ksk

ksk.KUI = KUI
ksk.L   = L
ksk.KRP = KRP
ksk.KLD = KLD
ksk.H   = H
ksk.KDB = DB

ksk.CHAT_MSG_PREFIX = "KSKC"

local MakeFrame = KUI.MakeFrame

-- We will be using both KKoreParty and KKoreLoot.
KRP:RegisterAddon ("ksk")
KLD:RegisterAddon ("ksk")

-------------------------------------------------------------------------------
--
-- KSK "global" variables. All variables, whether they can be nil or not, that
-- can possibly be set in the ksk namespace, must be listed here, along with
-- their default value. A description of what the variable controls and which
-- user interface element is affected by the variable must accompany each such
-- global variable. This includes variables used in other files. They must all
-- be declared and described here.
--
-------------------------------------------------------------------------------

-- The version number of this release of KSK. This is set by the prep script
-- when it sets MINOR above. For debug / development releases this is always
-- set to 1. This is used in the version check code as well as the mod info
-- display and mod registration.
ksk.version = MINOR

-- The KSK "protocol" version number. This is used in every addon message
-- that KSK sends. As a general principle someone with a version of the mod
-- that has a higher protocol version number should be able to decode messages
-- from a lower version protocol, but so far we have made no attempt to code
-- this backwards compatibility into each protocol message. So at the moment
-- these protocol versions must match exactly in order for two KSK mods to
-- talk to each other.
ksk.protocol = 2

-- The format and "shape" of the KSK stored variables database. As various new
-- features have been added or bugs fixed, this changes. The code in the file
-- KSK-Utility.lua (ksk.UpdateDatabaseVersion ()) will update olrder databases
-- dating all the way back to version 1. Once a database version has been
-- upgraded it cannot be reverted.
ksk.dbversion = 1

-- Whether or not KSK has been fully initialised. This can take a while as
-- certain bits of information are not immediately available on login.
-- None of the event handlers or callback functions except those participating
-- in actual initialisation should execute if this is false.
ksk.initialised = false

-- Whether or nor KSK is currently suspended. Always only set to true or false.
-- If the mod is suspended then certain callbacks and event handlers must do
-- nothing. Such things should probably always also check ksk.initialised too.
-- We start out with this set to false and during initialisation we may end up
-- setting this to true.
ksk.suspended = false

-- Maximum number of disenchanters that can be defined in a config
ksk.MAX_DENCHERS = 4

-- A static table with the list of possible player roles (from a KSK point
-- of view - not to be confused with the in-game raid or player roles). This
-- is used to restrict certain items to a particular type of raider. We also
-- define constants for each role name.
ksk.ROLE_UNSET  = 0
ksk.ROLE_HEALER = 1
ksk.ROLE_MELEE  = 2
ksk.ROLE_RANGED = 3
ksk.ROLE_CASTER = 4
ksk.ROLE_TANK   = 5
ksk.rolenames = {
 [ksk.ROLE_UNSET]  = L["Not Set"],
 [ksk.ROLE_HEALER] = L["Healer"],
 [ksk.ROLE_MELEE]  = L["Melee DPS"],
 [ksk.ROLE_RANGED] = L["Ranged DPS"],
 [ksk.ROLE_CASTER] = L["Spellcaster"],
 [ksk.ROLE_TANK]   = L["Tank"],
}

-- Constants used to define the various UI tabs and sub-tabs. These should
-- never be changed by code.
ksk.LISTS_TAB = 1
 ksk.LISTS_MEMBERS_PAGE = 1
 ksk.LISTS_CONFIG_PAGE  = 2
ksk.LOOT_TAB = 2
 ksk.LOOT_ASSIGN_PAGE  = 1
 ksk.LOOT_ITEMS_PAGE   = 2
 ksk.LOOT_HISTORY_PAGE = 3
ksk.USERS_TAB = 3
ksk.SYNC_TAB = 4
ksk.CONFIG_TAB = 5
 ksk.CONFIG_LOOT_PAGE  = 1
 ksk.CONFIG_ROLLS_PAGE = 2
 ksk.CONFIG_ADMIN_PAGE = 3

ksk.NON_ADMIN_THRESHOLD        = ksk.USERS_TAB
ksk.NON_ADMIN_CONFIG_THRESHOLD = ksk.CONFIG_ROLLS_PAGE

-- Constants for the different types of configuration we support. Currently
-- this is only guild and PUG and this is highly unlikely to ever change.
ksk.CFGTYPE_GUILD = 1
ksk.CFGTYPE_PUG   = 2

-- Whether or not we are actually in a raid. This is set via a callback from
-- KKoreParty (IN_RAID_CHANGED). If we are in a raid this will be non-nil.
-- If we are not in a raid it will always be nil, but only for the master
-- looter. For normal users we must check KRP.in_raid.
ksk.raid = nil

-- Handle to the return value from database initialisation. This is set early
-- on in the initialisation process. No code other than that initialisation
-- code should ever touch this.
ksk.db = nil

-- The faction and realm database. This is the root of all stored configuration
-- variables and is set during initialisation. This is a convenience alias for
-- ksk.db.factionrealm.
ksk.frdb = nil

-- Convenience alias for ksk.db.factionrealm.configs
ksk.configs = nil

-- The ID of the currently selected configuration or nil if none (rare).
ksk.currentid = nil

-- The config database for the currently selected configuration or nil if no
-- config is currently active. This is a convenience alias for
-- ksk.db.factionreal.configs[ksk.currentid].
ksk.cfg = nil

-- Convenience alias for ksk.cfg.users
ksk.users = nil

-- Convenience alias for ksk.cfg.settings
ksk.settings = nil

-- The number of raiders currently in the raid group that are missing from the
-- users list, and the actual list of such missing players. Each entry in the
-- missing table is itself a table with the members "name" and "class", where
-- "name" is the full player-realm name of the player and class is the KKore
-- class number (for example K.CLASS_DRUID) of the missing player. These are
-- set to 0 and nil respectively when not in a raid.
ksk.nmissing = 0
ksk.missing = nil

-- Cached session data. This is a table, with one entry per defined config in
-- the config file, and stores convenience data frequently accessed from each
-- config. Typically these are computed values and therefore not stored in the
-- actual database that is saved each time the user logs out. The table is
-- indexed by config id.
ksk.csdata = {}

-- Convenience alias for ksk.csdata[ksk.currentid]. Can never be nil once
-- initialisation has completed.
ksk.csd = nil

-- Convenience alias for ksk.cfg.lists
ksk.lists = nil

-- The sorted list of lists. This is almost never nil, even if the config has
-- no defined lists (it will just be an empty table). When not empty it
-- contains the sorted list of lists for the current config. It is refreshed
-- when the lists UI is refreshed by ksk.RefreshListsUI().
ksk.sortedlists = nil

-- Convenience alias for ksk.cfg.items
ksk.items = nil

-- Set to true if the main KSK window was automatically opened.
ksk.autoshown = nil

-- The default values for a new configuration.
ksk.defaults = {
  auto_bid = true,
  silent_bid = false,
  tooltips = true,
  announce_where = 0,
  def_list = "0",
  def_rank = 0,
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

-- The main UI window handle, which is a KUI frame.
ksk.mainwin = nil

-- The global popup window. There can only be one popup window active at a
-- time and if that window is currently up, this will be the frame for it.
-- Otherwise it is nil.
ksk.popupwindow = nil

-- The global quickframe cache. Each UI pabel should maintain its own
-- quickframe cache. This is only for the very top level UI frames.
ksk.qf = {}

-------------------------------------------------------------------------------

local admin_hooks_registered = nil
local ml_hooks_registered = nil
local chat_filters_installed = nil
local sentoloot = nil

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

--
-- "Register" KSK with the list of all other Konfer addons.
--
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
me.IsSuspended = function ()
  return ksk.suspended or false
end
me.SetSuspended = function (onoff)
  ksk.suspended = onoff or false
  if (ksk.frdb) then
    ksk.frdb.suspended = ksk.suspended
  end
  local ds = L["KONFER_SUSPENDED"]
  if (not ksk.suspended) then
    ksk.FullRefresh (true)
    ds = L["KONFER_ACTIVE"]
    ksk.CheckForOtherKonferMods ( strfmt ("%s (v%s) - %s", me.modtitle,
      me.version, me.desc))
  end
  K.printf (K.icolor, "%s: |cffffffff%s|r.", L["MODTITLE"], ds)
  ksk:SendIPC ("SUSPENDED", ksk.suspended)
end
me.OpenOnLoot = function ()
  if (ksk.settings and ksk.settings.auto_bid) then
    return true
  end
  return false
end
me.raid = true          -- KSK works in raids
me.party = false        -- KSK does not work in parties
me.battleground = false -- KSK does not work in battlegrounds

local function create_konfer_dialogs ()
  local kchoice = KKonfer["..."]
  assert (kchoice)
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
    blackbg = true,
  }
  kchoice.seldialog = KUI:CreateDialogFrame (arg)

  local ksd = kchoice.seldialog

  arg = {
    x = "CENTER", y = 0, width = 400, height = 96, autosize = false,
    font = "GameFontNormal",
    text = strfmt (L["KONFER_SEL_HEADER"], ks),
  }
  ksd.header = KUI:CreateStringLabel (arg, ksd)

  arg = {
    name = "KKonferModSelDD",
    x = 35, y = -105, dwidth = 350, justifyh = "CENTER",
    mode = "SINGLE", itemheight = 16, items = KUI.emptydropdown,
  }
  ksd.seldd = KUI:CreateDropDown (arg, ksd)
  ksd.seldd:Catch ("OnValueChanged", function (this, evt, val, usr)
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
    ksd.selected = val
  end)

  ksd.RefreshList = function (party, raid)
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
    blackbg = true,
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

function ksk.CheckForOtherKonferMods (nm)
  check_for_other_konfer (nm)
end

ksk.white = function (str)
  return "|cffffffff" .. str .. "|r"
end

ksk.red = function (str)
  return "|cffff0000" .. str .. "|r"
end

ksk.green = function (str)
  return "|cff00ff00" .. str .. "|r"
end

ksk.yellow = function (str)
  return "|cff00ffff" .. str .. "|r"
end

ksk.class = function (str, class)
  local sn
  if (type(str) == "table") then
    sn = str.name
    class = str.class
  else
    sn = str
  end

  if (KRP.in_raid and KRP.players) then
    local pinfo = KRP.players[sn]
    if (pinfo) then
      return K.ClassColorsEsc[class] .. sn .. "|r"
    else
      return "|cff808080" .. sn .. "|r"
    end
  end

  return K.ClassColorsEsc[class] .. sn .. "|r"
end

ksk.shortclass = function (str, class)
  local sn
  if (type(str) == "table") then
    sn = str.name
    class = str.class
  else
    sn = str
  end

  if (KRP.in_raid and KRP.players) then
    local pinfo = KRP.players[sn]
    sn = Ambiguate (sn, "guild")
    if (pinfo) then
      return K.ClassColorsEsc[class] .. sn .. "|r"
    else
      return "|cff808080" .. sn .. "|r"
    end
  end

  sn = Ambiguate (sn, "guild")
  return K.ClassColorsEsc[class] .. sn .. "|r"
end

ksk.aclass = function (str, class)
  local sn, class = str, class
  if (type (str) == "table") then
    sn = str.name
    class = str.class
  end

  return K.ClassColorsEsc[class] .. sn .. "|r"
end

ksk.shortaclass = function (str, class)
  local sn, class = str, class
  if (type (str) == "table") then
    sn = str.name
    class = str.class
  end

  sn = Ambiguate (sn, "guild")
  return K.ClassColorsEsc[class] .. sn .. "|r"
end

local white = ksk.white
local class = ksk.class
local shortclass = ksk.shortclass
local aclass = ksk.aclass
local shortaclass = ksk.shortaclass

function ksk.TimeStamp ()
  local tDate = date("*t")
  local mo = tDate["month"]
  local dy = tDate["day"]
  local yr = tDate["year"]
  local hh, mm = GetGameTime ()
  return strfmt ("%04d%02d%02d%02d%02d", yr, mo, dy, hh, mm), yr, mo, dy, hh, mm
end

-- cfg is known to be valid before this is called
local function get_my_ids (cfg)
  local uid = ksk.FindUser (K.player.name, cfg)
  if (not uid) then
    return nil, nil
  end

  local ia, main = ksk.UserIsAlt (uid, nil, cfg)
  if (ia) then
    return uid, main
  else
    return uid, uid
  end
end

function ksk.UpdateUserSecurity (conf)
  local conf = conf or ksk.currentid

  if (not conf or not ksk.frdb or not ksk.frdb.configs
      or not ksk.frdb.configs[conf] or not ksk.csdata
      or not ksk.csdata[conf]) then
    return false
  end

  local csd = ksk.csdata[conf]
  local cfg = ksk.frdb.configs[conf]

  csd.myuid, csd.mymainid = get_my_ids (conf)
  csd.is_admin = nil
  if (csd.myuid) then
    if (cfg.owner == csd.myuid or cfg.owner == csd.mymainid) then
      csd.is_admin = 2
    elseif (ksk.UserIsCoadmin (csd.myuid, conf)) then
      csd.is_admin = 1
    elseif (ksk.UserIsCoadmin (csd.mymainid, conf)) then
      csd.is_admin = 1
    end
  end

  if (ksk.initialised and conf == ksk.currentid) then
    ksk:SendIPC ("CONFIG_ADMIN", csd.is_admin ~= nil)
  end

  return true
end

function ksk.AmIML ()
  if (KRP.in_raid and KRP.is_ml and ksk.csd.is_admin and not KRP.in_battleground) then
    return true
  end
  return false
end

function ksk.IsSenderMasterLooter (sender)
  if (KRP.in_raid and KRP.master_looter and KRP.master_looter == sender) then
    return true
  end
  return false
end

function ksk.IsAdmin (uid, cfg)
  local cfg = cfg or ksk.currentid

  if (not cfg or not ksk.configs or not ksk.configs[cfg]) then
    return nil, nil
  end

  local uid = uid or ksk.FindUser (K.player.name, cfg)

  if (not uid) then
    return nil, nil
  end

  if (ksk.configs[cfg].owner == uid) then
    return 2, uid
  end
  if (ksk.UserIsCoadmin (uid, cfg)) then
    return 1, uid
  end

  local isalt, main = ksk.UserIsAlt (uid, nil, cfg)
  if (isalt) then
    if (ksk.configs[cfg].owner == main) then
      return 2, main
    end
    if (ksk.UserIsCoadmin (main, cfg)) then
      return 1, main
    end
  end
  return nil, nil
end

local ts_datebase = nil
local ts_evtcount = 0

local function get_server_base_time ()
  local tDate = date("*t")
  local mo = tDate["month"]
  local d = tDate["day"]
  local y = tDate["year"]
  local h, m = GetGameTime ()
  return strfmt ("%02d%02d%02d%02d%02d0000", y-2000, mo, d, h, m)
end

function ksk.GetEventID (cfg)
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

local vcdlg = nil

ksk.vcreplies = nil

local function vlist_newitem (objp, num)
  local bname = "KSKVCheckListButton" .. tostring(num)
  local rf = MakeFrame ("Button", bname, objp.content)
  local nfn = "GameFontNormalSmallLeft"
  local hfn = "GameFontHighlightSmallLeft"
  local htn = "Interface/QuestFrame/UI-QuestTitleHighlight"

  rf:SetWidth (325)
  rf:SetHeight (16)
  rf:SetHighlightTexture (htn, "ADD")

  local who = rf:CreateFontString (nil, "BORDER", nfn)
  who:ClearAllPoints ()
  who:SetPoint ("TOPLEFT", rf, "TOPLEFT", 0, -2)
  who:SetPoint ("BOTTOMLEFT", rf, "BOTTOMLEFT", 0, -2)
  who:SetWidth (168)
  who:SetJustifyH ("LEFT")
  who:SetJustifyV ("TOP")
  rf.who = who

  local version = rf:CreateFontString (nil, "BORDER", nfn)
  version:ClearAllPoints ()
  version:SetPoint ("TOPLEFT", who, "TOPRIGHT", 4, 0)
  version:SetPoint ("BOTTOMLEFT", who, "BOTTOMRIGHT", 4, 0)
  version:SetWidth (95)
  version:SetJustifyH ("LEFT")
  version:SetJustifyV ("TOP")
  rf.version = version

  local raid = rf:CreateFontString (nil, "BORDER", nfn)
  raid:ClearAllPoints ()
  raid:SetPoint ("TOPLEFT", version, "TOPRIGHT", 4, 0)
  raid:SetPoint ("BOTTOMLEFT", version, "BOTTOMRIGHT", 4, 0)
  raid:SetWidth (50)
  raid:SetJustifyH ("LEFT")
  raid:SetJustifyV ("TOP")
  rf.raid = raid

  rf.SetText = function (self, who, vers, raid)
    self.who:SetText (who)
    self.version:SetText (vers)
    if (raid) then
      self.raid:SetText (K.YES_STR)
    else
      self.raid:SetText (K.NO_STR)
    end
  end

  return rf
end

local function vlist_setitem (objp, idx, slot, btn)
  if (not ksk.vcreplies) then
    return
  end

  local vcent = ksk.vcreplies[idx]
  if (not vcent) then
    return
  end
  local name = shortaclass (vcent)
  local vers = tonumber(vcent.version)
  local fn = ksk.green
  if (vers < ksk.version) then
    fn = ksk.red
  end

  btn:SetText (name, fn (tostring (vers)), vcent.raid)
  btn:SetID (idx)
  btn:Show ()
end

local function sort_vcreplies ()
  tsort (ksk.vcreplies, function (a, b)
    if (a.raid and not b.raid) then
      return true
    end
    if (b.raid and not a.raid) then
      return false
    end
    if (a.version < b.version) then
      return true
    end
    if (b.version < a.version) then
      return false
    end
    return strlower (a.name) < strlower (b.name)
  end)
  vcdlg.slist.itemcount = #ksk.vcreplies
  vcdlg.slist:UpdateList ()
end

function ksk.VersionCheckReply (sender, version)
  if (not ksk.vcreplies) then
    return
  end

  for k, v in pairs (ksk.vcreplies) do
    if (v.name == sender) then
      v.version = version
      sort_vcreplies ()
      return
    end
  end
end

local function ksk_versioncheck ()
  if (not vcdlg) then
    local ks = "|cffff2222<" .. K.KAHLUA ..">|r"
    local arg = {
      x = "CENTER", y = "MIDDLE", name = "KSKVersionCheck",
      title = strfmt (L["VCTITLE"], ks, L["MODTITLE"]),
      canmove = true,
      canresize = false,
      escclose = true,
      xbutton = false,
      width = 400,
      height = 350,
      framelevel = 64,
      titlewidth = 270,
      border = true,
      blackbg = true,
      okbutton = { text = K.OK_STR },
    }
    vcdlg = KUI:CreateDialogFrame (arg)

    vcdlg.OnAccept = function (this)
      this:Hide ()
      if (this.mainshown) then
        ksk.mainwin:Show ()
      end
      this.mainshown = nil
      ksk.vcreplies = nil
    end
    vcdlg.OnCancel = vcdlg.OnAccept

    arg = {
      x = 5, y = 0, text = L["Who"], font = "GameFontNormal",
    }
    vcdlg.str1 = KUI:CreateStringLabel (arg, vcdlg)

    arg.x = 175
    arg.text = L["Version"]
    vcdlg.str2 = KUI:CreateStringLabel (arg, vcdlg)

    arg.x = 275
    arg.text = L["In Raid"]
    vcdlg.str3 = KUI:CreateStringLabel (arg, vcdlg)

    vcdlg.sframe = MakeFrame ("Frame", nil, vcdlg.content)
    vcdlg.sframe:ClearAllPoints ()
    vcdlg.sframe:SetPoint ("TOPLEFT", vcdlg.content, "TOPLEFT", 5, -18)
    vcdlg.sframe:SetPoint ("BOTTOMRIGHT", vcdlg.content, "BOTTOMRIGHT", 0, 0)


    arg = {
      name = "KSKVersionScrollList",
      itemheight = 16, newitem = vlist_newitem, setitem = vlist_setitem,
      selectitem = function (objp, idx, slot, btn, onoff) return end,
      highlightitem = function (objp, idx, slot, btn, onoff)
        return KUI.HighlightItemHelper (objp, idx, slot, btn, onoff)
      end,
    }
    vcdlg.slist = KUI:CreateScrollList (arg, vcdlg.sframe)
  end

  --
  -- Populate the expected replies with all current raid members and if we
  -- are in a guild, with all currently online guild members. We set the
  -- version to 0 to indicate no reply yet. As replies come in we change the
  -- version number and re-sort and refresh the list.
  --

  ksk.vcreplies = {}

  if (KRP.players) then
    for k, v in pairs (KRP.players) do
      local vce = { name = k, class = v.class, version = 0, raid = true }
      if (k == K.player.name) then
        vce.version = ksk.version
      end
      tinsert (ksk.vcreplies, vce)
    end
  end

  if (K.player.is_guilded) then
    for k, v in pairs (K.guild.roster.id) do
      if ((not KRP.players or not KRP.players[v.name]) and v.online) then
        local vce = { name = v.name, class = v.class, version = 0, raid = false }
        if (v.name == K.player.name) then
          vce.version = ksk.version
        end
        tinsert (ksk.vcreplies, vce)
      end
    end
  end

  sort_vcreplies ()

  vcdlg.mainshown = ksk.mainwin:IsShown ()
  ksk.mainwin:Hide ()
  vcdlg:Show ()

  if (KRP.in_raid) then
    ksk.SendRaidAM ({proto = 2, cmd = "VCHEK"}, nil)
  end
  if (K.player.is_guilded) then
    ksk.SendGuildAM ({proto = 2, cmd = "VCHEK"}, nil)
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
  if (not bypass and ksk.CheckPerm ()) then
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
  if (not bypass and ksk.CheckPerm ()) then
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

  return ksk.CreateNewConfig (nname, false)
end

local function ksk_selectconfig(input)
  local cmd = L["CMD_SELECTCONFIG"]
  local rv, nname, _, cfgid = common_verify_input (input, cmd, true, false,
    ksk.configs,
    L["configuration %q does not exist. Try again."], nil)

  if (rv) then
    return true
  end

  ksk.SetDefaultConfig (cfgid)
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

  ksk.DeleteConfig (cfgid)
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

  return ksk.RenameConfig (cfgid, newname)
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

  return ksk.CopyConfigSpace (cfgid, newname, newid)
end

local function ksk_createuser (input)
  if (ksk.CheckPerm ()) then
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
    if ((not v.ign) and v.l == lclass) then
      classid = k
    end
  end

  if (not classid) then
    err (L["invalid class %q specified. Valid classes are:"], white (lclass))
    for k,v in pairs(K.IndexClass) do
      if ((not v.ign) and v.l) then
        printf ("    |cffffffff%s|r", v.l)
      end
    end
    return true
  end

  if (not ksk.CreateNewUser (nname, classid)) then
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

  if (not ksk.DeleteUserCmd (userid)) then
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

  return ksk.RenameUser (userid, newname)
end

local function ksk_config(input)
  if (ksk.CheckPerm ()) then
    return true
  end
  local tab = ksk.CONFIG_TAB

  local subpanel = ksk.CONFIG_LOOT_PAGE

  if (input == L["SUBCMD_LOOT"] or input == "" or not input) then
    subpanel = ksk.CONFIG_LOOT_PAGE
  elseif (input == L["SUBCMD_ROLLS"]) then
    subpanel = ksk.CONFIG_ROLLS_PAGE
  elseif (input == L["SUBCMD_ADMIN"]) then
    subpanel = ksk.CONFIG_ADMIN_PAGE
  elseif (input == L["CMD_LISTS"]) then
    tab = ksk.LISTS_TAB
    subpanel = ksk.LISTS_CONFIG_PAGE
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
  if (ksk.bossloot) then
    ksk.mainwin:SetTab (ksk.LOOT_TAB, ksk.LOOT_ASSIGN_PAGE)
  else
    ksk.mainwin:SetTab (ksk.LISTS_TAB, ksk.LISTS_MEMBERS_PAGE)
  end
end

local function ksk_users()
  if (ksk.CheckPerm ()) then
    return true
  end

  ksk.mainwin:Show ()
  ksk.mainwin:SetTab (ksk.USERS_TAB, nil)
end

local function ksk_importgusers()
  if (ksk.CheckPerm ()) then
    return true
  end

  ksk.ImportGuildUsers (ksk.mainwin:IsShown ())
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

  return ksk.CreateNewList (nname)
end

local function ksk_selectlist(input)
  local cmd = L["CMD_SELECTLIST"]
  local rv, nname, _, listid = common_verify_input (input, cmd, true, false,
    ksk.cfg.lists,
    L["roll list %q does not exist. Try again."], nil)

  if (rv) then
    return true
  end

  ksk.SelectList (listid)
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

  ksk.DeleteListCmd (listid)
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

  return ksk.RenameList (listid, newname)
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

  return ksk.CopyList (listid, newname, ksk.currentid)
end

local function ksk_loot (input)
  local subpanel = ksk.LOOT_ASSIGN_PAGE

  if (input == L["SUBCMD_ASSIGN"] or input == "" or not input) then
    subpanel = ksk.LOOT_ASSIGN_PAGE
  elseif (input == L["SUBCMD_ITEMS"]) then
    if (ksk.CheckPerm ()) then
      return true
    end
    subpanel = ksk.LOOT_ITEMS_PAGE
  elseif (input == L["SUBCMD_HISTORY"]) then
    if (ksk.CheckPerm ()) then
      return true
    end
    subpanel = ksk.LOOT_HISTORY_PAGE
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
  ksk.mainwin:SetTab (ksk.LISTS_TAB, ksk.LISTS_MEMBERS_PAGE)
end

local function ksk_sync (input)
  if (ksk.CheckPerm ()) then
    return true
  end

  ksk.mainwin:Show ()
  ksk.mainwin:SetTab (ksk.SYNC_TAB)
end

local function ksk_items (input)
  if (ksk.CheckPerm ()) then
    return true
  end

  ksk.mainwin:Show ()
  ksk.mainwin:SetTab (ksk.LOOT_TAB, ksk.LOOT_ITEMS_PAGE)
end

local function ksk_history (input)
  if (ksk.CheckPerm ()) then
    return true
  end

  ksk.mainwin:Show ()
  ksk.mainwin:SetTab (ksk.LOOT_TAB, ksk.LOOT_HISTORY_PAGE)
end

local function ksk_additem (input)
  if (ksk.CheckPerm ()) then
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

  ksk.AddItem (itemid, ilink)
end

local function ksk_addloot (input)
  if (ksk.CheckPerm ()) then
    return true
  end

  if (not ksk.AmIML ()) then
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

  ksk.AddLoot (ilink)
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
    rs=strfmt (" ksk.raid:yes num_members:%d is_rl=%s is_aorl=%s is_ml=%s ml=%q missing=%d", KLD.num_members, tostring(KLD.is_rl), tostring(KLD.is_aorl), tostring(KLD.is_ml), tostring(KLD.master_looter), ksk.nmissing)
  end

  printf ("init=%s susp=%s myuid=%s mymainid=%s isadmin=%s" .. rs, tostring(ksk.initialised), tostring(ksk.suspended), tostring(ksk.csd.myuid), tostring(ksk.csd.mymainid), tostring(ksk.csd.is_admin))
end

local function ksk_resetpos (input)
  if (ksk.mainwin) then
    ksk.mainwin:SetPoint ("TOPLEFT", UIParent, "TOPLEFT", 100, -100)
  end
end

local function ksk_repair (input)
  ksk.RepairDatabases (true, true)
  ReloadUI ()
end

local function ksk_suspend (input)
  me.SetSuspended (true)
end

local function ksk_resume (input)
  me.SetSuspended (false)
end

local function ksk_refresh (input)
  KRP.UpdateGroup (false, true, false)
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

--
-- Function: ksk.RefreshCSData ()
-- Purpose : Re-calculate session temporary config values based on the
--           current stored values in each config. This does not change
--           ksk.csd to point to a new config, it simply changes all of
--           the data withing ksk.csdata.
-- Returns : Nothing.
--
function ksk.RefreshCSData ()
  if (not ksk.configs) then
    return
  end

  for k,v in pairs(ksk.configs) do
    if (not ksk.csdata[k]) then
      ksk.csdata[k] = {}
      ksk.csdata[k].reserved = {}
    end
    ksk.UpdateUserSecurity (k)
  end

  for k,v in pairs (ksk.csdata) do
    if (not ksk.configs[k]) then
      ksk.csdata[k] = nil
    end
  end

  if (ksk.currentid) then
    ksk.csd = ksk.csdata[ksk.currentid]
    ksk:SendIPC ("CONFIG_ADMIN", ksk.csd.is_admin ~= nil)
  end
end

function ksk.CreateNewID (strtohash)
  local _, y, mo, d, h, m = ksk.TimeStamp ()
  local ts = strfmt ("%02d%02d%02d", y-2000, mo, d)
  local crc = H:CRC32(ts, nil, false)
  crc = H:CRC32(tostring(h), crc, false)
  crc = H:CRC32(tostring(m), crc, false)
  crc = H:CRC32(strtohash, crc, true)
  ts = ts .. K.hexstr (crc)
  return ts
end

function ksk.CheckPerm (cfg)
  local cfg = cfg or ksk.currentid

  if (not cfg or not ksk.configs or not ksk.configs[cfg]
      or not ksk.csdata[cfg]) then
    return true
  end

  if (not ksk.csdata[cfg].is_admin) then
    err (L["you do not have permission to do that in this configuration."])
    return true
  end

  return false
end

function ksk.CanChangeConfigType ()
  K:UpdatePlayerAndGuild ()
  if (K.player.is_guilded == false) then
     return false
  else
    if (K.player.is_gm == true) then
      return true
    end
  end
  return false
end

local function update_bcast_button ()
  if (ksk.csd.is_admin) then
    if (ksk.cfg.cfgtype == ksk.CFGTYPE_GUILD) then
      ksk.qf.bcastbutton:SetEnabled (true)
    elseif (ksk.cfg.cfgtype == ksk.CFGTYPE_PUG) then
      ksk.qf.bcastbutton:SetEnabled (ksk.AmIML () or KRP.is_aorl)
    end
  else
    ksk.qf.bcastbutton:SetEnabled (false)
  end
end

function ksk.FullRefreshUI (reset)
  ksk.RefreshConfigUI (reset)
  ksk.RefreshListsUI (reset)
  ksk.RefreshLootUI (reset)
  ksk.RefreshUsersUI (reset)
  ksk.RefreshSyncUI (reset)
end

function ksk.FullRefresh (reset)
  ksk.FullRefreshUI (reset)
  K:UpdatePlayerAndGuild ()
  ksk.UpdateUserSecurity ()
  ksk.RefreshCSData ()
  KRP.UpdateGroup (false, true, false)

  -- JKJ FIXME: this logic should move into the refresh functions above.
  local en = true
  local kct = ksk.mainwin.currenttab
  local kmt = ksk.mainwin.tabs

  if (not ksk.csd.is_admin) then
    en = false
    if ((kct >= ksk.NON_ADMIN_THRESHOLD) or
        (kct == ksk.LISTS_TAB and kmt[ksk.LISTS_TAB].currenttab > ksk.LISTS_MEMBERS_PAGE) or
        (kct == ksk.LOOT_TAB and kmt[ksk.LOOT_TAB].currenttab > ksk.LOOT_ASSIGN_PAGE))
    then
      ksk.mainwin:SetTab (ksk.LOOT_TAB, ksk.LOOT_ASSIGN_PAGE)
      ksk.mainwin:SetTab (ksk.LISTS_TAB, ksk.LISTS_MEMBERS_PAGE)
    end
  end

  ksk.qf.userstab:SetShown (en)
  ksk.qf.synctab:SetShown (en)
  ksk.qf.configtab:SetShown (en)
  ksk.qf.iedittab:SetShown (en)
  ksk.qf.historytab:SetShown (en)
  ksk.qf.listcfgtab:SetShown (en)

  if (ksk.cfg.cfgtype == ksk.CFGTYPE_GUILD) then
    ksk.qf.bcastbutton:SetEnabled (en)
  else
    ksk.qf.bcastbutton:SetEnabled (KRP.is_aorl)
  end

  -- Only the config owner can see most of the config tab
  local cen = false
  if (ksk.csd.is_admin ~= 2) then
    if (kct == ksk.CONFIG_TAB and kmt[ksk.CONFIG_TAB].currenttab > ksk.NON_ADMIN_CONFIG_THRESHOLD) then
      ksk.mainwin:SetTab (ksk.CONFIG_TAB, ksk.CONFIG_LOOT_PAGE)
    end
  else
    cen = true
  end
  ksk.qf.cfgadmintab:SetShown (cen)

  if (reset) then
    ksk.SelectListByIdx (1)
  end
end

local function player_info_updated (evt, ...)
  if (ksk.initialised) then
    ksk.UpdateUserSecurity ()
  end

  RequestRaidInfo ()

  local en = K.player.is_guilded and ksk.csd.is_admin ~= nil
  ksk.qf.guildimp:SetEnabled (en)

  local iv = { text = L["None"], value = 0 }
  local rvals = {}
  tinsert (rvals, iv)

  if (K.player.is_guilded) then
    for i = 1, K.guild.numranks do
      iv = {text = K.guild.ranks[i], value = i }
      tinsert (rvals, iv)
    end
  end

  oldr = ksk.qf.lootrank:GetValue() or 0
  ksk.qf.lootrank:UpdateItems (rvals)
  ksk.qf.lootrank:SetValue (oldr)

  oldr = ksk.qf.defrankdd:GetValue() or 0
  ksk.qf.defrankdd:UpdateItems (rvals)
  ksk.qf.defrankdd:SetValue (oldr)

  oldr = ksk.qf.gdefrankdd:GetValue() or 0
  ksk.qf.gdefrankdd:UpdateItems (rvals)
  ksk.qf.gdefrankdd:SetValue (oldr)

  oldr = ksk.qf.itemrankdd:GetValue() or 0
  ksk.qf.itemrankdd:UpdateItems (rvals)
  ksk.qf.itemrankdd:SetValue (oldr)
end

function ksk.RefreshRaid ()
  KRP.UpdateGroup (true, true, true)
end

function ksk.AddItemToBossLoot (ilink, quant, lootslot)
  ksk.bossloot = ksk.bossloot or {}

  local lootslot = lootslot or 0
  local itemid = string.match (ilink, "item:(%d+)")
  local _, _, _, _, _, _, _, _, slot, _, _, icls, isubcls = GetItemInfo (ilink)
  local filt, boe = K.GetItemClassFilter (ilink)
  local ti = { itemid = itemid, ilink = ilink, slot = lootslot, quant = quant, boe = boe }
  if (icls == K.classfilters.weapon) then
    if (filt == K.classfilters.allclasses) then
      ti.strict = K.classfilters.weapons[isubcls]
      ti.relaxed = ti.strict
    else
      ti.strict = filt
      ti.relaxed = filt
    end
  elseif (icls == K.classfilters.armor) then
    if (filt == K.classfilters.allclasses) then
      ti.strict = K.classfilters.strict[isubcls]
      ti.relaxed = K.classfilters.relaxed[isubcls]
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
  else
    ti.strict = filt
    ti.relaxed = filt
  end
  tinsert (ksk.bossloot, ti)
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
    elseif (sender == K.player.name) then
      return true
    end
  end
  if (strmatch (msg, abbrevmatch)) then
    if (evt == "CHAT_MSG_WHISPER_INFORM") then
      return true
    elseif (sender == K.player.name) then
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
    if (ksk.raid) then
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
      return ksk.NewBidder (sender)
    elseif (cmd == "retract" or cmd == L["WHISPERCMD_RETRACT"]) then
      return ksk.RetractBidder (sender)
    elseif (cmd == "suicide" or cmd == L["WHISPERCMD_SUICIDE"]) then
      local uid = ksk.FindUser (sender)
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
          if (ksk.raid) then
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

--
-- Fired whenever our admin status for the currently selected config changes,
-- or when we refresh due to a config change or other events. This registers
-- messages that only an admin cares about.
--
local function ksk_config_admin_evt (evt, onoff, ...)
  if (onoff and admin_hooks_registered ~= true) then
    admin_hooks_registered = true
    ksk:RegisterEvent ("CHAT_MSG_WHISPER", chat_msg_whisper)
  elseif (not onoff and admin_hooks_registered == true) then
    admin_hooks_registered = false
    ksk:UnregisterEvent ("CHAT_MSG_WHISPER")
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
end

local function ksk_suspended_evt (evt, onoff, ...)
  if (onoff) then
    KRP:ActivateAddon ("ksk")
    KLD:ActivateAddon ("ksk")
  else
    KRP:SuspendAddon ("ksk")
    KLD:SuspendAddon ("ksk")
  end
end

--
-- This section contains the callback functions we register with KRP and KLD.
-- These add in KSK specific variables to various data structures since those
-- Kore addons now handle all raid group and loot tracking functions. We also
-- trap a number of their messages for keeping local track of loot states etc.
--

--
-- Called by KRP whenever it is starting a round of updates for the group.
-- We use this to reset the private data member called users, which is a
-- map of KSK user ID's to player names. This is useful in many places in
-- KSK to determine whether or not the given UID is in the raid, for example,
-- as well as other uses. So when we start the round of updates we null out
-- that table as it is about to be re-populated.
--
local function krp_update_group_start (_, _, pvt, ...)
  pvt.users = {}
  ksk.missing = {}
  ksk.nmissing = 0
end

local function update_denchers ()
  ksk.raid.denchers = {}

  for k, v in pairs (KRP.players) do
    if (v["ksk_dencher"]) then
      tinsert (ksk.raid.denchers, k)
    end
  end
end

--
-- Called by KRP when it is done updating all of the group info. This is a
-- callback fired at the same time as GROUP_ROSTER_CHANGED so there is no
-- need to handle both. One or the other will do.
--
local function krp_update_group_end (_, _, pvt, ...)
  if (ksk.suspended or not KRP.in_raid) then
    return
  end

  ksk.raid = ksk.raid or {}
  update_denchers ()

  ksk.RefreshAllMemberLists ()
  update_bcast_button ()
end

--
-- This is called by KRP whenever it refreshes the raid groups and a new player
-- is added to the players list. We are called with the player info as it
-- currently exists. For ease of use later we store the KSK user ID if it
-- exists in the player structure.
--
-- This must be called whenever we change configs as the info we add to each
-- player is unique to the current config.
--
local function krp_new_player (_, _, pvt, player)
  local nm = player.name
  local unkuser = nil

  player["ksk_uid"] = nil
  player["ksk_dencher"] = nil

  local uid = ksk.FindUser (nm) or "0fff"

  if (uid == "0fff") then
    local classid = player.class
    uid = uid .. ":" .. classid .. ":" .. nm
    unkuser = { name = nm, class = classid }

    if (not ksk.missing[uid]) then
      ksk.nmissing = ksk.nmissing + 1
      ksk.missing[uid] = unkuser
      if (KRP.in_raid and KLD.master_loot and ksk.csd.is_admin) then
        info (L["NOTICE: user %q is in the raid but not in the user list."], class (nm, classid))
      end
    end
    ksk.qf.addmissing:SetEnabled (ksk.csd.is_admin ~= nil)
    player["ksk_missing"] = true
    player["ksk_uid"] = nil
  else
    pvt.users[uid] = player.name
    player["ksk_uid"] = uid
    player["ksk_missing"] = nil

    for i = 1, ksk.MAX_DENCHERS do
      if (ksk.settings.denchers[i] == uid and player.online) then
        player["ksk_dencher"] = true
      end
    end
  end
end

--
-- Fired when there has been a change in group leadership. This can be fired
-- independently from GROUP_ROSTER_CHANGED, although any processing for that
-- event will also want to call this.
--
local function leader_changed_evt (evt)
  update_bcast_button ()
end

--
-- This is fired when the state changes from in raid to out, or out to in.
--
local function in_raid_changed_evt (evt, in_raid)
  if (ksk.suspended) then
    return
  end

  if (in_raid and not KRP.in_battleground) then
    local krp_private = KRP:GetPrivate ("ksk")
    ksk.raid = {}
    if (krp_private and krp_private.users) then
      ksk.raid.users = krp_private.users
    else
      ksk.raid.users = {}
    end
    if (not ksk.frdb.tempcfg) then
      update_denchers ()
      if (ksk.csd.is_admin) then
        ksk.SendRaidAM ("REQRS", "BULK")
      end
    end

    ksk.RefreshListsUIForRaid (true)
    ksk.qf.addmissing:SetEnabled (ksk.nmissing > 0 and true or false)

    if (KRP.is_ml and not ksk.csd.is_admin and not ksk.frdb.tempcfg) then
      info (L["you are the master looter but not an administrator of this configuration. You will be unable to loot effectively. Either change master looter or have the owner of the configuration assign you as an administrator."])
    end
  else
    ksk.raid = nil
    ksk.nmissing = 0
    ksk.missing = nil
    ksk.RefreshListsUIForRaid (false)
    ksk.qf.addmissing:SetEnabled (false)
    ksk.ResetBossLoot ()
  end

  update_bcast_button ()
end

local function kld_start_loot_info (_, _, pvt)
  if (ksk.suspended or not ksk.AmIML ()) then
    return
  end

  ksk.ResetBossLoot ()
end

--
-- This is called by KLD whenever a new item is added to the loot table.
-- We need to set whether or not we want to skip dealing with this item.
-- We also check to see whether or not this item is in the KSK items database
-- to be ignored or auto-disenchanted.
--
local function kld_loot_item (_, _, pvt, item)
  if (ksk.suspended or not ksk.AmIML ()) then
    return
  end

  ksk.announcedloot = ksk.announcedloot or {}

  local skipit = false
  local dencher = nil
  local itemid = nil
  local give = nil

  if (item["itemid"]) then
    itemid = item["itemid"]
  end

  if (not item.ilink or item.ilink == "" or not itemid) then
    skipit = true
  end

  if (item.locked) then
    skipit = true
  end

  if (ksk.raid and ksk.raid.denchers) then
    for k, v in pairs (ksk.raid.denchers) do
      if (not dencher) then
        -- Check to ensure that the dencher can receive the loot from master
        if (item.candidates[v]) then
          dencher = v
        end
      end
    end
  end

  if (not dencher) then
    if (item.candidates[KRP.master_looter]) then
      dencher = KRP.master_looter
    end
  end

  if (itemid and ksk.items[itemid]) then
    if (ksk.items[itemid].ignore) then
      skipit = true
    elseif (ksk.items[itemid].autodench) then
      if (dencher) then
        skipit = true
        give = dencher
      end
    elseif (ksk.items[itemid].automl) then
      if (item.candidates[KRP.master_looter]) then
        skipit = true
        give = KRP.master_looter
      end
    end
  elseif (itemid and ksk.iitems[itemid]) then
    if (ksk.iitems[itemid].ignore) then
      skipit = true
    end
  end

  local bthresh = ksk.cfg.settings.bid_threshold
  if (not skipit and dencher and bthresh and bthresh ~= 0) then
    if (item.quality < bthresh and item.quality >= KRP.loot_threshold) then
      skipit = true
      give = dencher
    end
  end

  item["ksk_skipit"] = skipit
  if (give) then
    KLD.GiveMasterLoot (item.lootslot, give)
  end

  if (not skipit) then
    ksk.AddItemToBossLoot (item.ilink, item.quantity, item.lootslot)
  end
end

--
-- This is fired when a corpse has been looted and we have retrieved all of
-- the lootable items. It can also be fired when we have changed the various
-- user lists and we want to refresh the loot so that the callbacks can access
-- the new data.
--
local function kld_end_loot_info ()
  if (ksk.suspended or not ksk.AmIML ()) then
    return
  end

  local nbossloot
  local ilist = {}

  if (not KLD.unit_name or not KLD.items or not ksk.bossloot) then
    ksk.bossloot = nil
    nbossloot = 0
  else
    nbossloot = #ksk.bossloot
    for k, v in ipairs (ksk.bossloot) do
      local ti = {v.ilink, v.quant }
      tinsert (ilist, ti)
    end
  end

  if (nbossloot == 0) then
    ksk.ResetBossLoot ()
  end

  ksk.RefreshBossLoot (nil)

  if (nbossloot > 0) then
    local uname = KLD.unit_name
    local uguid = KLD.unit_guid
    local realguid = KLD.unit_realguid

    sentoloot = true
    ksk.SendRaidAM ("OLOOT", "ALERT", uname, uguid, realguid, ilist)

    if (ksk.settings.auto_bid == true) then
      if (not ksk.mainwin:IsVisible ()) then
        ksk.autoshown = true
      end
      ksk.mainwin:Show ()
      ksk.mainwin:SetTab (ksk.LOOT_TAB, ksk.LOOT_ASSIGN_PAGE)
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

      if (dloot) then
        sendfn (strfmt (L["Loot from %s: "], uname))
        for k,v in ipairs (ksk.bossloot) do
          sendfn (v.ilink)
        end
        ksk.lastannouncetime = time ()
      end
    end
  end
end

local function looting_ended_evt (evt)
  if (ksk.suspended or not ksk.AmIML ()) then
    return
  end

  ksk.CloseLoot ()

  if (ksk.autoshown) then
    ksk.autoshown = nil
    ksk.mainwin:Hide ()
  end

  if (sentoloot) then
    ksk.SendRaidAM ("CLOOT", "ALERT")
  end
  sentoloot = nil
end

local function ksk_initialised_evt (evt, ...)
  if (ksk.initialised) then
    return
  end

  ksk.initialised = true

  -- JKJ FIXME: The only event that should be globally trapped is
  -- KRP:LOOT_METHOD_UPDATED. Only the master looter cares about any of
  -- these other events. All other users, including other admins, get their
  -- data from the mod, not directly from the game.

  ksk:RegisterIPC ("CONFIG_ADMIN", ksk_config_admin_evt)
  ksk:RegisterIPC ("SUSPENDED", ksk_suspended_evt)
  KRP:RegisterIPC ("IN_RAID_CHANGED", in_raid_changed_evt)
  KRP:RegisterIPC ("LEADER_CHANGED", leader_changed_evt)
  KRP:RegisterIPC ("ROLE_CHANGED", leader_changed_evt)
  KLD:RegisterIPC ("LOOTING_ENDED", looting_ended_evt)
  K:RegisterMessage ("PLAYER_INFO_UPDATED", player_info_updated)

  KLD:AddonCallback ("ksk", "start_loot_info", kld_start_loot_info)
  KLD:AddonCallback ("ksk", "loot_item", kld_loot_item)
  KLD:AddonCallback ("ksk", "end_loot_info", kld_end_loot_info)
  KRP:AddonCallback ("ksk", "update_group_start", krp_update_group_start)
  KRP:AddonCallback ("ksk", "update_group_end", krp_update_group_end)
  KRP:AddonCallback ("ksk", "new_player", krp_new_player)

  KRP:ActivateAddon ("ksk")
  KLD:ActivateAddon ("ksk")

  ksk.FullRefresh (true)
  ksk.SelectListByIdx (1)
  ksk.SetDefaultConfig (ksk.frdb.defconfig, true, true)
  ksk:SendIPC ("CONFIG_ADMIN", ksk.csd.is_admin ~= nil)

  --
  -- Broadcasts a list of all configurations we have, and the latest events
  -- we have for each user. The recipients of the message use this to trim
  -- old events from their lists to save space.
  --
  ksk.SyncCleanup ()
end

local function ksk_initialisation ()
  if (ksk.initialised) then
    return
  end

  ksk.db = DB:New("KKonferSKDB", nil, "Default")
  ksk.frdb = ksk.db.factionrealm

  if (not ksk.frdb.configs) then
    ksk.frdb.nconfigs = 0
    ksk.frdb.configs = {}
    ksk.configs = ksk.frdb.configs
    ksk.frdb.tempcfg = true -- Must be set true before call to CreateNewConfig
    ksk.CreateNewConfig (" ", true, true, "1")
    ksk.frdb.dbversion = ksk.dbversion
  end

  -- A lot of utility functions depend on this being set so ensure it is done
  -- early before we call any other functions.
  ksk.configs = ksk.frdb.configs

  -- ksk.SetDefaultConfig (called next) depends on ksk.csdata being set up
  -- and correct, so "refresh" that now.
  ksk.RefreshCSData ()

  -- Set up all of the various global aliases and the like.
  ksk.SetDefaultConfig (ksk.frdb.defconfig, true, true)

  ksk.UpdateDatabaseVersion ()

  ksk.suspended = ksk.frdb.suspended or false

  ksk.InitialiseUI ()

  K.comm.RegisterComm (ksk, ksk.CHAT_MSG_PREFIX)

  ksk:RegisterIPC ("INITIALISED", ksk_initialised_evt)

  ksk:SendIPC ("INITIALISED")
end

function ksk:OnLateInit ()
  ksk_initialisation ()
  check_for_other_konfer ()
end

