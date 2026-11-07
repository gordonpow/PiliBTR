import 'dart:convert';

/// 豎屏（story）推薦的一部影片。
class StoryItem {
  StoryItem({
    required this.aid,
    required this.bvid,
    required this.cid,
    required this.title,
    this.cover,
    this.desc,
    this.duration = 0,
    this.ownerMid = 0,
    this.ownerName,
    this.ownerFace,
    this.followed = false,
    this.view = 0,
    this.danmaku = 0,
    this.reply = 0,
    this.favorite = 0,
    this.coin = 0,
    this.share = 0,
    this.like = 0,
    this.copyright,
    this.width = 0,
    this.height = 0,
    this.rotate = 0,
    this.isVertical = false,
    this.hasLiked = false,
    this.coined = 0,
    this.hasFaved = false,
    this.playerPreload,
  });

  final int aid;
  final String bvid;
  final int cid;
  final String title;
  final String? cover;
  final String? desc;

  /// 秒
  final int duration;

  final int ownerMid;
  final String? ownerName;
  final String? ownerFace;

  /// 已關注 UP 主（`owner.relation.status` 為 2 或 4，或 `req_user.attention`）
  final bool followed;

  // 統計
  final int view;
  final int danmaku;
  final int reply;
  final int favorite;
  final int coin;
  final int share;
  final int like;
  final int? copyright;

  // 尺寸（原始值）
  final int width;
  final int height;
  final int rotate;

  /// 高大於寬（`rotate` 為 1 時寬高互換後判斷）
  final bool isVertical;

  // `req_user`：登入時的按讚、投幣、收藏狀態
  final bool hasLiked;
  final int coined;
  final bool hasFaved;

  /// `uri` 中的 `player_preload`（附帶 dash 播放網址，約 1 小時過期）原始 JSON。
  final Map<String, dynamic>? playerPreload;

  static int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  static bool _flag(dynamic v) => v == true || v == 1 || v == '1';

  /// 解析失敗（缺少 aid 或 bvid）時回傳 null。
  static StoryItem? fromJson(Map<String, dynamic> json) {
    final args = json['player_args'] as Map?;
    final aid = _int(json['param'] ?? args?['aid']);
    final bvid = json['bvid'] as String?;
    final cid = _int(args?['cid']);
    if (aid == 0 || bvid == null || bvid.isEmpty || cid == 0) return null;

    final owner = json['owner'] as Map? ?? const {};
    final stat = json['stat'] as Map? ?? const {};
    final dim = json['dimension'] as Map? ?? const {};
    final reqUser = json['req_user'] as Map? ?? const {};
    final rotate = _int(dim['rotate']);
    var w = _int(dim['width']);
    var h = _int(dim['height']);
    final rawW = w, rawH = h;
    if (rotate == 1) {
      final t = w;
      w = h;
      h = t;
    }
    final status = _int((owner['relation'] as Map?)?['status']);

    Map<String, dynamic>? preload;
    try {
      final raw = Uri.tryParse(
        json['uri'] as String? ?? '',
      )?.queryParameters['player_preload'];
      if (raw != null && raw.isNotEmpty) {
        preload = jsonDecode(raw) as Map<String, dynamic>?;
      }
    } catch (_) {}

    return StoryItem(
      aid: aid,
      bvid: bvid,
      cid: cid,
      title: json['title'] as String? ?? '',
      cover: json['cover'] as String?,
      desc: json['desc'] as String?,
      duration: _int(json['duration']),
      ownerMid: _int(owner['mid']),
      ownerName: owner['name'] as String?,
      ownerFace: owner['face'] as String?,
      followed: status == 2 || status == 4 || _flag(reqUser['attention']),
      view: _int(stat['view']),
      danmaku: _int(stat['danmaku']),
      reply: _int(stat['reply']),
      favorite: _int(stat['favorite']),
      coin: _int(stat['coin']),
      share: _int(stat['share']),
      like: _int(stat['like']),
      copyright: json['copyright'] == null ? null : _int(json['copyright']),
      width: rawW,
      height: rawH,
      rotate: rotate,
      isVertical: h > w,
      hasLiked: _flag(reqUser['like']),
      coined: _int(reqUser['coin']),
      hasFaved: _flag(reqUser['favorite']),
      playerPreload: preload,
    );
  }
}
