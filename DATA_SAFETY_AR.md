# دليل Data Safety — World Dominion RC1

هذا الملف يساعدك في Play Console لكنه ليس إجابة قانونية تلقائية. الإجابات النهائية يجب أن تطابق **نسخة التطبيق المنشورة ومزودي الاستضافة الفعليين**.

## ما يعالجه الكود الحالي عند استخدام Multiplayer

- Guest player ID عشوائي.
- Hash لـ Resume Token.
- Hash لمعرّف تثبيت مستعار يستخدم لمنع الإساءة والحظر.
- Display name يختاره المستخدم ويظهر للاعبين في الغرفة.
- الدولة المختارة، Room code، Ready/online state وحالة اللعبة.
- Abuse reports: معرف المبلّغ، معرف/اسم اللاعب المبلّغ عنه، Hash التثبيت الخاص بالهدف، الفئة والتوقيت وحالة المراجعة.
- كلمة مرور الغرفة لا تُخزن كنص واضح؛ يُحفظ salted verifier.
- مزود الاستضافة قد يسجل IP/Network metadata في سجلات البنية التحتية.

## أشياء غير موجودة في RC1

- لا Ads SDK.
- لا Analytics SDK.
- لا Google/Facebook login.
- لا Contacts/Location/Camera/Microphone permissions.
- لا شراء داخل التطبيق.
- لا دردشة أو رفع صور/فيديو.

## نقاط مرجحة عند تعبئة النموذج

قد تحتاج إلى التصريح بفئات مثل **Name / User IDs / App activity أو Other user-generated content** اعتماداً على تفسير Play للنموذج وقت الإرسال. لا تعتمد على هذا الملف وحده: اقرأ تعريف كل فئة داخل Play Console واختر ما يطابق البيانات أعلاه.

- Multiplayer data تستخدم لوظيفة اللعبة، الأمان، منع الاحتيال/الإساءة وإدارة الحساب/الجلسة الضيفية.
- الاتصال Production مشفر أثناء النقل عبر HTTPS/WSS.
- توجد آلية حذف بيانات هوية الغرفة من داخل التطبيق وصفحة `/delete-data`.
- الحفظ غير النشط مضبوط افتراضياً على 90 يوماً.
- قد تُحتفظ سجلات حظر مستعارة لمدة أطول عندما تكون لازمة لمنع إساءة الاستخدام؛ يجب أن يبقى ذلك مذكوراً في سياسة الخصوصية.

## مشاركة البيانات

الكود نفسه لا يبيع البيانات ولا يرسلها إلى شبكات إعلانات. لكن مزودي السيرفر/قاعدة البيانات يعالجون البيانات لتشغيل الخدمة. راجع شروط مزوديك وحدد في Play Console إن كان تعاملهم يدخل في تعريف Google لـ "sharing" أو في استثناء مزود الخدمة.

## روابط رسمية

- User Data / Privacy Policy: https://support.google.com/googleplay/android-developer/answer/10144311
- Data Safety form: https://support.google.com/googleplay/android-developer/answer/10787469
- UGC policy: https://support.google.com/googleplay/android-developer/answer/9876937
