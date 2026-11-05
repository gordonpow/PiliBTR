import 'dart:io' show Platform, Directory;

import 'package:PiliPlus/common/widgets/custom_icon.dart';
import 'package:PiliPlus/common/widgets/dialog/simple_dialog_option.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart'
    show RefreshIndicator, displacement, refreshDragExtent;
import 'package:PiliPlus/common/widgets/gesture/horizontal_drag_gesture_recognizer.dart'
    show deviceTouchSlop, touchSlopH;
import 'package:PiliPlus/common/widgets/image_grid/image_grid_view.dart'
    show ImageGridView, ImageModel;
import 'package:PiliPlus/http/fav.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/sponsor_block/skip_type.dart';
import 'package:PiliPlus/pages/common/slide/common_slide_page.dart';
import 'package:PiliPlus/pages/home/controller.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/widgets/slider_dialog.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/android/bindings.g.dart';
import 'package:PiliPlus/utils/desktop/window_controller.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/filtering_text.dart';
import 'package:PiliPlus/utils/image_utils.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart' hide RefreshIndicator;

List<SettingsModel> get extraSettings => [
  if (PlatformUtils.isDesktop) ...[
    SwitchModel(
      title: '退出時最小化',
      leading: const Icon(Icons.exit_to_app),
      setKey: SettingBoxKey.minimizeOnExit,
      defaultVal: true,
      onChanged: (value) => WindowController.instance.minimizeOnExit = value,
    ),
    NormalModel(
      title: '快取路徑',
      getSubtitle: () => downloadPath,
      leading: const Icon(Icons.storage),
      onTap: _showDownPathDialog,
    ),
  ] else if (Platform.isAndroid)
    SwitchModel(
      title: '允許三方APP訪問私有儲存',
      subtitle: '允許三方APP（例如MT管理器）通過訪問外部儲存的方式訪問私有儲存下的檔案',
      leading: const Icon(Icons.storage),
      setKey: SettingBoxKey.enableDocProvider,
      defaultVal: Pref.enableDocProvider,
      onChanged: AndroidHelper.updateDocProvider,
    ),
  SplitModel(
    normalModel: const NormalModel.split(
      title: '空降助手',
      subtitle: '點選配置',
      leading: Icon(CustomIcons.shield_play_arrow),
    ),
    switchModel: SwitchModel.split(
      defaultVal: false,
      setKey: SettingBoxKey.enableSponsorBlock,
      onTap: (context) => Get.toNamed('/sponsorBlock'),
    ),
  ),
  PopupModel<SkipType>(
    title: '番劇片頭/片尾跳過型別',
    leading: const Icon(MdiIcons.debugStepOver),
    value: () => Pref.pgcSkipType,
    items: SkipType.values,
    onSelected: (value, setState) => GStorage.setting
        .put(SettingBoxKey.pgcSkipType, value.index)
        .whenComplete(setState),
  ),
  const SwitchModel(
    title: '停用 SSL 證書驗證',
    subtitle: '謹慎開啟，停用容易受到中間人攻擊',
    leading: Icon(Icons.security),
    needReboot: true,
    setKey: SettingBoxKey.badCertificateCallback,
  ),
  const SwitchModel(
    title: '使用外部瀏覽器開啟連結',
    leading: Icon(Icons.open_in_browser),
    setKey: SettingBoxKey.openInBrowser,
    defaultVal: false,
  ),
  NormalModel(
    title: '橫向滑動閾值',
    getSubtitle: () => '當前:「${Pref.touchSlopH}」，系統預設值: $deviceTouchSlop',
    onTap: _showTouchSlopDialog,
    leading: const Icon(Icons.pan_tool_alt_outlined),
  ),
  NormalModel(
    title: '重新整理指示器高度',
    leading: const Icon(Icons.height),
    getSubtitle: () =>
        '當前指示器高度: ${Pref.refreshDisplacement}, 重新整理滑動距離: $refreshDragExtent',
    onTap: _showRefreshDialog,
  ),
  const SwitchModel(
    title: '顯示熱門推薦',
    subtitle: '熱門頁面顯示每週必看等推薦內容入口',
    leading: Icon(Icons.local_fire_department_outlined),
    setKey: SettingBoxKey.showHotRcmd,
    defaultVal: false,
    needReboot: true,
  ),
  const SwitchModel(
    title: '搜尋建議',
    leading: Icon(Icons.search),
    setKey: SettingBoxKey.searchSuggestion,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '記錄搜尋歷史',
    leading: Icon(Icons.history),
    setKey: SettingBoxKey.recordSearchHistory,
    defaultVal: true,
  ),
  SwitchModel(
    title: '預覽 Live Photo',
    subtitle: '開啟則以影片形式預覽 Live Photo，否則預覽靜態圖片',
    leading: const Icon(Icons.image_outlined),
    setKey: SettingBoxKey.enableLivePhoto,
    defaultVal: true,
    onChanged: (value) => ImageModel.enableLivePhoto = value,
  ),
  SwitchModel(
    title: '側滑關閉二級頁面',
    leading: const Icon(CustomIcons.touch_app_rotate_270),
    setKey: SettingBoxKey.slideDismissReplyPage,
    defaultVal: Platform.isIOS,
    onChanged: (value) => CommonSlideMixin.slideDismissReplyPage = value,
  ),
  const SwitchModel(
    title: '展示追番時間表',
    leading: Icon(MdiIcons.chartTimelineVariantShimmer),
    setKey: SettingBoxKey.showPgcTimeline,
    defaultVal: true,
    needReboot: true,
  ),
  SwitchModel(
    title: '靜默下載圖片',
    subtitle: '不顯示下載 Loading 彈窗',
    leading: const Icon(Icons.download_for_offline_outlined),
    setKey: SettingBoxKey.silentDownImg,
    defaultVal: false,
    onChanged: (value) => ImageUtils.silentDownImg = value,
  ),
  SwitchModel(
    title: '長按/右鍵顯示圖片選單',
    leading: const Icon(Icons.menu),
    setKey: SettingBoxKey.enableImgMenu,
    defaultVal: false,
    onChanged: (value) => ImageGridView.enableImgMenu = value,
  ),
  SwitchModel(
    setKey: SettingBoxKey.feedBackEnable,
    onChanged: (value) {
      enableFeedback = value;
      feedBack();
    },
    leading: const Icon(Icons.vibration_outlined),
    title: '震動反饋',
    subtitle: '請確定手機設定中已開啟震動反饋',
  ),
  const SwitchModel(
    title: '大家都在搜',
    subtitle: '是否展示「大家都在搜」',
    leading: Icon(Icons.data_thresholding_outlined),
    setKey: SettingBoxKey.enableHotKey,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '搜尋發現',
    subtitle: '是否展示「搜尋發現」',
    leading: Icon(Icons.search_outlined),
    setKey: SettingBoxKey.enableSearchRcmd,
    defaultVal: true,
  ),
  SwitchModel(
    title: '搜尋預設詞',
    subtitle: '是否展示搜尋框預設詞',
    leading: const Icon(Icons.whatshot_outlined),
    setKey: SettingBoxKey.enableSearchWord,
    defaultVal: false,
    onChanged: (val) {
      try {
        final controller = Get.find<HomeController>()..enableSearchWord = val;
        if (val) {
          controller.querySearchDefault();
        } else {
          controller.defaultSearch.value = '';
        }
      } catch (_) {}
    },
  ),
  const SwitchModel(
    title: '快速收藏',
    subtitle: '點選設定預設收藏夾\n點按收藏至預設，長按選擇資料夾',
    leading: Icon(Icons.bookmark_add_outlined),
    setKey: SettingBoxKey.enableQuickFav,
    onTap: _showFavDialog,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '啟用AI總結',
    subtitle: '影片詳情頁開啟AI總結',
    leading: Icon(Icons.engineering_outlined),
    setKey: SettingBoxKey.enableAi,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '訊息頁停用"收到的贊"功能',
    subtitle: '禁止開啟入口，降低網路社交依賴',
    leading: Icon(Icons.beach_access_outlined),
    setKey: SettingBoxKey.disableLikeMsg,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '啟用HTTP/2',
    leading: Icon(Icons.swap_horizontal_circle_outlined),
    setKey: SettingBoxKey.enableHttp2,
    defaultVal: false,
    needReboot: true,
  ),
  const NormalModel(
    title: '連線重試次數',
    subtitle: '為0時停用',
    leading: Icon(Icons.repeat),
    onTap: _showReplyCountDialog,
  ),
  const NormalModel(
    title: '連線重試間隔',
    subtitle: '實際間隔 = 間隔 * 第x次重試',
    leading: Icon(Icons.more_time_outlined),
    onTap: _showReplyDelayDialog,
  ),
  const SplitModel(
    normalModel: NormalModel.split(
      title: '設定代理',
      subtitle: '設定代理 host:port',
      leading: Icon(Icons.airplane_ticket_outlined),
    ),
    switchModel: SwitchModel.split(
      defaultVal: false,
      setKey: SettingBoxKey.enableSystemProxy,
      onTap: _showProxyDialog,
    ),
  ),
  NormalModel(
    title: '最大快取大小',
    getSubtitle: () => '當前最大快取大小: 「${Pref.maxCacheSize.formatSize}」',
    leading: const Icon(Icons.delete_outlined),
    onTap: _showCacheDialog,
  ),
];

