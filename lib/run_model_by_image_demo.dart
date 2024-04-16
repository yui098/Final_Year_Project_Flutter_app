import 'dart:io';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pytorch_lite/pytorch_lite.dart';
import 'package:FYP_demo_app/sorting_list.dart';

class RunModelByImageDemo extends StatefulWidget {
  const RunModelByImageDemo({Key? key}) : super(key: key);

  @override
  _RunModelByImageDemoState createState() => _RunModelByImageDemoState();
}

class _RunModelByImageDemoState extends State<RunModelByImageDemo> {
  ClassificationModel? _imageModel;
  //CustomModel? _customModel;
  late ModelObjectDetection _objectModel;
  late ModelObjectDetection _objectModelYoloV8;
  late ModelObjectDetection _OCRModel;

  String? textToShow;
  String? ocrResult = '';
  List? _prediction;
  File? _image;
  late Uint8List? croppedIMG = null;
  final ImagePicker _picker = ImagePicker();
  bool objectDetection = false;
  List<ResultObjectDetection?> objDetect = [];
  List<ResultObjectDetection?> ocrDetect = [];


  @override
  void initState() {
    super.initState();
    loadModel();
  }

  //load your model
  Future loadModel() async {
    String pathImageModel = "assets/models/model_classification.pt";
    String pathOCRModel = "assets/models/best_tf.torchscript";
    // String pathOCRModel = "assets/models/bus_number_ocr_v8n.torchscript";  // Train By Momo with preprocess
    String pathObjectDetectionModel = "assets/models/yolov5s.torchscript";
    String pathObjectDetectionModelYolov8 = "assets/models/v8n_led_best.torchscript";
    try {
      _imageModel = await PytorchLite.loadClassificationModel(
          pathImageModel, 224, 224, 1000,
          labelPath: "assets/labels/label_classification_imageNet.txt");
      //_customModel = await PytorchLite.loadCustomModel(pathCustomModel);
      _objectModel = await PytorchLite.loadObjectDetectionModel(
          pathObjectDetectionModel, 80, 640, 640,
          labelPath: "assets/labels/labels_objectDetection_Coco.txt");
      _objectModelYoloV8 = await PytorchLite.loadObjectDetectionModel(
          pathObjectDetectionModelYolov8, 2, 640, 640,
          labelPath: "assets/labels/labels_YoloV8Detection_busLed.txt",
          objectDetectionModelType: ObjectDetectionModelType.yolov8);
      _OCRModel = await PytorchLite.loadObjectDetectionModel(
          pathOCRModel, 23, 640, 640,
          labelPath: "assets/labels/labels_YoloV8_ocrN.txt",
          objectDetectionModelType: ObjectDetectionModelType.yolov8);
    } catch (e) {
      if (e is PlatformException) {
        print("only supported for android, Error is $e");
      } else {
        print("Error is $e");
      }
    }
  }

  //run an image model
  Future runObjectDetectionWithoutLabels() async {
    //pick a random image
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    Stopwatch stopwatch = Stopwatch()..start();

    objDetect = await _objectModel
        .getImagePredictionList(await File(image!.path).readAsBytes());
    textToShow = inferenceTimeAsString(stopwatch);

    for (var element in objDetect) {
      print({
        "score": element?.score,
        "className": element?.className,
        "class": element?.classIndex,
        "rect": {
          "left": element?.rect.left,
          "top": element?.rect.top,
          "width": element?.rect.width,
          "height": element?.rect.height,
          "right": element?.rect.right,
          "bottom": element?.rect.bottom,
        },
      });
    }
    setState(() {
      //this.objDetect = objDetect;
      _image = File(image.path);
    });
  }

