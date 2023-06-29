--[[
   KahLua Kore - loot distribution handling.
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

local KKOREKONFER_MAJOR = "KKoreKonfer"
local KKOREKONFER_MINOR = 4
local KK, oldminor = LibStub:NewLibrary(KKOREKONFER_MAJOR, KKOREKONFER_MINOR)

if (not KK) then
  return
end

KK.debug_id = KKOREKONFER_MAJOR

local K, KM = LibStub:GetLibrary("KKore")
assert(K, "KKoreKonfer requires KKore")
assert(tonumber(KM) >= 4, "KKoreKonfer requires KKore r4 or later")
K:RegisterExtension(KK, KKOREKONFER_MAJOR, KKOREKONFER_MINOR)

local KUI, KM = LibStub:GetLibrary("KKoreUI")
assert(KUI, "KKoreKonfer requires KKoreUI")
assert(tonumber(KM) >= 4, "KKoreKonfer requires KKoreUI r4 or later")

local H, KM = LibStub:GetLibrary("KKoreHash")
assert(H, "KKoreKonfer requires KKoreHash")
assert(tonumber(KM) >= 4, "KKoreKonfer requires KKoreHash r4 or later")

local KRP, KM = LibStub:GetLibrary("KKoreParty")
assert(KRP, "KKoreKonfer requires KKoreParty")
assert(tonumber(KM) >= 4, "KKoreKonfer requires KKoreParty r4 or later")

local ZL = LibStub:GetLibrary("LibDeflate")
assert(ZL, "KKoreKonfer requires LibDeflate")

local LS = LibStub:GetLibrary("LibSerialize")
assert(LS, "KKoreKonfer requires LibSerialize")

local L = LibStub("AceLocale-3.0"):GetLocale("KKore")

KK.addons = {}
KK.valid_callbacks = {
}

local printf = K.printf
local tsort = table.sort
local tinsert = table.insert
local strfmt = string.format
local strlen = string.len
local strsub = string.sub
local bor = bit.bor
local band = bit.band
local bxor = bit.bxor
local lshift = bit.lshift
local rshift = bit.rshift
local MakeFrame= KUI.MakeFrame

-- A static table with the list of possible player roles (from a konfer point
-- of view - not to be confused with the in-game raid or player roles). This
-- is used to restrict certain items to a particular type of raider. We also
-- define constants for each role name.
KK.ROLE_UNSET  = 0
KK.ROLE_HEALER = 1
KK.ROLE_MELEE  = 2
KK.ROLE_RANGED = 3
KK.ROLE_CASTER = 4
KK.ROLE_TANK   = 5
KK.rolenames = {
 [KK.ROLE_UNSET]  = L["Not Set"],
 [KK.ROLE_HEALER] = L["Healer"],
 [KK.ROLE_MELEE]  = L["Melee DPS"],
 [KK.ROLE_RANGED] = L["Ranged DPS"],
 [KK.ROLE_CASTER] = L["Spellcaster"],
 [KK.ROLE_TANK]   = L["Tank"],
}

-- The different configuration types supported, mainly for intra-mod comms.
-- Currently there is only need for two types: guild and PUG.
KK.CFGTYPE_GUILD = 1
KK.CFGTYPE_PUG   = 2

--
-- Global list of all Konfer modules.
--
_G["KKonfer"] = _G["KKonfer"] or {}
local KKonfer = _G["KKonfer"]
KKonfer["..."] = KKonfer["..."] or {}

local function opens_on_loot(handle)
  if (not handle or handle == "") then
    return false
  end

  local me = KKonfer[handle]
  if (not me) then
    return false
  end

  return me.open_on_loot(handle) or false
end

local function check_duplicate_modules(me, insusp)
  local kchoice = KKonfer["..."]
  local tstr = strfmt("%s (v%s) - %s", me.title, me.version, me.desc)

  if (not insusp and kchoice.selected and kchoice.selected ~= me.handle) then
    KK.SetSuspended(me.handle, true)
    return
  end

  local nactive = 0
  for k,v in pairs(KKonfer) do
    if (k ~= "...") then
      if (not KK.IsSuspended(k)) then
        if (opens_on_loot(k)) then
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
  if (insusp) then
    kchoice.actdialog.which:SetText(tstr)
    kchoice.actdialog.mod = me.handle
    kchoice.seldialog:Hide()
    kchoice.actdialog:Show()
  else
    kchoice.seldialog.RefreshList(me.party, me.raid)
    kchoice.actdialog:Hide()
    kchoice.seldialog:Show()
  end
end

function KK.IsSuspended(handle)
  if (not handle or handle == "") then
    return true
  end

  local me = KKonfer[handle]
  if (not me) then
    return true
  end

  return me.is_suspended(handle) or false
end

function KK.SetSuspended(handle, onoff)
  if (not handle or handle == "") then
    return
  end

  local me = KKonfer[handle]
  if (not me) then
    return
  end

  local cs = me.is_suspended(handle) or false
  local ts = onoff or false

  if (cs == ts) then
    return
  end

  me.set_suspended(handle, ts)

  local ds = L["KONFER_SUSPENDED"]
  if (not ts) then
    ds = L["KONFER_ACTIVE"]
    check_duplicate_modules(me, true)
  end
  K.printf(K.icolor, "%s: |cffffffff%s|r.", me.title, ds)
end

local function create_konfer_dialogs()
  local kchoice = KKonfer["..."]
  assert(kchoice)
  local ks = "|cffff2222<" .. K.KAHLUA ..">|r"

  local arg = {
    x = "CENTER", y = "MIDDLE", name = "KKonferModuleSelector",
    title = strfmt(L["KONFER_SEL_TITLE"], ks),
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
  kchoice.seldialog = KUI:CreateDialogFrame(arg)

  local ksd = kchoice.seldialog

  arg = {
    x = "CENTER", y = 0, width = 400, height = 96, autosize = false,
    font = "GameFontNormal",
    text = strfmt(L["KONFER_SEL_HEADER"], ks),
  }
  ksd.header = KUI:CreateStringLabel(arg, ksd)

  arg = {
    name = "KKonferModSelDD",
    x = 35, y = -105, dwidth = 350, justifyh = "CENTER", border = "THIN",
    mode = "SINGLE", itemheight = 16, items = KUI.emptydropdown,
  }
  ksd.seldd = KUI:CreateDropDown(arg, ksd)
  ksd.seldd:Catch("OnValueChanged", function(this, evt, val, usr)
    if (not usr) then
      return
    end
    local kkonfer = _G["KKonfer"]
    assert(kkonfer)
    for k,v in pairs(kkonfer) do
      if (k ~= "..." and k ~= val) then
        KK.SetSuspended(k, true)
      end
    end
    KK.SetSuspended(val, false)
    kkonfer["..."].seldialog:Hide()
    ksd.selected = val
  end)

  ksd.RefreshList = function(party, raid)
    local kkonfer = _G["KKonfer"] or {}
    local items = {}
    local kd = kkonfer["..."].seldialog.seldd

    tinsert(items, {
      text = L["KONFER_SEL_DDTITLE"], value = "", title = true,
    })
    for k,v in pairs(kkonfer) do
      if (k ~= "...") then
        if ((party and v.party) or (raid and v.raid)) then
          local item = {
            text = strfmt("%s (v%s) - %s", v.title, v.version, v.desc),
            value = k, checked = false,
          }
          tinsert(items, item)
        end
      end
    end
    kd:UpdateItems(items)
    kd:SetValue("", true)
  end

  arg = {
    x = "CENTER", y = "MIDDLE", name = "KKonferModuleDisable",
    title = strfmt(L["KONFER_SEL_TITLE"], ks),
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
  kchoice.actdialog = KUI:CreateDialogFrame(arg)
  kchoice.actdialog:Catch("OnAccept", function(this, evt)
    for k,v in pairs(KKonfer) do
      if (k ~= "..." and k ~= this.mod) then
        KK.SetSuspended(k, true)
      end
    end
  end)

  arg = {
    x = "CENTER", y = 0, autosize = false, border = true,
    width = 400, font = "GameFontHighlight", justifyh = "CENTER",
  }
  kchoice.actdialog.which = KUI:CreateStringLabel(arg, kchoice.actdialog)

  arg = {
    x = "CENTER", y = -24, width = 400, height = 128, autosize = false,
    font = "GameFontNormal",
    text = strfmt(L["KONFER_SUSPEND_OTHERS"], ks),
  }
  kchoice.actdialog.msg = KUI:CreateStringLabel(arg, kchoice.actdialog)
end

function KK:OnLateInit()
  if (self.initialised) then
    return
  end

  create_konfer_dialogs()
  self.initialised = true
end

function KK.TimeStamp()
  local tDate = date("*t")
  local mo = tDate["month"]
  local dy = tDate["day"]
  local yr = tDate["year"]
  local hh, mm = GetGameTime()
  return strfmt("%04d%02d%02d%02d%02d", yr, mo, dy, hh, mm), yr, mo, dy, hh, mm
end

function KK.CreateNewID(strtohash)
  local _, y, mo, d, h, m = KK.TimeStamp()
  local ts = strfmt("%02d%02d%02d", y-2000, mo, d)
  local crc = H:CRC32(ts, nil, false)
  crc = H:CRC32(tostring(h), crc, false)
  crc = H:CRC32(tostring(m), crc, false)
  crc = H:CRC32(strtohash, crc, true)
  ts = ts .. K.hexstr(crc)
  return ts
end

function KK.IsSenderMasterLooter(sender)
  if (KRP.in_party and KRP.master_looter and KRP.master_looter == sender) then
    return true
  end
  return false
end

function KK:OldProtoDialog()
  if (self.old_proto) then
    return
  end

  self.old_proto = true

  local arg = {
    name = self.konfer.handle .. "OldProtoDialog",
    x = "CENTER", y = "MIDDLE", border = true, blackbg = true,
    okbutton = { text = K.OK_STR }, canmove = false, canresize = false,
    escclose = false, width = 450, height = 100, title = self.title,
  }
  local dlg = KUI:CreateDialogFrame(arg)
  dlg.OnAccept = function(this)
    this:Hide()
  end
  dlg.OnCancel = function(this)
    this:Hide()
  end

  arg = {
    x = 8, y = -10, width = 410, height = 64, autosize = false,
    color = { r = 1, g = 0, b = 0, a = 1},
    text = self.konfer.title .. ": " .. strfmt(L["your version of %s is out of date. Please update it."], self.konfer.title),
    font = "GameFontNormal", justifyv = "TOP",
  }
  dlg.str1 = KUI:CreateStringLabel(arg, dlg)

  if (self.mainwin and self.mainwin:IsShown()) then
    self.mainwin:Hide()
  end
  dlg:Show()
end

--
-- This is the function that is responsible for creating all internal addon
-- messages we send. It implements all and any "protocol" we want to use to
-- communicate between different instances of the addon. It has a reciprocal
-- function comm_received below that should be used to decode all messages
-- received by the addon. Thus, as long as these two functions can deal with
-- changes between each other, pretty much any protocol can be used. For right
-- now the basic protocol is that each message is always a string that begins
-- with two lower case hexadecimal numbers, followed by a colon, followed
-- immediately by the payload, which extends from this point to the end of the
-- message.
--
-- The payload protocol is always a colon separated list in the form:
--   command:cfgid:crc32:data
--
-- Each handler is called with the command, config ID, protocol version and
-- then any other data.
--
local function send_addon_msg(self, cfg, cmd, prio, dist, target, ...)
  local proto = self.protocol
  local rcmd

  if (type(cmd) == "table") then
    proto = cmd.proto
    rcmd = cmd.cmd
  else
    rcmd = cmd
  end

  local serialised = LS:Serialize(...)
  if (not serialised) then
    self.debug(4, "failed to serialise data for %q", rcmd)
    return
  end

  local compressed = ZL:CompressDeflate(serialised, { level = 5 })
  if (not compressed) then
    self.debug(4, "failed to compress data for %q", rcmd)
    return
  end

  local encoded = ZL:EncodeForWoWAddonChannel(compressed)
  if (not encoded) then
    self.debug(4, "encode failed for %q", rcmd)
    return nil
  end

  local cfg = cfg or self.currentid or "0"
  local prio = prio or "ALERT"
  local fs = strfmt("%02x:%s:%s:", proto, rcmd, cfg)
  local crc = H:CRC32(fs, nil, false)
  crc = H:CRC32(encoded, crc, true)
  fs = fs .. K.hexstr(crc) .. ":" .. encoded

  self.debug(9, "send: dist=%s msg=%q", dist, strsub(fs, 1, 48))

  K:SendCommMessage(self.CHAT_MSG_PREFIX, fs, dist, target, prio)
end

-- Designed to process host addon's OnCommReceived with a dispatcher.
local function comm_received(self, prefix, msg, dist, snd, dispatcher)
  local sender = K.CanonicalName(snd)
  if (sender == K.player.name) then
    return -- Ignore our own messages
  end

  self.debug(9, "recv: dist=%s snd=%s msg=%q", tostring(dist), tostring(snd), strsub(tostring(msg), 1, 48))

  if (dist == "UNKNOWN" and (sender ~= nil and sender ~= "")) then
    return
  end

  -- Create the itterator for splitting on a :
  local iter = gmatch(msg, "([^:]+)()")

  -- Get the protocol (should be 2 hex digits)
  local ps = iter()
  if (not ps) then
    self.debug(4, "bad msg received from %q", sender)
    return
  end

  local proto = tonumber(ps, 16)

  if (proto > self.protocol) then
    KK.OldProtoDialog(keg)
    return
  end

  -- Now get the command
  local cmd = iter()
  if (not cmd) then
    self.debug(4, "malformed cmd msg received from %q", sender)
    return
  end

  -- And the config this message is for
  local cfg = iter()
  if (not cfg) then
    self.debug(4, "malformed cfg msg received from %q", sender)
    return
  end

  -- Get the message checksum
  local msum, pos = iter()
  if (not msum) then
    self.debug(4, "malformed msum msg received from %q", sender)
    return
  end

  -- The rest of the message is the payload
  local data = strsub(msg, pos+1)
  if (not data) then
    self.debug(4, "malformed data msg received from %q", sender)
    return
  end

  local fs = strfmt("%02x:%s:%s:", proto, cmd, cfg)
  local crc = H:CRC32(fs, nil, false)
  crc = H:CRC32(data, crc, true)

  local mf = K.hexstr(crc)

  if (mf ~= msum) then
    local t = K.time()
    local n = userwarn[sender]
    if (n and ((n - t) >= 600)) then
      userwarn[sender] = nil
    end

    self.debug(1, "mismatch: cmd=%q mysum=%q theirsum=%q", tostring(cmd), tostring(mf), tostring(msum))

    if (not userwarn[sender]) then
      printf(K.ecolor, "WARNING: addon message from %q was truncated!", sender)
      userwarn[sender] = t
    end
    return
  end

  local decoded = ZL:DecodeForWoWAddonChannel(data)
  if (not decoded) then
    self.debug(4, "recv: decode failed for %q from %q", cmd, sender)
    return
  end

  local inflated = ZL:DecompressDeflate(decoded)
  if (not inflated) then
    self.debug(4, "recv: deflate failed for %q from %q", cmd, sender)
    return
  end

  dispatcher(self, sender, proto, cmd, cfg, LS:Deserialize(inflated))
end

local function send_to_raid_or_party_am_c(self, cfg, cmd, prio, ...)
  local cfgt = KK.CFGTYPE_PUG
  local cfg = cfg or self.currentid

  if (cfg and self.configs and self.configs[cfg]) then
    cfgt = self.configs[cfg].cfgtype or KK.CFGTYPE_PUG
  end

  local dist = nil

  if (cfgt == KK.CFGTYPE_GUILD and K.player.is_guilded) then
    dist = "GUILD"
  else
    if (KRP.in_party and self.konfer.party) then
      dist = "PARTY"
    end

    if (KRP.in_raid and self.konfer.raid) then
      dist = "RAID"
    end
  end

  if (not dist) then
    return
  end

  send_addon_msg(self, cfg, cmd, prio, dist, nil, ...)
end

local function send_to_raid_or_party_am(self, cmd, prio, ...)
  send_to_raid_or_party_am_c(self, nil, cmd, prio, ...)
end

local function send_to_guild_am_c(self, cfg, cmd, prio, ...)
  if (K.player.is_guilded) then
    send_addon_msg(self, cfg, cmd, prio, "GUILD", nil, ...)
  end
end

local function send_to_guild_am(self, cmd, prio, ...)
  if (K.player.is_guilded) then
    send_addon_msg(self, nil, cmd, prio, "GUILD", nil, ...)
  end
end

local function send_whisper_am_c(self, cfg, target, cmd, prio, ...)
  send_addon_msg(self, cfg, cmd, prio, "WHISPER", target, ...)
end

local function send_whisper_am(self, target, cmd, prio, ...)
  send_addon_msg(self, nil, cmd, prio, "WHISPER", target, ...)
end

local function send_plain_message(self, text)
  if (not KRP.in_party) then
    return
  end

  local dist = "PARTY"
  if (KRP.in_raid) then
    dist = "RAID"
  end

  SendChatMessage(text, dist)
end

local function send_guild_message(self, text)
  if (not K.player.is_guilded) then
    return
  end
  SendChatMessage(text, "GUILD")
end

local function send_whisper_message(self, text, target)
  SendChatMessage(text, "WHISPER", nil, target)
end

local function send_raid_warning(self, text)
  if (KRP.in_raid) then
    if (KRP.is_aorl) then
      SendChatMessage(text, "RAID_WARNING")
    else
      SendChatMessage("{skull}{skull} " .. text .. " {skull}{skull}", "RAID")
    end
  else
    SendChatMessage("{skull}{skull} " .. text .. " {skull}{skull}", "PARTY")
  end
end

local userwarn = userwarn or {}

--
-- Shared dialog for version checks.
--
local function vlist_newitem(objp, num)
  local kk = objp:GetParent():GetParent():GetParent().kkmod
  local bname = kk.konfer.handle .. "KKVCheckListButton" .. tostring(num)
  local rf = MakeFrame("Button", bname, objp.content)
  local nfn = "GameFontNormalSmallLeft"
  local hfn = "GameFontHighlightSmallLeft"
  local htn = "Interface/QuestFrame/UI-QuestTitleHighlight"

  rf:SetWidth(325)
  rf:SetHeight(16)
  rf:SetHighlightTexture(htn, "ADD")

  local who = rf:CreateFontString(nil, "BORDER", nfn)
  who:ClearAllPoints()
  who:SetPoint("TOPLEFT", rf, "TOPLEFT", 0, -2)
  who:SetPoint("BOTTOMLEFT", rf, "BOTTOMLEFT", 0, -2)
  who:SetWidth(168)
  who:SetJustifyH("LEFT")
  who:SetJustifyV("TOP")
  rf.who = who

  local version = rf:CreateFontString(nil, "BORDER", nfn)
  version:ClearAllPoints()
  version:SetPoint("TOPLEFT", who, "TOPRIGHT", 4, 0)
  version:SetPoint("BOTTOMLEFT", who, "BOTTOMRIGHT", 4, 0)
  version:SetWidth(95)
  version:SetJustifyH("LEFT")
  version:SetJustifyV("TOP")
  rf.version = version

  local raid = rf:CreateFontString(nil, "BORDER", nfn)
  raid:ClearAllPoints()
  raid:SetPoint("TOPLEFT", version, "TOPRIGHT", 4, 0)
  raid:SetPoint("BOTTOMLEFT", version, "BOTTOMRIGHT", 4, 0)
  raid:SetWidth(50)
  raid:SetJustifyH("LEFT")
  raid:SetJustifyV("TOP")
  rf.raid = raid

  rf.SetText = function(self, who, vers, raid)
    self.who:SetText(who)
    self.version:SetText(vers)
    if (raid) then
      self.raid:SetText(K.YES_STR)
    else
      self.raid:SetText(K.NO_STR)
    end
  end

  return rf
end

local function vlist_setitem(objp, idx, slot, btn)
  local kk = objp:GetParent():GetParent():GetParent().kkmod
  if (not kk or not kk.vcdlg or not kk.vcdlg.vcreplies) then
    return
  end

  local vcent = kk.vcdlg.vcreplies[idx]
  if (not vcent) then
    return
  end
  local name = kk.shortaclass(vcent)
  local vers = tonumber(vcent.version)
  local fn = kk.green
  if (vers < kk.version) then
    fn = kk.red
  end

  btn:SetText(name, fn(tostring(vers)), vcent.raid)
  btn:SetID(idx)
  btn:Show()
end

local function sort_vcreplies(self)
  tsort(self.vcdlg.vcreplies, function(a, b)
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
    return strlower(a.name) < strlower(b.name)
  end)
  self.vcdlg.slist.itemcount = #self.vcdlg.vcreplies
  self.vcdlg.slist:UpdateList()
end

local function kk_version_check(self)
  local vcdlg = self.vcdlg
  if (not vcdlg) then
    local ks = "|cffff2222<" .. K.KAHLUA ..">|r"
    local arg = {
      x = "CENTER", y = "MIDDLE",
      name = self.konfer.handle .. "KKVersionCheck",
      title = strfmt(L["VCTITLE"], ks, self.konfer.title),
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
    vcdlg = KUI:CreateDialogFrame(arg)
    vcdlg.kkmod = self

    vcdlg.OnAccept = function(this)
      this:Hide()
      if (this.mainshown) then
        this.kkmod.mainwin:Show()
      end
      this.mainshown = nil
      this.vcreplies = nil
    end
    vcdlg.OnCancel = vcdlg.OnAccept

    arg = {
      x = 5, y = 0, text = L["Who"], font = "GameFontNormal",
    }
    vcdlg.str1 = KUI:CreateStringLabel(arg, vcdlg)

    arg.x = 175
    arg.text = L["Version"]
    vcdlg.str2 = KUI:CreateStringLabel(arg, vcdlg)

    arg.x = 275
    arg.text = L["In Raid"]
    vcdlg.str3 = KUI:CreateStringLabel(arg, vcdlg)

    vcdlg.sframe = MakeFrame("Frame", nil, vcdlg.content)
    vcdlg.sframe:ClearAllPoints()
    vcdlg.sframe:SetPoint("TOPLEFT", vcdlg.content, "TOPLEFT", 5, -18)
    vcdlg.sframe:SetPoint("BOTTOMRIGHT", vcdlg.content, "BOTTOMRIGHT", 0, 0)


    arg = {
      name = self.konfer.handle .. "KKVersionScrollList",
      itemheight = 16, newitem = vlist_newitem, setitem = vlist_setitem,
      selectitem = function(objp, idx, slot, btn, onoff) return end,
      highlightitem = function(objp, idx, slot, btn, onoff)
        return KUI.HighlightItemHelper(objp, idx, slot, btn, onoff)
      end,
    }
    vcdlg.slist = KUI:CreateScrollList(arg, vcdlg.sframe)

    self.vcdlg = vcdlg
  end

  --
  -- Populate the expected replies with all current raid members and if we
  -- are in a guild, with all currently online guild members. We set the
  -- version to 0 to indicate no reply yet. As replies come in we change the
  -- version number and re-sort and refresh the list.
  --

  vcdlg.vcreplies = {}

  if (KRP.players) then
    for k, v in pairs(KRP.players) do
      local vce = { name = k, class = v.class, version = 0, raid = true }
      if (k == K.player.name) then
        vce.version = self.version
      end
      tinsert(vcdlg.vcreplies, vce)
    end
  end

  if (K.player.is_guilded) then
    for k, v in pairs(K.guild.roster.id) do
      if ((not KRP.players or not KRP.players[v.name]) and v.online) then
        local vce = { name = v.name, class = v.class, version = 0, raid = false }
        if (v.name == K.player.name) then
          vce.version = self.version
        end
        tinsert(vcdlg.vcreplies, vce)
      end
    end
  end

  sort_vcreplies(self)

  vcdlg.mainshown = self.mainwin:IsShown()
  self.mainwin:Hide()
  vcdlg:Show()

  self:SendAM({proto = 2, cmd = "VCHEK"}, nil)
  if (K.player.is_guilded) then
    self:SendGuildAM({proto = 2, cmd = "VCHEK"}, nil)
  end
end

local function kk_version_check_reply(self, sender, version)
  if (not self.vcdlg or not self.vcdlg.vcreplies) then
    return
  end

  for k, v in pairs(self.vcdlg.vcreplies) do
    if (v.name == sender) then
      v.version = version
      sort_vcreplies(self)
      return
    end
  end
end

--
-- Register a new addon (like KSK) with the base Konfer system. The single
-- argument to this function is a table with various parameters, as described
-- below. Returns a handle to the mod, which is a table.
--
function KK.RegisterKonfer(kmod)
  local targ = kmod.konfer
  if (not targ or type(targ) ~= "table") then
    error("Invalid call to RegisterKonfer.", 2)
  end

  local me = KKonfer[targ.handle]
  if (me ~= nil) then
    return me
  end

  assert(kmod.protocol)

  kmod.konfer = targ
  kmod.CSendAM = send_to_raid_or_party_am_c
  kmod.SendAM = send_to_raid_or_party_am
  kmod.CSendGuildAM = send_to_guild_am_c
  kmod.SendGuildAM = send_to_guild_am
  kmod.CSendWhisperAM = send_whisper_am_c
  kmod.SendWhisperAM = send_whisper_am
  kmod.SendText = send_plain_message
  kmod.SendGuildText = send_guild_message
  kmod.SendWhisper = send_whisper_message
  kmod.SendWarning = send_raid_warning
  kmod.VersionCheck = kk_version_check
  kmod.VersionCheckReply = kk_version_check_reply
  kmod.KonferCommReceived = comm_received

  KKonfer[targ.handle] = targ

  check_duplicate_modules(targ, false)
end
