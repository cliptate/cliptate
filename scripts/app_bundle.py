"""Build a relocatable macOS application from the locked Swift package."""

import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def settings(root=ROOT, environment=None):
    env = os.environ if environment is None else environment
    values = json.loads((root / "config/app.json").read_text())
    # Preserve existing local update/team settings without evaluating code.
    legacy = root / "config/Local.xcconfig"
    if legacy.exists():
        for line in legacy.read_text().splitlines():
            match = re.fullmatch(r"\s*(CLIPTATE_\w+)\s*=\s*(.*?)\s*", line)
            if match and (match[1] in values or match[1] == "CLIPTATE_DEVELOPMENT_TEAM"):
                values[match[1]] = match[2].replace("$()", "")
    local = root / "config/Local.json"
    if local.exists():
        values.update({key: value for key, value in json.loads(local.read_text()).items()
                       if key in values or key == "CLIPTATE_DEVELOPMENT_TEAM"})
    values.update({key: value for key, value in env.items()
                   if key in values or key in {"CLIPTATE_DEVELOPMENT_TEAM"}})
    if any(not isinstance(value, str) for value in values.values()):
        raise ValueError("App configuration values must be strings")
    configuration = env.get("CONFIGURATION", "Debug")
    if configuration not in {"Debug", "Release"}:
        raise ValueError("CONFIGURATION must be Debug or Release")
    development = configuration == "Debug"
    values.update({
        "CONFIGURATION": configuration,
        "PRODUCT_NAME": "Cliptate Dev" if development else "Cliptate",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.cliptate.dev" if development else "com.cliptate.app",
        "CLIPTATE_CLI_URL_SCHEME": "cliptate-dev-cli" if development else "cliptate-cli",
    })
    if development:
        values["CLIPTATE_UPDATES_ENABLED"] = "NO"
    return values


def expand(value, values):
    if isinstance(value, str):
        return re.sub(r"\$\((\w+)\)", lambda match: values[match[1]], value)
    if isinstance(value, dict):
        return {key: expand(item, values) for key, item in value.items()}
    if isinstance(value, list):
        return [expand(item, values) for item in value]
    return value


def info_plist(values, root=ROOT):
    info = expand(plistlib.loads((root / "Sources/Cliptate/Info.plist").read_bytes()), values)
    info.update({
        "CFBundleIdentifier": values["PRODUCT_BUNDLE_IDENTIFIER"],
        "CFBundleName": values["PRODUCT_NAME"],
        "CFBundleDisplayName": values["PRODUCT_NAME"],
        "CFBundleExecutable": values["PRODUCT_NAME"],
        "CFBundlePackageType": "APPL",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleShortVersionString": values["MARKETING_VERSION"],
        "CFBundleVersion": values["CURRENT_PROJECT_VERSION"],
        "CFBundleDevelopmentRegion": "en",
        "LSMinimumSystemVersion": "15.0",
        "LSApplicationCategoryType": "public.app-category.utilities",
        "NSHighResolutionCapable": True,
        "FirebaseAppDelegateProxyEnabled": False,
        "FirebaseAutomaticScreenReportingEnabled": False,
        "FIREBASE_ANALYTICS_COLLECTION_ENABLED": False,
        "GOOGLE_ANALYTICS_REGISTRATION_WITH_AD_NETWORK_ENABLED": False,
        "GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_STORAGE": False,
        "GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_USER_DATA": False,
        "GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS": False,
    })
    return info


def entitlements(values, root=ROOT, helper=False):
    if helper:
        result = {}
    else:
        filename = "Cliptate.entitlements"
        result = expand(plistlib.loads((root / "Sources/Cliptate" / filename).read_bytes()), values)
    if values["CONFIGURATION"] == "Debug":
        result["com.apple.security.get-task-allow"] = True
    return result


def run(*arguments, env=None, capture=False):
    return subprocess.run([str(argument) for argument in arguments], env=env, check=True,
                          stdout=subprocess.PIPE if capture else sys.stderr,
                          text=True).stdout


