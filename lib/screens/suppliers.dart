import 'package:flutter/material.dart';
import '../db.dart';
import '../session.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});
  @override
  State<SuppliersScreen> createState() => _SuppliersState();
}

class _SuppliersState extends State<SuppliersScreen> {
  List<Map<String, Object?>> rows = [];
  final Map<int, double> bal = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await AppDb.I.suppliers();
    for (final s in r) {
      bal[s['id'] as int] = await AppDb.I.supplierBalance(s['id'] as int);
    }
    if (mounted) setState(() => rows = r);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الموردون')),
        floatingActionButton: FloatingActionButton(
            onPressed: () async {
              if (await editSupplier(context, null) == true) _load();
            },
            child: const Icon(Icons.add)),
        body: rows.isEmpty
            ? const Center(child: Text('لا يوجد موردون'))
            : ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final s = rows[i];
                  final b = bal[s['id']] ?? 0;
                  return ListTile(
                    title: Text(s['name'] as String),
                    subtitle: Text('${s['phone'] ?? ''}'),
                    trailing: Text(b > 0 ? 'مستحق: ${fmt(b)}' : 'لا مستحقات',
                        style: TextStyle(color: b > 0 ? Colors.red : Colors.green)),
                    onTap: () async {
                      await Navigator.push(context,
                          MaterialPageRoute(builder: (_) => SupplierStatementScreen(supplier: s)));
                      _load();
                    },
                  );
                },
              ),
      );
}

Future<bool?> editSupplier(BuildContext c, Map<String, Object?>? s) {
  final n = TextEditingController(text: '${s?['name'] ?? ''}');
  final p = TextEditingController(text: '${s?['phone'] ?? ''}');
  final a = TextEditingController(text: '${s?['address'] ?? ''}');
  return showDialog<bool>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text(s == null ? 'إضافة مورد' : 'تعديل مورد'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: n, decoration: const InputDecoration(labelText: 'اسم المورد')),
        TextField(controller: p, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
        TextField(controller: a, decoration: const InputDecoration(labelText: 'العنوان')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () async {
            try {
              await AppDb.I.saveSupplier({
                if (s != null) 'id': s['id'],
                'name': n.text.trim(),
                'phone': p.text.trim(),
                'address': a.text.trim(),
              });
              if (ctx.mounted) Navigator.pop(ctx, true);
            } catch (e) {
              if (ctx.mounted) toast(ctx, errText(e));
            }
          },
          child: const Text('حفظ'),
        ),
      ],
    ),
  );
}

class SupplierStatementScreen extends StatefulWidget {
  final Map<String, Object?> supplier;
  const SupplierStatementScreen({super.key, required this.supplier});
  @override
  State<SupplierStatementScreen> createState() => _StatementState();
}

class _StatementState extends State<SupplierStatementScreen> {
  List<Map<String, Object?>> rows = [];
  double balance = 0;

  int get id => widget.supplier['id'] as int;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await AppDb.I.supplierStatement(id);
    final b = await AppDb.I.supplierBalance(id);
    if (mounted) {
      setState(() {
        rows = r;
        balance = b;
      });
    }
  }

  Future<void> _pay() async {
    final v = await askText(context, 'مبلغ الدفعة للمورد');
    if (v == null) return;
    try {
      await AppDb.I.paySupplier(id, toD(v), Session.id);
      _load();
    } catch (e) {
      if (mounted) toast(context, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('كشف حساب: ${widget.supplier['name']}')),
        body: Column(children: [
          Card(
            margin: const EdgeInsets.all(8),
            child: ListTile(
              title: Text('المستحق للمورد: ${fmt(balance)} ج.م',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: FilledButton(onPressed: balance > 0 ? _pay : null, child: const Text('سداد دفعة')),
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('لا توجد حركات'))
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      return ListTile(
                        dense: true,
                        title: Text('${r['title']}'),
                        subtitle: Text('${r['created_at']}'),
                        trailing: Text('عليك: ${fmt(r['debit'] as num)}  |  دفعت: ${fmt(r['credit'] as num)}'),
                      );
                    },
                  ),
          ),
        ]),
      );
}