  Future runObjectDetection() async {
    //pick a random image

    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    Stopwatch stopwatch = Stopwatch()..start();
    objDetect = await _objectModel.getImagePrediction(
        await File(image!.path).readAsBytes(),
        minimumScore: 0.1,
        iOUThreshold: 0.3);
    textToShow = inferenceTimeAsString(stopwatch);
    print('object executed in ${stopwatch.elapsed.inMilliseconds} ms');

    for (var element in objDetect) {
      print({
        "score": element?.score,
        "className": element?.className,
        "class": element?.classIndex,
        "rect": {
          "left": element?.rect.left,
          "top": element?.rect.top,
          "width": element?.rect.width,
          "height": element?.rect.height,
          "right": element?.rect.right,
          "bottom": element?.rect.bottom,
        },
      });
    }
    setState(() {
      //this.objDetect = objDetect;
      _image = File(image.path);
    });
  }

  Future runObjectDetectionYoloV8() async {
    //pick a random image

    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    Stopwatch stopwatch = Stopwatch()..start();

    try{

      objDetect = await _objectModelYoloV8.getImagePrediction(
          await File(image!.path).readAsBytes(),
          minimumScore: 0.3,
          iOUThreshold: 0.3);
      textToShow = inferenceTimeAsString(stopwatch);

      print('object executed in ${stopwatch.elapsed.inMilliseconds} ms');
      for (var element in objDetect) {
        print({
          "score": element?.score,
          "className": element?.className,
          "class": element?.classIndex,
          "rect": {
            "left": element?.rect.left,
            "top": element?.rect.top,
            "width": element?.rect.width,
            "height": element?.rect.height,
            "right": element?.rect.right,
            "bottom": element?.rect.bottom,
          },
        });
        if (element?.className == 'BusLed') {
          ocrResult = await chopFrameAndPrepareOCR(File(image.path).readAsBytes(), element);
        }
      }
      setState(() {
        //this.objDetect = objDetect;
        this.ocrResult = ocrResult;
        _image = File(image.path);
      });
    }catch(e){
      print(e);
    }
  }

