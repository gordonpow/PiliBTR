import 'package:PiliPlus/common/widgets/zh_material.dart';
import 'package:PiliPlus/models/common/setting_type.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';

/// A node of the settings tree: a category with [children], or a group with
/// setting [items]. The settings themselves stay in the lists of
/// [SettingType] (keys, defaults and behaviour do not change); the tree
/// only places each item of those lists in exactly one group.
class SettingNode {
  SettingNode({
    required this.id,
    required this.title,
    required this.icon,
    this.subtitle,
    this.children = const [],
    this.titles = const {},
    this.defaultFor = const {},
  });

  final String id;
  final String title;
  final String? subtitle;
  final IconData icon;

  /// Sub nodes. Empty for a group.
  final List<SettingNode> children;

  /// Titles ([SettingsModel.effectiveTitle]) of the items in this group.
  final Set<String> titles;

  /// Items of these lists that no group lists by title come here.
  final Set<SettingType> defaultFor;

  /// Items of this group, in the order of the source lists.
  final List<SettingsModel> items = [];

  /// Parent node, null for a root node.
  SettingNode? parent;

  bool get isGroup => children.isEmpty;

  /// Titles from the root to this node, for example 播放 › 字幕.
  String get path {
    final names = <String>[];
    for (SettingNode? n = this; n != null; n = n.parent) {
      names.insert(0, n.title);
    }
    return names.join(' › ');
  }
}

/// The settings tree. Build it once per settings page (the item lists read
/// the current settings when they are built).
class SettingTree {
  SettingTree._(this.roots);

  /// [accountActions] are extra items of the 帳號與隱私 group (switch
  /// account, log out); they need the settings page.
  factory SettingTree.build({
    List<SettingsModel> accountActions = const [],
  }) {
    final roots = _nodes();
    final tree = SettingTree._(roots);
    final groups = <SettingNode>[];
    void visit(SettingNode node, SettingNode? parent) {
      node.parent = parent;
      if (node.isGroup) {
        groups.add(node);
      } else {
        for (final child in node.children) {
          visit(child, node);
        }
      }
    }

    for (final root in roots) {
      visit(root, null);
    }

    final byTitle = <String, SettingNode>{};
    final byType = <SettingType, SettingNode>{};
    for (final group in groups) {
      for (final title in group.titles) {
        assert(!byTitle.containsKey(title), 'title in two groups: $title');
        byTitle[title] = group;
      }
      for (final type in group.defaultFor) {
        byType[type] = group;
      }
    }

    for (final type in SettingType.values) {
      if (type == .webdavSetting || type == .about) continue;
      for (final item in type.settings) {
        final group = byTitle[item.effectiveTitle] ?? byType[type]!;
        group.items.add(item);
        tree._groupOf[item] = group;
      }
    }

    final account = groups.firstWhere((e) => e.id == 'account');
    for (final item in accountActions) {
      account.items.add(item);
      tree._groupOf[item] = account;
    }

    return tree;
  }

  final List<SettingNode> roots;
  final Map<SettingsModel, SettingNode> _groupOf = Map.identity();

  /// All items of the tree, each once, in tree order.
  List<SettingsModel> get allItems {
    final out = <SettingsModel>[];
    void visit(SettingNode node) {
      if (node.isGroup) {
        out.addAll(node.items);
      } else {
        node.children.forEach(visit);
      }
    }

    roots.forEach(visit);
    return out;
  }

  /// Path of the group of [item], for example 播放 › 小視窗與子母畫面.
  String? pathOf(SettingsModel item) => _groupOf[item]?.path;

