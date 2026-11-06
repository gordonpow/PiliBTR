"""Make every `Text(...)` in lib/ convert the Chinese script (see
lib/utils/zh_convert.dart).

Rewrites the imports of Flutter's material/widgets libraries to the
PiliBTR versions in lib/common/widgets/, which export the same library
but with the converting `Text` from zh_text.dart:

    package:material_ui/material_ui.dart -> zh_material.dart
    package:flutter/material.dart        -> zh_flutter_material.dart
    package:flutter/widgets.dart         -> zh_widgets.dart

`show`/`hide` clauses are kept. Imports with a prefix (`as x`) are not
changed. Run it again after each merge from upstream:

    python lib/scripts/use_zh_text.py

The script is idempotent.
"""
import glob
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

TARGETS = {
    'package:material_ui/material_ui.dart':
        'package:PiliPlus/common/widgets/zh_material.dart',
    'package:flutter/material.dart':
        'package:PiliPlus/common/widgets/zh_flutter_material.dart',
    'package:flutter/widgets.dart':
        'package:PiliPlus/common/widgets/zh_widgets.dart',
}

# Flutter source copied into the app, and the files that define the
# converting Text, keep the real Flutter imports.
SKIP = (
    'lib/common/widgets/flutter/',
    'lib/common/widgets/zh_',
    'lib/grpc/',
)

IMPORT = re.compile(
    r"import '(" + '|'.join(re.escape(k) for k in TARGETS) + r")'(?P<rest>[^;]*);"
)


def fix(match):
    rest = match.group('rest')
    if re.search(r'\bas\s+\w+', rest):
        return match.group(0)
    return f"import '{TARGETS[match.group(1)]}'{rest};"


def main():
    changed = 0
    for path in glob.glob(os.path.join(ROOT, 'lib', '**', '*.dart'), recursive=True):
        rel = os.path.relpath(path, ROOT).replace(os.sep, '/')
        if rel.startswith(SKIP):
            continue
        with open(path, encoding='utf-8') as f:
            src = f.read()
        out = IMPORT.sub(fix, src)
        if out != src:
            with open(path, 'w', encoding='utf-8', newline='') as f:
                f.write(out)
            changed += 1
    print('changed', changed, 'files')


if __name__ == '__main__':
    main()
