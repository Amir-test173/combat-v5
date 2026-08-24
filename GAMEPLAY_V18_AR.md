# World Dominion v1.8 — Clean Build & Mode Parity

الإصدار: **1.8.0 Clean Build & Mode Parity / Protocol 9 / Ruleset 1.8.0-parity-1**.

## الهدف
v1.8 إصدار تثبيت هندسي فوق v1.7 Physical World. لا يزيل أي نظام Gameplay سابق؛ يركز على أن يعمل المصدر نفسه بشكل نظيف في Flutter/GitHub وأن تبقى القواعد الحساسة متطابقة بين اللعب الفردي والأونلاين.

## Offline وOnline
- **Offline:** نفس أنظمة الاقتصاد، المحافظات، الجبهات، الجغرافيا الفيزيائية، البحر، الطيران، الصواريخ والإمداد تعمل محليًا ضد AI، والحفظ محلي.
- **Online:** نفس القواعد الأساسية، لكن السيرفر Authoritative هو الذي يصدق الأوامر والحسابات الحساسة ويطبق Fog of War والمزامنة ومهلة الدور وإعادة الاتصال.
- النتيجة العشوائية لا يلزم أن تكون مطابقة حرفيًا بين مباراتين منفصلتين؛ المطلوب هو تطابق القوانين والمعاملات، لا تطابق بذرة RNG.

## Mode parity contract
أضيف `mode_parity_contract.json` للعميل والسيرفر ويحتوي متجهات مرجعية للقواعد الحرجة، منها:
- قوة وكلفة خطط الهجوم حذر/متوازن/اختراق.
- شدة خسائر جولة المعركة.
- تقدم الجبهة والتطويق والتفوق الجوي/البحري.
- مثال مرجعي لتكلفة الحركة الفيزيائية.

اختبارات Flutter تقارن منطق Offline بالعقد، واختبارات Node تقارن منطق السيرفر بالعقد نفسه. كما يرفض Protocol 9 اتصال عميل يحمل Ruleset مختلفًا.

## إصلاحات البناء المثبتة في المصدر
- إصلاح تعبيرات Dart ternary الخاطئة من نوع `?.86` إلى `?0.86`.
- إصلاح `StrategicSite` named parameters لاستخدام `name:` ونظرائها.
- إضافة `_=>` للـString switch الذي يحتاج default.
- تثبيت تحويلات `num`/`int` في نقاط deserialization والـmin/max الحساسة.
- استيراد `SMapWorld` صراحة من world map package.
- استبدال `withOpacity` بـ`withValues(alpha: ...)` في المصدر.
- Android: AGP 8.11.1، Kotlin 2.2.20، Java 17، compileSdk/targetSdk 36، Gradle 8.14.3.
- `.gitattributes` يثبت LF لملفات المصدر وCRLF فقط لملفات Windows scripts.

## CI
GitHub Actions لا يصلح `lib/main.dart` ولا `android/settings.gradle` ولا يعمل commit/push. لديه Clean Source Gate قبل البناء، ثم server tests، ثم بيانات العالم، ثم:

```text
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

ملاحظة: حزمة المشروع الحالية لا تتضمن binary `gradle-wrapper.jar`؛ Workflow يعيد فقط هذا الملف القياسي من scaffold Flutter مؤقت إذا كان غير موجود. هذه ليست عملية تعديل كود، لكن الهدف المستقبلي الأفضل هو تضمين wrapper binary القياسي في المستودع نفسه.

## الحفاظ
كل أنظمة v1.7 وما قبلها باقية. راجع `PRESERVATION_V18_AR.md`.
