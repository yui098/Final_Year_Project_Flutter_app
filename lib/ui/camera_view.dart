import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as imglib;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pytorch_lite/pytorch_lite.dart';
import 'package:pytorch_lite/image_utils.dart' as img_util;

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

  ModelObjectDetection? _busLedDisplayModel;
  late ModelObjectDetection _ocrModel;
  ClassificationModel? _imageModel;

  List<ResultObjectDetection> ocrDetect = [];
  String? ocrResult = '';

  bool classification = false;
  int _camFrameRotation = 0;
  String errorMessage = "";
  Uint8List? croppedIMG = null;

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

    try {
      _imageModel = await PytorchLite.loadClassificationModel(
          pathImageModel, 224, 224, 1000,
          labelPath: "assets/labels/label_classification_imageNet.txt");
      _ocrModel = await PytorchLite.loadObjectDetectionModel(
          pathOCRModel, 21, 640, 640,
          labelPath: "assets/labels/labels_YoloV8Detection_character.txt",
          objectDetectionModelType: ObjectDetectionModelType.yolov8);
      _busLedDisplayModel = await PytorchLite.loadObjectDetectionModel(
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
    if (croppedIMG == null ||cameraController == null || !cameraController!.value.isInitialized) {
      return Container();
    }

    return CameraPreview(cameraController!);
    // return cameraController!.buildPreview();

    //return Center(child: Image.memory(croppedIMG!));

    // return AspectRatio(
    //     aspectRatio: cameraController!.value.aspectRatio,
    //     child: CameraPreview(cameraController!));
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

    if (_busLedDisplayModel != null) {
    // Start the stopwatch
    Stopwatch stopwatch = Stopwatch()..start();

    var image = img_util.ImageUtils.processCameraImage(cameraImage)!;

    image = imglib.copyRotate(image, angle: 0);

    List<ResultObjectDetection> objDetect =
    await _busLedDisplayModel!.getImagePrediction(
      convertToUint8List(image),
    minimumScore: 0.5,
    iOUThreshold: 0.3,
    );

    // Stop the stopwatch
    stopwatch.stop();

    ocrResult = await chopFrameAndPrepareOCR(image,objDetect);

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

  Future<String?> chopFrameAndPrepareOCR(imglib.Image image,List<ResultObjectDetection> results) async{

    var resultList = [];

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

      if (element.classIndex == 0) {

      croppedIMG = convertToUint8List(chopImage(image, element));

      setState(() {
        croppedIMG = croppedIMG;
      });

        ocrDetect = await _ocrModel.getImagePrediction(
          croppedIMG!,
          minimumScore: 0.5,
          iOUThreshold: 0.1,
        );

        print({'Number of Ocr result': ocrDetect.length});

        for (var charDetect in ocrDetect) {
          print({
            "className": charDetect.className,
            "score": charDetect.score,
            "rect": {
              "left": charDetect.rect.left,
              "top": charDetect.rect.top,
              "width": charDetect.rect.width,
              "height": charDetect.rect.height,
              "right": charDetect.rect.right,
              "bottom": charDetect.rect.bottom,
            }
          });
          resultList.add(ObjectResult(charDetect.rect.left, charDetect.className!));
        }
      }
      resultList.sort((a, b) => a.x_axis.compareTo(b.x_axis));
      ocrResult = resultList.join();
      ocrResult = ocrResult?.replaceAll("'", "");
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
