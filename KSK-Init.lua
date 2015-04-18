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
local strlen = string.len
local strfind = string.find
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

--
-- This file contains all of the UI initialisation code for KahLua KonferSK.
--

local maintitle = "|cffff2222<" .. K.KAHLUA .. ">|r " .. L["MODTITLE"]

local mainwin = {
  x = "CENTER", y = "MIDDLE",
  name = "KKonferSK",
  title = maintitle,
  canresize = "HEIGHT",
  canmove = true,
  escclose = true,
  xbutton = true,
  width = 512,
  height = 512,
  minwidth = 512,
  minheight = 512,
  level = 8,
  tltexture = "Interface\\Addons\\KKonferSK\\KKonferSK.blp",
  tabs = {
    lists = {
      text = L["Lists"],
      id = tostring (ksk.LISTS_TAB),
      title = maintitle .. " - " .. L["List Manager"],
      vsplit = { width = 180 }, tabframe = "RIGHT",
      tabs = {
        members = { text = L["Members"],id = tostring (ksk.LISTS_MEMBERS_TAB) },
        config = { text = L["Config"],id = tostring (ksk.LISTS_CONFIG_TAB) },
      },
    },
    loot = {
      text = L["Loot"],
      id = tostring (ksk.LOOT_TAB),
      title = maintitle .. " - " .. L["Loot Manager"],
      tabs = {
        assign = { text = L["Assign Loot"],
          id = tostring (ksk.LOOT_ASSIGN_TAB), 
          vsplit = { width = 180}, },
        itemedit = { text = L["Item Editor"],
          id = tostring (ksk.LOOT_ITEMS_TAB),
          vsplit = { width = 225}, },
        history = { text = L["History"],
          id = tostring (ksk.LOOT_HISTORY_TAB),
          hsplit = { height = 48 }, },
      },
    },
    users = {
      text = L["Users"],
      id = tostring (ksk.USERS_TAB), vsplit = { width = 180},
      title = maintitle .. " - " .. L["User List Manager"],
    },
    sync = {
      text = L["Sync"],
      id = tostring (ksk.SYNC_TAB), vsplit = { width = 180},
      title = maintitle .. " - " .. L["Sync Manager"],
    },
    config = {
      text = L["Config"],
      id = tostring (ksk.CONFIG_TAB),
      title = maintitle .. " - " .. L["Config Manager"],
      tabs = {
        loot = { text = L["Loot"], id = tostring (ksk.CONFIG_LOOT_TAB) },
        rolls = { text = L["Rolls"], id = tostring (ksk.CONFIG_ROLLS_TAB) },
        admin = { text = L["Admin"], id = tostring (ksk.CONFIG_ADMIN_TAB),
          vsplit = { width = 180}, },
      },
    },
  }
}

ksk.mainwin = KUI:CreateTabbedDialog (mainwin)

function ksk:InitialiseUI()
  if (ksk.initialised) then
    return
  end

  --
  -- Every panel and every sub-panel needs to display the current config and
  -- the config selector drop-down. Thus, the most convenient place to put
  -- this is in the outer frame's topbar. It is the responsibility of the
  -- panels and subtabs to not overwrite this.
  --
  local tbf = ksk.mainwin.topbar
  local arg = { 
    x = 250, y = 0,
    name = "ConfigSpacesDropdown",
    itemheight = 16,
    dwidth = 125, items = KUI.emptydropdown,
    level = 12,
    tooltip = { title = L["TIP028.0"], text = L["TIP028.1"] },
  }
  ksk.mainwin.cfgselector = KUI:CreateDropDown (arg, tbf)
  ksk.mainwin.cfgselector:ClearAllPoints ()
  ksk.mainwin.cfgselector:SetPoint ("TOPRIGHT", tbf, "TOPRIGHT", 4, -4)
  ksk.mainwin.cfgselector:Catch ("OnValueChanged", function (this, evt, nv)
    ksk:SetDefaultConfig (nv)
  end)
  arg = {}

  ksk.qf.cfgsel = ksk.mainwin.cfgselector
  ksk.qf.lootopts = ksk.mainwin.tabs[ksk.CONFIG_TAB].tabs[ksk.CONFIG_LOOT_TAB].content
  ksk.qf.rollopts = ksk.mainwin.tabs[ksk.CONFIG_TAB].tabs[ksk.CONFIG_ROLLS_TAB].content
  ksk.qf.cfgadmin = ksk.mainwin.tabs[ksk.CONFIG_TAB].tabs[ksk.CONFIG_ADMIN_TAB].content
  ksk.qf.configtab = ksk.mainwin.tabs[ksk.CONFIG_TAB].tbutton
  ksk.qf.userstab = ksk.mainwin.tabs[ksk.USERS_TAB].tbutton
  ksk.qf.synctab = ksk.mainwin.tabs[ksk.SYNC_TAB].tbutton
  ksk.qf.loot = ksk.mainwin.tabs[ksk.LOOT_TAB].tabs[ksk.LOOT_ASSIGN_TAB].content
  ksk.qf.iedit = ksk.mainwin.tabs[ksk.LOOT_TAB].tabs[ksk.LOOT_ITEMS_TAB].content
  ksk.qf.iedittab = ksk.mainwin.tabs[ksk.LOOT_TAB].tabs[ksk.LOOT_ITEMS_TAB].tbutton
  ksk.qf.listcfgtab = ksk.mainwin.tabs[ksk.LISTS_TAB].tabs[ksk.LISTS_CONFIG_TAB].tbutton
  ksk.qf.cfgadmintab = ksk.mainwin.tabs[ksk.CONFIG_TAB].tabs[ksk.CONFIG_ADMIN_TAB].tbutton

  ksk:InitialiseConfigGUI ()
  ksk:InitialiseListsGUI ()
  ksk:InitialiseUsersGUI ()
  ksk:InitialiseLootGUI ()
  ksk:InitialiseSyncGUI ()

  ksk:RefreshListDropDowns ()
  ksk:RefreshConfigSpaces ()
  ksk:RefreshUsers ()
  ksk:RefreshLists ()
  ksk:RefreshHistory ()
  ksk:RefreshItemList ()
  ksk:UpdateAllConfigSettings ()
  ksk.currentid = ksk.frdb.defconfig
  ksk.initialised = true
  K:UpdatePlayerAndGuild ()
  ksk.mainwin.OnShow = function (this, evt)
    K:UpdatePlayerAndGuild ()
    ksk.mainwin.OnShow = function (this, evt)
      ksk:CleanupLootRoll ()
    end
  end
end

