# تثبيت Flutter SDK على Windows + Android Studio

نعم، يجب تثبيت Flutter SDK نفسه. تثبيت Flutter Plugin داخل Android Studio وحده لا يكفي.

## 1) المتطلبات

- Git for Windows
- Android Studio (نسخة مستقرة حديثة)
- Flutter SDK Stable

## 2) تثبيت Flutter SDK

نزّل Flutter SDK Stable من الموقع الرسمي، ثم فك الضغط في مسار بسيط لا يحتاج صلاحيات Administrator، مثال:

`C:\src\flutter`

تجنب وضعه داخل `Program Files` أو داخل مجلدات لها مسافات/صلاحيات خاصة.

## 3) إضافة Flutter إلى PATH

أضف هذا المسار إلى متغير Path للمستخدم:

`C:\src\flutter\bin`

ثم أغلق Terminal وافتحه من جديد، ونفّذ:

`flutter --version`

## 4) إعداد Android Studio

من Settings > Plugins ثبّت Flutter Plugin (وسيطلب Dart Plugin إن لزم).

من Tools > SDK Manager تأكد من تثبيت Android SDK Platform الحديثة، Android SDK Build-Tools، Android SDK Command-line Tools، Android Emulator، وAndroid SDK Platform-Tools.

## 5) قبول رخص Android

افتح PowerShell أو CMD:

`flutter doctor --android-licenses`

وافق على الرخص المطلوبة، ثم:

`flutter doctor`

الهدف أن يكون Android toolchain وAndroid Studio بعلامة نجاح.

## 6) تشغيل World Dominion

من داخل مجلد المشروع:

`flutter pub get`

`flutter analyze`

`flutter run`

## 7) إخراج APK

`flutter build apk --release`

المسار المعتاد:

`build\app\outputs\flutter-apk\app-release.apk`

## إذا قال flutter غير معروف

المشكلة غالباً PATH. تحقق أن `C:\src\flutter\bin` موجود في Path، ثم افتح Terminal جديداً.

## إذا قال cmdline-tools missing

من Android Studio > Tools > SDK Manager > SDK Tools، ثبّت Android SDK Command-line Tools ثم أعد `flutter doctor`.
