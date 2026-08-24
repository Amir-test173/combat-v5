# إعداد سيرفر World Dominion v1.8 Clean Build & Mode Parity

الإصدار المطابق: **1.8.0 / Protocol 9 / Ruleset 1.8.0-parity-1**.

## قاعدة التوافق
لا تستخدم تطبيق v1.8 مع سيرفر أقدم. عند `join` يرسل التطبيق Protocol + Ruleset، والسيرفر يرفض أي عدم تطابق قبل دخول الغرفة.

## التشغيل
داخل مجلد server:

```bash
npm install
npm run check
npm start
```

Node.js 20+ مطلوب، وCI يستخدم Node 22.

## Persistence
- إذا وُجد `DATABASE_URL` يستخدم PostgreSQL.
- بدونه يستخدم JSON محليًا في `LOCAL_SAVE_DIR`.
- Resume token يعيد اللاعب إلى هويته ودولته بعد الانقطاع.

## متغيرات مهمة
- `PORT`
- `DATABASE_URL`
- `LOCAL_SAVE_DIR`
- `MIN_PLAYERS_TO_START`
- `TURN_SECONDS` (override اختياري)
- `ADMIN_KEY`
- `DEVELOPER_NAME`
- `SUPPORT_EMAIL`

## Health
`/health` يعرض version/protocol/ruleset وخصائص البروتوكول وحالة geodata. يجب أن ترى v1.8 / 9 / `1.8.0-parity-1`.

## بيانات العالم
يفضل نشر Server bundle الذي ينتجه نفس GitHub Workflow الخاص بالـAPK، لأنه يحتوي `world_game_data.json` المولد من نفس Build وبالتالي تتطابق المحافظات والجغرافيا بين العميل والسيرفر.
