#!/usr/bin/env python3
"""Generate MDViewer.xcodeproj/project.pbxproj deterministically.

Kept in the repo so the Xcode project can be regenerated after adding files.
"""
import glob
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

_counter = [0]


def oid():
    _counter[0] += 1
    return f"{(0xA << 92) + _counter[0]:024X}"


# Auto-discover sources: adding a .swift file no longer requires editing this
# generator (or the pbxproj by hand).
SWIFT_FILES = sorted(
    p.replace("\\", "/")
    for p in glob.glob("MDViewer/**/*.swift", recursive=True)
)

RESOURCE_DIRS = [
    ("MDViewer/Resources/Assets.xcassets", "folder.assetcatalog"),
    ("MDViewer/Resources/Samples", "folder"),
]

INFO_PLIST = "MDViewer/Resources/Info.plist"

# ---------------------------------------------------------------- object ids
project_id = oid()
main_group_id = oid()
products_group_id = oid()
target_id = oid()
product_ref_id = oid()
sources_phase_id = oid()
frameworks_phase_id = oid()
resources_phase_id = oid()
project_cfg_list_id = oid()
target_cfg_list_id = oid()
proj_debug_id = oid()
proj_release_id = oid()
tgt_debug_id = oid()
tgt_release_id = oid()
info_ref_id = oid()

# groups, one per directory segment
group_ids = {}
for path in SWIFT_FILES + [INFO_PLIST] + [p for p, _ in RESOURCE_DIRS]:
    parts = path.split("/")[:-1]
    for depth in range(1, len(parts) + 1):
        key = "/".join(parts[:depth])
        if key not in group_ids:
            group_ids[key] = oid()

file_refs = {}
build_files = {}
for path in SWIFT_FILES:
    file_refs[path] = oid()
    build_files[path] = oid()
for path, _ in RESOURCE_DIRS:
    file_refs[path] = oid()
    build_files[path] = oid()
file_refs[INFO_PLIST] = oid()

# ------------------------------------------------------------------ pbxproj
L = []
a = L.append

a("// !$*UTF8*$!")
a("{")
a("\tarchiveVersion = 1;")
a("\tclasses = {")
a("\t};")
a("\tobjectVersion = 56;")
a("\tobjects = {")

# PBXBuildFile
a("/* Begin PBXBuildFile section */")
for path in SWIFT_FILES:
    a(f"\t\t{build_files[path]} /* {os.path.basename(path)} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[path]} /* {os.path.basename(path)} */; }};")
for path, _ in RESOURCE_DIRS:
    a(f"\t\t{build_files[path]} /* {os.path.basename(path)} in Resources */ = {{isa = PBXBuildFile; fileRef = {file_refs[path]} /* {os.path.basename(path)} */; }};")
a("/* End PBXBuildFile section */")

# PBXFileReference
a("/* Begin PBXFileReference section */")
a(f"\t\t{product_ref_id} /* MD Viewer.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = \"MD Viewer.app\"; sourceTree = BUILT_PRODUCTS_DIR; }};")
for path in SWIFT_FILES:
    a(f"\t\t{file_refs[path]} /* {os.path.basename(path)} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"{os.path.basename(path)}\"; sourceTree = \"<group>\"; }};")
for path, kind in RESOURCE_DIRS:
    a(f"\t\t{file_refs[path]} /* {os.path.basename(path)} */ = {{isa = PBXFileReference; lastKnownFileType = {kind}; path = \"{os.path.basename(path)}\"; sourceTree = \"<group>\"; }};")
a(f"\t\t{info_ref_id} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};")
a("/* End PBXFileReference section */")

# PBXFrameworksBuildPhase
a("/* Begin PBXFrameworksBuildPhase section */")
a(f"\t\t{frameworks_phase_id} /* Frameworks */ = {{")
a("\t\t\tisa = PBXFrameworksBuildPhase;")
a("\t\t\tbuildActionMask = 2147483647;")
a("\t\t\tfiles = (")
a("\t\t\t);")
a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
a("\t\t};")
a("/* End PBXFrameworksBuildPhase section */")

# PBXGroup
a("/* Begin PBXGroup section */")
a(f"\t\t{main_group_id} = {{")
a("\t\t\tisa = PBXGroup;")
main_children = [group_ids["MDViewer"], products_group_id]
a("\t\t\tchildren = (")
for cid in main_children:
    a(f"\t\t\t\t{cid},")
a("\t\t\t);")
a("\t\t\tsourceTree = \"<group>\";")
a("\t\t};")