void _showDownPathDialog(BuildContext context, VoidCallback setState) {
  showDialog(
    context: context,
    builder: (context) => SimpleDialog(
      clipBehavior: Clip.hardEdge,
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        DialogOption(
          onPressed: () {
            Get.back();
            PathUtils.openDir(downloadPath);
          },
          child: const Text('開啟'),
        ),
        DialogOption(
          onPressed: () {
            Get.back();
            Utils.copyText(downloadPath);
          },
          child: const Text('複製', style: TextStyle(fontSize: 14)),
        ),
        DialogOption(
          onPressed: () {
            Get.back();
            final defPath = defDownloadPath;
            if (downloadPath == defPath) return;
            downloadPath = defPath;
            setState();
            Get.find<DownloadService>().initDownloadList();
            GStorage.setting.delete(SettingBoxKey.downloadPath);
          },
          child: const Text('重置', style: TextStyle(fontSize: 14)),
        ),
        DialogOption(
          onPressed: () async {
            Get.back();
            final path = await FilePicker.getDirectoryPath(
              initialDirectory: Directory(downloadPath).existsSync()
                  ? downloadPath
                  : null,
            );
            if (path == null || path == downloadPath) return;
            downloadPath = path;
            setState();
            Get.find<DownloadService>().initDownloadList();
            GStorage.setting.put(SettingBoxKey.downloadPath, path);
          },
          child: const Text('設定新路徑', style: TextStyle(fontSize: 14)),
        ),
      ],
    ),
  );
}

