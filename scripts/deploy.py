"""Deploy/remove only journaled EAT-700 cooldown addon files while Helldivers 2 is closed."""
import argparse, csv, io, json, re, struct, subprocess, zipfile
from pathlib import Path
from build import ROOT, GAME, ARCHIVE, sha, unpack, package_name

JOURNAL=ROOT/'build/deployment.json'
STEM=ARCHIVE.split('.')[0]

def require_closed():
    out=subprocess.run(['tasklist','/FI','IMAGENAME eq helldivers2.exe','/FO','CSV','/NH'],capture_output=True,check=True)
    rows=csv.reader(io.StringIO(out.stdout.decode(errors='replace')))
    if any(row and row[0].lower()=='helldivers2.exe' for row in rows):
        raise RuntimeError('Helldivers 2 is running. Exit normally before installing/removing the addon.')

def target(name):
    assert re.fullmatch(STEM+r'\.patch_\d+(?:\.stream|\.gpu_resources)?',name)
    parent=(GAME/'data').resolve();path=(parent/name).resolve()
    assert path.parent==parent
    return path

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('action',choices=['install','uninstall'])
    p.add_argument('--channel',choices=['v14','v15'],default='v15')
    args=p.parse_args();require_closed()
    if args.action=='uninstall':
        record=json.loads(JOURNAL.read_text())
        assert Path(record['game_directory']).resolve()==GAME.resolve()
        paths=[]
        for name,digest in record['files'].items():
            path=target(name)
            if path.exists():
                assert sha(path.read_bytes())==digest,'Changed file; refusing to remove '+name
                paths.append(path)
        require_closed()
        for path in paths:path.unlink()
        record['status']='removed';JOURNAL.write_text(json.dumps(record,indent=2));print('Removed recorded EAT-700 cooldown addon files');return
    if JOURNAL.exists():
        assert json.loads(JOURNAL.read_text())['status']=='removed','Existing deployment needs inspection'
    report=json.loads((ROOT/f'build/package-{args.channel}.json').read_text())
    assert report['zip_name']==package_name(args.channel,report['version'])
    package=ROOT/'releases'/report['zip_name']
    assert sha(package.read_bytes())==report['zip_sha256']
    profile=report['profile']
    assert sha((GAME/'bin/helldivers2.exe').read_bytes())==profile['exe_sha256']
    assert sha((GAME/'data/game/game.dll').read_bytes())==profile['dll_sha256']
    with zipfile.ZipFile(package)as z:
        directory={'v14':'data','v15':'Addon'}[args.channel]
        assert report['data_directory']==directory
        payloads={s:z.read(directory+'/'+ARCHIVE+s) for s in ('','.stream','.gpu_resources')}
    wanted=set(unpack(payloads['']))
    indices=[]
    for path in (GAME/'data').glob(STEM+'.patch_*'):
        match=re.fullmatch(STEM+r'\.patch_(\d+)(?:\.stream|\.gpu_resources)?',path.name)
        if not match:continue
        indices.append(int(match[1]))
        if path.suffix!='.patch_'+match[1]:continue
        raw=path.read_bytes();magic,types,count=struct.unpack_from('<III',raw)
        assert magic==0xf0000011 and types<1000 and count<100000
        assert 72+32*types+count*80<=len(raw)
        existing={struct.unpack_from('<Q',raw,72+32*types+i*80)[0] for i in range(count)}
        assert not existing.intersection(wanted),'Resource conflict with '+path.name
    index=max(indices,default=-1)+1
    files={STEM+'.patch_'+str(index)+s:data for s,data in payloads.items()}
    for name in files:assert not target(name).exists()
    record={'status':'planned','channel':args.channel,'game_directory':str(GAME.resolve()),
            'package_sha256':report['zip_sha256'],'files':{n:sha(d) for n,d in files.items()}}
    JOURNAL.write_text(json.dumps(record,indent=2));require_closed()
    created=[]
    try:
        for name,data in files.items():
            path=target(name)
            with path.open('xb')as f:created.append(path);f.write(data)
        assert all(sha(path.read_bytes())==record['files'][path.name] for path in created)
    except Exception:
        for path in created:
            if path.exists() and sha(path.read_bytes())==record['files'][path.name]:path.unlink()
        record['status']='incomplete';JOURNAL.write_text(json.dumps(record,indent=2));raise
    record['status']='installed';JOURNAL.write_text(json.dumps(record,indent=2))
    print(json.dumps(record,indent=2))

if __name__=='__main__':
    main()
