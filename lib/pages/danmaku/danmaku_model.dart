sealed class DanmakuExtra {
  Object get mid;
  Object get id;

  /// Original text when the displayed text is a translation. Blocking,
  /// dedupe, copy and report use the original.
  String? get original;

  const DanmakuExtra();
}

class VideoDanmaku extends DanmakuExtra {
  @override
  final int id;
  @override
  final String mid;

  int like;

  bool isLike;

  @override
  final String? original;

  VideoDanmaku({
    required this.id,
    required this.mid,
    this.like = 0,
    this.isLike = false,
    this.original,
  });
}

class LiveDanmaku extends DanmakuExtra {
  @override
  final Object id;
  @override
  final int mid;

  final int dmType;

  final Object ts;
  final Object ct;

  @override
  final String? original;

  const LiveDanmaku({
    required this.id,
    required this.mid,
    required this.dmType,
    required this.ts,
    required this.ct,
    this.original,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'mid': mid,
    'dm_type': dmType,
    'ts': ts,
    'ct': ct,
  };
}
