"""Replace screen-related 「屏」 in UI string literals of lib/**/*.dart.

    python lib/scripts/screen_wording.py

Only text inside string literals changes (comments and code stay).
Literals listed in to_traditional.PROTECT (compared with server text) are
skipped. to_traditional.py also uses WORDING, so reruns keep this wording.
The script is idempotent.
"""
import glob
import importlib.util
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

# Applied in order: specific phrases first, then the general table.
WORDING = [
    ('強制豎屏', '強制直向'),
    ('強制橫屏', '強制橫向'),
    ('豎屏影片時豎屏', '直向影片時直向'),
    ('否則橫屏', '否則橫向'),
    ('小屏豎屏影片', '小螢幕直向影片'),
    ('豎屏影片', '直向影片'),
    ('橫屏影片', '橫向影片'),
    ('全屏', '全螢幕'),
    ('橫屏', '橫向螢幕'),
    ('豎屏', '直向螢幕'),
    ('小屏', '小螢幕'),
    ('摺疊屏', '摺疊螢幕'),
    ('折疊屏', '摺疊螢幕'),
    ('轉屏', '旋轉螢幕'),
    ('黑屏', '黑畫面'),
    ('息屏', '關閉螢幕'),
    ('投屏', '投放'),
    ('刷屏', '洗版'),
    ('屏蔽', '封鎖'),
    ('屏幕', '螢幕'),
]


def apply(text):
    for a, b in WORDING:
        text = text.replace(a, b)
    return text


def _load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + '.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    dartlex = _load('dartlex')
    protect = _load('to_traditional').PROTECT
    changed = 0
    for path in glob.glob(os.path.join(ROOT, 'lib', '**', '*.dart'), recursive=True):
        rel = os.path.relpath(path, ROOT).replace(os.sep, '/')
        if rel.startswith(('lib/grpc/', 'lib/scripts/')):
            continue
        with open(path, encoding='utf-8', newline='') as f:
            src = f.read()
        if '屏' not in src:
            continue
        lines = src.split('\n')
        keep = {i for i, line in enumerate(lines)
                for m in protect.get(rel, ()) if m in line}
        out, last = [], 0
        for s, e in dartlex.spans(src):
            text = src[s:e]
            if '屏' not in text or src.count('\n', 0, s) in keep:
                continue
            new = apply(text)
            if new != text:
                out.append(src[last:s])
                out.append(new)
                last = e
        if out:
            out.append(src[last:])
            with open(path, 'w', encoding='utf-8', newline='') as f:
                f.write(''.join(out))
            changed += 1
    print(f'changed {changed} files')


if __name__ == '__main__':
    main()
