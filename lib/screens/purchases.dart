import 'package:flutter/material.dart';
import '../db.dart';
import '../session.dart';

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});
  @override
  State<PurchasesScreen> createState() => _PurchasesState();
}

class _PurchasesState extends State<PurchasesScreen> {
  final search = TextEditingController();
  final paid = TextEditingController();
  final List<CartLine> cart = [];
  List<Map<String, Object?>> results = [];
  List<Map<String, Object?>> suppliers = [];
  int? supplierId;

  double get total => cart.fold(0.0, (a, l) => a + l.total);

  @override
  void initState() {
    super.initState();
    AppDb.I.suppliers().then((r) {
      if (mounted) setState(() => suppliers = r);
    });
  }

  Future<void> _search(String v) async {
    final r = v.trim().isEmpty ? <Map<String, Object?>>[] : await AppDb.I.products(v);
    if (mounted) setState(() => results = r.take(6).toList());
  }

  void _add(Map<String, Object?> p) {
    final id = p['id'] as int;
    setState(() {
      final i = cart.indexWhere((l) => l.productId == id);
      if (i >= 0) {
        cart[i].qty += 1;
      } else {
        cart.add(CartLine(id, p['name'] as String, 1, (p['cost_price'] as num).toDouble()));
      }
      search.clear();
      results = [];
    });
  }

  Future<void> _onSubmit(String v) async {
    final b = await AppDb.I.productByBarcode(v);
    if (b != null) return _add(b);
    if (results.length == 1) return _add(results.first);
    if (mounted) toast(context, 'لم يتم العثور على الصنف (أضفه من شاشة الأصناف أولاً)');
  }

  Future<void> _save() async {
    try {
      final p = paid.text.trim().isEmpty ? total : toD(paid.text);
      final id = await AppDb.I.createPurchase(
          supplierId: supplierId, lines: cart, paid: p, userId: Session.id);
      if (!mounted) return;
      setState(() {
        cart.clear();
        paid.clear();
      });
      toast(context, 'تم حفظ فاتورة الشراء رقم $id وتحديث المخزون');
    } catch (e) {
      if (mounted) toast(context, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('فاتورة شراء')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: DropdownButtonFormField<int?>(
              value: supplierId,
              decoration: const InputDecoration(labelText: 'المورد', border: OutlineInputBorder(), isDense: true),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('بدون مورد')),
                for (final s in suppliers)
                  DropdownMenuItem<int?>(value: s['id'] as int, child: Text(s['name'] as String)),
              ],
              onChanged: (v) => setState(() => supplierId = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: search,
              onChanged: _search,
              onSubmitted: _onSubmit,
              decoration: const InputDecoration(
                  hintText: 'ابحث عن صنف بالاسم أو الباركود',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder()),
            ),
          ),
          if (results.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              child: ListView(shrinkWrap: true, children: [
                for (final r in results)
                  ListTile(dense: true, title: Text(r['name'] as String), onTap: () => _add(r)),
              ]),
            ),
          Expanded(
            child: cart.isEmpty
                ? const Center(child: Text('أضف أصناف الفاتورة'))
                : ListView.builder(
                    itemCount: cart.length,
                    itemBuilder: (_, i) {
                      final l = cart[i];
                      return ListTile(
                        title: Text(l.name),
                        subtitle: Text('تكلفة ${fmt(l.price)} × ${fmt(l.qty)} = ${fmt(l.total)}   (اضغط للكمية، مطوّلاً للتكلفة)'),
                        leading: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => setState(() => cart.removeAt(i))),
                        onTap: () async {
                          final v = await askText(context, 'الكمية', initial: fmt(l.qty));
                          if (v != null && toD(v) > 0) setState(() => l.qty = toD(v));
                        },
                        onLongPress: () async {
                          final v = await askText(context, 'سعر التكلفة', initial: fmt(l.price));
                          if (v != null) setState(() => l.price = toD(v));
                        },
                      );
                    },
                  ),
          ),
          Card(
            margin: const EdgeInsets.all(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                  child: TextField(
                      controller: paid,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'المدفوع (فارغ = الكل)', isDense: true, border: OutlineInputBorder())),
                ),
                const SizedBox(width: 8),
                Text('الإجمالي: ${fmt(total)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                FilledButton(onPressed: cart.isEmpty ? null : _save, child: const Text('اعتماد')),
              ]),
            ),
          ),
        ]),
      );
}
