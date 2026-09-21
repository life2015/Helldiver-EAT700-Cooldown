-- Actual published v15 bytecode reads an isolated deployment directory through
-- real Win32 enumeration. Only resource lookup and game callbacks are mocked.
local ffi,bit=require('ffi'),require('bit')
local entry='mods/retrox/eat700_cooldown'
local impl='mods/retrox/eat700_cooldown_impl'
local function bytes(path)local f=assert(io.open(path,'rb'));local b=f:read('*a');f:close();return b end
local resources={[entry]=bytes(BUILD..'/entry.lua'),[impl]=bytes(BUILD..'/implementation.luac')}
local calls,scans={},0
local native=setmetatable({},{__index=ffi})
native.load=function(name)
    local kernel=ffi.load(name)
    if name~='kernel32' then return kernel end
    return setmetatable({GetModuleFileNameA=function(module,buffer,capacity)
        assert(module==nil);local path=FIXTURE..'/bin/helldivers2.exe'
        assert(capacity>#path);ffi.copy(buffer,path);return #path
    end,FindFirstFileA=function(pattern,buffer)
        scans=scans+1;assert(ffi.string(pattern):find(FIXTURE,1,true) or type(pattern)=='string' and pattern:find(FIXTURE,1,true))
        return kernel.FindFirstFileA(pattern,buffer)
    end},{__index=function(_,key)return kernel[key]end})
end
local env=setmetatable({print=function()end,os={getenv=function()return nil end},
    package={loaded={ffi=native,bit=bit},preload={}},
    stingray={Application={build=function()return 'release'end,can_get=function(kind,name)
        assert(kind=='lua')
        return resources[name]~=nil and not (MODE=='missing_impl' and name==impl)
    end}},update=function(x)return x,nil,3 end},{__index=_G})
env._G=env
env.loadstring=function(data,name)local c,why=loadstring(data,name);if c then setfenv(c,env)end;return c,why end
env.require=function(name)
    if name=='ffi' then return native end
    if name=='bit' then return bit end
    if name:sub(1,11)=='core/wwise/' then return {}end
    assert(resources[name],'Unexpected resource require: '..name)
    calls[name]=(calls[name]or 0)+1
    if name==entry then assert(env.CowboyBingusModLoader.modules[name]=='loading')end
    return assert(env.loadstring(resources[name],name))(name)
end
local startup=assert(env.loadstring(bytes(BUILD..'/published-loader.luac'),'@official_v15'))
startup()
assert(scans==1)
local loader=assert(env.CowboyBingusModLoader)
assert(loader.version==16 and loader.api==1 and type(loader.open_log)=='function')
if MODE=='no_addon' then
    assert(loader.discovery=='0 declared entries' and not calls[entry] and not env.EAT700Cooldown)
else
    assert(loader.discovery=='1 declared entries',tostring(loader.discovery))
    assert(calls[entry]==1)
    if MODE=='missing_impl' then
        assert(loader.modules[entry]:find('EAT-700 Cooldown implementation missing',1,true))
        assert(not calls[impl] and not env.EAT700Cooldown)
    else
        assert(loader.modules[entry]=='loaded' and calls[impl]==1)
        assert(env.EAT700Cooldown and env.EAT700Cooldown.status=='stopped')
        -- No game.dll exists in the build process; controlled initialization failure.
        assert(env.EAT700Cooldown.stopped)
        local x,y,z=env.update(7);assert(x==7 and y==nil and z==3)
    end
end
startup();assert(scans==1)
assert(not calls[entry] or calls[entry]==1)
assert(not calls[impl] or calls[impl]==1)
return 'PASS published v15 discovery + EAT-700 addon: '..MODE
