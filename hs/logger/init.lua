--- Simple logger for debug purposes
--@module logger

local date,time = os.date,os.time
local format,sub=string.format,string.sub
local select,print,concat,min=select,print,table.concat,math.min

local          ERROR , WARNING , INFO , DEBUG , VERBOSE  =1,2,3,4,5
local levels={'error','warning','info','debug','verbose'} levels[0]='nothing'
local slevels={{'ERROR',''},{'Warn:',''},{'',''},{'','-- '},{'','    -- '}}
local lastid
local lasttime=0

local fmt={'%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s',}
local lf = function(loglevel,lvl,id,fmt,...)
  if loglevel<lvl then return end
  local ct = time()
  local stime = '        '
  if ct-lasttime>4 or lvl<3 then stime=date('%X') lasttime=ct end
  if id==lastid and lvl>3 then id='          ' else lastid=id end
  print(format('%s %s%s %s'..fmt,stime,slevels[lvl][1],id,slevels[lvl][2],...))
end
local l = function(loglevel,lvl,id,...)
  if loglevel>=lvl then return lf(loglevel,lvl,id,concat(fmt,' ',1,min(select('#',...),#fmt)),...) end
end


local function new(id,loglevel)
  if type(id)~='string' then error('id must be a string',2) end
  id=format('%10s','['..format('%.8s',id)..']')
  local function setLogLevel(lvl)
    if type(lvl)=='string' then
      local i = hs.fnutils.indexOf(levels,string.lower(lvl))
      if i then loglevel = i
      else error('loglevel must be one of '..table.concat(levels,', ',0,#levels),2) end
    elseif type(lvl)=='number' then
      if lvl<0 or lvl>#levels then error('loglevel must be between 0 and '..#levels,2) end
      loglevel=lvl
    else error('loglevel must be a string or a number',2) end
  end
  if not loglevel then loglevel=2 else setLogLevel(loglevel) end

  local r = {
    setLogLevel = setLogLevel,
    e = function(...) return l(loglevel,ERROR,id,...) end,
    w = function(...) return l(loglevel,WARNING,id,...) end,
    i = function(...) return l(loglevel,INFO,id,...) end,
    d = function(...) return l(loglevel,DEBUG,id,...) end,
    v = function(...) return l(loglevel,VERBOSE,id,...) end,

    ef = function(fmt,...) return lf(loglevel,ERROR,id,fmt,...) end,
    wf = function(fmt,...) return lf(loglevel,WARNING,id,fmt,...) end,
    f = function(fmt,...) return lf(loglevel,INFO,id,fmt,...) end,
    df = function(fmt,...) return lf(loglevel,DEBUG,id,fmt,...) end,
    vf = function(fmt,...) return lf(loglevel,VERBOSE,id,fmt,...) end,
  }
  r.log=r.i r.logf=r.f
  return r
end
return {new=new}

--- Logger instance
--@type log

--- Log an error
-- @function [parent=#log] e
-- @param ...

--- Log a warning
-- @function [parent=#log] w
-- @param ...

--- Log info
-- @function [parent=#log] i
-- @param ...

--- Log debug info
-- @function [parent=#log] d
-- @param ...

--- Log verbose info
-- @function [parent=#log] v
-- @param ...

--- Log a formatted error
-- @function [parent=#log] ef
-- @param #string fmt as per string.format
-- @param ... args to fmt

--- Log a formatted warning
-- @function [parent=#log] wf
-- @param #string fmt as per string.format
-- @param ... args to fmt

--- Log formatted info
-- @function [parent=#log] f
-- @param #string fmt as per string.format
-- @param ... args to fmt

--- Log formatted debug info
-- @function [parent=#log] df
-- @param #string fmt as per string.format
-- @param ... args to fmt

--- Log formatted verbose info
-- @function [parent=#log] vf
-- @param #string fmt as per string.format
-- @param ... args to fmt

---@function [parent=#logger] new
--@param #string id id of the logger instance (usually the module name)
--@param #string loglevel
--@return #log a new logger instance

