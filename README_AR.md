# World Dominion v1.8.1 Clean Build & Mode Parity Hotfix

الإصدار: **v1.8.1 / Protocol 9 / Ruleset 1.8.0-parity-1**.

v1.8 يبني فوق v1.7 Physical World دون إزالة أنظمة اللعب. الأولوية في هذا الإصدار هي تثبيت المصدر ليبنى نظيفًا، ومنع انجراف قواعد اللعب بين Offline وOnline.

## هل Offline يختلف عن Online؟
القواعد الأساسية المقصودة واحدة: الاقتصاد، المحافظات، القتال، الإمداد، التضاريس، الطرق، البحر، الطيران والصواريخ. الفرق التشغيلي:
- Offline يحسب اللعبة محليًا ضد AI ولا يحتاج سيرفرًا.
- Online يستخدم سيرفرًا Authoritative لمنع الغش ومزامنة البشر وFog of War والـLobby والمهلة والاستعادة.
- لا نتوقع نفس أرقام RNG بين مباراتين منفصلتين، لكن المعاملات والقوانين الحرجة لها Parity Contract مشترك واختبارات على الطرفين.

## GitHub — ما الذي ترفعه؟
فك ضغط حزمة Flutter وارفع **محتويات المجلد كلها** إلى جذر Repository، بحيث يظهر `pubspec.yaml` مباشرة في الجذر.

Workflow الرئيسي: **Build World Dominion Clean Build & Parity**.

البيئة المثبتة:
- Flutter 3.47.1
- Java 17
- Android Gradle Plugin 8.11.1
- Kotlin 2.2.20
- Gradle 8.14.3
- compileSdk 36 / targetSdk 36

## ماذا يفعل CI؟
1. Clean Source Gate — يتأكد أن إصلاحات مشاكل البناء موجودة في المصدر ولا توجد auto-repair/commit.
2. `npm run check` للسيرفر.
3. توليد بيانات العالم والجغرافيا الفيزيائية والنقل الحقيقي مع Quality Gates.
4. اختبار السيرفر مرة ثانية على بيانات العالم المولدة.
5. `flutter pub get`.
6. `flutter analyze`.
7. `flutter test`.
8. `flutter build apk --release`.
9. رفع APK وServer bundle يحملان نفس بيانات العالم.

## اللعب الفردي
بعد تثبيت APK، اللعب ضد AI يعمل دون سيرفر. بيانات العالم التي بُنيت داخل APK متاحة محليًا.

## اللعب الأونلاين
استخدم تطبيق **v1.8 / Protocol 9 / Ruleset 1.8.0-parity-1** مع سيرفر مطابق فقط. السيرفر يرفض Protocol أو Ruleset غير المتوافق.

راجع `GAMEPLAY_V18_AR.md`, `PRESERVATION_V18_AR.md`, `DATA_SOURCES.md`, و`TEST_NOTES_AR.md`.


## v1.8.1 — Overture build hotfix
عند غياب PMTiles لإصدار Overture المثبت، يفحص CI المصدر قبل العمل المكلف ويستخدم إصدارًا حقيقيًا سابقًا ومثبتًا (حاليًا 2026-05-20.0 ثم 2026-04-15.0) بدل التحول إلى Natural Earth. يسجل manifest الإصدار الفعلي المستخدم.
