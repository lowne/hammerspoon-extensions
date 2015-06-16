local done,_hs={},hs
return setmetatable({},{__index=function(t,k)
  local t=_hs[k]
  if t then return t end
  if not done[k] then print('-- Loading extension: '..k)end done[k]=true
  t=require('hs.'..k)
  return t
end})
