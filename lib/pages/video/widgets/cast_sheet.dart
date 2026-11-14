import 'dart:async';

import 'package:PiliPlus/services/cast/tv_cast.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

/// 「投放到」選單：PiliBTRTV 電視、掃描 QR code、輸入 IP、DLNA。
abstract final class CastSheet {
  /// [capture] 在使用者選了電視的當下同步呼叫，取得要送出的資料。
  /// [onDlna] 執行原本的 DLNA 流程。[onCasted] 投放成功後呼叫（用來暫停）。
  static Future<void> show(
    BuildContext context, {
    required CastPayload Function() capture,
    required VoidCallback onDlna,
    required VoidCallback onCasted,
  }) {
    // 按鈕的 context 會隨播放器控制列隱藏而失效；之後的對話框改用根
    // Navigator 的 overlay context（在 Navigator 之下，且不會被卸載）。
    final host = Navigator.of(context, rootNavigator: true).overlay!.context;
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => _CastSheetBody(
        onSelect: (tv) {
          // 同步取值，之後使用者再拖進度也不影響
          final payload = capture();
          Navigator.of(sheetContext).pop();
          _send(host, tv, payload, onCasted);
        },
        onDlna: () {
          Navigator.of(sheetContext).pop();
          onDlna();
        },
      ),
    );
  }

  static Future<void> _send(
    BuildContext context,
    TvDevice tv,
    CastPayload payload,
    VoidCallback onCasted,
  ) async {
    final cancel = CancelToken();
    final message = ValueNotifier<String>('正在連線…');
    var dialogOpen = true;
    // 存下 navigator：等待期間播放頁可能關閉，context 失效後仍要能關掉對話框。
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: message,
                  builder: (_, v, _) => Text(v),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: cancel.cancel,
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    ).whenComplete(() => dialogOpen = false);

    final res = await TvCast.play(
      tv,
      payload,
      cancel: cancel,
      onPending: () => message.value = '請在電視上按允許',
    );
    if (dialogOpen && navigator.mounted) navigator.pop();
    // 對話框關閉動畫結束後才釋放，避免還在顯示的文字使用已釋放的物件。
    Future.delayed(const Duration(seconds: 1), message.dispose);
    switch (res) {
      case CastResult.ok:
        onCasted();
        SmartDialog.showToast('已投放到 ${tv.name}');
      case CastResult.denied:
        SmartDialog.showToast('電視拒絕投放');
      case CastResult.busy:
        SmartDialog.showToast('電視正在等待其他手機的允許');
      case CastResult.tooMany:
        SmartDialog.showToast('請稍後再試');
      case CastResult.notReady:
        SmartDialog.showToast('電視尚未就緒');
      case CastResult.network:
      case CastResult.error:
        SmartDialog.showToast('無法連線到 ${tv.name}');
      case CastResult.cancelled:
        break;
    }
  }
}

class _CastSheetBody extends StatefulWidget {
  const _CastSheetBody({required this.onSelect, required this.onDlna});

  final ValueChanged<TvDevice> onSelect;
  final VoidCallback onDlna;

  @override
  State<_CastSheetBody> createState() => _CastSheetBodyState();
}

class _CastSheetBodyState extends State<_CastSheetBody> {
  final List<TvDevice> _tvs = [];
  StreamSubscription<TvDevice>? _sub;
  bool _discovering = false;

  @override
  void initState() {
    super.initState();
    _discover();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _discover() {
    _sub?.cancel();
    _tvs.clear();
    setState(() => _discovering = true);
    _sub = TvCast.discover().listen(
      (tv) {
        if (!mounted) return;
        setState(() {
          final i = _tvs.indexWhere((e) => e.id == tv.id);
          if (i >= 0) {
            _tvs[i] = tv;
          } else {
            _tvs.add(tv);
          }
        });
      },
      onDone: () {
        if (mounted) setState(() => _discovering = false);
      },
    );
  }

  Future<void> _scan() async {
    await Get.toNamed('/scan');
    if (mounted) _discover();
  }

  Future<void> _inputIp() async {
    // 放在 builder 外：對話框重建（例如鍵盤彈出）時不會清掉已輸入的文字。
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('輸入 IP'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(hintText: '192.168.1.10:3322'),
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('確定'),
            ),
          ],
        );
      },
    );
    Future.delayed(const Duration(seconds: 1), controller.dispose);
    if (text == null || text.trim().isEmpty) return;
    var host = text.trim();
    var port = TvCast.defaultPort;
    final idx = host.lastIndexOf(':');
    if (idx > 0 && !host.contains('::')) {
      final p = int.tryParse(host.substring(idx + 1));
      if (p == null || p < 1 || p > 65535) {
        SmartDialog.showToast('找不到 PiliBTRTV');
        return;
      }
      port = p;
      host = host.substring(0, idx);
    }
    SmartDialog.showLoading();
    final tv = await TvCast.probe(host, port);
    SmartDialog.dismiss();
    if (tv == null) {
      SmartDialog.showToast('找不到 PiliBTRTV');
      return;
    }
    TvCast.upsert(tv);
    // 重新取得（帶入已存的 token）
    final saved = TvCast.loadKnown().where((e) => e.id == tv.id).firstOrNull;
    if (!mounted) return;
    setState(() {
      final t = saved ?? tv;
      final i = _tvs.indexWhere((e) => e.id == t.id);
      if (i >= 0) {
        _tvs[i] = t;
      } else {
        _tvs.add(t);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text('投放到', style: theme.textTheme.titleMedium),
                  const SizedBox(width: 12),
                  if (_discovering)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            for (final tv in _tvs)
              ListTile(
                leading: const Icon(Icons.tv),
                title: Text(tv.name),
                subtitle: Text('${tv.host}:${tv.port}'),
                onTap: () => widget.onSelect(tv),
              ),
            if (_tvs.isEmpty && !_discovering)
              const ListTile(
                enabled: false,
                leading: Icon(Icons.tv_off),
                title: Text('找不到電視'),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('掃描 QR code'),
              onTap: _scan,
            ),
            ListTile(
              leading: const Icon(Icons.keyboard),
              title: const Text('輸入 IP'),
              onTap: _inputIp,
            ),
            ListTile(
              leading: const Icon(Icons.cast),
              title: const Text('DLNA 裝置'),
              onTap: widget.onDlna,
            ),
          ],
        ),
      ),
    );
  }
}
