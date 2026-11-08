import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/pages/rcmd/controller.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/widgets/select_dialog.dart';
import 'package:PiliPlus/utils/recommend_filter.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart' hide StatefulBuilder;

const _visiblePreloadLabels = ['關閉', '僅 Wi-Fi', '一律'];

Future<void> _showVisiblePreloadDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<int>(
    context: context,
    builder: (context) => SelectDialog<int>(
      title: '預載入畫面上的影片',
      value: Pref.visiblePreloadMode,
      values: [
        for (var i = 0; i < _visiblePreloadLabels.length; i++)
          (i, _visiblePreloadLabels[i]),
      ],
    ),
  );
  if (res != null) {
    await GStorage.setting.put(SettingBoxKey.visiblePreloadMode, res);
    setState();
  }
}

List<SettingsModel> get recommendSettings => [
  NormalModel(
    title: '預載入畫面上的影片',
    leading: const Icon(Icons.downloading_outlined),
    getSubtitle: () =>
        '當前：${_visiblePreloadLabels[Pref.visiblePreloadMode.clamp(0, 2)]}（停止捲動後預先準備畫面上所有影片，會多用流量）',
    onTap: _showVisiblePreloadDialog,
  ),
  const SwitchModel(
    title: '首頁使用app端推薦',
    subtitle: '若web端推薦不太符合預期，可嘗試切換至app端推薦',
    leading: Icon(Icons.model_training_outlined),
    setKey: SettingBoxKey.appRcmd,
    defaultVal: true,
    needReboot: true,
  ),
  const SwitchModel(
    title: '長按影片預覽',
    subtitle: '在首頁長按影片卡片，直接在卡片上預覽影片（預設靜音）',
    leading: Icon(Icons.preview_outlined),
    setKey: SettingBoxKey.videoCardPreview,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '滑動時預覽',
    subtitle: '在首頁滑動時，手指停在哪張影片卡片上就預覽哪一張（需開啟長按影片預覽）',
    leading: Icon(Icons.swipe_vertical_outlined),
    setKey: SettingBoxKey.videoPreviewOnSwipe,
    defaultVal: true,
  ),
  SwitchModel(
    title: '保留首頁推薦重新整理',
    subtitle: '下拉重新整理時保留上次內容',
    leading: const Icon(Icons.refresh),
    setKey: SettingBoxKey.enableSaveLastData,
    defaultVal: true,
    onChanged: (value) {
      try {
        Get.find<RcmdController>()
          ..enableSaveLastData = value
          ..lastRefreshAt = null;
      } catch (e) {
        if (kDebugMode) debugPrint('$e');
      }
    },
  ),
  SwitchModel(
    title: '顯示上次看到位置提示',
    subtitle: '保留上次推薦時，在上次重新整理位置顯示提示',
    leading: const Icon(Icons.tips_and_updates_outlined),
    setKey: SettingBoxKey.savedRcmdTip,
    defaultVal: false,
    onChanged: (value) {
      try {
        Get.find<RcmdController>()
          ..savedRcmdTip = value
          ..lastRefreshAt = null;
      } catch (e) {
        if (kDebugMode) debugPrint('$e');
      }
    },
  ),
  getVideoFilterSelectModel(
    title: '點贊率',
    suffix: '%',
    key: SettingBoxKey.minLikeRatioForRecommend,
    values: [0, 1, 2, 3, 4],
    onChanged: (value) => RecommendFilter.minLikeRatioForRecommend = value,
    filterScope: 'Web推薦、熱門、分區',
  ),
  getBanWordModel(
    title: '標題關鍵詞過濾',
    key: SettingBoxKey.banWordForRecommend,
    onChanged: (value) {
      RecommendFilter.rcmdRegExp = value;
      RecommendFilter.enableFilter = value.pattern.isNotEmpty;
    },
    banScope: '推薦、熱門、分區、相關影片',
  ),
  getBanWordModel(
    title: '分區關鍵詞過濾',
    key: SettingBoxKey.banWordForZone,
    onChanged: (value) {
      VideoHttp.zoneRegExp = value;
      VideoHttp.enableFilter = value.pattern.isNotEmpty;
    },
    banScope: 'App推薦、熱門、分區',
  ),
  getVideoFilterSelectModel(
    title: '影片時長',
    suffix: 's',
    key: SettingBoxKey.minDurationForRcmd,
    values: [0, 30, 60, 90, 120],
    onChanged: (value) => RecommendFilter.minDurationForRcmd = value,
    filterScope: '推薦、相關影片',
  ),
  getVideoFilterSelectModel(
    title: '播放量',
    key: SettingBoxKey.minPlayForRcmd,
    values: [0, 50, 100, 500, 1000],
    onChanged: (value) => RecommendFilter.minPlayForRcmd = value,
    filterScope: '推薦、熱門、分區、相關影片',
  ),
  SwitchModel(
    title: '已關注UP豁免推薦過濾',
    subtitle: '推薦中已關注使用者釋出的內容不會被過濾',
    leading: const Icon(Icons.favorite_border_outlined),
    setKey: SettingBoxKey.exemptFilterForFollowed,
    defaultVal: true,
    onChanged: (value) => RecommendFilter.exemptFilterForFollowed = value,
  ),
  SwitchModel(
    title: '過濾器也應用於詳情頁相關影片',
    subtitle: '其它（如熱門影片、搜尋等）均不受過濾器影響，無法豁免相關影片中的已關注UP',
    leading: const Icon(Icons.explore_outlined),
    setKey: SettingBoxKey.applyFilterToRelatedVideos,
    defaultVal: true,
    onChanged: (value) => RecommendFilter.applyFilterToRelatedVideos = value,
  ),
];
