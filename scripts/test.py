"""Standalone checks; never accesses the game process or neighboring projects."""
import json, struct
from build import ROOT, GAME, Lua, literal, lua_value, source, sha

def run():
    p=json.loads((ROOT/'profile.json').read_text())
    assert set(p)=={'version','exe_sha256','dll_sha256','signatures','cooldown','proximity'}
    cd=p['cooldown'];assert cd['base_seconds']==70
    assert struct.unpack('<f',bytes.fromhex(cd['before']))[0]==140
    assert struct.unpack('<f',bytes.fromhex(cd['after']))[0]==70
    f32=lambda x:struct.unpack('<f',struct.pack('<f',x))[0]
    effective=f32(f32(70*cd['upgrade_multipliers'][0])*cd['upgrade_multipliers'][1])
    assert effective==cd['effective_seconds'] and round(effective)==60
    fuse=p['proximity']
    assert fuse['record_id']==259 and fuse['incendiary_explosion_id']==316
    assert [(e['offset'],e['after']) for e in fuse['edits']]==[
        (136,struct.pack('<f',360).hex()),
        (148,struct.pack('<f',2).hex()),(152,struct.pack('<f',.2).hex()),
        (156,struct.pack('<I',316).hex()),(160,struct.pack('<f',1).hex()),
        (248,'d8e996ab')]
    # Local runtime capture is optional and never distributed with the mod.
    captured=ROOT/'build/proximity/napalm.bin'
    if captured.exists():
        original=captured.read_bytes();patched=bytearray(original)
        assert len(original)==fuse['record_size'] and sha(original)==fuse['original_sha256']
        for edit in fuse['edits']:
            off=edit['offset'];assert original[off:off+4].hex()==edit['before']
            patched[off:off+4]=bytes.fromhex(edit['after'])
        assert sha(patched)==fuse['patched_sha256']
        changed={i for e in fuse['edits'] for i in range(e['offset'],e['offset']+4)}
        assert all(original[i]==patched[i] for i in range(len(original)) if i not in changed)
        assert struct.unpack_from('<I',patched,144)[0]==316
        # Native overlap hits use 90 degrees, then pass the same angle gate as impacts.
        # 0.2.0 retained the native 60-degree limit and therefore rejected these hits.
        assert struct.unpack_from('<f',original,136)[0]<90<=struct.unpack_from('<f',patched,136)[0]
        donor=(captured.parent/'flak.bin').read_bytes()
        assert patched[136:140]==donor[136:140] and patched[248:252]==donor[248:252]
    code=source()
    for forbidden in ('ProjectileWeaponComponent','WeaponDataComponent','VirtualAlloc','api.allocate','api.pointer_bytes','Flak','Cluster'):
        assert forbidden not in code,'Unexpected capability: '+forbidden
    results=[]
    for path in (ROOT/'tests/cooldown.lua',ROOT/'tests/proximity.lua',ROOT/'tests/install.lua'):
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
    results.append('PASS LuaJIT compile, real WinAPI limited to four-byte self-process writes, hashes, cooldown, no weapon table or projectile ID replacement capabilities')
    print(results[-1]);folder=ROOT/'build';folder.mkdir(exist_ok=True)
    (folder/'test-report.json').write_text(json.dumps({'passed':results,'game_process_accessed':False},indent=2))

if __name__=='__main__':run()
