# Preservation v1.7

قاعدة المشروع: **v1.7 يبني فوق v1.6 ولا يحذف نظامًا سابقًا.**

## كل الأنظمة المحفوظة
المحافظات، الحاميات، التحصينات، الذهب، التجنيد، معسكرات التدريب، FrontBattle، Auto/Manual، الاحتياط والتعزيز والانسحاب والتطويق، الاقتصاد والبحث والحكومة والأحداث والمقاومة والاحتلال والدبلوماسية والتجسس، الإمداد والغزو البرمائي، Fog of War، سرعات المباراة، EW والأقمار والصواريخ، Sea Zones وTask Forces والحاملات والغواصات والرادار والإنذار المبكر، وكل أنظمة v1.1–v1.6.

`roads`, `rail`, `logisticsLevel` القديمة لم تُستبدل؛ هي استثمار اللاعب فوق الشبكة الفعلية.

## الحقول المضافة/الموسعة
- Elevation: `elevationM`, `elevationMinM`, `elevationMaxM`, `reliefM`, `elevationSamples`.
- Land Cover: `landCover`, `landCoverMix`, `landCoverSamples`.
- Transport: `actualRoadKm`, `actualRailKm`, `roadDensity`, `railDensity`, `roadClassKm`, `railClassKm`.
- Quality: `physicalDataQuality`, `transportDataQuality`.
- `transport_map.json` يرسم شبكة استراتيجية مبسطة ولا يغير منطق الحفظ القديم.

## Save compatibility
كل الحقول الجديدة تملك Defaults عند قراءة Save أقدم. لذلك حفظ v1.6 لا يفشل لمجرد غياب البيانات الفيزيائية الجديدة.

## Protocol
Protocol = **8** لأن Snapshot المحافظات توسع. تطبيق وسيرفر v1.7 يجب أن يتطابقا في Multiplayer.

## مقارنة الملفات
المقارنة النهائية قبل التغليف: **v1.6 = 74 ملفًا، v1.7 = 86 ملفًا، المحذوف = 0، المضاف = 12** (مع استبعاد `node_modules` وملفات cache المؤقتة).
