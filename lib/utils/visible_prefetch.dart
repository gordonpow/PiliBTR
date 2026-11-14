import 'dart:async';

import 'package:PiliPlus/common/widgets/zh_material.dart';
import 'package:PiliPlus/utils/play_url_cache.dart';

/// A video card that can be prefetched while it is on screen.
abstract interface class VisibleCard {
  /// Bvid and cid of the card, or null when it has no cid.
  (String, int)? get prefetchKey;

  /// Rectangle of the card on screen, or null when it is not visible: its
  /// page is not on top, its tab is hidden, or it has no layout.
  Rect? get visibleRect;
}

/// Visible-card prefetch for every video list (home, related videos,
/// history, favorites, ...): each card registers here, and when a list stops
/// scrolling (and every 500 ms while it scrolls) the cards on screen go to
/// [PlayUrlCache.prefetchVisible]. Before, only the home feed did this, so a
/// related video waited 1-2 s for its playurl when it was opened.
abstract final class VisiblePrefetch {
  static final Set<VisibleCard> _cards = {};
  static Timer? _debounce;
  static Timer? _throttle;
  static _Lifecycle? _lifecycle;

  /// Lists that scroll now.
  static final Set<ScrollPosition> _scrolling = {};

  static void add(VisibleCard card) {
    _lifecycle ??= _Lifecycle();
    _cards.add(card);
    schedule();
  }

  static void remove(VisibleCard card) {
    _cards.remove(card);
  }

  /// Collects the visible cards after the layout settles.
  static void schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _collect);
  }

  /// Called by the cards when their list starts or stops scrolling.
  static void onScrolling(ScrollPosition position, bool scrolling) {
    if (scrolling) {
      _scrolling.add(position);
      _throttle ??= Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => _collect(),
      );
    } else {
      _scrolling.remove(position);
      if (_scrolling.isEmpty) {
        _throttle?.cancel();
        _throttle = null;
        schedule();
      }
    }
  }

  static void _collect() {
    if (PlayUrlCache.isPaused) return;
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null) return;
    final screen = Offset.zero & (view.physicalSize / view.devicePixelRatio);
    final found = <({(String, int) key, Rect rect})>[];
    final seen = <(String, int)>{};
    for (final card in _cards) {
      final key = card.prefetchKey;
      if (key == null || seen.contains(key)) continue;
      final rect = card.visibleRect;
      if (rect == null || !rect.overlaps(screen)) continue;
      seen.add(key);
      found.add((key: key, rect: rect));
    }
    if (found.isEmpty) return;
    // Top to bottom, left to right: the cards the eye reaches first.
    found.sort((a, b) {
      final c = a.rect.top.compareTo(b.rect.top);
      return c != 0 ? c : a.rect.left.compareTo(b.rect.left);
    });
    unawaited(PlayUrlCache.prefetchVisible([for (final f in found) f.key]));
  }
}

/// Stops the prefetch while the app is in the background.
class _Lifecycle with WidgetsBindingObserver {
  _Lifecycle() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      PlayUrlCache.isPaused = false;
      VisiblePrefetch.schedule();
    } else {
      PlayUrlCache.isPaused = true;
      PlayUrlCache.clearPending();
    }
  }
}
