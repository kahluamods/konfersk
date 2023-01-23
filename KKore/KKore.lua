--[[
   KahLua Kore - core library functions for KahLua addons.
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

local CallbackHandler = LibStub("CallbackHandler-1.0")

local KKORE_MAJOR = "KKore"
local KKORE_MINOR = 5

local K = LibStub:NewLibrary(KKORE_MAJOR, KKORE_MINOR)

if (not K) then
  return
end

local kaoname = ...
if (string.lower(kaoname) == "kkore") then
  K.KORE_PATH = "Interface\\Addons\\KKore\\"
else
  K.KORE_PATH = "Interface\\Addons\\" .. kaoname .. "\\KKore\\"
end

_G["KKore"] = K

--
-- KKore is a superset of a bunch of Ace3 plugins. In the past we used to
-- embed slightly tweaked versions of those plugins directly in KKore.
-- That turned out to be a maintenance mightmare. So now we use them the
-- way they were intended, as replaceable libraries. However, we still want
-- KKore to provide the actual "API" that Kahlua mods can use, which means
-- that these select few basic Ace3 mods must be present in every Kahlua
-- addon. This function centralises the location of that list of Ace3 libraries
-- and embeds them into the object passed as a parameter. This is called for
-- KKore itself (so it too has access to the same APIs) as well as each
-- Kahlua mod when it registers with KKore.
--

function K:AceKore(obj)
  LibStub("AceEvent-3.0"):Embed(obj)
  LibStub("AceComm-3.0"):Embed(obj)
  LibStub("AceTimer-3.0"):Embed(obj)
end

K:AceKore(K)

K.extensions = K.extensions or {}

-- Local aliases for global or Lua library functions
local tinsert = table.insert
local tremove = table.remove
local setmetatable = setmetatable
local tconcat = table.concat
local tostring, tonumber = tostring, tonumber
local max = math.max
local strfmt = string.format
local strsub = string.sub
local strfind = string.find
local strlower = string.lower
local strupper = string.upper
local strbyte = string.byte
local strchar = string.char
local gmatch = string.gmatch
local match = string.match
local gsub = string.gsub
local xpcall, pcall = xpcall, pcall
local pairs, type = pairs, type
local select, assert = select, assert
local band, rshift = bit.band, bit.rshift
local unpack, error = unpack, error

local k,v,i
local kore_ready = 0

--
-- The difference between the local time zone and UTC. If you add this
-- number to the return value of K.time() it will equal K.localtime().
-- This is useful for recording times in UTC but displaying them in the
-- local timezone. This is *NOT* robust and will probably give weird
-- result on the day that daylight saving starts / stops, if it does for
-- the user's timezone.
K.utcdiff = time(date("*t")) - time(date("!*t"))

--
-- Returns the number of seconds since the UTC epoch.
--
function K.time()
  return time(date("!*t"))
end

--
-- Returns the number of seconds since the local epoch.
--
function K.localtime()
  return time(date("*t"))
end

--
-- Returns the decomposed date as a table given a time, or the UTC epoch if
-- no time is provided.
--
function K.date(when)
  local when = when or time(date("!*t"))
  return date("*t", when)
end

--
-- Returns a YYYY-MM-DD HH:MM:SS timestamp for a specified time, or the UTC
-- epoch if no time is specified.
--
function K.TimeStamp(when)
  local when = when or time(date("!*t"))
  return date("%Y-%m-%d %H:%M:%S", when)
end

function K.LocalStamp(when)
  local when = when or time(date("!*t"))
  return date("%Y-%m-%d %H:%M:%S", when + K.utcdiff)
end

--
-- Returns a YYYY-MM-DD HH:MM timestamp for a specified time, or the UTC
-- epoch if no time is specified.
--
function K.TimeStampNS(when)
  local when = when or time(date("!*t"))
  return date("%Y-%m-%d %H:%M", when)
end

function K.LocalStampNS(when)
  local when = when or time(date("!*t"))
  return date("%Y-%m-%d %H:%M", when + K.utcdiff)
end

--
-- Returns a YYYY-MM-DD timestamp for a specified time, or the UTC epoch
-- if no time is specified.
--
function K.YMDStamp(when)
  local when = when or time(date("!*t"))
  return date("%Y-%m-%d", when)
end

function K.LocalYMD(when)
  local when = when or time(date("!*t"))
  return date("%Y-%m-%d", when + K.utcdiff)
end

--
-- Returns a HH:MM timestamp for a specified time, or the UTC epoch
-- if no time is specified.
--
function K.HMStamp(when)
  local when = when or time(date("!*t"))
  return date("%H:%M", when)
end

function K.LocalHM(when)
  local when = when or time(date("!*t"))
  return date("%H:%M", when + K.utcdiff)
end

--
-- Returns a HH:MM:SS timestamp for a specified time, or the UTC epoch
-- if no time is specified.
--
function K.HMSStamp(when)
  local when = when or time(date("!*t"))
  return date("%H:%M:%S", when)
end

function K.LocalHMS(when)
  local when = when or time(date("!*t"))
  return date("%H:%M:%S", when + K.utcdiff)
end

K.local_realm = K.local_realm or select(2, UnitFullName("player"))

--
-- Capitalise the first character in a users name. Many thanks to Arrowmaster
-- in #wowuidev on irc.freenode.net for the pattern below.
--
function K.CapitaliseName(name)
  assert(name)
  return gsub(strlower(name), "^([\192-\255]?%a?[\128-\191]*)", strupper, 1)
end
K.CapitalizeName = K.CapitaliseName

--
-- Return a full Name-Realm string. Even for users on the local realm it will
-- add it so that names are universally in the format Name-Realm. This will
-- always be a valid tell target as the realm name has had all spaces and
-- special characters removed (it is the realm name as returned by UnitName()
-- or equivalent functions). This is so much more complicated than it needs to
-- be. Some Blizzard functions return a full Name-Realm string in which case
-- we have nothing to do except capitalise it according to our own rules.
-- Other functions return Name-realm if the player is on a different realm.
-- Still others return only the name even if they player is on a different
-- realm but they are in the guild. This has been carefully adjusted over
-- time to always do The Right Thing(TM).
--
--[[
function K.CanonicalName(name, realm)
  if (not name) then
    return nil
  end

  --
  -- If the name is already in Name-Realm format, simply remove any spaces
  -- and capitalise it according to our function above.
  --
  if (strfind(name, "-", 1, true)) then
    local nm = gsub(name, " ", "")
    return K.CapitaliseName(nm)
  end

  --
  -- If this wasn't set correctly during addon initialisation do it now.
  --
  K.local_realm = K.local_realm or select(2, UnitFullName("player"))

  --
  -- Try UnitFullName(). This returns the player name as the first argument
  -- and the realm as the second. The realm name already has the spaces
  -- removed from it. However, this doesn't return anything if the user
  -- isn't online and it is ambiguous if the name given is a duplicate in the
  -- raid or the guild. But if this returns anything we go with it as there
  -- is only so much we can do.
  --
  local nm, rn = UnitFullName(name)

  if (nm and rn and nm ~= "" and rn ~= "") then
    return K.CapitaliseName(nm .. "-" .. rn)
  end

  if (not nm or nm == "") then
    nm = name
    rn = realm
  end

  if (not rn or rn == "") then
    rn = K.local_realm
  end

  if (not rn or rn == "") then
    return nil
  end

  nm = Ambiguate(nm, "mail")
  if (strfind(nm, "-", 1, true)) then
    return K.CapitaliseName(nm)
  else
    return K.CapitaliseName(nm .. '-' .. rn)
  end
end

function K.FullUnitName(unit)
  if (not unit or type(unit) ~= "string" or unit == "") then
    return nil
  end

  local unit_name, unit_realm = UnitFullName(unit)

  if (not unit_realm or unit_realm == "") then
    K.local_realm = K.local_realm or select(2, UnitFullName("player"))
    unit_realm = K.local_realm
  end

  if (not unit_name or unit_name == "Unknown" or not unit_realm or unit_realm == "") then
    return nil
  end

  return K.CapitaliseName(unit_name .. "-" .. unit_realm)
end
]]

function K.CanonicalName(name, realm)
  if (not name) then
    return nil
  end

  return K.CapitaliseName(Ambiguate(name, "short"))
end

function K.FullUnitName(unit)
  if (not unit or type(unit) ~= "string" or unit == "") then
    return nil
  end

  local unit_name, unit_realm = UnitFullName(unit)

  if (not unit_name or unit_name == "Unknown") then
    return nil
  end

  return K.CapitaliseName(Ambiguate(unit_name, "short"))
end

function K.ShortName(name)
  return Ambiguate(name, "short")
end

---
--- Some versions of the WoW client have problems with strfmt("%08x", val)
--- for any val > 2^31. This simple functions avoids that.
---
function K.hexstr(val)
  local lowerbits = band(val, 0xffff)
  local higherbits = band(rshift(val, 16), 0xffff)
  return strfmt("%04x%04x", higherbits, lowerbits)
end

K.GC_GCHAT_LISTEN       = 1
K.GC_GCHAT_SPEAK        = 2
K.GC_OCHAT_LISTEN       = 3
K.GC_OCHAT_SPEAK        = 4
K.GC_PROMOTE            = 5
K.GC_DEMOTE             = 6
K.GC_INVITE             = 7
K.GC_REMOVE             = 8
K.GC_SET_MODT           = 9
K.GC_EDIT_PUBLIC_NOTE   = 10
K.GC_VIEW_OFFICER_NOTE  = 11
K.GC_EDIT_OFFICER_NOTE  = 12
K.GC_MODIFY_GUILD_INFO  = 13

K.player = K.player or {}
K.guild = K.guild or {}
K.guild.ranks = K.guild.ranks or {}
K.guild.flags = K.guild.flags or {}
K.guild.roster = K.guild.roster or {}
K.guild.roster.id = K.guild.roster.id or {}
K.guild.roster.name = K.guild.roster.name or {}
K.guild.gmname = nil
K.raids = K.raids or { numraids = 0, info = {} }

local done_pi_once = false
local function get_static_player_info()
  if (done_pi_once) then
    return true
  end

  K.local_realm = select(2, UnitFullName("player"))
  if (not K.local_realm or K.local_realm == "") then
    K.local_realm = nil
    return false
  end

  K.player.name = K.FullUnitName("player")
  if (not K.player.name) then
    return false
  end

  K.player.faction = UnitFactionGroup("player")
  K.player.class = K.ClassIndex[select(2, UnitClass("player"))]
  done_pi_once = true
  kore_ready = kore_ready + 1
  return true
end

local function update_player_and_guild(nofire)
  if (not get_static_player_info()) then
    return
  end

  local fireevt = false

  K.player.level = UnitLevel("player")
  if (IsInGuild()) then
    local gname, _, rankidx = GetGuildInfo("player")
    if (not gname or gname == "") then
      return
    end
    if (not K.player.is_guilded) then
      fireevt = true
    end
    K.player.is_guilded = true

    if (K.player.guild and K.player.guild ~= gname) then
      fireevt = true
    end
    K.player.guild = gname

    if (K.player.guildrankidx and K.player.guildrankidx ~= (rankidx + 1)) then
      fireevt = true
    end
    K.player.guildrankidx = rankidx + 1

    if (IsGuildLeader()) then
      if (not K.player.is_gm) then
        fireevt = true
      end
      K.player.is_gm = true
    else
      if (K.player.is_gm) then
        fireevt = true
      end
      K.player.is_gm = false
    end
  else
    if (K.player.is_guilded) then
      fireevt = true
    end
    K.player.is_guilded = false
    K.player.guild = nil
    K.player.guildrankidx = 0
    K.player.is_gm = false
  end

  if (K.player.is_guilded) then
    local i

    K.guild.numranks = GuildControlGetNumRanks()
    K.guild.ranks = {}
    K.guild.flags = {}
    K.guild.numroster = GetNumGuildMembers()
    K.guild.roster = {}
    K.guild.roster.id = {}
    K.guild.roster.name = {}

    for i = 1, K.guild.numranks do
      local rname = GuildControlGetRankName(i)
      local flags = C_GuildInfo.GuildControlGetRankFlags(i)
      tinsert(K.guild.ranks, rname)
      tinsert(K.guild.flags, flags)
    end

    for i = 1, K.guild.numroster do
      local nm, _, ri, lvl, _, _, _, _, ol, _, cl = GetGuildRosterInfo(i)
      nm = K.CanonicalName(nm)
      local iv = { name = nm, rank = ri + 1, level = lvl, class = K.ClassIndex[cl], online = ol and true or false }
      tinsert(K.guild.roster.id, iv)
      K.guild.roster.name[nm] = i
      if (ri == 0) then
        K.guild.gmname = nm
      end
    end
  else
    K.guild = {}
    K.guild.numranks = 0
    K.guild.ranks = {}
    K.guild.flags = {}
    K.guild.numroster = 0
    K.guild.roster = {}
    K.guild.roster.id = {}
    K.guild.roster.name = {}
    K.guild.gmname = nil
  end

  if (not nofire) then
    K:SendMessage("GUILD_INFO_UPDATED")
  end

  if (fireevt and not nofire) then
    K:SendMessage("PLAYER_INFO_UPDATED")
  end
end

function K.UpdatePlayerAndGuild(nofire)
  update_player_and_guild(nofire)
end

--
-- Returns true if the user is thought to be an officer or the GM, false
-- if we can't tell or can determine otherwise.
--
function K.UserIsRanked(name)
  if (not K.player.is_guilded or not K.guild) then
    return false
  end

  if (name == K.guild.gmname) then
    return true
  end

  local rosterid = K.guild.roster.name[name]
  if (not rosterid) then
    return false
  end

  -- If they can read officer chat we assume they are an officer of some sort.
  local flags = K.guild.flags[K.guild.roster.id[rosterid].rank]
  return flags[K.GC_OCHAT_LISTEN]
end

--
-- Simple debugging mechanism.
--
K.debugging = K.debugging or {}
K.debugframe = nil
K.maxlevel = MAX_PLAYER_LEVEL_TABLE[GetExpansionLevel()]


function K.debug(addon, lvl, ...)
  if (not K.debugging[addon]) then
    K.debugging[addon] = 0
  end

  if (K.debugging[addon] < lvl) then
    return
  end

  local text = ":[:" .. addon .. ":]: " .. strfmt(...)
  local frame = K.debugframe or DEFAULT_CHAT_FRAME
  frame:AddMessage(text, 0.6, 1.0, 1.0)
end

local function debug(lvl,...)
  K.debug("kore", lvl, ...)
end

--
-- Standard colors for usage messages, error messages and info messages
--
K.ucolor = { r = 1.0, g = 0.5, b = 0.0 }
K.ecolor = { r = 1.0, g = 0.0, b = 0.0 }
K.icolor = { r = 0.0, g = 1.0, b = 1.0 }

K.white = function (str)
  return "|cffffffff" .. str .. "|r"
end

K.red = function (str)
  return "|cffff0000" .. str .. "|r"
end

K.green = function (str)
  return "|cff00ff00" .. str .. "|r"
end

K.yellow = function (str)
  return "|cffffff00" .. str .. "|r"
end

K.cyan = function (str)
  return "|cff00ffff" .. str .. "|r"
end

function K.printf(...)
  local first = ...
  local frame = DEFAULT_CHAT_FRAME
  local i = 1
  local r,g,b,id

  if (type(first) == "table") then
    if (first.AddMessage) then
      frame = first
      i = i + 1
    end

    local c = select(i, ...)
    if (type(c) == "table" and (c.r or c.g or c.b or c.id)) then
      r,g,b,id = c.r or nil, c.g or nil, c.b or nil, c.id or nil
      i = i + 1
    end
  end

  frame:AddMessage(strfmt(select(i, ...)), r, g, b, id)
end

--
-- Here we set up a bunch of constants that are used frequently throughout
-- various modules. Some of them require actual computation, and its
-- pointless having multiple modules do the same computations, so we set up
-- the list of such constants here. Modules can then either reference these
-- directly (K.constant) or do a local constant = K.constant.
--
--K.NaNstring = tostring(0/0)
K.Infstring = tostring(math.huge)
K.NInfstring = tostring(-math.huge)

--
-- There are a number of places where we want to store classes, but storing
-- the class name is inefficient. So here we create a standard numbering
-- scheme for the classes. The numbers are always 2 digits, so that when they
-- are embedded in strings, we can always lift out exactly two digits to get
-- back to the class name.
--

K.CLASS_WARRIOR     = "01"
K.CLASS_PALADIN     = "02"
K.CLASS_HUNTER      = "03"
K.CLASS_ROGUE       = "04"
K.CLASS_PRIEST      = "05"
K.CLASS_DEATHKNIGHT = "06"
K.CLASS_SHAMAN      = "07"
K.CLASS_MAGE        = "08"
K.CLASS_WARLOCK     = "09"
K.CLASS_MONK        = "10"
K.CLASS_DRUID       = "11"
K.CLASS_DEMONHUNTER = "12"

K.UnsupClasses = {
  K.CLASS_MONK,
  K.CLASS_DEMONHUNTER,
}

K.EmptyClassFilter = "000000000000"

K.ClassIndex = {
  ["WARRIOR"]     = K.CLASS_WARRIOR,
  ["PALADIN"]     = K.CLASS_PALADIN,
  ["HUNTER"]      = K.CLASS_HUNTER,
  ["ROGUE"]       = K.CLASS_ROGUE,
  ["PRIEST"]      = K.CLASS_PRIEST,
  ["DEATHKNIGHT"] = K.CLASS_DEATHKNIGHT,
  ["SHAMAN"]      = K.CLASS_SHAMAN,
  ["MAGE"]        = K.CLASS_MAGE,
  ["WARLOCK"]     = K.CLASS_WARLOCK,
  ["DRUID"]       = K.CLASS_DRUID,
}

local kClassTable = {}
FillLocalizedClassList(kClassTable, false)
kClassTable["DEATHKNIGHT"] = "Death Knight"
--kClassTable["MONK"] = "Monk"
--kClassTable["DEMONHUNTER"] = "Demon Hunter"

local warrior = kClassTable["WARRIOR"]
local paladin = kClassTable["PALADIN"]
local hunter = kClassTable["HUNTER"]
local rogue = kClassTable["ROGUE"]
local priest = kClassTable["PRIEST"]
local shaman = kClassTable["SHAMAN"]
local mage = kClassTable["MAGE"]
local warlock = kClassTable["WARLOCK"]
local druid = kClassTable["DRUID"]
local deathknight = kClassTable["DEATHKNIGHT"]

-- Same table but using the localised names
K.LClassIndex = {
  [warrior]     = K.CLASS_WARRIOR,
  [paladin]     = K.CLASS_PALADIN,
  [hunter]      = K.CLASS_HUNTER,
  [rogue]       = K.CLASS_ROGUE,
  [priest]      = K.CLASS_PRIEST,
  [deathknight] = K.CLASS_DEATHKNIGHT,
  [shaman]      = K.CLASS_SHAMAN,
  [mage]        = K.CLASS_MAGE,
  [warlock]     = K.CLASS_WARLOCK,
  [druid]       = K.CLASS_DRUID,
}

K.LClassIndexNSP = {
  [gsub(warrior, " ", "")]     = K.CLASS_WARRIOR,
  [gsub(paladin, " ", "")]     = K.CLASS_PALADIN,
  [gsub(hunter, " ", "")]      = K.CLASS_HUNTER,
  [gsub(rogue, " ", "")]       = K.CLASS_ROGUE,
  [gsub(priest, " ", "")]      = K.CLASS_PRIEST,
  [gsub(deathknight, " ", "")] = K.CLASS_DEATHKNIGHT,
  [gsub(shaman, " ", "")]      = K.CLASS_SHAMAN,
  [gsub(mage, " ", "")]        = K.CLASS_MAGE,
  [gsub(warlock, " ", "")]     = K.CLASS_WARLOCK,
  [gsub(druid, " ", "")]       = K.CLASS_DRUID,
}

-- And the reverse
K.IndexClass = {
  [K.CLASS_WARRIOR]     = { u = "WARRIOR", c = warrior },
  [K.CLASS_PALADIN]     = { u = "PALADIN", c = paladin },
  [K.CLASS_HUNTER]      = { u = "HUNTER", c = hunter },
  [K.CLASS_ROGUE]       = { u = "ROGUE", c = rogue },
  [K.CLASS_PRIEST]      = { u = "PRIEST", c = priest },
  [K.CLASS_DEATHKNIGHT] = { u = "DEATHKNIGHT", c = deathknight },
  [K.CLASS_SHAMAN]      = { u = "SHAMAN", c = shaman },
  [K.CLASS_MAGE]        = { u = "MAGE", c = mage },
  [K.CLASS_WARLOCK]     = { u = "WARLOCK", c = warlock },
  [K.CLASS_DRUID]       = { u = "DRUID", c = druid },
}
for k,v in pairs(K.IndexClass) do
  if (v.c) then
    K.IndexClass[k].l = gsub(strlower(v.c), " ", "")
  end
end

--
-- Maps a class ID to a widget name. We cannot use IndexClass.l because that
-- can be localised. So for widget names, we always use the English name and
-- it is always one of these values.
--
K.IndexClass[K.CLASS_WARRIOR].w     = "warrior"
K.IndexClass[K.CLASS_PALADIN].w     = "paladin"
K.IndexClass[K.CLASS_HUNTER].w      = "hunter"
K.IndexClass[K.CLASS_ROGUE].w       = "rogue"
K.IndexClass[K.CLASS_PRIEST].w      = "priest"
K.IndexClass[K.CLASS_DEATHKNIGHT].w = "deathknight"
K.IndexClass[K.CLASS_SHAMAN].w      = "shaman"
K.IndexClass[K.CLASS_MAGE].w        = "mage"
K.IndexClass[K.CLASS_WARLOCK].w     = "warlock"
K.IndexClass[K.CLASS_DRUID].w       = "druid"

--
-- Many mods need to know the different class colors. We set up three tables
-- here. The first is percentage-based RGB values, the second is decimal,
-- with all numbers between 0 and 255 and the third is with text strings
-- suitable for messages.
-- This also means that it is possible to change the class colors for all
-- KahLua mods by simply changing these values.
--
K.ClassColorsRGBPerc = {
  [K.CLASS_WARRIOR]     = RAID_CLASS_COLORS["WARRIOR"],
  [K.CLASS_PALADIN]     = RAID_CLASS_COLORS["PALADIN"],
  [K.CLASS_HUNTER]      = RAID_CLASS_COLORS["HUNTER"],
  [K.CLASS_ROGUE]       = RAID_CLASS_COLORS["ROGUE"],
  [K.CLASS_PRIEST]      = RAID_CLASS_COLORS["PRIEST"],
  [K.CLASS_DEATHKNIGHT] = RAID_CLASS_COLORS["DEATHKNIGHT"],
  [K.CLASS_SHAMAN]      = RAID_CLASS_COLORS["SHAMAN"],
  [K.CLASS_MAGE]        = RAID_CLASS_COLORS["MAGE"],
  [K.CLASS_WARLOCK]     = RAID_CLASS_COLORS["WARLOCK"],
  [K.CLASS_DRUID]       = RAID_CLASS_COLORS["DRUID"],
}

function K.RGBPercToDec(rgb)
  local ret = {}
  ret.r = rgb.r * 255
  ret.g = rgb.g * 255
  ret.b = rgb.b * 255
  return ret
end

function K.RGBDecToHex(rgb)
  return strfmt("%02x%02x%02x", rgb.r, rgb.g, rgb.b)
end

function K.RGBPercToHex(rgb)
  return strfmt("%02x%02x%02x", rgb.r*255, rgb.g*255, rgb.b*255)
end

function K.RGBPercToColorCode(rgb)
  local a = 1
  if (rgb.a) then
    a = rgb.a
  end
  return strfmt("|c%02x%02x%02x%02x", a*255, rgb.r*255, rgb.g*255, rgb.b*255)
end

function K.RGBDecToColorCode(rgb)
  local a = 255
  if (rgb.a) then
    a = rgb.a
  end
  return strfmt("|c%02x%02x%02x%02x", a, rgb.r, rgb.g, rgb.b)
end

K.ClassColorsRGB = {}
K.ClassColorsHex = {}
K.ClassColorsEsc = {}
K.ClassColorsRGBPerc2 = {}
K.ClassColorsRGB2 = {}
K.ClassColorsHex2 = {}
K.ClassColorsEsc2 = {}

for k,v in pairs(K.ClassIndex) do
  K.ClassColorsRGB[v] = K.RGBPercToDec(K.ClassColorsRGBPerc[v])
  K.ClassColorsHex[v] = K.RGBDecToHex(K.ClassColorsRGB[v])
  K.ClassColorsEsc[v] = K.RGBPercToColorCode(K.ClassColorsRGBPerc[v])

  local r, g, b, a
  r = K.ClassColorsRGBPerc[v].r / 1.75
  g = K.ClassColorsRGBPerc[v].g / 1.75
  b = K.ClassColorsRGBPerc[v].b / 1.75
  a = K.ClassColorsRGBPerc[v].a or 1
  K.ClassColorsRGBPerc2[v] = { r = r, g = g, b = b, a = a }
  K.ClassColorsRGB2[v] = K.RGBPercToDec(K.ClassColorsRGBPerc2[v])
  K.ClassColorsHex2[v] = K.RGBDecToHex(K.ClassColorsRGB2[v])
  K.ClassColorsEsc2[v] = K.RGBPercToColorCode(K.ClassColorsRGBPerc2[v])
end

local function errorhandler(err)
  return geterrorhandler()(err)
end

-- Call optional function
local function safecall(func, ...)
  if type(func) == "function" then
    return xpcall(func, errorhandler, ...)
  end
end

K.safecall = safecall

-- Utility function to copy one table to another
function K.CopyTable(src, dest)
  if (type(dest) ~= "table") then
    dest = {}
  end

  if (type(src) == "table") then
    for k, v in pairs(src) do
      if (type(v) == "table") then
        v = K.CopyTable(v, dest[k])
      end
      dest[k] = v
    end
  end
  return dest
end

--
-- Quite a few metatables want to prevent indexed access, so this
-- function is used quite a bit. It simply always asserts false which
-- will raise an exception.
--
K.assert_false = function() assert(false) end

--
-- Two functions to always return true or false
--
K.always_true = function(self) return true end
K.always_false = function(self) return false end

-- We treat British the same as American English.
K.CurrentLocale = GetLocale()
if (K.CurrentLocale == "enGB") then
  K.CurrentLocale = "enUS"
end

--
-- The list of functions that each addon gets when it is initialised via
-- K:NewAddon(). So for example, each addon gets an addon.SendMessage()
-- function. Calling addon.SendMessage() is identical to calling
-- K.SendMessage() directly.
--
local evtembeds = {
  "RegisterEvent", "UnregisterEvent",
  "RegisterMessage", "UnregisterMessage",
  "UnregisterAllMessages", "UnregisterAllEvents",
  "SendMessage",
}

local ctl = _G.ChatThrottleLib
assert(ctl, "KahLua Kore requires ChatThrottleLib")
assert(ctl.version >= 24, "KahLua Kore requires ChatThrottleLib >= 24")

--
-- Utility function: return a number of nil values, followed by any number
-- of other values.
--
function K.nilret(num, ...)
  if (num > 1) then
    return nil, K.nilret(num-1, ...)
  elseif (num == 1) then
    return nil, ...
  else
    return ...
  end
end

--
-- Utility function: get one or more arguments from a string
--
function K.GetArgs(arg, argc, spos)
  argc = argc or 1
  spos = max(spos or 1, 1)

  local pos = spos
  pos = strfind(arg, "[^ ]", pos)
  if (not pos) then
    -- End of string before we got an argument
    return K.nilret(argc, 1e9)
  end

  if (argc < 1) then
    return pos
  end

  local delim_or_pipe
  local ch = strsub(arg, pos, pos)
  if (ch == '"') then
    pos = pos + 1
    delim_or_pipe='([|"])'
  elseif (ch == "'") then
    pos = pos + 1
    delim_or_pipe="([|'])"
  else
    delim_or_pipe="([| ])"
  end

  spos = pos
  while true do
    -- Find delimiter or hyperlink
    local ch,_
    pos,_,ch = strfind(arg, delim_or_pipe, pos)

    if (not pos) then
      break
    end

    if (ch == "|") then
      -- Some kind of escape

      if (strsub(arg, pos, pos + 1) == "|H") then
        -- It's a |H....|hhyper link!|h
        pos = strfind(arg, "|h", pos + 2)       -- first |h
        if (not pos) then
          break
        end

        pos = strfind(arg, "|h", pos + 2)       -- second |h
        if (not pos) then
          break
        end
      elseif (strsub(arg,pos, pos + 1) == "|T") then
        -- It's a |T....|t  texture
        pos=strfind(arg, "|t", pos + 2)
        if (not pos) then
          break
        end
      end

      pos = pos + 2 -- Skip past this escape (last |h if it was a hyperlink)
    else
      -- Found delimiter, done with this arg
      return strsub(arg, spos, pos - 1), K.GetArgs(arg, argc - 1, pos + 1)
    end
  end

  -- Search aborted, we hit end of string. return it all as one argument.
  return strsub(arg, spos), K.nilret(argc - 1, 1e9)
end

--
-- Deal with KahLua Kore slash commands. Each KahLua module can have its
-- commands accessed either by typing /kahlua NAME, or any number of
-- additional extra arguments. /kNAME is always created too. So for
-- example, if you register a module called "konfer", you can get to its
-- main argument handling function via "/kahlua konfer" or "/kkonfer" by
-- default. You can also chose to register any number of additional
-- entry points.
--
-- Each argument after the name and the primary function is either a
-- string or a table. If its a string, it is a simple entry into the
-- main argument processing array. If it is a table, the table must have
-- two members: name and func. name is the name of the command and func
-- is a reference to the function that will deal with that alias.
--

local function listall()
  local k,v
  for k,v in pairs(K.slashtable) do
    K.printf(K.ucolor, "    |cffffff00%s|r - %s [r%s]", k, v.desc, v.version)
  end
end

local function kahlua_usage()
  local L = LibStub("AceLocale-3.0"):GetLocale(KKORE_MAJOR)
  K.printf(K.ucolor, "|cffff2222<%s>|r %s - %s", K.KAHLUA,
    strfmt(L["KAHLUA_VER"], KKORE_MINOR), L["KAHLUA_DESC"])
  K.printf(K.ucolor, L["Usage: %s/%s module [arg [arg...]]%s"],
    "|cffffffff", L["CMD_KAHLUA"], "|r")
  K.printf(K.ucolor, L["    Where module is one of the following modules:"])
  listall()
  K.printf(K.ucolor, L["For help with any module, type %s/%s module %s%s."], "|cffffffff", L["CMD_KAHLUA"], L["CMD_HELP"], "|r")
end

local function kahlua(input)
  if (not input or input == "" or input:lower() == "help") then
    kahlua_usage()
    return
  end

  local L = LibStub("AceLocale-3.0"):GetLocale(KKORE_MAJOR)

  if (input:lower() == L["CMD_VERSION"] or input:lower() == "version" or input:lower() == "ver") then
    K.printf(K.ucolor, "|cffff2222<%s>|r %s - %s", K.KAHLUA,
      strfmt(L["KAHLUA_VER"], KKORE_MINOR), L["KAHLUA_DESC"])
    K.printf(K.ucolor, "(C) Copyright 2008-2019 J. Kean Johnston (Cruciformer). All rights reserved.")
    K.printf(K.ucolor, L["KKore extensions loaded:"])
    for k,v in pairs(K.extensions) do
      K.printf(K.ucolor, "    |cffffff00%s|r %s", k, strfmt(L["KAHLUA_VER"], v.version))
    end
    K.printf(K.ucolor, "This is open source software, distributed under the terms of the Apache license. For the latest version, other KahLua modules and discussion forums, visit |cffffffffhttp://www.kahluamod.com|r.")
    return
  end

  if (input:lower() == L["CMD_LIST"]) then
    K.printf(K.ucolor,L["The following modules are available:"])
    listall()
    return
  end

  local cmd, pos = K.GetArgs(input)
  if (not cmd or cmd == "") then
    kahlua_usage()
    return
  end
  if (pos == 1e9) then
    kahlua_usage()
    return
  end
  strlower(cmd)

  if (not K.slashtable[cmd]) then
    K.printf(K.ecolor, L["Module '%s' does not exist. Use %s/%s %s%s for a list of available modules."], cmd, "|cffffffff", L["CMD_KAHLUA"], L["CMD_LIST"], "|r")
    return
  end

  local arg
  if (pos == 1e9) then
    arg = ""
  else
    arg = strsub(input, pos)
  end

  K.slashtable[cmd].fn(arg)
end

local function kcmdfunc(input)
  local L = LibStub("AceLocale-3.0"):GetLocale(KKORE_MAJOR)

  if (not input or input:lower() == L["CMD_HELP"] or input == "?" or input == "") then
    K.printf(K.ucolor,L["KahLua Kore usage: %s/%s command [arg [arg...]]%s"], "|cffffffff", L["CMD_KKORE"], "|r")
    K.printf(K.ucolor,L["%s/%s %s module level%s"], "|cffffffff", L["CMD_KKORE"], L["CMD_DEBUG"], "|r")
    K.printf(K.ucolor,L["  Sets the debug level for a module. 0 disables."])
    K.printf(K.ucolor,L["  The higher the number the more verbose the output."])
    K.printf(K.ucolor,"%s/%s %s%s", "|cffffffff", L["CMD_KKORE"], L["CMD_LIST"], "|r")
    K.printf(K.ucolor,L["  Lists all modules registered with KahLua."])
    return
  end

  if (input:lower() == L["CMD_LIST"] or input:lower() == "list") then
    K.printf(K.ucolor,L["The following modules are available:"])
    listall()
    return
  end

  local cmd, pos = K.GetArgs(input)
  if (not cmd or cmd == "") then
    kcmdfunc()
    return
  end
  strlower(cmd)

  if (cmd == L["CMD_DEBUG"] or cmd == "debug") then
    local md, lvl, npos = K.GetArgs(input, 2, pos)
    if (not md or not lvl or npos ~= 1e9) then
      kcmdfunc()
      return
    end
    lvl = tonumber(lvl)

    if (not K.slashtable[md]) then
      K.printf(K.ecolor, L["Cannot enable debugging for '%s' - no such module."],
        md)
      return
    end

    if (lvl < 0 or lvl > 10) then
      K.printf(K.ecolor, L["Debug level %d out of bounds - must be between 0 and 10."], lvl)
    end

    K.debugging[md] = lvl
    return
  elseif (cmd == "ginit") then
    update_player_and_guild()
  elseif (cmd == "status") then
    local rs = strfmt("player=%s faction=%s class=%s level=%s guilded=%s", tostring(K.player.name), tostring(K.player.faction), tostring(K.player.class), tostring(K.player.level), tostring(K.player.is_guilded))
    if (K.player.is_guilded) then
      rs = rs.. strfmt(" guild=%q isgm=%s rankidx=%s numranks=%s", tostring(K.player.guild), tostring(K.player.is_gm), tostring(K.player.guildrankidx), tostring(K.guild.numranks))
    end

    K.printf("%s", rs);
    if (K.player.is_guilded) then
      local i
      for i = 1, K.guild.numranks do
        K.printf("Rank %d: name=%q", i, tostring(K.guild.ranks[i]))
      end
    end
  end
end

local function RegisterSlashCommand(name, func, desc, version, ...)
  local L = LibStub("AceLocale-3.0"):GetLocale(KKORE_MAJOR)
  if (not L) then
    error ("KahLua Kore: I18N initialization did not complete.", 2)
  end

  strlower(name)

  if (not K.slashtable) then
    K.slashtable = {}
    K.slashtable["kore"] = { fn = kcmdfunc,
      desc = strfmt(L["KORE_DESC"], K.KAHLUA),
      version = KKORE_MINOR }
    K.slashtable["kore"].alts = {}
    K.slashtable["kore"].alts["kkore"] = kcmdfunc
  end

  K.slashtable[name] = K.slashtable[name] or {}
  local st = K.slashtable[name]
  local kname = "k" .. name

  st.fn = func
  st.desc = desc
  st.version = version
  st.alts = st.alts or {}
  st.alts[kname] = func

  for i = 1, select("#", ...) do
    local aname = select(i, ...)
    if (type(aname) == "string") then
      st.alts[strlower(aname)] = func
    elseif (type(aname) == "table") then
      st.alts[strlower(aname.name)] = aname.func
    else
      error("KKore:NewAddon: invalid alternate name.", 2)
    end
  end

  --
  -- Register all of the slash command each time a new one is added.
  -- No real penalty to doing so, as it will just re-register the same
  -- old commands on additional calls to the function.
  --
  SlashCmdList["KAHLUA"] = kahlua
  _G["SLASH_KAHLUA1"] = "/kahlua"

  for k,v in pairs(K.slashtable) do
    local c, sn, ds

    c = 1
    sn = "KAHLUA_" .. k:upper()
    SlashCmdList[sn] = v.fn
    ds = "SLASH_" .. sn .. tostring(c)
    _G[ds] = "/" .. k

    for kk,vv in pairs(v.alts) do
      if (vv == v.fn) then
        c = c + 1
        ds = "SLASH_" .. sn .. tostring(c)
        _G[ds] = "/" .. kk:lower()
      else
        asn = sn .. "_" .. kk:upper()
        SlashCmdList[asn] = vv
        ds = "SLASH_" .. asn .. "1"
        _G[ds] = "/" .. kk
      end
    end
  end
end

--
-- Now for a few standard events that we capture and process so that all addons
-- interested in them can simply register for the message. We want to keep
-- track of some of this stuff for our own internal purposes.
--
local function guild_update(evt, arg1)
  if (evt == "PLAYER_GUILD_UPDATE" or evt == "GUILD_RANKS_UPDATE") then
    update_player_and_guild()
    return
  end

  if (evt == "GUILD_ROSTER_UPDATE") then
    if (arg1) then
      GuildRoster()
      return
    end

    update_player_and_guild()
    return
  end
end

local hasraidinfo

local function instance_update(evt, ...)
  if (not hasraidinfo) then
    hasraidinfo = 1
    return
  end
  K.raids = {}
  K.raids.numraids = GetNumSavedInstances()
  K.raids.info = {}
  if (K.raids.numraids > 0) then
    local i
    for i = 1, K.raids.numraids do
      local iname, iid, ireset, ilevel = GetSavedInstanceInfo(i)
      local ti = { zone = iname, raidid = iid, level = ilevel }
      tinsert(K.raids.info, ti)
    end
  end
  K:SendMessage("RAID_LIST_UPDATED")
end

K:RegisterEvent("PLAYER_GUILD_UPDATE", guild_update)
K:RegisterEvent("GUILD_ROSTER_UPDATE", guild_update)
K:RegisterEvent("GUILD_RANKS_UPDATE", guild_update)
K:RegisterEvent("UPDATE_INSTANCE_INFO", instance_update)

--
-- Deal with Kore addon initialisation. We maintain a table of all Kore
-- addons, each of which announces itself to Kore by calling KKore:NewAddon(), 
-- defined below. Each addon calls this very early on in its life in order
-- to create the addon object. That call also embeds various Kore functions
-- into the returned object. It also sets up the slash command handler for
-- the modules and arranges to call the module's argument processing
-- function (addon.ProcessSlashCommand). We also arrange for the addon's
-- initialization functions to be called at the appropriate time. An addon
-- can have four initialisation functions: OnEarlyInit, which is called when
-- ADDON_LOADED fires, OnLoginInit() which is called when PLAYER_LOGIN is
-- fired and IsLoggedIn() returns true, OnEnteringWorld() which is called
-- when PLAYER_ENTERING_WORLD fires, which can happen more than once, and
-- OnLateInit(), which is called after all addons and FrameXML code has
-- loaded. Only OnEnteringWorld() is ever called more than once.
--
K.addons = K.addons or {}
K.earlyq = K.earlyq or {}
K.loginq = K.loginq or {}
K.pewq = K.pewq or {}
K.lateq = K.lateq or {}

local function addon_tostring(this)
  return this.kore_name
end

--
-- object  - existing object to embed Kore into or nil to create a new one
-- name    - the name of the addon, usually CamelCased
-- ver     - the version of the addon
-- desc    - brief description of the addon
-- cmdname - the primary command name for accessing the addon
-- ...     - additional alternate commands for accessing the addon
function K:NewAddon(obj, name, ver, desc, cmdname, ...)
  assert(obj == nil or type(obj) == "table", "KKore: first argument must be nil or an object table.")
  assert(name, "KKore: addon name must be provided.")
  assert(ver, "KKore: addon version must be provided.")
  assert(desc, "KKore: addon description must be provided.")

  if (self.addons[name]) then
    error(("KKore: addon %q already exists."):format(name), 2)
  end

  local obj = obj or {}
  obj.kore_name = name
  obj.kore_desc = desc
  obj.kore_ver = ver
  obj.kore_minor = KKORE_MINOR

  local addonmeta = {}
  local oldmeta = getmetatable(obj)
  if (oldmeta) then
    for k,v in pairs(oldmeta) do
      addonmeta[k] = v
    end
  end
  addonmeta.__tostring = addon_tostring
  setmetatable(obj, addonmeta)

  self.addons[name] = obj

  --
  -- Each object gets a Kore-specific frame that we use for timers and other
  -- such things. Create that frame now.
  --
  obj.kore_frame = obj.kore_frame or CreateFrame("Frame", name .. "KoreFrame")
  obj.kore_frame:UnregisterAllEvents()

  K:AceKore(obj)

  RegisterSlashCommand(cmdname, function(...)
    safecall(obj.OnSlashCommand, obj, ...)
  end, desc, ver, ...)

  tinsert(self.earlyq, obj)
  tinsert(self.pewq, obj)

  if (kore_ready == 2) then
    safecall(obj.OnLateInit, obj)
  else
    tinsert(self.lateq, obj)
  end

  return obj
end

function K:GetAddon(name, opt)
  if (not opt and not self.addons[name]) then
    error(("KKore:GetAddon: cannot find addon %q"):format(tostring(name)), 2)
  end
  return self.addons[name]
end

local function addonOnEvent(this, event, arg1)
  if (event == "PLAYER_LOGIN") then
    while (#K.earlyq > 0) do
      get_static_player_info()
      local addon = tremove(K.earlyq, 1)
      safecall(addon.OnEarlyInit, addon)
      tinsert(K.loginq, addon)
    end

    if (IsLoggedIn()) then
      get_static_player_info()
      while (#K.loginq> 0) do
        local addon = tremove(K.loginq, 1)
        safecall(addon.OnLoginInit, addon)
      end
    end
    return
  elseif (event == "PLAYER_ENTERING_WORLD") then
    get_static_player_info()
    for i = 1, #K.pewq do
      local addon = K.pewq[i]
      safecall(addon.OnEnteringWorld, addon)
    end
  end
end

local function addonOnUpdate(this, event)
  this:SetScript("OnUpdate", nil)
  update_player_and_guild()
  if (kore_ready == 1) then
    kore_ready = 2
    -- For each extension or addon that is using us let them know that basic
    -- Kore functionality is ready. If a module joins late, after this code
    -- has been run, then the code that deals with adding the extension will
    -- send the event.
    for k, v in pairs(K.extensions) do
      safecall(v.library.OnLateInit, v.library)
    end
    while (#K.lateq > 0) do
      local addon = tremove(K.lateq, 1)
      safecall(addon.OnLateInit, addon)
    end
  end
end

K.addonframe = K.addonframe or CreateFrame("Frame", "KKoreAddonFrame")
K.addonframe:UnregisterAllEvents()
K.addonframe:SetScript("OnEvent", addonOnEvent)
K.addonframe:SetScript("OnUpdate", addonOnUpdate)
K.addonframe:RegisterEvent("PLAYER_LOGIN")
K.addonframe:RegisterEvent("PLAYER_ENTERING_WORLD")

K.addons = {}

local addonembeds = {
  "DoCallbacks", "RegisterAddon", "SuspendAddon", "ResumeAddon",
  "ActivateAddon", "GetAddon", "AddonCallback", "GetPrivate",
  "ConfirmationDialog", "RenameDialog", "PopupSelectionList",
  "SingleStringInputDialog"
}

function K:DoCallbacks(name, ...)
  for k, v in pairs(self.addons) do
    if (type(v) == "table" and type(v.callbacks) == "table") then
      if (v.active) then
        -- All callbacks are called with the same first 3 arguments:
        -- 1. The name of the addon.
        -- 2. The name of the callback.
        -- 3. The addon private data table.
        -- Only active addons have their callbacks called.
        safecall(v.callbacks[name], k, name, v.private, ...)
      end
    end
  end
end

--
-- Function: K:RegisterAddon(name)
-- Purpose : Called by an addon to register with an ext. This creates both a
--           private config space for the addon, as well a place to store
--           any callback functions.
-- Fires   : NEW_ADDON(name)
--           SUSPEND_ADDON(name)
-- Returns : true if the addon was added and the events fired, false if not.
--
function K:RegisterAddon(nm)
  if (not nm or type(nm) ~= "string" or nm == "" or self.addons[nm]) then
    return false
  end

  local newadd = {}

  -- New addons start out in the inactive state.
  newadd.active = false

  -- Private addon config space
  newadd.private = {}

  -- List of callbacks
  newadd.callbacks = {}

  self.addons[nm] = newadd

  safecall(self.OnNewAddon, self, nm)
  safecall(self.OnActivateAddon, self, nm, false)

  return true
end

--
-- Function: K:SuspendAddon(name)
-- Purpose : Called by an addon to suspend itself. When an addon is suspended
--           none of its callback functions will be called by Kore as it does
--           its work. However, if the addon has registered any event handlers
--           they will still be called.
-- Fires   : SUSPEND_ADDON(name)
-- Returns : true if the addon was suspended, false if it was either already
--           suspended or the addon name is invalid.
--
function K:SuspendAddon(name)
  if (not name or type(name) ~= "string" or name == "" or not self.addons[name]
      or type(self.addons[name]) ~= "table") then
    return false
  end

  if (self.addons[name].active) then
    self.addons[name].active = false
    self.addons[name].private = {}
    safecall(self.OnActivateAddon, self, name, false)
    return true
  end

  return false
end

--
-- Function: K:ResumeAddon(name)
--           K:ActivateAddon(name)
-- Purpose : Called by an addon to resume itself.
-- Fires   : ACTIVATE_ADDON(name)
-- Returns : true if the addon was resumed, false if it was either already
--           active or the addon name is invalid.
--
function K:ResumeAddon(name)
  if (not name or type(name) ~= "string" or name == "" or not self.addons[name]
      or type(self.addons[name]) ~= "table") then
    return false
  end

  if (not self.addons[name].active) then
    self.addons[name].active = true
    self.addons[name].private = {}
    safecall(self.OnActivateAddon, self, name, true)
    return true
  end

  return false
end
K.ActivateAddon = K.ResumeAddon

--
-- Function: K:GetPrivate(name)
-- Purpose : Called by an addon to get its private config space.
-- Returns : The private config space for the named addon or nil if no such
--           addon exists.
--
function K:GetPrivate(name)
  if (not name or type(name) ~= "string" or name == "" or not self.addons[name]
      or type(self.addons[name]) ~= "table" or not self.addons[name].private
      or type(self.addons[name].private) ~= "table") then
    return nil
  end

  return self.addons[name].private
end

--
-- Function: K:AddonCallback(name, callback, handler)
-- Purpose : Called by an addon with the specified name to register a new
--           callback. The name of the callback must be a string and only
--           a defined set of callback names will ever be called by Kore.
--           The callback arg can be nil to remove a callback. Each addon
--           can only register a single handler function for each given
--           callback.
-- Returns : True if the callback was registered and valid, false otherwise.
--
function K:AddonCallback(name, callback, handler)
  if (not name or type(name) ~= "string" or name == ""
      or not self.addons[name] or type(self.addons[name]) ~= "table"
      or not self.addons[name].callbacks
      or type(self.addons[name].callbacks) ~= "table"
      or not callback or type(callback) ~= "string" or callback == "" 
      or not self.valid_callbacks[callback]) then
    return false
  end

  if (handler and type(handler) ~= "function") then
    return false
  end

  self.addons[name].callbacks[callback] = handler

  return true
end

--
-- This is for extensions to KKore itself, such as KKoreParty or KKoreLoot.
-- Those extensions register with the Kore via this function. Addons that
-- use either the Kore or its extensions can register themselves with the
-- component(s) they need, which they do using the various Addon functions
-- above, each of which is added to the list of elements in the extension.
-- So for example, an addon that wants to use both KKoreParty(KRP) and
-- KKoreLoot(KLD) would call: KRP:RegisterAddon() and KLD:RegisterAddon.
--
function K:RegisterExtension(kext, major, minor)
  local ext = {}
  ext.version = minor
  ext.library = kext
  K.extensions[major] = ext
  kext.version = minor

  for k,v in pairs (evtembeds) do
    kext[v] = K[v]
  end

  for k,v in pairs (addonembeds) do
    kext[v] = K[v]
  end

  if (kore_ready == 2) then
    safecall(kext.OnLateInit, kext)
  end
end

--
-- This isn't really useful to any mod that doesn't every have to deal with
-- items or loot, but it's a small table so this is now a part of Kore.
--
-- One of the things we need to know when looting items is the armor class
-- of an item. This info is returned by GetItemInfo() but the strings are
-- localised. So we need to set up a translation table from that localised
-- string to some constant that has generic meaning to us (and is locale
-- agnostic). Set up that table now. Please note that this relies heavily
-- on the fact that some of these functions return values in the same
-- order for a given UI release. If this proves to be inacurate, this whole
-- strategy will need to be re-thought.
--
K.classfilters = {}
K.classfilters.weapon = LE_ITEM_CLASS_WEAPON   -- 2
K.classfilters.armor  = LE_ITEM_CLASS_ARMOR    -- 4

local ohaxe    = LE_ITEM_WEAPON_AXE1H            -- 0
local thaxe    = LE_ITEM_WEAPON_AXE2H            -- 1
local bows     = LE_ITEM_WEAPON_BOWS             -- 2
local guns     = LE_ITEM_WEAPON_GUNS             -- 3
local ohmace   = LE_ITEM_WEAPON_MACE1H           -- 4
local thmace   = LE_ITEM_WEAPON_MACE2H           -- 5
local poles    = LE_ITEM_WEAPON_POLEARM          -- 6
local ohsword  = LE_ITEM_WEAPON_SWORD1H          -- 7
local thsword  = LE_ITEM_WEAPON_SWORD2H          -- 8
local staves   = LE_ITEM_WEAPON_STAFF            -- 10
local fist     = LE_ITEM_WEAPON_UNARMED          -- 13
local miscw    = LE_ITEM_WEAPON_GENERIC          -- 14
local daggers  = LE_ITEM_WEAPON_DAGGER           -- 15
local thrown   = LE_ITEM_WEAPON_THROWN           -- 16
local xbows    = LE_ITEM_WEAPON_CROSSBOW         -- 18
local wands    = LE_ITEM_WEAPON_WAND             -- 19
local fish     = LE_ITEM_WEAPON_FISHINGPOLE      -- 20

local amisc    = LE_ITEM_ARMOR_GENERIC           -- 0
local cloth    = LE_ITEM_ARMOR_CLOTH             -- 1
local leather  = LE_ITEM_ARMOR_LEATHER           -- 2
local mail     = LE_ITEM_ARMOR_MAIL              -- 3
local plate    = LE_ITEM_ARMOR_PLATE             -- 4
local cosmetic = LE_ITEM_ARMOR_COSMETIC          -- 5
local shields  = LE_ITEM_ARMOR_SHIELD            -- 6
local libram   = LE_ITEM_ARMOR_LIBRAM            -- 7
local idols    = LE_ITEM_ARMOR_IDOL              -- 8
local totems   = LE_ITEM_ARMOR_TOTEM             -- 9

K.classfilters.strict = {}
K.classfilters.relaxed = {}
K.classfilters.weapons = {}
--                                 +------------- Warriors            1
--                                 |+------------ Paladins            2
--                                 ||+----------- Hunters             3
--                                 |||+---------- Rogues              4
--                                 ||||+--------- Priests             5
--                                 |||||+-------- Death Knights       6
--                                 ||||||+------- Shaman              7
--                                 |||||||+------ Mages               8
--                                 ||||||||+----- Warlocks            9
--                                 |||||||||+---- Monks               10
--                                 ||||||||||+--- Druids              11
--                                 |||||||||||+-- Demon Hunter        12
K.classfilters.strict[amisc]    = "111111111111"
K.classfilters.strict[cloth]    = "000010011000"
K.classfilters.strict[leather]  = "000100000111"
K.classfilters.strict[mail]     = "001000100000"
K.classfilters.strict[plate]    = "110001000000"
K.classfilters.strict[cosmetic] = "111111111111"
K.classfilters.strict[shields]  = "110000100000"
K.classfilters.strict[libram]   = "010000000000"
K.classfilters.strict[idols]    = "000000000010"
K.classfilters.strict[totems]   = "000000010000"
K.classfilters.relaxed[amisc]   = "111111111111"
K.classfilters.relaxed[cloth]   = "111111111111"
K.classfilters.relaxed[leather] = "111101100111"
K.classfilters.relaxed[mail]    = "111001100000"
K.classfilters.relaxed[plate]   = "110001000000"
K.classfilters.relaxed[cosmetic]= "111111111111"
K.classfilters.relaxed[shields] = "110000100000"
K.classfilters.relaxed[libram]  = "010000000000"
K.classfilters.relaxed[idols]   = "000000000010"
K.classfilters.relaxed[totems]  = "000000010000"
K.classfilters.weapons[ohaxe]   = "111101100101"
K.classfilters.weapons[thaxe]   = "111001100000"
K.classfilters.weapons[bows]    = "101100000000"
K.classfilters.weapons[guns]    = "101100000000"
K.classfilters.weapons[ohmace]  = "110111100110"
K.classfilters.weapons[thmace]  = "110001100010"
K.classfilters.weapons[poles]   = "111001000110"
K.classfilters.weapons[ohsword] = "111101011101"
K.classfilters.weapons[thsword] = "111001000000"
K.classfilters.weapons[staves]  = "101010111110"
K.classfilters.weapons[fist]    = "101100100111"
K.classfilters.weapons[miscw]   = "111111111111"
K.classfilters.weapons[daggers] = "101110111011"
K.classfilters.weapons[thrown]  = "101100000000"
K.classfilters.weapons[xbows]   = "101100000000"
K.classfilters.weapons[wands]   = "000010011000"
-- K.classfilters.weapons[glaives] = "100101000101"
K.classfilters.weapons[fish]    = "111111111111"

K.classfilters.allclasses       = "111111111111"

--
-- This function will take a given itemlink and examine its tooltip looking
-- for class restrictions. It will return a class filter mask suitable for
-- use in a loot system. If no class restriction was found, return the
-- all-inclusive mask.
--
function K.GetItemClassFilter(ilink)
  local tnm = GetItemInfo(ilink)
  if (not tnm or tnm == "") then
    return K.classfilters.allclasses, nil
  end

  local tt = K.ScanTooltip(ilink)
  local ss = strfmt(ITEM_CLASSES_ALLOWED, "(.-)\n")
  local foo = match(tt, ss)
  local boe = nil
  if (match(tt, ITEM_BIND_ON_PICKUP)) then
    boe = false
  elseif (match(tt, ITEM_BIND_ON_EQUIP)) then
    boe = true
  end

  if (foo) then
    foo = gsub(foo, " ", "")
    local clist = { "0","0","0","0","0","0","0","0","0","0","0", "0" }
    for k,v in pairs( { string.split(",", foo) } ) do
      local cp = tonumber(K.LClassIndexNSP[v]) or 10
      clist[cp] = "1"
    end
    return tconcat(clist, ""), boe
  else
    return K.classfilters.allclasses, boe
  end
end

--
-- This portion of this file (through to the end) was not written by me.
-- It was a link given to me by Adys on #wowuidev@irc.freenode.net. Many
-- thanks for this code. It has been modified to suit Kore so any bugs are
-- mine.
--

--[[
Copyright (c) Jerome Leclanche. All rights reserved.


Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

    1. Redistributions of source code must retain the above copyright notice, 
       this list of conditions and the following disclaimer.
    
    2. Redistributions in binary form must reproduce the above copyright 
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.


THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--]]

local kkorett = CreateFrame("GameTooltip", "KKoreUTooltip", UIParent, "GameTooltipTemplate")
kkorett:SetOwner(UIParent, "ANCHOR_PRESERVE")
kkorett:SetPoint("CENTER", "UIParent")
kkorett:Hide()

local function SetTooltipHack(link)
  kkorett:SetOwner(UIParent, "ANCHOR_PRESERVE")
  kkorett:SetHyperlink("spell:1")
  kkorett:Show()
  kkorett:SetHyperlink(link)
end

local function UnsetTooltipHack()
  kkorett:SetOwner(UIParent, "ANCHOR_PRESERVE")
  kkorett:Hide()
end

function K.ScanTooltip(link)
  SetTooltipHack(link)

  local lines = kkorett:NumLines()
  local tooltiptxt = ""

  for i = 1, lines do
    local left = _G["KKoreUTooltipTextLeft"..i]:GetText()
    local right = _G["KKoreUTooltipTextRight"..i]:GetText()

    if (left) then
      tooltiptxt = tooltiptxt .. left
      if (right) then
        tooltiptxt = tooltiptxt .. "\t" .. right .. "\n"
      else
        tooltiptxt = tooltiptxt .. "\n"
      end
    elseif (right) then
      tooltiptxt = tooltiptxt .. right .. "\n"
    end
  end

  UnsetTooltipHack()
  return tooltiptxt
end

--[[ NOT CURRENTLY USED
function K.GetTooltipLine(link, line, side)
  side = side or "Left"
  SetTooltipHack(link)

  local lines = kkorett:NumLines()
  if (line > lines) then
    return UnsetTooltipHack()
  end

  local text = _G["KKUTooltipText"..side..line]:GetText()
  UnsetTooltipHack()
  return text
end

function K.GetTooltipLines(link, ...)
  local lines = {}
  SetTooltipHack(link)
        
  for k,v in pairs({...}) do
    lines[#lines+1] = _G["KKUTooltipTextLeft"..v]:GetText()
  end

  UnsetTooltipHack()
  return unpack(lines)
end
]]

