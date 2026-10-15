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
    # Preserve existing local billing/update/team settings without evaluating code.
    legacy = root / "config/Local.xcconfig"
    if legacy.exists():
        for line in legacy.read_text().splitlines():
            match = re.fullmatch(r"\s*(CLIPTATE_\w+)\s*=\s*(.*?)\s*", line)
            if match:
                values[match[1]] = match[2].replace("$()", "")
    local = root / "config/Local.json"
    if local.exists():
        values.update(json.loads(local.read_text()))
    values.update({key: value for key, value in env.items()
                   if key in values or key in {"CLIPTATE_APP_STORE", "CLIPTATE_DEVELOPMENT_TEAM"}})
    if any(not isinstance(value, str) for value in values.values()):
        raise ValueError("App configuration values must be strings")
    configuration = env.get("CONFIGURATION", "Debug")
    if configuration not in {"Debug", "Release"}:
        raise ValueError("CONFIGURATION must be Debug or Release")
    channel = values.get("CLIPTATE_APP_STORE") or ("YES" if configuration == "Release" else "NO")
    if channel not in {"YES", "NO"}:
        raise ValueError("CLIPTATE_APP_STORE must be YES or NO")
    development = configuration == "Debug"
    values.update({
        "CONFIGURATION": configuration,
        "CLIPTATE_APP_STORE": channel,
        "PRODUCT_NAME": "Cliptate Dev" if development else "Cliptate",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.cliptate.dev" if development else "com.voicepink.voicepinkpro",
        "CLIPTATE_CLI_URL_SCHEME": ("cliptate-dev-cli" if development else "cliptate-cli")
        + ("-disabled" if channel == "YES" else ""),
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
    })
    return info


def entitlements(values, root=ROOT, helper=False):
    if helper:
        result = {}
    else:
        filename = "Cliptate.entitlements" if values["CLIPTATE_APP_STORE"] == "YES" else "Cliptate-Direct.entitlements"
        result = expand(plistlib.loads((root / "Sources/Cliptate" / filename).read_bytes()), values)
    if values["CONFIGURATION"] == "Debug":
        result["com.apple.security.get-task-allow"] = True
    return result


def run(*arguments, env=None, capture=False):
    return subprocess.run([str(argument) for argument in arguments], env=env, check=True,
                          stdout=subprocess.PIPE if capture else sys.stderr,
                          text=True).stdout


def copy_resources(bin_path, resources):
    # SwiftPM accessors search Bundle.main.resourceURL; exclude test fixtures left
    # by earlier swift test runs in the same output directory.
    for bundle in sorted(bin_path.glob("*.bundle")):
        if bundle.name == "Cliptate_CliptateTests.bundle":
            continue
        shutil.copytree(bundle, resources / bundle.name, symlinks=True)


def compile_resources(resources, work):
    partial_info = work / "assets.plist"
    run("xcrun", "actool", ROOT / "Sources/Cliptate/Assets.xcassets",
        "--compile", resources, "--platform", "macosx", "--minimum-deployment-target", "15.0",
        "--target-device", "mac", "--app-icon", "AppIcon", "--accent-color", "AccentColor",
        "--output-partial-info-plist", partial_info, capture=True)
    # The app uses default Bundle.main localization, including String(localized:).
    run("xcrun", "xcstringstool", "compile", ROOT / "Sources/Cliptate/Localizable.xcstrings",
        "--output-directory", resources)
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


def build_app(values, destination, identity):
    env = {**os.environ, "CLIPTATE_APP_STORE": values["CLIPTATE_APP_STORE"]}
    command = [ROOT / "scripts/swift-safe.sh", "build", "--package-path", ROOT,
               "--configuration", values["CONFIGURATION"].lower(), "--force-resolved-versions"]
    run(*command, "--product", "CliptateApp", env=env)
    if values["CLIPTATE_APP_STORE"] == "NO":
        run(*command, "--product", "cliptate", env=env)
    bin_path = Path(run(*command, "--show-bin-path", env=env, capture=True).strip())
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".bundle-", dir=destination.parent) as temporary:
        work = Path(temporary)
        app = work / destination.name
        resources = app / "Contents/Resources"
        executable = app / "Contents/MacOS" / values["PRODUCT_NAME"]
        executable.parent.mkdir(parents=True)
        resources.mkdir()
        shutil.copy2(bin_path / "CliptateApp", executable)
        relocate(executable)
        copy_resources(bin_path, resources)
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
        binaries = [executable]
        if values["CLIPTATE_APP_STORE"] == "NO":
            helper = app / "Contents/Helpers/cliptate"
            helper.parent.mkdir()
            shutil.copy2(bin_path / "cliptate", helper)
            binaries.append(helper)
        if values["CONFIGURATION"] == "Release":
            for binary in binaries:
                run("xcrun", "dsymutil", binary, "-o", destination.parent / f"{binary.name}.dSYM")
                run("xcrun", "strip", "-S", "-x", binary)
        sign(app, values, identity, work)
        # Keep the previous working app until all compilation and signing succeeds.
        if destination.exists():
            shutil.rmtree(destination)
        shutil.move(app, destination)
    return destination
