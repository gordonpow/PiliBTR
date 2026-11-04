import 'dart:async' show FutureOr;
import 'dart:convert' show utf8, jsonDecode;
import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/dialog/simple_dialog_option.dart';
import 'package:PiliPlus/utils/config_archive.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/extension/file_ext.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/base16/github.dart';
import 'package:re_highlight/styles/github-dark.dart';

void exportToClipBoard({
  required ValueGetter<String> onExport,
}) {
  Utils.copyText(onExport());
}

void exportToLocalFile({
  required ValueGetter<String> onExport,
  required ValueGetter<String> localFileName,
}) {
  final res = utf8.encode(onExport());
  StorageUtils.saveBytes2File(
    name:
        'piliplus_${localFileName()}_'
        '${DateFormatUtils.only0_9.format(DateTime.now())}.json',
    bytes: res,
  );
}

Future<void> importFromClipBoard<T>(
  BuildContext context, {
  required String title,
  required ValueGetter<String> onExport,
  required FutureOr<void> Function(T json) onImport,
  bool showConfirmDialog = true,
}) async {
  final data = await Clipboard.getData('text/plain');
  if (data?.text case final text? when (text.isNotEmpty)) {
    if (!context.mounted) return;
    final T json;
    final String formatText;
    try {
      json = jsonDecode(text);
      formatText = Utils.jsonEncoder.convert(json);
    } catch (e) {
      SmartDialog.showToast('解析json失敗：$e');
      return;
    }
    bool? executeImport;
    if (showConfirmDialog) {
      final highlight = Highlight()..registerLanguage('json', langJson);
      final result = highlight.highlight(
        code: formatText,
        language: 'json',
      );
      late TextSpanRenderer renderer;
      bool? isDarkMode;
      executeImport = await showDialog<bool>(
        context: context,
        builder: (context) {
          final colorScheme = ColorScheme.of(context);
          final isDark = colorScheme.isDark;
          if (isDark != isDarkMode) {
            isDarkMode = isDark;
            renderer = TextSpanRenderer(
              null,
              isDark ? githubDarkTheme : githubTheme,
            );
            result.render(renderer);
          }
          return AlertDialog(
            title: Text('是否匯入如下$title？'),
            content: SingleChildScrollView(
              child: Text.rich(renderer.span!),
            ),
            actions: [
              TextButton(
                onPressed: Get.back,
                child: Text('取消', style: TextStyle(color: colorScheme.outline)),
              ),
              TextButton(
                onPressed: () => Get.back(result: true),
                child: const Text('確定'),
              ),
            ],
          );
        },
      );
    } else {
      executeImport = true;
    }
    if (executeImport ?? false) {
      try {
        await onImport(json);
        SmartDialog.showToast('匯入成功');
      } catch (e) {
        SmartDialog.showToast('匯入失敗：$e');
      }
    }
  } else {
    SmartDialog.showToast('剪貼簿無資料');
    return;
  }
}

Future<void> importFromLocalFile<T>({
  required FutureOr<void> Function(T json) onImport,
}) async {
  final result = await FilePicker.pickFile(
    type: .custom,
    allowedExtensions: const ['json', 'txt'],
  );
  if (result != null) {
    final data = await result.xFile.readAsString();
    final T json;
    try {
      json = jsonDecode(data);
    } catch (e) {
      SmartDialog.showToast('解析json失敗：$e');
      return;
    }
    try {
      await onImport(json);
      SmartDialog.showToast('匯入成功');
    } catch (e) {
      SmartDialog.showToast('匯入失敗：$e');
    }
  }
}

void importFromInput<T>(
  BuildContext context, {
  required String title,
  required FutureOr<void> Function(T json) onImport,
}) {
  final key = GlobalKey<FormFieldState<String>>();
  late T json;
  String? forceErrorText;

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('輸入$title'),
      constraints: Style.dialogFixedConstraints,
      content: TextFormField(
        key: key,
        minLines: 4,
        maxLines: 12,
        autofocus: true,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          errorMaxLines: 3,
        ),
        validator: (value) {
          if (forceErrorText != null) return forceErrorText;
          try {
            json = jsonDecode(value!) as T;
            return null;
          } catch (e) {
            return '解析json失敗：$e';
          }
        },
      ),
      actions: [
        TextButton(
          onPressed: Get.back,
          child: Text(
            '取消',
            style: TextStyle(
              color: ColorScheme.of(context).outline,
            ),
          ),
        ),
        TextButton(
          onPressed: () async {
            if (key.currentState?.validate() == true) {
              try {
                await onImport(json);
                Get.back();
                SmartDialog.showToast('匯入成功');
                return;
              } catch (e) {
                forceErrorText = '匯入失敗：$e';
              }
              key.currentState?.validate();
              forceErrorText = null;
            }
          },
          child: const Text('確定'),
        ),
      ],
    ),
  );
}

