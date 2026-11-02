#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist/NOIR-Audio-Windows
cp 'Build/windows/Windows/NOIR Audio.exe' 'dist/NOIR-Audio-Windows/NOIR Audio.exe'
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