  static List<SettingNode> _nodes() => [
    SettingNode(
      id: 'play',
      title: '播放',
      subtitle: '畫質、手勢、全螢幕、小視窗、彈幕、字幕',
      icon: Icons.play_circle_outline,
      children: [
        SettingNode(
          id: 'quality',
          title: '畫質與音質',
          subtitle: '畫質、音質、解碼、硬解、音訊輸出',
          icon: Icons.high_quality_outlined,
          defaultFor: {.videoSetting},
          titles: {'超解析度', '音量均衡'},
        ),
        SettingNode(
          id: 'behavior',
          title: '播放行為',
          subtitle: '自動播放、倍速、播放順序、進度條、影片頁',
          icon: Icons.slow_motion_video_outlined,
          defaultFor: {.playSetting},
          titles: {'番劇片頭/片尾跳過型別', '空降助手'},
        ),
        SettingNode(
          id: 'gesture',
          title: '手勢與操作',
          subtitle: '雙擊、滑動調節、全螢幕中間區塊、鍵盤',
          icon: Icons.swipe_outlined,
          titles: {
            '雙擊快退/快進',
            '左右側滑動調節亮度/音量',
            '滾輪調節音量',
            '調節系統亮度',
            '中間滑動進入/退出全螢幕',
            '啟用雙指縮小影片',
            '雙擊快進/快退時長',
            '滑動快進/快退使用相對時長',
            '滑動快進/快退時長',
            '全螢幕手勢反向',
            '全螢幕中間區塊寬度',
            '啟用鍵盤控制',
          },
        ),
        SettingNode(
          id: 'fullscreen',
          title: '全螢幕與旋轉',
          subtitle: '全螢幕方向、自動全螢幕、橫向螢幕、全螢幕按鈕',
          icon: Icons.screen_rotation_outlined,
          titles: {
            '預設全螢幕方向',
            '傾斜角度閾值',
            '自動全螢幕',
            '自動退出全螢幕',
            '全螢幕顯示鎖定按鈕',
            '全螢幕顯示截圖按鈕',
            '全螢幕顯示電池電量',
            '全螢幕展示點贊/投幣/收藏等操作按鈕',
            '全螢幕 SuperChat 設定',
            '直向螢幕擴大展示',
            '橫向螢幕自動展開影片簡介',
            '橫向螢幕分P/合集列表顯示在Tab欄',
            '橫向螢幕播放頁在側欄開啟UP主頁',
            '橫向螢幕在側欄開啟圖片預覽',
            '播放頁移除安全邊距',
          },
        ),
        SettingNode(
          id: 'mini',
          title: '小視窗與子母畫面',
          subtitle: '返回時縮小、小視窗大小、子母畫面、背景播放',
          icon: Icons.picture_in_picture_alt_outlined,
          titles: {
            '返回時縮小為小視窗',
            '斜下滑縮小為小視窗',
            '小視窗大小',
            '子母畫面',
            '畫中畫不載入彈幕',
            '背景播放',
            '背景音訊服務',
            '最小化時暫停/還原時播放',
          },
        ),
        SettingNode(
          id: 'danmaku',
          title: '彈幕',
          subtitle: '彈幕開關、點選彈幕、行高、合併彈幕',
          icon: Icons.subtitles_outlined,
          defaultFor: {.dmSetting},
        ),
        SettingNode(
          id: 'subtitle',
          title: '字幕',
          subtitle: '自動啟用字幕、字幕偏好、字幕位置',
          icon: Icons.closed_caption_outlined,
          titles: {
            '自動啟用字幕',
            '長按字幕按鈕複製字幕',
            '啟用拖拽字幕調整底部邊距',
            '翻譯服務',
            'DeepL 金鑰',
            'Google Cloud 金鑰',
            '離線翻譯模型',
          },
        ),
      ],
    ),
    SettingNode(
      id: 'network',
      title: '網路與加速',
      subtitle: 'BTR、CDN、緩衝、代理、重試、HTTP/2',
      icon: Icons.speed_outlined,
      titles: {
        'CDN 設定',
        '直播 CDN 設定',
        'CDN 測速',
        '網速單位',
        '音訊不跟隨 CDN 設定',
        'B站定向流量支援',
        '免登入1080P',
        '緩衝大小',
        '緩衝時長',
        '快速起播',
        '直播緩衝大小',
        '直播緩衝時長',
        '啟用HTTP/2',
        '連線重試次數',
        '連線重試間隔',
        '停用 SSL 證書驗證',
        '設定代理',
      },
    ),
    SettingNode(
      id: 'content',
      title: '內容',
      subtitle: '首頁推薦、評論、動態、搜尋',
      icon: Icons.dashboard_outlined,
      children: [
        SettingNode(
          id: 'recommend',
          title: '首頁推薦',
          subtitle: '推薦來源、預覽、重新整理、過濾器',
          icon: Icons.explore_outlined,
          defaultFor: {.recommendSetting},
          titles: {'顯示熱門推薦', '展示追番時間表', '預載入畫面上的影片', '同時預載影片數'},
        ),
        SettingNode(
          id: 'reply',
          title: '評論',
          subtitle: '過濾、遮蔽、記錄、預設展示',
          icon: Icons.comment_outlined,
          defaultFor: {.replySetting},
        ),
        SettingNode(
          id: 'dynamic',
          title: '動態',
          subtitle: '過濾、遮蔽、瀑布流、未讀標記',
          icon: Icons.dynamic_feed_outlined,
          defaultFor: {.dynSetting},
          titles: {
            '動態頁啟用瀑布流',
            '動態頁UP主顯示位置',
            '動態頁顯示所有已關注UP主',
            '動態頁展開正在直播UP列表',
            '動態未讀標記',
            '檢查未讀動態',
          },
        ),
        SettingNode(
          id: 'search',
          title: '搜尋',
          subtitle: '搜尋建議、搜尋歷史、搜尋發現',
          icon: Icons.search,
          titles: {'搜尋建議', '記錄搜尋歷史', '大家都在搜', '搜尋發現', '搜尋預設詞'},
        ),
      ],
    ),
    SettingNode(
      id: 'style',
      title: '外觀',
      subtitle: '主題、版面、字型、圖片、動畫',
      icon: Icons.palette_outlined,
      children: [
        SettingNode(
          id: 'theme',
          title: '主題與顏色',
          subtitle: '主題模式、純黑主題、應用主題',
          icon: Icons.color_lens_outlined,
          titles: {
            '主題模式',
            '純黑主題',
            '應用主題',
            '影片播放頁使用深色主題',
            '深色下圖片顏色疊加',
            '氣泡提示不透明度',
          },
        ),
        SettingNode(
          id: 'layout',
          title: '版面與導覽',
          subtitle: '橫向螢幕適配、側邊欄、底欄、首頁標籤、卡片排數',
          icon: Icons.view_quilt_outlined,
          defaultFor: {.styleSetting},
        ),
        SettingNode(
          id: 'font',
          title: '字型與縮放',
          subtitle: '語言、翻譯影片內容、開場動畫、字型、介面縮放',
          icon: Icons.text_fields,
          titles: {'語言', '翻譯影片內容', '開場動畫', 'App字型設定', '介面縮放'},
        ),
        SettingNode(
          id: 'image',
          title: '圖片',
          subtitle: '圖片質量、Live Photo、圖片選單',
          icon: Icons.image_outlined,
          titles: {
            '圖片質量',
            '檢視大圖質量',
            '預覽 Live Photo',
            '靜默下載圖片',
            '長按/右鍵顯示圖片選單',
          },
        ),
        SettingNode(
          id: 'animation',
          title: '動畫',
          subtitle: '頁面動畫、螢幕幀率、滑動手勢',
          icon: Icons.animation,
          titles: {
            '首頁切換頁面動畫',
            '頁面過渡動畫',
            '滑動動畫彈簧引數',
            '螢幕幀率',
            '側滑關閉二級頁面',
            '重新整理指示器高度',
          },
        ),
      ],
    ),
    SettingNode(
      id: 'account',
      title: '帳號與隱私',
      subtitle: '黑名單、帳號模式、切換帳號、退出登入',
      icon: Icons.privacy_tip_outlined,
      defaultFor: {.privacySetting},
    ),
    SettingNode(
      id: 'storage',
      title: '下載與儲存',
      subtitle: '下載路徑、快取路徑與大小',
      icon: Icons.folder_outlined,
      titles: {'下載路徑', '快取路徑', '允許三方APP訪問私有儲存', '最大快取大小'},
    ),
    SettingNode(
      id: 'other',
      title: '其他',
      subtitle: '震動、外部瀏覽器、快速收藏、AI 總結等',
      icon: Icons.more_horiz,
      defaultFor: {.extraSetting},
    ),
  ];
}
