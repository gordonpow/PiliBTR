import 'dart:async' show Timer;
import 'dart:convert' show jsonDecode;
import 'dart:io' show Platform;

import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/main.dart';
import 'package:PiliPlus/plugin/linux_webview.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';

class GeetestWebviewDialog extends StatefulWidget {
  const GeetestWebviewDialog(this.gt, this.challenge, {super.key});

  final String gt;
  final String challenge;

  @override
  State<GeetestWebviewDialog> createState() => _GeetestWebviewDialogState();

  static Future<Map<String, dynamic>?> geetest(String gt, String challenge) {
    return showDialog<Map<String, dynamic>>(
      context: Get.context!,
      builder: (context) => GeetestWebviewDialog(gt, challenge),
    );
  }
}

class _GeetestWebviewDialogState extends State<GeetestWebviewDialog> {
  static const _geetestJsUri =
      'https://static.geetest.com/static/js/fullpage.0.0.0.js';
  static const _geetestConfigUri = 'https://api.geetest.com/gettype.php';

  static const _timeoutDuration = Duration(seconds: 15);

  late String _html;
  bool _ready = false;
  String? _error;
  Timer? _timeout;
  InAppWebViewController? _ctr;

  static String _buildHtml(String gt, String challenge) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final r = Platform.isLinux
        ? "R=function(n,o){window.PiliPlus.postMessage(n+':'+JSON.stringify(o))};"
        : 'R=function(n,o){if(window.flutter_inappwebview&&window.flutter_inappwebview.callHandler){window.flutter_inappwebview.callHandler(n,o)}};';
    final js =
        'var C,S,T,t;'
        'T=function(){if(C&&S&&!t){try{'
        't=Geetest(C).onSuccess(function(){R("success",t.getValidate())})'
        '.onError(function(o){R("error",o)})'
        '.onClose(function(o){R("close",o)});'
        't.onReady(function(){R("ready",1);try{t.verify()}catch(e){R("error",String(e))}})'
        '}catch(e){R("error",String(e))}}};'
        'geetest_$ts=function(d){'
        'if(!d||d.status!="success"){R("error",JSON.stringify(d));return}'
        'var k,c={gt:"$gt",challenge:"$challenge",offline:false,new_captcha:true,product:"bind",width:"100%",https:true,protocol:"https://"};'
        'for(k in d.data){c[k]=d.data[k]}C=c;T()'
        '};'
        'G=function(){S=1;T()};'
        'E=function(){R("error","geetest script load failed")};';

