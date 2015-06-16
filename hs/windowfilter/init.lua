--- === hs.windowfilter ===
---
--- Filters windows by application, role, and/or title

-- * This module should fulfill a lot of use cases
-- * The root and default filters should be quite handy for users; however that means ongoing maintenance on the list
--    (how many menulets are out there?)
-- * Maybe an additional filter could be added for window geometry (e.g. minimum width/heigth/area)

hs=require'hs._inject_extensions'
local log=hs.logger.new('wfilter')
local ipairs,type,smatch,sformat = ipairs,type,string.match,string.format

local windowfilter={}
windowfilter.setLogLevel=function(lvl)log.setLogLevel(lvl) return windowfilter end

local SKIP_APPS_NO_PID = {
  --TODO keep this updated (used in the root filter)
  'universalaccessd','sharingd','Safari Networking','iTunes Helper','Safari Web Content',
  'App Store Web Content', 'Safari Database Storage',
  'Google Chrome Helper','Spotify Helper','Karabiner_AXNotifier',
--  'Little Snitch Agent','Little Snitch Network Monitor', -- depends on security settings in Little Snitch
}

local SKIP_APPS_NO_PID_BUNDLE = {
  'com.apple.qtkitserver', -- QTKitServer-(%d) Safari Web Content
}

local SKIP_APPS_NO_WINDOWS = {
  --TODO keep this updated (used in the root filter)
  'com.apple.internetaccounts', 'CoreServicesUIAgent', 'AirPlayUIAgent',
  'SystemUIServer', 'Dock', 'com.apple.dock.extra', 'storeuid',
  'Folder Actions Dispatcher', 'Keychain Circle Notification', 'Wi-Fi',
  'Image Capture Extensions', 'iCloud Photos', 'System Events',
  'Speech Synthesis Server', 'Dropbox Finder Integration', 'LaterAgent',
  'Karabiner_AXNotifier', 'Photos Agent', 'EscrowSecurityAlert',
  'Google Chrome Helper', 'com.apple.MailServiceAgent', 'Safari Web Content',
  'Safari Networking', 'nbagent',
}

local SKIP_APPS_TRANSIENT_WINDOWS = {
  --TODO keep this updated (used in the default filter)
  'Spotlight', 'Notification Center', 'loginwindow', 'ScreenSaverEngine',
  -- preferences etc
  'PopClip','Isolator', 'CheatSheet', 'CornerClickBG', 'Alfred 2', 'Moom', 'CursorSense Manager',
  -- menulets
  'Music Manager', 'Google Drive', 'Dropbox', '1Password mini', 'Colors for Hue', 'MacID',
  'CrashPlan menu bar', 'Flux', 'Jettison', 'Bartender', 'SystemPal', 'BetterSnapTool', 'Grandview', 'Radium',
}

local APPS_ALLOW_NONSTANDARD_WINDOWS = {
  --TODO keep this updated (used in the default filter)
  'iTerm2', --[['Lua Development Tools Product', 'SwitchResX Daemon',]]
}

local APPS_SKIP_NO_TITLE = {
  --TODO keep this updated (used in the default filter)
  'Lua Development Tools Product'
}

local ALLOWED_NONSTANDARD_WINDOW_ROLES = {'AXStandardWindow','AXDialog','AXFloatingWindow','AXSystemDialog'}
local ALLOWED_WINDOW_ROLES = {'AXStandardWindow','AXDialog','AXSystemDialog'}

local wf={} -- class

--- hs.windowfilter:isWindowAllowed(window) -> bool
--- Method
--- Checks if a window is allowed by the windowfilter
---
--- Parameters:
---  * window - a `hs.window` object to check
---
--- Returns:
---  * - `true` if the window is allowed by the windowfilter; `false` otherwise

