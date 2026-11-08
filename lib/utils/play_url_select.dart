import 'dart:io' show Platform;

import 'package:PiliPlus/models/common/video/video_decode_type.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/services/download/btr_config.dart';
import 'package:PiliPlus/services/download/btr_proxy.dart';
import 'package:PiliPlus/utils/connectivity_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/video_utils.dart';

/// Streams the video page plays for one DASH playurl response.
typedef SelectedStreams = ({
  int targetQuality,
  FormatItem targetFormat,
  VideoDecodeFormatType targetDecode,
  VideoItem video,
  AudioItem? audio,
  String videoUrl,
  String audioUrl,
});

/// Picks the video stream (target quality + codec preference) and the audio
/// stream (audio preference) of a DASH response, and their CDN URLs
/// ([VideoUtils.getCdnUrl] already starts from the backup URL when BTR is on).
///
/// The video page and the tap-down warm-up both call this, so they get the
/// same URL. Returns null when [data] has no DASH video list.
SelectedStreams? selectStreams(
  PlayUrlModel data, {
  required int qn,
  required int audioQa,
  required List<VideoDecodeFormatType> preferCodecs,
}) {
  final dash = data.dash;
  final videos = dash?.video;
  if (dash == null || videos == null || videos.isEmpty) return null;
  final (
    int targetQuality,
    FormatItem targetFormat,
    VideoDecodeFormatType targetDecode,
    VideoItem targetVideo,
  ) = VideoUtils.findTargetVideo(
    videos,
    qn,
    data.acceptQuality,
    data.supportFormats!,
    preferCodecs,
  );
  AudioItem? audio;
  String audioUrl = '';
  final audioList = dash.audio;
  if (audioList != null && audioList.isNotEmpty) {
    audio = VideoUtils.findTargetAudio(audioList, audioQa);
    audioUrl = VideoUtils.getCdnUrl(audio.playUrls, isAudio: true);
  }
  return (
    targetQuality: targetQuality,
    targetFormat: targetFormat,
    targetDecode: targetDecode,
    video: targetVideo,
    audio: audio,
    videoUrl: VideoUtils.getCdnUrl(targetVideo.playUrls),
    audioUrl: audioUrl,
  );
}

/// Audio quality and codec preference the video page would use right now
/// (same rules as `VideoDetailController._queryVideoUrl`).
Future<({int audioQa, List<VideoDecodeFormatType> preferCodecs})>
defaultSelectParams() async {
  final player = PlPlayerController.instance;
  var audioQa = player?.cacheAudioQa ?? Pref.defaultAudioQa;
  var preferCodecs = Pref.preferCodecs;
  if (PlatformUtils.isMobile || Platform.isLinux) {
    final isWiFi = await ConnectivityUtils.isWiFi;
    if (player?.cacheVideoQa == null) {
      audioQa = isWiFi ? Pref.defaultAudioQa : Pref.defaultAudioQaCellular;
    }
    preferCodecs = isWiFi ? Pref.preferCodecs : Pref.preferCodecsCellular;
  }
  return (audioQa: audioQa, preferCodecs: preferCodecs);
}

/// Starts to load the head of the streams the page will play (BTR only).
/// Does nothing when BTR playback is off.
Future<void> warmStreams(PlayUrlModel data, {required int qn}) async {
  if (!BtrConfig.playback) return;
  final params = await defaultSelectParams();
  final selected = selectStreams(
    data,
    qn: qn,
    audioQa: params.audioQa,
    preferCodecs: params.preferCodecs,
  );
  if (selected == null) return;
  BtrProxy.warm(selected.videoUrl);
  if (selected.audioUrl.isNotEmpty) BtrProxy.warm(selected.audioUrl);
}

/// Opens a CDN connection for the video stream of a prefetched playurl, so
/// the connection is ready when the player starts (BTR only).
Future<void> preconnectStreams(PlayUrlModel data, {required int qn}) async {
  if (!BtrConfig.playback) return;
  final params = await defaultSelectParams();
  final selected = selectStreams(
    data,
    qn: qn,
    audioQa: params.audioQa,
    preferCodecs: params.preferCodecs,
  );
  if (selected == null) return;
  BtrProxy.preconnect(selected.videoUrl);
}
