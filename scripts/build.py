#!/usr/bin/env python3
"""Build a standalone Apple Silicon macOS application with private FFmpeg libraries."""
import os, pathlib, plistlib, shutil, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]
APP = ROOT / 'build' / 'ClipWeaver.app'
CONTENTS = APP / 'Contents'
BIN = CONTENTS / 'Resources' / 'bin'
LIBS = CONTENTS / 'Frameworks'
for directory in [CONTENTS / 'MacOS', BIN, LIBS]:
    directory.mkdir(parents=True, exist_ok=True)

def run(args, **kw):
    return subprocess.run([str(a) for a in args], check=True, **kw)

def dependencies(path):
    text = subprocess.check_output(['otool', '-L', str(path)], text=True)
    return [line.strip().split(' (')[0] for line in text.splitlines()[1:]]

def copy_file(source, target):
    if target.exists(): target.unlink()
    shutil.copy2(source, target)

copied = {}
queue = []
for name in ['ffmpeg','ffprobe']:
    origin = pathlib.Path(shutil.which(name) or '/opt/homebrew/bin/' + name).resolve()
    target = BIN / name
    copy_file(origin, target)
    queue.append((origin,target))
while queue:
    origin,target = queue.pop(0)
    for dep in dependencies(origin):
        if not dep.startswith('/opt/homebrew/'):
            continue
        source = pathlib.Path(dep).resolve()
        dest = LIBS / source.name
        if source == origin:
            continue
        if source.name not in copied:
            copy_file(source,dest)
            copied[source.name] = source
            queue.append((source,dest))
        elif copied[source.name] != source:
            raise RuntimeError(f'Library filename collision: {source}')
        replacement = ('@loader_path/../../Frameworks/' if target.parent == BIN else '@loader_path/') + source.name
        run(['install_name_tool','-change',dep,replacement,target],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    if target.parent == LIBS:
        run(['install_name_tool','-id','@loader_path/' + target.name,target],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)

skill = CONTENTS / 'Resources' / 'clipweaver-editor'
if skill.exists():
    shutil.rmtree(skill)
shutil.copytree(ROOT / 'skill' / 'clipweaver-editor', skill)
copy_file(ROOT / 'START-HERE.md', CONTENTS / 'Resources' / 'START-HERE.md')
licenses = CONTENTS / 'Resources' / 'Licenses'
licenses.mkdir(exist_ok=True)
# Keep original upstream notices with the private bundled tools and dependencies.
for name, source in {'ffmpeg': pathlib.Path(shutil.which('ffmpeg')).resolve(), **copied}.items():
    parts = source.parts
    if 'Cellar' in parts:
        i = parts.index('Cellar')
        package_root = pathlib.Path(*parts[:i+3])
        for f in package_root.iterdir():
            if f.is_file() and any(x in f.name.upper() for x in ['LICENSE','COPYING','NOTICE','AUTHORS']):
                copy_file(f, licenses / (package_root.parent.name + '-' + f.name))
(licenses/'Bundled-components.txt').write_text('Private local build. FFmpeg uses GPL-enabled libx264 and other upstream components.\nFFmpeg source/build: https://ffmpeg.org/ and Homebrew ffmpeg 8.1.2_1.\nThis folder preserves available installed upstream license notices.\nLibraries:\n' + '\n'.join(str(v) for v in copied.values())+'\n')
if (ROOT/'Assets'/'AppIcon.icns').exists():
    copy_file(ROOT/'Assets'/'AppIcon.icns', CONTENTS/'Resources'/'AppIcon.icns')

info = {
    'CFBundleName':'ClipWeaver','CFBundleDisplayName':'ClipWeaver','CFBundleExecutable':'ClipWeaver',
    'CFBundleIdentifier':'local.clipweaver.studio','CFBundleVersion':'9','CFBundleShortVersionString':'6.1.1',
    'CFBundleIconFile':'AppIcon.icns','CFBundlePackageType':'APPL','LSMinimumSystemVersion':'14.0','NSHighResolutionCapable':True,
    'NSHumanReadableCopyright':'ClipWeaver — personal local video editor',
    'CFBundleDocumentTypes':[{'CFBundleTypeName':'ClipWeaver Project','CFBundleTypeRole':'Editor','CFBundleTypeExtensions':['clipweaver']},{'CFBundleTypeName':'ClipWeaver AI Response','CFBundleTypeRole':'Editor','LSHandlerRank':'Owner','CFBundleTypeExtensions':['clipweaveredit'],'LSItemContentTypes':['local.clipweaver.response']}],
    'UTImportedTypeDeclarations':[{'UTTypeIdentifier':'local.clipweaver.lrf','UTTypeDescription':'DJI Camera Preview','UTTypeConformsTo':['public.movie'],'UTTypeTagSpecification':{'public.filename-extension':['lrf']}},{'UTTypeIdentifier':'local.clipweaver.osv','UTTypeDescription':'DJI Camera Original','UTTypeConformsTo':['public.movie'],'UTTypeTagSpecification':{'public.filename-extension':['osv']}}],
    'UTExportedTypeDeclarations':[{'UTTypeIdentifier':'local.clipweaver.response','UTTypeDescription':'ClipWeaver AI Response','UTTypeConformsTo':['public.data'],'UTTypeTagSpecification':{'public.filename-extension':['clipweaveredit']}}]
}
with (CONTENTS/'Info.plist').open('wb') as f: plistlib.dump(info,f)
(CONTENTS/'PkgInfo').write_text('APPL????')
cache = ROOT / 'build' / 'module-cache'
cache.mkdir(exist_ok=True)
print('Compiling native application…', flush=True)
run(['xcrun','swiftc','-swift-version','5','-O','-target','arm64-apple-macosx14.0','-module-cache-path',cache,'-framework','AppKit','-framework','SwiftUI','-framework','CryptoKit','-framework','AVFoundation',*sorted((ROOT/'Sources').glob('*.swift')),'-o',CONTENTS/'MacOS'/'ClipWeaver'])
for target in [*LIBS.iterdir(),*BIN.iterdir()]:
    run(['codesign','--force','--sign','-',target],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
run(['codesign','--force','--sign','-',APP],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
run(['codesign','--verify','--deep','--strict',APP])
print(APP)
print(f'Bundled {len(copied)} private libraries. No Homebrew or Python required at runtime.')
