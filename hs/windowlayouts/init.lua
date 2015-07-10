--- === hs.windowlayouts ===
---
--- Save and restore window layouts; and automatically keep track and apply layouts across different screen configurations

-- FIXME test non-auto mode

--TODO constructors with a list of allowed appnames all the way down (watcher,filter)
--TODO wlayouts should therefore remember and deal with fullscreen windows

local next,ipairs,pairs,type,tinsert,tsort,ssub,sbyte,time,sformat=next,ipairs,pairs,type,table.insert,table.sort,string.sub,string.byte,os.time,string.format
local windowfilter=require'hs.windowfilter'
local screen=require'hs.screen'
local settings=require'hs.settings'
local timer=require'hs.timer'
--local doAfter=require'hs.delayed'.doAfter
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
local function idcomp(a,b)
  if not b then return true
  else return (a.id or -1)<(b.id or -1) end
end

local function windowcomp(w1,w2)
  if not w2 then return true end
  local diff = w1.time-w2.time
  if diff>5 or diff<-5 then return w1.time<w2.time end
  return (w1.id or 0)<(w2.id or 0)
end

local screenGeometry

local function actualSave(self)
  if self.saveDelayed then self.saveDelayed:stop() self.saveDelayed=nil end
  if self.duringAutolayout then
    self.saveDelayed=timer.doAfter(5,function()actualSave(self)end)
  else
    self.layouts[screenGeometry] = self.windows
    settings.set(KEY_LAYOUTS, self.layouts)
    log.i('automode layout saved')
  end
end
local function saveSettings(self)
  if not self.automode then return end
  if self.saveDelayed then self.saveDelayed:stop() self.saveDelayed=nil end
  self.saveDelayed=timer.doAfter(1,function()actualSave(self) end)
end

local function frameEqual(frame,savedwin)
  return frame.x==savedwin.x and frame.y==savedwin.y and frame.w==savedwin.w and frame.h==savedwin.h
end

local function loadSettings(self)
  log.i('automode layout loaded')
  self.layouts = settings.get(KEY_LAYOUTS) or {}
end


local MATCHFRAME,MATCHTITLE,MATCHSHAPE,MATCHANY=1,2,3,4

