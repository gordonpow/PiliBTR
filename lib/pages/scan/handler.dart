import 'package:PiliPlus/http/login.dart';
import 'package:PiliPlus/pages/mine/controller.dart';
import 'package:PiliPlus/pages/webview/view.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

abstract final class QrScanHandler {
  /// 回傳 true 表示已離開掃描頁
  static Future<bool> handle(BuildContext context, String value) async {
    final uri = Uri.tryParse(value);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      final host = uri.host;
      final authCode = uri.queryParameters['auth_code'];
      if (host == 'passport.bilibili.com' &&
          authCode != null &&
          authCode.isNotEmpty) {
        await _tvLogin(context, authCode);
        return false;
      }
      if (uri.queryParameters.containsKey('qrcode_key') &&
          (host == 'bilibili.com' || host.endsWith('.bilibili.com'))) {
        await _webLogin(context, uri.queryParameters['qrcode_key']!);
        return false;
      }
      Get.back();
      final handled = await PiliScheme.routePushFromUrl(value);
      if (!handled) Get.to(() => WebviewPage(url: value));
      return true;
    }

    await _showText(context, value);
    return false;
  }

  static Future<void> _tvLogin(BuildContext context, String authCode) async {
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
      context: context,
      builder: (ctx) => _withL10n(
        ctx,
        AlertDialog(
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
      ),
    );
    if (confirmed != true || !context.mounted) return;
    // The scan page does not show SmartDialog toasts reliably: show the
    // progress and the result in dialogs of this page.
    final pending = LoginHttp.confirmTvQrcode(authCode);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _withL10n(
        ctx,
        const AlertDialog(
          content: Row(
            children: [
              SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(width: 16),
              Text('登入中…'),
            ],
          ),
        ),
      ),
    );
    final res = await pending;
    if (!context.mounted) return;
    Navigator.of(context).pop();
    await showDialog<void>(
      context: context,
      builder: (ctx) => _withL10n(
        ctx,
        AlertDialog(
          title: Text(res.success ? '登入成功' : '登入失敗'),
          content: Text(
            res.success ? '已用目前帳號登入其他裝置。' : res.msg,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('確定'),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _showResult(
    BuildContext context,
    String title,
    String message,
  ) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => _withL10n(
        ctx,
        AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('確定'),
            ),
          ],
        ),
      ),
    );
  }

  static void _showLoading(BuildContext context, String text) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _withL10n(
        ctx,
        AlertDialog(
          content: Row(
            children: [
              const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(width: 16),
              Text(text),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _webLogin(BuildContext context, String qrcodeKey) async {
    if (!Accounts.main.isLogin) {
      SmartDialog.showToast('請先登入');
      return;
    }
    if (Accounts.main.accessKey?.isNotEmpty != true) {
      await _showResult(
        context,
        '登入失敗',
        '目前的登入方式沒有 App 憑證（access_key），請用掃碼方式重新登入 PiliBTR 後再試',
      );
      return;
    }
    String? name;
    if (Get.isRegistered<MineController>()) {
      name = Get.find<MineController>().userInfo.value.uname;
    }
    name ??= Accounts.main.mid.toString();

    _showLoading(context, '讀取登入請求…');
    final check = await LoginHttp.webQrcodeCheck(qrcodeKey);
    if (!context.mounted) return;
    if (!check.success) {
      Navigator.of(context).pop();
      await _showResult(context, '登入失敗', check.msg);
      return;
    }
    final scene = await LoginHttp.webQrcodeScene(qrcodeKey);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    if (!scene.success) {
      await _showResult(context, '登入失敗', scene.msg);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _withL10n(
        ctx,
        AlertDialog(
          title: const Text('登入網頁版'),
          content: Text(
            '要用目前帳號（$name）登入網頁版嗎？'
            '${scene.location.isEmpty ? '' : '\n登入位置：${scene.location}'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('確認登入'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;

    _showLoading(context, '登入中…');
    final res = await LoginHttp.webQrcodeConfirm(
      qrcodeKey,
      transient: scene.transient,
    );
    if (!context.mounted) return;
    Navigator.of(context).pop();
    await _showResult(
      context,
      res.success ? '登入成功' : '登入失敗',
      res.success ? '已用目前帳號登入網頁版。' : res.msg,
    );
  }

  static Future<void> _showText(BuildContext context, String text) {
    return showDialog(
      context: context,
      builder: (ctx) => _withL10n(
        ctx,
        AlertDialog(
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
      ),
    );
  }

  /// 掃描頁的 route 內取不到 MaterialLocalizations（AppBar／AlertDialog 會失敗，
  /// release 版表現為 Null check operator），這裡在對話框內補上。
  static Widget _withL10n(BuildContext context, Widget child) {
    return Localizations.override(
      context: context,
      delegates: GlobalMaterialLocalizations.delegates,
      child: child,
    );
  }
}
