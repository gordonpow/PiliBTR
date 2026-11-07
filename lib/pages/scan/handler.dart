import 'package:PiliPlus/http/login.dart';
import 'package:PiliPlus/pages/mine/controller.dart';
import 'package:PiliPlus/pages/webview/view.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/login_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

abstract final class QrScanHandler {
  /// 回傳 true 表示已離開掃描頁
  static Future<bool> handle(String value) async {
    final uri = Uri.tryParse(value);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      final host = uri.host;
      final authCode = uri.queryParameters['auth_code'];
      if (host == 'passport.bilibili.com' &&
          authCode != null &&
          authCode.isNotEmpty) {
        await _tvLogin(authCode);
        return false;
      }
      if (uri.queryParameters.containsKey('qrcode_key') &&
          (host == 'bilibili.com' || host.endsWith('.bilibili.com'))) {
        if (!Accounts.main.isLogin) {
          SmartDialog.showToast('請先登入');
          return false;
        }
        await LoginUtils.setWebCookie(Accounts.main);
        Get.back();
        Get.to(() => WebviewPage(url: value));
        return true;
      }
      Get.back();
      final handled = await PiliScheme.routePushFromUrl(value);
      if (!handled) Get.to(() => WebviewPage(url: value));
      return true;
    }

    await _showText(value);
    return false;
  }

  static Future<void> _tvLogin(String authCode) async {
    if (!Accounts.main.isLogin) {
      SmartDialog.showToast('請先登入');
      return;
    }
    String? name;
    if (Get.isRegistered<MineController>()) {
      name = Get.find<MineController>().userInfo.value.uname;
    }
    name ??= Accounts.main.mid.toString();
    final confirmed = await showDialog<bool>(
      context: Get.context!,
      builder: (_) => AlertDialog(
        title: const Text('登入確認'),
        content: Text('要用目前帳號（$name）登入其他裝置嗎？'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text('確認登入'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final res = await LoginHttp.confirmTvQrcode(authCode);
    SmartDialog.showToast(res.msg);
  }

  static Future<void> _showText(String text) {
    return showDialog(
      context: Get.context!,
      builder: (_) => AlertDialog(
        content: SelectableText(text),
        actions: [
          TextButton(
            onPressed: () => Utils.copyText(text),
            child: const Text('複製'),
          ),
          TextButton(
            onPressed: Get.back,
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }
}