void _showTouchSlopDialog(BuildContext context, VoidCallback setState) {
  String initialValue = Pref.touchSlopH.toString();
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('橫向滑動閾值'),
      content: TextFormField(
        autofocus: true,
        initialValue: initialValue,
        keyboardType: const .numberWithOptions(decimal: true),
        onChanged: (value) => initialValue = value,
        inputFormatters: FilteringText.decimal,
      ),
      actions: [
        TextButton(
          onPressed: Get.back,
          child: Text(
            '取消',
            style: TextStyle(color: ColorScheme.of(context).outline),
          ),
        ),
        TextButton(
          onPressed: () async {
            try {
              final val = double.parse(initialValue);
              Get.back();
              touchSlopH = val;
              await GStorage.setting.put(SettingBoxKey.touchSlopH, val);
              setState();
            } catch (e) {
              SmartDialog.showToast(e.toString());
            }
          },
          child: const Text('確定'),
        ),
      ],
    ),
  );
}

Future<void> _showRefreshDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<double>(
    context: context,
    builder: (context) => SliderDialog(
      title: const Text('重新整理指示器高度'),
      min: 10.0,
      max: 100.0,
      divisions: 9,
      value: Pref.refreshDisplacement,
    ),
  );
  if (res != null) {
    displacement = res;
    await GStorage.setting.put(SettingBoxKey.refreshDisplacement, res);
    if (WidgetsBinding.instance.rootElement case final context?) {
      context.visitChildElements(_visitor);
    }
    setState();
  }
}

