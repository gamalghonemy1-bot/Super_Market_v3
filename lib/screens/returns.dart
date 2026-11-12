import 'package:flutter/material.dart';
import '../db.dart';
import '../session.dart';

class ReturnsScreen extends StatefulWidget {
  const ReturnsScreen({super.key});
  @override
  State<ReturnsScreen> createState() => _ReturnsState();
}

class _ReturnsState extends State<ReturnsScreen> {
  final no = TextEditingController();
  final reason = TextEditingController();
  int? saleId;
  List<Map<String, Object?>> items = [];
  final Map<int, TextEditingController> ctl = {};
  bool restock = true;

  Future<void> _load() async {
    final id = int.tryParse(no.text.trim());
    if (id == null) {
      toast(context, 'اكتب رقم الفاتورة');
      return;
    }
    final s = await AppDb.I.saleById(id);
    if (!mounted) return;
    if (s == null || s['status'] != 'active') {
      toast(context, 'الفاتورة غير موجودة أو ملغاة');
      return;
    }
    final it = await AppDb.I.returnableItems(id);
    setState(() {
      saleId = id;
      items = it;
      ctl
        ..clear()
        ..addEntries(it.map((e) => MapEntry(e['id'] as int, TextEditingController())));
    });
  }

  Future<void> _save() async {
    try {
      final q = <int, double>{for (final e in ctl.entries) e.key: toD(e.value.text)};
      final id = await AppDb.I.createReturn(
          saleId: saleId!, qtys: q, reason: reason.text, restock: restock, userId: Session.id);
      if (!mounted) return;
      toast(context, 'تم تسجيل المرتجع رقم $id');
      setState(() {
        saleId = null;
        items = [];
        reason.clear();
        no.clear();
      });
    } catch (e) {
      if (mounted) toast(context, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('مرتجعات العملاء')),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          Row(children: [
            Expanded(
              child: TextField(
                  controller: no,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'رقم الفاتورة', border: OutlineInputBorder())),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _load, child: const Text('عرض')),
          ]),
          if (saleId != null) ...[
            const SizedBox(height: 12),
            for (final i in items)
              ListTile(
                title: Text('${i['name']}'),
                subtitle: Text('المباع: ${fmt(i['qty'] as num)} | المتاح للإرجاع: ${fmt(i['left_qty'] as num)}'),
                trailing: SizedBox(
                  width: 80,
                  child: TextField(
                      controller: ctl[i['id'] as int],
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: 'الكمية', isDense: true)),
                ),
              ),
            SwitchListTile(
                title: const Text('إعادة الكمية إلى المخزون (صالحة)'),
                value: restock,
                onChanged: (v) => setState(() => restock = v)),
            TextField(
                controller: reason,
                decoration: const InputDecoration(labelText: 'سبب المرتجع', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            FilledButton(onPressed: _save, child: const Text('تسجيل المرتجع')),
          ],
        ]),
      );
}
