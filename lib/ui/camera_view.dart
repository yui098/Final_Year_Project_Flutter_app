import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as imglib;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pytorch_lite/pytorch_lite.dart';

import '../sorting_list.dart';
import 'camera_view_singleton.dart';


/// [CameraView] sends each frame for inference
class CameraView extends StatefulWidget {
  /// Callback to pass results after inference to [HomeView]
  final Function(
          List<ResultObjectDetection> recognitions, Duration inferenceTime, String? ocrResult)
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
  String? ocrResult = '';

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
          pathOCRModel, 21, 640, 640,
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
    minimumScore: 0.6,
    iOUThreshold: 0.7,
    );

    // Stop the stopwatch
    stopwatch.stop();

    ocrResult = await chopFrameAndPrepareOCR(cameraImage,objDetect);

      // print("data outputted $objDetect");
      widget.resultsCallback(objDetect, stopwatch.elapsed, ocrResult);
    }
    if (!mounted) {
      return;
    }

    setState(() {
      predictingObjectDetection = false;
    });
  }

  static imglib.Image convertCameraImage(CameraImage cameraImage) {
    if (cameraImage.format.group == ImageFormatGroup.yuv420) {
      return convertYUV420ToImage(cameraImage);
    } else if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
      return convertBGRA8888ToImage(cameraImage);
    } else {
      throw Exception('Undefined image type.');
    }
  }

  ///
  /// Converts a [CameraImage] in BGRA888 format to [image_lib.Image] in RGB format
  ///
  static imglib.Image convertBGRA8888ToImage(CameraImage cameraImage) {
    return imglib.Image.fromBytes(
      width: cameraImage.planes[0].width!,
      height: cameraImage.planes[0].height!,
      bytes: cameraImage.planes[0].bytes.buffer,
      order: imglib.ChannelOrder.bgra,
    );
  }

  ///
  /// Converts a [CameraImage] in YUV420 format to [image_lib.Image] in RGB format
  ///
  static imglib.Image convertYUV420ToImage(CameraImage cameraImage) {
    final imageWidth = cameraImage.width;
    final imageHeight = cameraImage.height;

    final yBuffer = cameraImage.planes[0].bytes;
    final uBuffer = cameraImage.planes[1].bytes;
    final vBuffer = cameraImage.planes[2].bytes;

    final int yRowStride = cameraImage.planes[0].bytesPerRow;
    final int yPixelStride = cameraImage.planes[0].bytesPerPixel!;

    final int uvRowStride = cameraImage.planes[1].bytesPerRow;
    final int uvPixelStride = cameraImage.planes[1].bytesPerPixel!;

    final image = imglib.Image(width: imageWidth, height: imageHeight);

    for (int h = 0; h < imageHeight; h++) {
      int uvh = (h / 2).floor();

      for (int w = 0; w < imageWidth; w++) {
        int uvw = (w / 2).floor();

        final yIndex = (h * yRowStride) + (w * yPixelStride);

        // Y plane should have positive values belonging to [0...255]
        final int y = yBuffer[yIndex];

        // U/V Values are subsampled i.e. each pixel in U/V chanel in a
        // YUV_420 image act as chroma value for 4 neighbouring pixels
        final int uvIndex = (uvh * uvRowStride) + (uvw * uvPixelStride);

        // U/V values ideally fall under [-0.5, 0.5] range. To fit them into
        // [0, 255] range they are scaled up and centered to 128.
        // Operation below brings U/V values to [-128, 127].
        final int u = uBuffer[uvIndex];
        final int v = vBuffer[uvIndex];

        // Compute RGB values per formula above.
        int r = (y + v * 1436 / 1024 - 179).round();
        int g = (y - u * 46549 / 131072 + 44 - v * 93604 / 131072 + 91).round();
        int b = (y + u * 1814 / 1024 - 227).round();

        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);

        image.setPixelRgb(w, h, r, g, b);
      }
    }

    return image;
  }

  Future<String?> chopFrameAndPrepareOCR(CameraImage cameraImage,List<ResultObjectDetection> results) async{
    print('Start OCR');

    var image = convertCameraImage(cameraImage);

    var factorX = image.width;
    var factorY = image.height;

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
      if (element.className == 'BusLed') {
        var cropped = imglib.copyCrop(
            image,
            x: (element.rect.left * factorX).toInt(),
            y: (element.rect.top * factorY).toInt(),
            width: (element.rect.width * factorX).toInt(),
            height: (element.rect.height * factorY).toInt());

        print('Start OCR detect');

        var croppedIMG = Uint8List.fromList(imglib.encodePng(cropped));

        ocrDetect = await _OCRModel.getImagePrediction(croppedIMG,
            minimumScore: 0.3,
            iOUThreshold: 0.5);

        print('OCR Result');
        var resultList = [];

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
          resultList.add(ObjectResult(charDetect.rect.left,charDetect.className!));
        }
        resultList.sort((a, b) => a.x_axis.compareTo(b.x_axis));
        ocrResult = resultList.join();
        ocrResult = ocrResult?.replaceAll("'", "");
        }
      }
    return ocrResult;
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
    // var image = convertCameraImage(cameraImage);

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
