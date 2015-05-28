--- === hs.windowfilter ===
---
--- Filters windows by application, role, and/or title

hs=require'hs._inject_extensions'
local log=hs.logger.new('wfilter')
local ipairs,type,smatch = ipairs,type,string.match

local windowfilter={}
windowfilter.setLogLevel=function(lvl)log.setLogLevel(lvl) return windowfilter end

local SKIP_APPS_NO_PID = {
  --TODO keep this updated (used in the root filter)
  'universalaccessd','sharingd','Safari Networking','iTunes Helper','Safari Web Content',
  'App Store Web Content',
  'Google Chrome Helper','Spotify Helper','Karabiner_AXNotifier',
  'Little Snitch Agent','Little Snitch Network Monitor',
}

local SKIP_APPS_NO_PID_BUNDLE = {
  'com.apple.qtkitserver', -- QTKitServer-(%d) Safari Web Content
}

local SKIP_APPS_NO_WINDOWS = {
  --TODO keep this updated (used in the root filter)
  --'loginwindow', --FIXME this actually has a window...
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
  'Spotlight', 'Notification Center',
  -- preferences etc
  'PopClip','Isolator', 'CheatSheet', 'CornerClickBG', 'Alfred 2', 'Moom', 'CursorSense Manager',
  -- menulets
  'Music Manager', 'Google Drive', 'Dropbox', '1Password mini', 'Colors for Hue', 'MacID',
  'CrashPlan menu bar', 'Flux', 'Jettison', 'Bartender', 'SystemPal', 'BetterSnapTool', 'Grandview', 'Radium',
}

local APPS_ALLOW_NONSTANDARD_WINDOWS = {
  --TODO keep this updated (used in the default filter)
  'iTerm2', 'Lua Development Tools Product', 'SwitchResX Daemon',
}

local APPS_SKIP_NO_TITLE = {
  --TODO keep this updated (used in the default filter)
  'Lua Development Tools Product'
}

local ALLOWED_NONSTANDARD_WINDOW_ROLES = {'AXStandardWindow','AXDialog','AXFloatingWindow','AXSystemDialog'}
local ALLOWED_WINDOW_ROLES = {'AXStandardWindow'}

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
      if type(app.titles)=='number' then if #title<=app.titles then return end
      elseif not matchTitle(app.titles,title) then return end
    end
    if app.rtitles and matchTitle(app.rtitles,title) then return end
    if app.roles and not app.roles[role] then return end
    if app.fullscreen~=nil and app.fullscreen~=fullscreen then return end
    if app.visible~=nil and app.visible~=visible then return end
    return true
  end
  local role = window.subrole and window:subrole() or '?'
  local title = window:title()
  local fullscreen = window:isFullScreen()
  local visible = window:isVisible()

  local app=self.apps[true]
  if app==false then return false
  elseif app and not allowWindow(app,role,title,fullscreen,visible) then return false end
  appname = appname or window:application():title()
  app=self.apps[appname]
  if app==false then return false
  elseif app and not allowWindow(app,role,title,fullscreen,visible) then return false end
  app=self.apps[false]
  if app==false then return false
  elseif app and not allowWindow(app,role,title,fullscreen,visible) then
    return false
  end
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
---  * `false` if the app is outright rejected by the windowfilter; `true` otherwise

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

--- hs.windowfilter:rejectApp(appname)
--- Method
--- Sets the windowfilter to outright reject any windows belonging to a specific app
---
--- Parameters:
---  * appname - app name as per `hs.application:title()`

function wf:rejectApp(appname)
  self:setAppFilter(appname,false)
end

--- hs.window:setDefaultFilter(allowTitles, rejectTitles, allowRoles, fullscreen, visible)
--- Method
--- Set the default filtering rules to be used for apps without app-specific rules
---
--- Parameters:
---  * allowTitles - if a number, only allow windows whose title is at least as many characters long; e.g. pass `1` to filter windows with an empty title
---                - if a string or table of strings, only allow windows whose title matches (one of) the pattern(s) as per `string.match`
---  * rejectTitles - string or table of strings, reject windwos whose titles matches (one of) the pattern(s) as per `string.match`
---  * allowRoles - string or table of strings, only allow these window roles as per `hs.window:subrole()`
---  * fullscreen - if `true`, only allow fullscreen windows; if `false`, reject fullscreen windows; if `nil`, allow fullscreen and nonfullscreen windows
---  * visible - if `true`, only allow visible windows; if `false`, reject visible windows; if `nil`, allow visible and invisible windows
---
--- Notes:
---  * if any parameter is `nil` the relevant rule is ignored
function wf:setDefaultFilter(...)
  self:setAppFilter(false,...)
