import 'dart:typed_data';

import 'package:image/image.dart';
import 'package:pytorch_lite/pytorch_lite.dart';

class ObjectResult{
  double x_axis;
  String char;

  ObjectResult(this.x_axis,this.char);

  @override
  String toString() {
    return char;
  }
}

Uint8List convertToUint8List(Image image){
  var convertImg = Uint8List.fromList(encodePng(image));
  return convertImg;
}

Image convertToImage(Uint8List image){
  Image Unit8IMG = decodeImage(image)!;
  return Unit8IMG;
}

Image chopImage(Image image, ResultObjectDetection element){
  var factorX = image.width;
  var factorY = image.height;

  var cropped = copyCrop(
      image,
      x: (element.rect.left * factorX).toInt(),
      y: (element.rect.top * factorY).toInt(),
      width: (element.rect.width * factorX).toInt(),
      height: (element.rect.height * factorY).toInt());

  return cropped;
}
