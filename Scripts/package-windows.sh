#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist/NOIR-Audio-Windows
binary=${1:-Build/windows/Windows/NOIR Audio.exe}
cp "$binary" 'dist/NOIR-Audio-Windows/NOIR Audio.exe'
if [ -z "${1:-}" ] && command -v x86_64-w64-mingw32-strip >/dev/null; then
  x86_64-w64-mingw32-strip --strip-unneeded 'dist/NOIR-Audio-Windows/NOIR Audio.exe'
fi
python3 - <<'PYBUILD'
from pathlib import Path
import hashlib,os
p=Path('dist/NOIR-Audio-Windows/NOIR Audio.exe')
info='NOIR Audio 0.1.0 - Windows x64 preview\nSource: https://github.com/xeyuu0/noir-audio\nBuild commit: '+os.environ.get('NOIR_WINDOWS_COMMIT','local cross-build')+'\nExecutable SHA-256: '+hashlib.sha256(p.read_bytes()).hexdigest()+'\n'
Path('dist/NOIR-Audio-Windows/BUILD-INFO.txt').write_text(info)
PYBUILD
cp Windows/README.md dist/NOIR-Audio-Windows/README.md
cp LICENSE dist/NOIR-Audio-Windows/LICENSE.txt
cp ThirdParty/OctopusEAX/LICENSE dist/NOIR-Audio-Windows/OctopusEAX-LICENSE.txt
python3 - <<'PY'
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
with ZipFile('dist/NOIR-Audio-0.1.0-Windows-x64.zip','w',ZIP_DEFLATED,compresslevel=9) as z:
    for p in sorted(Path('dist/NOIR-Audio-Windows').iterdir()):
        z.write(p,Path('NOIR Audio')/p.name)
PY
(cd Windows && makensis -V2 installer.nsi)
echo 'Built the portable Windows ZIP and per-user setup executable.'
