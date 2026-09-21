"""Exercise published loaders in isolated Lua states and synthetic data folders."""
import tempfile
from pathlib import Path
from build import ROOT, GAME, ARCHIVE, Lua, literal


def run(test,values):
    lua=Lua(GAME/'bin/lua51.dll')
    try:
        prefix=';'.join(k+'='+literal(str(v).encode()) for k,v in values.items())+';'
        result=lua.run(prefix+'return assert(loadfile('+literal((ROOT/'tests'/test).as_posix().encode())+'))()').decode()
        print(result);return result
    finally:lua.close()


def check_v14(published,bridge):
    folder=ROOT/'build/v14';folder.mkdir(exist_ok=True)
    (folder/'published.luac').write_bytes(published)
    (folder/'bridge.luac').write_bytes(bridge)
    return [run('packaging_v14.lua',{'ROOT':ROOT.as_posix(),
        'ORIGINAL':(folder/'published.luac').as_posix(),'BRIDGE':(folder/'bridge.luac').as_posix()})]


def check_v15(loader_archive,callback,entry,code,archive):
    folder=ROOT/'build/v15';folder.mkdir(exist_ok=True)
    (folder/'entry.lua').write_bytes(entry)
    (folder/'implementation.luac').write_bytes(code)
    (folder/'published-loader.luac').write_bytes(callback)
    results=[]
    with tempfile.TemporaryDirectory(prefix='integration-',dir=folder)as temp:
        fixture=Path(temp).resolve();assert fixture.parent==folder.resolve()
        (fixture/'data').mkdir()
        for mode in ('loader_high','addon_high','missing_impl','no_addon'):
            addon_index,loader_index=(10,2) if mode=='addon_high' else (2,10)
            for index in (2,10):
                path=fixture/'data'/ARCHIVE.replace('.patch_0','.patch_'+str(index))
                if path.exists():path.unlink()
            (fixture/'data'/ARCHIVE.replace('.patch_0','.patch_'+str(loader_index))).write_bytes(loader_archive)
            if mode!='no_addon':
                (fixture/'data'/ARCHIVE.replace('.patch_0','.patch_'+str(addon_index))).write_bytes(archive)
            results.append(run('packaging_v15.lua',{'FIXTURE':fixture.as_posix(),'BUILD':folder.as_posix(),'MODE':mode}))
    return results
