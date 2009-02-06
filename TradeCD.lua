local ADDON_NAME = "TradeCD"
local MAJOR_VERSION = "TradeCD-1.0"
local MINOR_VERSION = 1
local DB_VERSION = 1

TradeCD = DMC_util:new(MAJOR_VERSION, MINOR_VERSION,
                       'TradeCD_DB', DB_VERSION)

local ldb = LibStub:GetLibrary("LibDataBroker-1.1")

local lib = TradeCD
local DB = lib.DB

local c = DMC_simple.colourise
local table_get = DMC_simple.table_get
local wrap = lib.s.wrap
local repr = DMC_simple.repr
local debug, dump = DMC_simple.create_debug(ADDON_NAME)

local _G = getfenv()
setfenv(1, DMC_util.s.checked_table(DMC_simple.copy_table(_G)))
-- global variables now have to be set through _G, and an error is raised
-- if an unset variable is accessed

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
  titansteel = "Titansteel",
  leatherworking = "Salt Shaker",
  snowmaster = "Snowmaster 9000",
  elunes_lantern = "Elune's Lantern",
}


--
-- Database manipulation
--

function DB:global_schema()
  local s = self.__index.global_schema(self)
  s.debug = false
  return s
end

function DB:player_schema()
  local s = self.__index.player_schema(self)
  s.cooldowns = {}
  return s
end

function DB:player_cooldowns(realm, player)
  return self:player_db(realm, player).cooldowns
end

function DB:update_cooldowns(cooldowns)
  local cd_db = self:player_cooldowns()
  for cooldown_id, when in pairs(cooldowns) do
    cd_db[cooldown_id] = when
  end
end

--
-- Tradeskill cooldowns
--

function lib:GetSkillSpellID(index)
  local link = GetTradeSkillRecipeLink(index)
  if not link then
    return nil
  end
  local _, _, spell_id = link:find("|Henchant:(%d+)")
  return tonumber(spell_id)
end

-- returns table of (item_id, when_cooldown_finishes) pairs
function lib:GetSkillCooldowns()
  local cooldowns = {}
  for index = 1, GetNumTradeSkills() do
    local spell_id = self:GetSkillSpellID(index)
    local cooldown_id = self.TradeskillCooldownIDs[spell_id]
    if cooldown_id then
      local cooldown = GetTradeSkillCooldown(index) or 0
      local cd_end = time() + cooldown
      if cooldowns[cooldown_id] then
        -- sanity check
        --  Are these shared? Check the old one and this are within
        --  a minute of each other
        local old_cd_end = cooldowns[cooldown_id]
        if math.abs(old_cd_end - cd_end) > 60 then
          debug(spell_id, " is not on the same cooldown as other ",
                cooldown_id)
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

function lib:UpdateSkillCooldowns()
  if IsTradeSkillLinked() then
    -- not ours, don't look at it
    return
  end
  self.DB:update_cooldowns(self:GetSkillCooldowns())
end

--
-- Item cooldowns
--

-- returns table of (item_id, when_cooldown_finishes) pairs
function lib:GetItemCooldowns()
  local cooldowns = {}
  for item_id,_ in pairs(self.ItemCooldownIDs) do
    local start, duration, enabled = GetItemCooldown(item_id)
    if start and start > 0 and duration > 0 and enabled then
      cooldowns[item_id] = start + duration
    end
  end
  return cooldowns
end

function lib:UpdateItemCooldowns()
  self.DB:update_cooldowns(self:GetItemCooldowns())
end

-- XXX Broker_TradeCooldowns watches the combat log for when something
-- of interest is used

--
-- Dump cooldowns
--

local sec_per_min = 60
local sec_per_hour = sec_per_min*60
local sec_per_day = sec_per_hour*24
function lib:DurationToDHM(d)
  local days, hours, minutes = 0, 0, 0
  days = math.floor(d/sec_per_day)
  d = d - days*sec_per_day
  hours = math.floor(d/sec_per_hour)
  d = d - hours*sec_per_hour
  minutes = math.floor(d/sec_per_min)
  return days, hours, minutes