def copy_resources(bin_path, resources, graph):
    # App catalogs are compiled into Bundle.main below. Dependency accessors
    # still need their bundles. Ignore stale products from removed dependencies.
    package_names = set()

    def collect(package):
        package_names.add(package["name"])
        for dependency in package.get("dependencies", []):
            collect(dependency)

    collect(graph)
    for bundle in sorted(bin_path.glob("*.bundle")):
        if bundle.name in {"Cliptate_Cliptate.bundle", "Cliptate_CliptateTests.bundle",
                           "Cliptate_CliptateCoreTests.bundle"}:
            continue
        if not any(bundle.name.startswith(name + "_") for name in package_names):
            continue
        shutil.copytree(bundle, resources / bundle.name, symlinks=True)


def copy_firebase_configuration(values, resources):
    source = ROOT / "config/firebase" / values["CONFIGURATION"] / "GoogleService-Info.plist"
    if not source.exists():
        return
    config = plistlib.loads(source.read_bytes())
    if config.get("BUNDLE_ID") != values["PRODUCT_BUNDLE_IDENTIFIER"]:
        raise ValueError("Firebase configuration does not match the app bundle identifier")
    shutil.copy2(source, resources / "GoogleService-Info.plist")


def compile_resources(resources, work):
    partial_info = work / "assets.plist"
    run("xcrun", "actool", ROOT / "Sources/Cliptate/Assets.xcassets",
        "--compile", resources, "--platform", "macosx", "--minimum-deployment-target", "15.0",
        "--target-device", "mac", "--app-icon", "AppIcon", "--accent-color", "AccentColor",
        "--output-partial-info-plist", partial_info, capture=True)
    # The app uses default Bundle.main localization, including String(localized:).
    run("xcrun", "xcstringstool", "compile", ROOT / "Sources/Cliptate/Localizable.xcstrings",
        "--output-directory", resources)
    for catalog in resources.glob("*.lproj/*.strings*"):
        run("plutil", "-convert", "binary1", catalog)
    return plistlib.loads(partial_info.read_bytes())


def compile_metal(resources, work):
    bundle = resources / "mlx-swift_Cmlx.bundle"
    if list(bundle.rglob("default.metallib")):
        return  # Swift Build / Xcode's package backend already compiled shaders.
    # The native SwiftPM backend doesn't compile Metal. The pinned MLX package
    # includes the same prepared sources used by its Xcode build.
    source = ROOT / ".build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal"
    shaders = sorted(source.rglob("*.metal"))
    if not shaders:
        raise ValueError("Missing MLX Metal sources; resolve the locked packages first")
    objects = []
    for index, shader in enumerate(shaders):
        target = work / f"metal-{index}.air"
        run("xcrun", "-sdk", "macosx", "metal", "-c", shader,
            "-I", source, "-fno-fast-math", "-Wno-c++17-extensions", "-Wno-c++20-extensions",
            "-mmacosx-version-min=15.0", "-o", target)
        objects.append(target)
    destination = bundle / "Contents/Resources"
    destination.mkdir(parents=True, exist_ok=True)
    (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "mlx-swift.Cmlx", "CFBundlePackageType": "BNDL"}))
    run("xcrun", "metallib", *objects, "-o", destination / "default.metallib")


def relocate(binary):
    load_commands = run("otool", "-l", binary, capture=True)
    paths = re.findall(r"cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset", load_commands)
    for path in paths:
        if path.startswith("/") and not path.startswith(("/usr/lib/", "/System/")):
            run("xcrun", "install_name_tool", "-delete_rpath", path, binary)
    if "@executable_path/../Frameworks" not in paths:
        run("xcrun", "install_name_tool", "-add_rpath", "@executable_path/../Frameworks", binary)


def sign(app, values, identity, work):
    env = {**os.environ, "CODE_SIGN_IDENTITY": identity}
    run(ROOT / "scripts/sign-sparkle.sh", app, env=env)
    flags = ["--force", "--sign", identity]
    if identity != "-":
        flags += ["--options", "runtime", "--timestamp"]
    helper = app / "Contents/Helpers/cliptate"
    if helper.exists():
        helper_entitlements = work / "cli-entitlements.plist"
        helper_entitlements.write_bytes(plistlib.dumps(entitlements(values, helper=True)))
        identifier = "com.cliptate.dev.cli" if values["CONFIGURATION"] == "Debug" else "com.cliptate.cli"
        run("codesign", *flags, "--identifier", identifier, "--entitlements", helper_entitlements, helper)
    app_entitlements = work / "app-entitlements.plist"
    app_entitlements.write_bytes(plistlib.dumps(entitlements(values)))
    run("codesign", *flags, "--entitlements", app_entitlements, app)
    run("codesign", "--verify", "--deep", "--strict", app)