end
--- hs.window:setOverrideFilter(allowTitles, rejectTitles, allowRoles, fullscreen, visible)
--- Method
--- Set overriding filtering rules that will be applied for all apps before any app-specific rules
---
--- Parameters:
---  * allowTitles - if a number, only allow windows whose title is at least as many characters long; e.g. pass `1` to filter windows with an empty title
---                - if a string or table of strings, only allow windows whose title matches (one of) the pattern(s) as per `string.match`
---  * rejectTitles - string or table of strings, reject windwos whose titles matches (one of) the pattern(s) as per `string.match`
---  * allowRoles - string or table of strings, only allow these window roles as per `hs.window:subrole()`
---  * fullscreen - if `true`, only allow fullscreen windows; if `false`, reject fullscreen windows; if `nil`, allow fullscreen and nonfullscreen windows
---  * visible - if `true`, only allow visible windows; if `false`, reject visible windows; if `nil`, allow visible and invisible windows
---
--- Notes:
---  * if any parameter is `nil` the relevant rule is ignored
function wf:setOverrideFilter(...)
  self:setAppFilter(true,...)
end

--- hs.window:setAppFilter(appname, allowTitles, rejectTitles, allowRoles, fullscreen, visible)
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
--- Notes:
---  * if any parameter (other than `appname`) is `nil` the relevant rule is ignored
function wf:setAppFilter(appname,allowTitles,rejectTitles,allowRoles,fullscreen,visible)
  if type(appname)~='string' and type(appname)~='boolean' then error('appname must be a string or boolean',2) end
  if allowTitles==false then self.apps[appname]=false return end

  local app = self.apps[appname] or {}
  if allowTitles~=nil then
    local titles=allowTitles
    if type(allowTitles)=='string' then titles={allowTitles}
    elseif type(allowTitles)~='number' and type(allowTitles)~='table' then error('allowTitles must be a number, string or table',2) end
    app.titles=titles
  end
  if rejectTitles~=nil then
    local rtitles=rejectTitles
    if type(rejectTitles)=='string' then rtitles={rejectTitles}
    elseif type(rejectTitles)~='table' then error('rejectTitles must be a string or table',2) end
    app.rtitles=rtitles
  end
  if allowRoles~=nil then
    local roles={}
    if type(allowRoles)=='string' then roles={[allowRoles]=true}
    elseif type(allowRoles)=='table' then
      for _,r in ipairs(allowRoles) do roles[r]=true end
    else error('allowRoles must be a string or table',2) end
    app.roles=roles
  end
  if fullscreen~=nil then app.fullscreen=fullscreen end
  if visible~=nil then app.visible=visible end
  self.apps[appname]=app
end


--- hs.windowfilter.new(fn, includeFullscreen, includeInvisible) -> hs.windowfilter
--- Function
--- Creates a new hs.windowfilter instance
---
--- Parameters:
---  * fn - if `true`, returns a copy of the default windowfilter that you can further restrict or expand
---       - if `nil`, returns an empty windowfilter that allows every window
---       - otherwise it must be a function that accepts a `hs.window` and returns `true` if the window is allowed or `false` otherwise; this way you can define a custom windowfilter
---  * includeFullscreen - only valid when `fn` is true; if true fullscreen windows will be accepted
---  * includeInvisible - only valid when `fn` is true; if true invisible windows will be accepted
---
--- Returns:
---  * a new windowfilter instance

function windowfilter.new(fn,includeFullscreen,includeInvisible)
  if type(fn)=='function' then
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
  end
  local o = setmetatable({apps={}},{__index=wf})
  if fn==true then
    for _,list in ipairs{SKIP_APPS_NO_PID,SKIP_APPS_NO_WINDOWS,SKIP_APPS_TRANSIENT_WINDOWS} do
      for _,appname in ipairs(list) do
        o:rejectApp(appname)
      end
    end
    for _,appname in ipairs(APPS_ALLOW_NONSTANDARD_WINDOWS) do
      o:setAppFilter(appname,nil,nil,ALLOWED_NONSTANDARD_WINDOW_ROLES)
    end
    for _,appname in ipairs(APPS_SKIP_NO_TITLE) do
      o:setAppFilter(appname,1)
    end
    local fs,vis=false,true
    if includeFullscreen then fs=nil end
    if includeInvisible then vis=nil end
    o:setOverrideFilter(nil,nil,nil,fs,vis)
    o:setDefaultFilter(nil,nil,ALLOWED_WINDOW_ROLES)--,ALLOWED_WINDOW_ROLES_INVISIBLE)
    return o
  elseif fn==nil then return o
  else error('fn must be nil, true or a function',2) end
end

--- hs.windowfilter.default
--- Constant
--- The default windowfilter; it filters nonstandard or transient windows (floating windows, menulet windows, notifications etc.), fullscreen windows, and invisible windows
---
--- Notes:
---  * while you can customize the default windowfilter, it's advisable to make your customizations on a local copy via `hs.windowfilter.new(true)`

windowfilter.default = windowfilter.new(true)
--local appstoskip={Hammerspoon=true}
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

