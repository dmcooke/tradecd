--
-- Static methods on lib
--   colourise
--   table_get
--   sorted_keys
--   dump_to_string
-- Instance variables of lib
--   object (base prototype object)

local MAJOR_VERSION = "DMC-Utilities-1.0"
local MINOR_VERSION = 1
local lib
if module then
  -- we're running in an interactive interpreter, instead of WoW
  lib = {}
  -- we set this up as a module at the end
else
  lib = LibStub:NewLibrary(MAJOR_VERSION, MINOR_VERSION)
  if not lib then return end
end

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

function isa(clone_object, base_object)
  local clone_object_type = type(clone_object)
  local base_object_type = type(base_object)
  if clone_object_type ~= "table" and base_object_type ~= table then
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

-- Base object. Derives from the table package, so object.foreach works
local object = clone(table, {clone = clone, isa = isa})

-- convert this library as returned from LibStub to a prototype object.
lib = clone(object, lib)

lib.object = object


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


local colours = {
  stop = "|r",
  white = "|cFFFFFFFF",
  black = "|cFF000000",
  red = "|cFFFF0000",
  green = "|cFF00FF00",
  blue = "|cFF0000FF",
  cyan = "|cFF00FFFF",
  yellow = "|cFFFFFF00",
  magenta = "|cFFFFF00FF",
}

local function colourise(s)
  return string.gsub(s, "{(%w+)}", colours)
end
lib.colourise = colourise

local function table_get(d, key, default)
  local value = d[key]
  if value == nil then
    value = default()
    d[key] = value
  end
  return value
end
lib.table_get = table_get

local function sorted_keys(t)
  local keys = {}
  for k, v in pairs(t) do
    table.insert(keys, k)
  end
  table.sort(keys)
  return keys
end
lib.sorted_keys = sorted_keys


local dump_table
function lib.dump_to_string(v)
  local d = dump_table[type(v)]
  if d then return d(v)
  else return tostring(v) end
end
dump_table = {
  ["nil"] = function (_) return "nil" end,
  ["number"] = tostring,
  ["string"] = function (s)
                 return "\"" .. string.gsub(s, "\\", "\\\\") .. "\""
               end,
  ["boolean"] = tostring,
  ["table"] = function (t)
                local s = tostring(t)
                s = s .. " = {"
                for k, v in pairs(t) do
                  s = s .. ("[" ..  dump_to_string(k)
                          .. "] = " .. dump_to_string(v) .. ",")
                end
                return s.."}"
              end,
  ["function"] = tostring,
  ["thread"] = tostring,
  ["userdata"] = tostring,
}

function lib:print(msg)
  if msg then
    if self.icon then
      print(string.format("|T%s:0|t%s", self.icon, msg))
    else
      print(msg)
    end
  end
end

function lib:debug(msg)
  if msg and self.debug then
    self:print("DEBUG: " .. tostring(msg))
  end
end

function lib:dump(v)
  self:print(dump_to_string(v))
end


--
-- Player database
--

local DB = object:clone()

function lib:new_character_database(saved_variable)
  local db = DB:clone()
  db.lib = self
  db.db = saved_variable
  return db
end

function DB:initialise(version)
  local db = self.db
  if not db.version then
    db.version = "1.0"
  elseif db.version ~= version then
    self:upgrade(version)
  end
  if not db.realm then
    db.realm = {}
  end
end

function DB:upgrade(version)
  self.lib:debug(string.format("can't upgrade database version %s to version %s", self.db.version, version))
end

function DB:player_defaults()
  return {}
end

function DB:player_db(realm, player)
  if not realm then
    realm = GetRealmName()
    player = UnitName("player")
  end
  local realm_db = table_get(self.db.realm, realm,
                             function () return {} end)
  local player_db = table_get(realm_db, player,
                              function () return self:player_defaults() end)
  return player_db
end

function DB:realms()
  return sorted_keys(self.db.realms)
end

function DB:players_in_realm(realm)
  local realm_db = self.db.realm[realm]
  if realm_db then return sorted_keys(realm_db)
  else return {} end
end

if module then
  dmc = lib
  module("dmc")
end