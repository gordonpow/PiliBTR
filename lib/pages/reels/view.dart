import 'dart:async';

import 'package:PiliPlus/common/widgets/gesture/horizontal_drag_gesture_recognizer.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';
import 'package:PiliPlus/grpc/bilibili/community/service/dm/v1.pb.dart'
    show DanmakuElem;
import 'package:PiliPlus/grpc/dm.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/image_type.dart';
import 'package:PiliPlus/models_new/story/story_item.dart';
import 'package:PiliPlus/pages/danmaku/danmaku_model.dart';
import 'package:PiliPlus/pages/main_reply/view.dart';
import 'package:PiliPlus/pages/reels/controller.dart';
import 'package:PiliPlus/plugin/pl_player/utils/danmaku_options.dart';
import 'package:PiliPlus/utils/danmaku_utils.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/share_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/gestures.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 豎屏模式（類似 IG Reels）：全螢幕直向 PageView，上下滑換影片，播完自動接下一部。
///
/// 路由 `/reels`，參數 `{aid, bvid, cid, title, cover, item?, progress?}`。
/// 首頁「豎屏」分頁是卡片清單（[ReelsFeedPage]），點卡片才進入這一頁。
class ReelsPage extends StatefulWidget {
  const ReelsPage({super.key});

  @override
  State<ReelsPage> createState() => _ReelsPageState();
}

class _ReelsPageState extends State<ReelsPage> with WidgetsBindingObserver {
  late final ReelsController _ctr;
  late final String _tag = 'reels_${identityHashCode(this)}';

  bool _resumed = true;
  bool _tickerOn = true;
  bool _visible = false;

  final _danmakuOn = Pref.enableShowDanmaku.obs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final seed = Get.arguments;
    _ctr = Get.put(
      ReelsController(seed: seed is Map ? seed : null),
      tag: _tag,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 其他頁面蓋在上面時，TickerMode 會關閉
    _tickerOn = TickerMode.valuesOf(context).enabled;
    _scheduleEvaluate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _evaluate();
  }

  void _scheduleEvaluate() {
    // 不在 build 期間改變狀態
    scheduleMicrotask(() {
      if (mounted) _evaluate();
    });
  }

  void _evaluate() {
    if (!mounted) return;
    final visible = _resumed && _tickerOn;
    if (visible == _visible) return;
    _visible = visible;
    _ctr.setActive(visible);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Get.delete<ReelsController>(tag: _tag);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ReelsBody(ctr: _ctr, danmakuOn: _danmakuOn);
  }
}

class _ReelsBody extends StatelessWidget {
  const _ReelsBody({
    required this.ctr,
    required this.danmakuOn,
  });

  final ReelsController ctr;
  final RxBool danmakuOn;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Obx(() {
            final items = ctr.items;
            if (items.isEmpty) {
              return _emptyState();
            }
            return PageView.builder(
              controller: ctr.pageController,
              scrollDirection: Axis.vertical,
              itemCount: items.length,
              onPageChanged: ctr.onPageChanged,
              itemBuilder: (context, i) => _ReelsItem(
                key: ValueKey(items[i].aid),
                ctr: ctr,
                item: items[i],
                position: i,
                danmakuOn: danmakuOn,
              ),
            );
          }),
          Positioned(
            left: 4,
            top: 0,
            child: SafeArea(
              child: IconButton(
                color: Colors.white,
                tooltip: '返回',
                icon: const Icon(Icons.arrow_back),
                onPressed: Get.back,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() => Obx(() {
    if (ctr.loading.value) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '暫時沒有豎屏影片',
            style: TextStyle(color: Colors.white, fontSize: 15),
          ),
          if (ctr.error.value case final msg?)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                msg,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: ctr.retry, child: const Text('重試')),
        ],
      ),
    );
  });
}

class _ReelsItem extends StatelessWidget {
  const _ReelsItem({
    super.key,
    required this.ctr,
    required this.item,
    required this.position,
    required this.danmakuOn,
  });

  final ReelsController ctr;
  final StoryItem item;
  final int position;
  final RxBool danmakuOn;

