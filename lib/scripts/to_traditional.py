"""Convert UI string literals in lib/**/*.dart to Traditional Chinese (Taiwan).

PiliBTR shows its UI in Traditional Chinese. Upstream PiliPlus writes UI
text as Simplified Chinese string literals, so after each merge from
upstream, run this script again:

    pip install opencc
    python lib/scripts/to_traditional.py

Only the text inside string literals changes (comments and code stay).
Literals compared with Simplified text from the Bilibili server are kept:
they are listed in PROTECT as "path:line".

The script is idempotent.
"""
import glob
import os
import re

import opencc

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CJK = re.compile(r'[㐀-鿿]')

# Lines with literals that are compared with server data (keep Simplified).
PROTECT = {
    'lib/models/dynamics/result.dart': ["json['text'] == '投稿视频'"],
    'lib/models/home/rcmd/result.dart': ["== '竖屏'", "contains('赞')", "{'已关注', '新关注'}"],
    'lib/pages/common/reply/reply_controller.dart': ["contains('可发')"],
    'lib/pages/episode_panel/view.dart': ['badge == "会员"'],
    'lib/pages/video/introduction/pgc/widgets/episode.dart': ["contains('连载')", "badge == '会员'"],
    'lib/pages/video/introduction/pgc/widgets/section.dart': ["badge == '会员'"],
    'lib/pages/history/widgets/item.dart': ["badge != '番剧'", "contains('动画')"],
    'lib/pages/member_home/widgets/video_card_v_member_home.dart': ["== '充电专属'"],
    'lib/pages/member_video/widgets/video_card_h_member_video.dart': ["== '充电专属'"],
    'lib/pages/member_video/controller.dart': ["text == '继续播放'"],
    'lib/pages/mine/controller.dart': ["errMsg == '账号未登录'"],
    'lib/utils/login_utils.dart': ["errMsg == '账号未登录'"],
    'lib/pages/video/controller.dart': ["contains('试看')"],
    'lib/pages/video/introduction/ugc/view.dart': ["replaceFirst('发现'"],
    'lib/pages/whisper_detail/widget/chat_item.dart': ["['source'] == '直播'"],
    'lib/pages/whisper_settings/view.dart': ["title == '黑名单'", "title == '消息屏蔽词'"],
    'lib/utils/num_utils.dart': ['[千万亿]', "case '千'", "case '万'", "case '亿'"],
}

# Corrections applied after OpenCC.
FIXUP = {
    '執行緒撕裂者': '線程撕裂者',  # project name (BTR = Bilibili thread ripper)
    '分割槽': '分區',  # 分区 = video category, not disk partition
    '賬': '帳',  # 帳號 is the Taiwan form
    '後臺': '背景',  # background playback
}


def literal_spans(src):
    """Text parts of all string literals, as (start, end)."""
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        'dartlex', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'dartlex.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.spans(src)


def main():
    cc = opencc.OpenCC('s2twp')
    changed = 0
    found = {k: set() for k in PROTECT}
    for path in glob.glob(os.path.join(ROOT, 'lib', '**', '*.dart'), recursive=True):
        rel = os.path.relpath(path, ROOT).replace('\\', '/')
        if rel.startswith('lib/grpc/'):
            continue
        with open(path, encoding='utf-8', newline='') as f:
            src = f.read()
        lines = src.split('\n')
        keep = set()
        for i, line in enumerate(lines):
            for marker in PROTECT.get(rel, ()):
                if marker in line:
                    keep.add(i)
                    found[rel].add(marker)
        out, last = [], 0
        for s, e in literal_spans(src):
            text = src[s:e]
            if not CJK.search(text) or src.count('\n', 0, s) in keep:
                continue
            new = cc.convert(text)
            for a, b in FIXUP.items():
                new = new.replace(a, b)
            if new != text:
                out.append(src[last:s])
                out.append(new)
                last = e
        if out:
            out.append(src[last:])
            new_src = ''.join(out)
            if new_src != src:
                with open(path, 'w', encoding='utf-8', newline='') as f:
                    f.write(new_src)
                changed += 1
    for rel, markers in PROTECT.items():
        for m in markers:
            if m not in found[rel]:
                print(f'warning: protected text not found: {rel}: {m}')
    print(f'converted {changed} files')


if __name__ == '__main__':
    main()
