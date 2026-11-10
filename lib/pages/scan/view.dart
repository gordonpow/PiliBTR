import 'dart:async';

import 'package:PiliPlus/pages/scan/handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    // noDuplicates never reports the same code again, so a code could not be
    // scanned a second time (e.g. after a failed login). Repeats are dropped
    // below instead.
    detectionSpeed: DetectionSpeed.normal,
  );
  bool _handling = false;
  String? _lastValue;
  DateTime _lastDone = DateTime.fromMillisecondsSinceEpoch(0);
  BuildContext? _pageContext;

  // 相機操作序列化：mobile_scanner 內建的生命週期處理是 unawaited 的 stop/start，
  // 快速 inactive -> resumed 時平台 start 會和未完成的 stop 交錯，最後相機被停掉
  // 但 isRunning 仍為 true（黑屏）。改由本頁自己排隊，stop 完成（或逾時）才 start。
  static const _opTimeout = Duration(seconds: 3);
  Future<void> _camOp = Future.value();
  bool _wantRunning = true;
  bool _disposed = false;
  final _foreground = ValueNotifier<bool>(true);
  DateTime _lastRestart = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _foreground.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground.value = true;
        _wantRunning = true;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _foreground.value = false;
        _wantRunning = false;
      case AppLifecycleState.detached:
        return;
    }
    _enqueue(_applyWanted);
  }

  void _enqueue(Future<void> Function() op) {
    _camOp = _camOp
        .then((_) async {
          if (_disposed) return;
          await op();
        })
        .catchError((Object _) {});
  }

  // 依執行當下的 _wantRunning 決定動作，連續相同請求不會累積。
  Future<void> _applyWanted() => _wantRunning ? _startCam() : _stopCam();

  Future<void> _stopCam() async {
    try {
      // 部分裝置 stop() 不會返回，所以加逾時。
      await _controller.stop().timeout(_opTimeout);
    } on TimeoutException {
      // 放棄等待，繼續後續操作。
    } on MobileScannerException {
      // 忽略，下一次操作會重試。
    }
  }

  Future<void> _startCam() async {
    final v = _controller.value;
    if (v.isStarting || v.isRunning) return;
    try {
      await _controller.start().timeout(_opTimeout);
    } on TimeoutException {
      // 放棄等待。
    } on MobileScannerException {
      // 錯誤狀態由 errorBuilder 顯示。
    }
  }

  void _restart() {
    if (_handling) return;
    final now = DateTime.now();
    if (now.difference(_lastRestart) < const Duration(seconds: 1)) return;
    _lastRestart = now;
    _wantRunning = true;
    _enqueue(() async {
      await _stopCam();
      if (_disposed || !_wantRunning) return;
      await _startCam();
    });
  }

  Future<void> _onResult(BarcodeCapture? capture) async {
    if (_handling) return;
    String? value;
    for (final b in capture?.barcodes ?? const <Barcode>[]) {
      final v = b.rawValue;
      if (v != null && v.isNotEmpty) {
        value = v;
        break;
      }
    }
    if (value == null) return;
    // The same code right after its dialog closed: still in front of the
    // camera, not a new scan.
    if (value == _lastValue &&
        DateTime.now().difference(_lastDone) < const Duration(seconds: 2)) {
      return;
    }
    // 不在 onDetect 回呼中 await stop()：部分裝置上 stop() 不會返回，畫面會停在
    // 黑屏且不再處理。相機保持運作，由 _handling 擋掉重複的掃描結果。
    _handling = true;
    var left = false;
    try {
      left = await QrScanHandler.handle(_pageContext ?? context, value);
    } catch (e) {
      SmartDialog.showToast('處理 QR code 失敗：$e');
    } finally {
      _lastValue = value;
      _lastDone = DateTime.now();
      if (!left && mounted) {
        _handling = false;
        if (_foreground.value && !_controller.value.isRunning) {
          _wantRunning = true;
          _enqueue(_applyWanted);
        }
      }
    }
  }

  Future<void> _pickImage() async {
    if (_handling) return;
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final capture = await _controller.analyzeImage(
      file.path,
      formats: const [BarcodeFormat.qrCode],
    );
    final hasValue =
        capture?.barcodes.any((b) => (b.rawValue ?? '').isNotEmpty) ?? false;
    if (!hasValue) {
      SmartDialog.showToast('未辨識到 QR code');
      return;
    }
    await _onResult(capture);
  }

  @override
  Widget build(BuildContext context) {
    // 掃描頁的 route 取不到 MaterialLocalizations，補上以免 AppBar／對話框失敗。
    return Localizations.override(
      context: context,
      delegates: GlobalMaterialLocalizations.delegates,
      child: Builder(
        builder: (ctx) {
          _pageContext = ctx;
          return _buildScaffold();
        },
      ),
    );
  }

  Widget _buildScaffold() {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('掃描 QR code'),
        actions: [
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (context, state, _) {
              final on = state.torchState == TorchState.on;
              return IconButton(
                tooltip: '手電筒',
                onPressed: state.torchState == TorchState.unavailable
                    ? null
                    : _controller.toggleTorch,
                icon: Icon(on ? Icons.flash_on : Icons.flash_off),
              );
            },
          ),
          TextButton(
            onPressed: _pickImage,
            child: const Text('相簿', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            useAppLifecycleState: false,
            onDetect: _onResult,
            errorBuilder: (context, error) => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '無法使用相機，請到系統設定允許相機權限，或從相簿選擇圖片',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          // 點預覽區一律重新啟動（isRunning 為 true 但黑屏時無法偵測）。
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _restart,
              child: ValueListenableBuilder<bool>(
                valueListenable: _foreground,
                builder: (context, fg, _) => ValueListenableBuilder(
                  valueListenable: _controller,
                  builder: (context, v, _) {
                    final stopped =
                        fg &&
                        v.hasCameraPermission &&
                        !v.isRunning &&
                        !v.isStarting &&
                        v.error == null;
                    if (!stopped) return const SizedBox.expand();
                    return const ColoredBox(
                      color: Color(0x99000000),
                      child: Center(
                        child: Text(
                          '點一下重新啟動相機',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '將 QR code 放入框內',
                    style: TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '畫面變黑時點一下重新啟動',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