    return '<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width"></head>'
        '<body>'
        '<script>'
        '$r$js'
        '</script>'
        '<script src="$_geetestJsUri" onload="G()" onerror="E()"></script>'
        '<script src="$_geetestConfigUri?gt=$gt&callback=geetest_$ts" onerror="E()"></script>'
        '</body></html>';
  }

  @override
  void initState() {
    super.initState();
    _html = _buildHtml(widget.gt, widget.challenge);
    _startTimer();
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  bool _closed = false;

  /// Closes this dialog once. The close button and the geetest close or
  /// success callbacks can come together: a second pop would close the
  /// login page too.
  void _close([Map<String, dynamic>? result]) {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(result);
  }

  void _startTimer() {
    _timeout?.cancel();
    _timeout = Timer(_timeoutDuration, () {
      if (mounted && !_ready && _error == null) {
        setState(() => _error = '驗證碼載入逾時，請檢查網路後重試');
      }
    });
  }

  void _retry() {
    setState(() {
      _error = null;
      _ready = false;
    });
    _startTimer();
    _html = _buildHtml(widget.gt, widget.challenge);
    _ctr?.loadData(data: _html);
  }

  Widget _overlay(BuildContext context) {
    final theme = Theme.of(context);
    final Widget child;
    if (_error case final error?) {
      child = Card(
        color: theme.colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(onPressed: _retry, child: const Text('重試')),
                  const SizedBox(width: 8),
                  TextButton(onPressed: _close, child: const Text('關閉')),
                ],
              ),
            ],
          ),
        ),
      );
    } else {
      child = IgnorePointer(
        child: Card(
          color: theme.colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('驗證碼載入中…'),
              ],
            ),
          ),
        ),
      );
    }
    return Align(child: child);
  }

  @override
  Widget build(BuildContext context) {
    final html = _html;

    if (Platform.isLinux) {
      return AlertDialog(
        title: const Text('驗證碼'),
        content: SizedBox(
          width: 300,
          height: 400,
          child: LinuxWebview(
            initialHtml: html,
            userAgent: BrowserUa.mob,
            incognito: true,
            onWebMessageReceived: (msg) {
              final msgStr = msg.toString();
              if (msgStr.startsWith("success:")) {
                final dataStr = msgStr.substring("success:".length);
                try {
                  final data = jsonDecode(dataStr);
                  _close(data);
                } catch (e) {
                  debugPrint('geetest decode error: $e');
                }
              } else if (msgStr.startsWith('ready:')) {
                // 忽略
              } else if (msgStr.startsWith("error:")) {
                debugPrint('geetest error: $msgStr');
              } else if (msgStr.startsWith('close:')) {
                _close();
              }
            },
          ),
        ),
      );
    }

    return Stack(
      children: [
        InAppWebView(
          webViewEnvironment: webViewEnvironment,
          initialSettings: InAppWebViewSettings(
            clearCache: true,
            javaScriptEnabled: true,
            forceDark: ForceDark.AUTO,
            useHybridComposition: true,
            algorithmicDarkeningAllowed: true,
            useShouldOverrideUrlLoading: true,
            userAgent: BrowserUa.mob,
            mixedContentMode: .MIXED_CONTENT_ALWAYS_ALLOW,

            incognito: true,
            allowFileAccess: false,
            allowsLinkPreview: false,
            allowContentAccess: false,
            useOnDownloadStart: false,
            geolocationEnabled: false,
            thirdPartyCookiesEnabled: false,
            enterpriseAuthenticationAppLinkPolicyEnabled: false,
            saveFormData: false,
            safeBrowsingEnabled: false,
            isFraudulentWebsiteWarningEnabled: false,
            domStorageEnabled: false,
            databaseEnabled: false,
            cacheEnabled: false,
            cacheMode: .LOAD_NO_CACHE,

            horizontalScrollBarEnabled: false,
            verticalScrollBarEnabled: false,
            overScrollMode: .NEVER,

            pageZoom: Platform.isIOS ? 3 : 1,
          ),
          initialData: InAppWebViewInitialData(data: html),
          onWebViewCreated: (ctr) {
            _ctr = ctr;
            ctr
              ..addJavaScriptHandler(
                handlerName: 'success',
                callback: (args) {
                  if (args.isNotEmpty) {
                    if (args[0] case Map<String, dynamic> data) {
                      _close(data);
                      return;
                    }
                  }
                  debugPrint('geetest invalid result: $args');
                },
              )
              ..addJavaScriptHandler(
                handlerName: 'error',
                callback: (args) {
                  debugPrint('geetest error: $args');
                  if (!_ready && _error == null && mounted) {
                    var msg = args.isEmpty ? '' : args.first.toString();
                    if (msg.length > 100) msg = msg.substring(0, 100);
                    _timeout?.cancel();
                    setState(() => _error = '驗證碼載入失敗：$msg');
                  }
                },
              )
              ..addJavaScriptHandler(
                handlerName: 'ready',
                callback: (args) {
                  _timeout?.cancel();
                  if (mounted && !_ready) {
                    setState(() => _ready = true);
                  }
                },
              )
              ..addJavaScriptHandler(
                handlerName: 'close',
                callback: (args) => _close(),
              );
          },
        ),
        if (!_ready) _overlay(context),
        Positioned(
          left: 8,
          top: 8,
          child: IconButton.filledTonal(
            icon: const Icon(Icons.close),
            onPressed: _close,
            tooltip: '關閉',
          ),
        ),
      ],
    );
  }
}
