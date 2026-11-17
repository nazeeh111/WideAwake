"""Build a task-owned effects-disabled host for the shipping AppKit panel. No install."""
from pathlib import Path
import sys,shutil,subprocess,plistlib,json,hashlib
repo=Path(__file__).resolve().parents[2]
if len(sys.argv)!=2:raise SystemExit('Choose a NEW private runtime directory outside the repository')
out=Path(sys.argv[1]).expanduser().resolve()
if out.exists():raise SystemExit('Refusing to overwrite runtime: '+str(out))
if repo in out.parents:raise SystemExit('Runtime must be outside the source repository')
sources=out/'Sources/WideAwakeCase';sources.mkdir(parents=True)
shutil.copytree(repo/'Sources/WideAwake',sources,dirs_exist_ok=True)
p=sources/'WideAwakeApp.swift';s=p.read_text();assert s.count('@main @MainActor enum WideAwakeApp')==1;p.write_text(s.replace('@main @MainActor enum WideAwakeApp','@MainActor enum WideAwakeApp',1))
s=(repo/'Tests/WideAwakeTests/TestSupport.swift').read_text().replace('import XCTest\n','').replace('@testable import WideAwake\n','');(sources/'FixtureSupport.swift').write_text(s)
shutil.copy2(Path(__file__).with_name('NativeCase.swift'),sources/'NativeCase.swift')
(out/'Package.swift').write_text('// swift-tools-version:6.2\nimport PackageDescription\nlet package=Package(name:"WideAwakeCase",platforms:[.macOS(.v26)],targets:[.executableTarget(name:"WideAwakeCase")])\n')
subprocess.run(['/usr/bin/swift','build','-c','release','--package-path',str(out)],check=True)
app=out/'WideAwakeCase.app';(app/'Contents/MacOS').mkdir(parents=True);shutil.copy2(out/'.build/release/WideAwakeCase',app/'Contents/MacOS/WideAwakeCase');(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'dev.nazeeh.wideawake.portfolio-case','CFBundleName':'WideAwake Case','CFBundleExecutable':'WideAwakeCase','CFBundleVersion':'1','LSUIElement':True,'NSPrincipalClass':'NSApplication'}));subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(app)],check=True)
(out/'SOURCE.json').write_text(json.dumps({'scope':'Shipping AppKit SliderPanel/MenuBarPanel, ManualLidSession and SessionManager; existing test doubles. AppDelegate/live services never instantiated.','changes':'Only original @main annotation disabled; test-only XCTest/module imports removed; separate case entrypoint added.','source':[{'path':str(p.relative_to(repo)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted((repo/'Sources/WideAwake').rglob('*.swift'))]},indent=2)+'\n')
print(app)
