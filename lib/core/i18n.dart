import 'package:flutter/widgets.dart';

/// Minimal EN/AR string table. Keys are stable; add both languages together.
const Map<String, Map<String, String>> _strings = {
  'app_name': {'en': 'ServePOS Waiter', 'ar': 'ServePOS للنادل'},
  // Server URL
  'server_title': {'en': 'Connect to your restaurant', 'ar': 'اتصل بمطعمك'},
  'server_hint': {'en': 'Paste the address your manager gave you', 'ar': 'الصق العنوان الذي أعطاك إياه المدير'},
  'server_label': {'en': 'Server address', 'ar': 'عنوان الخادم'},
  'server_paste': {'en': 'Paste', 'ar': 'لصق'},
  'server_continue': {'en': 'Continue', 'ar': 'متابعة'},
  'server_checking': {'en': 'Checking server…', 'ar': 'جارٍ فحص الخادم…'},
  'server_invalid': {'en': 'That does not look like a web address.', 'ar': 'هذا لا يبدو عنوان ويب صحيحاً.'},
  'server_unreachable': {'en': 'Could not reach a ServePOS server at this address.', 'ar': 'تعذر الوصول إلى خادم ServePOS على هذا العنوان.'},
  'server_http_public': {
    'en': 'This address is not secure (http). Ask your manager for the https address.',
    'ar': 'هذا العنوان غير آمن (http). اطلب من المدير عنوان https.'
  },
  'server_http_local_title': {'en': 'Insecure local server', 'ar': 'خادم محلي غير آمن'},
  'server_http_local_body': {
    'en': 'This server uses plain http on a local network. Passwords and orders are sent unencrypted. Only continue on a trusted test network.',
    'ar': 'يستخدم هذا الخادم http على شبكة محلية. ستُرسل كلمات المرور والطلبات بدون تشفير. تابع فقط على شبكة اختبار موثوقة.'
  },
  'server_http_local_ok': {'en': 'I understand, continue', 'ar': 'أفهم ذلك، تابع'},
  'cancel': {'en': 'Cancel', 'ar': 'إلغاء'},
  // Login
  'login_title': {'en': 'Sign in', 'ar': 'تسجيل الدخول'},
  'login_user': {'en': 'Username or email', 'ar': 'اسم المستخدم أو البريد'},
  'login_password': {'en': 'Password', 'ar': 'كلمة المرور'},
  'login_button': {'en': 'Sign in', 'ar': 'دخول'},
  'login_change_server': {'en': 'Change server', 'ar': 'تغيير الخادم'},
  'login_help': {'en': 'Your manager creates your account. Ask them if you forgot your password.', 'ar': 'المدير ينشئ حسابك. اسأله إذا نسيت كلمة المرور.'},
  'session_ended': {'en': 'Your session ended. Please sign in again.', 'ar': 'انتهت جلستك. يرجى تسجيل الدخول مرة أخرى.'},
  'bio_offer_title': {'en': 'Use fingerprint to unlock next time?', 'ar': 'استخدام البصمة لفتح التطبيق في المرة القادمة؟'},
  'bio_offer_body': {
    'en': 'You will not need your password again on this phone until you sign out.',
    'ar': 'لن تحتاج إلى كلمة المرور مجدداً على هذا الهاتف حتى تسجل الخروج.'
  },
  'bio_offer_yes': {'en': 'Use fingerprint', 'ar': 'استخدم البصمة'},
  'bio_offer_no': {'en': 'Not now', 'ar': 'ليس الآن'},
  'lock_title': {'en': 'Unlock ServePOS', 'ar': 'افتح ServePOS'},
  'lock_reason': {'en': 'Confirm it is you to open the waiter app', 'ar': 'أكّد هويتك لفتح تطبيق النادل'},
  'lock_unlock': {'en': 'Unlock', 'ar': 'فتح'},
  'lock_use_password': {'en': 'Use password instead', 'ar': 'استخدم كلمة المرور'},
  'lock_failed': {'en': 'Not recognised. Try again.', 'ar': 'لم يتم التعرف. حاول مرة أخرى.'},
  'profile_pick': {'en': 'Choose your outlet', 'ar': 'اختر المنفذ'},
  // Shell
  'nav_floor': {'en': 'Floor', 'ar': 'الصالة'},
  'nav_orders': {'en': 'Orders', 'ar': 'الطلبات'},
  'nav_calls': {'en': 'Calls', 'ar': 'النداءات'},
  'nav_account': {'en': 'Account', 'ar': 'الحساب'},
  'offline_banner': {'en': 'Offline: orders will wait on this phone', 'ar': 'غير متصل: ستنتظر الطلبات على هذا الهاتف'},
  'outbox_waiting': {'en': 'Waiting to send ({n})', 'ar': 'بانتظار الإرسال ({n})'},
  'outbox_failed': {'en': '{n} not sent: tap to review', 'ar': '{n} لم يُرسل: اضغط للمراجعة'},
  // Floor
  'floor_takeaway': {'en': 'Takeaway', 'ar': 'سفري'},
  'floor_all': {'en': 'All', 'ar': 'الكل'},
  'floor_available': {'en': 'Free', 'ar': 'متاحة'},
  'floor_occupied': {'en': 'Occupied', 'ar': 'مشغولة'},
  'floor_reserved': {'en': 'Reserved', 'ar': 'محجوزة'},
  'floor_updated': {'en': 'Updated {t}', 'ar': 'آخر تحديث {t}'},
  'floor_stale': {'en': 'Showing last known floor', 'ar': 'عرض آخر حالة معروفة'},
  'floor_empty': {'en': 'No tables set up for this outlet.', 'ar': 'لا توجد طاولات لهذا المنفذ.'},
  'floor_draft': {'en': 'Draft', 'ar': 'مسودة'},
  'min': {'en': '{n} min', 'ar': '{n} د'},
  // Take order
  'order_search': {'en': 'Search menu', 'ar': 'ابحث في القائمة'},
  'order_all_items': {'en': 'All', 'ar': 'الكل'},
  'order_guests': {'en': 'Guests', 'ar': 'الضيوف'},
  'order_notes': {'en': 'Order note for kitchen', 'ar': 'ملاحظة الطلب للمطبخ'},
  'order_line_note': {'en': 'Note for this item', 'ar': 'ملاحظة لهذا الصنف'},
  'order_send': {'en': 'Send', 'ar': 'إرسال'},
  'order_add_round': {'en': 'Add to order', 'ar': 'أضف إلى الطلب'},
  'order_sent_items': {'en': 'Sent', 'ar': 'أُرسل'},
  'order_new_items': {'en': 'New', 'ar': 'جديد'},
  'order_cart_empty': {'en': 'Tap items to add them', 'ar': 'اضغط على الأصناف لإضافتها'},
  'order_review': {'en': 'Review', 'ar': 'مراجعة'},
  'order_items': {'en': '{n} items', 'ar': '{n} أصناف'},
  'order_unavailable': {'en': 'Not available', 'ar': 'غير متوفر'},
  'order_menu_missing': {'en': 'Menu not loaded yet. Connect to the server once to download it.', 'ar': 'لم يتم تحميل القائمة. اتصل بالخادم مرة لتنزيلها.'},
  'order_mods_missing': {'en': 'Options for this item are not downloaded. Refresh the menu online first.', 'ar': 'خيارات هذا الصنف غير محملة. حدّث القائمة أولاً.'},
  'order_sending': {'en': 'Sending…', 'ar': 'جارٍ الإرسال…'},
  'order_sent_ok': {'en': 'Sent to the till: {name}', 'ar': 'أُرسل إلى الكاشير: {name}'},
  'order_queued': {'en': 'No connection. Order saved on this phone and NOT sent yet. It will send automatically.', 'ar': 'لا يوجد اتصال. حُفظ الطلب على الهاتف ولم يُرسل بعد. سيُرسل تلقائياً.'},
  'order_clear': {'en': 'Clear draft', 'ar': 'مسح المسودة'},
  'order_clear_q': {'en': 'Remove all new items for this table?', 'ar': 'حذف كل الأصناف الجديدة لهذه الطاولة؟'},
  'order_waiting_here': {'en': 'Waiting to send for this table: {n}', 'ar': 'بانتظار الإرسال لهذه الطاولة: {n}'},
  'remove': {'en': 'Remove', 'ar': 'حذف'},
  'done': {'en': 'Done', 'ar': 'تم'},
  'add': {'en': 'Add', 'ar': 'أضف'},
  'total': {'en': 'Total', 'ar': 'المجموع'},
  'retry': {'en': 'Retry', 'ar': 'إعادة المحاولة'},
  'discard': {'en': 'Discard', 'ar': 'تجاهل'},
  'close': {'en': 'Close', 'ar': 'إغلاق'},
  'refresh': {'en': 'Refresh', 'ar': 'تحديث'},
  // Modifiers
  'mod_required': {'en': 'Required', 'ar': 'مطلوب'},
  'mod_optional': {'en': 'Optional', 'ar': 'اختياري'},
  'mod_pick_one': {'en': 'Pick 1', 'ar': 'اختر 1'},
  'mod_pick_up_to': {'en': 'Up to {n}', 'ar': 'حتى {n}'},
  'mod_pick_any': {'en': 'Any', 'ar': 'أي عدد'},
  'mod_err_required': {'en': 'Choose an option for {g}', 'ar': 'اختر خياراً لـ {g}'},
  'mod_err_max': {'en': '{g}: choose at most {n}', 'ar': '{g}: اختر {n} كحد أقصى'},
  'mod_add_to_order': {'en': 'Add to order', 'ar': 'أضف إلى الطلب'},
  // Orders
  'orders_mine': {'en': 'Mine', 'ar': 'طلباتي'},
  'orders_all': {'en': 'All open', 'ar': 'كل المفتوحة'},
  'orders_empty': {'en': 'No orders today.', 'ar': 'لا توجد طلبات اليوم.'},
  'orders_load_failed': {'en': 'Could not refresh. Showing the last list.', 'ar': 'تعذر التحديث. عرض آخر قائمة.'},
  'orders_ready_banner': {'en': 'Ready to serve: {list}', 'ar': 'جاهز للتقديم: {list}'},
  'order_cancel': {'en': 'Cancel order', 'ar': 'إلغاء الطلب'},
  'order_cancel_reason': {'en': 'Reason for cancelling', 'ar': 'سبب الإلغاء'},
  'order_cancel_confirm': {'en': 'Cancel this order', 'ar': 'إلغاء هذا الطلب'},
  'order_cancelled': {'en': 'Order cancelled', 'ar': 'تم إلغاء الطلب'},
  'order_round': {'en': 'Round {n}', 'ar': 'الدفعة {n}'},
  'order_by': {'en': 'by {n}', 'ar': 'بواسطة {n}'},
  'order_add_more': {'en': 'Add items', 'ar': 'أضف أصنافاً'},
  'order_guests_n': {'en': '{n} guests', 'ar': '{n} ضيوف'},
  'takeaway': {'en': 'Takeaway', 'ar': 'سفري'},
  'status_pending': {'en': 'Pending', 'ar': 'قيد الانتظار'},
  'status_accepted': {'en': 'Accepted', 'ar': 'مقبول'},
  'status_inKitchen': {'en': 'In Kitchen', 'ar': 'في المطبخ'},
  'status_ready': {'en': 'Ready', 'ar': 'جاهز'},
  'status_served': {'en': 'Served', 'ar': 'تم التقديم'},
  'status_paid': {'en': 'Paid', 'ar': 'مدفوع'},
  'status_cancelled': {'en': 'Cancelled', 'ar': 'ملغي'},
  'status_rejected': {'en': 'Rejected', 'ar': 'مرفوض'},
  'status_unknown': {'en': 'Unknown', 'ar': 'غير معروف'},
  'status_waiting': {'en': 'Waiting to send', 'ar': 'بانتظار الإرسال'},
  'status_failed': {'en': 'Not sent', 'ar': 'لم يُرسل'},
  // Calls
  'calls_empty': {'en': 'No guests are calling right now.', 'ar': 'لا يوجد ضيوف يطلبون الآن.'},
  'calls_accept': {'en': 'I\'m going', 'ar': 'أنا ذاهب'},
  'calls_attended': {'en': 'Done', 'ar': 'تم'},
  'calls_taken_by': {'en': 'Already taken by {n}', 'ar': 'تولاه {n} بالفعل'},
  'calls_yours': {'en': 'You are on it', 'ar': 'أنت تتولاه'},
  'calls_waiting': {'en': 'Waiting for a waiter', 'ar': 'بانتظار نادل'},
  'calls_ago': {'en': '{n} min ago', 'ar': 'منذ {n} د'},
  'calls_notify_off': {'en': 'Notifications are off. You will not hear guest calls.', 'ar': 'الإشعارات متوقفة. لن تسمع نداءات الضيوف.'},
  'calls_enable': {'en': 'Turn on', 'ar': 'تفعيل'},
  // Settings
  'acc_outlet': {'en': 'Outlet', 'ar': 'المنفذ'},
  'acc_server': {'en': 'Server', 'ar': 'الخادم'},
  'acc_security': {'en': 'Security', 'ar': 'الأمان'},
  'acc_biometric': {'en': 'Fingerprint unlock', 'ar': 'فتح بالبصمة'},
  'acc_biometric_unavailable': {'en': 'No fingerprint or screen lock set up on this phone', 'ar': 'لا توجد بصمة أو قفل شاشة على هذا الهاتف'},
  'acc_idle': {'en': 'Lock after', 'ar': 'القفل بعد'},
  'acc_idle_n': {'en': '{n} min in background', 'ar': '{n} د في الخلفية'},
  'acc_screenshots': {'en': 'Block screenshots', 'ar': 'منع لقطات الشاشة'},
  'acc_language': {'en': 'Language', 'ar': 'اللغة'},
  'acc_devices': {'en': 'Signed-in devices', 'ar': 'الأجهزة المسجلة'},
  'acc_this_device': {'en': 'This phone', 'ar': 'هذا الهاتف'},
  'acc_revoke': {'en': 'Sign out', 'ar': 'تسجيل خروج'},
  'acc_revoke_q': {'en': 'Sign out {d}?', 'ar': 'تسجيل خروج {d}؟'},
  'acc_last_seen': {'en': 'Last seen {t}', 'ar': 'آخر ظهور {t}'},
  'acc_sign_out': {'en': 'Sign out of this phone', 'ar': 'تسجيل الخروج من هذا الهاتف'},
  'acc_sign_out_q': {'en': 'Sign out? Unsent orders on this phone will be lost.', 'ar': 'تسجيل الخروج؟ ستُفقد الطلبات غير المرسلة على هذا الهاتف.'},
  'acc_sign_out_q_clean': {'en': 'Sign out of ServePOS on this phone?', 'ar': 'تسجيل الخروج من ServePOS على هذا الهاتف؟'},
  'acc_change_outlet': {'en': 'Change', 'ar': 'تغيير'},
  'acc_version': {'en': 'Version {v}', 'ar': 'الإصدار {v}'},
  'acc_refresh_menu': {'en': 'Refresh menu', 'ar': 'تحديث القائمة'},
  'acc_menu_version': {'en': 'Menu updated {t}', 'ar': 'آخر تحديث للقائمة {t}'},
  'acc_notifications': {'en': 'Notifications', 'ar': 'الإشعارات'},
  'acc_push_on': {'en': 'Push alerts on', 'ar': 'تنبيهات الدفع مفعلة'},
  'acc_push_on_sub': {'en': 'Guest calls ring even when the app is closed.', 'ar': 'نداءات الضيوف تصل حتى عند إغلاق التطبيق.'},
  'acc_push_off': {'en': 'Push alerts off', 'ar': 'تنبيهات الدفع متوقفة'},
  'acc_push_off_sub': {
    'en': 'This build has no push setup. Guest calls are checked every 10 seconds only while the app is open.',
    'ar': 'هذا الإصدار بدون إعداد تنبيهات الدفع. يتم فحص نداءات الضيوف كل 10 ثوانٍ فقط أثناء فتح التطبيق.'
  },
  'error_generic': {'en': 'Something went wrong. Try again.', 'ar': 'حدث خطأ. حاول مرة أخرى.'},
};

String tr(String lang, String key, [Map<String, Object?> args = const {}]) {
  final entry = _strings[key];
  var s = entry == null ? key : (entry[lang] ?? entry['en'] ?? key);
  args.forEach((k, v) => s = s.replaceAll('{$k}', '${v ?? ''}'));
  return s;
}

/// Every key, for the completeness test.
Iterable<String> get allStringKeys => _strings.keys;
bool hasTranslation(String key, String lang) => _strings[key]?[lang] != null;

extension Tr on BuildContext {
  String get lang => Localizations.maybeLocaleOf(this)?.languageCode == 'ar' ? 'ar' : 'en';
  bool get isArabic => lang == 'ar';
  String t(String key, [Map<String, Object?> args = const {}]) => tr(lang, key, args);
}
