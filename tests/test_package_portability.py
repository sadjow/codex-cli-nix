import importlib.util
import pathlib
import struct
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / 'scripts/check-package-portability.py'
SPEC = importlib.util.spec_from_file_location('portability', SCRIPT)
PORTABILITY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PORTABILITY)


class PackagePortabilityTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = pathlib.Path(directory.name)

    def test_rejects_store_dependency(self):
        (self.root / 'rg').write_bytes(b'/nix/store/' + b'0' * 32 + b'-glibc/lib/ld.so')
        with self.assertRaisesRegex(ValueError, 'Store dependency in rg'):
            PORTABILITY.check_package(self.root)

    def test_checks_a_single_helper(self):
        helper = self.root / 'rg'
        helper.write_bytes(b'/nix/store/' + b'0' * 32 + b'-glibc/lib/ld.so')
        with self.assertRaisesRegex(ValueError, 'Store dependency in rg'):
            PORTABILITY.check_package(helper)
        helper.write_bytes(b'portable helper')
        PORTABILITY.check_package(helper)

    def test_rejects_system_dynamic_loader(self):
        binary = bytearray(120)
        binary[:6] = b'\x7fELF\x02\x01'
        struct.pack_into('<Q', binary, 32, 64)
        struct.pack_into('<HH', binary, 54, 56, 1)
        struct.pack_into('<I', binary, 64, 3)
        (self.root / 'rg').write_bytes(binary)
        with self.assertRaisesRegex(ValueError, 'Dynamic ELF dependency in rg'):
            PORTABILITY.check_package(self.root)

    def test_rejects_missing_or_empty_package(self):
        for root in [self.root / 'missing', self.root]:
            with self.subTest(root=root), self.assertRaises(ValueError):
                PORTABILITY.check_package(root)

    def test_accepts_static_elf(self):
        binary = bytearray(64)
        binary[:6] = b'\x7fELF\x02\x01'
        (self.root / 'rg').write_bytes(binary)
        PORTABILITY.check_package(self.root)


if __name__ == '__main__':
    unittest.main()
