--- === hs.windowwatcher ===
---
--- Watches interesting events on interesting windows

hs = require'hs._inject_extensions'
local next,pairs,ipairs=next,pairs,ipairs
local setmetatable=setmetatable
local log = hs.logger.new('wwatcher')
local delayed = hs.delayed
local hsappwatcher,hsapp,hswin=hs.application.watcher,hs.application,hs.window
local hsuiwatcher=hs.uielement.watcher

local isGuiApp = hs.windowfilter.isGuiApp
--TODO allow override of 'root' windowfilter

local watchers={} -- internal list for windowwatchers


local windowwatcher={} -- module and class object
local events={windowCreated=true, windowDestroyed=true, windowMoved=true,
  windowMinimized=true, windowUnminimized=true,
  windowFullscreened=true, windowUnfullscreened=true, --FIXME better names
  --TODO perhaps windowMaximized? (compare win:frame to win:screen:frame)
  windowHidden=true, windowShown=true, windowFocused=true, windowUnfocused=true,
  windowTitleChanged=true,
}
for k in pairs(events) do windowwatcher[k]=k end -- expose events
--- hs.windowwatcher.windowCreated
--- Constant
--- A new window was created

--- hs.windowwatcher.windowDestroyed
--- Constant
--- A window was destroyed

--- hs.windowwatcher.windowMoved
--- Constant
--- A window was moved or resized, including toggling fullscreen/maximize

--- hs.windowwatcher.windowMinimized
--- Constant
--- A window was minimized

--- hs.windowwatcher.windowUnminimized
--- Constant
--- A window was unminimized

--- hs.windowwatcher.windowFullscreened
--- Constant
--- A window was expanded to full screen

--- hs.windowwatcher.windowUnfullscreened
--- Constant
--- A window was reverted back from full screen

--- hs.windowwatcher.windowHidden
--- Constant
--- A window is no longer visible due to it being minimized or its application being hidden (e.g. via cmd-h)

--- hs.windowwatcher.windowShown
--- Constant
--- A window was became visible again after being hidden

--- hs.windowwatcher.windowFocused
--- Constant
--- A window received focus

--- hs.windowwatcher.windowUnfocused
--- Constant
--- A window lost focus

--- hs.windowwatcher.windowTitleChanged
--- Constant
--- A window's title changed

local apps={global={}} -- all GUI apps


local Window={} -- class

function Window:emitEvent(event)
  log.f('Emitting %s %d (%s)',event,self.id,self.app.name)
  for ww in pairs(self.wws) do
    if watchers[ww] then -- skip if wwatcher was stopped
      local fn=ww.events[event]
      if fn then fn(self.window) end
    end
  end
end

function Window:focused()
  if apps.global.focused==self then return log.df('Window %d (%s) already focused',self.id,self.app.name) end
  apps.global.focused=self
  self.app.focused=self
  self:emitEvent(windowwatcher.windowFocused)
end

function Window:unfocused()
  if apps.global.focused~=self then return log.vf('Window %d (%s) already unfocused',self.id,self.app.name) end
  apps.global.focused=nil
  self.app.focused=nil
  self:emitEvent(windowwatcher.windowUnfocused)
end

function Window:setWWatcher(ww)
  self.wws[ww]=nil --reset in case it's now filtered after title change
  if ww.windowfilter:isWindowAllowed(self.window,self.app.name) then
    self.wws[ww]=true
  end
end

function Window.new(win,id,app,watcher)
  local o = setmetatable({app=app,window=win,id=id,watcher=watcher,wws={}},{__index=Window})
  if not win:isVisible() then o.isHidden = true end
  if win:isMinimized() then o.isMinimized = true end
  o.isFullscreen = win:isFullScreen()
  app.windows[id]=o
  for ww,active in pairs(watchers) do
    if active then o:setWWatcher(ww) end
  end
  o:emitEvent(windowwatcher.windowCreated)
end

