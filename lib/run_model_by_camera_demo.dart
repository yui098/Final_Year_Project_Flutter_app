import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pytorch_lite/pytorch_lite.dart';
import 'package:FYP_demo_app/ui/box_widget.dart';
import 'package:vibration/vibration.dart';

import 'ui/camera_view.dart';

/// [RunModelByCameraDemo] stacks [CameraView] and [BoxWidget]s with bottom sheet for stats
class RunModelByCameraDemo extends StatefulWidget {
  const RunModelByCameraDemo({Key? key}) : super(key: key);

  @override
  _RunModelByCameraDemoState createState() => _RunModelByCameraDemoState();
}

class _RunModelByCameraDemoState extends State<RunModelByCameraDemo> {
  TextEditingController? targetInputController = new TextEditingController();
  List<ResultObjectDetection>? results;
  Duration? objectDetectionInferenceTime;
  Duration? ocrDetectionInferenceTime;

  String? classification;
  String? targetRoute;
  String? ocrResult;
  Duration? classificationInferenceTime;

  /// Scaffold Key
  GlobalKey<ScaffoldState> scaffoldKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      targetRoute = await targetInputDialog();
    });
    setState(() {
      targetRoute = targetRoute;
      ocrResult = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          // Camera View
          CameraView(resultsCallback, resultsCallbackClassification),

          // Bounding boxes
          boundingBoxes2(results),

          // Heading
          // Align(
          //   alignment: Alignment.topLeft,
          //   child: Container(
          //     padding: EdgeInsets.only(top: 20),
          //     child: Text(
          //       'Object Detection Flutter',
          //       textAlign: TextAlign.left,
          //       style: TextStyle(
          //         fontSize: 28,
          //         fontWeight: FontWeight.bold,
          //         color: Colors.deepOrangeAccent.withOpacity(0.6),
          //       ),
          //     ),
          //   ),
          // ),

          //Bottom Sheet
          Align(
            alignment: Alignment.bottomCenter,
            child: DraggableScrollableSheet(
              initialChildSize: 0.4,
              minChildSize: 0.1,
              maxChildSize: 0.5,
              builder: (_, ScrollController scrollController) => Container(
                width: double.maxFinite,
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(24.0),
                        topRight: Radius.circular(24.0))),
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.keyboard_arrow_up,
                            size: 48, color: Colors.orange),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            children: [
                              if (classification != null)
                                StatsRow('Classification:', '$classification'),
                              if (classificationInferenceTime != null)
                                StatsRow('Classification Inference time:',
                                    '${classificationInferenceTime?.inMilliseconds} ms'),
                              if (objectDetectionInferenceTime != null)
                                StatsRow('Object Detection Inference time:',
                                    '${objectDetectionInferenceTime?.inMilliseconds} ms'),
                              if (ocrResult != null || ocrResult != 'null' || ocrResult != '')
                                StatsRow('OCR Result:', '$ocrResult'),
                              ElevatedButton(
                                  child: targetRoute == null?const Text("Find New Route"):Text("Current finding Route $targetRoute"),
                                  onPressed: () async {
                                    //弹出对话框并等待其关闭
                                    targetRoute = await targetInputDialog();
                                  }
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }




  /// Returns Stack of bounding boxes
  Widget boundingBoxes2(List<ResultObjectDetection>? results) {
    if (results == null) {
      return Container();
    }
    return Stack(
      children: results.map((e) => BoxWidget(result: e)).toList(),
    );
  }

  void resultsCallback(
      List<ResultObjectDetection> results, Duration inferenceTime, String? ocrReturn) {
    if (!mounted) {
      return;
    }

    if (ocrResult != null && targetRoute != null && ocrResult != 'null' && ocrResult == targetRoute){
      Vibration.vibrate(duration: 5000, amplitude: 512);
      targetFoundDialog(targetRoute!);
      targetRoute = null;
      setState(() {
        targetRoute = null;
      });
    }

    setState(() {
      ocrResult = ocrReturn;
      this.results = results;
      objectDetectionInferenceTime = inferenceTime;
      // for (var element in results) {
      //   print({
      //     "score" : element.score,
      //     "className" : element.className,
      //     "rect": {
      //       "left": element.rect.left,
      //       "top": element.rect.top,
      //       "width": element.rect.width,
      //       "height": element.rect.height,
      //       "right": element.rect.right,
      //       "bottom": element.rect.bottom,
      //     },
      //   });
      // }
    });
  }

  void resultsCallbackClassification(
      String classification, Duration inferenceTime) {
    if (!mounted) {
      return;
    }
    setState(() {
      this.classification = classification;
      classificationInferenceTime = inferenceTime;
    });
  }

  Future<String?> targetInputDialog() {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text("Target Bus Route"),
          content: TextField(
            controller: targetInputController,
            autofocus: true,
            decoration: InputDecoration(hintText: 'Enter The Target Bus Route'),
          ),
          actions: <Widget>[
            TextButton(
            child: Text("SUBMIT"),
            onPressed: () => Navigator.of(context).pop(targetInputController?.text.toUpperCase()), // 关闭对话框
            ),
          ],
        );
      },
    );
  }

  Future targetFoundDialog(String routeNumber) {
    return showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text("$routeNumber Arrived"),
            content: Text('Bus Route $routeNumber is arriving, Please get on very soon.'),
            actions: <Widget>[
              TextButton(
                child: Text("close"),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        }
    );
  }

  @override
  void dispose() {
    targetInputController?.dispose();
    super.dispose();
  }

  // static const BOTTOM_SHEET_RADIUS = Radius.circular(24.0);
  // static const BORDER_RADIUS_BOTTOM_SHEET = BorderRadius.only(
  //     topLeft: BOTTOM_SHEET_RADIUS, topRight: BOTTOM_SHEET_RADIUS);
}

/// Row for one Stats field
class StatsRow extends StatelessWidget {
  final String title;
  final String value;

  const StatsRow(this.title, this.value, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        // mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(value)
        ],
      ),
    );
  }
}
