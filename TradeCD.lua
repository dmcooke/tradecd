local MAJOR_VERSION = "DMC-Utilities-1.0"
local MINOR_VERSION = 1
local DB_VERSION = 1


local util = LibStub.GetLibrary("DMC-Utilities-1.0", 1)
local lib = LibStub.NewLibrary(MAJOR_VERSION, MINOR_VERSION)
lib = util:clone(lib)

TradeCD = lib
TradeCD_DB = {}

local c = lib.colourise
local table_get = lib.table_get

lib.icon = "Interface\\Icons\\INV_Misc_PocketWatch_03"

lib.TradeskillCooldownIDs = {
  -- Alchemy
  --  CDs for primal might, earthstorm diamond, and skyfire diamond were
  --  removed in 3.0.2
  -- eternals
  [54020] = "elemental",        -- Transmute: Eternal Might
  [53777] = "elemental",        -- Transmute: Eternal Air to Earth
  [53776] = "elemental",        -- Transmute: Eternal Air to Water
  [53781] = "elemental",        -- Transmute: Eternal Earth to Air
  [53782] = "elemental",        -- Transmute: Eternal Earth to Shadow
  [53775] = "elemental",        -- Transmute: Eternal Fire to Life
  [53774] = "elemental",        -- Transmute: Eternal Fire to Water
  [53773] = "elemental",        -- Transmute: Eternal Life to Fire
  [53771] = "elemental",        -- Transmute: Eternal Life to Shadow
  [53779] = "elemental",        -- Transmute: Eternal Shadow to Earth
  [53780] = "elemental",        -- Transmute: Eternal Shadow to Life
  [53783] = "elemental",        -- Transmute: Eternal Water to Air
  [53784] = "elemental",        -- Transmute: Eternal Water to Fire
  -- primals
  [28566] = "elemental",        -- Transmute: Primal Air to Fire
  [28585] = "elemental",        -- Transmute: Primal Earth to Life
  [28567] = "elemental",        -- Transmute: Primal Earth to Water
  [28568] = "elemental",        -- Transmute: Primal Fire to Earth
  [28583] = "elemental",        -- Transmute: Primal Fire to Mana
  [28584] = "elemental",        -- Transmute: Primal Life to Earth
  [28582] = "elemental",        -- Transmute: Primal Mana to Fire
  [28580] = "elemental",        -- Transmute: Primal Shadow to Water
  [28569] = "elemental",        -- Transmute: Primal Water to Air
  [28581] = "elemental",        -- Transmute: Primal Water to Shadow
  -- classic
  [17559] = "elemental",        -- Transmute: Air to Fire
  [17566] = "elemental",        -- Transmute: Earth to Life
  [17561] = "elemental",        -- Transmute: Earth to Water
  [17560] = "elemental",        -- Transmute: Fire to Earth
  [17565] = "elemental",        -- Transmute: Life to Earth
  [17563] = "elemental",        -- Transmute: Undeath to Water
  [17564] = "elemental",        -- Transmute: Water to Undeath
  -- metals
  [11479] = "elemental",        -- Transmute: Iron to Gold
  [11480] = "elemental",        -- Transmute: Mithril to Truesilver
  [60350] = "elemental",        -- Transmute: Titanium
  -- research
  [60893] = "alchemy_research", -- Northrend alchemy research

  -- Enchanting
  [28028] = "void_sphere",      -- Void Sphere

  -- Tailoring
  --  TBC cloths no longer have a CD in 3.0.8
  [56002] = "ebonweave",        -- Ebonweave
  [56001] = "moonshroud",       -- Moonshroud
  [56003] = "spellweave",       -- Spellweave

  -- Inscription
  [61288] = "minor_inscription", -- Minor Inscription Research
  [61177] = "northrend_inscription", -- Northrend Inscription Research

  -- Mining
  [55208] = "titansteel",       -- Titansteel
}

lib.ItemCooldownIDs = {
  [15846] = "salt_shaker",      -- Salt Shaker
  [17716] = "snowmaster",       -- Snowmaster 9000
  [21540] = "elunes_lantern",   -- Elune's Lantern
  [27388] = "mr_pinchy",        -- Mr. Pinchy
}

lib.CooldownNames = {
  elemental = "Elemental",
  alchemy_research = "Northrend alchemy research",
  void_sphere = "Void sphere",
  ebonweave = "Ebonweave",
  moonshroud = "Moonshroud",
  spellweave = "Spellweave",
  minor_inscription = "Minor inscription research",
  northrend_inscription = "Northrend inscription research",
  titanstell = "Titansteel",
  leatherworking = "Salt Shaker",
  snowmaster = "Snowmaster 9000",
  elunes_lantern = "Elune's Lantern",
}


--
-- Database manipulation
---

local DB = util:new_character_database(TradeCD_DB)
lib.DB = DB

function DB:initialise(version)
  self.__index.initialise(self, version)
  if not self.db.debug then
    self.db.debug = false
  end
end

function DB:player_defaults()
  return {cooldowns = {}}
end

function DB:player_cooldowns(realm, player)
  return self:player_db(realm, player).cooldowns
end

function DB:update_cooldowns(cooldowns)
  local cd_db = self:get_player_cooldowns()
  for cooldown_id, when in pairs(cooldowns) do
    cd_db[cooldown_id] = when
  end
end

--
-- Tradeskill cooldowns
--

function lib.GetSkillSpellID(index)
  local link = GetTradeSkillRecipeLink(index)
  if not link then
    return nil
  end
  local _, _, spell_id = link:find("|Henchant:(%d+)")
  return tonumber(spell_id)
end

