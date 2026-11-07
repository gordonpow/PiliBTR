import 'package:PiliPlus/common/widgets/zh_material.dart';

class ThinProgressBar extends StatelessWidget {
  const ThinProgressBar({super.key, required this.value, this.color});

  final double? value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(2)),
      child: LinearProgressIndicator(
        minHeight: 3,
        value: value,
        backgroundColor: primary.withValues(alpha: 0.15),
        color: color ?? primary,
        // 關閉 Material 3 的結尾圓點與軌道間隙
        stopIndicatorRadius: 0,
        stopIndicatorColor: Colors.transparent,
        trackGap: 0,
      ),
    );
  }
}
