#!/usr/bin/env python3
"""Generate the native Xcode project without third-party dependencies."""

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "Smalltalk80.xcodeproj"
objects = {}


def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def add(key, isa, **fields):
    identifier = uid(key)
    objects[identifier] = {"isa": isa, **fields}
    return identifier


def encode(value, indent=0):
    tab = "\t" * indent
    if isinstance(value, dict):
        entries = [f"{tab}\t{json.dumps(str(key))} = {encode(item, indent + 1)};" for key, item in value.items()]
        return "{\n" + "\n".join(entries) + f"\n{tab}}}"
    if isinstance(value, list):
        return "(\n" + "\n".join(f"{tab}\t{encode(item, indent + 1)}," for item in value) + f"\n{tab})"
    return json.dumps(str(value), ensure_ascii=False)


def configurations(name, settings):
    refs = []
    for configuration in ["Debug", "Release"]:
        build_settings = dict(settings)
        if name == "Project":
            build_settings.update({
                "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if configuration == "Debug" else "-O",
                "DEBUG_INFORMATION_FORMAT": "dwarf" if configuration == "Debug" else "dwarf-with-dsym",
                "ENABLE_TESTABILITY": "YES" if configuration == "Debug" else "NO",
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)" if configuration == "Debug" else "$(inherited)",
            })
        refs.append(add(f"{name}.{configuration}", "XCBuildConfiguration", name=configuration, buildSettings=build_settings))
    return add(f"{name}.Configurations", "XCConfigurationList", buildConfigurations=refs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")


def swift_sources(target, directory, resource_folders, subdirectory=Path()):
    folder = directory / subdirectory
    refs, builds = [], []
    for source in sorted((ROOT / folder).glob("*.swift")):
        ref = add(f"File.{folder / source.name}", "PBXFileReference", lastKnownFileType="sourcecode.swift", path=source.name, sourceTree="<group>")
        refs.append(ref)
        builds.append(add(f"Build.{target}.{subdirectory / source.name}", "PBXBuildFile", fileRef=ref))
    for child in sorted((ROOT / folder).glob("*")):
        child_path = subdirectory / child.name
        if child_path in resource_folders or child.name.startswith(".") or child.is_symlink() or not child.is_dir():
            continue
        child_refs, child_builds = swift_sources(target, directory, resource_folders, child_path)
        if child_refs:
            refs.append(add(f"Group.{target}.{child_path}", "PBXGroup", children=child_refs, path=child.name, sourceTree="<group>"))
            builds.extend(child_builds)
    return refs, builds


products = {
    "Smalltalk80": ("Smalltalk80.app", "wrapper.application", "com.apple.product-type.application"),
    "SmalltalkCore": ("SmalltalkCore.framework", "wrapper.framework", "com.apple.product-type.framework"),
    "SmalltalkCoreTests": ("SmalltalkCoreTests.xctest", "wrapper.cfbundle", "com.apple.product-type.bundle.unit-test"),
    "Smalltalk80UITests": ("Smalltalk80UITests.xctest", "wrapper.cfbundle", "com.apple.product-type.bundle.ui-testing"),
}
product_refs = {
    name: add(f"Product.{name}", "PBXFileReference", explicitFileType=kind, includeInIndex=0, path=path, sourceTree="BUILT_PRODUCTS_DIR")
    for name, (path, kind, _) in products.items()
}

groups = []
source_phases = {}
resource_builds = {}
for name in products:
    directory = Path("Tests" if name.endswith("Tests") else "Sources") / name
    resource_folders = set()
    resource_refs = []
    resource_builds[name] = []
    if name == "SmalltalkCore":
        path = Path("Library")
        library = add("File.Library", "PBXFileReference", lastKnownFileType="folder", path=str(path), sourceTree="<group>")
        resource_folders.add(path)
        resource_refs.append(library)
        resource_builds[name].append(add("Build.Library", "PBXBuildFile", fileRef=library))
    if name == "Smalltalk80":
        path = Path("Assets.xcassets")
        catalog = add(f"File.{directory / path}", "PBXFileReference", lastKnownFileType="folder.assetcatalog", path=str(path), sourceTree="<group>")
        resource_folders.add(path)
        resource_refs.append(catalog)
        resource_builds[name].append(add("Build.Smalltalk80.Assets.xcassets", "PBXBuildFile", fileRef=catalog))
    refs, builds = swift_sources(name, directory, resource_folders)
    groups.append(add(f"Group.{name}", "PBXGroup", children=refs + resource_refs, name=name, path=str(directory), sourceTree="<group>"))
    source_phases[name] = add(f"Sources.{name}", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=builds, runOnlyForDeploymentPostprocessing=0)

documentation = []
for path, kind in [("README.md", "net.daringfireball.markdown"), ("Package.swift", "sourcecode.swift")]:
    documentation.append(add(f"File.{path}", "PBXFileReference", lastKnownFileType=kind, path=path, sourceTree="<group>"))
products_group = add("Products", "PBXGroup", children=list(product_refs.values()), name="Products", sourceTree="<group>")
main_group = add("MainGroup", "PBXGroup", children=groups + documentation + [products_group], sourceTree="<group>")

common = {
    "SDKROOT": "macosx",
    "MACOSX_DEPLOYMENT_TARGET": "14.0",
    "SWIFT_VERSION": "6.0",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "CLANG_ENABLE_MODULES": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "CODE_SIGN_STYLE": "Manual",
    "CODE_SIGN_IDENTITY": "-",
    "CODE_SIGNING_ALLOWED": "YES",
}
project_configs = configurations("Project", common)
targets = []
for name, (_, _, product_type) in products.items():
    frameworks = []
    dependencies = []
    extra_phases = []
    if name in ["Smalltalk80", "SmalltalkCoreTests"]:
        frameworks.append(add(f"Link.{name}.Core", "PBXBuildFile", fileRef=product_refs["SmalltalkCore"]))
        proxy = add(f"Proxy.{name}.Core", "PBXContainerItemProxy", containerPortal=uid("Project"), proxyType=1, remoteGlobalIDString=uid("Target.SmalltalkCore"), remoteInfo="SmalltalkCore")
        dependencies.append(add(f"Dependency.{name}.Core", "PBXTargetDependency", target=uid("Target.SmalltalkCore"), targetProxy=proxy))
    if name == "Smalltalk80":
        embed = add("Embed.Core", "PBXBuildFile", fileRef=product_refs["SmalltalkCore"], settings={"ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]})
        extra_phases.append(add("Embed.Frameworks", "PBXCopyFilesBuildPhase", buildActionMask=2147483647, dstPath="", dstSubfolderSpec=10, files=[embed], name="Embed Frameworks", runOnlyForDeploymentPostprocessing=0))
    if name == "Smalltalk80UITests":
        proxy = add("Proxy.UI.App", "PBXContainerItemProxy", containerPortal=uid("Project"), proxyType=1, remoteGlobalIDString=uid("Target.Smalltalk80"), remoteInfo="Smalltalk80")
        dependencies.append(add("Dependency.UI.App", "PBXTargetDependency", target=uid("Target.Smalltalk80"), targetProxy=proxy))
    framework_phase = add(f"Frameworks.{name}", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=frameworks, runOnlyForDeploymentPostprocessing=0)
    resource_phase = add(f"Resources.{name}", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=resource_builds[name], runOnlyForDeploymentPostprocessing=0)
    settings = {
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "PRODUCT_BUNDLE_IDENTIFIER": f"dev.moritz.{name}",
        "GENERATE_INFOPLIST_FILE": "YES",
        "CURRENT_PROJECT_VERSION": "1",
        "MARKETING_VERSION": "0.1.0",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks", "@loader_path/../Frameworks", "$(BUILT_PRODUCTS_DIR)"],
    }
    if name == "Smalltalk80":
        settings.update({
            "INFOPLIST_KEY_CFBundleDisplayName": "Smalltalk/80",
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.developer-tools",
            "INFOPLIST_KEY_NSPrincipalClass": "NSApplication",
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            # SmalltalkCore is already signed when it reaches Embed Frameworks.
            "COPY_PHASE_STRIP": "NO",
            "ENABLE_HARDENED_RUNTIME": "YES",
        })
    elif name == "SmalltalkCore":
        settings.update({"DEFINES_MODULE": "YES", "SKIP_INSTALL": "YES", "DYLIB_COMPATIBILITY_VERSION": "1", "DYLIB_CURRENT_VERSION": "1", "INSTALL_PATH": "$(LOCAL_LIBRARY_DIR)/Frameworks", "LD_DYLIB_INSTALL_NAME": "@rpath/$(EXECUTABLE_PATH)"})
    elif name == "Smalltalk80UITests":
        settings["TEST_TARGET_NAME"] = "Smalltalk80"
    target_configs = configurations(name, settings)
    targets.append(add(f"Target.{name}", "PBXNativeTarget", buildConfigurationList=target_configs, buildPhases=[source_phases[name], framework_phase, resource_phase] + extra_phases, buildRules=[], dependencies=dependencies, name=name, productName=name, productReference=product_refs[name], productType=product_type))

add("Project", "PBXProject", attributes={
    "BuildIndependentTargetsInParallel": "YES",
    "LastUpgradeCheck": "2730",
    "TargetAttributes": {uid(f"Target.{name}"): {"CreatedOnToolsVersion": "27.3", **({"TestTargetID": uid("Target.Smalltalk80")} if name == "Smalltalk80UITests" else {})} for name in products},
}, buildConfigurationList=project_configs, compatibilityVersion="Xcode 14.0", developmentRegion="en", hasScannedForEncodings=0, knownRegions=["en", "Base"], mainGroup=main_group, productRefGroup=products_group, projectDirPath="", projectRoot="", targets=targets)

PROJECT.mkdir(exist_ok=True)
(PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n" + encode({"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": uid("Project")}) + "\n")

scheme_dir = PROJECT / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)


def reference(name):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(f"Target.{name}")}" BuildableName="{products[name][0]}" BlueprintName="{name}" ReferencedContainer="container:Smalltalk80.xcodeproj"/>'


scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2730" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference("Smalltalk80")}</BuildActionEntry>
    </BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
    <Testables>
      <TestableReference skipped="NO" parallelizable="NO">{reference("SmalltalkCoreTests")}</TestableReference>
      <TestableReference skipped="NO" parallelizable="NO">{reference("Smalltalk80UITests")}</TestableReference>
    </Testables>
  </TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">{reference("Smalltalk80")}</BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference("Smalltalk80")}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
(scheme_dir / "Smalltalk80.xcscheme").write_text(scheme)
print(f"Generated {PROJECT}")
