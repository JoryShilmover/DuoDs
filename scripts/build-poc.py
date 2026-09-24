#!/usr/bin/env python3
import argparse, json, os, subprocess, sys
from pathlib import Path
root=Path(__file__).resolve().parent.parent
os.chdir(root)
p=argparse.ArgumentParser()
p.add_argument('--sdk',choices=['iphonesimulator','iphoneos'],default='iphonesimulator')
p.add_argument('--configuration',default='Release',choices=['Debug','Release'])
p.add_argument('--scheme',default='DuoDS')
p.add_argument('--destination',default=None)
p.add_argument('--team',default=None)
p.add_argument('--skip-core',action='store_true')
p.add_argument('--diagnostic',action='store_true',help='Include locally authored diagnostic built from assembly')
a=p.parse_args()
def run(args): print('+',args,flush=True);subprocess.run([str(x) for x in args],check=True)
cmake=root/'build/tools/bin/cmake'
if not cmake.exists(): raise SystemExit('Run scripts/bootstrap-tools.sh first.')
if not a.skip_core: run([sys.executable,'scripts/fetch-dependencies.py'])
build=root/('build/core-simulator' if a.sdk=='iphonesimulator' else 'build/core-device')
if not a.skip_core:
    args=[cmake,'-S',root/'build/dependencies/melonds-ds','-B',build,'-G','Ninja','-DCMAKE_MAKE_PROGRAM='+str(root/'build/tools/bin/ninja'),'-DCMAKE_SYSTEM_NAME=iOS','-DCMAKE_OSX_SYSROOT='+a.sdk,'-DCMAKE_OSX_ARCHITECTURES=arm64','-DCMAKE_OSX_DEPLOYMENT_TARGET=17.0','-DCMAKE_BUILD_TYPE=Release','-DBUILD_AS_STATIC_LIBRARY=ON','-DENABLE_JIT=OFF','-DENABLE_OPENGL=OFF','-DENABLE_NETWORKING=OFF','-DENABLE_DYNAMIC=OFF','-DBUILD_TESTING=OFF','-DENABLE_LTO_RELEASE=OFF','-DENABLE_LTO=OFF','-DFETCHCONTENT_BASE_DIR='+str(build/'_deps'),'-DCMAKE_MODULE_PATH='+str(root/'build/dependencies/fetched/embed-binaries-src/cmake')+';'+str(root/'build/dependencies/fetched/melonds-src/cmake'),'-DFETCHCONTENT_FULLY_DISCONNECTED=ON']
    for dep in json.loads((root/'Dependencies/lock.json').read_text())['dependencies'][1:]:
        args.append('-DFETCHCONTENT_SOURCE_DIR_'+dep['name'].upper()+'='+str(root/dep['path']))
    run(args);run([cmake,'--build',build,'--target','melondsds_libretro','-j','8'])
archives=sorted(build.rglob('*.a'))
# Upstream gives even static cores the platform's dynamic-library suffix.
core=build/'src/libretro/melondsds_libretro.dylib'
if core.exists(): archives.append(core)
if not archives: raise SystemExit('No built core archives found.')
# Use one combined archive; no runtime-loaded executable core.
combined=build/'libDuoCoreCombined.a'
archives=[x for x in archives if x!=combined]
run(['xcrun','libtool','-static','-o',combined,*archives])
(root/'build/Core.xcconfig').write_text('OTHER_LDFLAGS = $(inherited) "'+str(combined)+'" -lc++ -lz\nHEADER_SEARCH_PATHS = $(inherited) "$(SRCROOT)/build/dependencies/fetched/libretro-common-src/include"\n')
if a.diagnostic:run([sys.executable,'scripts/build-fixture.py'])
run([sys.executable,'scripts/generate-project.py']+(['--diagnostic'] if a.diagnostic else []))
dest=a.destination or ('generic/platform=iOS Simulator' if a.sdk=='iphonesimulator' else 'generic/platform=iOS')
args=['xcodebuild','-project','DuoDS.xcodeproj','-scheme',a.scheme,'-configuration',a.configuration,'-sdk',a.sdk,'-destination',dest,'-derivedDataPath','build/DerivedData','ARCHS=arm64']
# Automatic signing needs Xcode to create/refresh the development profile for the device.
if a.team: args+=['DEVELOPMENT_TEAM='+a.team,'-allowProvisioningUpdates','-allowProvisioningDeviceRegistration']
else: args+=['CODE_SIGNING_ALLOWED=NO']
run(args+['build'])