function wf:isWindowAllowed(window,appname)--appname,windowrole,windowtitle)
  local function matchTitle(titles,t)
    for _,title in ipairs(titles) do
      if smatch(t,title) then return true end
    end
  end
  local function allowWindow(app,role,title,fullscreen,visible)
    if app.titles then
      if type(app.titles)=='number' then if #title<=app.titles then return false end
      elseif not matchTitle(app.titles,title) then return false end
    end
    if app.rtitles and matchTitle(app.rtitles,title) then return false end
    if app.roles and not app.roles[role] then return false end
    if app.fullscreen~=nil and app.fullscreen~=fullscreen then return false end
    if app.visible~=nil and app.visible~=visible then return false end
    return true
  end
  local role = window.subrole and window:subrole() or ''
  local title = window:title() or ''
  local fullscreen = window:isFullScreen() or false
  local visible = window:isVisible() or false
  local app=self.apps[true]
  if app==false then log.vf('%s rejected: override reject',role)return false
  elseif app then
    local r=allowWindow(app,role,title,fullscreen,visible)
    log.vf('%s %s: override filter',role,r and 'allowed' or 'rejected')
    return r
  end
  appname = appname or window:application():title()
  app=self.apps[appname]
  if app==false then log.vf('%s (%s) rejected: app reject',role,appname) return false
  elseif app then
    local r=allowWindow(app,role,title,fullscreen,visible)
    log.vf('%s (%s) %s: app filter',role,appname,r and 'allowed' or 'rejected')
    return r
  end
  app=self.apps[false]
  if app==false then log.vf('%s (%s) rejected: default reject',role,appname) return false
  elseif app then
    local r=allowWindow(app,role,title,fullscreen,visible)
    log.vf('%s (%s) %s: default filter',role,appname,r and 'allowed' or 'rejected')
    return r
  end
  log.vf('%s (%s) accepted (no rules)',role,appname)
  return true
end

--- hs.windowfilter:isAppAllowed(appname) -> bool
--- Method
--- Checks if an app is allowed by the windowfilter
---
--- Parameters:
---  * appname - app name as per `hs.application:title()`
---
--- Returns:
---  * `false` if the app is rejected by the windowfilter; `true` otherwise

function wf:isAppAllowed(appname)
  return self.apps[appname]~=false
end

--- hs.windowfilter:filterWindows(windows) -> table
--- Filters a list of windows
---
--- Parameters:
---  * windows - (optional) a list of `hs.window` objects to filter; if omitted, `hs.window.allWindows()` will be used
---
--- Returns:
---  * a list containing only the windows that were allowed by the windowfilter

