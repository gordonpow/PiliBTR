import 'package:PiliPlus/pages/scan/handler.dart';
import 'package:flutter/material.dart';
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
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handling = false;

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
    _handling = true;
    await _controller.stop();
    final left = await QrScanHandler.handle(value);
    if (left || !mounted) return;
    _handling = false;
    await _controller.start();
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