  @override
  Widget build(BuildContext context) {
    final itemCtr = ctr.itemCtr(item);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Stack(
          fit: StackFit.expand,
          children: [
            // 封面，播放第一個畫面後被影片蓋掉
            NetworkImgLayer(
              src: item.cover,
              width: size.width,
              height: size.height,
              borderRadius: BorderRadius.zero,
              fit: BoxFit.cover,
            ),
            Obx(() {
              final current = ctr.index.value == position;
              final video = ctr.videoController.value;
              if (!current || video == null || !ctr.firstFrame.value) {
                return const SizedBox.shrink();
              }
              return ColoredBox(
                color: Colors.black,
                child: ClipRect(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SimpleVideo(controller: video),
                  ),
                ),
              );
            }),
            // 點一下暫停或繼續
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (ctr.index.value == position) ctr.togglePlay();
                },
              ),
            ),
            Obx(() {
              if (ctr.index.value != position) return const SizedBox.shrink();
              if (ctr.userPaused.value) {
                return const IgnorePointer(
                  child: Center(
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: 72,
                      color: Colors.white70,
                    ),
                  ),
                );
              }
              if (ctr.playError.value case final msg?) {
                return IgnorePointer(
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Text(
                          '$msg，即將播放下一部',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }
              if (!ctr.firstFrame.value) {
                return const IgnorePointer(
                  child: Center(
                    child: SizedBox.square(
                      dimension: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            }),
            // 彈幕
            Obx(() {
              if (ctr.index.value != position) return const SizedBox.shrink();
              return IgnorePointer(
                child: AnimatedOpacity(
                  opacity: danmakuOn.value ? Pref.danmakuOpacity : 0,
                  duration: const Duration(milliseconds: 100),
                  child: _ReelsDanmaku(
                    key: ValueKey('dm${item.aid}'),
                    ctr: ctr,
                    cid: item.cid,
                    size: size,
                  ),
                ),
              );
            }),
            // 底部漸層
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 220,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black54],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 76,
              bottom: 18,
              child: _InfoPanel(item: item, itemCtr: itemCtr),
            ),
            Positioned(
              right: 8,
              bottom: 24,
              child: _ActionColumn(
                ctr: ctr,
                item: item,
                itemCtr: itemCtr,
                danmakuOn: danmakuOn,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Obx(
                () => ctr.index.value == position
                    ? _ProgressBar(ctr: ctr)
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 左下：UP 主頭像、名稱、關注，標題（兩行，點選展開說明）。
class _InfoPanel extends StatefulWidget {
  const _InfoPanel({required this.item, required this.itemCtr});

  final StoryItem item;
  final ReelsItemCtr itemCtr;

  @override
  State<_InfoPanel> createState() => _InfoPanelState();
}

class _InfoPanelState extends State<_InfoPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final itemCtr = widget.itemCtr;
    const shadow = [Shadow(blurRadius: 4, color: Colors.black54)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Obx(
          () => Row(
            children: [
              GestureDetector(
                onTap: itemCtr.ownerMid == 0
                    ? null
                    : () => Get.toNamed('/member?mid=${itemCtr.ownerMid}'),
                child: NetworkImgLayer(
                  src: itemCtr.ownerFace.value,
                  width: 36,
                  height: 36,
                  type: ImageType.avatar,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  itemCtr.ownerName.value ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    shadows: shadow,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (itemCtr.ownerMid != 0)
                SizedBox(
                  height: 28,
                  child: itemCtr.followed.value
                      ? OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Colors.white54),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          onPressed: itemCtr.actionFollow,
                          child: const Text('已關注'),
                        )
                      : FilledButton(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onPressed: itemCtr.actionFollow,
                          child: const Text('關注'),
                        ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Obx(() {
            final desc = itemCtr.desc.value;
            final text = _expanded && desc != null && desc.isNotEmpty
                ? '${widget.item.title}\n$desc'
                : widget.item.title;
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: _expanded ? 220 : double.infinity,
              ),
              child: SingleChildScrollView(
                physics: _expanded
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                child: Text(
                  text,
                  maxLines: _expanded ? null : 2,
                  overflow: _expanded ? null : TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    shadows: shadow,
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// 右側直列按鈕。
class _ActionColumn extends StatelessWidget {
  const _ActionColumn({
    required this.ctr,
    required this.item,
    required this.itemCtr,
    required this.danmakuOn,
  });

  final ReelsController ctr;
  final StoryItem item;
  final ReelsItemCtr itemCtr;
  final RxBool danmakuOn;

  static const _active = Color(0xFFFB7299);

  Widget _btn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 32,
              color: active ? _active : Colors.white,
              shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Obx(
          () => _btn(
            icon: Icons.thumb_up_alt_rounded,
            label: NumUtils.numFormat(itemCtr.like.value),
            active: itemCtr.hasLike.value,
            onTap: itemCtr.actionLikeVideo,
          ),
        ),
        Obx(
          () => _btn(
            icon: Icons.monetization_on_rounded,
            label: NumUtils.numFormat(itemCtr.coin.value),
            active: itemCtr.coinNum.value > 0,
            onTap: itemCtr.actionCoinVideo,
          ),
        ),
        Obx(
          () => _btn(
            icon: Icons.star_rounded,
            label: NumUtils.numFormat(itemCtr.fav.value),
            active: itemCtr.hasFav.value,
            onTap: () => itemCtr.showFavBottomSheet(context),
          ),
        ),
        Obx(
          () => _btn(
            icon: Icons.comment_rounded,
            label: NumUtils.numFormat(itemCtr.reply.value),
            onTap: () =>
                MainReplyPage.toMainReplyPage(oid: item.aid, replyType: 1),
          ),
        ),
        Obx(
          () => _btn(
            icon: Icons.share_rounded,
            label: NumUtils.numFormat(itemCtr.share.value),
            onTap: () => ShareUtils.shareText(
              '${item.title} https://b23.tv/${item.bvid}',
            ),
          ),
        ),
        Obx(
          () => _btn(
            icon: danmakuOn.value
                ? Icons.subtitles_rounded
                : Icons.subtitles_off_outlined,
            label: danmakuOn.value ? '彈幕開' : '彈幕關',
            onTap: danmakuOn.toggle,
          ),
        ),
        _btn(
          icon: Icons.slideshow_rounded,
          label: '完整影片',
          onTap: () {
            final progress = ctr.currentPosition.inMilliseconds;
            PageUtils.toVideoPage(
              aid: item.aid,
              bvid: item.bvid,
              cid: item.cid,
              cover: item.cover,
              title: item.title,
              progress: progress > 0 ? progress : null,
              isVertical: true,
            );
          },
        ),
      ],
    );
  }
}

/// 底部細進度條。用自訂的水平拖動辨識器，首頁 TabBarView 的左右滑動
/// 不會搶走拖動。
class _ProgressBar extends StatefulWidget {
  const _ProgressBar({required this.ctr});

  final ReelsController ctr;

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  double? _drag;

  double _value(Offset local, double width) =>
      width <= 0 ? 0 : (local.dx / width).clamp(0.0, 1.0);

  void _seek(double value) {
    final total = widget.ctr.duration.value;
    widget.ctr.seekTo(
      Duration(milliseconds: (total.inMilliseconds * value).round()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            CustomHorizontalDragGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  CustomHorizontalDragGestureRecognizer
                >(CustomHorizontalDragGestureRecognizer.new, (instance) {
                  instance
                    ..onStart = (d) {
                      setState(() => _drag = _value(d.localPosition, width));
                    }
                    ..onUpdate = (d) {
                      setState(() => _drag = _value(d.localPosition, width));
                    }
                    ..onEnd = (_) {
                      if (_drag case final v?) _seek(v);
                      setState(() => _drag = null);
                    }
                    ..onCancel = () => setState(() => _drag = null);
                }),
            TapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  TapGestureRecognizer.new,
                  (instance) => instance.onTapUp = (d) =>
                      _seek(_value(d.localPosition, width)),
                ),
          },
          // 觸控區至少 28dp 高
          child: SizedBox(
            height: 28,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  widget.ctr.position,
                  widget.ctr.duration,
                ]),
                builder: (context, _) {
                  final total = widget.ctr.duration.value.inMilliseconds;
                  final value =
                      _drag ??
                      (total > 0
                          ? (widget.ctr.position.value.inMilliseconds / total)
                                .clamp(0.0, 1.0)
                          : 0.0);
                  final h = _drag != null ? 5.0 : 3.0;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      SizedBox(
                        height: h,
                        width: width,
                        child: ColoredBox(
                          color: Colors.white.withValues(alpha: .3),
                        ),
                      ),
                      SizedBox(
                        height: h,
                        width: width * value,
                        child: const ColoredBox(color: Color(0xFFFB7299)),
                      ),
                      if (_drag != null)
                        Positioned(
                          left: width * value - 6,
                          top: -4,
                          child: const SizedBox.square(
                            dimension: 13,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Color(0xFFFB7299),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 輕量彈幕：直接使用 canvas_danmaku 的 [DanmakuScreen]，自己依播放位置
/// 載入彈幕分段（不使用綁定 PlPlayerController 的 PlDanmaku）。
/// 簡化：不套用使用者的彈幕過濾規則與合併，略過高級彈幕（mode 7）。
class _ReelsDanmaku extends StatefulWidget {
  const _ReelsDanmaku({
    super.key,
    required this.ctr,
    required this.cid,
    required this.size,
  });

  final ReelsController ctr;
  final int cid;
  final Size size;

  @override
  State<_ReelsDanmaku> createState() => _ReelsDanmakuState();
}

class _ReelsDanmakuState extends State<_ReelsDanmaku> {
  DanmakuController<DanmakuExtra>? _dm;
  final Map<int, List<DanmakuElem>> _byTime = {};
  final Set<int> _requested = {};
  int _lastAdded = -1;
  int _lastPos = 0;
  Worker? _playingWorker;

  @override
  void initState() {
    super.initState();
    widget.ctr.position.addListener(_onPosition);
    _playingWorker = ever(widget.ctr.playing, (playing) {
      if (playing) {
        _dm?.resume();
      } else {
        _dm?.pause();
      }
    });
    _query(DmUtils.calcSegment(widget.ctr.position.value.inMilliseconds));
  }

  Future<void> _query(int segment) async {
    if (!_requested.add(segment)) return;
    final res = await DmGrpc.dmSegMobile(
      cid: widget.cid,
      segmentIndex: segment + 1,
    );
    if (!mounted) return;
    if (res case Success(:final response)) {
      for (final e in response.elems) {
        (_byTime[e.progress ~/ 100] ??= []).add(e);
      }
    } else {
      _requested.remove(segment);
    }
  }

  void _onPosition() {
    final dm = _dm;
    if (dm == null || !widget.ctr.playing.value) return;
    var pos = widget.ctr.position.value.inMilliseconds;
    // 拖動進度後清掉畫面上的彈幕
    if ((pos - _lastPos).abs() > 2000) dm.clear();
    _lastPos = pos;
    pos -= pos % 100;
    if (pos == _lastAdded) return;
    _lastAdded = pos;
    final segment = DmUtils.calcSegment(pos);
    if (!_requested.contains(segment)) {
      _query(segment);
      return;
    }
    final list = _byTime[pos ~/ 100];
    if (list == null) return;
    final weight = DanmakuOptions.danmakuWeight;
    final colorful = DanmakuOptions.blockColorful;
    for (final e in list) {
      if (e.weight < weight || e.mode == 7) continue;
      dm.addDanmaku(
        DanmakuContentItem(
          e.content,
          color: colorful ? Colors.white : DmUtils.decimalToColor(e.color),
          type: DmUtils.getPosition(e.mode),
          extra: VideoDanmaku(id: e.id.toInt(), mid: e.midHash),
        ),
      );
    }
  }

  @override
  void dispose() {
    widget.ctr.position.removeListener(_onPosition);
    _playingWorker?.dispose();
    _dm = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DanmakuScreen<DanmakuExtra>(
      createdController: (e) => _dm = e,
      option: DanmakuOptions.get(notFullscreen: true),
      size: widget.size,
    );
  }
}
