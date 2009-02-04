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

if not wipe then
  function wipe(t)
    for _, k in ipairs(t) do
      t[k] = nil
    end
  end
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

-- Base object.
local object = clone({}, {clone = clone, isa = isa})

local function copy_table(t)
  local c = {}
  for k, v in pairs(t) do
    c[k] = v
  end
  return c
end

--
-- xobject has added functionality over object
-- * xobject.extend_clone(f) adds a function f(xobject) that is called
--   when the object is cloned. If f is a string, we do on xobject[f]:clone()
--   The method used (default 'clone') can be a string or a function.
-- * xobject.wrap is a table that returns closures over the object
--   i.e., xobject.wrap.f() = function () return xobject.f(xobject) end
--   Useful for passing methods around as functions
--

local function xclone(self, klone)
  klone = clone(self, klone)
  klone._clone_functions = copy_table(self._clone_functions)
  for _, k in ipairs(klone._clone_functions) do
    k(klone)
  end
  return klone
end

local function extend_clone(self, f, method)
  if type(f) == "string" then
    local name = f
    method = method or 'clone'
    if type(method) == "string" then
      f = function(self)
            self[name] = self[name][method]()
          end
    else
      f = function(self)
            self[name] = method(self)
          end
    end
  end
  table.insert(self._clone_functions, f)
end

local xobject = clone({}, {clone = xclone, isa = isa,
                           extend_clone = extend_clone})
xobject._clone_functions = {}

xobject.wrap = {}

local function wrap__index(self, key)
  local upref = self.upref
  local v = upref[key]
  if type(v) == "function" then
    return function(...)
             return v(upref, ...)
           end
  else
    return v
  end
end
local wrap_mt = {__index = wrap__index, __mode = "v"}

local function wrap(obj)
  local w = {upref = self}
  return setmetatable(w, wrap_mt)
end

xobject:extend_clone('wrap', wrap)


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

function lib:new(major_version, minor_version)
  local l = LibStub:NewLibrary(major_version, minor_version)
  if not l then
    return nil
  end
  return lib:clone(l)
end

lib.s = {}
lib.s.copy_table = copy_table
lib.s.wrap = wrap

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
lib.s.colourise = colourise
local c = colourise

local function table_get(d, key, default)
  local value = d[key]
  if value == nil then
    value = default()
    d[key] = value
  end
  return value
end
lib.s.table_get = table_get

local function sorted_keys(t)
  local keys = {}
  for k, v in pairs(t) do
    table.insert(keys, k)
  end
  table.sort(keys)
  return keys
end
lib.s.sorted_keys = sorted_keys

local function simple_repr(v)
  local t = type(v)
  if t == "string" then
    return string.format("%q", v)
  else
    return tostring(v)
  end
end

local function table_print(tt, indent, done)
  done = done or {}
  indent = indent or 0
  if type(tt) == "table" then
    local sb = {}
    for key, value in pairs (tt) do
      table.insert(sb, string.rep (" ", indent)) -- indent it
      if type(value) == "table" and not done[value] then
        done[value] = true
        table.insert(sb, string.format("%s = {\n", simple_repr(key)));
        table.insert(sb, table_print (value, indent + 2, done))
        table.insert(sb, string.rep (" ", indent)) -- indent it
        table.insert(sb, "}\n");
      elseif type(key) == "number" then
        table.insert(sb, string.format("%s\n", simple_repr(value)))
      else
        table.insert(sb, string.format(
                       "%s = %s\n", simple_repr(key), simple_repr(value)))
       end
    end
    return table.concat(sb)
  else
    return tt .. "\n"
  end
end

local function to_string(tbl)
  local t = type(tbl)
  if t == "nil"  then
    return tostring(nil)
  elseif t == "table" then
    return table_print(tbl)
  elseif t == "string" then
    return string.format("%q", tbl)
  else
    return tostring(tbl)
  end
end

lib.s.to_string = to_string

function lib:print(msg)
  if msg then
    if lib.icon then
      print(string.format("|T%s:0|t%s", lib.icon, msg))
    else
      print(msg)
    end
  end
end

function lib:printf(msg, ...)
  local s = string.format(msg, ...)
  lib:print(s)
end

function lib:debug(msg)
  if msg and lib.debug then
    lib:print("DEBUG: " .. tostring(msg))
  end
end

function lib:debugf(msg, ...)
  local s = string.format(msg, ...)
  lib:debug(s)
end

function lib:dump(v)
  local s = lib.s.to_string(v)
  self:print(c"{blue}DUMP")
  for _, line in ipairs({strsplit("\n", s)}) do
    self:print(line)
  end
end


--
-- Player database
--

local DB = object:clone()
lib.DB = DB

function DB:new(save_variable, version)
  local obj = DB:clone()
  obj.save_variable = save_variable
  obj.version = version
  lib:dump(obj)
  obj.update_from_save_variable(obj)
  return obj
end

function DB:update_from_save_variable()
  local self = DB
  lib:dump(self)
  self.db = table_get(_G, self.save_variable, function () return {} end)
  if self.version ~= self.db.version then
    self:upgrade(self.version)
  end
end

function DB.update_to_save_variable(self)
  _G[self.save_variable] = self.db
end

function DB.initialise(self)
  local db = self.db
  if not db.version then
    db.version = self.version
  elseif db.version ~= version then
    self:upgrade(version)
  end
  if not db.realm then
    db.realm = {}
  end
end

function DB.upgrade(self, version)
  self.lib:debugf("can't upgrade database version %s to version %s",
                self.db.version, version)
end

function DB.realm_defaults(self)
  return {}
end

function DB.player_defaults(self)
  return {}
end

function DB.player_db(self, realm, player)
  if not realm then
    realm = GetRealmName()
    player = UnitName("player")
  end
  local realm_db = table_get(self.db.realm, realm, wrap(self).realm_defaults)
  local player_db = table_get(realm_db, player,
                              wrap(self).player_defaults)
  return player_db
end

function DB.realms(self)
  return sorted_keys(self.db.realms)
end

function DB.players_in_realm(self, realm)
  local realm_db = self.db.realm[realm]
  if realm_db then return sorted_keys(realm_db)
  else return {} end
end

function DB.clear_player(self, realm, player)
  local db = self:player_db(realm, player)
  wipe(db)
end

function DB.clear_all(self)
  wipe(self.db.realms)
end

--
-- Events
--

lib.events = object:clone()
lib:extend_clone('events')

function lib.events.register_events(self, frame)
  frame:SetScript("OnEvent", function(f, event, ...)
                               self[event](...)
                             end)
  for event, _ in pairs(self) do
    if event:match("^[A-Z]") then
      frame:RegisterEvent(event)
    end
  end
end


if module then
  dmc = lib
  module("dmc")
end