void _visitor(Element context) {
  if (!context.mounted) return;
  if (context.widget is RefreshIndicator) {
    context.markNeedsBuild();
  } else {
    context.visitChildren(_visitor);
  }
}

Future<void> _showFavDialog(BuildContext context) async {
  if (Accounts.main.isLogin) {
    final res = await FavHttp.allFavFolders(Accounts.main.mid);
    if (res case Success(:final response)) {
      final list = response.list;
      if (list == null || list.isEmpty) {
        return;
      }
      final quickFavId = Pref.quickFavId;
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          clipBehavior: Clip.hardEdge,
          title: const Text('選擇預設收藏夾'),
          contentPadding: const EdgeInsets.only(top: 5, bottom: 18),
          content: SingleChildScrollView(
            child: RadioGroup(
              onChanged: (value) {
                Get.back();
                GStorage.setting.put(SettingBoxKey.quickFavId, value);
                SmartDialog.showToast('設定成功');
              },
              groupValue: quickFavId,
              child: Column(
                children: list
                    .map(
                      (item) => RadioListTile(
                        toggleable: true,
                        dense: true,
                        title: Text(item.title),
                        value: item.id,
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
      );
    } else {
      res.toast();
    }
  }
}

Future<void> _showReplyCountDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<double>(
    context: context,
    builder: (context) => SliderDialog(
      title: const Text('連線重試次數'),
      min: 0,
      max: 8,
      divisions: 8,
      precise: 0,
      value: Pref.retryCount.toDouble(),
    ),
  );
  if (res != null) {
    await GStorage.setting.put(SettingBoxKey.retryCount, res.toInt());
    setState();
    SmartDialog.showToast('重啟生效');
  }
}

Future<void> _showReplyDelayDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<double>(
    context: context,
    builder: (context) => SliderDialog(
      title: const Text('連線重試間隔'),
      min: 0,
      max: 1000,
      divisions: 10,
      precise: 0,
      value: Pref.retryDelay.toDouble(),
      suffix: 'ms',
    ),
  );
  if (res != null) {
    await GStorage.setting.put(SettingBoxKey.retryDelay, res.toInt());
    setState();
    SmartDialog.showToast('重啟生效');
  }
}

void _showProxyDialog(BuildContext context) {
  String systemProxyHost = Pref.systemProxyHost;
  String systemProxyPort = Pref.systemProxyPort;

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('設定代理'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 6),
          TextFormField(
            initialValue: systemProxyHost,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '請輸入Host，使用 . 分割',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(6)),
              ),
            ),
            onChanged: (e) => systemProxyHost = e,
          ),
          const SizedBox(height: 10),
          TextFormField(
            initialValue: systemProxyPort,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '請輸入Port',
              border: OutlineInputBorder(borderRadius: .all(.circular(6))),
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (e) => systemProxyPort = e,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: Get.back,
          child: Text(
            '取消',
            style: TextStyle(color: ColorScheme.of(context).outline),
          ),
        ),
        TextButton(
          onPressed: () {
            Get.back();
            GStorage.setting.put(
              SettingBoxKey.systemProxyHost,
              systemProxyHost,
            );
            GStorage.setting.put(
              SettingBoxKey.systemProxyPort,
              systemProxyPort,
            );
          },
          child: const Text('確認'),
        ),
      ],
    ),
  );
}

void _showCacheDialog(BuildContext context, VoidCallback setState) {
  String valueStr = '';
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('最大快取大小'),
      content: TextField(
        maxLength: 6,
        autofocus: true,
        onChanged: (value) => valueStr = value,
        keyboardType: TextInputType.number,
        inputFormatters: FilteringText.decimal,
        decoration: const InputDecoration(suffixText: 'MB'),
      ),
      actions: [
        TextButton(
          onPressed: Get.back,
          child: Text(
            '取消',
            style: TextStyle(color: ColorScheme.of(context).outline),
          ),
        ),
        TextButton(
          onPressed: () async {
            try {
              final val = num.parse(valueStr);
              Get.back();
              await GStorage.setting.put(
                SettingBoxKey.maxCacheSize,
                val * 1024 * 1024,
              );
              setState();
            } catch (e) {
              SmartDialog.showToast(e.toString());
            }
          },
          child: const Text('確定'),
        ),
      ],
    ),
  );
}
