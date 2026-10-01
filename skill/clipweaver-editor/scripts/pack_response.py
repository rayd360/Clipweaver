#!/usr/bin/env python3
"""Create one self-contained ClipWeaver response. Standard library only.
Usage: pack_response.py choices.json manifest.json asset_directory output.clipweaveredit
"""
import base64, hashlib, json, os, pathlib, sys, tempfile
from validate_edit import validate

def pack(edit_path, manifest_path, asset_dir, output):
    edit=json.loads(pathlib.Path(edit_path).read_text()); manifest=json.loads(pathlib.Path(manifest_path).read_text())
    choices=edit if isinstance(edit,list) else [edit]
    errors=validate(edit,manifest)
    if errors: raise ValueError('; '.join(errors))
    names=set()
    for choice in choices:
        names.update(o['filename'] for o in choice.get('overlays',[]) if o.get('filename'))
        if choice.get('music'): names.add(choice['music']['filename'])
        if (choice.get('end_card') or {}).get('filename'): names.add(choice['end_card']['filename'])
    if len({n.lower() for n in names}) != len(names): raise ValueError("Asset names must be unique ignoring case")
    assets=[]; total=0
    for name in sorted(names):
        if not isinstance(name,str) or '/' in name or '\\' in name or name in {'.','..'}: raise ValueError('Asset names must be basenames')
        if pathlib.Path(name).suffix.lower() not in [".png",".jpg",".jpeg",".m4a",".mp3",".wav",".aac"]: raise ValueError("Unsupported response asset format")
        data=(pathlib.Path(asset_dir)/name).read_bytes(); total+=len(data)
        if not data or total>100*1024*1024: raise ValueError('Assets are empty or exceed 100 MB total')
        assets.append(dict(filename=name,sha256=hashlib.sha256(data).hexdigest(),base64=base64.b64encode(data).decode('ascii')))
    payload=json.dumps(dict(package_version=2,edits=choices,assets=assets) if isinstance(edit,list) else dict(package_version=1,edit=edit,assets=assets),ensure_ascii=False,separators=(',',':')).encode('utf-8')
    out=pathlib.Path(output)
    if out.suffix!='.clipweaveredit': raise ValueError('Output extension must be .clipweaveredit')
    out.parent.mkdir(parents=True,exist_ok=True)
    fd,tmp=tempfile.mkstemp(prefix='.response-',suffix='.tmp',dir=out.parent)
    try:
        with os.fdopen(fd,'wb') as f:f.write(payload)
        os.replace(tmp,out)
    finally:
        if os.path.exists(tmp):os.unlink(tmp)
    print(f'Ready: {out} ({len(payload):,} bytes; {len(assets)} embedded assets)')
if __name__=='__main__':
    try:
        if len(sys.argv)!=5:raise ValueError(__doc__)
        pack(*sys.argv[1:])
    except (OSError,ValueError,KeyError,TypeError) as e:sys.exit(str(e))
