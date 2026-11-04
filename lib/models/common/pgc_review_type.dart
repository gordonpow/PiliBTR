import 'package:PiliPlus/http/api.dart';

enum PgcReviewType {
  long(label: '長評', api: Api.pgcReviewL),
  short(label: '短評', api: Api.pgcReviewS),
  ;

  final String label;
  final String api;
  const PgcReviewType({
    required this.label,
    required this.api,
  });
}

enum PgcReviewSortType {
  def('預設', 0),
  latest('最新', 1),
  ;

  final int sort;
  final String label;
  const PgcReviewSortType(this.label, this.sort);
}
