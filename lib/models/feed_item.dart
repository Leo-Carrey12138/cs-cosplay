/// 战报条目：/rooms/{roomId}/feed/{pushId} = { text, ts }
class FeedItem {
  const FeedItem({required this.id, required this.text, required this.ts});

  final String id;
  final String text;
  final int ts;

  static FeedItem? fromSnapshot(String id, Object? value) {
    if (value is! Map) return null;
    final text = value['text'];
    if (text is! String || text.isEmpty) return null;
    return FeedItem(
      id: id,
      text: text,
      ts: (value['ts'] is num) ? (value['ts'] as num).toInt() : 0,
    );
  }
}
