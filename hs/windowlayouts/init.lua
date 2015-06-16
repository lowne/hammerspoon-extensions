--- === hs.windowlayouts ===
---
--- Save and restore window layouts; and automatically keep track and apply layouts across different screen configurations

-- FIXME test non-auto mode

--TODO constructors with a list of allowed appnames all the way down (watcher,filter)

local next,ipairs,pairs,tinsert,tsort,ssub,time,sformat=next,ipairs,pairs,table.insert,table.sort,string.sub,os.time,string.format
local windowwatcher=require'hs.windowwatcher'
local screenwatcher=require'hs.screenwatcher'
local settings=require'hs.settings'
local doAfter=require'hs.delayed'.doAfter
local log = require'hs.logger'.new('wlayouts')

local windowlayouts = {} -- class and module
windowlayouts.setLogLevel=function(lvl) log.setLogLevel(lvl)end

local instances = {} -- started/running instances

local KEY_LAYOUTS = 'windowlayouts.automode'

local function sortedinsert(t,elem,comp)
  local i = 1
  local next = t[i]
  while not comp(elem,next) do
    i = i+1
    next = t[i]
  end
  tinsert(t,i,elem)
  return i
end


local function windowcomp(w1,w2)
  if not w2 then return true end
  local diff = w1.time-w2.time
  if diff>5 or diff<-5 then return w1.time<w2.time end
  return (w1.id or 0)<(w2.id or 0)
end


function windowlayouts:actualSave()
  if self.duringAutolayout then self.saveDelayed=doAfter(self.saveDelayed,5,windowlayouts.actualSave,self)
  else
    log.i('automode layout saved')
    settings.set(KEY_LAYOUTS, self.layouts)
  end
end
function windowlayouts:saveSettings()
  self.saveDelayed=doAfter(self.saveDelayed,1,windowlayouts.actualSave,self)
end

local function frameEqual(frame,savedwin)
  return frame.x==savedwin.x and frame.y==savedwin.y and frame.w==savedwin.w and frame.h==savedwin.h
end

function windowlayouts:loadSettings()
  log.i('automode layout loaded')
  self.layouts = settings.get(KEY_LAYOUTS) or {}
end




--returns an existing table for the newly created window, or nil if not found
function windowlayouts:findMatchingWindow(appname,win,role,title)
  local frame = win:frame()
  local savedWindows = self.windows[appname]
  local found
  local bestmatch=0.75 -- only similar windows allowed to match
  for i,savedwin in ipairs(savedWindows) do
    if not savedwin.id and role==savedwin.role then
      -- first, search for matching frames
      if frameEqual(frame,savedwin) then
        log.df('frame match for %s [%s]: %s',role,appname,title)
        return savedwin
          -- search for matching (meaningful) title
      elseif #title>2 and title==savedwin.title then
        log.df('title match for %s [%s]: %s',role,appname,title)
        return savedwin
      else
        -- otherwise, match the best fitting window (if reasonably similar in shape/size)
        local area = frame.w*frame.h
        local aspect = frame.w/frame.h
        local sarea = savedwin.w*savedwin.h
        local saspect = savedwin.w/savedwin.h
        local areamatch=area<sarea and area/sarea or sarea/area
        local aspectmatch = aspect<saspect and aspect/saspect or saspect/aspect
        local match=areamatch*aspectmatch
        if match>bestmatch then
          bestmatch = match
          found = savedwin
        end
      end
    end
  end
  if found then
    log.df('shape match for %s [%s]: %s',role,appname,title)
  else
    -- a never-seen-before window! return nil
    log.df('no match for %s [%s]: %s',role,appname,title)
  end
  return found
end


local function getSavedWindow(t,id)
  if not t then return end
  for _,w in ipairs(t) do
    if w.id==id then return w end
  end
end

function windowlayouts:windowMoved(win,appname)
  if instances[self]~=true then return end -- skip when paused
  if self.automode and self.duringAutoLayout then log.v('auto mode layout in progress') return end -- skip during autolayout phase
  local f = win:frame()
  local t = getSavedWindow(self.windows[appname],win:id())
  if not t then log.ef('%s %d (%s) missing!',win:subrole(),win:id(),appname) return end
  t.x=f.x t.y=f.y t.w=f.w t.h=f.h
  log.df('%s (%s) -> %d,%d [%dx%d]',t.role,appname,t.x,t.y,t.w,t.h)
  if self.automode then self:saveSettings() end
end