# build children of every group: sub-groups first, then files
for key, gid in group_ids.items():
    child_groups = []
    child_files = []
    for sub, subid in group_ids.items():
        if sub.startswith(key + "/") and sub.count("/") == key.count("/") + 1:
            child_groups.append((sub, subid))
    for path in SWIFT_FILES + [INFO_PLIST] + [p for p, _ in RESOURCE_DIRS]:
        if os.path.dirname(path) == key:
            child_files.append(path)
    a(f"\t\t{gid} /* {key.split('/')[-1]} */ = {{")
    a("\t\t\tisa = PBXGroup;")
    a("\t\t\tchildren = (")
    for sub, subid in child_groups:
        a(f"\t\t\t\t{subid} /* {sub.split('/')[-1]} */,")
    for path in child_files:
        a(f"\t\t\t\t{file_refs[path]} /* {os.path.basename(path)} */,")
    a("\t\t\t);")
    a(f"\t\t\tpath = \"{key.split('/')[-1]}\";")
    a("\t\t\tsourceTree = \"<group>\";")
    a("\t\t};")

a(f"\t\t{products_group_id} /* Products */ = {{")
a("\t\t\tisa = PBXGroup;")
a("\t\t\tchildren = (")
a(f"\t\t\t\t{product_ref_id} /* MD Viewer.app */,")
a("\t\t\t);")
a("\t\t\tname = Products;")
a("\t\t\tsourceTree = \"<group>\";")
a("\t\t};")
a("/* End PBXGroup section */")

# PBXNativeTarget
a("/* Begin PBXNativeTarget section */")
a(f"\t\t{target_id} /* MDViewer */ = {{")
a("\t\t\tisa = PBXNativeTarget;")
a(f"\t\t\tbuildConfigurationList = {target_cfg_list_id} /* Build configuration list for PBXNativeTarget \"MDViewer\" */;")
a("\t\t\tbuildPhases = (")
a(f"\t\t\t\t{sources_phase_id} /* Sources */,")
a(f"\t\t\t\t{frameworks_phase_id} /* Frameworks */,")
a(f"\t\t\t\t{resources_phase_id} /* Resources */,")
a("\t\t\t);")
a("\t\t\tbuildRules = (")
a("\t\t\t);")
a("\t\t\tdependencies = (")
a("\t\t\t);")
a("\t\t\tname = MDViewer;")
a("\t\t\tproductName = MDViewer;")
a(f"\t\t\tproductReference = {product_ref_id} /* MD Viewer.app */;")
a("\t\t\tproductType = \"com.apple.product-type.application\";")
a("\t\t};")
a("/* End PBXNativeTarget section */")

