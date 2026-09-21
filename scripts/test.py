"""Standalone checks; never accesses the game process or neighboring projects."""
import json, struct
from build import ROOT, GAME, Lua, literal, lua_value, source, sha

def run():
    p=json.loads((ROOT/'profile.json').read_text())
    assert set(p)=={'version','exe_sha256','dll_sha256','signatures','cooldown'}
    cd=p['cooldown'];assert cd['base_seconds']==70
    assert struct.unpack('<f',bytes.fromhex(cd['before']))[0]==140
    assert struct.unpack('<f',bytes.fromhex(cd['after']))[0]==70
    f32=lambda x:struct.unpack('<f',struct.pack('<f',x))[0]
    effective=f32(f32(70*cd['upgrade_multipliers'][0])*cd['upgrade_multipliers'][1])
    assert effective==cd['effective_seconds'] and round(effective)==60
    code=source()
    for forbidden in ('ProjectileWeaponComponent','WeaponDataComponent','VirtualAlloc','api.allocate','api.pointer_bytes','Flak','Cluster'):
        assert forbidden not in code,'Unexpected capability: '+forbidden
    results=[]
    for path in (ROOT/'tests/cooldown.lua',ROOT/'tests/install.lua'):
        lua=Lua(GAME/'bin/lua51.dll')
        try:
            result=lua.run('ROOT='+literal(ROOT.as_posix().encode())+';PROFILE='+lua_value(p)+';return assert(loadfile('+literal(path.as_posix().encode())+'))()').decode()
            results.append(result);print(result)
        finally:lua.close()
    lua=Lua(GAME/'bin/lua51.dll')
    try:
        result=lua.run('local api=assert(loadfile('+literal((ROOT/'src/windows.lua').as_posix().encode())+'))()();'+r'''
            local ffi=require('ffi')
            local buffer=ffi.new('uint8_t[8]',{1,2,3,4,5,6,7,8})
            local p=tonumber(ffi.cast('uintptr_t',buffer))
            api.write(p,'\1\2\3\4','abcd')
            assert(api.read(p,8)=='abcd\5\6\7\8')
            assert(not pcall(api.write,p,'abcd\5\6\7\8','12345678'))
            assert(not pcall(api.write,p,'wrong','wrong'))
            assert(api.read(p,8)=='abcd\5\6\7\8')
            assert(api.sha('abc')=='BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD')
            return api.module_hash(api.module('lua51.dll'))
        ''').decode()
        assert result==sha((GAME/'bin/lua51.dll').read_bytes())
        assert lua.compile(code).startswith(b'\x1bLJ\x02\x02')
    finally:lua.close()
    results.append('PASS standalone LuaJIT compile, real WinAPI limited to four-byte self-process writes, hashes, rounded cooldown, no weapon modification capabilities')
    print(results[-1]);folder=ROOT/'build';folder.mkdir(exist_ok=True)
    (folder/'test-report.json').write_text(json.dumps({'passed':results,'game_process_accessed':False},indent=2))

if __name__=='__main__':run()
