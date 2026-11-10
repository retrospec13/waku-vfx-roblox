-- Explicit logic-only mocks: no geometry accuracy, engine rendering or asset fetching.
local valueMT = {}
local function value(x,y,z)
	return setmetatable({X=x or 0,Y=y or 0,Z=z or 0}, valueMT)
end
valueMT.__add=function(a,b) return value(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
valueMT.__sub=function(a,b) return value(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
valueMT.__unm=function(a) return value(-a.X,-a.Y,-a.Z) end
valueMT.__mul=function(a,b)
	if type(a)=='number' then return value(a*b.X,a*b.Y,a*b.Z) end
	if type(b)=='number' then return value(a.X*b,a.Y*b,a.Z*b) end
	return value(a.X+b.X,a.Y+b.Y,a.Z+b.Z) -- transforms approximate translation only
end
valueMT.__div=function(a,b) return value(a.X/b,a.Y/b,a.Z/b) end
valueMT.__index=function(a,k)
	if k=='Position' then return a end
	if k=='Magnitude' then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end
	if k=='Unit' then local n=a.Magnitude;return if n>0 then a/n else value(0,0,1) end
	if k=='LookVector' then return value(0,0,-1) end
	if k=='RightVector' then return value(1,0,0) end
	if k=='UpVector' then return value(0,1,0) end
	if k=='Rotation' then return value() end
	if k=='Cross' then return function(self,b) return value(self.Y*b.Z-self.Z*b.Y,self.Z*b.X-self.X*b.Z,self.X*b.Y-self.Y*b.X) end end
	if k=='Dot' then return function(self,b) return self.X*b.X+self.Y*b.Y+self.Z*b.Z end end
	if k=='Lerp' then return function(self,b,t) return self+(b-self)*t end end
	if k=='PointToWorldSpace' or k=='VectorToWorldSpace' then return function(self,b) return self+b end end
	if k=='ToObjectSpace' then return function(self,b) return b-self end end
	error('unsupported value field '..k)
end
local Vector3={new=value,one=value(1,1,1),zero=value(),xAxis=value(1,0,0),yAxis=value(0,1,0),zAxis=value(0,0,1)}
local CFrame={new=function(x,y,z) return if type(x)=='table' then x else value(x,y,z) end,identity=value(),Angles=function() return value() end,lookAt=function(a) return a end,fromMatrix=function(a) return a end,fromAxisAngle=function() return value() end}
local colorMT = {__index={Lerp=function(self,b,t) return self end}}
local Color3={new=function(r,g,b) return setmetatable({R=r or 0,G=g or 0,B=b or 0},colorMT) end,fromRGB=function(r,g,b) return setmetatable({R=r/255,G=g/255,B=b/255},colorMT) end,fromHSV=function(h,s,v) return setmetatable({H=h,S=s,V=v},colorMT) end}
local function sequence(v) return {Keypoints=if type(v)=='table' then v else {{Value=v}}} end
local ColorSequence={new=sequence};local NumberSequence={new=sequence}
local ColorSequenceKeypoint={new=function(t,v) return {Time=t,Value=v} end}
local NumberSequenceKeypoint={new=function(t,v,e) return {Time=t,Value=v,Envelope=e} end}
local NumberRange={new=function(a,b) return {Min=a,Max=b or a} end}
local Vector2={new=function(x,y) return {X=x,Y=y} end}
local Enum=setmetatable({}, {__index=function(t,k)
 local e=setmetatable({}, {__index=function(s,n) rawset(s,n,n);return n end});rawset(t,k,e);return e
end})
local Random={new=function(seed) return {NextNumber=function(_,a,b) return (a or 0)+((b or 1)-(a or 0))*0.37 end,NextInteger=function(_,a,b) return a end} end}
local RaycastParams={new=function() return {} end}
local methods={}
local instanceMT={}
local function newInstance(cls)
 return setmetatable({_p={ClassName=cls,Name=cls,Archivable=true,Transparency=0,Anchored=false,CFrame=CFrame.identity,Position=Vector3.zero,Size=Vector3.one,Transform=CFrame.identity},_children={}},instanceMT)
end
instanceMT.__index=function(t,k) local v=t._p[k];if v~=nil then return v end;return methods[k] end
instanceMT.__newindex=function(t,k,v)
 if k=='Parent' then
  local old=t._p.Parent
  if old then for i,c in old._children do if c==t then table.remove(old._children,i);break end end end
  if v then table.insert(v._children,t) end
 end
 t._p[k]=v
end
function methods:IsA(c)
 return c==self.ClassName or (c=='BasePart' and (self.ClassName=='Part' or self.ClassName=='WedgePart'))
end
function methods:GetChildren() return table.clone(self._children) end
function methods:GetDescendants()
 local out={};for _,v in self._children do table.insert(out,v);for _,d in v:GetDescendants() do table.insert(out,d) end end;return out
end
function methods:FindFirstChild(n) for _,v in self._children do if v.Name==n then return v end end;return nil end
function methods:FindFirstChildOfClass(n) for _,v in self._children do if v:IsA(n) then return v end end;return nil end
function methods:FindFirstChildWhichIsA(n,recursive) for _,v in (if recursive then self:GetDescendants() else self._children) do if v:IsA(n) then return v end end;return nil end
function methods:Destroy() for _,v in self:GetChildren() do v:Destroy() end;self.Parent=nil;self._p.Destroyed=true end
function methods:Clone()
 if self.FailClone then error('injected Clone failure') end
 local n=newInstance(self.ClassName);for k,v in self._p do if k~='Parent' then n[k]=v end end
 for _,c in self._children do c:Clone().Parent=n end;return n
end
function methods:Emit(_) end
function methods:Clear() end
function methods:GetPlayingAnimationTracks() return {} end
function methods:Raycast(...) return nil end
local Instance={new=newInstance}
local Workspace=newInstance('Workspace')
local Lighting=newInstance('Lighting')
local callbacks={}
local Heartbeat={Connect=function(_,fn)
 local c={fn=fn,Connected=true};function c:Disconnect() self.Connected=false end;table.insert(callbacks,c);return c
end}
local realTime=0
local os={clock=function() return realTime end}
local function tick(dt) realTime+=dt;for _,c in callbacks do if c.Connected then c.fn() end end end
local Players={GetPlayerFromCharacter=function(_,c) return if c.IsPlayer then {} else nil end}
local game={GetService=function(_,n)
 if n=='Players' then return Players elseif n=='RunService' then return {Heartbeat=Heartbeat} elseif n=='Workspace' then return Workspace elseif n=='Lighting' then return Lighting elseif n=='ContentProvider' then return {} end
 error('unsupported service '..n)
end}
local warn=function(...) end -- assertions below inspect waku.Errors; expected failures are intentional
local task={wait=function(t) tick(t or 0.03) end}
local function makeCaster(player,anchor)
 local c=newInstance('Model');c.Name='TestCaster';c.IsPlayer=player;c.Archivable=false;c.Parent=Workspace
 local r=newInstance('Part');r.Name='HumanoidRootPart';r.Transparency=1;r.Anchored=anchor or false;r.Parent=c
 local b=newInstance('Part');b.Name='Body';b.Transparency=0.35;b.Parent=c
 local d=newInstance('Decal');d.Name='Face';d.Transparency=0.2;d.Parent=b
 local m=newInstance('Motor6D');m.Name='RightShoulder';m.Parent=b
 return c,r,b,d
end
