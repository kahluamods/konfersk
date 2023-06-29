--[[
   KahLua Kore - core library functions for KahLua addons.
     WWW: http://kahluamod.com/kore
     Git: https://github.com/kahluamods/kore
     IRC: #KahLua on irc.freenode.net
     E-mail: me@cruciformer.com
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

local K = LibStub:GetLibrary("KKore")

if (not K) then
  return
end

local L = LibStub("AceLocale-3.0"):NewLocale("KKore", "enUS", true)
if (not L) then
  return
end

--
-- A few strings that are very commonly used that can be translated once.
-- These are mainly used in user interface elements so the strings should
-- be short, preferably one word.
--
K.OK_STR = "Ok"
K.CANCEL_STR = "Cancel"
K.ACCEPT_STR = "Accept"
K.CLOSE_STR = "Close"
K.OPEN_STR = "Open"
K.HELP_STR = "Help"
K.YES_STR = "Yes"
K.NO_STR = "No"
K.KAHLUA = "KahLua"

L["CMD_KAHLUA"] = "kahlua"
L["CMD_KKORE"] = "kkore"
L["CMD_HELP"] = "help"
L["CMD_LIST"] = "list"
L["CMD_DEBUG"] = "debug"
L["CMD_VERSION"] = "version"

L["KAHLUA_VER"] = "(version %d)"
L["KAHLUA_DESC"] = "a suite of user interface enhancements."
L["KORE_DESC"] = "core %s functionality, such as debugging and profiling."
L["Usage: %s/%s module [arg [arg...]]%s"] = true
L["    Where module is one of the following modules:"] = true
L["For help with any module, type %s/%s module %s%s."] = true
L["KahLua Kore usage: %s/%s command [arg [arg...]]%s"] = true
L["%s/%s %s module level%s"] = true
L["  Sets the debug level for a module. 0 disables."] = true
L["  The higher the number the more verbose the output."] = true
L["  Lists all modules registered with KahLua."] = true
L["The following modules are available:"] = true
L["Cannot enable debugging for '%s' - no such module."] = true
L["Debug level %d out of bounds - must be between 0 and 10."] = true
L["Module '%s' does not exist. Use %s/%s %s%s for a list of available modules."] = true
L["KKore extensions loaded:"] = true
L["Chest"] = true

-- Konfer related stuff
L["Not Set"] = true
L["Tank"] = true
L["Ranged DPS"] = true
L["Melee DPS"] = true
L["Healer"] = true
L["Spellcaster"] = true
L["your version of %s is out of date. Please update it."] = true
L["VCTITLE"] = "%s %s Version Check"
L["Version"] = true
L["In Raid"] = true
L["Who"] = true
L["Shield"] = true

L["KONFER_SEL_TITLE"] = "Select Active %s Konfer Module"
L["KONFER_SEL_HEADER"] = "You have multiple %s Konfer modules installed, and more than one of them is active and set to auto-open when you loot a corpse or chest. This can cause conflicts and you need to select which one of the modules should be the active one. All others will be suspended."
L["KONFER_SEL_DDTITLE"] = "Select Module to Make Active"
L["KONFER_ACTIVE"] = "active"
L["KONFER_SUSPENDED"] = "suspended"
L["KONFER_SUSPEND_OTHERS"] = "You have just activated the %s Konfer module above, but other Konfer modules are also currently active. Having multiple Konfer modules active at the same time can cause problems, especially if more than one of them is set to auto-open on loot. It is suggested that you suspend all other Konfer modules. If you would like to do this and make the module above the only active one, press 'Ok' below. If you are certain you want to leave multiple Konfer modules running, press 'Cancel'."
