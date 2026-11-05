import 'dart:io';
import 'dart:typed_data';

/// Merges a video-only and an audio-only fragmented MP4 (the DASH `.m4s`
/// streams of bilibili) into one fragmented MP4 that common players can
/// play. The media data is copied as it is: nothing is decoded or
/// encoded.
///
/// Output layout: `ftyp` (from the video), a new `moov` with both tracks
/// (video track 1, audio track 2), then the fragments (`moof` + `mdat`) of
/// both files in decode time order.
abstract final class Mp4Mux {
  static const _copyChunk = 1 << 20;

  /// Merges [videoPath] and [audioPath] into [outPath].
  /// [onProgress] gets the part of the media data that is written (0 to 1).
  static Future<void> merge({
    required String videoPath,
    required String audioPath,
    required String outPath,
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final video = await File(videoPath).open();
    final audio = await File(audioPath).open();
    final out = await File(outPath).open(mode: FileMode.writeOnly);
    try {
      final v = await _Track.read(video, trackId: 1);
      final a = await _Track.read(audio, trackId: 2);

      await out.writeFrom(v.ftyp);
      await out.writeFrom(_buildMoov(v, a));

      // Both lists are in time order: merge them.
      final fragments = <_Fragment>[];
      var i = 0, j = 0;
      while (i < v.fragments.length || j < a.fragments.length) {
        if (j >= a.fragments.length ||
            (i < v.fragments.length &&
                v.fragments[i].time <= a.fragments[j].time)) {
          fragments.add(v.fragments[i++]);
        } else {
          fragments.add(a.fragments[j++]);
        }
      }

      final total = fragments.fold<int>(0, (s, f) => s + f.length);
      var written = 0;
      var sequence = 1;
      for (final f in fragments) {
        if (isCancelled?.call() ?? false) {
          throw const FileSystemException('cancelled');
        }
        final file = f.track.file;
        final newOffset = await out.position();
        await file.setPosition(f.offset);
        final moof = await file.read(f.moofSize);
        _patchMoof(
          moof,
          trackId: f.track.trackId,
          sequence: sequence++,
          offsetShift: newOffset - f.offset,
        );
        await out.writeFrom(moof);
        var left = f.length - f.moofSize;
        while (left > 0) {
          final data = await file.read(left < _copyChunk ? left : _copyChunk);
          if (data.isEmpty) throw const FormatException('unexpected end');
          await out.writeFrom(data);
          left -= data.length;
        }
        written += f.length;
        onProgress?.call(written / total);
      }
    } finally {
      await video.close();
      await audio.close();
      await out.close();
    }
  }

  static Uint8List _buildMoov(_Track v, _Track a) {
    final mvhd = Uint8List.fromList(v.mvhd);
    // next_track_ID is the last field of mvhd.
    _setU32(mvhd, mvhd.length - 4, 3);
    return _box('moov', [
      mvhd,
      v.trak,
      a.trak,
      _box('mvex', [v.trex, a.trex]),
    ]);
  }

  /// Sets the track ID and sequence number of a `moof`, and moves
  /// absolute data offsets by [offsetShift].
  static void _patchMoof(
    Uint8List moof, {
    required int trackId,
    required int sequence,
    required int offsetShift,
  }) {
    final header = _headerSize(moof, 0);
    for (final child in _children(moof, header, moof.length)) {
      if (child.type == 'mfhd') {
        _setU32(moof, child.payload + 4, sequence);
      } else if (child.type == 'traf') {
        for (final box in _children(moof, child.payload, child.end)) {
          if (box.type != 'tfhd') continue;
          final flags = _u32(moof, box.payload) & 0xFFFFFF;
          _setU32(moof, box.payload + 4, trackId);
          // base-data-offset-present: the offset is from the file start.
          if (flags & 0x1 != 0) {
            final p = box.payload + 8;
            _setU64(moof, p, _u64(moof, p) + offsetShift);
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Box helpers
  // ---------------------------------------------------------------------------

  static Uint8List _box(String type, List<Uint8List> children) {
    final size = 8 + children.fold<int>(0, (s, c) => s + c.length);
    final b = BytesBuilder(copy: false)
      ..add(_u32Bytes(size))
      ..add(type.codeUnits);
    for (final c in children) {
      b.add(c);
    }
    return b.takeBytes();
  }

  static int _headerSize(Uint8List b, int offset) =>
      _u32(b, offset) == 1 ? 16 : 8;

  static Iterable<_Child> _children(Uint8List b, int start, int end) sync* {
    var pos = start;
    while (pos + 8 <= end) {
      var size = _u32(b, pos);
      final type = String.fromCharCodes(b, pos + 4, pos + 8);
      var header = 8;
      if (size == 1) {
        size = _u64(b, pos + 8);
        header = 16;
      } else if (size == 0) {
        size = end - pos;
      }
      if (size < header || pos + size > end) {
        throw FormatException('bad box $type');
      }
      yield _Child(type, pos, pos + header, pos + size);
      pos += size;
    }
  }

  static int _u32(Uint8List b, int o) => ByteData.sublistView(b).getUint32(o);

  static int _u64(Uint8List b, int o) => ByteData.sublistView(b).getUint64(o);

  static void _setU32(Uint8List b, int o, int v) =>
      ByteData.sublistView(b).setUint32(o, v);

  static void _setU64(Uint8List b, int o, int v) =>
      ByteData.sublistView(b).setUint64(o, v);

  static Uint8List _u32Bytes(int v) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, v);
}

class _Child {
  const _Child(this.type, this.start, this.payload, this.end);

  final String type;
  final int start;

  /// Offset of the content after the box header.
  final int payload;
  final int end;

  Uint8List bytes(Uint8List b) => Uint8List.sublistView(b, start, end);
}

/// One fragment: a `moof` and the boxes after it up to the end of its
/// last `mdat`, copied as one block.
class _Fragment {
  _Fragment(this.track, this.offset, this.moofSize, this.length, this.time);

  final _Track track;
  final int offset;
  final int moofSize;
  final int length;

  /// Decode time of the fragment in seconds.
  final double time;
}

class _Track {
  _Track(this.file, this.trackId);

  final RandomAccessFile file;
  final int trackId;
  late Uint8List ftyp;
  late Uint8List mvhd;
  late Uint8List trak;
  late Uint8List trex;
  late int timescale;
  final fragments = <_Fragment>[];

  static Future<_Track> read(
    RandomAccessFile file, {
    required int trackId,
  }) async {
    final t = _Track(file, trackId);
    final length = await file.length();
    final top = <({String type, int offset, int size})>[];
    var pos = 0;
    while (pos + 8 <= length) {
      await file.setPosition(pos);
      final h = await file.read(16);
      final d = ByteData.sublistView(h);
      var size = d.getUint32(0);
      final type = String.fromCharCodes(h, 4, 8);
      if (size == 1) {
        size = d.getUint64(8);
      } else if (size == 0) {
        size = length - pos;
      }
      if (size < 8) throw FormatException('bad box $type');
      top.add((type: type, offset: pos, size: size));
      pos += size;
    }

    Future<Uint8List> load(({String type, int offset, int size}) box) async {
      await file.setPosition(box.offset);
      return file.read(box.size);
    }

    final ftyp = top.where((e) => e.type == 'ftyp').firstOrNull;
    final moov = top.where((e) => e.type == 'moov').firstOrNull;
    if (ftyp == null || moov == null) {
      throw const FormatException('not an MP4 stream');
    }
    final ftypBytes = await load(ftyp);
    final moovBytes = await load(moov);
    t
      ..ftyp = ftypBytes
      .._readMoov(moovBytes);

    // Fragments: from each moof to the end of its last mdat.
    for (var i = 0; i < top.length; i++) {
      final box = top[i];
      if (box.type != 'moof') continue;
      var end = box.offset + box.size;
      for (var k = i + 1; k < top.length && top[k].type != 'moof'; k++) {
        if (top[k].type == 'mdat') end = top[k].offset + top[k].size;
      }
      final moof = await load(box);
      t.fragments.add(
        _Fragment(
          t,
          box.offset,
          box.size,
          end - box.offset,
          t._decodeTime(moof) / t.timescale,
        ),
      );
    }
    if (t.fragments.isEmpty) {
      throw const FormatException('not a fragmented MP4 stream');
    }
    return t;
  }

  void _readMoov(Uint8List moov) {
    Uint8List? mvhd, trak, trex;
    int? scale;
    for (final c in Mp4Mux._children(
      moov,
      Mp4Mux._headerSize(moov, 0),
      moov.length,
    )) {
      switch (c.type) {
        case 'mvhd':
          mvhd = Uint8List.fromList(c.bytes(moov));
        case 'trak':
          trak = Uint8List.fromList(c.bytes(moov));
          scale = _timescale(moov, c);
        case 'mvex':
          for (final e in Mp4Mux._children(moov, c.payload, c.end)) {
            if (e.type == 'trex') trex = Uint8List.fromList(e.bytes(moov));
          }
      }
    }
    if (mvhd == null || trak == null || trex == null || scale == null) {
      throw const FormatException('missing moov boxes');
    }
    // track_ID in tkhd: after version/flags and the two times.
    for (final c in Mp4Mux._children(
      trak,
      Mp4Mux._headerSize(trak, 0),
      trak.length,
    )) {
      if (c.type == 'tkhd') {
        final version = trak[c.payload];
        Mp4Mux._setU32(trak, c.payload + (version == 1 ? 20 : 12), trackId);
      }
    }
    Mp4Mux._setU32(trex, Mp4Mux._headerSize(trex, 0) + 4, trackId);
    this.mvhd = mvhd;
    this.trak = trak;
    this.trex = trex;
    timescale = scale;
  }

  /// Timescale of the track: trak > mdia > mdhd.
  static int? _timescale(Uint8List b, _Child trak) {
    for (final m in Mp4Mux._children(b, trak.payload, trak.end)) {
      if (m.type != 'mdia') continue;
      for (final h in Mp4Mux._children(b, m.payload, m.end)) {
        if (h.type != 'mdhd') continue;
        final version = b[h.payload];
        return Mp4Mux._u32(b, h.payload + (version == 1 ? 20 : 12));
      }
    }
    return null;
  }

  /// Base media decode time of the first traf (tfdt), or 0.
  int _decodeTime(Uint8List moof) {
    for (final c in Mp4Mux._children(
      moof,
      Mp4Mux._headerSize(moof, 0),
      moof.length,
    )) {
      if (c.type != 'traf') continue;
      for (final b in Mp4Mux._children(moof, c.payload, c.end)) {
        if (b.type != 'tfdt') continue;
        return moof[b.payload] == 1
            ? Mp4Mux._u64(moof, b.payload + 4)
            : Mp4Mux._u32(moof, b.payload + 4);
      }
    }
    return 0;
  }
}