local function findMatchingWindow(self,appname,role,frame,title,pass)
  local allwins,wins = self.windows[appname] or {},{}
  for _, w in ipairs(allwins) do
    if not w.id and role==w.role then wins[#wins+1]=w end
  end
  if #wins==0 then return end-- no candidates
  --    log.df('no match for %s [%s]: %s',role,appname,title) return
  --  end
  if pass==MATCHFRAME or not pass then
    for i,sw in ipairs(wins) do
      if frameEqual(frame,sw) then
        log.df('frame match (%d/%d) for %s [%s]: %s',i,#allwins,role,appname,title)
        return sw
      end
    end
  end
  if pass==MATCHTITLE or not pass then
    if #title>1 then
      for i,sw in ipairs(wins) do
        if title==sw.title then
          log.df('title match (%d/%d) for %s [%s]: %s',i,#allwins,role,appname,title)
          return sw
        end
      end
    end
  end
  if pass==MATCHSHAPE or not pass then
    local bestmatch,ifound,found=0.75
    for i,sw in ipairs(wins) do
      local area = frame.w*frame.h
      local aspect = frame.w/frame.h
      local sarea = sw.w*sw.h
      local saspect = sw.w/sw.h
      local areamatch=area<sarea and area/sarea or sarea/area
      local aspectmatch = aspect<saspect and aspect/saspect or saspect/aspect
      local match=areamatch*aspectmatch
      if match>bestmatch then
        bestmatch=match
        found=sw ifound=i
      end
    end
    if found then
      log.df('shape match (%d/%d) for %s [%s]: %s',ifound,#allwins,role,appname,title)
      return found
    end
  end
  if pass==MATCHANY or not pass then
    -- return the first of the remaining candidates
    log.df('last match (%d/%d) for %s [%s]: %s',1,#allwins,role,appname,title)
    return wins[1]
  end
end
--[[
function windowlayouts:findMatchingWindow(appname,win,role,title)
  local allwins,wins = self.windows[appname],{}
  for _,w in ipairs(allwins) do
    if not w.id and role==w.role then wins[#wins+1]=w end
  end
  if #wins==0 then
    -- no candidates
    log.df('no match for %s [%s]: %s',role,appname,title)
    return
  end
  local frame=win:frame()
  -- first, search for matching frames
  for i,sw in ipairs(wins) do
    if frameEqual(frame,sw) then
      log.df('frame match (%d/%d) for %s [%s]: %s',i,#allwins,role,appname,title)
      return sw
    end
  end
  -- search for matching title
  if #title>1 then
    for i,sw in ipairs(wins) do
      if title==sw.title then
        log.df('title match (%d/%d) for %s [%s]: %s',i,#allwins,role,appname,title)
        return sw
      end
    end
  end
  -- match best fitting window (if reasonably similar in shape/size)
  local bestmatch,ifound,found=0.75
  for i,sw in ipairs(wins) do
    local area = frame.w*frame.h
    local aspect = frame.w/frame.h
    local sarea = sw.w*sw.h
    local saspect = sw.w/sw.h
    local areamatch=area<sarea and area/sarea or sarea/area
    local aspectmatch = aspect<saspect and aspect/saspect or saspect/aspect
    local match=areamatch*aspectmatch
    if match>bestmatch then
      bestmatch=match
      found=sw ifound=i
    end
  end
  if found then
    log.df('shape match (%d/%d) for %s [%s]: %s',ifound,#allwins,role,appname,title)
    return found
  end
  -- return the first of the remaining candidates
  log.df('last match (%d/%d) for %s [%s]: %s',1,#allwins,role,appname,title)
  return wins[1]
end

--returns an existing table for the newly created window, or nil if not found
function windowlayouts:OLDfindMatchingWindow(appname,win,role,title,pass)
  local frame = win:frame()
  local savedWindows = self.windows[appname]
  local found
  local bestmatch=0.75 -- only similar windows allowed to match
  for i,savedwin in ipairs(savedWindows) do
    if not savedwin.id and role==savedwin.role then
      -- first, search for matching frames
      if pass==1 and frameEqual(frame,savedwin) then
        log.df('frame match for %s [%s]: %s',role,appname,title)
        return savedwin
          -- search for matching (meaningful) title
      elseif pass==2 and #title>2 and title==savedwin.title then
        log.df('title match for %s [%s]: %s',role,appname,title)
        return savedwin
      elseif pass==3 then
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
      elseif pass==4 then
        -- match anything that remains
        return savedwin
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
--]]
local function getSavedWindowNoApp(t,id)
  for _,windows in pairs(t) do
    for _,w in ipairs(windows) do
      if w.id==id then return w end
    end
  end
end

local function getSavedWindow(t,id)
  --  if not t then return end
  for _,w in ipairs(t) do
    if w.id==id then return w end
  end
end

function windowlayouts:windowMoved(win,appname)
  if not appname then return end
  if instances[self]~=true then return end -- skip when paused
  if self.automode and self.duringAutoLayout then log.v('auto mode layout in progress') return end -- skip during autolayout phase
  local f = win:frame()
  local t = getSavedWindow(self.windows[appname],win:id())
  if not t then log.ef('%s %d (%s) missing!',win:subrole(),win:id(),appname) return end
  t.x=f.x t.y=f.y t.w=f.w t.h=f.h
  log.f('%s (%s) -> %d,%d [%dx%d]',t.role,appname,t.x,t.y,t.w,t.h)
  saveSettings(self)
end
local function getTitle(win)
  local title = ssub(win:title(),1,40)
  if #title==0 then title=' '
  else
    while (sbyte(title,#title))>127 do
      title=ssub(title,1,#title-1)
      if #title==0 then title=' ' end
    end
  end
  return title
end
function windowlayouts:windowShown(win,appname)
  if not appname then log.d('Window shown, no appname') return end
  if instances[self]~=true then return end -- skip when paused
  self.windows[appname]=self.windows[appname] or {}
  local role = win:subrole()
  local id = win:id()
  if not self.duringAutoLayout and getSavedWindow(self.windows[appname],id) then
    -- already registered
    log.vf('%s %d (%s) already registered',role,id,appname)
    return
  end
  local title = getTitle(win)
  --  local matched = self:findMatchingWindow(appname,win,role,title,not self.duringAutoLayout)
  local frame=win:frame()
  local matched = findMatchingWindow(self,appname,role,frame,title)
  local t = matched or frame
  t.id=id t.role=role t.title=title
  if not matched then
    local i = sortedinsert(self.windows[appname],t,idcomp)
    log.f('registered %s [%s %d/%d]: %s',role,appname,i,#self.windows[appname],title)
    saveSettings(self)
  else
    if self.automode or self.duringAutoLayout then
      if not frameEqual(frame,t) then
        win:setFrame(t,0)
        log.f('%s (%s) <= %d,%d [%dx%d]',t.role,appname,t.x,t.y,t.w,t.h)
      end
    else
      print('------------- NEVAH!')
      -- update with current frame
      log.df('%s (%s) -> %d,%d [%dx%d]',t.role,appname,t.x,t.y,t.w,t.h)
      local f=win:frame()
      t.x=f.x t.y=f.y t.w=f.w t.h=f.h
    end
  end
end

function windowlayouts:windowHidden(win,appname)
  --  if not appname then return end
  --  if not self.windows then return end -- FIXME crashes sometimes, but it never should
  local t = appname and getSavedWindow(self.windows[appname],win:id()) or getSavedWindowNoApp(self.windows,win:id())
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
  windowfilter.switchedToSpace(space,function()
    log.i('Entered space #'..space..', refreshing all windows')
    for wl in pairs(instances) do
      wl:refreshWindows()
    end
    spacesDone[space] = true
  end)
end

--[[
function windowlayouts:removeIDs()
  log.d('remove all IDs')
  --  for layoutname,layout in pairs(self.layouts) do
  --    for appname,windows in pairs(layout) do
  for appname,windows in pairs(self.windows) do
    for _,w in ipairs(windows) do
      w.id=nil
    end
  end
  --  end
end
--]]


local function getLayout(self)
  self.windows = {}
  local windows = self.wf:getWindows()
  for _,w in ipairs(windows) do
    local appname=w:application():title()
    if appname then
      if not self.windows[appname] then self.windows[appname]={} end
      local t=w:frame()
      t.title=getTitle(w) t.role=w:subrole() t.id=w:id() or -1
      sortedinsert(self.windows[appname],t,idcomp)
    end
  end
end

--- hs.windowlayouts:getLayout() -> table, string
--- Method
--- Gets the current window layout
---
--- Returns:
---   * a table containing the current layout for the instance windows; you can save it with `hs.settings.set` for later use
---   * a string describing the current screen geometry; if relevant you can use it as part of the key name when saving with `hs.settings.set`
function windowlayouts:getLayout()
  -- get the current layout snapshot
  getLayout(self)
  return self.windows, screenGeometry
end

--- hs.windowlayouts:saveLayout(key)
--- Method
--- Convenience function to save the current window layout via `hs.settings.set`
---
--- Parameters:
---   * key - a string to identify, in conjunction with the current screen geometry, the current screen layout;
--            it can then be used with `hs.windowlayouts:applyLayout`
function windowlayouts:saveLayout(key)
  getLayout(self)
  settings.set(key..screenGeometry,self.windows)
  log.i('layout saved to '..key..screenGeometry)
end

--- hs.windowlayouts:applyLayout(layout)
--- Method
--- Applies a previously saved window layout to the current windows
---
--- Parameters:
---  * layout - it can be:
---              * a table containing the window layout to apply, as returned by `hs.windowlayouts:getLayout`
---              * a string used previously as key with `hs.windowlayouts:saveLayout`
---
--- Notes:
---  * This won't work for instances that have been started in auto mode
local function applyLayout(self,layout)
  --  if layout then self.layouts[screenGeometry] = layout end
  log.f('applying %slayout',self.automode and 'auto' or '')
  self.duringAutoLayout = true
  self.windows = layout or self.layouts[screenGeometry] or {}
  -- remove all ids
  for appname,windows in pairs(self.windows) do
    for _,w in ipairs(windows) do
      w.id=nil
    end
  end
  local windows = self.wf:getWindows()
  local apps = {}
  for _, w in ipairs(windows) do
    local appname = w:application():title()
    if not apps[appname] then apps[appname] = {} end
    tinsert(apps[appname],{role=w:subrole(),title=getTitle(w),frame=w:frame(),id=w:id() or -1,win=w})
  end
  for appname, windows in pairs(apps) do
    for pass=1, MATCHANY do
      for _, w in ipairs(windows) do
        if not w.match then
          local m = findMatchingWindow(self,appname,w.role,w.frame,w.title,pass)
          if m then m.id=w.id w.match=m end
        end
      end
    end
    for _, w in ipairs(windows) do
      local t = w.match or w.frame
      t.id=w.id t.role=w.role t.title=w.title
      if w.match then
        if not frameEqual(w.frame,t) then
          w.win:setFrame(t)
          log.f('%s (%s) <= %d,%d [%dx%d]',t.role,appname,t.x,t.y,t.w,t.h)
        end
      elseif self.automode then
        if not self.windows[appname] then self.windows[appname]={} end
        local i = sortedinsert(self.windows[appname],t,idcomp)
        log.f('registered %s [%s %d/%d]: %s',t.role,appname,i,#self.windows[appname],t.title)
        saveSettings(self)
      end
    end
  end
  log.i('layout applied')
  self.duringAutoLayout = nil
end


function windowlayouts:applyLayout(layout)
  if self.automode then log.e('Cannot manually apply a layout in autolayout mode') return end
  if type(layout)=='string' then
    local key=layout..screenGeometry
    layout=settings.get(key)
    if not layout then log.ef('layout key %s not found',key) return
    else log.f('applying layout from key %s',key) end
  end
  if type(layout)~='table' then error('layout must be a table or a string',2) return end
  return applyLayout(self,layout)
end
--[[
function windowlayouts:refreshWindows()
  log.i('Refresh windows, apply layout')
  self.duringAutoLayout = true
  self.layouts[screenGeometry] = self.layouts[screenGeometry] or {}
  self.windows = self.layouts[screenGeometry]
  local windows = self.wf:getWindows()
  for _,w in ipairs(windows) do
    self:windowShown(w,w:application():title())
  end
  if self.layoutDelayed then self.layoutDelayed:stop() self.layoutDelayed=nil end
  self.layoutDelayed=timer.doAfter(5,function()
    self.layoutDelayed = nil
    self.duringAutoLayout = nil
    log.i('Apply layout finished')
  end)
end
--]]
local screenWatcherDelayed
local function enumScreens()
  local screens = screen.allScreens()
  screenWatcherDelayed = nil
  local function rect2str(rect)
    return sformat('[%d,%d %dx%d]',rect.x,rect.y,rect.w,rect.h)
  end
  screenGeometry = ''
  for _,screen in ipairs(screens) do
    screenGeometry = screenGeometry..rect2str(screen:fullFrame())
  end
  log.f('Enumerated screens: %s',screenGeometry)
  for wl in pairs(instances) do if wl.automode then applyLayout(wl) end end
end


local function screensChanged()
  log.d('Screens changed')
  if screenWatcherDelayed then screenWatcherDelayed:stop() end
  for wl in pairs(instances) do
    if wl.automode then wl.duringAutoLayout = true end
  end
  screenWatcherDelayed=timer.doAfter(3,enumScreens)
end

local screenWatcher=screen.watcher.new(screensChanged)

local globalRunning
local function startGlobal()
  if globalRunning then return end
  globalRunning = true
  log.i('global start')
  screenWatcher:start()
  enumScreens()
end

local function stopGlobal()
  if not globalRunning then return end
  if next(instances) then return end
  --  for wl in pairs(instances) do
  --    if wl.active then return end
  --  end
  globalRunning = nil
  log.i('global stop')
  if screenWatcherDelayed then screenWatcherDelayed:stop() screenWatcherDelayed=nil end
  screenWatcher:stop()
end


--- hs.windowlayouts:delete() -> hs.windowlayouts
--- Method
--- Deletes an `hs.windowlayouts` instance (for cleanup)
function windowlayouts:delete()
  log.i('stop')
  instances[self] = nil
  self.automode = nil
  if self.wfsubs then self.wf:unsubscribe(self.wfsubs) end
  stopGlobal()
end

--- hs.windowlayouts:pause() -> hs.windowlayouts
--- Method
--- Pauses the autolayout mode instance
---
--- Returns:
---  * the `hs.windowlayouts` object, for method chaining
function windowlayouts:pause()
  if self.automode then
    instances[self]=false log.i('autolayout paused')
  end
end

--- hs.windowlayouts:resume() -> hs.windowlayouts
--- Method
--- Resumes the autolayout mode instance
---
--- Returns:
---  * the `hs.windowlayouts` object, for method chaining
function windowlayouts:resume()
  if self.automode then
    instances[self]=true log.i('autolayout resumed') self:removeIDs() self:refreshWindows()
  end
end

function windowlayouts:resetAll()
  -- useful for testing/debugging
  log.w('Autolayout reset')
  self.layouts = {}
  self:actualSave()
  self:refreshWindows()
end

--- hs.windowlayouts.new(windowfilter) -> hs.windowlayouts
--- Function
--- Creates a new `hs.windowlayouts` instance. It uses an `hs.windowfilter` object to only affect specific windows
---
--- Parameters:
---  * windowfilter; it can be:
---    * `nil` (as in `mywl=hs.windowlayouts.new()`): the default windowfilter will be used
---    * an `hs.windowfilter` object
---    * otherwise this parameter is passed to `hs.windowfilter.new` to create a new instance
---
--- Returns:
---  * a new `hs.windowlayouts` instance
local function new(wf)
  local o = setmetatable({layouts={}},{__index=windowlayouts})
  if wf==nil then
    o.wf = windowfilter.default
  elseif type(wf)=='table' and type(wf.getWindows)=='function' then
    log.i('new windowlayouts using a windowfilter instance')
    o.wf = wf
  end
  if not o.wf then
    log.i('new windowlayouts, creating windowfilter')
    o.wf = windowfilter.new(wf)
  end
  --  o.wf:keepActive()
  return o
end

function windowlayouts.new(wf)
  startGlobal()
  local self=new(wf)
  instances[self] = true
  return self
end

--- hs.windowlayouts.autolayout.new(windowfilter) -> hs.windowlayouts
--- Method
--- Creates a new `hs.windowlayouts` instance in autolayout mode. It uses an `hs.windowfilter` object to only affect specific windows.
--- As you move windows around, the window layout is automatically saved internally for the current screen configuration;
--- when screen changes are detected, the appropriate layout is automatically applied to current and future windows.
--- In practice this means that when e.g. you connect your laptop to your triple-monitor setup at your desk,
--- all the watched windows (including those that will be opened later) will be restored to exactly where they were
--- when you last left your desk - and vice versa.
---
--- Parameters:
---  * windowfilter; it can be:
---    * `nil` (as in `mywl=hs.windowlayouts.new()`): the default windowfilter will be used
---    * an `hs.windowfilter` object
---    * otherwise this parameter is passed to `hs.windowfilter.new` to create a new instance
---
--- Returns:
---  * a new `hs.windowlayouts` instance

local function startauto(self)
  if self.automode then log.i('instance was already started, ignoring') return end
  if not screenGeometry then timer.doAfter(1,function()startauto(self)end) return end
  log.i('start auto mode')
  self.automode = true
  loadSettings(self)
  self.wfsubs={
    function(w,a)self:windowShown(w,a)end,
    function(w,a)self:windowHidden(w,a)end,
    function(w,a)self:windowMoved(w,a)end
  }
  self.wf:subscribe(windowfilter.windowShown,self.wfsubs[1])
    :subscribe(windowfilter.windowHidden,self.wfsubs[2])
    :subscribe(windowfilter.windowMoved,self.wfsubs[3])
  instances[self] = true
  applyLayout(self)
end

windowlayouts.autolayout={}
function windowlayouts.autolayout.new(wf)
  startGlobal()
  local self=new(wf)
  startauto(self)
  return self
end
return windowlayouts

