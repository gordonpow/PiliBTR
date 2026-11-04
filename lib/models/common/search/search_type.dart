// ignore_for_file: constant_identifier_names
import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/models/common/enum_with_label.dart';

enum SearchType implements EnumWithLabel {
  all('綜合', api: Api.searchAll),
  // 番剧：media_bangumi,
  media_bangumi('番劇'),
  // 影视：media_ft
  media_ft('影視'),
  // 直播间及主播：live
  // live,
  // 直播间：live_room
  live_room('直播間'),
  // 主播：live_user
  // live_user,
  // 话题：topic
  // topic,
  // 用户：bili_user
  bili_user('使用者'),
  // 专栏：article
  article('專欄'),
  // 视频：video
  video('影片'),
  ;

  // 相簿：photo
  // photo

  @override
  final String label;
  final String api;
  const SearchType(this.label, {this.api = Api.searchByType});

  static const List<SearchType> actives = [
    .all,
    .media_bangumi,
    .media_ft,
    .live_room,
    .bili_user,
    .article,
  ];
}
