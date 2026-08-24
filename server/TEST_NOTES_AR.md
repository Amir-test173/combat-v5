# Test notes — v1.8 Clean Build & Mode Parity

## Server
`npm run check` محليًا: **32/32 passed**.

يشمل كل اختبارات v1.7 السابقة إضافة إلى اختبار Mode Parity الذي يقارن السيرفر بالعقد المشترك، بما فيه attack plan power/cost، خسائر المعركة، تقدم الجبهة والحركة الفيزيائية.

## Clean Source Gate
`python tool/check_clean_source.py` يرفض رجوع الأخطاء المعروفة في تقرير البناء، ومنها Dart `?.<decimal>`, `withOpacity`, StrategicSite `name=`, switch بلا default، pins Android الخاطئة، CI الذي يرقع المصدر أو يعمل commit، Protocol/Ruleset غير متطابق، وCRLF في ملفات المصدر.

## Python transport pipeline
`cd tool && python -m unittest -v test_transport_pipeline.py`: **4/4 passed** محليًا.

## Flutter
Flutter SDK غير مثبت في بيئة ChatGPT الحالية، لذلك لم يتم الادعاء بأن الأوامر التالية نجحت محليًا:

```text
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

GitHub Actions يشغلها حرفيًا على Flutter 3.47.1. نجاح Workflow الأخضر هو معيار القبول الحقيقي للبناء.
