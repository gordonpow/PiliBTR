import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

abstract final class StorageUtils {
  static Future<void> saveBytes2File({
    required String name,
    required Uint8List bytes,
  }) async {
    try {
      final path = await FilePicker.saveFile(
        fileName: name,
        bytes: PlatformUtils.isDesktop ? Uint8List(0) : bytes,
      );
      if (path == null) {
        SmartDialog.showToast("取消儲存");
        return;
      }
      if (PlatformUtils.isDesktop) {
        await File(path.toFilePath()).writeAsBytes(bytes);
      }
      SmartDialog.showToast("已儲存");
    } catch (e) {
      SmartDialog.showToast("儲存失敗: $e");
    }
  }
}
