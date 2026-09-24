#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Jory Shilmover
"""Deterministic minimal Xcode project; root owns this generator and project."""
from pathlib import Path
import hashlib, sys
root = Path(__file__).resolve().parent.parent
project = root / 'DuoDS.xcodeproj'
project.mkdir(exist_ok=True)
def ident(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def q(s): return '"' + str(s).replace('\\','\\\\').replace('"','\\"') + '"'
objects=[]
def obj(key, value): objects.append(f'{ident(key)} = {{ {value} }};'); return ident(key)
sources=[]
for folder in ['App','Shared','Emulator','Platform','Features']:
    for p in sorted((root/folder).rglob('*')):
        if p.suffix not in ['.swift','.cpp','.mm','.m','.c']: continue
        path=p.relative_to(root).as_posix()
        typ={'.swift':'sourcecode.swift','.cpp':'sourcecode.cpp.cpp','.mm':'sourcecode.cpp.objcpp','.m':'sourcecode.c.objc','.c':'sourcecode.c.c'}[p.suffix]
        f=obj(path, f'isa = PBXFileReference; lastKnownFileType = {typ}; path = {q(path)}; sourceTree = SOURCE_ROOT;')
        b=obj('build:'+path, f'isa = PBXBuildFile; fileRef = {f};')
        sources.append((f,b))
product=obj('product','isa = PBXFileReference; explicitFileType = wrapper.application; path = DuoDS.app; sourceTree = BUILT_PRODUCTS_DIR;')
group=obj('group',f'isa = PBXGroup; children = ({",".join([f for f,b in sources]+[product])}); sourceTree = "<group>";')
phase=obj('sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(b for f,b in sources)}); runOnlyForDeploymentPostprocessing = 0;')
frameworks=obj('frameworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
resource_builds=[]
resource_paths=['Dependencies/CORE-NOTICES.txt']
if '--diagnostic' in sys.argv: resource_paths.append('build/fixtures/duo-diagnostic.nds')
for path in resource_paths:
    if not (root/path).exists(): continue
    rf=obj('resource:'+path, f'isa = PBXFileReference; lastKnownFileType = file; path = {q(path)}; sourceTree = SOURCE_ROOT;')
    resource_builds.append(obj('rb:'+path, f'isa = PBXBuildFile; fileRef = {rf};'))
resources=obj('resources', 'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ('+','.join(resource_builds)+'); runOnlyForDeploymentPostprocessing = 0;')
settings={
 'PRODUCT_BUNDLE_IDENTIFIER':'org.duods.prototype','PRODUCT_NAME':'DuoDS','SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'17.0',
 'TARGETED_DEVICE_FAMILY':'1,2','SWIFT_VERSION':'5.0','CLANG_CXX_LANGUAGE_STANDARD':'c++17','CLANG_ENABLE_MODULES':'YES',
 'GENERATE_INFOPLIST_FILE':'YES','INFOPLIST_KEY_UILaunchScreen_Generation':'YES','INFOPLIST_KEY_UIApplicationSceneManifest_Generation':'YES',
 'INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents':'YES','INFOPLIST_FILE':'App/Info.plist','INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace':'YES','INFOPLIST_KEY_NSMicrophoneUsageDescription':'Enable microphone input for the Nintendo DS game you are playing.',
 'INFOPLIST_KEY_UISupportedInterfaceOrientations':'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight UIInterfaceOrientationPortraitUpsideDown',
 'CODE_SIGN_STYLE':'Automatic','SWIFT_OBJC_BRIDGING_HEADER':'Emulator/CoreBridge/include/DuoCore.h',
 'HEADER_SEARCH_PATHS':'$(inherited) "$(SRCROOT)/Emulator/CoreBridge/include"',
 'SWIFT_OPTIMIZATION_LEVEL':'-O','ENABLE_USER_SCRIPT_SANDBOXING':'NO',
}
# Build scripts supply static archives and dependency headers through generated xcconfig.
configref=obj('configfile','isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = build/Core.xcconfig; sourceTree = SOURCE_ROOT;')
configs=[]
for name in ['Debug','Release']:
 s=dict(settings)
 if name=='Debug': s['SWIFT_OPTIMIZATION_LEVEL']='-Onone'
 configs.append(obj('config'+name,'isa = XCBuildConfiguration; baseConfigurationReference = '+configref+'; buildSettings = {'+''.join(k+' = '+q(v)+';' for k,v in s.items())+'}; name = '+name+';'))
cl=obj('configs','isa = XCConfigurationList; buildConfigurations = ('+','.join(configs)+'); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target=obj('target',f'isa = PBXNativeTarget; buildConfigurationList = {cl}; buildPhases = ({phase},{frameworks},{resources}); buildRules = (); dependencies = (); name = DuoDS; productName = DuoDS; productReference = {product}; productType = "com.apple.product-type.application";')
proj=obj('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2710; }}; buildConfigurationList = {cl}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base); mainGroup = {group}; projectDirPath = ""; projectRoot = ""; targets = ({target});')
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {proj};}}\n')
scheme=project/'xcshareddata/xcschemes'; scheme.mkdir(parents=True,exist_ok=True)
ref=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="DuoDS.app" BlueprintName="DuoDS" ReferencedContainer="container:DuoDS.xcodeproj"/>'
(scheme/'DuoDS.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2710" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
