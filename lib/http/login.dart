import 'dart:convert';

import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/login_devices/data.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/app_sign.dart';
import 'package:PiliPlus/utils/login_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:encrypt/encrypt.dart';

abstract final class LoginHttp {
  static final String deviceId = LoginUtils.genDeviceId();
  static String get _buvid => AnonymousAccount().buvid;
  static final Map<String, String> headers = {
    'buvid': _buvid,
    'env': 'prod',
    'app-key': 'android_hd',
    'user-agent': Constants.userAgent,
    'x-bili-trace-id': Constants.traceId,
    'x-bili-aurora-eid': '',
    'x-bili-aurora-zone': '',
    'bili-http-engine': 'cronet',
    'content-type': 'application/x-www-form-urlencoded; charset=utf-8',
  };

  @pragma('vm:notify-debugger-on-exception')
  static Future<LoadingState<({String authCode, String url})>>
  getHDcode() async {
    final params = {
      // 'local_id': 'Y952A395BB157D305D8A8340FC2AAECECE17',
      'local_id': '0',
      'platform': 'android',
      'mobi_app': 'android_hd',
    };
    AppSign.appSign(params);
    final res = await Request().post(Api.getTVCode, queryParameters: params);

    if (res.data['code'] == 0) {
      try {
        final Map<String, dynamic> data = res.data['data'];
        return Success((authCode: data['auth_code'], url: data['url']));
      } catch (e, s) {
        return Error('$e\n\n$s');
      }
    } else {
      return Error(res.data['message']);
    }
  }

  static Future codePoll(String authCode) async {
    final params = {
      'auth_code': authCode,
      'local_id': '0',
    };
    AppSign.appSign(params);
    final res = await Request().post(Api.qrcodePoll, queryParameters: params);
    return {
      'status': res.data['code'] == 0,
      'code': res.data['code'],
      'data': res.data['data'],
      'msg': res.data['message'],
    };
  }

