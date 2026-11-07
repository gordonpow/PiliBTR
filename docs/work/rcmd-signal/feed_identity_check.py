# -*- coding: utf-8 -*-
"""比對 /x/v2/feed/index 舊參數（android_i）與新參數（android_hd）的回應結構。
不帶 access_key，不輸出任何帳號憑證。"""
import hashlib, json, random, urllib.parse, urllib.request, time

APPKEY = 'dfca71928277209b'
APPSEC = 'b5475a8825547a4fc26c7d518eaaa02e'
URL = 'https://app.bilibili.com/x/v2/feed/index'
TRACE = '11111111111111111111111111111111:1111111111111111:0:0'
UA = ('Mozilla/5.0 BiliDroid/2.0.1 (bbcallen@gmail.com) os/android model/android_hd '
      'mobi_app/android_hd build/2001100 channel/master innerVer/2001100 osVer/15 network/2')
STAT_OLD = '{"appId":1,"platform":3,"version":"8.43.0","abtest":""}'
STAT_NEW = '{"appId":5,"platform":3,"version":"2.0.1","abtest":""}'
KEYS = ['card_goto', 'player_args', 'args', 'param', 'track_id']


def fake_buvid():
    return 'XY' + ''.join(random.choice('0123456789ABCDEF') for _ in range(35))


def sign(params):
    p = dict(params)
    p['appkey'] = APPKEY
    p['ts'] = str(int(time.time()))
    q = '&'.join('%s=%s' % (urllib.parse.quote(k, safe=''), urllib.parse.quote(str(p[k]), safe=''))
                 for k in sorted(p))
    p['sign'] = hashlib.md5((q + APPSEC).encode()).hexdigest()
    return p


def call(mobi_app, build, statistics, buvid):
    params = {
        'build': build, 'c_locale': 'zh_CN', 'channel': 'master', 'column': 2,
        'device': 'phone', 'device_name': 'android', 'device_type': 0,
        'disable_rcmd': 0, 'flush': 8, 'fnval': 976, 'fnver': 0, 'force_host': 2,
        'fourk': 1, 'guidance': 1, 'https_url_req': 1, 'idx': 0, 'mobi_app': mobi_app,
        'network': 'wifi', 'platform': 'android', 'player_net': 1, 'pull': 'true',
        'qn': 32, 'recsys_mode': 0, 's_locale': 'zh_CN', 'splash_id': '',
        'statistics': statistics, 'voice_balance': 0,
    }
    url = URL + '?' + urllib.parse.urlencode(sign(params), quote_via=urllib.parse.quote)
    headers = {
        'buvid': buvid, 'env': 'prod', 'app-key': 'android_hd', 'User-Agent': UA,
        'x-bili-trace-id': TRACE, 'bili-http-engine': 'cronet',
    }
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read().decode())


def summarize(name, d):
    items = (d.get('data') or {}).get('items') or []
    present = {k: sum(1 for i in items if k in i) for k in KEYS}
    print('%s: code=%s message=%s items=%d' % (name, d.get('code'), d.get('message'), len(items)))
    print('  key presence (cards having key / total): %s' % json.dumps(present))
    print('  card_goto values: %s' % sorted({str(i.get('card_goto')) for i in items}))
    return d.get('code') == 0 and len(items) > 0


if __name__ == '__main__':
    buvid = fake_buvid()
    ok = []
    for name, m, b, s in [('OLD android_i/8430300/appId1', 'android_i', 8430300, STAT_OLD),
                          ('NEW android_hd/2001100/appId5', 'android_hd', 2001100, STAT_NEW)]:
        try:
            ok.append(summarize(name, call(m, b, s, buvid)))
        except Exception as e:
            print('%s: ERROR %s' % (name, e))
            ok.append(False)
    print('RESULT: %s' % ('PASS' if all(ok) else 'FAIL'))
