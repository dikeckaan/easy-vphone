import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

BASE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('prepare_runtime', BASE/'Resources/prepare-runtime.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root/'source'; self.source.mkdir()
        self.runtime = self.root/'runtime'
        self.target = self.runtime/'scripts/patchers'; self.target.mkdir(parents=True)
        self.host = self.runtime/'scripts/cfw_install_host.sh'
        self.host.write_text('#!/bin/zsh\n' + module.MARKER + '\necho done\n')
        self.saved = module.EXPECTED
        module.EXPECTED = {'one.py':hashlib.sha256(b'old1').hexdigest(), 'two.py':hashlib.sha256(b'old2').hexdigest()}
        self.addCleanup(setattr, module, 'EXPECTED', self.saved)
        for n, content in [('one.py',b'old1'),('two.py',b'old2')]:
            (self.target/n).write_bytes(content)
            (self.source/n).write_bytes(b'new-'+content)
    def test_repeat_is_idempotent(self):
        module.prepare(self.source,self.runtime)
        first = self.host.read_text()
        module.prepare(self.source,self.runtime)
        self.assertEqual(first,self.host.read_text())
        self.assertEqual(first.count(module.ADDITION),1)
        self.assertEqual((self.target/'one.py').read_bytes(),b'new-old1')
    def test_unknown_patcher_leaves_everything_untouched(self):
        (self.target/'two.py').write_bytes(b'new upstream')
        host = self.host.read_text()
        with self.assertRaisesRegex(ValueError,'unknown code'):
            module.prepare(self.source,self.runtime)
        self.assertEqual(self.host.read_text(),host)
        self.assertEqual((self.target/'one.py').read_bytes(),b'old1')
    def test_unknown_host_script_is_rejected(self):
        self.host.write_text('different upstream script')
        with self.assertRaisesRegex(ValueError,'SDK patch'):
            module.prepare(self.source,self.runtime)
        self.assertEqual((self.target/'one.py').read_bytes(),b'old1')
