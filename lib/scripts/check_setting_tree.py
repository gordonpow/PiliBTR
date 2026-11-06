"""Checks lib/pages/setting/models/setting_tree.dart against the setting
lists (AC-2 of docs/work/settings-tree-search):
- every title listed in a tree group exists as `title: '...'` in a setting
  list (else a typo: the item would fall into its default group);
- no title is listed in two groups.
Items not listed go to the default group of their list, so no item is lost.
Run: python lib/scripts/check_setting_tree.py"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MODELS = os.path.join(ROOT, 'lib', 'pages', 'setting', 'models')

tree = open(os.path.join(MODELS, 'setting_tree.dart'), encoding='utf-8').read()
listed = []
for block in re.findall(r'titles: \{(.*?)\}', tree, re.S):
    listed += re.findall(r"'([^']+)'", block)

known = set()
for path in glob.glob(os.path.join(MODELS, '*_settings.dart')):
    known |= set(re.findall(r"title: '([^']+)'", open(path, encoding='utf-8').read()))

bad = False
for t in sorted(set(listed)):
    if t not in known:
        print('not found:', t)
        bad = True
for t in sorted({t for t in listed if listed.count(t) > 1}):
    print('in two groups:', t)
    bad = True
print(f'{len(listed)} listed titles, {len(known)} titles in the lists:',
      'FAIL' if bad else 'OK')
sys.exit(1 if bad else 0)