-- returns table of (item_id, when_cooldown_finishes) pairs
function lib.GetSkillCooldowns()
  -- ??? collapsed sections in tradeskills
  local cooldowns = {}
  for index = 1, GetNumTradeSkills() do
    local spell_id = lib.GetSkillSpellID(index)
    local cooldown_id = lib.TradeskillCooldownIDs[spell_id]
    if cooldown_id then
      local cooldown = GetTradeSkillCooldown(index)
      local cd_end = time() + cooldown
      if cooldowns[cooldown_id] then
        -- sanity check
        --  Are these shared? Check the old one and this are within
        --  a minute of each other
        local old_cd_end = cooldowns[cooldown_id]
        if math.abs(old_cd_end - cd_end) > 60 then
          lib:debug("%s is not on the same cooldown as other %s",
                        spell_id, cooldown_id)
        else
          cooldowns[cooldown_id] = math.min(old_cd_end, cd_end)
        end
      else
        cooldowns[cooldown_id] = cd_end
      end
    end
  end
  return cooldowns
end

function lib.UpdateSkillCooldowns()
  if IsTradeSkillLinked() then
    return
  end
  DB:update_cooldowns(lib.GetSkillCooldowns())
end

--
-- Item cooldowns
--

-- returns table of (item_id, when_cooldown_finishes) pairs
function lib.GetItemCooldowns()
  local cooldowns
  for item_id,_ in pairs(lib.ItemCooldownIDs) do
    local start, duration, enabled = GetItemCooldown(item_id)
    if start and start > 0 and duration > 0 and enabled then
      if not cooldowns then cooldowns = {} end
      cooldowns[item_id] = start + duration
    end
  end
  return cooldowns
end

function lib.UpdateItemCooldowns()
  DB:update_cooldowns(lib.GetItemCooldowns())
end

-- XXX Broker_TradeCooldowns watches the combat log for when something
-- of interest is used

--
-- Dump cooldowns
--

local sec_per_min = 60
local sec_per_hour = sec_per_min*60
local sec_per_day = sec_per_hour*24
function lib.DurationToDHM(d)
  local days, hours, minutes = 0, 0, 0
  days = math.floor(d/sec_per_day)
  d = d - days*sec_per_day
  hours = math.floor(d/sec_per_hour)
  d = d - hours*sec_per_hour
  minutes = math.floor(d/sec_per_min)
  return days, hours, minutes
end

function lib.DurationToString(d)
  local days, hours, minutes = lib.DurationToDHM(d)
  local s = ""
  if days > 0 then
    s = s .. tostring(days) .. "d"
  end
  if hours > 0 or days ~= 0 then
    s = s .. tostring(hours) .. "h"
  end
  s = s .. tostring(minutes) .. "m"
  return s
end

function lib.PrintCooldowns(cd_db)
  local names = {}
  for cooldown_id, when in pairs(cd_db) do
    local name = lib.CooldownNames[cooldown_id]
    if not name then
      lib:debug("%s not found in TradeCD.CooldownNames", name)
    end
    table.insert(names, {name, when})
  end
  table.sort(names, function (a,b) return (a[1] < b[1]) end)
  local now = time()
  for i, v in ipairs(names) do
    local d = lib.DurationToString(v[2] - now)
    lib:print(string.format(c"{green}%s{white}: {red}%s", v[1], d))
  end
end

function lib.PrintMyCooldowns()
  lib.PrintPlayerCooldowns(lib.GetPlayerCooldowns())
end

function lib.PrintAllCooldowns()
  local realms = lib.GetRealms()
  for _, realm in ipairs(lib.GetRealms()) do
    for _, player in ipairs(lib.GetPlayersInRealm(realm)) do
      lib:print(c("{blue}") .. name)
      local cd_db = lib.GetPlayerCooldowns(realm, player)
      lib.PrintCooldowns(cd_db)
    end
  end
end

function lib.SlashCommand(arg)
  if arg == "show" then
    lib.PrintMyCooldowns()
  elseif arg == "showall" then
    lib.PrintAllCooldowns()
  elseif arg == "clear" then
    wipe(lib.GetPlayerDB())
  elseif arg == "clearall" then
    wipe(lib.GetRealmsDB())
  else
    lib:print(c"{cyan}TradeCD help")
    lib:print(c"{white}/tradecd help {cyan}-- this message")
    lib:print(c"{white}/tradecd show {cyan}-- show cooldowns for this toon")
    lib:print(c"{white}/tradecd showall {cyan}-- show cooldowns for all toons")
    lib:print(c"{white}/tradecd clear {cyan}-- forget cooldowns on this toon")
    lib:print(c"{white}/tradecd clearall {cyan}-- forget cooldowns on all toons")
  end
end

--
-- Event handling
--

lib.events = {}
lib.events.TRADE_SKILL_UPDATE = lib.UpdateSkillCooldowns
lib.events.TRADE_SKILL_SHOW = lib.UpdateSkillCooldowns
lib.events.BAG_UPDATE_COOLDOWN = lib.UpdateItemCooldowns
lib.events.BAG_UPDATE = lib.UpdateItemCooldowns

function lib.events.ADDON_LOADED(addon_name)
  DB.initialise(DB_VERSION)
  SLASH_TRADECD1 = "/tradecd"
  SlashCmdList["TRADECD"] = lib.SlashCommand
end

function lib.OnLoad()
  local frame = CreateFrame("Frame")
  frame:SetScript("OnEvent", function(self, event, ...)
                               lib.events[event](...)
                             end)
  for event, callback in pairs(lib.events) do
    frame:RegisterEvent(event)
  end
end


lib.OnLoad()
-- End of lib.lua
