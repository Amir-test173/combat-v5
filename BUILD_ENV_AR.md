# بيئة البناء المعتمدة — v1.8

المصفوفة التي ثُبتت في المصدر وCI بناءً على تقرير البناء الناجح:
- Flutter 3.47.1
- Android Gradle Plugin 8.11.1
- Kotlin 2.2.20
- Gradle 8.14.3
- Java 17
- compileSdk 36
- targetSdk 36

بيئة ChatGPT الحالية لا تحتوي Flutter SDK أو Android SDK الكامل، لذلك لا يتم الادعاء بنتيجة Flutter محلية. GitHub Actions هو اختبار التكامل والبناء الفعلي.

CI لا يصلح Dart أو Gradle source تلقائيًا ولا يعمل commit/push. الإصلاحات موجودة في المصدر نفسه. إذا كان `gradle-wrapper.jar` غير موجود في حزمة المصدر، يستعيد Workflow هذا الـbinary القياسي فقط من scaffold Flutter مؤقت؛ لا يغير ملفات Dart/Gradle versions.