function windowlayouts:windowShown(win,appname)
  if instances[self]~=true then return end -- skip when paused
  self.windows[appname]=self.windows[appname] or {}
  local role = win:subrole()
  local id = win:id()
  if getSavedWindow(self.windows[appname],id) then
    -- already registered
    log.vf('%s %d (%s) already registered',role,id,appname)
    return
  end
  local title = ssub(win:title(),1,40)
  local matched = self:findMatchingWindow(appname,win,role,title)
  local t = matched or win:frame()
  t.id=id t.role=role t.title=title t.time=time()
  if not matched then
    local i = sortedinsert(self.windows[appname],t,windowcomp)
    log.df('registered %s [%s %d/%d]: %s',role,appname,i,#self.windows[appname],title)
    if self.automode then self:saveSettings() end
  else
    if self.automode then
      win:setFrame(t,0)
      log.df('%s (%s) <= %d,%d [%dx%d]',t.role,appname,t.x,t.y,t.w,t.h)
    else
      -- update with current frame
      log.df('%s (%s) -> %d,%d [%dx%d]',t.role,appname,t.x,t.y,t.w,t.h)
      local f=win:frame()
      t.x=f.x t.y=f.y t.w=f.w t.h=f.h
    end
  end
end

function windowlayouts:windowHidden(win,appname)
  if not self.windows then return end -- FIXME crashes sometimes, but it never should
  local t = getSavedWindow(self.windows[appname],win:id())
  if t then
    log.f('deregistered %s: %s',t.role,t.title)
    t.id = nil
  end
end




local spacesDone = {}
--- hs.windowlayouts.switchedToSpace(space)
--- Function
--- Call this from your `init.lua` when you intercept (e.g. via `hs.hotkey.bind`) a space change
---
--- Parameters:
---  * space - integer, the space number we're switching to
function windowlayouts.switchedToSpace(space)
  if spacesDone[space] then log.v('Switched to space #'..space) return end
  for wl in pairs(instances) do
    wl.duringAutoLayout=true
  end
  windowwatcher.switchedToSpace(space,function()
    log.i('Entered space #'..space..', refreshing all windows')
    for wl in pairs(instances) do
      wl:refreshWindows()
    end
    spacesDone[space] = true
  end)
end

function windowlayouts:removeIDs()
  log.d('remove all IDs')
  for layoutname,layout in pairs(self.layouts) do
    for appname,windows in pairs(layout) do
      for _,w in ipairs(windows) do
        w.id=nil
      end
    end
  end
end


local globalRunning

local screenGeometry

--- hs.windowlayouts:getLayout() -> table, string
--- Method
--- Gets the current window layout
---
--- Returns:
---   * a table containing the current layout for the instance windows; you can save it with `hs.settings.set` for later use
---   * a string describing the current screen geometry; if relevant you can use it as part of the key name when saving with `hs.settings.set`
function windowlayouts:getLayout()
  -- get the current layout snapshot
  self.layouts={} self:refreshWindows()
  return self.windows, screenGeometry
end

--- hs.windowlayouts:applyLayout(layout)
--- Method
--- Applies a previously saved window layout to the current windows
---
--- Parameters:
---  * layouts - a table containing the window layout to apply, as returned by `hs.windowlayout.getLayout`
---
--- Notes:
---  * This won't work for instances that have been started in auto mode
function windowlayouts:applyLayout(layout)
  if self.automode then log.e('Cannot manually apply a layout in auto mode') return end
  if type(layout)~='table' then error('layout must be a table',2) return end

  self.layouts[screenGeometry] = layout
  self:removeIDs()
  self.automode = true
  self:refreshWindows()
  self.automode = nil
end

function windowlayouts:refreshWindows()
  log.i('Refresh windows, apply layout')
  self.duringAutoLayout = true
  self.layouts[screenGeometry] = self.layouts[screenGeometry] or {}
  self.windows = self.layouts[screenGeometry]
  local windows = self.ww:getWindows()
  for _,w in ipairs(windows) do
    self:windowShown(w,w:application():title())
  end
  self.layoutDelayed=doAfter(self.layoutDelayed,5,function()
    self.duringAutoLayout = nil
    log.i('Apply layout finished')
  end)
end

local function enumScreens(screens)
  local function rect2str(rect)
    return sformat('[%d,%d %dx%d]',rect.x,rect.y,rect.w,rect.h)
  end
  screenGeometry = ''
  for _,screen in ipairs(screens) do
    screenGeometry = screenGeometry..rect2str(screen:fullFrame())
  end
  log.f('Enumerated screens: %s',screenGeometry)
  for wl in pairs(instances) do wl:removeIDs() wl:refreshWindows() end
end


local function screensChanged()
  log.d('Screens changed')
  for wl in pairs(instances) do
    wl.duringAutoLayout = true
  end
end


local function startGlobal()
  if globalRunning then return end
  globalRunning = true
  log.i('global start')
  screenwatcher.subscribe(screensChanged,enumScreens)
end

local function stopGlobal()
  if not globalRunning then return end
  if next(instances) then return end
  --  for wl in pairs(instances) do
  --    if wl.active then return end
  --  end
  globalRunning = nil
  log.i('global stop')
  screenwatcher.unsubscribe({enumScreens,screensChanged})
end

--- hs.windowlayouts:start() -> hs.windowlayouts
--- Method
--- Starts an `hs.windowlayouts` instance
---
--- Returns:
---  * the instance, for method chaining
function windowlayouts:start()
  if instances[self] then log.i('instance was already started, ignoring') return end
  startGlobal()
  if not screenGeometry then doAfter(1,windowlayouts.start,self) return self end
  log.i('start')
  self:removeIDs()
  instances[self] = true
  self.ww:start()
  self:refreshWindows()
  return self
end

--- hs.windowlayouts:startAutoMode() -> hs.windowlayouts
--- Method
--- Starts an `hs.windowlayouts` instance in automatic mode.
--- As you move windows around, the window layout is automatically saved internally for the current screen configuration;
--- when screen changes are detected, the appropriate layout is automatically applied to current and future windows.
--- In practice this means that when e.g. you connect your laptop to your triple-monitor setup at your desk,
--- all the windows (including those that will be opened later) will be restored to exactly where they were
---  when you last left your desk - and vice versa.
---
--- Returns:
---  * the instance, for method chaining
function windowlayouts:startAutoMode()
  if instances[self] then log.i('instance was already started, ignoring') return end
  -- only one automode instance allowed
  for wl in pairs(instances) do
    if wl.automode then log.e('only one automode instance is allowed') return end
  end
  log.i('start auto mode')
  self.automode = true
  self:loadSettings()
  self.wwsubs={
    function(w,a)self:windowShown(w,a)end,
    function(w,a)self:windowHidden(w,a)end,
    function(w,a)self:windowMoved(w,a)end
  }
  self.ww:subscribe(windowwatcher.windowShown,self.wwsubs[1])
    :subscribe(windowwatcher.windowHidden,self.wwsubs[2])
    :subscribe(windowwatcher.windowMoved,self.wwsubs[3])
  return self:start()
end

--- hs.windowlayouts:stop() -> hs.windowlayouts
--- Method
--- Stops an `hs.windowlayouts` instance (for cleanup)
---
--- Returns:
---  * the instance, for method chaining
function windowlayouts:stop()
  log.i('stop')
  instances[self] = nil
  self.automode = nil
  self.ww:unsubscribe(self.wwsubs):stop()
  stopGlobal()
  return self
end

--- hs.windowlayouts:pause() -> hs.windowlayouts
--- Method
--- Pauses the instance
---
--- Returns:
---  * the instance, for method chaining

--- hs.windowlayouts:resume() -> hs.windowlayouts
--- Method
--- Resumes the instance
---
--- Returns:
---  * the instance, for method chaining
function windowlayouts:pause() instances[self]=false log.i('autolayout paused')end
function windowlayouts:resume() instances[self]=true log.i('autolayout resumed') self:removeIDs() self:refreshWindows() end

function windowlayouts:resetAll()
  -- useful for testing/debugging
  log.w('Autolayout reset')
  self.layouts = {}
  self:actualSave()
  self:refreshWindows()
end

--- hs.windowlayouts.new(windowwatcher,...) -> hs.windowlayouts
--- Function
--- Creates a new `hs.windowlayouts` instance. It uses an `hs.windowwatcher` object to only affect specific windows
---
--- Parameters:
---  * windowwatcher - if all parameters are nil (as in `mywl=hs.windowlayouts.new()`), the default windowwatcher will be used
---                   - otherwise, it can be an `hs.windowwatcher` object, or an `hs.windowfilter` object that will be used to build the windowwatcher
---                   - if none of the above, all parameters are passed to `hs.windowwatcher.new` to create a new instance
---  * ... - (optional) additional arguments passed to `hs.windowwatcher.new`
---
--- Returns:
---  * a new `hs.windowlayouts` instance
local function allnil(...)
  local n=select('#',...)
  for i=1,n do if select(i,...)~=nil then return end end
  return true
end
windowlayouts.new = function(ww,...)
  local o = setmetatable({layouts={}},{__index=windowlayouts})
  if ww==nil then
    if allnil(...) then
      log.i('new windowlayouts using default windowwatcher')
      o.ww = windowwatcher.default
    end
  elseif type(ww)=='table' and type(ww.getWindows)=='function' then
    log.i('new windowlayouts using a windowwatcher instance')
    o.ww = ww
  end
  if not o.ww then
    log.i('new windowlayouts, creating windowwatcher')
    o.ww = windowwatcher.new(ww,...)
  end
  return o
end

return windowlayouts

