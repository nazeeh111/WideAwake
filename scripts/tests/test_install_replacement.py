from pathlib import Path
import tempfile,subprocess,shutil
source=(Path(__file__).resolve().parents[1]/'install.sh').read_text()
a=source.index('# Stage and verify');b=source.index('# 4. Backstop',a);block=source[a:b]
for mode in ['success','copy-failure','verify-failure','publish-failure']:
 root=Path(tempfile.mkdtemp(prefix='wideawake-install-check-'))
 appdir=root/'Applications';appdir.mkdir();app=appdir/'WideAwake.app';app.mkdir();(app/'bytes').write_text('old')
 pre=root/'new.app';pre.mkdir();(pre/'bytes').write_text('new')
 verify=root/'codesign';verify.write_text('#!/bin/bash\nexit '+('1' if mode=='verify-failure' else '0')+'\n');verify.chmod(0o700)
 setup='set -euo pipefail\n'
 import shlex
 for key,val in {'APP_DIR':appdir,'APP':app,'PREBUILT':pre,'CODESIGN':verify}.items():setup+=key+'='+shlex.quote(str(val))+'\n'
 if mode=='copy-failure':setup+='cp() { return 1; }\n'
 if mode=='publish-failure':setup+='mv() { if [[ "$1" == *".WideAwake.stage."* ]]; then return 1; fi; /bin/mv "$@"; }\n'
 result=subprocess.run(['/bin/bash'],input=setup+block,text=True,capture_output=True)
 assert result.returncode==(0 if mode=='success' else 1),(mode,result.stderr)
 assert (app/'bytes').read_text()==('new' if mode=='success' else 'old'),mode
 if mode=='success':assert next(appdir.glob('.WideAwake.previous.*/WideAwake.app/bytes')).read_text()=='old'
 print(mode,'passed')
 shutil.rmtree(root)
