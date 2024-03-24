import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pytorch_lite/pytorch_lite.dart';

import 'camera_view_singleton.dart';


/// [CameraView] sends each frame for inference
class CameraView extends StatefulWidget {
  /// Callback to pass results after inference to [HomeView]
  final Function(
          List<ResultObjectDetection> recognitions, Duration inferenceTime)
      resultsCallback;
  final Function(String classification, Duration inferenceTime)
      resultsCallbackClassification;

  /// Constructor
  const CameraView(this.resultsCallback, this.resultsCallbackClassification,
      {Key? key}) : super(key: key);
  @override
  _CameraViewState createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> with WidgetsBindingObserver {
  /// List of available cameras
  late List<CameraDescription> cameras;

  /// Controller
  CameraController? cameraController;

  /// true when inference is ongoing
  bool predicting = false;

  /// true when inference is ongoing
  bool predictingObjectDetection = false;

  ModelObjectDetection? _BusLedDisplayModel;
  late ModelObjectDetection _OCRModel;
  ClassificationModel? _imageModel;

  List<ResultObjectDetection> ocrDetect = [];

  bool classification = false;
  int _camFrameRotation = 0;
  String errorMessage = "";
  @override
  void initState() {
    super.initState();
    initStateAsync();
  }

  //load your model
  Future loadModel() async {
    String pathImageModel = "assets/models/model_classification.pt";
    String pathOCRModel = "assets/models/v8n_char_best.torchscript";
    String pathObjectDetectionModel = "assets/models/v8n_led_best.torchscript";
    print("Using CPU Model");
    try {
      _imageModel = await PytorchLite.loadClassificationModel(
          pathImageModel, 224, 224, 1000,
          labelPath: "assets/labels/label_classification_imageNet.txt");
      _OCRModel = await PytorchLite.loadObjectDetectionModel(
          pathOCRModel, 23, 640, 640,
          labelPath: "assets/labels/labels_YoloV8Detection_character.txt",
          objectDetectionModelType: ObjectDetectionModelType.yolov8);
      _BusLedDisplayModel = await PytorchLite.loadObjectDetectionModel(
          pathObjectDetectionModel, 2, 640, 640,
          labelPath: "assets/labels/labels_YoloV8Detection_busLed.txt",
          objectDetectionModelType: ObjectDetectionModelType.yolov8);
    } catch (e) {
      if (e is PlatformException) {
        print("only supported for android, Error is $e");
      } else {
        print("Error is $e");
      }
    }
  }

  void initStateAsync() async {
    WidgetsBinding.instance.addObserver(this);
    await loadModel();

    // Camera initialization
    try {
      initializeCamera();
    } on CameraException catch (e) {
      switch (e.code) {
        case 'CameraAccessDenied':
          errorMessage = ('You have denied camera access.');
          break;
        case 'CameraAccessDeniedWithoutPrompt':
          // iOS only
          errorMessage = ('Please go to Settings app to enable camera access.');
          break;
        case 'CameraAccessRestricted':
          // iOS only
          errorMessage = ('Camera access is restricted.');
          break;
        case 'AudioAccessDenied':
          errorMessage = ('You have denied audio access.');
          break;
        case 'AudioAccessDeniedWithoutPrompt':
          // iOS only
          errorMessage = ('Please go to Settings app to enable audio access.');
          break;
        case 'AudioAccessRestricted':
          // iOS only
          errorMessage = ('Audio access is restricted.');
          break;
        default:
          errorMessage = (e.toString());
          break;
      }
      setState(() {});
    }
    // Initially predicting = false
    setState(() {
      predicting = false;
    });
  }

  /// Initializes the camera by setting [cameraController]
  void initializeCamera() async {
    cameras = await availableCameras();

    var idx =
        cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
    if (idx < 0) {
      log("No Back camera found - weird");
      return;
    }

    var desc = cameras[idx];
    _camFrameRotation = Platform.isAndroid ? desc.sensorOrientation : 0;
    // cameras[0] for rear-camera
    cameraController = CameraController(desc, ResolutionPreset.medium,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
        enableAudio: false);

    cameraController?.initialize().then((_) async {
      // Stream of image passed to [onLatestImageAvailable] callback
      await cameraController?.startImageStream(onLatestImageAvailable);

      /// previewSize is size of each image frame captured by controller
      ///
      /// 352x288 on iOS, 240p (320x240) on Android with ResolutionPreset.low
      Size? previewSize = cameraController?.value.previewSize;

      /// previewSize is size of raw input image to the model
      CameraViewSingleton.inputImageSize = previewSize!;

      // the display width of image on screen is
      // same as screenWidth while maintaining the aspectRatio
      Size screenSize = MediaQuery.of(context).size;
      CameraViewSingleton.screenSize = screenSize;
      CameraViewSingleton.ratio = cameraController!.value.aspectRatio;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Return empty container while the camera is not initialized
    if (cameraController == null || !cameraController!.value.isInitialized) {
      return Container();
    }

    return CameraPreview(cameraController!);
    //return cameraController!.buildPreview();

    // return AspectRatio(
    //     // aspectRatio: cameraController.value.aspectRatio,
    //     child: CameraPreview(cameraController));
  }

  runClassification(CameraImage cameraImage) async {
    if (predicting) {
      return;
    }
    if (!mounted) {
      return;
    }

    setState(() {
      predicting = true;
    });
    if (_imageModel != null) {
      // Start the stopwatch
      Stopwatch stopwatch = Stopwatch()..start();

      String imageClassification = await _imageModel!
          .getCameraImagePrediction(cameraImage, _camFrameRotation);
      // Stop the stopwatch
      stopwatch.stop();
      // print("imageClassification $imageClassification");
      widget.resultsCallbackClassification(
          imageClassification, stopwatch.elapsed);
    }
    if (!mounted) {
      return;
    }

    setState(() {
      predicting = false;
    });
  }

  Future<void> runObjectDetection(CameraImage cameraImage) async {
    if (predictingObjectDetection) {
      return;
    }
    if (!mounted) {
      return;
    }

    setState(() {
      predictingObjectDetection = true;
    });
    if (_BusLedDisplayModel != null) {
      // Start the stopwatch
      Stopwatch stopwatch = Stopwatch()..start();

      List<ResultObjectDetection> objDetect =
          await _BusLedDisplayModel!.getCameraImagePrediction(
        cameraImage,
        _camFrameRotation,
        minimumScore: 0.3,
        iOUThreshold: 0.3,
      );

      // Stop the stopwatch
      stopwatch.stop();

      ocrDetect = chopFrameAndPrepareOCR(cameraImage,objDetect) as List<ResultObjectDetection>;
      // print("data outputted $objDetect");
      widget.resultsCallback(objDetect, stopwatch.elapsed);
    }
    if (!mounted) {
      return;
    }

    setState(() {
      predictingObjectDetection = false;
    });
  }

  Future<ui.Image> createImage(
      Uint8List buffer, int width, int height, ui.PixelFormat pixelFormat) {
    final Completer<ui.Image> completer = Completer();

    ui.decodeImageFromPixels(buffer, width, height, pixelFormat, (ui.Image img) {
      completer.complete(img);
    });

    return completer.future;
  }

  Uint8List yuv420ToRgba8888(List<Uint8List> planes, int width, int height) {
    final yPlane = planes[0];
    final uPlane = planes[1];
    final vPlane = planes[2];

    final Uint8List rgbaBytes = Uint8List(width * height * 4);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int yIndex = y * width + x;
        final int uvIndex = (y ~/ 2) * (width ~/ 2) + (x ~/ 2);

        final int yValue = yPlane[yIndex] & 0xFF;
        final int uValue = uPlane[uvIndex] & 0xFF;
        final int vValue = vPlane[uvIndex] & 0xFF;

        final int r = (yValue + 1.13983 * (vValue - 128)).round().clamp(0, 255);
        final int g =
        (yValue - 0.39465 * (uValue - 128) - 0.58060 * (vValue - 128))
            .round()
            .clamp(0, 255);
        final int b = (yValue + 2.03211 * (uValue - 128)).round().clamp(0, 255);

        final int rgbaIndex = yIndex * 4;
        rgbaBytes[rgbaIndex] = r.toUnsigned(8);
        rgbaBytes[rgbaIndex + 1] = g.toUnsigned(8);
        rgbaBytes[rgbaIndex + 2] = b.toUnsigned(8);
        rgbaBytes[rgbaIndex + 3] = 255; // Alpha value
      }
    }

    return rgbaBytes;
  }

  Future<ui.Image?> ProcessImage(CameraImage availableImage,List<Uint8List> planes) async{
    print('into ProcessImage');
    if(Platform.isIOS){
      print('Device is IOS');
      ui.Image uiimage = await createImage(availableImage.planes[0].bytes,
          availableImage.width, availableImage.height, ui.PixelFormat.rgba8888);
      return uiimage;
    }else if (Platform.isAndroid){
      print('Device is Android');
      // Convert the YUV420 data to a jpeg image.
      Uint8List data = yuv420ToRgba8888(planes, availableImage.width, availableImage.height);
      ui.Image uiimage = await createImage(data, availableImage.width, availableImage.height,
          ui.PixelFormat.rgba8888);
      return uiimage;
    }
    return null;
  }

  Future<List<ResultObjectDetection>?> chopFrameAndPrepareOCR(CameraImage cameraImage,List<ResultObjectDetection> results) async{
    print('Start OCR');

    List<Uint8List> planes = [];
    for (int planeIndex = 0; planeIndex < 3; planeIndex++) {
      Uint8List buffer;
      int width;
      int height;
      if (planeIndex == 0) {
        width = cameraImage.width;
        height = cameraImage.height;
      } else {
        width = cameraImage.width ~/ 2;
        height = cameraImage.height ~/ 2;
      }

      buffer = Uint8List(width * height);

      int pixelStride = cameraImage.planes[planeIndex].bytesPerPixel!;
      int rowStride = cameraImage.planes[planeIndex].bytesPerRow;

      int index = 0;
      for (int i = 0; i < height; i++) {
        for (int j = 0; j < width; j++) {
          buffer[index++] = cameraImage
              .planes[planeIndex].bytes[i * rowStride + j * pixelStride];
        }
      }
      planes.add(buffer);
    }

    try{
      print('camera image to UI image');
      ui.Image uiimage = ProcessImage(cameraImage,planes) as ui.Image;
      final pngBytes = await uiimage.toByteData(format: ImageByteFormat.png);
      img.Image image = Image.memory(Uint8List.view(pngBytes!.buffer)) as img.Image;

      for (var element in results) {
        print({
          "score": element.score,
          "className": element.className,
          "class": element.classIndex,
          "rect": {
            "left": element.rect.left,
            "top": element.rect.top,
            "width": element.rect.width,
            "height": element.rect.height,
            "right": element.rect.right,
            "bottom": element.rect.bottom,
          },
        });
        // Crop the image
        print('chop  image');
        img.Image cropped = img.copyCrop(
            image,
            x: element.rect.left.toInt(),
            y: element.rect.top.toInt(),
            width: element.rect.width.toInt(),
            height: element.rect.height.toInt());

        ocrDetect = await _OCRModel.getImagePrediction(cropped.toUint8List(),
            minimumScore: 0.1,
            iOUThreshold: 0.3);

        print('OCR Result');



        for (var charDetect in ocrDetect){

          print({
            "className" : charDetect.className,
            "score" : charDetect.score,
            "rect": {
              "left": charDetect.rect.left,
              "top": charDetect.rect.top,
              "width": charDetect.rect.width,
              "height": charDetect.rect.height,
              "right": charDetect.rect.right,
              "bottom": charDetect.rect.bottom,
            }
          });
          return ocrDetect;
        }
      }
    }catch(e){
      print(e.toString());
    }






    return [];
  }

  /// Callback to receive each frame [CameraImage] perform inference on it
  onLatestImageAvailable(CameraImage cameraImage) async {
    // Make sure we are still mounted, the background thread can return a response after we navigate away from this
    // screen but before bg thread is killed
    if (!mounted) {
      return;
    }

    // log("will start prediction");
    // log("Converted camera image");

    //runClassification(cameraImage);
    runObjectDetection(cameraImage);

    // log("done prediction camera image");
    // Make sure we are still mounted, the background thread can return a response
    // after we navigate away from this screen but before bg thread is killed
    if (!mounted) {
      return;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (!mounted) {
      return;
    }
    switch (state) {
      case AppLifecycleState.paused:
        cameraController?.stopImageStream();
        break;
      case AppLifecycleState.resumed:
        if (!cameraController!.value.isStreamingImages) {
          await cameraController?.startImageStream(onLatestImageAvailable);
        }
        break;
      default:
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    cameraController?.dispose();
    super.dispose();
  }
}