  Future runOcrDetectionYoloV8() async {
    //pick a random image

    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    Stopwatch stopwatch = Stopwatch()..start();

    try {
      objDetect = await _OCRModel.getImagePrediction(
          await File(image!.path).readAsBytes(),
          minimumScore: 0.5,
          iOUThreshold: 0.9);

      textToShow = inferenceTimeAsString(stopwatch);

      var resultList = [];

      print('object executed in ${stopwatch.elapsed.inMilliseconds} ms');
      for (var element in objDetect) {
        print({
          "score": element!.score,
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
        resultList.add(ObjectResult(element.rect.left,element.className!));
      }
      resultList.sort((a, b) => a.x_axis.compareTo(b.x_axis));
      print('Sort by x_axis: $resultList');
      ocrResult = resultList.join();
      ocrResult = ocrResult?.replaceAll("'", "");
      print(ocrResult);
      setState(() {
        //this.objDetect = objDetect;
        this.ocrResult = ocrResult;
        _image = File(image.path);
      });
    }catch(e){
      print(e);
    }
  }

  Future<String?> chopFrameAndPrepareOCR(Future<Uint8List> image,ResultObjectDetection? element) async{

    // Crop the image
    final decodedImage = img.decodeImage(await image);

    var factorX = decodedImage!.width;
    var factorY = decodedImage.height;

    print({
      "factorX":factorX,
      "factorY":factorY,
      "Left" : element!.rect.left * factorX,
      "Top" : element.rect.top * factorY,
      "Width" : element.rect.width * factorX,
      "Height" : element.rect.height * factorY
    });

    var cropped = img.copyCrop(
        decodedImage,
        x: (element.rect.left * factorX).toInt(),
        y: (element.rect.top * factorY).toInt(),
        width: (element.rect.width * factorX).toInt(),
        height: (element.rect.height * factorY).toInt());

    print('Start OCR detect');

    croppedIMG = Uint8List.fromList(img.encodePng(cropped));

    ocrDetect = await _OCRModel.getImagePrediction(croppedIMG!,
        minimumScore: 0.25,
        iOUThreshold: 0.2);

    print('OCR Result');

    List<ObjectResult> resultList = [];

    for (var charDetect in ocrDetect){
      print({
        "Num of result" : ocrDetect.length,
        "className" : charDetect!.className,
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
    return ocrResult;
  }

  String inferenceTimeAsString(Stopwatch stopwatch) =>
      "Inference Took ${stopwatch.elapsed.inMilliseconds} ms";

  Future runClassification() async {
    objDetect = [];
    //pick a random image
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    //get prediction
    //labels are 1000 random english words for show purposes
    print(image!.path);
    Stopwatch stopwatch = Stopwatch()..start();

    textToShow = await _imageModel!
        .getImagePrediction(await File(image.path).readAsBytes());
    textToShow = "${textToShow ?? ""}, ${inferenceTimeAsString(stopwatch)}";

    List<double?>? predictionList = await _imageModel!.getImagePredictionList(
      await File(image.path).readAsBytes(),
    );

    print(predictionList);
    // List<double?>? predictionListProbabilities =
    //     await _imageModel!.getImagePredictionListProbabilities(
    //   await File(image.path).readAsBytes(),
    // );
    // //Gettting the highest Probability
    // double maxScoreProbability = double.negativeInfinity;
    // double sumOfProbabilities = 0;
    // int index = 0;
    // for (int i = 0; i < predictionListProbabilities!.length; i++) {
    //   if (predictionListProbabilities[i]! > maxScoreProbability) {
    //     maxScoreProbability = predictionListProbabilities[i]!;
    //     sumOfProbabilities =
    //         sumOfProbabilities + predictionListProbabilities[i]!;
    //     index = i;
    //   }
    // }
    // print(predictionListProbabilities);
    // print(index);
    // print(sumOfProbabilities);
    // print(maxScoreProbability);

    setState(() {
      //this.objDetect = objDetect;
      _image = File(image.path);
    });
  }

/*
  //run a custom model with number inputs
  Future runCustomModel() async {
    _prediction = await _customModel!
        .getPrediction([1, 2, 3, 4], [1, 2, 2], DType.float32);

    setState(() {});
  }
*/
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Run model with Image'),
        ),
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: objDetect.isNotEmpty
                  ? _image == null
                  ? const Text('No image selected.')
                  // : croppedIMG != null
                  // ? Image.memory(croppedIMG!)
                  : _objectModel.renderBoxesOnImage(_image!, objDetect)
                  : _image == null
                  ? const Text('No image selected.')
                  : Image.file(_image!)
            ),
            Center(
              child: Visibility(
                visible: textToShow != null,
                child: Text(
                  "$textToShow",
                  maxLines: 1,
                ),
              ),
            ),
            Center(
              child: Visibility(
                visible: ocrResult != null,
                child: Text(
                  "Detected Character : $ocrResult",
                  maxLines: 1,
                ),
              ),
            ),
            /*
            Center(
              child: TextButton(
                onPressed: runImageModel,
                child: Row(
                  children: [

                    Icon(
                      Icons.add_a_photo,
                      color: Colors.grey,
                    ),
                  ],
                ),
              ),
            ),
            */
            TextButton(
              onPressed: runObjectDetectionYoloV8,
              style: TextButton.styleFrom(
                backgroundColor: Colors.blue,
              ),
              child: const Text(
                "Run object detection YoloV8 with labels",
                style: TextStyle(
                  color: Colors.white,
                ),
              ),
            ),
            TextButton(
              onPressed: runOcrDetectionYoloV8,
              style: TextButton.styleFrom(
                backgroundColor: Colors.blue,
              ),
              child: const Text(
                "Run OCR detection YoloV8 with labels",
                style: TextStyle(
                  color: Colors.white,
                ),
              ),
            ),
            Center(
              child: Visibility(
                visible: _prediction != null,
                child: Text(_prediction != null ? "${_prediction![0]}" : ""),
              ),
            )
          ],
        ),
      ),
    );
  }
}