# PBXProject
a("/* Begin PBXProject section */")
a(f"\t\t{project_id} /* Project object */ = {{")
a("\t\t\tisa = PBXProject;")
a("\t\t\tattributes = {")
a("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
a("\t\t\t\tLastSwiftUpdateCheck = 2720;")
a("\t\t\t\tLastUpgradeCheck = 2720;")
a(f"\t\t\t\tTargetAttributes = {{ {target_id} = {{ CreatedOnToolsVersion = 27.2; }}; }};")
a("\t\t\t};")
a(f"\t\t\tbuildConfigurationList = {project_cfg_list_id} /* Build configuration list for PBXProject \"MDViewer\" */;")
a("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
a("\t\t\tdevelopmentRegion = en;")
a("\t\t\thasScannedForEncodings = 0;")
a('\t\t\tknownRegions = (en, Base, "zh-Hans",);')
a(f"\t\t\tmainGroup = {main_group_id};")
a(f"\t\t\tproductRefGroup = {products_group_id} /* Products */;")
a("\t\t\tprojectDirPath = \"\";")
a("\t\t\tprojectRoot = \"\";")
a("\t\t\ttargets = (")
a(f"\t\t\t\t{target_id} /* MDViewer */,")
a("\t\t\t);")
a("\t\t};")
a("/* End PBXProject section */")

# PBXResourcesBuildPhase
a("/* Begin PBXResourcesBuildPhase section */")
a(f"\t\t{resources_phase_id} /* Resources */ = {{")
a("\t\t\tisa = PBXResourcesBuildPhase;")
a("\t\t\tbuildActionMask = 2147483647;")
a("\t\t\tfiles = (")
for path, _ in RESOURCE_DIRS:
    a(f"\t\t\t\t{build_files[path]} /* {os.path.basename(path)} in Resources */,")
a("\t\t\t);")
a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
a("\t\t};")
a("/* End PBXResourcesBuildPhase section */")

# PBXSourcesBuildPhase
a("/* Begin PBXSourcesBuildPhase section */")
a(f"\t\t{sources_phase_id} /* Sources */ = {{")
a("\t\t\tisa = PBXSourcesBuildPhase;")
a("\t\t\tbuildActionMask = 2147483647;")
a("\t\t\tfiles = (")
for path in SWIFT_FILES:
    a(f"\t\t\t\t{build_files[path]} /* {os.path.basename(path)} in Sources */,")
a("\t\t\t);")
a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
a("\t\t};")
a("/* End PBXSourcesBuildPhase section */")

# XCBuildConfiguration
a("/* Begin XCBuildConfiguration section */")

common_project = [
    "ALWAYS_SEARCH_USER_PATHS = NO;",
    "CLANG_ANALYZER_NONNULL = YES;",
    "CLANG_ENABLE_MODULES = YES;",
    "CLANG_ENABLE_OBJC_ARC = YES;",
    "COPY_PHASE_STRIP = NO;",
    "ENABLE_STRICT_OBJC_MSGSEND = YES;",
    "ENABLE_USER_SCRIPT_SANDBOXING = YES;",
    "GCC_C_LANGUAGE_STANDARD = gnu17;",
    "GCC_NO_COMMON_BLOCKS = YES;",
    "IPHONEOS_DEPLOYMENT_TARGET = 26.0;",
    "MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;",
    "MTL_FAST_MATH = YES;",
    "ONLY_ACTIVE_ARCH = YES;",
    "SDKROOT = iphoneos;",
    "SWIFT_STRICT_CONCURRENCY = minimal;",
    "SWIFT_VERSION = 5.0;",
    "TARGETED_DEVICE_FAMILY = \"1,2\";",
]

common_target = [
    "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;",
    "CODE_SIGN_STYLE = Automatic;",
    "CURRENT_PROJECT_VERSION = 1;",
    "DEVELOPMENT_ASSET_PATHS = \"\";",
    "GENERATE_INFOPLIST_FILE = NO;",
    "INFOPLIST_FILE = MDViewer/Resources/Info.plist;",
    "MARKETING_VERSION = 1.0;",
    "PRODUCT_BUNDLE_IDENTIFIER = app.mdviewer.ios;",
    "PRODUCT_NAME = \"MD Viewer\";",
    "SUPPORTED_PLATFORMS = \"iphoneos iphonesimulator\";",
    "SWIFT_EMIT_LOC_STRINGS = YES;",
    "SWIFT_STRICT_CONCURRENCY = minimal;",
    "SWIFT_VERSION = 5.0;",
    "TARGETED_DEVICE_FAMILY = \"1,2\";",
]


def cfg(ident, name, lines):
    a(f"\t\t{ident} /* {name} */ = {{")
    a("\t\t\tisa = XCBuildConfiguration;")
    a("\t\t\tbuildSettings = {")
    for line in lines:
        a(f"\t\t\t\t{line}")
    a("\t\t\t};")
    a(f"\t\t\tname = {name};")
    a("\t\t};")


cfg(proj_debug_id, "Debug", common_project + [
    "DEBUG_INFORMATION_FORMAT = dwarf;",
    "ENABLE_TESTABILITY = YES;",
    "GCC_OPTIMIZATION_LEVEL = 0;",
    "GCC_PREPROCESSOR_DEFINITIONS = (\"DEBUG=1\", \"$(inherited)\",);",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS = \"DEBUG $(inherited)\";",
    "SWIFT_OPTIMIZATION_LEVEL = \"-Onone\";",
])
cfg(proj_release_id, "Release", common_project + [
    "DEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";",
    "GCC_OPTIMIZATION_LEVEL = s;",
    "SWIFT_COMPILATION_MODE = wholemodule;",
    "SWIFT_OPTIMIZATION_LEVEL = \"-O\";",
    "VALIDATE_PRODUCT = YES;",
])
cfg(tgt_debug_id, "Debug", common_target)
cfg(tgt_release_id, "Release", common_target)
a("/* End XCBuildConfiguration section */")

# XCConfigurationList
a("/* Begin XCConfigurationList section */")
for ident, comment, d, r in [
    (project_cfg_list_id, 'Build configuration list for PBXProject "MDViewer"', proj_debug_id, proj_release_id),
    (target_cfg_list_id, 'Build configuration list for PBXNativeTarget "MDViewer"', tgt_debug_id, tgt_release_id),
]:
    a(f"\t\t{ident} /* {comment} */ = {{")
    a("\t\t\tisa = XCConfigurationList;")
    a("\t\t\tbuildConfigurations = (")
    a(f"\t\t\t\t{d} /* Debug */,")
    a(f"\t\t\t\t{r} /* Release */,")
    a("\t\t\t);")
    a("\t\t\tdefaultConfigurationIsVisible = 0;")
    a("\t\t\tdefaultConfigurationName = Release;")
    a("\t\t};")
a("/* End XCConfigurationList section */")

a("\t};")
a(f"\trootObject = {project_id} /* Project object */;")
a("}")

out = "MDViewer.xcodeproj/project.pbxproj"
with open(out, "w", encoding="utf-8") as f:
    f.write("\n".join(L) + "\n")
print("wrote", out, "with", _counter[0], "objects")

scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2720" version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
            <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_id}" BuildableName="MD Viewer.app" BlueprintName="MDViewer" ReferencedContainer="container:MDViewer.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_id}" BuildableName="MD Viewer.app" BlueprintName="MDViewer" ReferencedContainer="container:MDViewer.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_id}" BuildableName="MD Viewer.app" BlueprintName="MDViewer" ReferencedContainer="container:MDViewer.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration="Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES">
   </ArchiveAction>
</Scheme>
'''
scheme_out = "MDViewer.xcodeproj/xcshareddata/xcschemes/MDViewer.xcscheme"
with open(scheme_out, "w", encoding="utf-8") as f:
    f.write(scheme)
print("wrote", scheme_out)
