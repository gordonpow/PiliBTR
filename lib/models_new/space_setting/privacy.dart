class SpaceSettingModel {
  SpaceSettingModel({
    required this.name,
    required this.key,
    required this.value,
    this.isReverse = false,
  });

  String name;
  String key;
  int? value;
  bool isReverse;

  bool get boolVal => isReverse ? value == 0 : value == 1;
}

class Privacy {
  List<SpaceSettingModel> list1;
  List<SpaceSettingModel> list2;
  List<SpaceSettingModel> list3;

  Privacy({
    required this.list1,
    required this.list2,
    required this.list3,
  });

  factory Privacy.fromJson(Map<String, dynamic> json) => Privacy(
    list1: [
      SpaceSettingModel(
        name: '公開我的收藏',
        key: 'fav_video',
        value: json['fav_video'],
      ),
      SpaceSettingModel(
        name: '公開我的追番追劇',
        key: 'bangumi',
        value: json['bangumi'],
      ),
      SpaceSettingModel(
        name: '公開我的追漫',
        key: 'comic',
        value: json['comic'],
      ),
      SpaceSettingModel(
        name: '公開最近投幣的影片',
        key: 'coins_video',
        value: json['coins_video'],
      ),
      SpaceSettingModel(
        name: '公開最近點讚的影片',
        key: 'likes_video',
        value: json['likes_video'],
      ),
      SpaceSettingModel(
        name: '公開最近玩過的遊戲',
        key: 'played_game',
        value: json['played_game'],
      ),
      SpaceSettingModel(
        name: '公開擁有的粉絲裝扮',
        key: 'dress_up',
        value: json['dress_up'],
      ),
      SpaceSettingModel(
        name: '公開我的關注列表',
        key: 'disable_following',
        value: json['disable_following'],
        isReverse: true,
      ),
      SpaceSettingModel(
        name: '公開我的粉絲列表',
        key: 'disable_show_fans',
        value: json['disable_show_fans'],
        isReverse: true,
      ),
    ],
    list2: [
      SpaceSettingModel(
        name: '公開佩戴的粉絲勳章',
        key: 'close_space_medal',
        value: json['close_space_medal'],
        isReverse: true,
      ),
      SpaceSettingModel(
        name: '勳章牆公開顯示所有粉絲勳章',
        key: 'only_show_wearing',
        value: json['only_show_wearing'],
        isReverse: true,
      ),
      SpaceSettingModel(
        name: '公開學校資訊',
        key: 'disable_show_school',
        value: json['disable_show_school'],
        isReverse: true,
      ),
    ],
    list3: [
      SpaceSettingModel(
        name: '投稿影片列表中展現直播回放',
        key: 'live_playback',
        value: json['live_playback'],
      ),
      SpaceSettingModel(
        name: '投稿影片列表中展現包月充電專屬影片',
        key: 'charge_video',
        value: json['charge_video'],
      ),
      SpaceSettingModel(
        name: '投稿影片列表中展現課堂影片',
        key: 'lesson_video',
        value: json['lesson_video'],
      ),
    ],
  );
}
