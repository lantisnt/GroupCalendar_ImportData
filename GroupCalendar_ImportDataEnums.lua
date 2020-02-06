-- This file is part of Group Calendar Import Data WoW Classic AddOn.

-- Group Calendar Import Data WoW Classic AddOn is free software: 
-- you can redistribute it and/or modify it
-- under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.

-- Group Calendar Import Data WoW Classic AddOn is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.

-- You should have received a copy of the GNU General Public License
-- along with Group Calendar Import Data WoW Classic AddOn.
-- If not, see <https://www.gnu.org/licenses/>.

function Set (list)
  local set = {}
  for _, l in ipairs(list) do set[l] = true end
  return set
end

GCID = { -- TODO get class and spec codes from main addon automatically
  EVENT_INFO_COLUMN = {
    RAID = "raid", 
    NAME = "name", 
    DATE = "date",
    TIME = "time"
  },
  CLASS = 
  {
    ["druid"] = "D",
    ["hunter"] = "H",
    ["mage"] = "M",
    ["paladin"] = "L",
    ["priest"] = "P",
    ["rogue"] = "R",
    ["shaman"] = "S",
    ["warlock"] = "K",
    ["warrior"] = "W",
    ["unknown"] = "?"
  },
  VALID_CLASS = Set {"druid", "hunter", "mage", "paladin", "priest", "rogue", "shaman", "warlock", "warrior"},
  SPEC =
  { 
    ["DPS"] = "D",
    ["Healer"] = "H",
    ["Tank"] = "T",
    ["Unknown"] = "U",
    NAME_MAP =
    {
      DPS = Set {"dps", "fury", "arms", "ret", "retri", "retribution", "feral", "moonkin", "balance", "shadow", "elemental", "ele", "enhancement", "ench"},
      HEALER = Set {"heal", "healer", "holy", "resto", "restoration"},
      TANK = Set {"tank", "bear", "prot", "protection"}
    }
  },
  RAID = 
  {
    MOLTEN_CORE = { ID = "MC", NAME_MAP = Set {"mc", "molten core", "moltencore" } },
    BLACKWING_LAIR = { ID = "BWL", NAME_MAP = Set {"bwl", "blackwing lair", "blackwinglair" } },
    ONYXIA = { ID = "Onyxia", NAME_MAP = Set {"ony", "onyxia", "onyxias lair", "onyxiaslair" } },
    DEFAULT = "Act"
  },
  SETTINGS = 
  {
    FORMAT =
    {
      DATE = { DMY = 1, MDY = 2, YMD = 3 },
      TIME = { TIME_12H = 12, TIME_24H = 24 } 
    }
  }
}

PLAYERS = "players"