def prepare_release_binary(binary, symbols):
    run("xcrun", "dsymutil", binary, "-o", symbols)
    # Match Xcode's executable STRIP_STYLE=all; -S -x retains tens of
    # thousands of global Swift symbols that aren't needed for dynamic linking.
    run("xcrun", "strip", "-u", "-r", binary)


def prepare_framework(framework, architectures):
    # Do not follow framework symlinks: each nested executable is rewritten once,
    # before sign-sparkle.sh restores its signature and sandbox entitlements.
    magic = {b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",
             b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}
    for directory, _, files in os.walk(framework):
        for name in files:
            binary = Path(directory) / name
            if binary.is_symlink():
                continue
            with binary.open("rb") as stream:
                if stream.read(4) not in magic:
                    continue
            available = run("xcrun", "lipo", "-archs", binary, capture=True).split()
            if not architectures or not set(architectures).issubset(available):
                raise ValueError(f"Framework executable lacks app architectures: {binary}")
            if set(available) == set(architectures):
                continue
            flags = ["-thin", architectures[0]] if len(architectures) == 1 else [
                flag for architecture in architectures for flag in ("-extract", architecture)]
            run("xcrun", "lipo", binary, *flags, "-output", binary)


def build_app(values, destination, identity):
    env = dict(os.environ)
    command = [ROOT / "scripts/swift-safe.sh", "build", "--package-path", ROOT,
               "--configuration", values["CONFIGURATION"].lower(), "--force-resolved-versions"]
    run(*command, "--product", "Cliptate", env=env)
    run(*command, "--product", "CliptateCLI", env=env)
    bin_path = Path(run(*command, "--show-bin-path", env=env, capture=True).strip())
    graph = json.loads(run(ROOT / "scripts/swift-safe.sh", "package", "--package-path", ROOT,
                           "show-dependencies", "--format", "json", env=env, capture=True))
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".bundle-", dir=destination.parent) as temporary:
        work = Path(temporary)
        app = work / destination.name
        resources = app / "Contents/Resources"
        executable = app / "Contents/MacOS" / values["PRODUCT_NAME"]
        executable.parent.mkdir(parents=True)
        resources.mkdir()
        shutil.copy2(bin_path / "Cliptate", executable)
        relocate(executable)
        copy_resources(bin_path, resources, graph)
        copy_firebase_configuration(values, resources)
        info = info_plist(values)
        info.update(compile_resources(resources, work))
        compile_metal(resources, work)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        (app / "Contents/PkgInfo").write_bytes(b"APPL????")
        frameworks = app / "Contents/Frameworks"
        frameworks.mkdir()
        # Sparkle is the only dynamic dependency; SwiftPM links other products statically.
        sparkle = bin_path / "Sparkle.framework"
        if not sparkle.exists():
            sparkle = ROOT / ".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
        shutil.copytree(sparkle, frameworks / "Sparkle.framework", symlinks=True)
        if values["CONFIGURATION"] == "Release":
            architectures = run("xcrun", "lipo", "-archs", executable, capture=True).split()
            prepare_framework(frameworks / "Sparkle.framework", architectures)
        binaries = [executable]
        helper = app / "Contents/Helpers/cliptate"
        helper.parent.mkdir()
        shutil.copy2(bin_path / "CliptateCLI", helper)
        binaries.append(helper)
        if values["CONFIGURATION"] == "Release":
            for binary in binaries:
                # App and helper names differ only in case on production builds.
                name = f"{app.name}.dSYM" if binary == executable else f"{binary.name}.dSYM"
                prepare_release_binary(binary, destination.parent / name)
        sign(app, values, identity, work)
        # Keep the previous working app until all compilation and signing succeeds.
        if destination.exists():
            shutil.rmtree(destination)
        shutil.move(app, destination)
    return destination
