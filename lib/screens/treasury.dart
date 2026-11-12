import 'package:flutter/material.dart';
import '../db.dart';
import '../session.dart';

class TreasuryScreen extends StatefulWidget {
  const TreasuryScreen({super.key});
  @override
  State<TreasuryScreen> createState() => _TreasuryState();
}

class _TreasuryState extends State<TreasuryScreen> {
  Map<String, Object?>? shift;
  double expected = 0;
  List<Map<String, Object?>> history = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await AppDb.I.openShift();
    final e = s == null ? 0.0 : await AppDb.I.expectedCash(s);
    final h = Session.isAdmin ? await AppDb.I.shifts() : <Map<String, Object?>>[];
    if (mounted) {
      setState(() {
        shift = s;
        expected = e;
        history = h;
      });
    }
  }

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
      _load();
    } catch (e) {
      if (mounted) toast(context, errText(e));
    }
  }

  Future<void> _open() async {
    final v = await askText(context, 'رصيد بداية الوردية');
    if (v == null) return;
    await _run(() => AppDb.I.startShift(toD(v), Session.id));
  }

  Future<void> _close() async {
    final v = await askText(context, 'المبلغ الفعلي الموجود في الدرج');
    if (v == null) return;
    try {
      final diff = await AppDb.I.closeShift(toD(v), '', Session.id);
      if (!mounted) return;
      toast(
          context,
          Session.isAdmin
              ? (diff == 0 ? 'تم الإقفال بدون فرق' : diff < 0 ? 'تم الإقفال - عجز ${fmt(-diff)}' : 'تم الإقفال - زيادة ${fmt(diff)}')
              : 'تم إقفال الوردية');
      _load();
    } catch (e) {
      if (mounted) toast(context, errText(e));
    }
  }

  Future<void> _move(String type) async {
    final v = await askText(context, type == 'deposit' ? 'مبلغ الإيداع' : 'مبلغ السحب');
    if (v == null) return;
    await _run(() => AppDb.I.addTreasury(type, toD(v), '', Session.id));
  }

  Future<void> _expense() async {
    final t = await askText(context, 'بيان المصروف');
    if (t == null || !mounted) return;
    final a = await askText(context, 'المبلغ');
    if (a == null) return;
    await _run(() => AppDb.I.addExpense(t, toD(a), Session.id));
  }

  @override
  Widget build(BuildContext context) {
    final admin = Session.isAdmin;
    return Scaffold(
      appBar: AppBar(title: const Text('الخزينة والورديات')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          child: ListTile(
            title: Text(shift == null ? 'لا توجد وردية مفتوحة' : 'وردية مفتوحة منذ ${shift!['opened_at']}'),
            subtitle: shift == null
                ? null
                : Text(admin
                    ? 'رصيد البداية: ${fmt(shift!['opening'] as num)} | المتوقع الآن: ${fmt(expected)}'
                    : 'رصيد البداية: ${fmt(shift!['opening'] as num)}'),
          ),
        ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (shift == null) FilledButton.icon(onPressed: _open, icon: const Icon(Icons.lock_open), label: const Text('فتح وردية')),
          if (shift != null) FilledButton.icon(onPressed: _close, icon: const Icon(Icons.lock), label: const Text('إقفال الوردية')),
          if (admin && shift != null) ...[
            FilledButton.tonalIcon(onPressed: () => _move('deposit'), icon: const Icon(Icons.add), label: const Text('إيداع')),
            FilledButton.tonalIcon(onPressed: () => _move('withdraw'), icon: const Icon(Icons.remove), label: const Text('سحب')),
          ],
          if (admin) FilledButton.tonalIcon(onPressed: _expense, icon: const Icon(Icons.payments), label: const Text('مصروف')),
        ]),
        if (admin) ...[
          const Divider(height: 32),
          const Text('تقرير فروق الخزينة (آخر الورديات)', style: TextStyle(fontWeight: FontWeight.bold)),
          for (final h in history.where((e) => e['closed_at'] != null))
            ListTile(
              dense: true,
              title: Text('${h['opened_at']}  ←  ${h['closed_at']}'),
              subtitle: Text('${h['user_name'] ?? ''} | متوقع ${fmt(h['expected'] as num)} | فعلي ${fmt(h['actual'] as num)}'),
              trailing: Text(
                  (h['diff'] as num) == 0 ? 'بدون فرق' : 'فرق ${fmt(h['diff'] as num)}',
                  style: TextStyle(color: (h['diff'] as num) == 0 ? Colors.green : Colors.red)),
            ),
        ],
      ]),
    );
  }
}
