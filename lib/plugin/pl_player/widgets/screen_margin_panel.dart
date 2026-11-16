import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';

/// 全螢幕橫向畫面邊界的設定（左、上、右、下，0–20%）。
/// 拖動時即時套用到目前的播放器，放開時保存。
class ScreenMarginPanel extends StatefulWidget {
  const ScreenMarginPanel({super.key});

  static const double maxPercent = 20;

  /// 設定頁副標題用：「左 0%・上 0%・右 0%・下 0%」。
  static String describe(List<double> margin) => [
    for (var i = 0; i < 4; i++) '${_labels[i]} ${_format(margin[i])}',
  ].join('・');

  static const _labels = ['左', '上', '右', '下'];

  static String _format(double v) =>
      '${v == v.roundToDouble() ? v.toInt() : v.toStringAsFixed(1)}%';

  @override
  State<ScreenMarginPanel> createState() => _ScreenMarginPanelState();
}

class _ScreenMarginPanelState extends State<ScreenMarginPanel> {
  late final List<double> _margin =
      PlPlayerController.instance?.fullScreenMargin.toList() ??
      Pref.fullScreenMargin;

  void _update(int index, double value) {
    setState(() => _margin[index] = value);
    final controller = PlPlayerController.instance;
    if (controller != null) controller.fullScreenMargin[index] = value;
  }

  void _save() =>
      GStorage.setting.put(SettingBoxKey.fullScreenMargin, _margin.toList());

  void _reset() {
    for (var i = 0; i < 4; i++) {
      _update(i, 0);
    }
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 4; i++)
          Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  ScreenMarginPanel._labels[i],
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: Slider(
                  value: _margin[i].clamp(0, ScreenMarginPanel.maxPercent),
                  max: ScreenMarginPanel.maxPercent,
                  divisions: 40,
                  label: ScreenMarginPanel._format(_margin[i]),
                  onChanged: (value) => _update(i, value),
                  onChangeEnd: (_) => _save(),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  ScreenMarginPanel._format(_margin[i]),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        Row(
          children: [
            Expanded(
              child: Text(
                '只在全螢幕橫向時生效，單位是螢幕寬（左右）或高（上下）的百分比',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
            TextButton(onPressed: _reset, child: const Text('全部歸零')),
          ],
        ),
      ],
    );
  }
}
