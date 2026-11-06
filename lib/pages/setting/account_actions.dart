import 'package:PiliPlus/common/widgets/flutter/list_tile.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart' hide ListTile;
import 'package:PiliPlus/http/login.dart';
import 'package:PiliPlus/pages/login/controller.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/widgets/multi_select_dialog.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

final RxBool _noAccount = Accounts.account.isEmpty.obs;

/// Switch account and log out items, for the 帳號與隱私 group.
List<SettingsModel> accountActionItems() {
  _noAccount.value = Accounts.account.isEmpty;
  return [
    CustomModel(
      title: '切換帳號',
      builder: () => Builder(
        builder: (context) => ListTile(
          onTap: () => LoginPageController.switchAccountDialog(context),
          leading: const Icon(Icons.switch_account_outlined),
          title: Text(
            '切換帳號',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
    ),
    CustomModel(
      title: '退出登入',
      builder: () => Obx(
        () => _noAccount.value
            ? const SizedBox.shrink()
            : Builder(
                builder: (context) => ListTile(
                  leading: const Icon(Icons.logout_outlined),
                  onTap: () => logoutDialog(context),
                  title: Text(
                    '退出登入',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
      ),
    ),
  ];
}

Future<void> _removeAccounts(Set<LoginAccount> accounts) async {
  await Accounts.deleteAll(accounts);
  _noAccount.value = Accounts.account.isEmpty;
}

Future<LoginAccount?> _logoutWrapper(LoginAccount account) async {
  try {
    final res = await LoginHttp.logout(account);
    return res.isSuccess ? account : null;
  } catch (e, s) {
    Utils.reportError(e, s);
    return null;
  }
}

Future<void> logoutDialog(BuildContext context) async {
  final result = await showDialog<Set<LoginAccount>>(
    context: context,
    builder: (context) => MultiSelectDialog<LoginAccount>(
      title: '選擇要登出的帳號uid',
      initValues: const Iterable.empty(),
      values: {
        for (final i in Accounts.account.values) i: i.mid.toString(),
      },
    ),
  );
  if (!context.mounted || result == null || result.isEmpty) return;

  final theme = Theme.of(context);
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('提示'),
        content: Text(
          "確認要退出以下帳號登入嗎\n\n${result.map((i) => i.mid).join('\n')}",
        ),
        actions: [
          TextButton(
            onPressed: Get.back,
            child: Text(
              '點錯了',
              style: TextStyle(color: theme.colorScheme.outline),
            ),
          ),
          TextButton(
            onPressed: () {
              Get.back();
              _removeAccounts(result);
            },
            child: Text(
              '僅登出',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
          TextButton(
            onPressed: () async {
              SmartDialog.showLoading();
              final res = await Future.wait(result.map(_logoutWrapper));
              SmartDialog.dismiss();
              final logoutAccounts = res.nonNulls.toSet();
              if (logoutAccounts.isEmpty) {
                SmartDialog.showToast('所選帳號均退出登入失敗');
              } else {
                Get.back();
                _removeAccounts(logoutAccounts);
                if (logoutAccounts.length != result.length) {
                  result.removeWhere(logoutAccounts.contains);
                  SmartDialog.showToast(
                    '帳號 ${result.map((i) => i.mid).join(",")} 退出登入失敗',
                  );
                }
              }
            },
            child: const Text('確認'),
          ),
        ],
      );
    },
  );
}
