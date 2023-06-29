--[[
   KahLua Kore - core library functions for KahLua addons.
     WWW: http://kahluamod.com/kore
     Git: https://github.com/kahluamods/kore
     IRC: #KahLua on irc.freenode.net
     E-mail: me@cruciformer.com
   Please refer to the file LICENSE.txt for the Apache License, Version 2.0.

   Copyright 2008-2018 James Kean Johnston. All rights reserved.

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

local L = LibStub("AceLocale-3.0"):NewLocale("KKore", "ruRU")
if (not L) then
  return
end

--
-- A few strings that are very commonly used that can be translated once.
-- These are mainly used in user interface elements so the strings should
-- be short, preferably one word.
--
K.OK_STR = "Ok"
K.CANCEL_STR = "Отмена"
K.ACCEPT_STR = "Принять"
K.CLOSE_STR = "Закрыть"
K.OPEN_STR = "Открыть"
K.HELP_STR = "Помощь"
K.YES_STR = "Да"
K.NO_STR = "Нет"
K.KAHLUA = "KahLua"

L["CMD_KAHLUA"] = "kahlua"
L["CMD_KKORE"] = "kkore"
L["CMD_HELP"] = "help"
L["CMD_LIST"] = "list"
L["CMD_DEBUG"] = "debug"
L["CMD_VERSION"] = "version"

L["KAHLUA_VER"] = "(версия %d)"
L["KAHLUA_DESC"] = "комплекс усовершенствований UI."
L["KORE_DESC"] = "основные %s функции, такие как отладка и профили."
L["Usage: %s/%s module [arg [arg...]]%s"] = "Использование: %s/%s модуль [arg [arg...]]%s"
L["    Where module is one of the following modules:"] = "    Где модуль один из следующих:"
L["For help with any module, type %s/%s module %s%s."] = "Для помощи по любому из модулей наберите %s/%s модуль %s%s."
L["KahLua Kore usage: %s/%s command [arg [arg...]]%s"] = "KahLua Kore использование: %s/%s команда [arg [arg...]]%s."
L["%s/%s %s module level%s"] = "%s/%s %s уровень модуля %s"
L["  Sets the debug level for a module. 0 disables."] = "  Задайте уровень отладки для модуля. 0 отключить."
L["  The higher the number the more verbose the output."] = "  Чем выше число, тем более подробный вывод."
L["  Lists all modules registered with KahLua."] = "  Список всех модулей, зерегистрированных в KahLua."
L["The following modules are available:"] = "Доступны следующие модули:"
L["Cannot enable debugging for '%s' - no such module."] = "Не могу включить отладку для '%s' - модуль не существует."
L["Debug level %d out of bounds - must be between 0 and 10."] = "Уровень отладки %d вне диапазона - должен быть от 0 до 10."
L["Module '%s' does not exist. Use %s/%s %s%s for a list of available modules."] = "Модуль '%s' не существует. Используйте %s/%s %s%s для отображения списка доступных модулей."
L["KKore extensions loaded:"] = "KKore расширения загружены:"
L["Chest"] = true

L["Not Set"] = "Нет"
L["Tank"] = "Танк"
L["Ranged DPS"] = "Рэйнж ДД"
L["Melee DPS"] = "Мили ДД"
L["Healer"] = "Хилер"
L["Spellcaster"] = "Кастер"
L["your version of %s is out of date. Please update it."] = true
L["VCTITLE"] = "%s %s Version Check"
L["Version"] = true
L["In Raid"] = true
L["Who"] = true
L["Shield"] = true

L["KONFER_SEL_TITLE"] = "Выберите Активный %s Konfer Модуль"
L["KONFER_SEL_HEADER"] = "У Вас установлено несколько %s Konfer модулей, и активны более одного, когда Вы осматриваете тело монстра или сундук. Это может вызывать конфликты и Вы должны выбрать лишь один, который будет оставаться активным. Все остальные будут отключены."
L["KONFER_SEL_DDTITLE"] = "Пометить модуль как Активный"
L["KONFER_ACTIVE"] = "активный"
L["KONFER_SUSPENDED"] = "отключен"
L["KONFER_SUSPEND_OTHERS"] = "Вы активировали %s Konfer модуль, но один из других модулей сейчас также помечен как Активный. Наличие нескольких одновременно активных Konfer модулей может вызывать проблемы, особенно если они должны срабатывать при дележе добычи. Предполагается, что вы должны отключить остальные Konfer модули. Если Вы хотите это сделать и оставить активным, только этот модуль, а остальные отключить нажмите 'Ok'. Если вы уверены, что хотите оставить несколько активных Konfer модулей, нажмите 'Отмена'."
