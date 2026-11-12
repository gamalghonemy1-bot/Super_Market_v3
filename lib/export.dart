import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'db.dart';
import 'reports.dart';
import 'session.dart';

String esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

const _css =
    'body{font-family:sans-serif;direction:rtl;text-align:right;margin:8px}'
    'table{width:100%;border-collapse:collapse;font-size:13px}'
    'th,td{border:1px solid #999;padding:4px}th{background:#e8f5e9}'
    'h2,h3,p{margin:4px 0}';

String reportHtml(String store, Report r, String period) {
  final b = StringBuffer('<html dir="rtl" lang="ar"><head><meta charset="utf-8"><style>$_css</style></head><body>');
  b.write('<h2>${esc(store)}</h2><h3>${esc(r.title)}</h3><p>${esc(period)}</p><table><tr>');
  for (final h in r.headers) {
    b.write('<th>${esc(h)}</th>');
  }
  b.write('</tr>');
  for (final row in r.rows) {
    b.write('<tr>${row.map((c) => '<td>${esc(c)}</td>').join()}</tr>');
  }
  b.write('</table>');
  for (final t in r.totals) {
    b.write('<p><b>${esc(t)}</b></p>');
  }
  b.write('</body></html>');
  return b.toString();
}

String reportCsv(Report r) {
  String q(String c) => '"${c.replaceAll('"', '""')}"';
  final lines = <List<String>>[r.headers, ...r.rows, ...r.totals.map((t) => [t])];
  return '\uFEFF${lines.map((l) => l.map(q).join(',')).join('\r\n')}';
}

Future<String> _tmpFile(String name, List<int> bytes) async {
  final d = await getTemporaryDirectory();
  final f = File('${d.path}/$name');
  await f.writeAsBytes(bytes, flush: true);
  return f.path;
}

Future<void> shareFile(String name, List<int> bytes) async {
  final p = await _tmpFile(name, bytes);
  await Share.shareXFiles([XFile(p)]);
}

Future<PdfPageFormat> _format() async {
  final paper = await AppDb.I.getSetting('paper');
  return paper == '80mm'
      ? const PdfPageFormat(80 * PdfPageFormat.mm, 220 * PdfPageFormat.mm, marginAll: 3 * PdfPageFormat.mm)
      : PdfPageFormat.a4;
}

Future<void> printHtml(String html, String name) async {
  final f = await _format();
  await Printing.layoutPdf(
      name: name, onLayout: (_) => Printing.convertHtml(format: f, html: html));
}

Future<void> sharePdfHtml(String html, String name) async {
  final f = await _format();
  final bytes = await Printing.convertHtml(format: f, html: html);
  await Printing.sharePdf(bytes: bytes, filename: name);
}

Future<String> invoiceHtml(Map<String, Object?> s, List<Map<String, Object?>> items) async {
  final store = await AppDb.I.getSetting('store_name');
  final branch = await AppDb.I.getSetting('branch');
  final footer = await AppDb.I.getSetting('invoice_footer');
  final b = StringBuffer('<html dir="rtl" lang="ar"><head><meta charset="utf-8"><style>$_css</style></head><body>');
  b.write('<h2 style="text-align:center">${esc(store)}</h2><p style="text-align:center">${esc(branch)}</p>');
  b.write('<p>فاتورة رقم: ${s['id']}<br>التاريخ: ${s['created_at']}</p>');
  b.write('<table><tr><th>الصنف</th><th>الكمية</th><th>السعر</th><th>الإجمالي</th></tr>');
  for (final i in items) {
    final q = (i['qty'] as num).toDouble();
    final p = (i['price'] as num).toDouble();
    b.write('<tr><td>${esc('${i['name']}')}</td><td>${fmt(q)}</td><td>${fmt(p)}</td><td>${fmt(q * p)}</td></tr>');
  }
  b.write('</table>');
  b.write('<p>الخصم: ${fmt(s['discount'] as num)}</p>');
  b.write('<h3>الإجمالي: ${fmt(s['total'] as num)} ج.م</h3>');
  b.write('<p>المدفوع: ${fmt(s['paid'] as num)} | المتبقي: ${fmt(s['remaining'] as num)} | ${esc('${s['method']}')}</p>');
  if (footer.trim().isNotEmpty) b.write('<p style="text-align:center">${esc(footer)}</p>');
  b.write('</body></html>');
  return b.toString();
}
