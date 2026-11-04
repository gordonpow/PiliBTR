import 'dart:async';
import 'dart:io' show Platform;

import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/loading_widget/loading_widget.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_sliver_safe_area.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:PiliPlus/utils/permission_handler.dart';
import 'package:dlna_dart/dlna.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class DLNAPage extends StatefulWidget {
  const DLNAPage({super.key});

  @override
  State<DLNAPage> createState() => _DLNAPageState();
}

class _DLNAPageState extends State<DLNAPage> {
  final _searcher = DLNAManager();
  final Map<String, DLNADevice> _deviceList = {};
  late final _url = Get.parameters['url']!;
  late final _title = Get.parameters['title'];

  Timer? _timer;
  bool _isSearching = false;
  PermissionStatus? _permissionStatus;
  String? _searchError;
  DLNADevice? _lastDevice;
  String? _lastDeviceKey;

  @override
  void initState() {
    super.initState();
    _onSearch(isInit: true);
  }

  Future<void> _onSearch({bool isInit = false}) async {
    if (_isSearching) return;
    _isSearching = true;
    _permissionStatus = null;
    _searchError = null;
    if (!isInit && mounted) {
      _lastDevice = null;
      _deviceList.clear();
      setState(() {});
    }
    try {
      // PiliPlus targets API 37; older systems do not require this permission.
      if (Platform.isAndroid && DeviceUtils.sdkInt >= 37) {
        final status = await Permission.accessLocalNetwork.request();
        if (!mounted) return;
        _permissionStatus = status;
        if (!status.isGranted) return;
      }
      final deviceManager = await _searcher.start();
      if (!mounted) return;
      _timer = Timer(const Duration(seconds: 20), _searcher.stop);
      await for (final deviceList in deviceManager.devices.stream) {
        if (mounted) {
          _deviceList.addAll(deviceList);
          setState(() {});
        }
      }
    } catch (_) {
      _searchError = '搜尋裝置失敗，請檢查網路後重試';
    } finally {
      _timer?.cancel();
      _timer = null;
      _searcher.stop();
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _searcher.stop();
    _lastDevice = null;
    _lastDeviceKey = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return SimpleScaffold(
      appBar: AppBar(
        title: const Text('投屏'),
        actions: [
          IconButton(
            tooltip: '搜尋',
            onPressed: _onSearch,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          if (_isSearching) linearLoading,
          ViewSliverSafeArea(sliver: _buildBody(colorScheme)),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    if (!_isSearching && _deviceList.isEmpty) {
      if (_permissionStatus case final status? when !status.isGranted) {
        final permanentlyDenied = status.isPermanentlyDenied;
        return HttpError(
          errMsg: permanentlyDenied
              ? '區域網許可權未授權，請在系統設定中允許附近的裝置，返回後點選搜尋'
              : '需要區域網許可權才能搜尋投屏裝置',
          btnText: permanentlyDenied ? '前往設定' : '授予許可權',
          onReload: permanentlyDenied
              ? () {
                  openAppSettings();
                }
              : _onSearch,
        );
      }
      return HttpError(
        errMsg: _searchError ?? '沒有裝置',
        onReload: _onSearch,
      );
    }
    if (_deviceList.isNotEmpty) {
      final keys = _deviceList.keys.toList();
      return SliverList.builder(
        itemCount: keys.length,
        itemBuilder: (context, index) {
          final key = keys[index];
          final device = _deviceList[key]!;
          final isCurr = key == _lastDeviceKey;
          return ListTile(
            title: Text(
              device.info.friendlyName,
              style: isCurr ? TextStyle(color: colorScheme.primary) : null,
            ),
            subtitle: Text(key),
            onTap: () async {
              if (isCurr) return;
              _lastDevice?.pause();
              _lastDevice = device;
              _lastDeviceKey = key;
              setState(() {});
              await device.setUrl(_url, title: _title ?? '');
              await device.play();
            },
          );
        },
      );
    }
    return const SliverToBoxAdapter();
  }
}
