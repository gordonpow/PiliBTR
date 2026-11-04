import 'package:PiliPlus/pages/fav/article/view.dart';
import 'package:PiliPlus/pages/fav/cheese/view.dart';
import 'package:PiliPlus/pages/fav/note/view.dart';
import 'package:PiliPlus/pages/fav/pgc/view.dart';
import 'package:PiliPlus/pages/fav/topic/view.dart';
import 'package:PiliPlus/pages/fav/video/view.dart';
import 'package:material_ui/material_ui.dart';

enum FavTabType {
  video('影片', FavVideoPage()),
  bangumi('追番', FavPgcPage(type: 1)),
  cinema('追劇', FavPgcPage(type: 2)),
  article('專欄', FavArticlePage()),
  note('筆記', FavNotePage()),
  topic('話題', FavTopicPage()),
  cheese('課堂', FavCheesePage()),
  ;

  final String title;
  final Widget page;
  const FavTabType(this.title, this.page);
}
