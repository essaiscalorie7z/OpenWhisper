"""Inspect the shipped ZIP, including the Mach-O platform of each executable."""
import plistlib
import struct
import sys
import zipfile


def check(condition, message):
    if not condition:
        raise ValueError(message)


def device_macho(binary, expected_type):
    # The project builds thin arm64 device executables.
    magic, cpu, _, kind, count, _, _, _ = struct.unpack_from("<8I", binary)
    check((magic, cpu, kind) == (0xfeedfacf, 0x0100000c, expected_type), "Mach-O arm64 inattendu")
    offset = 32
    platforms = []
    for _ in range(count):
        cmd, size = struct.unpack_from("<II", binary, offset)
        check(size >= 8 and offset + size <= len(binary), "Commande Mach-O tronquée")
        if cmd == 0x32:  # LC_BUILD_VERSION
            platforms.append(struct.unpack_from("<I", binary, offset + 8)[0])
        offset += size
    check(platforms == [2], "Le binaire doit cibler iPhoneOS")


def verify(path):
    app = "Payload/OpenWhisper.app/"
    ext = app + "PlugIns/Clavier.appex/"
    framework = app + "Frameworks/whisper.framework/"
    with zipfile.ZipFile(path) as archive:
        check(archive.testzip() is None, "CRC invalide")
        paths = archive.namelist()
        check(len(paths) == len(set(paths)), "Entrées dupliquées")
        check(all(p.startswith("Payload/") for p in paths), "Élément hors Payload")
        infos = {}
        for prefix, kind in [(app, 2), (ext, 2), (framework, 6)]:
            info = plistlib.loads(archive.read(prefix + "Info.plist"))
            device_macho(archive.read(prefix + info["CFBundleExecutable"]), kind)
            infos[prefix] = info
        check(infos[ext]["CFBundleIdentifier"] == infos[app]["CFBundleIdentifier"] + ".clavier", "Identifiants incohérents")
        check(infos[ext]["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.keyboard-service", "Extension clavier absente")
        check(app + "Assets.car" in paths, "Ressources visuelles absentes")
        check(not any(p.endswith((".xctest/", ".bin", ".wav", "embedded.mobileprovision")) for p in paths),
              "Ressources de test, modèle ou profil dans le produit")
        print("IPA vérifié : app, ressources, extension clavier et moteur Whisper pour iPhone arm64.")


if __name__ == "__main__":
    verify(sys.argv[1])
