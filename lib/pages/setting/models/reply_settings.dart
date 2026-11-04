import 'dart:io' show Platform;

import 'package:PiliPlus/common/widgets/custom_icon.dart';
import 'package:PiliPlus/grpc/reply.dart';
import 'package:PiliPlus/models/common/reply/reply_sort_type.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/video/reply/widgets/reply_item_grpc.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart' hide RefreshIndicator;

List<SettingsModel> get replySettings => [
  const SwitchModel(
    title: '顯示影片評論',
    leading: Icon(MdiIcons.commentTextOutline),
    setKey: SettingBoxKey.showVideoReply,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '顯示番劇評論',
    leading: Icon(MdiIcons.commentTextOutline),
    setKey: SettingBoxKey.showBangumiReply,
    defaultVal: true,
  ),
  NormalModel(
    title: '評論摺疊行數',
    subtitle: '0行為不折疊',
    leading: const Icon(Icons.compress),
    getTrailing: (theme) => Text(
      '${ReplyItemGrpc.replyLengthLimit}行',
      style: theme.textTheme.titleSmall,
    ),
    onTap: _showReplyLengthDialog,
  ),
  const SwitchModel(
    title: '記錄評論',
    leading: Icon(Icons.message_outlined),
    setKey: SettingBoxKey.saveReply,
    defaultVal: true,
    needReboot: true,
  ),
  const SwitchModel(
    title: '發評反詐',
    subtitle: '傳送評論後檢查評論是否可見',
    leading: Icon(CustomIcons.shield_reply),
    setKey: SettingBoxKey.enableCommAntifraud,
    defaultVal: false,
  ),
  if (Platform.isAndroid)
    const SwitchModel(
      title: '使用「嗶哩發評反詐」檢查評論',
      leading: Icon(
        FontAwesomeIcons.b,
        size: 22,
      ),
      setKey: SettingBoxKey.biliSendCommAntifraud,
      defaultVal: false,
    ),
  SwitchModel(
    title: '遮蔽帶貨評論',
    leading: const Icon(CustomIcons.shopping_bag_not_interested),
    setKey: SettingBoxKey.antiGoodsReply,
    defaultVal: false,
    onChanged: (value) => ReplyGrpc.antiGoodsReply = value,
  ),
  const NormalModel(
    title: '遮蔽評論@數量',
    getSubtitle: _replyAtBlockSubtitle,
    leading: Icon(Icons.pin_outlined),
    onTap: _showReplyAtBlockDialog,
  ),
  const SwitchModel(
    title: '遮蔽只包含@的評論',
    leading: Icon(Icons.alternate_email),
    setKey: SettingBoxKey.blockAtOnlyReply,
    onChanged: _onBlockAtOnlyReplyChanged,
  ),
  const SwitchModel(
    title: '遮蔽複製簡介評論',
    leading: Icon(Icons.summarize),
    setKey: SettingBoxKey.filterIntro,
    defaultVal: false,
  ),
  getBanWordModel(
    title: '評論關鍵詞過濾',
    key: SettingBoxKey.banWordForReply,
    onChanged: (value) {
      ReplyGrpc.replyRegExp = value;
      ReplyGrpc.enableFilter = value.pattern.isNotEmpty;
    },
  ),
  SwitchModel(
    title: '評論區搜尋關鍵詞',
    subtitle: '展示評論區搜尋關鍵詞',
    leading: const Icon(Icons.search_outlined),
    setKey: SettingBoxKey.enableWordRe,
    defaultVal: false,
    onChanged: (value) => ReplyItemGrpc.enableWordRe = value,
  ),
  const SwitchModel(
    title: '預設展示評論區',
    subtitle: '在影片詳情頁預設切換至評論區頁（僅Tab型佈局）',
    leading: Icon(Icons.mode_comment_outlined),
    setKey: SettingBoxKey.defaultShowComment,
    defaultVal: false,
  ),
  PopupModel(
    title: '評論展示',
    leading: const Icon(Icons.whatshot_outlined),
    value: () => Pref.replySortType,
    items: ReplySortType.values.take(2),
    onSelected: (value, setState) => GStorage.setting
        .put(SettingBoxKey.replySortType, value.index)
        .whenComplete(setState),
  ),
  PopupModel(
    title: '樓中樓評論展示',
    leading: const Icon(Icons.subdirectory_arrow_right_outlined),
    value: () => Pref.reply2SortType,
    items: ReplySortType.values.take(2),
    onSelected: (value, setState) => GStorage.setting
        .put(SettingBoxKey.reply2SortType, value.index)
        .whenComplete(setState),
  ),
];

void _showReplyLengthDialog(BuildContext context, VoidCallback setState) {
  String replyLengthLimit = ReplyItemGrpc.replyLengthLimit.toString();
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('評論摺疊行數'),
      content: TextFormField(
        autofocus: true,
        initialValue: replyLengthLimit,
        keyboardType: TextInputType.number,
        onChanged: (value) => replyLengthLimit = value,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(suffixText: '行'),
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
              final val = int.parse(replyLengthLimit);
              Get.back();
              ReplyItemGrpc.replyLengthLimit = val == 0 ? null : val;
              await GStorage.setting.put(SettingBoxKey.replyLengthLimit, val);
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

String _replyAtBlockSubtitle() {
  final blockReplyAtCount = Pref.blockReplyAtCount;
  if (blockReplyAtCount == null) {
    return '停用';
  }
  return '遮蔽$blockReplyAtCount個@及以上的評論';
}

Future<void> _showReplyAtBlockDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  void onChanged([int? value]) {
    Get.back();
    ReplyGrpc.blockReplyAtCount = value;
    GStorage.setting
        .put(SettingBoxKey.blockReplyAtCount, value)
        .whenComplete(setState);
  }

  var countStr = Pref.blockReplyAtCount?.toString();
  await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('遮蔽@的數量'),
      content: TextFormField(
        autofocus: true,
        keyboardType: .number,
        initialValue: countStr,
        onChanged: (value) => countStr = value,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      ),
      actions: [
        TextButton(
          onPressed: onChanged,
          child: const Text('停用'),
        ),
        TextButton(
          onPressed: Get.back,
          child: Text(
            '取消',
            style: TextStyle(color: ColorScheme.of(context).outline),
          ),
        ),
        TextButton(
          onPressed: () {
            try {
              final count = int.parse(countStr!);
              onChanged(count > 0 ? count : null);
            } catch (e) {
              SmartDialog.showToast(e.toString());
            }
          },
          child: const Text('確認'),
        ),
      ],
    ),
  );
}

void _onBlockAtOnlyReplyChanged(bool value) =>
    ReplyGrpc.blockAtOnlyReply = value;
