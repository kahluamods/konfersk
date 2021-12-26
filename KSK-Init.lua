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

local _G = _G

--
-- This file contains all of the UI initialisation code for KahLua KonferSK.
--

--
-- Local state variable to record the name of the last configuration we
-- selected from the config dropdown. This is used to prevent a loop where
-- the button is changed when a new config is selected, which makes a call
-- to refresh the UI, which makes a call to set the conf, which makes a
-- call to refresh the UI ..... ad infinitum. Note that this doesn't REALLY
-- happen because the UI detects whether or not there has been an actual
-- change but that means that this code is dependent on that exact behaviour
-- which isn't a guaranteed contract between the UI code and this. So this
-- errs on the side of caution and prevents what would otherwise be an
-- infinite loop.
--
local last_cfg_selected = nil

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
  deftab = ksk.LISTS_TAB,
  tabs = {
    lists = {
      text = L["Lists"],
      id = ksk.LISTS_TAB,
      title = maintitle .. " - " .. L["List Manager"],
      vsplit = { width = 198 }, tabframe = "RIGHT",
      deftab = ksk.LISTS_MEMBERS_PAGE,
      tabs = {
        members = { text = L["Members"], id = ksk.LISTS_MEMBERS_PAGE },
        config = { text = L["Config"], id = ksk.LISTS_CONFIG_PAGE },
      },
    },
    loot = {
      text = L["Loot"],
      id = ksk.LOOT_TAB,
      title = maintitle .. " - " .. L["Loot Manager"],
      deftab = ksk.LOOT_ASSIGN_PAGE,
      tabs = {
        assign = { text = L["Assign Loot"], id = ksk.LOOT_ASSIGN_PAGE, 
          vsplit = { width = 180}, },
        itemedit = { text = L["Item Editor"], id = ksk.LOOT_ITEMS_PAGE,
          vsplit = { width = 225}, },
        history = { text = L["History"], id = ksk.LOOT_HISTORY_PAGE,
          hsplit = { height = 48 }, },
      },
    },
    users = {
      text = L["Users"],
      id = ksk.USERS_TAB, vsplit = { width = 210},
      title = maintitle .. " - " .. L["User List Manager"],
    },
    sync = {
      text = L["Sync"],
      id = ksk.SYNC_TAB, vsplit = { width = 180},
      title = maintitle .. " - " .. L["Sync Manager"],
    },
    config = {
      text = L["Config"],
      id = ksk.CONFIG_TAB,
      title = maintitle .. " - " .. L["Config Manager"],
      deftab = ksk.CONFIG_LOOT_PAGE,
      tabs = {
        loot = { text = L["Loot"], id = ksk.CONFIG_LOOT_PAGE },
        rolls = { text = L["Rolls"], id = ksk.CONFIG_ROLLS_PAGE },
        admin = { text = L["Admin"], id = ksk.CONFIG_ADMIN_PAGE,
          vsplit = { width = 180}, },
      },
    },
  }
}

ksk.mainwin = KUI:CreateTabbedDialog(mainwin)

function ksk:InitialiseUI()
  if (self.initialised) then
    return
  end

  --
  -- Every panel and every sub-panel needs to display the current config and
  -- the config selector drop-down. Thus, the most convenient place to put
  -- this is in the outer frame's topbar. It is the responsibility of the
  -- panels and subtabs to not overwrite this.
  --
  local tbf = self.mainwin.topbar
  local arg = { 
    x = 250, y = 0, name = "ConfigSpacesDropdown", itemheight = 16, dwidth = 135, items = KUI.emptydropdown,
    level = 12, tooltip = { title = L["TIP028.0"], text = L["TIP028.1"] }, border = "THIN",
  }
  self.mainwin.cfgselector = KUI:CreateDropDown(arg, tbf)
  self.mainwin.cfgselector:ClearAllPoints()
  self.mainwin.cfgselector:SetPoint("TOPRIGHT", tbf, "TOPRIGHT", 4, -4)
  self.mainwin.cfgselector:Catch("OnValueChanged", function(this, evt, nv)
    if (self.frdb and not self.frdb.tempcfg) then
      if (last_cfg_selected ~= nv) then
        last_cfg_selected = nv
        self:SetDefaultConfig(nv)
        if (self.qf.synctopbar) then
          self.qf.synctopbar:SetCurrentCRC()
        end
      end
    end
  end)

  self.qf.configtab = self.mainwin.tabs[self.CONFIG_TAB].tbutton
  self.qf.userstab = self.mainwin.tabs[self.USERS_TAB].tbutton
  self.qf.synctab = self.mainwin.tabs[self.SYNC_TAB].tbutton
  self.qf.iedittab = self.mainwin.tabs[self.LOOT_TAB].tabs[self.LOOT_ITEMS_PAGE].tbutton
  self.qf.historytab = self.mainwin.tabs[self.LOOT_TAB].tabs[self.LOOT_HISTORY_PAGE].tbutton
  self.qf.listcfgtab = self.mainwin.tabs[self.LISTS_TAB].tabs[self.LISTS_CONFIG_PAGE].tbutton
  self.qf.cfgadmintab = self.mainwin.tabs[self.CONFIG_TAB].tabs[self.CONFIG_ADMIN_PAGE].tbutton

  self:InitialiseListsUI()
  self:InitialiseLootUI()
  self:InitialiseUsersUI()
  self:InitialiseSyncUI()
  self:InitialiseConfigUI()
end
