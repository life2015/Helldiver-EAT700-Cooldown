local factory=assert(loadfile(ROOT..'/src/cooldown.lua'))()
local controller=assert(loadfile(ROOT..'/src/controller.lua'))()
local ffi=require('ffi')
local function bytes(s)return(s:gsub('..',function(h)return string.char(tonumber(h,16))end))end
local function pointer(n)return ffi.string(ffi.new('uint64_t[1]',n),8)end
local config=PROFILE.cooldown
local base,record,name=0x100000,0x60000000,0x61000000
local function fixture()
    local memory={};local api={writes={}};local state={}
    local raw=string.rep('\165',config.record_size)
    local function replace(s,off,value)return s:sub(1,off)..value..s:sub(off+#value+1)end
    raw=replace(raw,0,bytes(config.identity_hex))
    raw=replace(raw,config.name_offset,pointer(name))
    raw=replace(raw,config.offset,bytes(config.before))
    memory[record]=raw;memory[name]=config.name..'\0';memory[base+config.slot_rva]=pointer(record)
    function api.read(p,n)
        for start,data in pairs(memory)do
            if p>=start and p+n<=start+#data then return data:sub(p-start+1,p-start+n)end
        end
    end
    function api.ptr(p)
        local data=api.read(p,8);if not data then return nil end
        local n=0;for i=8,1,-1 do n=n*256+data:byte(i)end
        return n~=0 and n or nil
    end
    function api.writable()return true end
    function api.write(p,before,after)
        assert(p==record+config.offset and #before==4 and #after==4,'Unexpected write scope')
        assert(api.read(p,4)==before)
        memory[record]=replace(memory[record],config.offset,after)
        api.writes[#api.writes+1]={p,before,after}
        if api.fail then api.fail=false;error('Simulated failure after write')end
    end
    return {memory=memory,api=api,raw=raw,state=state,control=controller(api,PROFILE,base,state,factory),replace=replace}
end
local t=fixture();t.control.poll()
assert(t.state.status=='active' and #t.api.writes==1 and t.state.base_cooldown==70)
assert(t.memory[record]==t.replace(t.raw,config.offset,bytes(config.after)))
t.control.poll();assert(#t.api.writes==1)
assert(t.control.restore() and t.memory[record]==t.raw and #t.api.writes==2)
assert(t.control.restore() and #t.api.writes==2)

t=fixture();t.memory[base+config.slot_rva]=nil;t.control.poll()
assert(t.state.status=='waiting_for_stratagem' and #t.api.writes==0)
t.memory[base+config.slot_rva]=pointer(record);t.control.poll();assert(#t.api.writes==1)

t=fixture();t.memory[name]='wrong'..string.rep('\0',#config.name)
assert(not pcall(t.control.poll));assert(t.control.restore() and #t.api.writes==0)

t=fixture();t.memory[record]=t.replace(t.raw,config.offset,bytes(config.after))
assert(not pcall(t.control.poll));assert(t.control.restore() and #t.api.writes==0)

t=fixture();t.api.fail=true
assert(not pcall(t.control.poll));assert(t.control.restore() and t.memory[record]==t.raw)

t=fixture();t.control.poll()
t.memory[record]=t.replace(t.memory[record],config.offset,'xxxx')
assert(not pcall(t.control.poll));assert(not t.control.restore() and #t.api.writes==1)

t=fixture();t.control.poll();t.memory[base+config.slot_rva]=pointer(record+4096)
assert(not pcall(t.control.poll));assert(not t.control.restore() and #t.api.writes==1)
return 'PASS only one four-byte cooldown field changes; wait/retry, restoration, changed identity, foreign values, failed-write rollback'
