# TRMatrix – Build Guide

All platform folders (android, ios, windows, linux, macos, web) are already included,
with camera, microphone, notification, media and screen-share permissions set.

## 1. Install
- Flutter SDK 3.24+ (https://docs.flutter.dev/get-started/install)
- Windows: Visual Studio 2022 with "Desktop development with C++"
- Android: Android Studio + SDK
- Linux: `sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libmpv-dev mpv`

## 2. Run
```
cd trmatrix_app
flutter pub get
flutter run -d windows     # or: -d android, -d linux, -d chrome
```

## 3. Release builds
```
flutter build apk --release        # Android -> build/app/outputs/flutter-apk/
flutter build windows --release    # Windows -> build/windows/x64/runner/Release/
flutter build linux --release
```

## 4. Push notifications (optional)
Add your Firebase `google-services.json` to `android/app/` (see README.md).

If something fails, copy the error text and send it back.
