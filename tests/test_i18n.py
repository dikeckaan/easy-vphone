import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = {'tr','en','de','fr','es','it','pt','ru','ja','zh-Hans'}

class CatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalogs = {}
        for path in (ROOT/'Resources/i18n').glob('*.json'):
            def unique(pairs):
                result={}
                for key,value in pairs:
                    if key in result: raise ValueError('Duplicate key: '+key)
                    result[key]=value
                return result
            cls.catalogs[path.stem] = json.loads(path.read_text(),object_pairs_hook=unique)
    def test_all_ten_languages_have_all_keys(self):
        self.assertEqual(set(self.catalogs),LANGUAGES)
        baseline=set(self.catalogs['en'])
        self.assertGreaterEqual(len(baseline),190)
        for language,strings in self.catalogs.items():
            self.assertEqual(set(strings),baseline,language)
            self.assertTrue(all(isinstance(x,str) and x.strip() for x in strings.values()),language)
    def test_placeholders_match_in_every_language(self):
        for key,english in self.catalogs['en'].items():
            expected=sorted(re.findall(r'\{\d+\}',english))
            for lang,strings in self.catalogs.items():
                self.assertEqual(sorted(re.findall(r'\{\d+\}',strings[key])),expected,(lang,key))
    def test_all_source_keys_exist(self):
        for path in (ROOT/'Sources').glob('*.swift'):
            for key in re.findall(r'(?:tr|localizedMessage)\("([a-z][a-z0-9_.]+)"',path.read_text()):
                self.assertIn(key,self.catalogs['en'],str(path)+': '+key)
    def test_no_turkish_literals_left_in_application_views(self):
        for name in ['App.swift','VMModel.swift','ProcessConsole.swift','IPALibrary.swift']:
            self.assertIsNone(re.search(r'[çğıöşüÇĞİÖŞÜ]',(ROOT/'Sources'/name).read_text()),name)
