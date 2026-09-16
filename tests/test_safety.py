from pathlib import Path
import os
import select
import subprocess
import sys
import tempfile
import time
import unittest

BASE = Path(__file__).resolve().parents[1]

class InstallerValidationTests(unittest.TestCase):
    def check_rejected(self, values, text, action='create'):
        env = dict(os.environ, ROOT='/private/tmp/easy-vphone-test-unused',VM_NAME='test',VARIANT='jb',DISK_GB='64')
        env.update(values)
        p = subprocess.run(['/bin/bash',str(BASE/'Resources/install.sh'),action],env=env,capture_output=True,text=True,timeout=10)
        self.assertNotEqual(p.returncode,0)
        self.assertIn(text,p.stdout+p.stderr)
    def test_path_traversal_name(self):
        self.check_rejected({'VM_NAME':'../../outside'},'VM adı')
    def test_root_directory_rejected(self):
        self.check_rejected({'ROOT':'/'},'mutlak')
    def test_relative_directory_rejected(self):
        self.check_rejected({'ROOT':'relative'},'mutlak')
    def test_unsupported_variant_rejected(self):
        self.check_rejected({'VARIANT':'less'},'varyant')
    def test_invalid_disk_rejected(self):
        self.check_rejected({'DISK_GB':'31'},'32–512')
    def test_missing_external_drive_rejected(self):
        self.check_rejected({'ROOT':'/Volumes/easy-vphone-missing-test-volume/vm'},'Disk bağlı değil')
    def test_unknown_action_rejected(self):
        self.check_rejected({},'Bilinmeyen işlem',action='oops')

class TerminalTests(unittest.TestCase):
    def start_bridge(self, code):
        p = subprocess.Popen([sys.executable,str(BASE/'Resources/terminal.py'),sys.executable,'-u','-c',code],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        self.addCleanup(self.cleanup,p)
        return p
    @staticmethod
    def cleanup(p):
        if p.poll() is None:
            p.terminate()
            try: p.wait(timeout=3)
            except subprocess.TimeoutExpired: p.kill(); p.wait()
        p.stdin.close(); p.stdout.close()
    def read_until(self,p,marker):
        output=b''; deadline=time.monotonic()+8
        while marker not in output and time.monotonic()<deadline:
            ready,_,_=select.select([p.stdout],[],[],0.2)
            if ready:
                chunk=os.read(p.stdout.fileno(),4096)
                if not chunk: break
                output+=chunk
        self.assertIn(marker,output,output.decode(errors='replace'))
        return output
    def test_interactive_password_stays_off_output(self):
        p=self.start_bridge("import getpass; value=getpass.getpass('Password: '); print('OK' if value=='test-secret-8237' else 'BAD')")
        before=self.read_until(p,b'Password: ')
        p.stdin.write(b'test-secret-8237\n'); p.stdin.flush()
        after=self.read_until(p,b'OK')
        p.wait(timeout=5)
        self.assertEqual(p.returncode,0)
        self.assertNotIn(b'test-secret-8237',before+after)
    def test_nonzero_exit_is_preserved(self):
        p=self.start_bridge("print('finished'); raise SystemExit(7)")
        self.read_until(p,b'finished'); p.wait(timeout=5)
        self.assertEqual(p.returncode,7)
