import 'dart:typed_data';

import 'package:camera/camera.dart';

/// 把 camera 插件给出的图像转成 ML Kit 需要的 **NV21 连续缓冲区**。
///
/// 两条路径：
/// 1) Android + camera_android_camerax：用 ImageFormatGroup.nv21 初始化控制器时，
///    官方说明「流出来的 format 仍是 yuv420，但数据本身已经是 NV21」，
///    此时插件给的是单 plane，直接复用，零拷贝。
/// 2) 其它情况（3 plane 的 YUV420_888）：手工重排成 NV21（Y 平面 + VU 交错）。
Uint8List? toNv21(CameraImage image) {
  final width = image.width;
  final height = image.height;
  if (width <= 0 || height <= 0) return null;

  // ---- 路径 1：已经是 NV21 ----
  if (image.planes.length == 1) {
    final bytes = image.planes.first.bytes;
    final expected = width * height * 3 ~/ 2;
    if (bytes.length >= expected) return bytes;
  }

  // ---- 路径 2：YUV420_888 → NV21 ----
  if (image.planes.length < 3) return null;

  final yPlane = image.planes[0];
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];

  final ySize = width * height;
  final out = Uint8List(ySize * 3 ~/ 2);

  // Y：逐行拷贝，去掉每行末尾的 padding
  var pos = 0;
  for (var row = 0; row < height; row++) {
    final start = row * yPlane.bytesPerRow;
    final end = start + width;
    if (end > yPlane.bytes.length) break;
    out.setRange(pos, pos + width, yPlane.bytes, start);
    pos += width;
  }

  // 色度：NV21 = Y 之后交错存放 V,U (VU VU VU ...)
  final uvRows = height ~/ 2;
  final uvCols = width ~/ 2;
  var uvPos = ySize;
  for (var row = 0; row < uvRows; row++) {
    for (var col = 0; col < uvCols; col++) {
      final vi = row * vPlane.bytesPerRow + col * 2;
      final ui = row * uPlane.bytesPerRow + col * 2;
      final v = (vi >= 0 && vi < vPlane.bytes.length) ? vPlane.bytes[vi] : 128;
      final u = (ui >= 0 && ui < uPlane.bytes.length) ? uPlane.bytes[ui] : 128;
      if (uvPos + 1 >= out.length) break;
      out[uvPos++] = v;
      out[uvPos++] = u;
    }
  }
  return out;
}
