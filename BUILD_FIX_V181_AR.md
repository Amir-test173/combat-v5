# World Dominion v1.8.1 — GitHub build hotfix

## سبب الفشل الذي ظهر في GitHub Actions
تشغيل المستخدم رقم 32769105240 نجح في source-and-server-check، ثم نجح في إعداد Flutter/Java/Node وتوليد 194 دولة و4275 محافظة وElevation/WorldCover. الفشل كان في Overture Transportation لأن URL الإصدار 2026-06-17.0 أعاد HTTP 404. النسخة السابقة اكتشفت ذلك بعد انتهاء Raster enrichment المكلف.

## الإصلاح
- فحص Overture PMTiles قبل أي Raster enrichment مكلف.
- المطلوب أولاً: 2026-06-17.0.
- fallbacks حقيقية مثبتة: 2026-05-20.0 ثم 2026-04-15.0.
- لا يعتبر Natural Earth نجاحاً عندما WD_REQUIRE_REAL_TRANSPORT=1.
- retries محدودة لطلبات HTTP Range.
- geodata_manifest.json يسجل إصدار Transportation الحقيقي المستخدم.
- تحديث GitHub Actions إلى runtimes أحدث مبنية على Node 24 لتقليل تحذيرات Node 20.
- Protocol 9 و Ruleset 1.8.0-parity-1 بقيا كما هما.

## السلوك المتوقع
إذا كان PMTiles للإصدار المطلوب غير متاح، سيظهر في السجل خلال ثوانٍ ثم يتم اختبار الإصدار السابق. إذا لم يتوفر أي Overture حقيقي، يفشل CI مبكراً ولا ينتظر ~16 دقيقة قبل إظهار الخطأ.
