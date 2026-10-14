# لمّة تلاتة — نسخة GitHub Pages

## الملفات

ارفع الملفين `index.html` و`anime-friends.png` الموجودين في هذا المجلد إلى جذر مستودع GitHub.

## نشر الموقع

1. افتح المستودع على GitHub ثم **Settings → Pages**.
2. في **Build and deployment** اختر **Deploy from a branch**.
3. اختر الفرع `main` والمجلد `/(root)` ثم اضغط **Save**.
4. انتظر ظهور رابط الموقع في صفحة Pages. عادةً يكون على الشكل `https://USERNAME.github.io/REPOSITORY/`.

بعد ظهور الرابط، أضفه في إعدادات Supabase تحت **Authentication → URL Configuration** كـ **Site URL** وضمن **Redirect URLs** حتى تعمل روابط الدعوة وتسجيل الدخول.

مفتاح Supabase الموجود في الصفحة هو publishable key. لا تضف أبدًا مفتاح `secret` أو `service_role` إلى ملفات الموقع.
