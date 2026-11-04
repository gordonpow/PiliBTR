import 'package:PiliPlus/common/widgets/button/icon_button.dart';
import 'package:PiliPlus/common/widgets/radio_widget.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/utils/extension/string_ext.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart';

typedef ReasonCheck = bool Function(int? reasonType);

bool _kReportCheck(int? reasonType) => reasonType == 0;

typedef OnReport = Future<LoadingState> Function(
  int reasonType,
  String? reasonDesc,
  bool banUid,
);

Future<void> autoWrapReportDialog(
  BuildContext context,
  Map<String, Map<int, String>> options,
  OnReport onReport, {
  ValueGetter<int>? mid,
  VoidCallback? onRemove,
  String? reportUrl,
  ReasonCheck withContent = _kReportCheck,
  ReasonCheck contentRequired = _kReportCheck,
}) {
  int? reasonType;
  String? reasonDesc;
  bool banUid = false;
  late final key = GlobalKey<FormFieldState<String>>();

  bool isWithContent = withContent(reasonType);
  bool isContentRequired = contentRequired(reasonType);

  void updateReasonType(int? value) {
    reasonType = value;
    isWithContent = withContent(reasonType);
    isContentRequired = contentRequired(reasonType);
    if (isWithContent) {
      key.currentState?.clearError();
    }
  }

  Widget title = const Text('舉報');
  if (reportUrl != null) {
    title = Row(
      mainAxisAlignment: .spaceBetween,
      children: [
        title,
        iconButton(
          iconSize: 21,
          tooltip: '網頁舉報',
          onPressed: () =>
              Get.toNamed('/webview', parameters: {'url': reportUrl}),
          icon: const Icon(MdiIcons.web, size: 22),
        ),
      ],
    );
  }

  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: title,
      titlePadding: const .only(left: 22, top: 16, right: 22),
      contentPadding: const .symmetric(vertical: 5),
      actionsPadding: const .only(left: 16, right: 16, bottom: 10),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: Builder(
                  builder: (context) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: .only(left: 22, right: 22, bottom: 5),
                        child: Text('請選擇舉報的理由：'),
                      ),
                      RadioGroup(
                        onChanged: (value) {
                          updateReasonType(value);
                          (context as Element).markNeedsBuild();
                        },
                        groupValue: reasonType,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: options.entries.map((entry) {
                            return WrapRadioOptionsGroup<int>(
                              groupTitle: entry.key,
                              options: entry.value,
                            );
                          }).toList(),
                        ),
                      ),
                      if (isWithContent)
                        Padding(
                          padding: const .only(left: 22, top: 5, right: 22),
                          child: TextFormField(
                            key: key,
                            minLines: 2,
                            maxLines: 4,
                            initialValue: reasonDesc,
                            autofocus: isContentRequired,
                            decoration: const InputDecoration(
                              labelText: '為幫助稽核人員更快處理，請補充問題型別和出現位置等詳細資訊',
                              border: OutlineInputBorder(),
                              contentPadding: .all(10),
                              labelStyle: TextStyle(fontSize: 14),
                              floatingLabelStyle: TextStyle(fontSize: 14),
                            ),
                            onChanged: (value) => reasonDesc = value,
                            validator: (value) =>
                                isContentRequired && value.isNullOrEmpty
                                ? '理由不能為空'
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (mid != null)
            Padding(
              padding: const EdgeInsets.only(left: 14, top: 6),
              child: CheckBoxText(
                text: '拉黑該使用者',
                onChanged: (value) => banUid = value,
              ),
            ),
        ],
      ),
      actions: [
        if (mid != null)
          TextButton(
            onPressed: () {
              Get.back();
              Pref.setBlackMid(mid());
              onRemove?.call();
            },
            child: const Text('本地遮蔽'),
          ),
        TextButton(
          onPressed: Get.back,
          child: Text(
            '取消',
            style: TextStyle(color: ColorScheme.of(context).outline),
          ),
        ),
        TextButton(
          onPressed: () async {
            if (reasonType == null ||
                (isContentRequired && key.currentState?.validate() != true)) {
              return;
            }
            SmartDialog.showLoading();
            try {
              final res = await onReport(
                reasonType!,
                isWithContent ? reasonDesc : null,
                banUid,
              );
              SmartDialog.dismiss();
              if (res.isSuccess) {
                Get.back();
                SmartDialog.showToast('舉報成功');
              } else {
                res.toast();
              }
            } catch (e, s) {
              SmartDialog.dismiss();
              SmartDialog.showToast('提交失敗：$e');
              Utils.reportError(e, s);
            }
          },
          child: const Text('確定'),
        ),
      ],
    ),
  );
}

