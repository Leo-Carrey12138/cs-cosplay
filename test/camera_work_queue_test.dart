import 'dart:async';

import 'package:cs_cosplay/util/camera_work_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('变焦未结束时不能释放，释放后才能重开相机', () async {
    final queue = CameraWorkQueue();
    final zoomDone = Completer<void>();
    final zoomStarted = Completer<void>();
    final events = <String>[];
    final zoom = queue.run(() async {
      events.add('zoom start');
      zoomStarted.complete();
      await zoomDone.future;
      events.add('zoom end');
    });
    final dispose = queue.run(() async => events.add('dispose'));
    final reopen = queue.run(() async => events.add('reopen'));
    await zoomStarted.future;
    expect(events, ['zoom start']);
    zoomDone.complete();
    await Future.wait([zoom, dispose, reopen]);
    expect(events, ['zoom start', 'zoom end', 'dispose', 'reopen']);
  });

  test('相机 API 失败向调用者报告，后续释放仍会执行', () async {
    final queue = CameraWorkQueue();
    final failed = queue.run(
      () async => throw StateError('camera unavailable'),
    );
    final failureCheck = expectLater(failed, throwsStateError);
    var disposed = false;
    final dispose = queue.run(() async {
      disposed = true;
    });
    await failureCheck;
    await dispose;
    expect(disposed, isTrue);
  });
}
