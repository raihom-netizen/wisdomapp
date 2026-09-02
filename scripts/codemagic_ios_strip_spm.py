#!/usr/bin/env python3
"""Remove Swift Package Manager integration from Xcode project (pbxproj).

Called by codemagic.yaml BEFORE flutter build ipa.
Flutter auto-adds SPM which conflicts (TOCropViewController 3.x vs 2.x).
CocoaPods resolves the same tree without conflict.

Usage: python3 codemagic_ios_strip_spm.py [ios_dir]
  ios_dir defaults to "ios" (relative to working directory = flutter_app).
"""
import os, re, sys

def strip_spm(pbxproj_path):
    with open(pbxproj_path, "r", encoding="utf-8") as f:
        content = f.read()

    original = content

    # 1. Remove packageProductDependencies blocks (may appear inside PBXNativeTarget)
    #    Format:
    #      packageProductDependencies = (
    #        UUID /* Name */,
    #        ...
    #      );
    content = re.sub(
        r'\n\s*packageProductDependencies\s*=\s*\([^)]*\)\s*;',
        '', content, flags=re.DOTALL
    )

    # 2. Remove packageReferences blocks (inside PBXProject)
    content = re.sub(
        r'\n\s*packageReferences\s*=\s*\([^)]*\)\s*;',
        '', content, flags=re.DOTALL
    )

    # 3. Remove PBXSwiftPackageManagerBuildPhase sections
    #    Format:
    #      UUID /* SwiftPM ... */ = {
    #        isa = PBXSwiftPackageManagerBuildPhase;
    #        ...
    #      };
    content = re.sub(
        r'\n\s*[A-F0-9]+\s*/\*\s*SwiftPM[^*]*\*/\s*=\s*\{[^}]*isa\s*=\s*PBXSwiftPackageManagerBuildPhase[^}]*\}\s*;',
        '', content, flags=re.DOTALL
    )

    # 4. Remove XCRemoteSwiftPackageReference entries
    #    Format:
    #      UUID /* XCRemoteSwiftPackageReference "..." */ = {
    #        isa = XCRemoteSwiftPackageReference;
    #        ...
    #      };
    content = re.sub(
        r'\n\s*[A-F0-9]+\s*/\*\s*XCRemoteSwiftPackageReference[^*]*\*/\s*=\s*\{[^}]*isa\s*=\s*XCRemoteSwiftPackageReference[^}]*\}\s*;',
        '', content, flags=re.DOTALL
    )

    # 5. Remove XCSwiftPackageProductDependency entries
    #    Format:
    #      UUID /* XCSwiftPackageProductDependency "..." */ = {
    #        isa = XCSwiftPackageProductDependency;
    #        ...
    #      };
    content = re.sub(
        r'\n\s*[A-F0-9]+\s*/\*\s*XCSwiftPackageProductDependency[^*]*\*/\s*=\s*\{[^}]*isa\s*=\s*XCSwiftPackageProductDependency[^}]*\}\s*;',
        '', content, flags=re.DOTALL
    )

    # 6. Remove SwiftPackageManagerBuildPhase references from PBXNativeTarget buildPhases
    #    These appear as:  UUID /* SwiftPM ... */ in the buildPhases list
    content = re.sub(
        r'\n\s*[A-F0-9]+\s*/\*\s*SwiftPM[^*]*\*/,',
        '', content
    )

    # 7. Set EnablePackageResolution = NO in all XCBuildConfiguration buildSettings
    #    If it exists, replace; if not, add before closing };
    if 'EnablePackageResolution' in content:
        content = re.sub(
            r'(EnablePackageResolution\s*=\s*)\w+',
            r'\g<1>NO',
            content
        )
    else:
        # Add EnablePackageResolution = NO to each buildSettings block
        # Match the closing of buildSettings: }; that follows buildSettings = {
        def add_disable(m):
            block = m.group(0)
            if 'EnablePackageResolution' not in block:
                # Insert before the closing }; of the buildSettings dict
                block = re.sub(
                    r'(\n\s*)(\};)',
                    r'\1EnablePackageResolution = NO;\n\1\2',
                    block, count=1
                )
            return block

        # Match buildSettings = { ... }; blocks
        content = re.sub(
            r'buildSettings\s*=\s*\{[^}]*\};',
            add_disable,
            content,
            flags=re.DOTALL
        )

    if content == original:
        print("  [SPM strip] Nenhuma referencia SPM encontrada no pbxproj (ja limpo).")
        return False

    with open(pbxproj_path, "w", encoding="utf-8") as f:
        f.write(content)

    changes = []
    for label, pattern in [
        ("packageProductDependencies", r'packageProductDependencies'),
        ("packageReferences", r'packageReferences'),
        ("PBXSwiftPackageManagerBuildPhase", r'PBXSwiftPackageManagerBuildPhase'),
        ("XCRemoteSwiftPackageReference", r'XCRemoteSwiftPackageReference'),
        ("XCSwiftPackageProductDependency", r'XCSwiftPackageProductDependency'),
    ]:
        if re.search(pattern, original) and not re.search(pattern, content):
            changes.append(label)
    print(f"  [SPM strip] Removido: {', '.join(changes) if changes else 'secoes SPM'}")
    print(f"  [SPM strip] EnablePackageResolution = NO aplicado.")
    return True


def main():
    ios_dir = sys.argv[1] if len(sys.argv) > 1 else "ios"
    pbxproj = os.path.join(ios_dir, "Runner.xcodeproj", "project.pbxproj")

    if not os.path.exists(pbxproj):
        print(f"  [SPM strip] ERRO: {pbxproj} nao encontrado.")
        sys.exit(1)

    print(f"  [SPM strip] Processando: {pbxproj}")
    changed = strip_spm(pbxproj)

    # Also clean Package.resolved if present
    pkg_resolved = os.path.join(ios_dir, "Runner.xcodeproj", "project.xcworkspace", "xcshareddata", "swiftpm", "Package.resolved")
    if os.path.exists(pkg_resolved):
        os.remove(pkg_resolved)
        print(f"  [SPM strip] Removido: {pkg_resolved}")

    # Remove swiftpm directory if present
    swiftpm_dir = os.path.join(ios_dir, "Runner.xcodeproj", "project.xcworkspace", "xcshareddata", "swiftpm")
    if os.path.exists(swiftpm_dir):
        import shutil
        shutil.rmtree(swiftpm_dir, ignore_errors=True)
        print(f"  [SPM strip] Removido diretorio: {swiftpm_dir}")

    if changed:
        print("  [SPM strip] OK — SPM removido do pbxproj. CocoaPods resolve dependencias nativas.")
    else:
        print("  [SPM strip] OK — pbxproj ja sem SPM.")


if __name__ == "__main__":
    main()
