class VoiceItem {
  final String text;
  double qty;
  final Map<String, Object?>? product;
  VoiceItem(this.text, this.qty, this.product);
}

String normAr(String s) {
  var o = s.toLowerCase();
  o = o.replaceAll(RegExp('[\u064B-\u0652\u0640]'), '');
  o = o.replaceAll(RegExp('[أإآ]'), 'ا').replaceAll('ى', 'ي').replaceAll('ة', 'ه');
  const ar = '٠١٢٣٤٥٦٧٨٩';
  for (var i = 0; i < 10; i++) {
    o = o.replaceAll(ar[i], '$i');
  }
  o = o.replaceAll(RegExp('[،,.؟?!]'), ' ');
  return o.replaceAll(RegExp(r'\s+'), ' ').trim();
}

const _nums = <String, double>{
  'واحد': 1, 'واحده': 1, 'اتنين': 2, 'اثنين': 2, 'تنين': 2, 'اثنان': 2,
  'ثلاثه': 3, 'تلاته': 3, 'ثلاث': 3, 'تلات': 3, 'اربعه': 4, 'اربع': 4,
  'خمسه': 5, 'خمس': 5, 'سته': 6, 'ست': 6, 'سبعه': 7, 'سبع': 7,
  'ثمانيه': 8, 'تمانيه': 8, 'ثماني': 8, 'تسعه': 9, 'تسع': 9,
  'عشره': 10, 'عشر': 10, 'نص': 0.5, 'نصف': 0.5, 'ربع': 0.25,
  'زجاجتين': 2, 'علبتين': 2, 'كيسين': 2, 'عبوتين': 2,
};

const _units = <String>{
  'كيلو', 'كيلوجرام', 'كجم', 'جرام', 'لتر', 'لترات', 'زجاجه', 'زجاجات',
  'علبه', 'علب', 'كيس', 'اكياس', 'عبوه', 'عبوات', 'قطعه', 'قطع',
  'كرتونه', 'كراتين', 'دسته', 'باكو', 'باكت', 'زجاجتين', 'علبتين', 'كيسين', 'عبوتين',
};

const _cmds = <String>{'اضف', 'زود', 'حط', 'ضيف', 'اعمل', 'عايز', 'اريد', 'محتاج', 'من', 'فضلك'};

double? _numOf(String t) {
  if (_nums.containsKey(t)) return _nums[t];
  return double.tryParse(t);
}

bool _isQty(String r) =>
    r.isNotEmpty && (_numOf(r) != null || _units.contains(r) || RegExp(r'^\d').hasMatch(r));

String _stripAl(String t) => t.length > 3 && t.startsWith('ال') ? t.substring(2) : t;

/// يحوّل جملة مثل «أضف 2 كيلو سكر و3 زجاجات زيت وعلبة شاي» إلى أصناف وكميات.
/// الأصناف التي لم يتم التعرف عليها تُرجَع بـ product == null.
List<VoiceItem> parseVoice(String text, List<Map<String, Object?>> products) {
  final tokens = normAr(text).split(' ').where((t) => t.isNotEmpty).toList();
  final segs = <List<String>>[[]];
  for (final t in tokens) {
    if (t == 'و') {
      segs.add([]);
      continue;
    }
    if (t.length > 1 && t.startsWith('و') && _isQty(t.substring(1))) {
      segs.add([t.substring(1)]);
      continue;
    }
    segs.last.add(t);
  }
  final normProducts = [
    for (final p in products)
      (p, normAr(p['name'] as String).split(' ').map(_stripAl).toList(), normAr(p['name'] as String))
  ];
  final out = <VoiceItem>[];
  for (final seg in segs) {
    final toks = seg.where((t) => !_cmds.contains(t)).toList();
    if (toks.isEmpty) continue;
    double qty = 1;
    var found = false;
    final query = <String>[];
    for (final t in toks) {
      if (!found && _numOf(t) != null) {
        qty = _numOf(t)!;
        found = true;
      } else if (_units.contains(t)) {
        // كلمة وحدة فقط
      } else {
        query.add(_stripAl(t));
      }
    }
    final label = seg.join(' ');
    if (query.isEmpty) {
      out.add(VoiceItem(label, qty, null));
      continue;
    }
    Map<String, Object?>? best;
    var bestLen = 1 << 30;
    for (final (p, ptoks, full) in normProducts) {
      final ok = query.every((q) => ptoks.any((pt) => pt == q || pt.contains(q)) || full.contains(q));
      if (ok && full.length < bestLen) {
        best = p;
        bestLen = full.length;
      }
    }
    out.add(VoiceItem(label, qty, best));
  }
  return out;
}
