# World Dominion — Geographic data sources

الملف `assets/geodata_manifest.json` يسجل مصدر وتغطية كل Build. البيانات الخارجية تُستخدم وقت البناء؛ اللعب العادي يقرأ Assets محلية.

## Natural Earth — Admin-1 boundaries
- الإصدار المثبت: **v5.1.2 / 1:10m**.
- يستخدم لحدود المحافظات/الولايات Admin-1 وخريطة النقر داخل الدولة.
- Natural Earth يعلن بياناته Public Domain.
- طبقة Roads منه لم تعد المصدر الافتراضي للشبكة العالمية في v1.7؛ بقيت Fallback فقط.

## Copernicus DEM GLO-90
- نموذج ارتفاع عالمي بدقة 90 مترًا.
- v1.7 يأخذ عدة عينات حتمية داخل كل Admin-1 ويحسب ارتفاعًا نموذجيًا ومدى ارتفاع وتضرسًا محليًا.
- لا ندعي أنها إحصائية لكل بكسل من مساحة المحافظة.
- Copernicus يجعل GLO-90 متاحًا للعامة على أساس مجاني وفق رخصته؛ يجب الاحتفاظ بإشعارات المصدر والرخصة المطلوبة عند التوزيع.

## ESA WorldCover 2021 v200
- Land Cover عالمي بدقة 10 م و11 فئة.
- عدة عينات داخل Admin-1 تُجمع إلى فئة غالبة و`landCoverMix`.
- WorldCover يعلن المنتج مجانيًا بلا تقييد استخدام تحت **CC BY 4.0** مع الإسناد المطلوب.
- Attribution المقترح من ESA: `© ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium`.
- الدقة الإجمالية المنشورة لـWorldCover 2021 v200 هي 76.7%؛ لذلك هو منتج Land Cover وليس حقيقة ميدانية مطلقة لكل نقطة.

## Overture Maps Transportation
- Release مثبت في v1.7: **2026-06-17.0**.
- المصدر في Build الحقيقي: Transportation PMTiles.
- طبقة اللعبة الاستراتيجية تستخدم road classes: `motorway`, `trunk`, `primary`, `secondary` + `rail`.
- هذا يتوافق مع hierarchy الموجودة في Overture Transportation profile؛ Zoom 9 يسمح بشبكة مناسبة لخريطة استراتيجية دون تخزين كل شارع محلي.
- `actualRoadKm` في اللعبة = طول الشبكة الاستراتيجية المستخرجة، وليس إجمالي كل شوارع المحافظة.
- Overture Transportation يخضع لـ **ODbL** ويحتوي بيانات من OpenStreetMap ومصادر أخرى مثل TomTom. يجب الحفاظ على Attribution واتباع متطلبات ODbL قبل النشر التجاري/إعادة توزيع قاعدة مشتقة.
- Attribution يجب أن يشمل OpenStreetMap contributors وOverture Maps Foundation وفق صفحة Attribution الرسمية.

## mledoze/countries
يستعمل `tool/fetch_world_data.py` حاليًا بيانات ISO/السكان/العواصم/الحدود البرية من هذا المشروع، وهو يعلن ODbL-1.0. يلزم تدقيق ترخيص كامل قبل إطلاق متجر تجاري لقاعدة البيانات المولدة.

## ما هو Gameplay abstraction؟
- Sea Zones ليست EEZ أو خرائط ملاحة قانونية.
- Weather الحالي نظام محاكاة مناخي/استراتيجي وليس تغذية طقس حي.
- Roads/Rail/Logistics 0–5 هي استثمارات اللاعب؛ لا تمثل عدد الطرق الحقيقية. الشبكة الفعلية محفوظة في حقول منفصلة.
