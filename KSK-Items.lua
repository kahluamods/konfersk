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

ksk.iitems = {}
local sp = ksk.iitems

-- Items we want to ignore
sp["43228"] = { ignore = true } -- Stone Keepers Shard
sp["49426"] = { ignore = true } -- Emblem of Frost
sp["47241"] = { ignore = true } -- Emblem of Triumph
sp["45624"] = { ignore = true } -- Emblem of Conquest
sp["40753"] = { ignore = true } -- Emblem of Valor
sp["40752"] = { ignore = true } -- Emblem of Heroism
sp["29434"] = { ignore = true } -- Badge of Justice
sp["34664"] = { ignore = true } -- Sunmote
sp["30311"] = { ignore = true } -- KT's Warp Slicer
sp["30313"] = { ignore = true } -- KT's Staff of Disintegration
sp["30314"] = { ignore = true } -- KT's Phaseshift Bulwark
sp["30312"] = { ignore = true } -- KT's Infinity Blade
sp["30316"] = { ignore = true } -- KT's Devastation
sp["30317"] = { ignore = true } -- KT's Cosmic Infuser
sp["30318"] = { ignore = true } -- KT's Netherstrand Longbow
sp["30319"] = { ignore = true } -- KT's Nether Spike
sp["30320"] = { ignore = true } -- KT's Bundle of Spikes

