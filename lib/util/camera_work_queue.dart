/// 相机原生调用的串行队列。一次失败不会阻断之后的释放或重新初始化。
class CameraWorkQueue {
  Future<void> _tail = Future<void>.value();

  Future<void> run(Future<void> Function() action) {
    final operation = _tail.then((_) => action());
    _tail = operation.catchError((Object _) {});
    return operation;
  }
}
