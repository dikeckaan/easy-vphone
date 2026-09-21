import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    result=importlib.util.module_from_spec(spec); spec.loader.exec_module(result); return result
metrics=module('metrics',ROOT/'scripts/metrics.py')
ssh=module('ssh_vm',ROOT/'Resources/ssh-vm.py')

class MetricsTests(unittest.TestCase):
    def test_overlapping_days_replaced_not_added(self):
        old=[{'timestamp':'2026-09-16','count':2,'uniques':1}]
        new=[{'timestamp':'2026-09-16','count':3,'uniques':2}]
        self.assertEqual(metrics.merge_daily(old,new),new)
    def test_only_zip_downloads_count(self):
        self.assertEqual(metrics.downloads({'releases':[{'assets':[{'name':'a.zip','downloads':4},{'name':'SHA256SUMS','downloads':3}]}]}),4)
    def test_denied_traffic_preserves_snapshot(self):
        previous={'clones':{'updated_at':'old','count':9,'uniques':2,'daily':[]}}
        def api(path,paginate=False):
            if path=='': return dict(stargazers_count=0,forks_count=0,subscribers_count=0,open_issues_count=0)
            if path.startswith('releases'): return []
            raise RuntimeError('denied')
        with patch.object(metrics,'api',api):
            result=metrics.collect(previous)
        self.assertEqual(result['clones'],previous['clones'])
        self.assertIn('clones_error',result)
    def test_ssh_pins_identity_and_local_target(self):
        args=ssh.ssh_args('0000FE01-BFF2B3E52E4CCABC','mobile',34567)
        self.assertIn('HostKeyAlias=easy-vphone-0000fe01-bff2b3e52e4ccabc',args)
        self.assertEqual(args[-1],'mobile@127.0.0.1')
    def test_invalid_ssh_identity_rejected(self):
        for identity in ('','*','--help','../../foo'):
            with self.assertRaises(ValueError): ssh.ssh_args(identity,'mobile',22222)