end

function lib:DurationToString(d)
  local days, hours, minutes = self:DurationToDHM(d)
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

function lib:PrintCooldowns(cd_db)
  local names = {}
  for cooldown_id, when in pairs(cd_db) do
    local name = self.CooldownNames[cooldown_id]
    if not name then
      debug(cooldown_id, " not found in TradeCD.CooldownNames")
    end
    table.insert(names, {name, when})
  end
  table.sort(names, function (a,b) return (a[1] < b[1]) end)
  local now = time()
  for i, v in ipairs(names) do
    local d = v[2] - now
    local s
    if d > 0 then
      s = c"{red}" .. self:DurationToString(d)
    else
      s = c"{green}Ready"
    end
    self:printf(c"{yellow}%s{white}: %s", v[1], s)
  end
end

function lib:PrintMyCooldowns()
  self:print(c"{orange}Trade Cooldowns")
  self:PrintCooldowns(self.DB:player_cooldowns())
end

function lib:PrintAllCooldowns()
  self:print(c"{orange}Trade Cooldowns")
  for _, realm in ipairs(DB:realms()) do
    for _, player in ipairs(DB:players_in_realm()) do
      local cd_db = self.DB:player_cooldowns(realm, player)
      if next(cd_db) ~= nil then
        self:printf(c"{cyan}%s -- %s", player, realm)
        self:PrintCooldowns(cd_db)
      end
    end
  end
end

function lib:SlashCommand(arg)
  if arg == "show" then
    self:PrintMyCooldowns()
  elseif arg == "showall" then
    self:PrintAllCooldowns()
  elseif arg == "clear" then
    self.DB:clear_player()
  elseif arg == "clearall" then
    self.DB:clear_all()
  elseif arg == "debug on" then
    self.DB.db.debug = true
  elseif arg == "debug off" then
    self.DB.db.debug = false
  else
    self:print(c"{cyan}TradeCD help")
    self:print(c"{white}/tradecd help {cyan}-- this message")
    self:print(c"{white}/tradecd show {cyan}-- show cooldowns for this toon")
    self:print(c"{white}/tradecd showall {cyan}-- show cooldowns for all toons")
    self:print(c"{white}/tradecd clear {cyan}-- forget cooldowns on this toon")
    self:print(c"{white}/tradecd clearall {cyan}-- forget cooldowns on all toons")
  end
end

--
-- Event handling
--

-- It's amazing how many times an event can be called. Open the trade skill
-- window and TRADE_SKILL_UPDATE will be called 10+ times right after each
-- other. The delay() decorator only calls the decorated function if it
-- hasn't been called in the last 0.1 second

local function delay(f)
  local last_call = 0.0
  local function wrapper(...)
    local t = GetTime()
    local go = t > last_call
    last_call = t + 0.1
    if go then
      return f(...)
    end
  end
  return wrapper
end

local update_skill = delay(wrap(lib).UpdateSkillCooldowns)
local update_item = delay(wrap(lib).UpdateItemCooldowns)
lib.events.TRADE_SKILL_UPDATE = update_skill
lib.events.TRADE_SKILL_SHOW = update_skill
lib.events.BAG_UPDATE_COOLDOWN = update_item
lib.events.BAG_UPDATE = update_item

function lib.events:ADDON_LOADED(addon_name)
  if addon_name == ADDON_NAME then
    lib.DB:update_from_save_variable()
    _G['SLASH_TRADECD1'] = "/tradecd"
    SlashCmdList["TRADECD"] = wrap(lib).SlashCommand
  end
end

function lib:OnLoad()
  local frame = CreateFrame("Frame")
  self.events:register_events(frame)
end


lib:OnLoad()
-- End of lib.lua