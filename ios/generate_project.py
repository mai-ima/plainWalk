#!/usr/bin/env python3
"""Generate the Xcode project using only Python's standard library. No credentials."""
from pathlib import Path
import hashlib, plistlib, json
ROOT=Path(__file__).resolve().parent
objects={}
def uid(key): return hashlib.sha1(key.encode()).hexdigest()[:24].upper()
def q(s): return json.dumps(s, ensure_ascii=False)
def add(key, text): objects[uid(key)]=text; return uid(key)
app_sources=[*sorted((ROOT/'PlainWalk').glob('*.swift')),ROOT/'Shared/WalkActivityAttributes.swift']
live_sources=[ROOT/'PlainWalkLive/PlainWalkLive.swift',ROOT/'Shared/WalkActivityAttributes.swift']
all_sources=sorted(set(app_sources+live_sources))
refs={p:add('file:'+str(p.relative_to(ROOT)),f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(str(p.relative_to(ROOT)))}; sourceTree = "<group>";') for p in all_sources}
asset=add('assets','isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = PlainWalk/Assets.xcassets; sourceTree = "<group>";')
privacy=add('privacy','isa = PBXFileReference; lastKnownFileType = text.xml; path = PlainWalk/PrivacyInfo.xcprivacy; sourceTree = "<group>";')
app_product=add('app-product','isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = PlainWalk.app; sourceTree = BUILT_PRODUCTS_DIR;')
live_product=add('live-product','isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = PlainWalkLive.appex; sourceTree = BUILT_PRODUCTS_DIR;')
products=add('products',f'isa = PBXGroup; children = ({app_product}, {live_product},); name = Products; sourceTree = "<group>";')
main=add('main',f'isa = PBXGroup; children = ({", ".join(refs.values())}, {asset}, {privacy}, {products},); sourceTree = "<group>";')
source_phases={}
for target,files in [('app',app_sources),('live',live_sources)]:
 builds=[add(f'build:{target}:{p.name}',f'isa = PBXBuildFile; fileRef = {refs[p]};') for p in files]
 source_phases[target]=add(target+'sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(builds)},); runOnlyForDeploymentPostprocessing = 0;')
asset_build=add('assetbuild',f'isa = PBXBuildFile; fileRef = {asset};')
privacy_build=add('privacy-build',f'isa = PBXBuildFile; fileRef = {privacy};')
resources=add('resources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({asset_build}, {privacy_build},); runOnlyForDeploymentPostprocessing = 0;')
script='set -eu\nWEB_SOURCE="$SRCROOT/../dist"\nWEB_DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Web"\ntest -f "$WEB_SOURCE/index.html"\ntest -f "$WEB_SOURCE/data/japan-municipalities.geojson" || { echo "Run npm run build before building iOS"; exit 1; }\nmkdir -p "$WEB_DEST"\n/usr/bin/ditto "$WEB_SOURCE" "$WEB_DEST"\n'
copy_web=add('copy-web',f'isa = PBXShellScriptBuildPhase; buildActionMask = 2147483647; files = (); inputPaths = (); outputPaths = (); alwaysOutOfDate = 1; name = "Bundle Web application"; runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/sh; shellScript = {q(script)};')
embed_build=add('embedbuild',f'isa = PBXBuildFile; fileRef = {live_product}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, );}};')
embed=add('embed',f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = ({embed_build},); name = "Embed App Extensions"; runOnlyForDeploymentPostprocessing = 0;')
proxy=add('proxy',f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("live-target")}; remoteInfo = PlainWalkLive;')
dep=add('dependency',f'isa = PBXTargetDependency; target = {uid("live-target")}; targetProxy = {proxy};')
configs={}
for kind in ['project','app','live']:
 ids=[]
 for mode in ['Debug','Release']:
  settings={'IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'iphoneos','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','ENABLE_USER_SCRIPT_SANDBOXING':'NO'}
  if kind!='project':
   settings.update({'CODE_SIGN_STYLE':'Automatic','CURRENT_PROJECT_VERSION':'2','MARKETING_VERSION':'0.3.0','TARGETED_DEVICE_FAMILY':'1,2','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','PRODUCT_NAME':'$(TARGET_NAME)','GENERATE_INFOPLIST_FILE':'NO','INFOPLIST_FILE':'PlainWalk/Info.plist' if kind=='app' else 'PlainWalkLive/Info.plist','PRODUCT_BUNDLE_IDENTIFIER':'org.example.plainwalkweb' + ('.Live' if kind=='live' else '')})
   if kind=='app':settings.update({'CODE_SIGN_ENTITLEMENTS':'PlainWalk/PlainWalk.entitlements','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks'})
   else:settings.update({'SKIP_INSTALL':'YES','APPLICATION_EXTENSION_API_ONLY':'YES','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'})
  if mode=='Debug':settings.update({'SWIFT_OPTIMIZATION_LEVEL':'-Onone','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG'})
  else:settings['SWIFT_COMPILATION_MODE']='wholemodule'
  config=add(kind+mode,'isa = XCBuildConfiguration; buildSettings = {'+' '.join(f'{k} = {q(v)};' for k,v in settings.items())+'}; name = '+mode+';');ids.append(config)
 configs[kind]=add(kind+'configlist',f'isa = XCConfigurationList; buildConfigurations = ({", ".join(ids)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
add('app-target',f'isa = PBXNativeTarget; buildConfigurationList = {configs["app"]}; buildPhases = ({source_phases["app"]}, {resources}, {copy_web}, {embed},); buildRules = (); dependencies = ({dep},); name = PlainWalk; productName = PlainWalk; productReference = {app_product}; productType = "com.apple.product-type.application";')
add('live-target',f'isa = PBXNativeTarget; buildConfigurationList = {configs["live"]}; buildPhases = ({source_phases["live"]},); buildRules = (); dependencies = (); name = PlainWalkLive; productName = PlainWalkLive; productReference = {live_product}; productType = "com.apple.product-type.app-extension";')
add('project',f'isa = PBXProject; attributes = {{LastUpgradeCheck = 1600; BuildIndependentTargetsInParallel = YES; TargetAttributes = {{{uid("app-target")} = {{SystemCapabilities = {{com.apple.BackgroundModes = {{enabled = 1;}}; com.apple.HealthKit = {{enabled = 1;}};}};}};}};}}; buildConfigurationList = {configs["project"]}; compatibilityVersion = "Xcode 14.0"; developmentRegion = ja; hasScannedForEncodings = 0; knownRegions = (ja, en, Base,); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({uid("app-target")}, {uid("live-target")},);')
project=ROOT/'PlainWalk.xcodeproj';project.mkdir(exist_ok=True)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(f'{k} = {{{v}}};' for k,v in sorted(objects.items()))+'\n}; rootObject = '+uid('project')+'; }\n')
shared=project/'xcshareddata/xcschemes';shared.mkdir(parents=True,exist_ok=True)
(shared/'PlainWalk.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?><Scheme LastUpgradeVersion="1600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('app-target')}" BuildableName="PlainWalk.app" BlueprintName="PlainWalk" ReferencedContainer="container:PlainWalk.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('app-target')}" BuildableName="PlainWalk.app" BlueprintName="PlainWalk" ReferencedContainer="container:PlainWalk.xcodeproj"/></BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print('Generated', project)
