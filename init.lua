-- clear the buffer on every restart
ngx.shared.log_buffer:flush_all()
ngx.shared.log_timer:flush_all()

function script_path()
   local str = debug.getinfo(2, "S").source:sub(2)
   return str:match("(.*/)")
end

package.path = script_path() .. '?.lua;' .. package.path
local inifile = require 'inifile'

-- read the config file, save it
-- inifile module from http://santos.nfshost.com/inifile.html
-- https://github.com/hahawoo/love-misc-libs/blob/master/inifile/inifile.lua
--local inifile = assert(loadfile(script_path() .. 'inifile.lua'), "Can't load inifile.lua")
log_settings = assert(inifile.parse(script_path() .. "logging.ini"), "Can't find logging configuration")

make_handler = assert(loadfile(script_path() .. 'functions.lua'), "Can't load functions.lua")
