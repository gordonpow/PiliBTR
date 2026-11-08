import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/pages/mine/controller.dart';
import 'package:PiliPlus/pages/rcmd/controller.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/login_utils.dart';
import 'package:PiliPlus/utils/play_url_cache.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';

abstract final class Accounts {
  static late final Box<LoginAccount> account;
  static final List<Account> accountMode = List.filled(
    AccountType.values.length,
    AnonymousAccount(),
  );
  static bool get isMainVip => Pref.userInfoCache?.vipStatus == 1;
  static bool get isVideoVip => main == video ? isMainVip : true;
  static Account get main => accountMode[AccountType.main.index];
  static Account get video => accountMode[AccountType.video.index];
  static Account get heartbeat => accountMode[AccountType.heartbeat.index];
  static Account get history {
    final heartbeat = Accounts.heartbeat;
    if (heartbeat is AnonymousAccount) {
      return Accounts.main;
    }
    return heartbeat;
  }
  // static set main(Account account) => set(AccountType.main, account);

  static Future<void> init() async {
    account = await Hive.openBox(
      'account',
      compactionStrategy: (int entries, int deletedEntries) {
        return deletedEntries > 2;
      },
    );
  }

  static Future<void> refresh() {
    for (final a in account.values) {
      for (final t in a.type) {
        accountMode[t.index] = a;
      }
    }
    return Future.wait(
      (accountMode.toSet()..removeWhere((i) => i.activated)).map(
        Request.buvidActive,
      ),
    );
  }

  static Future<void> clear() async {
    PlayUrlCache.clear();
    await account.clear();
    for (int i = 0; i < AccountType.values.length; i++) {
      accountMode[i] = AnonymousAccount();
    }
    await AnonymousAccount().delete();
    Request.buvidActive(AnonymousAccount());
  }

  static Future<void> deleteAll(Set<Account> accounts) async {
    PlayUrlCache.clear();
    final isLoginMain = Accounts.main.isLogin;
    final recommendChanged = accounts.contains(
      accountMode[AccountType.recommend.index],
    );
    for (int i = 0; i < AccountType.values.length; i++) {
      if (accounts.contains(accountMode[i])) {
        accountMode[i] = AnonymousAccount();
      }
    }
    await Future.wait(accounts.map((i) => i.delete()));
    if (isLoginMain && !Accounts.main.isLogin) {
      await LoginUtils.onLogoutMain();
    }
    if (recommendChanged) _reloadRcmd();
  }

  static void _reloadRcmd() {
    if (Get.isRegistered<RcmdController>()) {
      Get.find<RcmdController>().onAccountChanged();
    }
  }

  static Future<void> set(AccountType key, Account account) async {
    // 任何帳號類型變更都清空（影片帳號也會影響 playurl）。
    PlayUrlCache.clear();
    final oldAccount = accountMode[key.index]..type.remove(key);
    accountMode[key.index] = account..type.add(key);
    await Future.wait([?account.onChange(), ?oldAccount.onChange()]);
    if (!account.activated) await Request.buvidActive(account);
    switch (key) {
      case AccountType.main:
        await (account.isLogin
            ? LoginUtils.onLoginMain()
            : LoginUtils.onLogoutMain());
        break;
      case AccountType.heartbeat:
        MineController.anonymity.value = !account.isLogin;
        break;
      case AccountType.recommend:
        // The home feed was loaded with the old account (for example the
        // guest account before login): load it again for the new account.
        _reloadRcmd();
        break;
      default:
        break;
    }
  }

  @pragma("vm:prefer-inline")
  static Account get(AccountType key) {
    return accountMode[key.index];
  }

  static Future<void> importJsonAccount(Map<String, dynamic> json) async {
    final res = json.map(
      (key, value) => MapEntry(key, LoginAccount.fromJson(value)),
    );
    await Accounts.account.putAll(res);
    await Accounts.refresh();
    MineController.anonymity.value = !Accounts.heartbeat.isLogin;
    if (Accounts.main.isLogin) {
      await LoginUtils.onLoginMain();
    }
  }
}