function wf:filterWindows(windows)
  if not windows then windows=hs.window.allWindows() end
  local res={}
  for _,w in ipairs(windows) do
    if self:isWindowAllowed(w) then res[#res+1]=w end
  end
  return res
end

--- hs.windowfilter:rejectApp(appname) -> hs.windowfilter
--- Method
--- Sets the windowfilter to outright reject any windows belonging to a specific app
---
--- Parameters:
---  * appname - app name as per `hs.application:title()`
---
--- Returns:
---  * the `hs.windowfilter` object for method chaining

function wf:rejectApp(appname)
  return self:setAppFilter(appname,false)
end

--- hs.window:setDefaultFilter(allowTitles, rejectTitles, allowRoles, fullscreen, visible) -> hs.windowfilter
--- Method
--- Set the default filtering rules to be used for apps without app-specific rules
---
--- Parameters:
---  * allowTitles - if a number, only allow windows whose title is at least as many characters long; e.g. pass `1` to filter windows with an empty title
---                - if a string or table of strings, only allow windows whose title matches (one of) the pattern(s) as per `string.match`
---  * rejectTitles - string or table of strings, reject windwos whose titles matches (one of) the pattern(s) as per `string.match`
---  * allowRoles - string or table of strings, only allow these window roles as per `hs.window:subrole()`
---  * fullscreen - if `true`, only allow fullscreen windows; if `false`, reject fullscreen windows
---  * visible - if `true`, only allow visible windows; if `false`, reject visible windows
---
--- Returns:
---  * the `hs.windowfilter` object for method chaining
---
--- Notes:
---  * if any parameter is `nil` the relevant rule is ignored
function wf:setDefaultFilter(...)
  return self:setAppFilter(false,...)
end
--- hs.window:setOverrideFilter(allowTitles, rejectTitles, allowRoles, fullscreen, visible) -> hs.windowfilter
--- Method
--- Set overriding filtering rules that will be applied for all apps before any app-specific rules
---
--- Parameters:
---  * allowTitles - if a number, only allow windows whose title is at least as many characters long; e.g. pass `1` to filter windows with an empty title
---                - if a string or table of strings, only allow windows whose title matches (one of) the pattern(s) as per `string.match`
---  * rejectTitles - string or table of strings, reject windwos whose titles matches (one of) the pattern(s) as per `string.match`
---  * allowRoles - string or table of strings, only allow these window roles as per `hs.window:subrole()`
---  * fullscreen - if `true`, only allow fullscreen windows; if `false`, reject fullscreen windows
---  * visible - if `true`, only allow visible windows; if `false`, reject visible windows
---
--- Returns:
---  * the `hs.windowfilter` object for method chaining
---
--- Notes:
---  * if any parameter is `nil` the relevant rule is ignored
function wf:setOverrideFilter(...)
  return self:setAppFilter(true,...)
end

--- hs.window:setAppFilter(appname, allowTitles, rejectTitles, allowRoles, fullscreen, visible) -> hs.windowfilter
--- Method
--- Sets the filtering rules for the windows of a specific app
---
--- Parameters:
---  * appname - app name as per `hs.application:title()`
---  * allowTitles - if a number, only allow windows whose title is at least as many characters long; e.g. pass `1` to filter windows with an empty title
---                - if a string or table of strings, only allow windows whose title matches (one of) the pattern(s) as per `string.match`
---  * rejectTitles - string or table of strings, reject windwos whose titles matches (one of) the pattern(s) as per `string.match`
---  * allowRoles - string or table of strings, only allow these window roles as per `hs.window:subrole()`
---  * fullscreen - if `true`, only allow fullscreen windows; if `false`, reject fullscreen windows
---  * visible - if `true`, only allow visible windows; if `false`, reject visible windows
---
--- Returns:
---  * the `hs.windowfilter` object for method chaining
---
--- Notes:
---  * if any parameter (other than `appname`) is `nil` the relevant rule is ignored
function wf:setAppFilter(appname,allowTitles,rejectTitles,allowRoles,fullscreen,visible)
  if type(appname)~='string' and type(appname)~='boolean' then error('appname must be a string or boolean',2) end
  local logs = 'setting '
  if type(appname)=='boolean' then logs=sformat('setting %s filter: ',appname==true and 'override' or 'default')
  else logs=sformat('setting filter for %s: ',appname) end


  if allowTitles==false then
    log.d(logs..'reject')
    self.apps[appname]=false
    return self
  end

  local app = self.apps[appname] or {}
  if allowTitles~=nil then
    local titles=allowTitles
    if type(allowTitles)=='string' then titles={allowTitles}
    elseif type(allowTitles)~='number' and type(allowTitles)~='table' then error('allowTitles must be a number, string or table',2) end
    logs=sformat('%sallowTitles=%s, ',logs,type(allowTitles)=='table' and '{...}' or allowTitles)
    app.titles=titles
  end
  if rejectTitles~=nil then
    local rtitles=rejectTitles
    if type(rejectTitles)=='string' then rtitles={rejectTitles}
    elseif type(rejectTitles)~='table' then error('rejectTitles must be a string or table',2) end
    logs=sformat('%srejectTitles=%s, ',logs,type(rejectTitles)=='table' and '{...}' or rejectTitles)
    app.rtitles=rtitles
  end
  if allowRoles~=nil then
    local roles={}
    if type(allowRoles)=='string' then roles={[allowRoles]=true}
    elseif type(allowRoles)=='table' then
      for _,r in ipairs(allowRoles) do roles[r]=true end
    else error('allowRoles must be a string or table',2) end
    logs=sformat('%sallowRoles=%s, ',logs,type(allowRoles)=='table' and '{...}' or allowRoles)
    app.roles=roles
  end
  if fullscreen~=nil then app.fullscreen=fullscreen end
  if visible~=nil then app.visible=visible end
  self.apps[appname]=app
  log.d(logs)
  return self
end


--- hs.windowfilter.new(fn, includeFullscreen, includeInvisible) -> hs.windowfilter
--- Function
--- Creates a new hs.windowfilter instance
---
--- Parameters:
---  * fn - if `nil`, returns a copy of the default windowfilter; you can then further restrict or expand it
---       - if `true`, returns an empty windowfilter that allows every window
---       - if `false`, returns a windowfilter with a default rule to reject every window
--        - if a string or table of strings, returns a copy of the default windowfilter that only accepts the specified apps
---       - otherwise it must be a function that accepts a `hs.window` and returns `true` if the window is allowed or `false` otherwise; this way you can define a custom windowfilter
---  * includeFullscreen - only valid when `fn` is nil; if true fullscreen windows will be accepted
---  * includeInvisible - only valid when `fn` is nil; if true invisible windows will be accepted
---
--- Returns:
---  * a new windowfilter instance

function windowfilter.new(fn,includeFullscreen,includeInvisible)
  if type(fn)=='function' then
    log.i('new windowfilter, custom function')
    return {
      isWindowAllowed = fn,
      isAppAllowed = function()return true end,
      filterWindows = function(windows)
        local res={}
        for _,w in ipairs(windows) do
          if fn(w) then res[#res+1]=w end
        end
        return res
      end,
    }
  elseif type(fn)=='string' then fn={fn}
  end
  local isTable=type(fn)=='table'
  local o = setmetatable({apps={}},{__index=wf})
  if fn==nil or isTable then
    for _,list in ipairs{SKIP_APPS_NO_PID,SKIP_APPS_NO_WINDOWS,SKIP_APPS_TRANSIENT_WINDOWS} do
      for _,appname in ipairs(list) do
        o:rejectApp(appname)
      end
    end
    if not isTable then
      log.i('new windowfilter, default windowfilter copy')
      for _,appname in ipairs(APPS_ALLOW_NONSTANDARD_WINDOWS) do
        o:setAppFilter(appname,nil,nil,ALLOWED_NONSTANDARD_WINDOW_ROLES)
      end
      for _,appname in ipairs(APPS_SKIP_NO_TITLE) do
        o:setAppFilter(appname,1)
      end
      o:setAppFilter('Hammerspoon',{'Preferences','Console'})
      local fs,vis=false,true
      if includeFullscreen then fs=nil end
      if includeInvisible then vis=nil end
      o:setDefaultFilter(nil,nil,ALLOWED_WINDOW_ROLES,fs,vis)
    else
      log.i('new windowfilter, reject all with exceptions')
      for _,app in ipairs(fn) do
        log.i('allow '..app)
        o:setAppFilter(app,nil,nil,ALLOWED_NONSTANDARD_WINDOW_ROLES,nil,true)
      end
      o:setDefaultFilter(false)
    end
    return o
  elseif fn==true then log.i('new empty windowfilter') return o
  elseif fn==false then log.i('new windowfilter, reject all') o:setDefaultFilter(false)  return o
  else error('fn must be nil, a boolean, a string or table of strings, or a function',2) end
end

--- hs.windowfilter.default
--- Constant
--- The default windowfilter; it filters nonstandard or transient windows (floating windows, menulet windows, notifications etc.), fullscreen windows, and invisible windows
---
--- Notes:
---  * while you can customize the default windowfilter, it's advisable to make your customizations on a local copy via `hs.windowfilter.new()`

windowfilter.default = windowfilter.new()
log.i('default windowfilter instantiated')
local appstoskip={}
for _,list in ipairs{SKIP_APPS_NO_PID,SKIP_APPS_NO_WINDOWS} do
  for _,appname in ipairs(list) do
    appstoskip[appname]=true
    --    skipnonguiapps:rejectApp(appname)
  end
end

--- hs.windowfilter.isGuiApp(appname) -> bool
--- Function
--- Checks whether an app is a known non-GUI app
---
--- Parameters:
---  * appname - name of the app to check as per `hs.application:title()`
---
--- Returns:
---  * `false` if the app is a known non-GUI (or not accessible) app; `true` otherwise

local ssub=string.sub
windowfilter.isGuiApp = function(appname)
  if not appname then return true
  elseif appstoskip[appname] then return false
  elseif ssub(appname,1,12)=='QTKitServer-' then return false
  else return true end
end


return windowfilter

