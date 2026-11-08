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

class _ScanPageState extends State<ScanPage> {
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
      if (!left && mounted) _handling = false;
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
