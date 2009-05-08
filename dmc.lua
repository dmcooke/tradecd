-- Utility functions and objects
--
-- This can be used outside of WoW in a standalone Lua

local MAJOR_VERSION = "DMC-Utilities-1.0"
local MINOR_VERSION = 1
local lib = LibStub:NewLibrary(MAJOR_VERSION, MINOR_VERSION)
if not lib then return end

local base = LibStub:GetLibrary("DMC-Base-1.0")
local DMC_debug = LibStub:GetLibrary("DMC-Debug-1.0", 1)

local copy_table = base.copy_table
local repr = tostring
if DMC_debug then
  repr = DMC_debug.repr
end

function lib:print(msg)
  if self.icon then
    print(string.format("|T%s:0|t%s", self.icon, msg))
  else
    print(msg)
  end
end

function lib:printf(msg, ...)
  local s = string.format(msg, ...)
  self:print(s)
end


--
-- Player database
--

local DB = {}
lib.DB = DB

function DB.new(...)
  local obj = copy_table(DB)
  obj.super = DB
  obj:init(...)
  return obj
end

function DB:init(save_variable, version)
  self.this_player = UnitName("player")
  self.this_realm = GetRealmName()
  self.save_variable = save_variable
  self.version = version
  self.db = {}
end

function DB:update_from_save_variable()
  self.db = base.table_get(_G, self.save_variable, base.new_ctable)
  self:upgrade(self.version)
end

function DB:update_to_save_variable()
  _G[self.save_variable] = self.db
end

function DB:global_schema()
  return base.ctable{version = self.version,
                     realm = base.ctable{}}
end

function DB:player_schema()
  return base.ctable{}
end

function DB:init_store()
  local db = self.db
  for k, v in pairs(self:global_schema()) do
    if db[k] == nil then
      db[k] = v
    end
  end
end

function DB:upgrade()
  if self.db.version == nil then
    self:init_store()
  elseif self.db.version ~= self.version then
    print(string.format("can't upgrade database version %s to version %s",
                        repr(self.db.version), repr(self.version)))
  end
  base.deep_convert_to_ctable(self.db)
end

function DB:realm_db(realm)
  realm = realm or self.this_realm
  return base.ctable_get(self.db.realm, realm, base.new_ctable)
end

function DB:player_db(realm, player)
  local realm_db = self:realm_db(realm)
  player = player or self.this_player
  return base.ctable_get(realm_db, player,
                         base.wrap(self).player_schema)
end

function DB:realms()
  return base.sorted_keys(self.db.realm)
end

function DB:players_in_realm(realm)
  return base.sorted_keys(self:realm_db(realm))
end

function DB:clear_player(realm, player)
  local realm_db = self:realm_db(realm)
  player = player or self.this_player
  realm_db[player] = nil
end

function DB:clear_all()
  self.db.realm = base.ctable{}
end

--
-- Events
--

local events = {}

function events.new()
  local obj = copy_table(events)
  return obj
end

function events.register_events(self, frame)
  self.frame = frame or CreateFrame("Frame")
  self.frame:SetScript("OnEvent", function(frame, event, ...)
                                    self[event](self, event, ...)
                                  end)
  for event, _ in pairs(self) do
    if event:match("^[A-Z]") then
      self.frame:RegisterEvent(event)
    end
  end
end


function lib:embed(other)
  other.print = self.print
  other.printf = self.printf
  other.new_events = events.new
  return other
end