class CheckBoxText extends StatefulWidget {
  final String text;
  final ValueChanged<bool> onChanged;
  final bool selected;

  const CheckBoxText({
    super.key,
    required this.text,
    required this.onChanged,
    this.selected = false,
  });

  @override
  State<CheckBoxText> createState() => _CheckBoxTextState();
}

class _CheckBoxTextState extends State<CheckBoxText> {
  late bool _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.selected;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return InkWell(
      onTap: () {
        setState(() {
          _selected = !_selected;
          widget.onChanged(_selected);
        });
      },
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              size: 22,
              _selected
                  ? Icons.check_box_outlined
                  : Icons.check_box_outline_blank,
              color: _selected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            Text(
              ' ${widget.text}',
              style: TextStyle(color: _selected ? colorScheme.primary : null),
            ),
          ],
        ),
      ),
    );
  }
}

abstract final class ReportOptions {
  // from https://s1.hdslb.com/bfs/seed/jinkela/comment-h5/static/js/605.chunks.js
  static Map<String, Map<int, String>> get commentReport => const {
    '違反法律法規': {9: '違法違規', 2: '色情', 10: '低俗', 12: '賭博詐騙', 23: '違法資訊外鏈'},
    '謠言類不實資訊': {19: '涉政謠言', 22: '虛假不實資訊*', 20: '涉社會事件謠言'},
    '侵犯個人權益': {7: '人身攻擊', 15: '侵犯隱私'},
    '有害社群環境': {
      1: '垃圾廣告',
      4: '引戰',
      5: '劇透',
      3: '刷屏',
      8: '影片不相關',
      18: '違規抽獎',
      17: '青少年不良資訊',
    },
    '其他': {0: '其他*'},
  };
  static bool withContentReply(int? reasonType) => reasonType != null;
  static bool contentRequiredReply(int? reasonType) =>
      reasonType == 0 || reasonType == 22;

  static Map<String, Map<int, String>> get dynamicReport => const {
    '': {
      4: '垃圾廣告',
      8: '引戰',
      1: '色情',
      5: '人身攻擊',
      3: '違法資訊',
      9: '涉政謠言',
      10: '涉社會事件謠言',
      12: '虛假不實資訊',
      13: '違法資訊外鏈',
      0: '其他*',
    },
  };

  static Map<String, Map<int, String>> get danmakuReport => const {
    '': {
      1: '違法違禁',
      2: '色情低俗',
      3: '賭博詐騙',
      4: '人身攻擊',
      5: '侵犯隱私',
      6: '垃圾廣告',
      7: '引戰',
      8: '劇透',
      9: '惡意刷屏',
      10: '影片無關',
      12: '青少年不良資訊',
      13: '違法資訊外鏈',
      11: '其它*',
    },
  };
  static bool danmakuReportCheck(int? reasonType) => reasonType == 11;

  static Map<String, Map<int, String>> get liveDanmakuReport => const {
    '': {
      1: '違法違規',
      2: '低俗色情',
      3: '垃圾廣告',
      4: '辱罵引戰',
      5: '政治敏感',
      6: '青少年不良資訊',
      0: '其他',
    },
  };
  static bool liveDanmakuReportCheck(int? _) => false;

  static Map<String, Map<int, String>> get imMsgReport => const {
    '': {
      1: '色情低俗',
      2: '政治敏感',
      3: '違法有害',
      4: '廣告騷擾',
      5: '人身攻擊',
      6: '詐騙',
      0: '其他問題*',
    },
  };
}
