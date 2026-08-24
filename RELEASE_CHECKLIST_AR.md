# Checklist الإطلاق — World Dominion 1.2 Combat / Frontlines

## A — لعب أونلاين مع صديقك الآن

- [ ] انشر `server/` على استضافة عامة.
- [ ] أضف PostgreSQL واضبط `DATABASE_URL`.
- [ ] أضف `DEVELOPER_NAME` و`SUPPORT_EMAIL` و`ADMIN_KEY`.
- [ ] افتح `/health` وتأكد من `ok=true`, `persistence=postgres`, `policyConfigured=true`.
- [ ] في GitHub → Settings → Secrets and variables → Actions → Variables أضف:
  - `DEFAULT_SERVER_URL` = `wss://YOUR-SERVER`
  - `PRIVACY_POLICY_URL` = `https://YOUR-SERVER/privacy`
  - `SUPPORT_EMAIL` = بريد الدعم.
- [ ] شغّل Action: **Build World Dominion RC**.
- [ ] نزّل Artifact: `world-dominion-1.3.0-provinces-apk`.
- [ ] ثبّت APK على هاتفين حقيقيين.
- [ ] أنشئ غرفة بكلمة مرور، واختر دولتين مختلفتين، ثم Ready/Start.
- [ ] اختبر 10 أدوار على الأقل، هجوم، بناء، تجنيد، تحالف، رفض تحالف، انقطاع Wi‑Fi وإعادة اتصال.
- [ ] أغلق/أعد تشغيل السيرفر وتأكد أن PostgreSQL يعيد المباراة.
- [ ] اختبر الاستسلام وخسارة آخر إقليم والتحول إلى Spectator.

## B — قبل Google Play Closed Testing

- [ ] قرر Package ID النهائي. الحالي `com.worlddominion.game`. تغييره بعد أول نشر في Play ليس خطوة عادية، لذلك احسمه قبل الرفع الأول.
- [ ] قرر الاسم التجاري النهائي وافحص العلامات التجارية/الأسماء المتشابهة في الأسواق المستهدفة.
- [ ] استبدل أيقونة التطبيق المؤقتة بهوية أصلية تملك حقوقها.
- [ ] جهز 512×512 Play icon، Feature Graphic، ولقطات شاشة فعلية من اللعبة.
- [ ] اضبط بريد دعم وموقع/صفحة خصوصية عامة ثابتة.
- [ ] راجع `DATA_SAFETY_AR.md` ثم املأ Data Safety بما يطابق الاستضافة الفعلية.
- [ ] حدد Target audience وContent rating بدقة. اللعبة تتضمن حرباً عسكرية خيالية؛ لا تخمّن التصنيف.
- [ ] اختبر على Android 15/16 وعلى جهاز/محاكي 64-bit حديث.
- [ ] بعد رفع AAB افحص Play Console للتأكد من عدم وجود تحذير 16 KB page-size compatibility.

## C — مفتاح الرفع والتوقيع

أنشئ Upload Keystore واحتفظ به في مكانين آمنين خارج GitHub:

```bash
keytool -genkeypair -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

في GitHub Actions Secrets أضف:

```text
ANDROID_KEYSTORE_BASE64
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD
ANDROID_STORE_PASSWORD
```

لتحويل keystore إلى Base64 في PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks")) | Set-Clipboard
```

ثم شغّل Action: **Build signed Google Play AAB**.

الناتج:

```text
world-dominion-1.3.0-provinces-play-aab / app-release.aab
```

## D — متطلبات Play الحالية التي يجب الانتباه لها

- التطبيقات الجديدة وتحديثاتها يجب أن تستهدف API 36 ابتداءً من 31 أغسطس 2026. المشروع مضبوط على 36.
- التطبيقات الجديدة تُرفع بصيغة Android App Bundle (AAB).
- كل التطبيقات تحتاج Privacy Policy وData Safety دقيقين.
- إذا كان حساب المطور Personal وأنشئ بعد 13 نوفمبر 2023، فالمتطلب الحالي للوصول إلى Production هو Closed Test بحد أدنى 12 مختبراً منضمين باستمرار لمدة 14 يوماً ثم التقدم للحصول على Production access.
- أسماء اللاعبين المرئية تعتبر محتوى ينشئه المستخدم؛ اللعبة تطلب قبول الشروط وتوفر Report/Block والسيرفر يوفر مسار إشراف، لكن يجب أن تراجع البلاغات فعلياً عند فتح الخدمة للعامة.

روابط مرجعية رسمية مذكورة أيضاً في `PLAY_STORE_LISTING_AR.md`.

## E — Go / No-Go قبل البيع العام

لا تنتقل إلى Production إذا بقي أي مما يلي:

- [ ] Crash أو Freeze متكرر.
- [ ] فقدان مباراة بعد إعادة تشغيل السيرفر.
- [ ] لاعب يستطيع تعديل موارده عبر Client غير موثوق.
- [ ] أخطاء إعادة الاتصال/ازدواجية الدولة.
- [ ] سياسة الخصوصية فيها بيانات Placeholder.
- [ ] لا يوجد شخص يراجع بلاغات المستخدمين.
- [ ] لا يوجد Backup لقاعدة البيانات.
- [ ] لم تختبر AAB الذي نزله Google Play على مسار Internal/Closed Testing.
