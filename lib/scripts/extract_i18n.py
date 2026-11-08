"""Extract Traditional Chinese UI literals from lib/ for the English language pack.

Outputs (under i18n/):
  source.json     {"strings": {...}, "templates": {...}}  (values empty)
  todo.json       same shape, only keys not yet translated in en.json
  review.txt      skipped / uncertain literals with file:line and reason
  fragments.txt   short pieces likely split across Text/TextSpan

Interpolations ($name, ${expr}) become {0}, {1}... in templates.
Safe to run repeatedly.
"""
import ast
import glob
import importlib.util
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, 'i18n')
CJK = re.compile(r'[㐀-鿿]')

spec = importlib.util.spec_from_file_location('dartlex', os.path.join(HERE, 'dartlex.py'))
dartlex = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dartlex)

# Language option labels: must stay as they are (quoted source literals).
LANG_LABELS = {'简体中文', '繁體中文', '繁体中文'}

# Context before / after the literal that means it is compared or parsed.
BEFORE = re.compile(
    r'(?:==|!=|\bcontains\(|\bstartsWith\(|\bendsWith\(|\bRegExp\(\s*r?|\bindexOf\(|'
    r'\breplaceFirst\(|\bsplit\(|\bcase)\s*$')
AFTER = re.compile(r'^\s*(?:==|!=)')
MAP_KEY_BEFORE = re.compile(r'(?:[{,]|^)\s*$')
MAP_KEY_AFTER = re.compile(r'^\s*:(?!:)')

ESC = {'n': '\n', 't': '\t', 'r': '\r', 'b': '\b', 'f': '\f', 'v': '\v'}


def load_protect():
    """Read PROTECT from to_traditional.py without importing it (needs opencc)."""
    with open(os.path.join(HERE, 'to_traditional.py'), encoding='utf-8') as f:
        tree = ast.parse(f.read())
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
                isinstance(t, ast.Name) and t.id == 'PROTECT' for t in node.targets):
            return ast.literal_eval(node.value)
    raise SystemExit('PROTECT not found in to_traditional.py')


def unescape(t):
    out, i = [], 0
    while i < len(t):
        c = t[i]
        if c == '\\' and i + 1 < len(t):
            d = t[i + 1]
            if d in ESC:
                out.append(ESC[d])
                i += 2
            elif d == 'u':
                m = re.match(r'\{([0-9a-fA-F]+)\}|([0-9a-fA-F]{4})', t[i + 2:])
                if m:
                    out.append(chr(int(m.group(1) or m.group(2), 16)))
                    i += 2 + m.end()
                else:
                    out.append(d)
                    i += 2
            elif d == 'x' and re.match(r'[0-9a-fA-F]{2}', t[i + 2:i + 4]):
                out.append(chr(int(t[i + 2:i + 4], 16)))
                i += 4
            else:
                out.append(d)
                i += 2
        else:
            out.append(c)
            i += 1
    return ''.join(out)


def cjk_count(s):
    return len(CJK.findall(s))


def main():
    protect = load_protect()
    strings, templates = {}, {}
    review, fragments = [], []
    protected = 0

    files = sorted(glob.glob(os.path.join(ROOT, 'lib', '**', '*.dart'), recursive=True))
    for path in files:
        rel = os.path.relpath(path, ROOT).replace('\\', '/')
        if rel.startswith(('lib/grpc/', 'lib/scripts/')) or rel.endswith('.g.dart'):
            continue
        with open(path, encoding='utf-8', newline='') as f:
            src = f.read()
        lines = src.split('\n')
        markers = protect.get(rel, ())

        for qs, end, parts, raw in dartlex.literals(src):
            texts = [src[s:e] for k, s, e in parts if k == 't']
            if not any(CJK.search(t) for t in texts):
                continue
            ln = src.count('\n', 0, qs)
            line = lines[ln].rstrip('\r')
            where = f'{rel}:{ln + 1}'
            snippet = src[qs:end].replace('\n', '\\n').replace('\r', '')[:80]

            # Protected (server-compared) literals.
            if any(m in line for m in markers) or any(t in LANG_LABELS for t in texts):
                protected += 1
                continue

            # Comparison / parsing context.
            ls = src.rfind('\n', 0, qs) + 1
            le = src.find('\n', end)
            le = len(src) if le < 0 else le
            before, after = src[ls:qs], src[end:le]
            if raw and before.endswith('r'):
                before = before[:-1]
            reason = None
            if BEFORE.search(before) or AFTER.search(after):
                reason = 'compared / matched (==, contains, startsWith, RegExp, case...)'
            elif MAP_KEY_AFTER.match(after) and MAP_KEY_BEFORE.search(before):
                reason = 'possible map key'
            if reason:
                review.append(f'{where}\t{reason}\t{snippet}')
                continue

            # Build key.
            buf, n_ph, adjacent, prev_e = [], 0, False, False
            for k, s, e in parts:
                if k == 't':
                    t = src[s:e]
                    buf.append(t if raw else unescape(t))
                    if t:
                        prev_e = False
                else:
                    if prev_e:
                        adjacent = True
                    buf.append('{%d}' % n_ph)
                    n_ph += 1
                    prev_e = True
            key = ''.join(buf)

            if n_ph == 0:
                strings[key] = ''
                short = cjk_count(key) == 1 or key != key.strip()
                if short or re.search(r'TextSpan\(\s*text:\s*$', before):
                    fragments.append(f'{where}\t{key!r}')
                continue

            if cjk_count(key) < 2:
                review.append(f'{where}\ttemplate with <2 Chinese chars\t{snippet}')
                fragments.append(f'{where}\t{key!r}')
            elif adjacent:
                review.append(f'{where}\tadjacent placeholders\t{snippet}')
            else:
                templates[key] = ''

    # Keep existing translations; list only new items in todo.json.
    en = {'strings': {}, 'templates': {}}
    en_path = os.path.join(OUT, 'en.json')
    if os.path.exists(en_path):
        with open(en_path, encoding='utf-8') as f:
            en.update(json.load(f))
    todo = {
        'strings': {k: '' for k in strings if not en['strings'].get(k)},
        'templates': {k: '' for k in templates if not en['templates'].get(k)},
    }

    os.makedirs(OUT, exist_ok=True)

    def dump(name, obj):
        with open(os.path.join(OUT, name), 'w', encoding='utf-8', newline='\n') as f:
            json.dump(obj, f, ensure_ascii=False, indent=1, sort_keys=True)
            f.write('\n')

    dump('source.json', {'strings': strings, 'templates': templates})
    dump('todo.json', todo)
    for name, rows in (('review.txt', review), ('fragments.txt', fragments)):
        rows = sorted(set(rows))
        with open(os.path.join(OUT, name), 'w', encoding='utf-8', newline='\n') as f:
            f.write('\n'.join(rows) + ('\n' if rows else ''))

    print(f"strings={len(strings)} templates={len(templates)} review={len(set(review))} "
          f"fragments={len(set(fragments))} protected_skipped={protected} "
          f"todo_strings={len(todo['strings'])} todo_templates={len(todo['templates'])}")


if __name__ == '__main__':
    main()
