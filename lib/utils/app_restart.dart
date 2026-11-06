import 'dart:io' show Platform;

import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:get/get.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';

/// Restarts the app after a setting that only applies on start.
abstract final class AppRestart {
  static const _channel = MethodChannel('pilibtr/update');

  /// Closes the app and opens it again. Only Android can do this; other
  /// platforms show a message to restart by hand.
  static Future<void> restart() async {
    if (Platform.isAndroid) {
      try {
        // The process ends right after the call: write settings first.
        await GStorage.setting.flush();
        await _channel.invokeMethod('restart');
        return;
      } catch (_) {}
    }
    SmartDialog.showToast('請手動重新啟動 App');
  }

  /// Asks the user to restart now or later.
  static Future<void> ask() async {
    final context = Get.context;
    if (context == null || !context.mounted) {
      SmartDialog.showToast('重新啟動後生效');
      return;
    }
    final now = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('需要重新啟動'),
        content: const Text('設定需要重新啟動 App 才會生效。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              '稍後',
              style: TextStyle(color: ColorScheme.of(context).outline),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('重新啟動'),
          ),
        ],
      ),
    );
    if (now == true) await restart();
  }
}
