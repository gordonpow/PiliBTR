// ignore_for_file: constant_identifier_names

import 'dart:ui';

import 'package:PiliPlus/models/common/sponsor_block/action_type.dart';

enum SegmentType {
  sponsor(
    '贊助/恰飯',
    '贊助',
    '付費推廣、推薦和直接廣告。不是自我推廣或免費提及他們喜歡的商品/創作者/網站/產品。',
    Color(0xFF00d400),
    [
      ActionType.skip,
      ActionType.mute,
      ActionType.full,
    ],
  ),
  selfpromo(
    '無償/自我推廣',
    '推廣',
    '類似於 “贊助廣告” ，但無報酬或是自我推廣。包括有關商品、捐贈的部分或合作者的資訊。',
    Color(0xFFffff00),
    [
      ActionType.skip,
      ActionType.mute,
      ActionType.full,
    ],
  ),
  exclusive_access(
    '獨家訪問/搶先體驗',
    '品牌合作',
    '僅用於對整個影片進行標記。適用於展示UP主免費或獲得補貼後使用的產品、服務或場地的影片。',
    Color(0xFF008a5c),
    [ActionType.full],
  ),
  interaction(
    '三連/互動提醒',
    '三連提醒',
    '影片中間簡短提醒觀眾來一鍵三連或關注。 如果片段較長，或是有具體內容，則應分類為自我推廣。',
    Color(0xFFcc00ff),
    [
      ActionType.skip,
      ActionType.mute,
    ],
  ),
  poi_highlight(
    '精彩時刻/重點',
    '精彩時刻',
    '大部分人都在尋找的空降時間。類似於“封面在12:34”的評論。',
    Color(0xFFff1684),
    [ActionType.poi],
  ),
  intro(
    '過場/開場動畫',
    '開場動畫',
    '沒有實際內容的間隔片段。可以是暫停、靜態幀或重複動畫。不適用於包含內容的過場。',
    Color(0xFF00ffff),
    [
      ActionType.skip,
      ActionType.mute,
    ],
  ),
  outro(
    '鳴謝/結束畫面',
    '片尾',
    '致謝畫面或片尾畫面。不包含內容的結尾。',
    Color(0xFF0202ed),
    [
      ActionType.skip,
      ActionType.mute,
    ],
  ),
  preview(
    '回顧/概要',
    '預覽',
    '展示此影片或同系列影片將出現的畫面集錦，片段中所有內容都將在之後的正片中再次出現。',
    Color(0xFF008fd6),
    [
      ActionType.skip,
      ActionType.mute,
    ],
  ),
  padding(
    '填充內容/前黑/後黑',
    '填充內容',
    '搬運影片片頭片尾的純粹填充內容，如黑屏或無關畫面，與影片主體內容無實際意義和關聯。',
    Color(0xFF222222),
    [ActionType.skip],
  ),
  filler(
    '離題閒聊/玩笑',
    '離題',
    "僅作為填充內容或增添趣味而新增的離題片段，這些內容對理解影片的主要內容並非必需。這不包括提供背景資訊或上下文的片段。這是一個非常激進的分類，適用於當你不想看'娛樂性'內容的時候。",
    Color(0xFF7300FF),
    [
      ActionType.skip,
      ActionType.mute,
    ],
  ),
  music_offtopic(
    '音樂:非音樂部分',
    '非音樂',
    '僅用於音樂影片。此分類只能用於音樂影片中未包括於其他分類的部分。',
    Color(0xFFff9900),
    [ActionType.skip],
  ),
  jumpscare(
    '驚嚇片段',
    '驚嚇',
    '突發大音量、跳臉、恐怖音效及意外驚嚇。',
    Color(0xFFe53935),
    [ActionType.mute],
  ),
  ;

  /// from https://github.com/hanydd/BilibiliSponsorBlock/blob/master/public/_locales/zh_CN/messages.json
  final String title;
  final String shortTitle;
  final String description;
  final Color color;
  final List<ActionType> toActionType;

  const SegmentType(
    this.title,
    this.shortTitle,
    this.description,
    this.color,
    this.toActionType,
  );
}

// List<SegmentType> _actionType2SegmentType(ActionType actionType) {
//   return switch (actionType) {
//     ActionType.skip => [
//         SegmentType.sponsor,
//         SegmentType.selfpromo,
//         SegmentType.interaction,
//         SegmentType.intro,
//         SegmentType.outro,
//         SegmentType.preview,
//         SegmentType.filler,
//       ],
//     ActionType.mute => [
//         SegmentType.sponsor,
//         SegmentType.selfpromo,
//         SegmentType.interaction,
//         SegmentType.intro,
//         SegmentType.outro,
//         SegmentType.preview,
//         SegmentType.music_offtopic,
//         SegmentType.filler,
//       ],
//     ActionType.full => [
//         SegmentType.sponsor,
//         SegmentType.selfpromo,
//         SegmentType.exclusive_access,
//       ],
//     ActionType.poi => [
//         SegmentType.poi_highlight,
//       ],
//   };
// }
