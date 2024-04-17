# Final_Year_Project_app

A Final Year Project of HKMU student

It handle cameraImage and Image and Uint8List of image.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://flutter.dev/docs/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://flutter.dev/docs/cookbook)

For help getting started with Flutter, view our
[online documentation](https://flutter.dev/docs), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Before use

Use "pub get" command for followings:
flutter:
sdk: flutter
pytorch_lite: 4.2.4
image_picker: ^0.8.5+3
path_provider: ^2.0.2
camera: ^0.10.5
image: ^4.0.15
vibration: ^1.8.4

Remind:

pytorch_lite only usable on version 4.2.4 and need update the library code:

Find image_utils.dart in pytorch_lite-4.2.4 in your library path:

Example path : "/.pub-cache/hosted/pub.dev/pytorch_lite-4.2.4/lib/image_utils.dart"

Change function processCameraImage and change variable angel to 0

```static Image? processCameraImage(CameraImage cameraImage) {
Image? image = ImageUtils.convertCameraImage(cameraImage);

    if (Platform.isIOS) {
      // ios, default camera image is portrait view
      // rotate 270 to the view that top is on the left, bottom is on the right
      // image ^4.0.17 error here
      image = copyRotate(image!, angle: 0); // change angel to 0
    }
    if (Platform.isAndroid) {
      // ios, default camera image is portrait view
      // rotate 270 to the view that top is on the left, bottom is on the right
      // image ^4.0.17 error here
      image = copyRotate(image!, angle: 0); // change angel to 0
    }

    return image;
    // processImage(inputImage);
}
```
