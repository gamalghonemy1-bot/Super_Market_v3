import 'dart:convert';
import 'package:flutter/material.dart';
import '../db.dart';
import '../export.dart';
import '../reports.dart';
import '../session.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsState();
}

class _ReportsState extends State<ReportsScreen> {
  String kind = 'sales';
  String period = 'day';
  late DateTime from = DateTime.now();
  late DateTime to = DateTime.now();
  Report? rep;
  bool busy = false;

  String _d(DateTime x) => x.toString().substring(0, 10);
  String get periodText => 'الفترة: ${_d(from)} إلى ${_d(to)}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _setPeriod(String p) {
    final n = DateTime.now();
    period = p;
    to = n;
    if (p == 'day') from = n;
    if (p == 'week') from = n.subtract(const Duration(days: 6));
    if (p == 'month') from = DateTime(n.year, n.month, 1);
    if (p == 'year') from = DateTime(n.year, 1, 1);
  }

  Future<void> _load() async {
    setState(() => busy = true);
    try {
      final r = await buildReport(kind, _d(from), _d(to));
      if (mounted) setState(() => rep = r);
    } catch (e) {
      if (mounted) toast(context, errText(e));
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _custom() async {
    final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 1)),
        initialDateRange: DateTimeRange(start: from, end: to));
    if (r == null) return;
    setState(() {
      period = 'custom';
      from = r.start;
      to = r.end;
    });
    _load();
  }

  Future<void> _pdf() async {
    if (rep == null) return;
    try {
      final store = await AppDb.I.getSetting('store_name');
      final html = reportHtml(store, rep!, periodText);
      await sharePdfHtml(html, '${rep!.title}.pdf');
    } catch (e) {
      if (mounted) toast(context, 'تعذر إنشاء PDF: ${errText(e)}');
    }
  }

  Future<void> _print() async {
    if (rep == null) return;
    final store = await AppDb.I.getSetting('store_name');
    try {
      await printHtml(reportHtml(store, rep!, periodText), rep!.title);
    } catch (e) {
      if (mounted) toast(context, 'تعذرت الطباعة: ${errText(e)}');
    }
  }

  Future<void> _csv() async {
    if (rep == null) return;
    try {
      await shareFile('${rep!.title}.csv', utf8.encode(reportCsv(rep!)));
    } catch (e) {
      if (mounted) toast(context, 'تعذر التصدير: ${errText(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = rep;
    return Scaffold(
      appBar: AppBar(title: const Text('التقارير')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: DropdownButtonFormField<String>(
            value: kind,
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
            items: [for (final e in reportKinds.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) {
              kind = v!;
              _load();
            },
          ),
        ),
        Wrap(spacing: 6, children: [
          for (final e in {'day': 'اليوم', 'week': 'أسبوع', 'month': 'شهر', 'year': 'سنة'}.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: period == e.key,
              onSelected: (_) {
                setState(() => _setPeriod(e.key));
                _load();
              },
            ),
          ChoiceChip(label: const Text('فترة مخصصة'), selected: period == 'custom', onSelected: (_) => _custom()),
        ]),
        Padding(padding: const EdgeInsets.all(4), child: Text(periodText, style: const TextStyle(fontSize: 12))),
        if (busy) const LinearProgressIndicator(),
        Expanded(
          child: r == null
              ? const SizedBox()
              : r.rows.isEmpty
                  ? const Center(child: Text('لا توجد بيانات في هذه الفترة'))
                  : SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columnSpacing: 16,
                          columns: [for (final h in r.headers) DataColumn(label: Text(h))],
                          rows: [
                            for (final row in r.rows) DataRow(cells: [for (final c in row) DataCell(Text(c))])
                          ],
                        ),
                      ),
                    ),
        ),
        if (r != null && r.totals.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(r.totals.join('   |   '), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(spacing: 8, children: [
            FilledButton.icon(onPressed: _pdf, icon: const Icon(Icons.picture_as_pdf), label: const Text('PDF')),
            FilledButton.tonalIcon(onPressed: _csv, icon: const Icon(Icons.table_chart), label: const Text('Excel')),
            FilledButton.tonalIcon(onPressed: _print, icon: const Icon(Icons.print), label: const Text('طباعة')),
          ]),
        ),
      ]),
    );
  }
}
