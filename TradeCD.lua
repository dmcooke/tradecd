local ADDON_NAME = "TradeCD"
local MAJOR_VERSION = "TradeCD-1.0"
local MINOR_VERSION = 1
local DB_VERSION = 1

TradeCD = LibStub:NewLibrary(MAJOR_VERSION, MINOR_VERSION)
local lib = TradeCD
local ldb = LibStub:GetLibrary("LibDataBroker-1.1")
local dmc = LibStub:GetLibrary("DMC-Utilities-1.0")
local base = LibStub:GetLibrary("DMC-Base-1.0")
local DMC_debug = LibStub:GetLibrary("DMC-Debug-1.0")

local DB = dmc.DB.new('TradeCD_DB', 1)
lib.DB = DB

local c = base.c
local wrap = base.wrap
local debug, dump = DMC_debug.create_debug(ADDON_NAME)
TradeCD.debug = debug
TradeCD.dump = dump

local _G = base.global_protection()
-- global variables now have to be set through _G, and an error is raised
-- if an unset variable is accessed

dmc:embed(lib)

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
  local s = self.super.global_schema(self)
  s.debug = false
  return s
end

function DB:player_schema()
  local s = self.super.player_schema(self)
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

function lib:get_skill_spell_id(index)
  local link = GetTradeSkillRecipeLink(index)
  if not link then
    return nil
  end
  local _, _, spell_id = link:find("|Henchant:(%d+)")
  return tonumber(spell_id)
end

-- returns table of (item_id, when_cooldown_finishes) pairs
function lib:get_skill_cooldowns()
  local now = time()
  local cooldowns = {}
  for index = 1, GetNumTradeSkills() do
    local spell_id = self:get_skill_spell_id(index)
    local cooldown_id = self.TradeskillCooldownIDs[spell_id]
    if cooldown_id then
      local cooldown = GetTradeSkillCooldown(index) or 0
      local cd_end = now + cooldown
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

function lib:update_skill_cooldowns()
  if IsTradeSkillLinked() then
    -- not ours, don't look at it
    return
  end
  DB:update_cooldowns(self:get_skill_cooldowns())
end

--
-- Item cooldowns
--

-- returns table of (item_id, when_cooldown_finishes) pairs
function lib:get_item_cooldowns()
  -- Convert current system uptime to seconds since the epoch
  local gt_offset = time () - GetTime()
  local cooldowns = {}
  for item_id, _ in pairs(self.ItemCooldownIDs) do
    -- start is in terms of current system uptime (i.e., GetTime())
    local start, duration, enabled = GetItemCooldown(item_id)
    if start and start > 0 and duration > 0 and enabled then
      local cooldown_id = self.ItemCooldownIDs[item_id]
      cooldowns[cooldown_id] = gt_offset + start + duration
    end
  end
  return cooldowns
end

function lib:update_item_cooldowns()
  DB:update_cooldowns(self:get_item_cooldowns())
end

-- XXX Broker_TradeCooldowns watches the combat log for when something
-- of interest is used

--
-- Dump cooldowns
--

local sec_per_min = 60
local sec_per_hour = sec_per_min*60
local sec_per_day = sec_per_hour*24
function lib:duration_to_dhm(d)
  local days, hours, minutes = 0, 0, 0
  days = math.floor(d/sec_per_day)
  d = d - days*sec_per_day
  hours = math.floor(d/sec_per_hour)
  d = d - hours*sec_per_hour
  minutes = math.floor(d/sec_per_min)
  return days, hours, minutes
end

function lib:duration_to_string(d)
  local days, hours, minutes = self:duration_to_dhm(d)
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

function lib:foreach_cooldown(cd_db, cd_callback)
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
    local d = math.max(v[2] - now, 0)
    cd_callback(v[1], d)
  end
end

function lib:print_cooldowns(cd_db)
  local function callback(what, duration)
    if duration > 0 then
      s = c"{red}" .. self:duration_to_string(duration)
    else
      s = c"{green}Ready"
    end
    self:printf(c"{yellow}%s{white}: %s", what, s)
  end
  self:foreach_cooldown(cd_db, callback)
end

function lib:print_my_cooldowns()
  self:print(c"{orange}Trade Cooldowns")
  self:print_cooldowns(DB:player_cooldowns())
end

function lib:foreach_player(callback)
  for _, realm in ipairs(DB:realms()) do
    for _, player in ipairs(DB:players_in_realm()) do
      local cd_db = DB:player_cooldowns(realm, player)
      if next(cd_db) ~= nil then
        callback(player, realm, cd_db)
      end
    end
  end
end

function lib:print_all_cooldowns()
  self:print(c"{orange}Trade Cooldowns")
  local function player_callback(player, realm, cd_db)
    self:printf(c"{cyan}%s -- %s", player, realm)
    self:print_cooldowns(cd_db)
  end
  lib:foreach_player(player_callback)
end

function lib:slash_command(arg)
  if arg == "show" then
    self:print_my_cooldowns()
  elseif arg == "showall" then
    self:print_all_cooldowns()
  elseif arg == "clear" then
    DB:clear_player()
  elseif arg == "clearall" then
    DB:clear_all()
  elseif arg == "debug on" then
    DB.db.debug = true
  elseif arg == "debug off" then
    DB.db.debug = false
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
-- LibDataBroker support
--

local dataobj = ldb:NewDataObject(ADDON_NAME, {
                                    type = "data source",
                                    text = ADDON_NAME,
                                    label = ADDON_NAME,
                                    icon = lib.icon,
                                  })

function dataobj:OnTooltipShow()
  local function cooldown_callback(what, duration)
    local s, right_r, right_g, right_b
    if duration > 0 then
      s = lib:duration_to_string(duration)
      right_r, right_g, right_b = 1, 0, 0
    else
      s = "Ready"
      right_r, right_g, right_b = 0, 1, 0
    end
    self:AddDoubleLine(what, s, 1, 1, 0, right_r, right_g, right_b)
  end
  local function player_callback(player, realm, cd_db)
    self:AddLine(player .. " (" .. realm .. ")", 0, 1, 1)
    lib:foreach_cooldown(cd_db, cooldown_callback)
  end
  self:AddLine("Tradeskill Cooldowns", 1, 0.65, 0)
  lib:foreach_player(player_callback)
end

--
-- Event handling
--

-- It's amazing how many times an event can be called. Open the trade skill
-- window and TRADE_SKILL_UPDATE will be called 10+ times right after each
-- other. The delay() decorator only calls the decorated function if it
-- hasn't been called in the last 0.1 second. This isn't ideal; the first one
-- may not have the right info yet, but it seems to work.

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

local update_skill = delay(wrap(lib).update_skill_cooldowns)
local update_item = delay(wrap(lib).update_item_cooldowns)

local events = dmc.events.new()
events.TRADE_SKILL_UPDATE = update_skill
events.TRADE_SKILL_SHOW = update_skill
events.BAG_UPDATE_COOLDOWN = update_item
events.BAG_UPDATE = update_item

function events:ADDON_LOADED(addon_name)
  if addon_name == ADDON_NAME then
    DB:update_from_save_variable()
    _G['SLASH_TRADECD1'] = "/tradecd"
    SlashCmdList["TRADECD"] = wrap(lib).slash_command
  end
end

function lib:OnLoad()
  local frame = CreateFrame("Frame")
  events:register_events(frame)
end


lib:OnLoad()
-- End of lib.lua
