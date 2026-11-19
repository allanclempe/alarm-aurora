"""aurora-scripts' POSIX helpers: device tree property and ESP layout fallbacks.

functions.sh reads /proc/device-tree; the tests run a copy that reads a
temporary tree instead, under dash (the initramfs runs it under busybox ash).
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

FUNCTIONS = Path(__file__).resolve().parents[1] / 'packages/aurora-scripts/functions.sh'
SHELL = shutil.which('dash') or shutil.which('sh')


class Functions(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / 'chosen').mkdir()
        self.lib = self.root / 'functions.sh'
        self.lib.write_text(FUNCTIONS.read_text().replace('/proc/device-tree', str(self.root)))

    def run_sh(self, script):
        return subprocess.run([SHELL, '-c', f'. {self.lib}; {script}'], capture_output=True,
                              text=True, check=True).stdout

    def test_esp_uuid_prefers_the_aurora_property(self):
        (self.root / 'chosen/aurora,efi-system-partition').write_bytes(b'new-uuid\0')
        (self.root / 'chosen/asahi,efi-system-partition').write_bytes(b'old-uuid\0')
        self.assertEqual(self.run_sh('aurora_esp_uuid'), 'new-uuid')

    def test_esp_uuid_reads_the_legacy_property(self):
        # LEGACY-ASAHI(2027-02-28): an aura from before the rename.
        (self.root / 'chosen/asahi,efi-system-partition').write_bytes(b'old-uuid\0')
        self.assertEqual(self.run_sh('aurora_esp_uuid'), 'old-uuid')

    def test_esp_uuid_is_empty_without_either(self):
        self.assertEqual(self.run_sh('aurora_esp_uuid'), '')

    def stage2_dir(self, *files):
        esp = self.root / 'esp'
        shutil.rmtree(esp, ignore_errors=True)
        for name in files:
            (esp / name).parent.mkdir(parents=True, exist_ok=True)
            (esp / name).write_bytes(b'x')
        esp.mkdir(exist_ok=True)
        return self.run_sh(f'aurora_stage2_dir {esp}').strip()

    def test_stage2_dir(self):
        self.assertEqual(self.stage2_dir(), 'aurora')
        self.assertEqual(self.stage2_dir('aurora/boot.bin'), 'aurora')
        self.assertEqual(self.stage2_dir('aurora/boot-ctxr.bin', 'm1n1/boot.bin'), 'aurora')
        self.assertEqual(self.stage2_dir('aurora/stage1.macho'), 'aurora')
        # LEGACY-ASAHI(2027-02-28): a Stage 1 enrolled before the rename.
        self.assertEqual(self.stage2_dir('m1n1/boot.bin'), 'm1n1')
        self.assertEqual(self.stage2_dir('m1n1/boot-ctxr.bin', 'aurora/stage1.macho'), 'm1n1')

    def test_esp_layout(self):
        for name in ('aurora', 'm1n1'):
            (self.root / 'b' / name).mkdir(parents=True)
            self.assertEqual(subprocess.run([SHELL, '-c', f'. {self.lib}; aurora_is_esp {self.root / "b"}']).returncode, 0)
            shutil.rmtree(self.root / 'b')
        (self.root / 'b').mkdir()
        self.assertNotEqual(subprocess.run([SHELL, '-c', f'. {self.lib}; aurora_is_esp {self.root / "b"}']).returncode, 0)


if __name__ == '__main__':
    unittest.main()
