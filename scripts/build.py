"""Build a local EAT addon; never deploys or modifies a running game."""
import hashlib, json, os, struct, zipfile
from urllib.request import urlopen
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
GAME=Path(os.environ.get('HD2_GAME_ROOT',r'C:\Program Files (x86)\Steam\steamapps\common\Helldivers 2'))
from lua_host import Lua, literal
from archive import resource_hash, make_archive, TYPE, ARCHIVE

MODULE='mods/retrox/eat700_cooldown'
IMPL=MODULE+'_impl'
CALLBACK='core/wwise/lua/wwise_flow_callbacks'
LOADER_SHA={
    'v14':'7FA8AF328AC2C98F68DD5946D94444315DD61B2B3504B0788301700CC9C023B2',
    'v15':'FA766634DFF3F7D1FD9C5C0EBA72B1FBABAD8721710491CAAA4E12A598028CDA'}
CALLBACK_SHA='B2E82518373E7EB85315C54B5829F8FD2BB1277D1690E40476354111B1608210'

def package_name(channel,version):
    label={'v14':'内置加载器','v15':'需要额外安装加载器'}[channel]
    return f'EAT700-Cooldown-{version}-{channel}-{label}.zip'

def loader_archive(channel):
    path=ROOT/'build'/f'Bingus-Shared-Loader-{channel}.zip'
    if not path.exists():
        url=f'https://github.com/CowboyBingus/BingusSharedLoader/releases/download/{channel}/{path.name}'
        with urlopen(url,timeout=60)as response:data=response.read()
        assert sha(data)==LOADER_SHA[channel],'Unexpected published loader download'
        path.parent.mkdir(exist_ok=True);path.write_bytes(data)
    assert sha(path.read_bytes())==LOADER_SHA[channel],'Unexpected cached loader ZIP'
    with zipfile.ZipFile(path)as z:return z.read('data/'+ARCHIVE)

def bridge_source(published,code):
    startup=(ROOT/'src/startup.lua').read_text(encoding='utf-8')
    return ('local start=(function()\n'+startup+'\nend)()\n'
            'start(function() assert(loadstring('+literal(published)+", '@published_bingus_v14'))() end,\n"
            'function() assert(loadstring('+literal(code)+", '@eat700_cooldown'))() end)\n")

def sha(data):return hashlib.sha256(data).hexdigest().upper()

def lua_value(value):
    if isinstance(value,str):return literal(value.encode())
    if isinstance(value,(int,float)):return str(value)
    if isinstance(value,list):return '{'+','.join(lua_value(x) for x in value)+'}'
    if isinstance(value,dict):return '{'+','.join('['+lua_value(k)+']='+lua_value(v) for k,v in value.items())+'}'
    raise TypeError(type(value))

def source():
    profile=json.loads((ROOT/'profile.json').read_text())
    parts=[]
    for name in ('windows','cooldown','controller','install'):
        parts.append('local '+name+'=(function()\n'+(ROOT/'src'/f'{name}.lua').read_text()+'\nend)()')
    parts.append('return install(windows,controller,'+lua_value(profile)+',cooldown)')
    return '\n'.join(parts)

def unpack(archive):
    magic,types,count=struct.unpack_from('<III',archive)
    assert magic==0xf0000011 and types==1
    result={}
    for i in range(count):
        row=struct.unpack_from('<7Q6I',archive,104+i*80)
        assert row[1]==TYPE and row[2]>=104+count*80 and row[2]+row[7]<=len(archive)
        raw=archive[row[2]:row[2]+row[7]]
        length,version=struct.unpack_from('<II',raw)
        assert version==2 and length==len(raw)-8 and row[0] not in result
        result[row[0]]=raw[8:]
    return result

