import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_insets_safe_area.dart';
import 'package:PiliPlus/common/widgets/view_sliver_safe_area.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';
import 'package:PiliPlus/pages/search/controller.dart' show DebounceStreamState;
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/models/setting_tree.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/waterfall.dart';
import 'package:PiliPlus/utils/zh_convert.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:get/get.dart';

class SettingsSearchPage extends StatefulWidget {
  const SettingsSearchPage({super.key});

  @override
  State<SettingsSearchPage> createState() => _SettingsSearchPageState();
}

class _SettingsSearchPageState
    extends DebounceStreamState<SettingsSearchPage, String> {
  static const _maxHistory = 20;

  final _textEditingController = TextEditingController();
  final RxList<SettingsModel> _list = <SettingsModel>[].obs;
  final RxString _query = ''.obs;
  late final RxList<String> _history = List<String>.from(
    GStorage.localCache.get(LocalCacheKey.settingsSearchHistory) ??
        const <String>[],
  ).obs;
  late final SettingTree _tree = SettingTree.build();
  late final List<SettingsModel> _settings = _tree.allItems;

  bool _matches(String? text, String query) {
    if (text == null) return false;
    return text.toLowerCase().contains(query) ||
        ZhConvert.convert(text).toLowerCase().contains(query);
  }

  @override
  void onValueChanged(String value) {
    final query = value.trim().toLowerCase();
    _query.value = query;
    if (query.isEmpty) {
      _list.clear();
    } else {
      _list.value = _settings
          .where(
            (item) =>
                _matches(item.effectiveTitle, query) ||
                _matches(item.effectiveSubtitle, query),
          )
          .toList();
    }
  }

  void _saveHistory() {
    GStorage.localCache.put(
      LocalCacheKey.settingsSearchHistory,
      _history.toList(),
    );
  }

  void _record(String keyword) {
    keyword = keyword.trim();
    if (keyword.isEmpty) return;
    _history
      ..remove(keyword)
      ..insert(0, keyword);
    if (_history.length > _maxHistory) {
      _history.removeRange(_maxHistory, _history.length);
    }
    _saveHistory();
  }

  void _removeHistory(String keyword) {
    _history.remove(keyword);
    _saveHistory();
  }

  void _clearHistory() {
    _history.clear();
    _saveHistory();
  }

  void _onHistoryTap(String keyword) {
    _textEditingController.value = TextEditingValue(
      text: keyword,
      selection: TextSelection.collapsed(offset: keyword.length),
    );
    ctr!.add(keyword);
  }

  @override
  void dispose() {
    _textEditingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SimpleScaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            onPressed: () {
              if (_textEditingController.text.isNotEmpty) {
                _textEditingController.clear();
                _query.value = '';
                _list.clear();
              } else {
                Get.back();
              }
            },
            icon: const Icon(Icons.clear),
          ),
          const SizedBox(width: 10),
        ],
        title: TextField(
          autofocus: true,
          controller: _textEditingController,
          textAlignVertical: TextAlignVertical.center,
          onChanged: ctr!.add,
          onSubmitted: _record,
          decoration: const InputDecoration(
            isDense: true,
            hintText: '搜尋',
            visualDensity: .standard,
            border: InputBorder.none,
          ),
        ),
      ),
      body: ViewInsetsSafeArea(
        child: CustomScrollView(
          slivers: [
            ViewSliverSafeArea(
              sliver: Obx(() {
                if (_query.value.isEmpty) {
                  return _buildHistory(context);
                }
                if (_list.isEmpty) {
                  return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text('沒有符合的設定')),
                  );
                }
                final theme = Theme.of(context);
                final labelStyle = theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                );
                return SliverMasonryGrid(
                  gridDelegate: gridDelegate,
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final item = _list[index];
                    final path = _tree.pathOf(item);
                    return Column(
                      crossAxisAlignment: .start,
                      children: [
                        if (path != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 16, top: 8),
                            child: Text(path, style: labelStyle),
                          ),
                        _TapRecorder(
                          onTap: () => _record(_textEditingController.text),
                          child: item.widget,
                        ),
                      ],
                    );
                  }, childCount: _list.length),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistory(BuildContext context) {
    if (_history.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: Text('輸入關鍵字搜尋設定')),
      );
    }
    final theme = Theme.of(context);
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(left: 16, right: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('搜尋紀錄', style: theme.textTheme.titleSmall),
                ),
                TextButton(
                  onPressed: _clearHistory,
                  child: const Text('清除全部'),
                ),
              ],
            ),
          );
        }
        final keyword = _history[index - 1];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.history),
          title: Text(keyword),
          trailing: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => _removeHistory(keyword),
          ),
          onTap: () => _onHistoryTap(keyword),
        );
      }, childCount: _history.length + 1),
    );
  }

  late final gridDelegate = SliverSimpleGridDelegateWithMaxCrossAxisExtent_(
    maxCrossAxisExtent: Grid.smallCardWidth * 2,
  );
}

/// Calls [onTap] when a pointer goes down and up within [kTouchSlop], without
/// taking part in the gesture arena (the child keeps its own tap).
class _TapRecorder extends StatefulWidget {
  const _TapRecorder({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_TapRecorder> createState() => _TapRecorderState();
}

class _TapRecorderState extends State<_TapRecorder> {
  Offset? _downPosition;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) => _downPosition = e.position,
      onPointerUp: (e) {
        final down = _downPosition;
        _downPosition = null;
        if (down != null && (e.position - down).distance < kTouchSlop) {
          widget.onTap();
        }
      },
      onPointerCancel: (_) => _downPosition = null,
      child: widget.child,
    );
  }
}
