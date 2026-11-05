import 'package:material_ui/material_ui.dart';

class CompactNavigationDestination {
  const CompactNavigationDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final Widget icon;
  final Widget selectedIcon;
}

/// A flat bottom bar: a small icon over a small label, the selected item
/// in the primary color, and no indicator.
class CompactNavigationBar extends StatelessWidget {
  const CompactNavigationBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  static const double height = 50;

  final List<CompactNavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Material(
      color: colorScheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: colorScheme.outline.withValues(alpha: 0.12),
              width: 0.5,
            ),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: SizedBox(
            height: height,
            child: Row(
              children: [
                for (int i = 0; i < destinations.length; i++)
                  Expanded(child: _item(colorScheme, i)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(ColorScheme colorScheme, int index) {
    final item = destinations[index];
    final selected = index == selectedIndex;
    final color = selected ? colorScheme.primary : colorScheme.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: () => onDestinationSelected(index),
        radius: 32,
        child: Column(
          mainAxisAlignment: .center,
          children: [
            IconTheme.merge(
              data: IconThemeData(color: color, size: 24),
              child: selected ? item.selectedIcon : item.icon,
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: TextStyle(fontSize: 10.5, height: 1.2, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