def build():
    profile=json.loads((ROOT/'profile.json').read_text());version=profile['version']
    assert sha((GAME/'data/game/game.dll').read_bytes())==profile['dll_sha256']
    assert sha((GAME/'bin/helldivers2.exe').read_bytes())==profile['exe_sha256']
    folder=ROOT/'build';folder.mkdir(exist_ok=True)
    text=source();(folder/'eat700_cooldown.lua').write_text(text,encoding='utf-8')
    lua=Lua(GAME/'bin/lua51.dll')
    try:code=lua.compile(text)
    finally:lua.close()
    (folder/'eat700_cooldown.luac').write_bytes(code)
    entry=(ROOT/'src/addon.lua').read_bytes()
    assert entry.startswith(('-- HD2-Addon: '+MODULE+'\n').encode())
    reports=[]
    from packaging_checks import check_v14, check_v15
    for channel in ('v14','v15'):
        published_archive=loader_archive(channel)
        published=unpack(published_archive)
        callback=published[resource_hash(CALLBACK)]
        if channel=='v14':
            assert sha(struct.pack('<II',len(callback),2)+callback)==CALLBACK_SHA
            lua=Lua(GAME/'bin/lua51.dll')
            try:bridge=lua.compile(bridge_source(callback,code))
            finally:lua.close()
            bodies={resource_hash(CALLBACK):bridge,resource_hash(IMPL):code}
            resources=[CALLBACK,IMPL];directory='data'
        else:
            bodies={resource_hash(MODULE):entry,resource_hash(IMPL):code}
            assert not set(bodies).intersection(published)
            resources=[MODULE,IMPL];directory='Addon'
        archive=make_archive({key:struct.pack('<II',len(value),2)+value for key,value in bodies.items()})
        assert unpack(archive)==bodies
        assert resource_hash('boot') not in bodies
        assert resource_hash('mods/codex/gun_calibration') not in bodies
        checks=check_v14(callback,bridge) if channel=='v14' else check_v15(published_archive,callback,entry,code,archive)
        description='Only EAT-700 cooldown: base 140s -> 70s (same as EAT-17); 59.85s after 5% and 10% upgrades. '
        description+=('Includes published Bingus Shared Loader v14. This package MUST WIN the Wwise startup conflict. '
                      'Arsenal default priority: put last; first-mod priority: put first.' if channel=='v14' else
                      'Requires separately installed Bingus Shared Loader v15 or newer. Discoverable addon; no Wwise/boot replacement.')
        report={'version':version,'channel':channel,'source_sha256':sha(text.encode()),'archive_sha256':sha(archive),
                'resources':resources,'data_directory':directory,'implementation_sha256':sha(code),
                'tested_loader_zip_sha256':LOADER_SHA[channel],'startup_tests':checks,
                'profile':profile,'validation':{'cooldown_origin':'Base 70s matches EAT-17 stratagem registry row 145 at offset 104; new cooldown and standalone startup not yet tested in game',
                'packaged_startup_in_game':False,'multiplayer':False},
                'bundled_loader':channel=='v14','replaces_wwise':channel=='v14'}
        name=package_name(channel,version)
        manifest={'Version':1,'Guid':'4d59d3ea-05aa-432b-b124-0e9d6688785a','Name':f'EAT-700 Cooldown {version} {channel}',
                  'Description':description,'Options':[{'Name':'EAT-700 Cooldown','Description':description,'Include':[directory]}]}
        files={directory+'/'+ARCHIVE:archive,directory+'/'+ARCHIVE+'.stream':b'',directory+'/'+ARCHIVE+'.gpu_resources':b'',
               'manifest.json':json.dumps(manifest,indent=2).encode(),'provenance.json':json.dumps(report,indent=2).encode(),
               'THIRD_PARTY.md':(ROOT/'THIRD_PARTY.md').read_bytes(),
               'INSTALL.txt':('Package channel: '+channel+'\n\n'+(ROOT/'INSTALL.txt').read_text(encoding='utf-8')).encode()}
        out=ROOT/'releases'/name;out.parent.mkdir(exist_ok=True)
        with zipfile.ZipFile(out,'w',compression=zipfile.ZIP_DEFLATED)as z:
            for path,data in sorted(files.items()):
                info=zipfile.ZipInfo(path,date_time=(1980,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED
                z.writestr(info,data)
        with zipfile.ZipFile(out)as z:
            assert z.testzip()is None and set(z.namelist())==set(files) and unpack(z.read(directory+'/'+ARCHIVE))==bodies
        report.update(zip_name=name,zip_sha256=sha(out.read_bytes()))
        (folder/f'package-{channel}.json').write_text(json.dumps(report,indent=2))
        reports.append(report);print(out)
    assert len({r['implementation_sha256'] for r in reports})==1
    (folder/'package-matrix.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
    return reports

if __name__=='__main__':build()