  /// 確認電視／盒子 QR code 登入
  static Future<({bool success, String msg})> confirmTvQrcode(
    String authCode,
  ) async {
    try {
      // With an app credential, authenticate with access_key + app sign like
      // the official app: the SESSDATA cookie can be rejected (-101) even
      // when the app still works (PiliPlus issue #2933).
      final accessKey = Accounts.main.accessKey;
      final res = await Request().post(
        Api.qrcodeConfirm,
        data: accessKey != null && accessKey.isNotEmpty
            ? _webQrcodeParams(
                authCode,
                codeField: 'auth_code',
                extra: {'scanning_type': '1'},
              )
            : {
                'auth_code': authCode,
                'build': 7082000,
                'csrf': Accounts.main.csrf,
              },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'origin': 'https://passport.bilibili.com'},
        ),
      );
      if (kDebugMode) {
        debugPrint('confirmTvQrcode: ${res.statusCode} ${res.data}');
      }
      final data = res.data;
      final code = data is Map ? data['code'] : null;
      final ok = code == 0;
      if (ok) return (success: true, msg: '登入成功');
      final message = data is Map ? data['message']?.toString() ?? '' : '';
      return (
        success: false,
        msg: '${_webQrcodeErrMsg(code, message)}（$code）',
      );
    } catch (e) {
      return (success: false, msg: e.toString());
    }
  }

  static Map<String, dynamic> _webQrcodeParams(
    String qrcodeKey, {
    String codeField = 'qrcode_key',
    Map<String, dynamic>? extra,
  }) {
    final params = <String, dynamic>{
      'access_key': Accounts.main.accessKey ?? '',
      codeField: qrcodeKey,
      'build': '2001100',
      'csrf': Accounts.main.csrf,
      'disable_rcmd': '0',
      'mobi_app': 'android_hd',
      'platform': 'android',
      'statistics': Constants.statistics,
      ...?extra,
    };
    AppSign.appSign(params);
    return params;
  }

  static String _webQrcodeErrMsg(dynamic code, dynamic message) {
    final m = message?.toString() ?? '';
    return switch (code) {
      -101 => '目前登入狀態無法授權，請重新登入',
      86038 => '二維碼已過期，請重新整理後再掃',
      -111 => '登入憑證驗證失敗，請重新登入',
      -400 => 'B 站拒絕了這次授權（-400），請重新整理二維碼後再試',
      _ => m.isEmpty ? '授權失敗（$code）' : m,
    };
  }

  /// 網頁版登入 QR code：檢查
  static Future<({bool success, String msg})> webQrcodeCheck(
    String qrcodeKey,
  ) async {
    try {
      final res = await Request().get(
        Api.webQrcodeCheck,
        queryParameters: _webQrcodeParams(qrcodeKey),
      );
      if (kDebugMode) {
        debugPrint('webQrcodeCheck: ${res.statusCode} ${res.data}');
      }
      final data = res.data;
      final code = data is Map ? data['code'] : null;
      if (code == 0) return (success: true, msg: '');
      return (
        success: false,
        msg: _webQrcodeErrMsg(code, data is Map ? data['message'] : null),
      );
    } catch (e) {
      return (success: false, msg: e.toString());
    }
  }

  /// 網頁版登入 QR code：取得登入場景
  static Future<({bool success, String msg, String location, bool transient})>
  webQrcodeScene(String qrcodeKey) async {
    try {
      final res = await Request().get(
        Api.webQrcodeScene,
        queryParameters: _webQrcodeParams(qrcodeKey),
      );
      if (kDebugMode) {
        debugPrint('webQrcodeScene: ${res.statusCode} ${res.data}');
      }
      final data = res.data;
      final code = data is Map ? data['code'] : null;
      if (code == 0) {
        final d = data['data'];
        return (
          success: true,
          msg: '',
          location: d is Map ? d['location']?.toString() ?? '' : '',
          transient: d is Map && d['transient'] == true,
        );
      }
      return (
        success: false,
        msg: _webQrcodeErrMsg(code, data is Map ? data['message'] : null),
        location: '',
        transient: false,
      );
    } catch (e) {
      return (
        success: false,
        msg: e.toString(),
        location: '',
        transient: false,
      );
    }
  }

  /// 網頁版登入 QR code：確認
  static Future<({bool success, String msg})> webQrcodeConfirm(
    String qrcodeKey, {
    bool transient = false,
  }) async {
    try {
      final res = await Request().post(
        Api.webQrcodeConfirm,
        data: _webQrcodeParams(
          qrcodeKey,
          extra: {
            'transient': transient.toString(),
            'env_key': '',
            'verify_type': 'verify_tel',
            'verify_code': '',
            'verify_key': '',
          },
        ),
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      if (kDebugMode) {
        debugPrint('webQrcodeConfirm: ${res.statusCode} ${res.data}');
      }
      final data = res.data;
      final code = data is Map ? data['code'] : null;
      if (code == 0) return (success: true, msg: '登入成功');
      return (
        success: false,
        msg: _webQrcodeErrMsg(code, data is Map ? data['message'] : null),
      );
    } catch (e) {
      return (success: false, msg: e.toString());
    }
  }

  // static Future queryCaptcha() async {
  //   final res = await Request().get(Api.getCaptcha);
  //   if (res.data['code'] == 0) {
  //     return {
  //       'status': true,
  //       'data': CaptchaDataModel.fromJson(res.data['data']),
  //     };
  //   } else {
  //     return {'status': false, 'data': res.data['message']};
  //   }
  // }

  // 获取salt与PubKey
  static Future getWebKey() async {
    final res = await Request().get(Api.getWebKey);
    //data: {'disable_rcmd': 0, 'local_id': LoginUtils.generateBuvid()});
    if (res.data['code'] == 0) {
      return {'status': true, 'data': res.data['data']};
    } else {
      return {'status': false, 'data': {}, 'msg': res.data['message']};
    }
  }

  static Future sendSmsCode({
    required Object cid,
    required String tel,
    // String? deviceTouristId,
    String? geeChallenge,
    String? geeSeccode,
    String? geeValidate,
    String? recaptchaToken,
  }) async {
    int timestamp = DateTime.now().millisecondsSinceEpoch;
    final data = {
      'build': '2001100',
      'buvid': _buvid,
      'c_locale': 'zh_CN',
      'channel': 'master',
      'cid': cid,
      // if (deviceTouristId != null) 'device_tourist_id': deviceTouristId,
      'disable_rcmd': '0',
      'gee_challenge': ?geeChallenge,
      'gee_seccode': ?geeSeccode,
      'gee_validate': ?geeValidate,
      'local_id': _buvid,
      // https://chinggg.github.io/post/appre/
      'login_session_id': md5
          .convert(ascii.encode(_buvid + timestamp.toString()))
          .toString(),
      'mobi_app': 'android_hd',
      'platform': 'android',
      'recaptcha_token': ?recaptchaToken,
      's_locale': 'zh_CN',
      'statistics': Constants.statistics,
      'tel': tel,
      'ts': (timestamp ~/ 1000).toString(),
    };
    AppSign.appSign(data);

    final res = await Request().post(
      Api.appSmsCode,
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: headers,
      ),
    );

    if (res.data['code'] == 0 && res.data['data']['recaptcha_url'] == "") {
      return {'status': true, 'data': res.data['data']};
    } else {
      return {
        'status': false,
        'code': res.data['code'],
        'msg': res.data['message'],
        'data': res.data['data'],
      };
    }
  }

  // static Future getGuestId(String key) async {
  //   dynamic publicKey = RSAKeyParser().parse(key);
  //   final params = {
  //     'appkey': Constants.appKey,
  //     'build': '2001100',
  //     'buvid': buvid,
  //     'c_locale': 'zh_CN',
  //     'channel': 'master',
  //     'deviceInfo': 'xxxxxx',
  //     'disable_rcmd': '0',
  //     'dt': Uri.encodeComponent(Encrypter(RSA(publicKey: publicKey))
  //         .encrypt(generateRandomString(16))
  //         .base64),
  //     'local_id': buvid,
  //     'mobi_app': 'android_hd',
  //     'platform': 'android',
  //     's_locale': 'zh_CN',
  //     'statistics': Constants.statistics,
  //     'ts': (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
  //   };
  //   String sign = AppSign.appSign(
  //     params,
  //     Constants.appKey,
  //     Constants.appSec,
  //   );
  //   final res = await Request().post(Api.getGuestId,
  //       queryParameters: {...params, 'sign': sign},
  //       options: Options(
  //         contentType: Headers.formUrlEncodedContentType,
  //         headers: headers,
  //       ));
  //   print("getGuestId: $res");
  //   if (res.data['code'] == 0) {
  //     return {'status': true, 'data': res.data['data']};
  //   } else {
  //     return {'status': false, 'msg': res.data['message']};
  //   }
  // }

  // app端密码登录
  static Future loginByPwd({
    required String username,
    required String password,
    required String key,
    required String salt,
    String? geeChallenge,
    String? geeSeccode,
    String? geeValidate,
    String? recaptchaToken,
  }) async {
    dynamic publicKey = RSAKeyParser().parse(key);
    String passwordEncrypted = Encrypter(
      RSA(publicKey: publicKey),
    ).encrypt(salt + password).base64;

    Map<String, String> data = {
      'bili_local_id': deviceId,
      'build': '2001100',
      'buvid': _buvid,
      'c_locale': 'zh_CN',
      'channel': 'master',
      'device': 'phone',
      'device_id': deviceId,
      //'device_meta': '',
      'device_name': 'vivo',
      'device_platform': 'Android14vivo',
      'disable_rcmd': '0',
      'dt': Uri.encodeComponent(
        Encrypter(
          RSA(publicKey: publicKey),
        ).encrypt(Utils.generateRandomString(16)).base64,
      ),
      'from_pv': 'main.homepage.avatar-nologin.all.click',
      'from_url': Uri.encodeComponent('bilibili://pegasus/promo'),
      'gee_challenge': ?geeChallenge,
      'gee_seccode': ?geeSeccode,
      'gee_validate': ?geeValidate,
      'local_id': _buvid, //LoginUtils.generateBuvid(),
      'mobi_app': 'android_hd',
      'password': passwordEncrypted,
      'permission': 'ALL',
      'platform': 'android',
      'recaptcha_token': ?recaptchaToken,
      's_locale': 'zh_CN',
      'statistics': Constants.statistics,
      'username': username,
    };
    AppSign.appSign(data);
    final res = await Request().post(
      Api.loginByPwdApi,
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: headers,
        //responseType: ResponseType.plain
      ),
    );

    if (res.data['code'] == 0) {
      return {
        'status': true,
        'data': res.data['data'],
        'msg': res.data['message'],
      };
    } else {
      return {
        'status': false,
        'code': res.data['code'],
        'msg': res.data['message'],
        'data': res.data['data'],
      };
    }
  }

  // app端短信验证码登录
  static Future loginBySms({
    required String captchaKey,
    required String tel,
    required String code,
    required Object cid,
    required String key,
  }) async {
    dynamic publicKey = RSAKeyParser().parse(key);
    Map<String, Object> data = {
      'bili_local_id': deviceId,
      'build': '2001100',
      'buvid': _buvid,
      'c_locale': 'zh_CN',
      'captcha_key': captchaKey,
      'channel': 'master',
      'cid': cid,
      'code': code,
      'device': 'phone',
      'device_id': deviceId,
      //'device_meta': '',
      'device_name': 'vivo',
      'device_platform': 'Android14vivo',
      // 'device_tourist_id': '',
      'disable_rcmd': '0',
      'dt': Uri.encodeComponent(
        Encrypter(
          RSA(publicKey: publicKey),
        ).encrypt(Utils.generateRandomString(16)).base64,
      ),
      'from_pv': 'main.my-information.my-login.0.click',
      'from_url': Uri.encodeComponent('bilibili://user_center/mine'),
      'local_id': _buvid,
      'mobi_app': 'android_hd',
      'platform': 'android',
      's_locale': 'zh_CN',
      'statistics': Constants.statistics,
      'tel': tel,
    };
    AppSign.appSign(data);
    final res = await Request().post(
      Api.logInByAppSms,
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: headers,
        //responseType: ResponseType.plain
      ),
    );

    if (res.data['code'] == 0) {
      return {'status': true, 'data': res.data['data']};
    } else {
      return {
        'status': false,
        'code': res.data['code'],
        'msg': res.data['message'],
        'data': res.data['data'],
      };
    }
  }

  // 密码登录时风控验证手机
  static Future safeCenterGetInfo({
    required String tmpCode,
  }) async {
    final res = await Request().get(
      Api.safeCenterGetInfo,
      queryParameters: {
        'tmp_code': tmpCode,
      },
    );
    if (res.data['code'] == 0) {
      return {'status': true, 'data': res.data['data']};
    } else {
      return {
        'status': false,
        'code': res.data['code'],
        'msg': res.data['message'],
        'data': res.data['data'],
      };
    }
  }

  // 风控验证手机前的极验验证码
  static Future preCapture() async {
    final res = await Request().post(Api.preCapture);

    if (res.data['code'] == 0) {
      return {'status': true, 'data': res.data['data']};
    } else {
      return {
        'status': false,
        'code': res.data['code'],
        'msg': res.data['message'],
        'data': res.data['data'],
      };
    }
  }

  // 风控验证手机：发送短信验证码
  static Future safeCenterSmsCode({
    String? smsType,
    required String tmpCode,
    String? geeChallenge,
    String? geeSeccode,
    String? geeValidate,
    String? recaptchaToken,
    required String refererUrl,
  }) async {
    Map<String, String> data = {
      'disable_rcmd': '0',
      'sms_type': smsType ?? 'loginTelCheck',
      'tmp_code': tmpCode,
      'gee_challenge': ?geeChallenge,
      'gee_seccode': ?geeSeccode,
      'gee_validate': ?geeValidate,
      'recaptcha_token': ?recaptchaToken,
    };
    AppSign.appSign(data);
    final res = await Request().post(
      Api.safeCenterSmsCode,
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          "Referer": refererUrl,
        },
      ),
    );

    if (res.data['code'] == 0) {
      return {'status': true, 'data': res.data['data']};
    } else {
      return {
        'status': false,
        'code': res.data['code'],
        'msg': res.data['message'],
        'data': res.data['data'],
      };
    }
  }

  // 风控验证手机：提交短信验证码
  static Future safeCenterSmsVerify({
    String? type,
    required String code,
    required String tmpCode,
    required String requestId,
    required String source,
    required String captchaKey,
    required String refererUrl,
  }) async {
    Map<String, String> data = {
      'type': type ?? 'loginTelCheck',
      'code': code,
      'tmp_code': tmpCode,
      'request_id': requestId,
      'source': source,
      'captcha_key': captchaKey,
    };
    AppSign.appSign(data);
    final res = await Request().post(
      Api.safeCenterSmsVerify,
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          "Referer": refererUrl,
        },
      ),
    );

    if (res.data['code'] == 0) {
      return {'status': true, 'data': res.data['data']};
    } else {
      return {
        'status': false,
        'code': res.data['code'],
        'msg': res.data['message'],
        'data': res.data['data'],
      };
    }
  }

  // 风控验证手机：用oauthCode换回accessToken
  static Future oauth2AccessToken({
    required String code,
  }) async {
    final Map<String, String> data = {
      'build': '2001100',
      'buvid': _buvid,
      // 'c_locale': 'zh_CN',
      // 'channel': 'master',
      'code': code,
      // 'device': 'phone',
      // 'device_id': deviceId,
      // 'device_name': 'vivo',
      // 'device_platform': 'Android14vivo',
      'disable_rcmd': '0',
      'grant_type': 'authorization_code',
      'local_id': _buvid,
      'mobi_app': 'android_hd',
      'platform': 'android',
      // 's_locale': 'zh_CN',
      // 'statistics': Constants.statistics,
    };
    AppSign.appSign(data);
    final res = await Request().post(
      Api.oauth2AccessToken,
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: headers,
      ),
    );

    if (res.data['code'] == 0) {
      return {'status': true, 'data': res.data['data']};
    } else {
      return {
        'status': false,
        'code': res.data['code'],
        'msg': res.data['message'],
        'data': res.data['data'],
      };
    }
  }

  static Future<LoadingState<void>> logout(LoginAccount account) async {
    final res = await Request().post(
      Api.logout,
      data: {'biliCSRF': account.csrf},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        extra: {'account': account},
      ),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<LoginDevicesData>> loginDevices() async {
    final account = Accounts.main;
    final params = {
      'local_id': _buvid,
      'buvid': _buvid,
      'device_name': 'android',
      'device_platform': 'android',
      'csrf': account.csrf,
      'mobi_app': 'android_hd',
      'platform': 'android',
      'access_key': account.accessKey,
      'statistics': Constants.statistics,
    };
    AppSign.appSign(params);
    final res = await Request().get(
      Api.loginDevices,
      queryParameters: params,
    );
    if (res.data['code'] == 0) {
      return Success(LoginDevicesData.fromJson(res.data['data']));
    } else {
      return Error(res.data['message']);
    }
  }
}
