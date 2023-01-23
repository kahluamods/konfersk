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

local L = LibStub("AceLocale-3.0"):NewLocale("KKore", "deDE")
if (not L) then
  return
end

--
-- A few strings that are very commonly used that can be translated once.
-- These are mainly used in user interface elements so the strings should
-- be short, preferably one word.
--
K.OK_STR = "Ok"
K.CANCEL_STR = "Abbrechen"
K.ACCEPT_STR = "Akzeptieren"
K.CLOSE_STR = "Schließen"
K.OPEN_STR = "\195\150ffnen"
K.HELP_STR = "Hilfe"
K.YES_STR = "Ja"
K.NO_STR = "Nein"
K.KAHLUA = "KahLua"

L["CMD_KAHLUA"] = "kahlua"
L["CMD_KKORE"] = "kkore"
L["CMD_HELP"] = "hilfe"
L["CMD_LIST"] = "list"
L["CMD_DEBUG"] = "debig"
L["CMD_VERSION"] = "version"

L["KAHLUA_VER"] = "(Version %d)"
L["KAHLUA_DESC"] = "eine Sammlung von User Interface Verbesserungen."
L["KORE_DESC"] = "Core %s Fuktionalität, wie z. B. debugging und profiling."
L["Usage: %s/%s module [arg [arg...]]%s"] = "Benutzung: %s/%s Modul [arg [arg...]]%s"
L["    Where module is one of the following modules:"] = "    Wo das Modul eines der folgenden ist:"
L["For help with any module, type %s/%s module %s%s."] = "Für Hilfe mit einem der Module, tippe %s/%s Modul %s%s."
L["KahLua Kore usage: %s/%s command [arg [arg...]]%s"] = "KahLua Kore Benutzung: %s/%s Kommando [arg [arg...]]%s."
L["%s/%s %s module level%s"] = "%s/%s %s Modul level%s"
L["  Sets the debug level for a module. 0 disables."] = "  Setzt das Debug Level für ein Modul. 0 Deaktiviert es."
L["  The higher the number the more verbose the output."] = "  Je höher die Zahl, desto ausführlicher ist die Ausgabe."
L["  Lists all modules registered with KahLua."] = "  Listet alle Module die mit KahLua registriert sind auf."
L["The following modules are available:"] = "Die folgenden Module sind verfügbar:"
L["Cannot enable debugging for '%s' - no such module."] = "Kann das debuggen für '%s' nicht aktivieren - dieses Modul existiert nicht."
L["Debug level %d out of bounds - must be between 0 and 10."] = "Debug Level %d ist außerhalb des Rahmens - es muss zwischen 0 und 10 liegen."
L["Module '%s' does not exist. Use %s/%s %s%s for a list of available modules."] = "Modul '%s' existiert nicht. Benutze %s/%s %s%s für eine Liste aller verfügbarer Module."
L["KKore extensions loaded:"] = "KKore Erweiterungen geladen:"
L["Chest"] = true

L["Not Set"] = "Nicht festgelegt"
L["Tank"] = "Tank"
L["Ranged DPS"] = "Ranged DPS"
L["Melee DPS"] = "Melee DPS"
L["Healer"] = "Healer"
L["Spellcaster"] = "Spellcaster"
L["your version of %s is out of date. Please update it."] = "Deine Version von %s ist nicht aktuell. Bitte aktualisiere sie."
L["VCTITLE"] = "%s %s Version Check"
L["Version"] = "Version"
L["In Raid"] = "In Raid"
L["Who"] = "Wer"
L["Shield"] = true

L["KONFER_SEL_TITLE"] = "Auswahl des aktiven %s Konfer-Moduls"
L["KONFER_SEL_HEADER"] = "Du hast %s Konfer-Module installiert und mehr als eines von ihnen ist aktiv und eingestellt auf automatisches Ãffnen, wenn ein Leichnam oder eine Kiste/Truhe geplÃ¼ndert wird. Dies kann Konflikte verursachen, du solltest eines der Module als aktives auswÃ¤hlen. Alle anderen werden dann ausgeschlossen."
L["KONFER_SEL_DDTITLE"] = "Modul-Auswahl zum Aktivieren"
L["KONFER_ACTIVE"] = "aktiv"
L["KONFER_SUSPENDED"] = "ausgeschlossen"
L["KONFER_SUSPEND_OTHERS"] = "Du hast das %s Konfer-Modul gerade aktiviert, aber andere Konfer-Module sind ebenfalls aktiv. Mehrere Module zur selben Zeit aktiv zu haben, kann Probleme verursachen, besonders wenn mehr als eins sich beim Looten automatisch Ã¶ffnet. Es wird empfohlen, die anderen Module zu deaktivieren. Wenn du dies tun willst und nur das ausgewÃ¤hlte aktivieren willst, drÃ¼cke den 'OK'-Button. Wenn du sicher bist, dass mehrere Konfer-Module laufen sollen, dann drÃ¼cke 'Abbrechen'."
