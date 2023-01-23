--[[
   KahLua Kore - useful simple dialogs
     WWW: http://kahluamod.com/kore
     Git: https://github.com/kahluamods/kore
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

local K, KM = LibStub:GetLibrary("KKore")
assert(K, "KKoreKonfer requires KKore")
assert(tonumber(KM) >= 4, "KKoreKonfer requires KKore r4 or later")

local KUI, KM = LibStub:GetLibrary("KKoreUI")
assert(KUI, "KKoreKonfer requires KKoreUI")
assert(tonumber(KM) >= 4, "KKoreKonfer requires KKoreUI r4 or later")

local L = LibStub("AceLocale-3.0"):GetLocale("KKore")

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
local MakeFrame= KUI.MakeFrame

local ucolor = K.ucolor
local ecolor = K.ecolor
local icolor = K.icolor

function K.ConfirmationDialog(kmod, ttxt, msg, val, func, farg, isshown, height, option, xtras)
  local height = height or 240
  local confirmdlg = kmod.confirmdialog

  if (not confirmdlg) then
    local arg = {
      x = "CENTER", y = "MIDDLE",
      name = "KKoreConfirmDialog",
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
    if (xtras and type(xtras) == "table") then
      for k,v in pairs(xtras) do
        arg[k] = v
      end
    end

    local ret = KUI:CreateDialogFrame(arg)

    arg = {
      x = "CENTER", y = -4, height = 24, autosize = false,
      font = "GameFontNormal", text = "", width = 375,
      color = {r = 1, g = 1, b = 1, a = 1 }, border = true,
      justifyh = "CENTER",
    }
    ret.str1 = KUI:CreateStringLabel(arg, ret)

    arg = {
      x = 8, y = -35, width = 410, height = height - 95 - (option and 24 or 0),
      autosize = false,
      color = {r = 1, g = 0, b = 0, a = 1 }, text = "",
      font = "GameFontNormal", justifyv = "TOP",
    }
    ret.str2 = KUI:CreateStringLabel(arg, ret)

    arg = {
      x = "CENTER", y = -height + 85, label = { text = ""},
    }
    ret.opt = KUI:CreateCheckBox(arg, ret)
    ret.optval = false
    ret.opt:Catch("OnValueChanged", function(this, evt, val)
      ret.optval = val
    end)

    ret.OnCancel = function(this)
      local tcd = this.kmod.confirmdialog
      tcd:Hide()
      if (tcd.isshown) then
        tcd.kmod.mainwin:Show()
      end
      tcd.isshown = nil
    end

    ret.OnAccept = function(this)
      local tcd = this.kmod.confirmdialog
      tcd:Hide()
      if (tcd.isshown) then
        tcd.kmod.mainwin:Show()
      end
      tcd.runfunction(this.kmod, tcd.arg, tcd.optval)
      tcd.isshown = nil
    end

    ret.kmod = kmod
    kmod.confirmdialog = ret
    confirmdlg = kmod.confirmdialog
  end

  confirmdlg:SetHeight(height)
  confirmdlg.str2:SetHeight(height - 95 - (option and 24 or 0))
  confirmdlg.opt:SetPoint("TOP", confirmdlg, "BOTTOM", 0, 56)
  if (option) then
    confirmdlg.opt:SetText(option)
    confirmdlg.opt:Show()
    confirmdlg.optval = false
    confirmdlg.opt:SetChecked(false)
  else
    confirmdlg.opt:Hide()
  end
  confirmdlg:SetTitleText(ttxt)
  confirmdlg.str1:SetText(val)
  confirmdlg.str2:SetText(msg)
  confirmdlg.runfunction = func
  confirmdlg.arg = farg
  confirmdlg.isshown = isshown

  confirmdlg.kmod.mainwin:Hide()
  confirmdlg:Show()
end

function K.RenameDialog(kmod, ttxt, oldlbl, oldval, newlbl, len, func, farg, shown, xtras)
  local renamedlg = kmod.renamedialog

  if (not renamedlg) then
    local arg = {
      x = "CENTER", y = "MIDDLE",
      name = "KKoreRenameDialog",
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
    if (xtras and type(xtras) == "table") then
      for k,v in pairs(xtras) do
        arg[k] = v
      end
    end

    local ret = KUI:CreateDialogFrame(arg)

    arg = {
      x = 0, y = 0, width = 150, height = 24, autosize = false,
      justifyh = "RIGHT", font = "GameFontNormal", text = "",
    }
    ret.str1 = KUI:CreateStringLabel(arg, ret)

    arg = {
      x = 0, y = 0, width = 200, height = 24, autosize = false,
      justifyh = "LEFT", font = "GameFontNormal", text = "",
      color = {r = 1, g = 1, b = 1, a = 1 }, border = true,
    }
    ret.str2 = KUI:CreateStringLabel(arg, ret)

    ret.str2:ClearAllPoints()
    ret.str2:SetPoint("TOPLEFT", ret.str1, "TOPRIGHT", 8, 0)

    arg = {
      x = 0, y = -30, width = 150, height = 24, autosize = false,
      justifyh = "RIGHT", font = "GameFontNormal", text = "",
    }
    ret.str3 = KUI:CreateStringLabel(arg, ret)

    arg = {
      x = 0, y = -30, width = 200, height = 20,
    }
    ret.input = KUI:CreateEditBox(arg, ret)
    ret.input:SetFocus()

    ret.input:ClearAllPoints()
    ret.input:SetPoint("TOPLEFT", ret.str3, "TOPRIGHT", 12, 0)

    ret.OnCancel = function(this)
      local trd = this.kmod.renamedialog
      trd:Hide()
      if (trd.isshown) then
        trd.kmod.mainwin:Show()
      end
      trd.isshown = nil
    end

    ret.OnAccept = function(this)
      local trd = this.kmod.renamedialog
      local rv = trd.runfunction(trd.input:GetText(), trd.arg, true)
      if (rv) then
        trd:Show()
        trd.input:SetFocus()
      else
        trd:Hide()
        if (trd.isshown) then
          trd.kmod.mainwin:Show()
        end
        trd.isshown = nil
      end
    end
    ret.input.OnEnterPressed = function(this)
      local tp = this:GetParent():GetParent()
      tp.OnAccept(tp)
    end

    ret.kmod = kmod
    kmod.renamedialog = ret
    renamedlg = kmod.renamedialog
  end

  renamedlg:SetTitleText(ttxt)
  renamedlg.str1:SetText(oldlbl)
  renamedlg.str2:SetText(oldval)
  renamedlg.str3:SetText(newlbl)
  renamedlg.input:SetMaxLetters(len)
  renamedlg.runfunction = func
  renamedlg.arg = farg
  renamedlg.isshown = shown

  renamedlg.kmod.mainwin:Hide()
  renamedlg:Show()
  renamedlg.input:SetText("")
  renamedlg.input:SetFocus()
end

function K.PopupSelectionList(kmod, name, list, title, width, height, parent, itemheight, func, topspace, botspace, xtras)
  if (kmod.popupwindow) then
    kmod.popupwindow:Hide()
    kmod.popupwindow = nil
  end

  assert(name)

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
    func = function(lst, idx, arg)
      func(lst[idx].value)
    end,
    timeout = 3,
  }
  if (xtras and type(xtras) == "table") then
    for k,v in pairs(xtras) do
      arg[k] = v
    end
  end

  local rv = KUI:CreatePopupList(arg, parent)
  assert(rv)
  rv.kmod = kmod

  rv:UpdateList(list)
  rv:Show()

  return rv
end

function K.SingleStringInputDialog(kmod, name, title, text, width, height, xtras)
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
  if (xtras and type(xtras) == "table") then
    for k,v in pairs(xtras) do
      arg[k] = v
    end
  end

  local ret = KUI:CreateDialogFrame(arg)
  assert(ret)
  ret.kmod = kmod

  arg = {
    x = 8, y = 0, width = width - 40, height = height - 90, autosize = false,
    font = "GameFontNormal", text = text, }
  ret.str1 = KUI:CreateStringLabel(arg, ret)

  arg = { x = "CENTER", y = -(height - 85), len = 32 }
  ret.ebox = KUI:CreateEditBox(arg, ret)

  ret.ebox:SetFocus()

  return ret, ret.ebox
end
