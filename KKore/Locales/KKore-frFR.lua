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

local L = LibStub("AceLocale-3.0"):NewLocale("KKore", "frFR")
if (not L) then
  return
end

--
-- A few strings that are very commonly used that can be translated once.
-- These are mainly used in user interface elements so the strings should
-- be short, preferably one word.
--
K.OK_STR = "OK"
K.CANCEL_STR = "Annuler"
K.ACCEPT_STR = "Accepter"
K.CLOSE_STR = "Fermer"
K.OPEN_STR = "Ouvrir"
K.HELP_STR = "Aide"
K.YES_STR = "Oui"
K.NO_STR = "Non"
K.KAHLUA = "KahLua"

L["CMD_KAHLUA"] = "kahlua"
L["CMD_KKORE"] = "kkore"
L["CMD_HELP"] = "aide"
L["CMD_LIST"] = "liste"
L["CMD_DEBUG"] = "debug"
L["CMD_VERSION"] = "version"

L["KAHLUA_VER"] = "(Version %d)"
L["KAHLUA_DESC"] = "un ensemble d'améliorations de l'interface utilisateur."
L["KORE_DESC"] = "Fonctionnaliés %s du coeur, telles que le debug ou les profils."
L["Usage: %s/%s module [arg [arg...]]%s"] = "Utilisation : %s/%s module [arg [arg...]]%s"
L["    Where module is one of the following modules:"] = "    module étant l'in des modules suivants :"
L["For help with any module, type %s/%s module %s%s."] = "Pour une aide sur l'un des modules, tapez %s/%s module %s%s."
L["KahLua Kore usage: %s/%s command [arg [arg...]]%s"] = "Utilisation de KahLua Kore : %s/%s commande [arg [arg...]]%s."
L["%s/%s %s module level%s"] = "%s/%s %s module level%s"
L["  Sets the debug level for a module. 0 disables."] = "  Définit le niveau de déboguage pour un module. 0 désactive."
L["  The higher the number the more verbose the output."] = "  Plus le nombre est grand, plus la sortie est détaillée."
L["  Lists all modules registered with KahLua."] = "  Liste tous les modules enregistrés avec KahLua."
L["The following modules are available:"] = "Les modules suivants sont disponibles :"
L["Cannot enable debugging for '%s' - no such module."] = "Impossible d'activer le déboguage pour '%s' - module inexistant."
L["Debug level %d out of bounds - must be between 0 and 10."] = "Niveau de déboguage %s hors limites - doit être compris entre 0 et 10."
L["Module '%s' does not exist. Use %s/%s %s%s for a list of available modules."] = "Module '%s' inexistant. Utilisez %s/%s %s%s pour une liste des modules disponibles."
L["KKore extensions loaded:"] = "Extensions KKore chargées :"
L["Chest"] = "Coffre"

L["Not Set"] = "Non d\195\169fini"
L["Tank"] = "Tank"
L["Ranged DPS"] = "DPS distant"
L["Melee DPS"] = "DPS CaC"
L["Healer"] = "Heal"
L["Spellcaster"] = "DPS magique"
L["your version of %s is out of date. Please update it."] = "Votre version de %s n'est pas \195\160 jour. T\195\169l\195\169chargez-la sur le site des GDO."
L["VCTITLE"] = "%s %s Version Check"
L["Version"] = "Version"
L["In Raid"] = "In Raid"
L["Who"] = "Qui"
L["Shield"] = true

L["KONFER_SEL_TITLE"] = "S\195\169lectionner le module Konfer %s actif"
L["KONFER_SEL_HEADER"] = "Vous avez plusieurs add-ons Konfer %s install\195\169s, et plus d'un est actif et configur\195\169 pour s'ouvrir automatiquement lors du loot d'un corps ou d'un coffre. Ceci peut provoquer des conflits, vous devez donc choisir lequel activer, tous les autres seront d\195\169sactiv\195\169s."
L["KONFER_SEL_DDTITLE"] = "Choisir le module \195\160 activer"
L["KONFER_ACTIVE"] = "activ\195\169"
L["KONFER_SUSPENDED"] = "d\195\169sactiv\195\169"
L["KONFER_SUSPEND_OTHERS"] = "Vous venez d'activer le module Konfer %s ci-dessus, mais d'autres modules Konfer sont \195\169galement activ\195\169s. Avoir plusieurs modules Konfer actifs en m\195\170me temps peut g\195\169n\195\169rer des probl\195\168mes, notamment si plus d'un est configur\195\169 pour s'ouvrir automatiquement lors d'un loot. Nous vous conseillons de d\195\169sactiver tous les autres add-ons Konfer. Pour suivre ce conseil et faire de ce module le seul actif, cliquez sur 'Ok'. Si vous \195\170tes certain de vouloir laisser plusieurs add-ons Konfer actifs, cliquez sur 'Annuler'."
