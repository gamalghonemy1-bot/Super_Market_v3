import 'package:flutter/material.dart';
import '../db.dart';
import '../session.dart';

const _typeNames = {
  'opening': 'رصيد افتتاحي',
  'sale': 'بيع',
  'purchase': 'شراء',
  'return': 'مرتجع',
  'cancel': 'إلغاء فاتورة',
  'adjust': 'تعديل يدوي',
  'shortage': 'عجز جرد',
  'surplus': 'زيادة جرد',
};

Future<void> showMovements(BuildContext c, Map<String, Object?> p) async {
  final rows = await AppDb.I.movements(p['id'] as int);
  if (!c.mounted) return;
  await showDialog<void>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text('حركة: ${p['name']}'),
      content: SizedBox(
        width: double.maxFinite,
        child: rows.isEmpty
            ? const Text('لا توجد حركات')
            : ListView(shrinkWrap: true, children: [
                for (final m in rows)
                  ListTile(
                    dense: true,
                    title: Text('${_typeNames[m['type']] ?? m['type']}: ${fmt(m['qty'] as num)}'),
                    subtitle: Text('${m['created_at']} ${m['user_name'] ?? ''}'),
                  ),
              ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
    ),
  );
}

class StocktakeScreen extends StatefulWidget {
  const StocktakeScreen({super.key});
  @override
  State<StocktakeScreen> createState() => _StocktakeState();
}

class _StocktakeState extends State<StocktakeScreen> {
  String q = '';
  List<Map<String, Object?>> items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await AppDb.I.products(q);
    if (mounted) setState(() => items = r);
  }

  Future<void> _count(Map<String, Object?> p) async {
    final v = await askText(context, 'الكمية الفعلية: ${p['name']}',
        hint: 'بالنظام: ${fmt(p['qty'] as num)}');
    if (v == null || v.trim().isEmpty) return;
    try {
      final diff = await AppDb.I.stocktake(p['id'] as int, toD(v), Session.id);
      if (!mounted) return;
      toast(context, diff == 0 ? 'لا يوجد فرق' : diff < 0 ? 'عجز ${fmt(-diff)}' : 'زيادة ${fmt(diff)}');
      _load();
    } catch (e) {
      if (mounted) toast(context, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('جرد المخزون')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              onChanged: (v) {
                q = v;
                _load();
              },
              decoration: const InputDecoration(
                  hintText: 'بحث بالاسم أو الباركود', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (_, i) => ListTile(
                title: Text(items[i]['name'] as String),
                subtitle: Text('بالنظام: ${fmt(items[i]['qty'] as num)} ${items[i]['unit'] ?? ''}'),
                trailing: const Icon(Icons.edit_note),
                onTap: () => _count(items[i]),
              ),
            ),
          ),
        ]),
      );
}

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  Widget _section(String title, List<Map<String, Object?>> rows, Color c, {bool expiry = false}) =>
      ExpansionTile(
        initiallyExpanded: rows.isNotEmpty,
        leading: Icon(Icons.warning_amber, color: c),
        title: Text('$title (${rows.length})'),
        children: [
          if (rows.isEmpty) const ListTile(title: Text('لا يوجد')),
          for (final r in rows)
            ListTile(
              dense: true,
              title: Text(r['name'] as String),
              subtitle: Text(expiry
                  ? 'تنتهي: ${r['expiry_date']}'
                  : 'المتاح: ${fmt(r['qty'] as num)} | الحد الأدنى: ${fmt(r['min_qty'] as num)}'),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('التنبيهات')),
        body: FutureBuilder<List<List<Map<String, Object?>>>>(
          future: Future.wait([AppDb.I.outOfStock(), AppDb.I.lowStock(), AppDb.I.expiringSoon()]),
          builder: (_, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            return ListView(children: [
              _section('أصناف نافدة', s.data![0], Colors.red),
              _section('أصناف منخفضة', s.data![1], Colors.amber),
              _section('قاربت على انتهاء الصلاحية (30 يوماً)', s.data![2], Colors.orange, expiry: true),
            ]);
          },
        ),
      );
}