function Window:destroyed()
  delayed.cancel(self.movedDelayed)
  delayed.cancel(self.titleDelayed)
  self.watcher:stop()
  self.app.windows[self.id]=nil
  self:unfocused()
  self:emitEvent(windowwatcher.windowDestroyed)
end
local WINDOWMOVED_DELAY=0.5
function Window:moved()
  self.movedDelayed=delayed.doAfter(self.movedDelayed,WINDOWMOVED_DELAY,Window.doMoved,self)
end

function Window:doMoved()
  self:emitEvent(windowwatcher.windowMoved)
  local fs = self.window:isFullScreen()
  local oldfs = self.isFullscreen or false
  if self.isFullscreen~=fs then
    self:emitEvent(fs and windowwatcher.windowFullscreened or windowwatcher.windowUnfullscreened)
    self.isFullscreen=fs
  end
end
local TITLECHANGED_DELAY=0.5
function Window:titleChanged()
  self.titleDelayed=delayed.doAfter(self.titleDelayed,TITLECHANGED_DELAY,Window.doTitleChanged,self)
end
function Window:doTitleChanged()
  for ww in pairs(watchers) do
    self:setWWatcher(ww) -- recheck the filter for all watchers
  end
  self:emitEvent(windowwatcher.windowTitleChanged)
end
function Window:hidden()
  if self.isHidden then return log.df('Window %d (%s) already hidden',self.id,self.app.name) end
  self:unfocused()
  self.isHidden = true
  self:emitEvent(windowwatcher.windowHidden)
end
function Window:shown()
  if not self.isHidden then return log.df('Window %d (%s) already shown',self.id,self.app.name) end
  self.isHidden = nil
  self:emitEvent(windowwatcher.windowShown)
  --  if hswin.focusedWindow():id()==self.id then self:focused() end
end
function Window:minimized()
  if self.isMinimized then return log.df('Window %d (%s) already minimized',self.id,self.app.name) end
  self.isMinimized=true
  self:emitEvent(windowwatcher.windowMinimized)
  self:hidden()
end
function Window:unminimized()
  if not self.isMinimized then log.df('Window %d (%s) already unminimized',self.id,self.app.name) end
  self.isMinimized=nil
  self:shown()
  self:emitEvent(windowwatcher.windowUnminimized)
end

local appWindowEvent

local App={} -- class

function App:getFocused()
  if self.focused then return end
  local fw=self.app:focusedWindow()
  local fwid=fw and fw.id and fw:id()
  if not fwid then
    fw=self.app:mainWindow()
    fwid=fw and fw.id and fw:id()
  end
  if fwid then
    log.vf('Window %d is focused for app %s',fwid,self.name)
    if not self.windows[fwid] then
      -- windows on a different space aren't picked up by :allWindows()
      log.df('Focused window %d (%s) was not registered',fwid,self.name)
      appWindowEvent(fw,hsuiwatcher.windowCreated,nil,self.name)
    end
    if not self.windows[fwid] then
      log.wf('Focused window %d (%s) is STILL not registered',fwid,self.name)
    else
      self.focused = self.windows[fwid]
    end
  end
end