Future<void> _exportAllDataToArchive() async {
  final name =
      'piliplus_data_'
      '${DateFormatUtils.only0_9.format(DateTime.now())}.zip';
  if (PlatformUtils.isDesktop) {
    final path = await FilePicker.saveFile(
      fileName: name,
      bytes: Uint8List(0),
    );
    if (path == null) {
      SmartDialog.showToast("取消儲存");
      return;
    }
    try {
      final out = OutputFileStream(path.toFilePath());
      ConfigArchive.export(out);
      await out.close();
    } catch (e) {
      SmartDialog.showToast('匯出失敗：$e');
      File.fromUri(path).tryDel();
      return;
    }
  } else {
    final out = OutputMemoryStream();
    try {
      ConfigArchive.export(out);
    } catch (e) {
      out.closeSync();
      SmartDialog.showToast('匯出失敗：$e');
      return;
    }
    final path = await FilePicker.saveFile(
      fileName: name,
      bytes: out.getBytes(),
    );
    out.closeSync();
    if (path == null) {
      SmartDialog.showToast("取消儲存");
    }
  }
}

Future<void> _importAllDataFromArchive(BuildContext context) async {
  final result = await FilePicker.pickFile(
    type: .custom,
    allowedExtensions: const ['zip'],
  );
  if (result == null) return;

  final Uint8List bytes;
  try {
    bytes = await result.readAsBytes();
  } catch (e) {
    SmartDialog.showToast('匯入失敗：$e');
    return;
  }

  if (!context.mounted) return;

  final actions = [
    TextButton(
      onPressed: Get.back,
      child: Text(
        '取消',
        style: TextStyle(color: ColorScheme.of(context).outline),
      ),
    ),
    TextButton(
      onPressed: () => Get.back(result: true),
      child: const Text('繼續'),
    ),
  ];

  final res = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('匯入所有資料？'),
      content: const Text('將用壓縮包內的設定、賬號資訊、歷史評論、搜尋記錄、黑名單、自定義字型覆蓋當前資料，此操作不可撤銷。'),
      actions: actions,
    ),
  );

  if (res != true) return;

  try {
    final res = await ConfigArchive.import(
      bytes,
      onWarning: (warning) async {
        if (!context.mounted) return false;
        return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('注意'),
                content: Text(warning),
                actions: actions,
              ),
            ) ??
            false;
      },
    );
    if (res != null) {
      SmartDialog.showToast(res.isEmpty ? '匯入成功' : '匯入成功，但$res');
    }
  } catch (e) {
    SmartDialog.showToast('匯入失敗：$e');
  }
}

Future<void> showDataImportExportDialog(BuildContext context) {
  final pageContext = context;
  return showDialog(
    context: context,
    builder: (context) {
      const style = TextStyle(fontSize: 15);
      return SimpleDialog(
        clipBehavior: .hardEdge,
        title: const Text('匯入/匯出所有資料'),
        children: [
          DialogOption(
            child: const Text('匯出到壓縮包', style: style),
            onPressed: () {
              Get.back();
              _exportAllDataToArchive();
            },
          ),
          DialogOption(
            child: const Text('從壓縮包匯入', style: style),
            onPressed: () {
              Get.back();
              _importAllDataFromArchive(pageContext);
            },
          ),
        ],
      );
    },
  );
}

Future<void> showImportExportDialog<T>(
  BuildContext context, {
  required String title,
  required ValueGetter<String> onExport,
  required FutureOr<void> Function(T json) onImport,
  required ValueGetter<String> localFileName,
}) => showDialog(
  context: context,
  builder: (context) {
    const style = TextStyle(fontSize: 15);
    return SimpleDialog(
      clipBehavior: .hardEdge,
      title: Text('匯入/匯出$title'),
      children: [
        DialogOption(
          child: const Text('匯出至剪貼簿', style: style),
          onPressed: () {
            Get.back();
            exportToClipBoard(onExport: onExport);
          },
        ),
        DialogOption(
          child: const Text('匯出檔案至本地', style: style),
          onPressed: () {
            Get.back();
            exportToLocalFile(onExport: onExport, localFileName: localFileName);
          },
        ),
        Divider(
          height: 1,
          color: ColorScheme.of(context).outline.withValues(alpha: 0.1),
        ),
        DialogOption(
          child: const Text('輸入', style: style),
          onPressed: () {
            Get.back();
            importFromInput<T>(context, title: title, onImport: onImport);
          },
        ),
        DialogOption(
          child: const Text('從剪貼簿匯入', style: style),
          onPressed: () {
            Get.back();
            importFromClipBoard<T>(
              context,
              title: title,
              onExport: onExport,
              onImport: onImport,
            );
          },
        ),
        DialogOption(
          child: const Text('從本地檔案匯入', style: style),
          onPressed: () {
            Get.back();
            importFromLocalFile<T>(onImport: onImport);
          },
        ),
      ],
    );
  },
);
