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
  }
}

PLAYERS = "players"