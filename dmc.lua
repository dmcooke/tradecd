-- Utility functions and objects
--
-- This can be used outside of WoW in a standalone Lua

local MAJOR_VERSION = "DMC-Utilities-1.0"
local MINOR_VERSION = 1
local lib = {}
if not module then
  -- we're running in WoW, not a standalone Lua
  lib = LibStub:NewLibrary(MAJOR_VERSION, MINOR_VERSION)
  if not lib then return end
end


local c = DMC_simple.colourise
local table_get = DMC_simple.table_get
local copy_table = DMC_simple.copy_table
local sorted_keys = DMC_simple.sorted_keys
local repr = DMC_simple.repr

local debug, dump = DMC_simple.create_debug(MAJOR_VERSION)

--
-- Prototype objects
-- Taken from http://lua-users.org/wiki/InheritanceTutorial
--

local function clone(base_object, clone_object)
  if type(base_object) ~= "table" then
    return clone_object or base_object
  end
  clone_object = clone_object or {}
  clone_object.__index = base_object
  return setmetatable(clone_object, clone_object)
end

local function isa(clone_object, base_object)
  local clone_object_type = type(clone_object)
  local base_object_type = type(base_object)
  if clone_object_type ~= "table" and base_object_type ~= "table" then
    return clone_object_type == base_object_type
  end
  local index = clone_object.__index
  local _isa = index == base_object
  while not _isa and index ~= nil do
    index = index.__index
    _isa = index == base_object
  end
  return _isa
end

-- Like clone, but copies the slots of base_object into clone_object
-- for access speed. Downsides are that changes to slots in base_object
-- are not reflected upwards; new slots however are as we still
-- set __index on clone_object to base_object.
local function xclone(base_object, clone_object)
  clone_object = clone(base_object, clone_object)
  for k, v in pairs(base_object) do
    if k ~= "__index" then
      clone_object[k] = v
    end
  end
  return clone_object
end

-- Base object.
local object = clone({}, {clone = clone, isa = isa})
local xobject = clone({}, {clone = xclone, isa = isa})


local function wrap_index(self, key)
  local upref = rawget(self, '_upref')
  local v = upref[key]
  if type(v) == "function" then
    return function(...)
             return v(upref, ...)
           end
  else
    return v
  end
end
local wrap_mt = {__index = wrap_index, __mode = "v"}

local function wrap(obj)
  local w = {_upref = obj}
  return setmetatable(w, wrap_mt)
end

local function staticmethod(obj, name, f)
  function static_method(s, ...)
    if type(s) == "table" and obj.isa(s) then
      f(unpack(...))
    else
      f(s, unpack(...))
    end
  end
  obj[name] = static_method
end

-- convert this library as returned from LibStub to a prototype object.
lib = xobject:clone(lib)
lib.object = object
lib.xobject = xobject

function lib:new(major_version, minor_version,
                 db_save_variable, db_version)
  local l = {}
  if LibStub then
    l = LibStub:NewLibrary(major_version, minor_version)
    if not l then return nil end
  end
  l = self:clone(l)
  l.DB = self.DB:new(db_save_variable, db_version)
  l.events = self.events:clone()
  return l
end

function lib:init()
end

lib.s = {
  colourise = colourise,
  copy_table = copy_table,
  table_get = table_get,
  sorted_keys = sorted_keys,
  repr = repr,
  wrap = wrap,
  clone = clone,
  xclone = xclone,
  isa = isa,
}

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
--
--

local checked_table_mt = {
  __index = function(t, key)
              error(string.format("Attempt to access non-existing key %q",
                                  tostring(key)), 2)
            end
}
local function checked_table(t)
  return setmetatable(t, checked_table_mt)
end
lib.s.checked_table = checked_table

local function isctable(t)
  return getmetatable(t) == checked_table_mt
end
lib.s.isctable = isctable

local function new_table() return {} end
local function new_ctable() return checked_table{} end

local function convert_to_ctable(t)
  if not isctable(t) then
    for k, v in pairs(t) do
      if type(v) == "table" then
        convert_to_ctable(v)
      end
    end
    checked_table(t)
  end
end

local function ctable_get(d, key, default)
  local value = rawget(d, key)
  if value == nil then
    value = default()
    d[key] = value
  end
  return value  
end

local function lazy_table_copy(tbl)
  local function getter(t, k)
    local v = tbl[k]
    t[k] = v
    return v
  end
  return setmetatable({}, {__index = getter})
end

local function lazy_ctable_copy(tbl)
  local function getter(t, k)
    local v = tbl[k]
    if v == nil then
      error(string.format("Attempt to access non-existing key %q",
                          tostring(key)), 2)
    end
    t[k] = v
    return v
  end
end

--
-- Player database
--

local DB = xobject:clone()
lib.DB = DB
DB.this_player = UnitName("player")
DB.this_realm = GetRealmName()

function DB:new(...)
  local obj = DB:clone()
  obj:init(...)
  return obj
end

function DB:init(save_variable, version)
  self.save_variable = save_variable
  self.version = version
  self.db = {}
end

function DB:update_from_save_variable()
  self.db = table_get(_G, self.save_variable, new_ctable)
  self:upgrade(self.version)
end

function DB:update_to_save_variable()
  _G[self.save_variable] = self.db
end

function DB:global_schema()
  return checked_table{version = self.version,
                       realm = checked_table{}}
end

function DB:player_schema()
  return checked_table{}
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
  convert_to_ctable(self.db)
end

function DB:realm_db(realm)
  realm = realm or self.this_realm
  return ctable_get(self.db.realm, realm, new_ctable)
end

function DB:player_db(realm, player)
  local realm_db = self:realm_db(realm)
  player = player or self.this_player
  return ctable_get(realm_db, player, wrap(self).player_schema)
end

function DB:realms()
  return sorted_keys(self.db.realm)
end

function DB:players_in_realm(realm)
  return sorted_keys(self:realm_db(realm))
end

function DB:clear_player(realm, player)
  local realm_db = self:realm_db(realm)
  player = player or self.this_player
  realm_db[player] = nil
end

function DB:clear_all()
  self.db.realm = checked_table{}
end

--
-- Events
--

lib.events = object:clone()

function lib.events.register_events(self, frame)
  frame = frame or CreateFrame("Frame")
  frame:SetScript("OnEvent", function(frame, event, ...)
                               self[event](self, ...)
                             end)
  for event, _ in pairs(self) do
    if event:match("^[A-Z]") then
      frame:RegisterEvent(event)
    end
  end
end

DMC_util = lib
if module then
  dmc = lib
  module("dmc")
end
