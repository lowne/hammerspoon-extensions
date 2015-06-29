--- === hs.screenwatcher ===
---
--- A singleton hs.screen.watcher (and companion hs.caffeinate.watcher) for multiple consumption


--- hs.screenwatcher.delay
--- Variable
--- The delay in second between callback calls to `fn` and `fnDelayed`; default is 3
local screenwatcher={delay=3}

local swinstance,pwinstance
local substarted,subdone={},{}
local type,next,sformat,pairs,ipairs=type,next,string.format,pairs,ipairs
local allScreens,_doAfter=require'hs.screen'.allScreens,require'hs.timer'.doAfter
local hsscreenwatcher,hspowerwatcher=require'hs.screen.watcher',require'hs.caffeinate.watcher'
local log=require'hs.logger'.new('swatcher')
local function doAfter(prev,delay,fn)
  if prev then prev:stop() end
  return _doAfter(delay,fn)
end

local screensChangedDelayed
local function screensChanged()
  local function sframe(frame)
    return sformat('[%d,%d %dx%d] ',frame.x,frame.y,frame.w,frame.h)
  end
  screensChangedDelayed=nil
  local screens=allScreens()
  local ss='Screen change completed: '
  for _,s in ipairs(screens) do
    ss=ss..sframe(s:fullFrame())
  end
  log.i(ss)
  for fn in pairs(subdone) do
    fn(screens)
  end
end
local function startScreensChanged()
  local screens=allScreens()
  log.i('Screen change detected')
  for fn in pairs(substarted) do
    fn(screens)
  end
  screensChangedDelayed=doAfter(screensChangedDelayed,screenwatcher.delay,screensChanged)
end

local running

local function start()
  if not swinstance then
    swinstance=hsscreenwatcher.new(startScreensChanged)
    swinstance:start()
    pwinstance = hspowerwatcher.new(function(ev)
      if ev==hspowerwatcher.screensDidWake then
        startScreensChanged()
      end
    end)
  end
  log.i('Instance started')
  swinstance:start() pwinstance:start() running=true
end

--- hs.screenwatcher.stop()
--- Function
--- Cleanup
function screenwatcher.stop()
  if screensChangedDelayed then screensChangedDelayed:stop() end
  screensChangedDelayed=nil
  log.i('Instance stopped')
  swinstance:stop() pwinstance:stop() subdone,substarted={},{} swinstance,pwinstance,running=nil
end


--- hs.screenwatcher.subscribe(fn, fndelayed)
--- Function
--- Set a callback function for screen change events
---
--- Parameters:
---  * fn - can be nil; a function that will be called when the attached screens change;
---         it will receive a list of the attached screens (as per `hs.screen.allScreens()`)
---  * fnDelayed - (optional) a function that will be called shortly after the attached screens change;
---                it will receive a list of the attached screens (as per `hs.screen.allScreens()`).
---                Use this if you want to let the system perform its tasks (such as rearranging windows around) before the callback.
---
--- Notes:
---  * the callback(s) will be called once immediately upon subscribing
function screenwatcher.subscribe(fn,fnDelayed)
  if not fn and not fnDelayed then return end
  log.d('Adding subscription')
  if (fn~=nil and type(fn)~='function') or (fnDelayed~=nil and type(fnDelayed)~='function') then error('fn and fnDelayed must be nil or functions',2) end
  if not running then start() end
  if fn then substarted[fn]=true end
  if fnDelayed then subdone[fnDelayed]=true end
  fn(allScreens())
  if not screensChangedDelayed and fnDelayed then fnDelayed(allScreens()) end
end

--- hs.screenwatcher.unsubscribe(fns)
--- Function
--- Unsubscribe one or more callbacks
---
--- Parameters:
---  * fns - function or table of functions to unsubscribe
function screenwatcher.unsubscribe(fns)
  if not fns then return
  elseif type(fns)=='function' then fns={fns}
  elseif type(fns)~='table' then error('fns must be a function or table of functions',2) end
  for _,fn in ipairs(fns) do
    if subdone[fn] or substarted[fn] then
      log.d('Removing subscription')
      subdone[fn]=nil substarted[fn]=nil
    end
  end
  if running and not next(subdone) and not next(substarted) then screenwatcher.stop() end
end

return screenwatcher
