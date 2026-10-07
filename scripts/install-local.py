"""Install the local build without touching project or source media folders."""
from pathlib import Path
import datetime, hashlib, plistlib, shutil, subprocess
root=Path(__file__).resolve().parents[1]
source=root/'build/ClipWeaver.app'
destination=Path.home()/'Applications/ClipWeaver.app'
subprocess.run(['codesign','--verify','--deep','--strict',str(source)],check=True)
assert plistlib.loads((source/'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']=='6.1'
backup=root/'build/install-backups'/datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
backup.mkdir(parents=True)
if destination.exists():
 subprocess.run(['/usr/bin/ditto','-c','-k','--sequesterRsrc','--keepParent',str(destination),str(backup/'ClipWeaver-previous.zip')],check=True)
 destination.rename(backup/'previous-app.bundle-backup')
staging=destination.with_name('ClipWeaver-installing.app')
assert not staging.exists(), 'An earlier installation is still staged'
shutil.copytree(source,staging,symlinks=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(staging)],check=True)
staging.rename(destination)
assert hashlib.sha256((source/'Contents/MacOS/ClipWeaver').read_bytes()).digest()==hashlib.sha256((destination/'Contents/MacOS/ClipWeaver').read_bytes()).digest()
skill=Path.home()/'.codex/skills/clipweaver-editor'
if skill.exists():shutil.copytree(skill,backup/'previous-editor-skill')
shutil.copytree(root/'skill/clipweaver-editor',skill,dirs_exist_ok=True)
print('Installed:',destination)
print('Previous application and editor skill backed up:',backup)
