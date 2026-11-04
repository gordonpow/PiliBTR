import 'package:PiliPlus/models_new/live/live_feed_index/card_data_list_item.dart';

class CardDataItem {
  final List<CardLiveItem>? list;
  final ExtraInfo? extraInfo;

  const CardDataItem({
    this.list,
    this.extraInfo,
  });

  factory CardDataItem.fromJson(Map<String, dynamic> json) => CardDataItem(
    list: (json['list'] as List<dynamic>?)
        ?.map((e) => CardLiveItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    extraInfo: json['extra_info'] == null
        ? null
        : ExtraInfo.fromJson(json['extra_info'] as Map<String, dynamic>),
  );

  static const kAreaEntrance = CardDataItem(
    list: [
      CardLiveItem(
        areaV2Id: 0,
        areaV2ParentId: 0,
        title: '人氣',
      ),
      CardLiveItem(
        areaV2Id: 0,
        areaV2ParentId: 9,
        title: '虛擬主播',
      ),
      CardLiveItem(
        areaV2Id: 0,
        areaV2ParentId: 14,
        title: '聊天室',
      ),
      CardLiveItem(
        areaV2Id: 145,
        areaV2ParentId: 1,
        title: '顏值',
      ),
      CardLiveItem(
        areaV2Id: 0,
        areaV2ParentId: 1,
        title: '娛樂',
      ),
      CardLiveItem(
        areaV2Id: 86,
        areaV2ParentId: 2,
        title: '英雄聯盟',
      ),
      CardLiveItem(
        areaV2Id: 35,
        areaV2ParentId: 3,
        title: '王者榮耀',
      ),
      CardLiveItem(
        areaV2Id: 0,
        areaV2ParentId: 5,
        title: '電臺',
      ),
      CardLiveItem(
        areaV2Id: 89,
        areaV2ParentId: 2,
        title: 'CS2',
      ),
      CardLiveItem(
        areaV2Id: 0,
        areaV2ParentId: 15,
        title: '互動玩法',
      ),
      CardLiveItem(
        areaV2Id: 0,
        areaV2ParentId: 6,
        title: '單機遊戲',
      ),
      CardLiveItem(
        areaV2Id: 21,
        areaV2ParentId: 1,
        title: '影片唱見',
      ),
      CardLiveItem(
        areaV2Id: 301000,
        areaV2ParentId: 301,
        title: '幫我玩',
      ),
      CardLiveItem(
        areaV2Id: 1013,
        areaV2ParentId: 1,
        title: '團播',
      ),
    ],
  );
}

class ExtraInfo {
  int? totalCount;

  ExtraInfo.fromJson(Map<String, dynamic> json) {
    totalCount = json['total_count'];
  }
}
