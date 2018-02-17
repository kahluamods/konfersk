--[[
   KahLua KonferSK - a suicide kings loot distribution addon.
     WWW: http://kahluamod.com/ksk
     Git: https://github.com/kahluamods/konfersk
     IRC: #KahLua on irc.freenode.net
     E-mail: cruciformer@gmail.com
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
local renamedialog

--
-- This file contains functions that can be used in more than one place,
-- such as the rename dialog and others.
--

function ksk.ConfirmationDialog (ttxt, msg, val, func, farg, isshown, height, option)
  height = height or 240
  if (not ksk.confirmdlg) then
    local arg = {
      x = "CENTER", y = "MIDDLE",
      name = "KSKConfirmDialog",
      title = "",
      border = true,
      width = 450,
      height = height,
      canmove = true,
      canresize = false,
      escclose = false,
      blackbg = true,
      okbutton = { text = K.OK_STR },
      cancelbutton = { text = K.CANCEL_STR },
    }

    local ret = KUI:CreateDialogFrame (arg)
    arg = {}

    arg = {
      x = "CENTER", y = -4, height = 24, autosize = false,
      font = "GameFontNormal", text = "",
      color = {r = 1, g = 1, b = 1, a = 1 }, border = true,
      justifyh = "CENTER",
    }
    ret.str1 = KUI:CreateStringLabel (arg, ret)
    arg = {}

    arg = {
      x = 8, y = -35, width = 410, height = height - 95 - (option and 24 or 0),
      autosize = false,
      color = {r = 1, g = 0, b = 0, a = 1 }, text = "",
      font = "GameFontNormal", justifyv = "TOP",
    }
    ret.str2 = KUI:CreateStringLabel (arg, ret)
    arg = {}

    arg = {
      x = "CENTER", y = -height + 85, label = { text = ""},
    }
    ret.opt = KUI:CreateCheckBox (arg, ret)
    ret.optval = false
    ret.opt:Catch ("OnValueChanged", function (this, evt, val)
      ret.optval = val
    end)
    arg = {}

    ret.OnCancel = function (this)
      ksk.confirmdlg:Hide ()
      if (ksk.confirmdlg.isshown) then
        ksk.mainwin:Show ()
      end
    end

    ret.OnAccept = function (this)
      ksk.confirmdlg:Hide ()
      if (ksk.confirmdlg.isshown) then
        ksk.mainwin:Show ()
      end
      ksk.confirmdlg.runfunction (ksk.confirmdlg.arg, ksk.confirmdlg.optval)
    end

    ksk.confirmdlg = ret
  end

  ksk.confirmdlg:SetHeight (height)
  ksk.confirmdlg.str2:SetHeight (height - 95 - (option and 24 or 0))
  ksk.confirmdlg.opt:SetPoint ("TOP", ksk.confirmdlg, "BOTTOM", 0, 56)
  if (option) then
    ksk.confirmdlg.opt:SetText (option)
    ksk.confirmdlg.opt:Show ()
    ksk.confirmdlg.optval = false
    ksk.confirmdlg.opt:SetChecked (false)
  else
    ksk.confirmdlg.opt:Hide ()
  end
  ksk.confirmdlg:SetTitleText (ttxt)
  ksk.confirmdlg.str1:SetText (val)
  ksk.confirmdlg.str2:SetText (msg)
  ksk.confirmdlg.runfunction = func
  ksk.confirmdlg.arg = farg
  ksk.confirmdlg.isshown = isshown
  ksk.confirmdlg:Show ()
end

function ksk.RenameDialog (ttxt, oldlbl, oldval, newlbl, len, func, farg, shown)
  if (not renamedialog) then
    local arg = {
      x = "CENTER", y = "MIDDLE",
      name = "KSKRenameDialog",
      title = "",
      border = true,
      width = 450,
      height = 125,
      canmove = true,
      canresize = false,
      escclose = true,
      blackbg = true,
      okbutton = { text = K.OK_STR },
      cancelbutton = { text = K.CANCEL_STR },
    }

    local ret = KUI:CreateDialogFrame (arg)
    arg = {}

    arg = {
      x = 0, y = 0, width = 150, height = 24, autosize = false,
      justifyh = "RIGHT", font = "GameFontNormal", text = "",
    }
    ret.str1 = KUI:CreateStringLabel (arg, ret)
    arg = {}

    arg = {
      x = 0, y = 0, width = 200, height = 24, autosize = false,
      justifyh = "LEFT", font = "GameFontNormal", text = "",
      color = {r = 1, g = 1, b = 1, a = 1 }, border = true,
    }
    ret.str2 = KUI:CreateStringLabel (arg, ret)
    arg = {}

    ret.str2:ClearAllPoints ()
    ret.str2:SetPoint ("TOPLEFT", ret.str1, "TOPRIGHT", 8, 0)

    arg = {
      x = 0, y = -30, width = 150, height = 24, autosize = false,
      justifyh = "RIGHT", font = "GameFontNormal", text = "",
    }
    ret.str3 = KUI:CreateStringLabel (arg, ret)
    arg = {}

    arg = {
      x = 0, y = -30, width = 200, height = 20,
    }
    ret.input = KUI:CreateEditBox (arg, ret)
    ret.input:SetFocus ()
    arg = {}

    ret.input:ClearAllPoints ()
    ret.input:SetPoint ("TOPLEFT", ret.str3, "TOPRIGHT", 12, 0)

    ret.OnCancel = function (this)
      renamedialog:Hide ()
      if (renamedialog.isshown) then
        ksk.mainwin:Show ()
      end
    end

    ret.OnAccept = function (this)
      local rv = renamedialog.runfunction (renamedialog.input:GetText (), renamedialog.arg, true)
      if (rv) then
        renamedialog:Show ()
        renamedialog.input:SetFocus ()
      else
        renamedialog:Hide ()
        if (renamedialog.isshown) then
          ksk.mainwin:Show ()
        end
      end
    end
    ret.input.OnEnterPressed = ret.OnAccept

    renamedialog = ret
  end

  renamedialog:SetTitleText (ttxt)
  renamedialog.str1:SetText (oldlbl)
  renamedialog.str2:SetText (oldval)
  renamedialog.str3:SetText (newlbl)
  renamedialog.input:SetMaxLetters (len)
  renamedialog.runfunction = func
  renamedialog.arg = farg
  renamedialog.isshown = shown

  ksk.mainwin:Hide ()
  renamedialog:Show ()
  renamedialog.input:SetText ("")
  renamedialog.input:SetFocus ()
end

function ksk.PopupSelectionList (name, list, title, width, height, parent, itemheight, func, topspace, botspace)
  if (ksk.popupwindow) then
    ksk.popupwindow:Hide ()
    ksk.popupwindow = nil
  end

  assert (name)

  local arg = {
    name = name,
    itemheight = itemheight,
    width = width,
    height = height,
    header = topspace,
    footer = botspace,
    title = title,
    titlewidth = width - 110,
    canmove = true,
    canresize = true,
    escclose = true,
    blackbg = true,
    xbutton = false,
    level = 32,
    border = "THICK",
    x = "CENTER",
    y = "MIDDLE",
    func = function (lst, idx, arg)
      func (lst[idx].value)
    end,
    timeout = 3,
  }
  local rv = KUI:CreatePopupList (arg, parent)
  assert (rv)
  rv:UpdateList (list)
  rv:Show ()
  return rv
end

function ksk.SingleStringInputDialog (name, title, text, width, height)
  local arg = {
    x = "CENTER", y = "MIDDLE",
    name = name,
    title = title,
    border = "THICK",
    width = width,
    height = height,
    canmove = true,
    canresize = false,
    escclose = true,
    xbutton = false,
    blackbg = true,
    okbutton = { text = K.ACCEPTSTR },
    cancelbutton = { text = K.CANCELSTR },
  }

  local ret = KUI:CreateDialogFrame (arg)
  arg = {}

  arg = {
    x = 8, y = 0, width = width - 40, height = height - 90, autosize = false,
    font = "GameFontNormal", text = text, }
  ret.str1 = KUI:CreateStringLabel (arg, ret)

  arg = {}
  arg = { x = "CENTER", y = -(height - 85), len = 32 }
  ret.ebox = KUI:CreateEditBox (arg, ret)

  ret.ebox:SetFocus ()

  return ret, ret.ebox
end

