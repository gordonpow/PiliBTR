import 'package:PiliPlus/common/widgets/flutter/list_tile.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/models/common/setting_type.dart';
import 'package:PiliPlus/pages/about/view.dart';
import 'package:PiliPlus/pages/setting/account_actions.dart';
import 'package:PiliPlus/pages/setting/models/setting_tree.dart';
import 'package:PiliPlus/pages/setting/setting_node_page.dart';
import 'package:PiliPlus/pages/update/view.dart';
import 'package:PiliPlus/pages/webdav/view.dart';
import 'package:PiliPlus/utils/extension/size_ext.dart';
import 'package:PiliPlus/utils/update.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart' hide ListTile;

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  late final SettingTree _tree;

  /// Landscape: selected nodes, from a root node to a group.
  List<SettingNode> _path = [];

  /// Landscape: category whose children the left pane shows, null for roots.
  SettingNode? _category;

  /// Landscape: WebDAV or About selected instead of a node.
  SettingType? _special;

  late bool _isPortrait;
  late ThemeData theme;

  @override
  void initState() {
    super.initState();
    _tree = SettingTree.build(accountActions: accountActionItems());
    final account = _tree.roots.firstWhere((e) => e.id == 'account');
    _path = [account];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    theme = Theme.of(context);
    _isPortrait = MediaQuery.sizeOf(context).isPortrait;
  }

  String get _title {
    if (_isPortrait) return '設定';
    if (_special != null) return _special!.title;
    if (_path.isEmpty) return '設定';
    return _path.map((e) => e.title).join(' › ');
  }

  @override
  Widget build(BuildContext context) {
    final canPop = _isPortrait || _category == null;
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_isPortrait && _category != null) {
          setState(() => _category = null);
        }
      },
      child: SimpleScaffold(
        appBar: AppBar(title: Text(_title)),
        body: ViewSafeArea(
          child: _isPortrait
              ? _buildList(theme)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: _buildList(theme),
                    ),
                    VerticalDivider(
                      width: 1,
                      color: theme.colorScheme.outline.withValues(alpha: 0.1),
                    ),
                    Expanded(
                      flex: 6,
                      child: switch (_special) {
                        .webdavSetting => const WebDavSettingPage(
                          showAppBar: false,
                        ),
                        .about => const AboutPage(showAppBar: false),
                        _ =>
                          _path.isEmpty
                              ? const SizedBox.shrink()
                              : SettingNodePage(
                                  node: _path.last,
                                  showAppBar: false,
                                ),
                      },
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  void _openRoot(SettingNode node) {
    if (_isPortrait) {
      Get.to(() => SettingNodePage(node: node));
    } else {
      setState(() {
        _special = null;
        if (node.isGroup) {
          _path = [node];
        } else {
          _category = node;
          _path = [node, node.children.first];
        }
      });
    }
  }

  void _openChild(SettingNode node) {
    setState(() {
      _special = null;
      _path = [node.parent!, node];
    });
  }

  void _toPage(SettingType type) {
    if (_isPortrait) {
      Get.to(
        () => switch (type) {
          .webdavSetting => const WebDavSettingPage(),
          _ => const AboutPage(),
        },
      );
    } else {
      setState(() {
        _special = type;
        _category = null;
      });
    }
  }

  Color? _getTileColor(ThemeData theme, bool selected) {
    if (_isPortrait || !selected) return null;
    return theme.colorScheme.onInverseSurface;
  }

  Widget _buildList(ThemeData theme) {
    final padding = MediaQuery.viewPaddingOf(context);
    TextStyle titleStyle = theme.textTheme.titleMedium!;
    TextStyle subTitleStyle = theme.textTheme.labelMedium!.copyWith(
      color: theme.colorScheme.outline,
    );
    final category = _isPortrait ? null : _category;
    if (category != null) {
      return ListView(
        padding: EdgeInsets.only(bottom: padding.bottom + 100),
        children: [
          ListTile(
            onTap: () => setState(() => _category = null),
            leading: const Icon(Icons.chevron_left),
            title: Text(category.title, style: titleStyle),
          ),
          for (final child in category.children)
            ListTile(
              tileColor: _getTileColor(
                theme,
                _special == null && _path.lastOrNull == child,
              ),
              onTap: () => _openChild(child),
              leading: Icon(child.icon),
              title: Text(child.title, style: titleStyle),
              subtitle: child.subtitle == null
                  ? null
                  : Text(child.subtitle!, style: subTitleStyle),
            ),
        ],
      );
    }
    return ListView(
      padding: EdgeInsets.only(bottom: padding.bottom + 100),
      children: [
        _buildSearchItem(theme),
        for (final node in _tree.roots)
          ListTile(
            tileColor: _getTileColor(
              theme,
              _special == null && _path.firstOrNull == node,
            ),
            onTap: () => _openRoot(node),
            leading: Icon(node.icon),
            title: Text(node.title, style: titleStyle),
            subtitle: node.subtitle == null
                ? null
                : Text(node.subtitle!, style: subTitleStyle),
          ),
        ListTile(
          onTap: () => Get.to(() => const UpdatePage()),
          leading: Obx(
            () => Badge(
              isLabelVisible: Update.available.value != null,
              smallSize: 7,
              child: const Icon(Icons.system_update_alt),
            ),
          ),
          title: Text('更新', style: titleStyle),
          subtitle: Obx(
            () {
              final tag = Update.available.value?.tag;
              return Text(
                tag == null ? '自動檢查、手動檢查更新' : '發現新版本 $tag',
                style: subTitleStyle,
              );
            },
          ),
        ),
        ListTile(
          tileColor: _getTileColor(theme, _special == .webdavSetting),
          onTap: () => _toPage(.webdavSetting),
          leading: const Icon(MdiIcons.databaseCogOutline),
          title: Text(SettingType.webdavSetting.title, style: titleStyle),
        ),
        ListTile(
          tileColor: _getTileColor(theme, _special == .about),
          onTap: () => _toPage(.about),
          leading: const Icon(Icons.info_outline),
          title: Text(SettingType.about.title, style: titleStyle),
        ),
      ],
    );
  }

  Widget _buildSearchItem(ThemeData theme) => Padding(
    padding: const EdgeInsets.only(
      left: 16,
      right: 16,
      bottom: 8,
    ),
    child: Material(
      color: theme.colorScheme.onInverseSurface,
      borderRadius: const BorderRadius.all(Radius.circular(50)),
      child: InkWell(
        onTap: () => Get.toNamed('/settingsSearch'),
        borderRadius: const BorderRadius.all(Radius.circular(50)),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  size: 18,
                  applyTextScaling: true,
                  Icons.search,
                ),
                Text(
                  ' 搜尋',
                  style: TextStyle(height: 1),
                  strutStyle: StrutStyle(height: 1, leading: 0),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