function App.new(app,appname,watcher)
  local o = setmetatable({app=app,name=appname,watcher=watcher,windows={}},{__index=App})
  if app:isHidden() then o.isHidden=true end
  local windows=app:allWindows()
  --FIXME is there a way to get windows in different spaces? focusedWindow() doesn't have a problem with that
  log.f('New app %s (%d windows) registered',appname,#windows)
  apps[appname] = o
  for _,win in ipairs(windows) do
    appWindowEvent(win,hsuiwatcher.windowCreated,nil,appname)
  end
  o:getFocused()
  if app:isFrontmost() then
    log.df('App %s is the frontmost app',appname)
    if apps.global.active then apps.global.active:deactivated() end
    apps.global.active = o
    if o.focused then
      o.focused:focused()
      log.df('Window %d is the focused window',o.focused.id)
      --      apps.global.focused=o.focused
    end
  end
  return o
end

function App:activated()
  local prevactive=apps.global.active
  if self==prevactive then return log.df('App %s already active; skipping',self.name) end
  if prevactive then prevactive:deactivated() end
  log.vf('App %s activated',self.name)
  apps.global.active=self
  self:getFocused()
  if not self.focused then return log.df('App %s does not (yet) have a focused window',self.name) end
  self.focused:focused()
end
function App:deactivated()
  if self~=apps.global.active then return end
  log.vf('App %s deactivated',self.name)
  apps.global.active=nil
  if apps.global.focused~=self.focused then log.e('Focused app/window inconsistency') end
  --  if not self.focused then return log.ef('App %s does not have a focused window',self.name) end
  if self.focused then self.focused:unfocused() end
end
function App:focusChanged(id,win)
  if not id then return log.wf('Cannot process focus changed for app %s - no window id',self.name) end
  if self.focused and self.focused.id==id then return log.df('Window %d (%s) already focused, skipping',id,self.name) end
  local active=apps.global.active
  if not self.windows[id] then
    appWindowEvent(win,hsuiwatcher.windowCreated,nil,self.name)
  end
  log.vf('App %s focus changed',self.name)
  if self==active then self:deactivated() end
  self.focused = self.windows[id]
  if self==active then self:activated() end
end
function App:hidden()
  if self.isHidden then return log.df('App %s already hidden, skipping',self.name) end
  for id,window in pairs(self.windows) do
    window:hidden()
  end
  log.vf('App %s hidden',self.name)
  self.isHidden=true
end
function App:shown()
  if not self.isHidden then return log.df('App %s already visible, skipping',self.name) end
  for id,window in pairs(self.windows) do
    window:shown()
  end
  log.vf('App %s shown',self.name)
  self.isHidden=nil
end
function App:destroyed()
  log.f('App %s deregistered',self.name)
  self.watcher:stop()
  for id,window in pairs(self.windows) do
    window:destroyed()
    --    window.watcher:stop()
  end
end

local function windowEvent(win,event,_,appname,retry)
  log.vf('Received %s for %s',event,appname)
  local id=win and win.id and win:id()
  local app=apps[appname]
  if not id and app then
    for _,window in pairs(app.windows) do
      if window.window==win then id=window.id break end
    end
  end
  if not id then return log.ef('%s: %s cannot be processed',appname,event) end
  if not app then return log.ef('App %s is not registered!',appname) end
  local window = app.windows[id]
  if not window then return log.ef('Window %d (%s) is not registered!',id,appname) end
  if event==hsuiwatcher.elementDestroyed then
    window:destroyed()
  elseif event==hsuiwatcher.windowMoved or event==hsuiwatcher.windowResized then
    window:moved()
  elseif event==hsuiwatcher.windowMinimized then
    window:minimized()
  elseif event==hsuiwatcher.windowUnminimized then
    window:unminimized()
  elseif event==hsuiwatcher.titleChanged then
    window:titleChanged()
  end
end
local RETRY_DELAY,MAX_RETRIES = 0.2,3
local windowWatcherDelayed={}


appWindowEvent=function(win,event,_,appname,retry)
  log.vf('Received %s for %s',event,appname)
  local id = win and win.id and win:id()
  if event==hsuiwatcher.windowCreated then
    retry=(retry or 0)+1
    --    if retry>5 then return log.wf('%s: %s cannot be processed',appname,) end
    if not id then
      --      log.df('%s: window has no id%s',appname,retry>5 and ', giving up' or '')
      --      log.df('%s: %s has no id%s',appname,win.subrole and win:subrole() or (win.role and win:role()),retry>MAX_RETRIES and ', giving up' or'')
      if retry>MAX_RETRIES then log.df('%s: %s has no id',appname,win.subrole and win:subrole() or (win.role and win:role()) or 'window') end
      if retry<=MAX_RETRIES then windowWatcherDelayed[win]=delayed.doAfter(windowWatcherDelayed[win],retry*RETRY_DELAY,appWindowEvent,win,event,_,appname,retry) end
      return
    end
    if apps[appname].windows[id] then return log.df('%s: window %d already registered',appname,id) end
    local watcher=win:newWatcher(windowEvent,appname)
    if not watcher._element.pid then
      --      log.df('%s: %s has no watcher pid%s',appname,win.subrole and win:subrole() or (win.role and win:role()),retry>MAX_RETRIES and ', giving up' or'')
      if retry>MAX_RETRIES then log.df('%s: %s has no watcher pid',appname,win.subrole and win:subrole() or (win.role and win:role()) or 'window') end
      if retry<=MAX_RETRIES then windowWatcherDelayed[win]=delayed.doAfter(windowWatcherDelayed[win],retry*RETRY_DELAY,appWindowEvent,win,event,_,appname,retry) end
      return
    end
    delayed.cancel(windowWatcherDelayed[win]) windowWatcherDelayed[win]=nil
    Window.new(win,id,apps[appname],watcher)
    watcher:start({hsuiwatcher.elementDestroyed,hsuiwatcher.windowMoved,hsuiwatcher.windowResized
      ,hsuiwatcher.windowMinimized,hsuiwatcher.windowUnminimized,hsuiwatcher.titleChanged})
  elseif event==hsuiwatcher.focusedWindowChanged then
    local app=apps[appname]
    if not app then return log.ef('App %s is not registered!',appname) end
    app:focusChanged(id,win)
  end
end
local appWatcherDelayed={}

local function startAppWatcher(app,appname,retry)
  if not app or not appname then log.e('Called startAppWatcher with no app') return end
  if apps[appname] then log.df('App %s already registered',appname) return end
  if app:kind()<0 or not isGuiApp(appname) then log.df('App %s has no GUI',appname) return end
  local watcher = app:newWatcher(appWindowEvent,appname)
  if watcher._element.pid then
    watcher:start({hsuiwatcher.windowCreated,hsuiwatcher.focusedWindowChanged})
    App.new(app,appname,watcher)
  else
    retry=(retry or 0)+1
    if retry>5 then return log.wf('STILL no accessibility pid for app %s, giving up',(appname or '[???]')) end
    log.df('No accessibility pid for app %s',(appname or '[???]'))
    appWatcherDelayed[appname]=delayed.doAfter(appWatcherDelayed[appname],0.2*retry,startAppWatcher,app,appname,retry)

  end
end

local function appEvent(appname,event,app,retry)
  local sevent={[0]='launching','launched','terminated','hidden','unhidden','activated','deactivated'}
  log.vf('Received app %s for %s',sevent[event],appname)
  if event==hsappwatcher.launched then return startAppWatcher(app,appname) end
  local appo=apps[appname]
  if event==hsappwatcher.activated then
    if appo then return appo:activated() end
    retry = (retry or 0)+1
    if retry==1 then
      log.df('First attempt at registering app %s',appname)
      startAppWatcher(app,appname,5)
    end
    if retry>5 then return log.ef('App %s still is not registered!',appname) end
    return delayed.doAfter(0.1*retry,appEvent,appname,event,_,retry)
  end
  if not appo then return log.ef('App %s is not registered!',appname) end
  if event==hsappwatcher.terminated then return appo:destroyed()
  elseif event==hsappwatcher.deactivated then return apps[appname]:deactivated()
  elseif event==hsappwatcher.hidden then return apps[appname]:hidden()
  elseif event==hsappwatcher.unhidden then return apps[appname]:shown() end
end

local function startGlobalWatcher()
  if apps.global.watcher then return end
  --if not next(watchers) then return end --safety
  --  if not next(events) then return end
  apps.global.watcher = hsappwatcher.new(appEvent)
  local runningApps = hsapp.runningApplications()
  log.f('Registering %d running apps',#runningApps)
  for _,app in ipairs(runningApps) do
    startAppWatcher(app,app:title())
  end
  apps.global.watcher:start()
end

local function stopGlobalWatcher()
  if not apps.global.watcher then return end
  for _,active in pairs(watchers) do
    if active then return end
  end
  local totalApps = 0
  for _,app in pairs(apps) do
    for _,window in pairs(app.windows) do
      window.watcher:stop()
    end
    app.watcher:stop()
    totalApps=totalApps+1
  end
  apps.global.watcher:stop()
  apps={global={}}
  log.f('Unregistered %d apps',totalApps)
end

local function subscribe(self,event,fn)
  if not events[event] then error('invalid event: '..event,2) end
  if type(fn)~='function' then error('fn must be a function',2)end
  self.events[event]=fn
  return self
end
local function unsubscribe(self,event)
  if not events[event] then error('invalid event: '..event,2) end
  self.events[event]=nil
  --  if not next(self.events) then return self:unsubscribeAll() end
  return self
end

function windowwatcher:getWindows()
  local t={}
  for appname,app in pairs(apps) do
    if appname~='global' then
      for _,window in pairs(app.windows) do
        for ww in pairs(window.wws) do
          if ww==self then t[#t+1]=window.window end
        end
      end
    end
  end
  return t
end

--- hs.windowwatcher:subscribe(event,tn)
--- Method
--- Subscribes to one or more events
---
--- Parameters:
---  * event - string or table of strings, the event(s) to subscribe to (see the `hs.windowwatcher` constants)
--   * fn - the callback for the event(s); it should accept as parameter a `hs.window` object referring to the event's window
---
--- Returns:
---  * the `hs.windowwatcher` object for method chaining
function windowwatcher:subscribe(event,fn)
  if type(event)=='string' then return subscribe(self,event,fn)
  elseif type(event)=='table' then
    for _,e in ipairs(event) do
      subscribe(self,e,fn)
    end
    return self
  else error('event must be a string or a table of strings',2) end
end

--- hs.windowwatcher:unsubscribe(event)
--- Method
--- Removes all subscriptions
---
--- Parameters:
---  * event - string or table of strings, the event(s) to unsubscribe
---
--- Returns:
---  * the `hs.windowwatcher` object for method chaining
function windowwatcher:unsubscribe(event)
  if type(event)=='string' then return unsubscribe(self,event)
  elseif type(event)=='table' then
    for _,e in ipairs(event) do
      unsubscribe(self,event)
    end
    return self
  else error('event must be a string or a table of strings',2) end
end

--- hs.windowwatcher:unsubscribeAll() -> hs.windowwatcher
--- Method
--- Removes all subscriptions
---
--- Returns:
---  * the `hs.windowwatcher` object for method chaining
function windowwatcher:unsubscribeAll()
  self.events={}
  return self
end


local function filterWindows(self)
  for appname,app in pairs(apps) do
    if appname~='global' then
      for _,window in pairs(app.windows) do
        window:setWWatcher(self)
      end
    end
  end
end

--- hs.windowwatcher:start()
--- Method
--- Starts the windowwatcher; after calling this, all subscribed events will trigger their callback
function windowwatcher:start()
  if watchers[self]==true then log.i('windowwatcher was already started, ignoring') return end
  startGlobalWatcher()
  watchers[self]=true
  filterWindows(self)
end

--- hs.windowwatcher:stop()
--- Method
--- Stops the windowwatcher; no more event callbacks will be triggered, but the subscriptions remain intact for a subsequent call to `hs.windowwatcher:start()`
function windowwatcher:stop()
  watchers[self]=nil
  stopGlobalWatcher()
end

--- hs.windowwatcher.new(windowfilter) -> hs.windowwatcher
--- Function
--- Creates a new windowwatcher instance
---
--- Parameters:
---  * windowfilter - (optional) a `hs.windowfilter` object to only receive events about specific windows; if omitted `hs.windowfilter.default` will be used
---
--- Returns:
---  * a new windowwatcher instance

function windowwatcher.new(windowfilter)
  local o = setmetatable({events={},windowfilter=windowfilter or hs.windowfilter.default},{__index=windowwatcher})
  return o
end

windowwatcher.setLogLevel=log.setLogLevel
return windowwatcher
