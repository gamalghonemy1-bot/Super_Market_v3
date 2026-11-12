import 'db.dart';
import 'session.dart';

class Report {
  final String title;
  final List<String> headers;
  final List<List<String>> rows;
  final List<String> totals;
  Report(this.title, this.headers, this.rows, [this.totals = const []]);
}

const reportKinds = <String, String>{
  'sales': 'تقرير المبيعات',
  'items': 'مبيعات كل صنف',
  'sellers': 'مبيعات البائعين',
  'purchases': 'تقرير المشتريات',
  'inventory': 'تقرير المخزون',
  'profit': 'تقرير الأرباح',
  'expenses': 'تقرير المصروفات',
  'returns': 'تقرير المرتجعات',
};

double _n(Object? v) => ((v ?? 0) as num).toDouble();

Future<Report> buildReport(String kind, String from, String to) async {
  final d = await AppDb.I.db;
  final a = [from, to];
  const between = 'date(created_at) BETWEEN ? AND ?';
  switch (kind) {
    case 'sales':
      final r = await d.rawQuery(
          "SELECT date(created_at) d, COUNT(*) c, SUM(subtotal) sub, SUM(discount) disc, SUM(total) t FROM sales WHERE status='active' AND $between GROUP BY d ORDER BY d",
          a);
      final t = r.fold<double>(0, (x, e) => x + _n(e['t']));
      final c = r.fold<double>(0, (x, e) => x + _n(e['c']));
      return Report(
          reportKinds[kind]!,
          ['التاريخ', 'عدد الفواتير', 'الإجمالي قبل الخصم', 'الخصم', 'الصافي'],
          [for (final e in r) ['${e['d']}', fmt(_n(e['c'])), fmt(_n(e['sub'])), fmt(_n(e['disc'])), fmt(_n(e['t']))]],
          ['عدد الفواتير: ${fmt(c)}', 'صافي المبيعات: ${fmt(t)} ج.م']);
    case 'items':
      final r = await d.rawQuery(
          "SELECT si.name n, SUM(si.qty) q, SUM(si.price*si.qty) amt, SUM((si.price-si.cost_price)*si.qty) pr FROM sale_items si JOIN sales s ON s.id=si.sale_id WHERE s.status='active' AND date(s.created_at) BETWEEN ? AND ? GROUP BY si.product_id ORDER BY amt DESC",
          a);
      return Report(
          reportKinds[kind]!,
          ['الصنف', 'الكمية', 'المبيعات', 'الربح (قبل الخصم)'],
          [for (final e in r) ['${e['n']}', fmt(_n(e['q'])), fmt(_n(e['amt'])), fmt(_n(e['pr']))]],
          ['إجمالي المبيعات: ${fmt(r.fold<double>(0, (x, e) => x + _n(e['amt'])))} ج.م']);
    case 'sellers':
      final r = await d.rawQuery(
          "SELECT COALESCE(u.full_name,u.username,'-') n, COUNT(*) c, SUM(s.total) t FROM sales s LEFT JOIN users u ON u.id=s.user_id WHERE s.status='active' AND date(s.created_at) BETWEEN ? AND ? GROUP BY s.user_id ORDER BY t DESC",
          a);
      return Report(reportKinds[kind]!, ['البائع', 'عدد الفواتير', 'إجمالي المبيعات'],
          [for (final e in r) ['${e['n']}', fmt(_n(e['c'])), fmt(_n(e['t']))]]);
    case 'purchases':
      final r = await d.rawQuery(
          "SELECT p.created_at ca, COALESCE(sp.name,'-') n, p.total, p.paid, p.remaining FROM purchases p LEFT JOIN suppliers sp ON sp.id=p.supplier_id WHERE date(p.created_at) BETWEEN ? AND ? ORDER BY p.id",
          a);
      return Report(
          reportKinds[kind]!,
          ['التاريخ', 'المورد', 'الإجمالي', 'المدفوع', 'المتبقي'],
          [for (final e in r) ['${e['ca']}', '${e['n']}', fmt(_n(e['total'])), fmt(_n(e['paid'])), fmt(_n(e['remaining']))]],
          ['إجمالي المشتريات: ${fmt(r.fold<double>(0, (x, e) => x + _n(e['total'])))} ج.م']);
    case 'inventory':
      final r = await d.query('products', orderBy: 'name');
      final v = r.fold<double>(0, (x, e) => x + _n(e['qty']) * _n(e['cost_price']));
      return Report(
          reportKinds[kind]!,
          ['الصنف', 'الكمية', 'الوحدة', 'سعر الشراء', 'القيمة'],
          [for (final e in r) ['${e['name']}', fmt(_n(e['qty'])), '${e['unit'] ?? ''}', fmt(_n(e['cost_price'])), fmt(_n(e['qty']) * _n(e['cost_price']))]],
          ['قيمة المخزون: ${fmt(v)} ج.م']);
    case 'profit':
      Future<double> one(String sql) async =>
          _n((await d.rawQuery(sql, a)).first.values.first);
      final sales = await one("SELECT COALESCE(SUM(total),0) FROM sales WHERE status='active' AND $between");
      final cogs = await one("SELECT COALESCE(SUM(si.cost_price*si.qty),0) FROM sale_items si JOIN sales s ON s.id=si.sale_id WHERE s.status='active' AND date(s.created_at) BETWEEN ? AND ?");
      final ret = await one('SELECT COALESCE(SUM(total),0) FROM returns WHERE $between');
      final retCost = await one('SELECT COALESCE(SUM(ri.cost_price*ri.qty),0) FROM return_items ri JOIN returns r ON r.id=ri.return_id WHERE ri.restock=1 AND date(r.created_at) BETWEEN ? AND ?');
      final exp = await one('SELECT COALESCE(SUM(amount),0) FROM expenses WHERE $between');
      final net = sales - ret - (cogs - retCost) - exp;
      return Report(reportKinds[kind]!, ['البند', 'القيمة (ج.م)'], [
        ['إجمالي المبيعات بعد الخصومات', fmt(sales)],
        ['المرتجعات', fmt(ret)],
        ['تكلفة البضاعة المباعة', fmt(cogs - retCost)],
        ['المصروفات التشغيلية', fmt(exp)],
        ['صافي الربح', fmt(net)],
      ]);
    case 'expenses':
      final r = await d.rawQuery('SELECT * FROM expenses WHERE $between ORDER BY id', a);
      return Report(reportKinds[kind]!, ['التاريخ', 'البيان', 'المبلغ'],
          [for (final e in r) ['${e['created_at']}', '${e['title']}', fmt(_n(e['amount']))]],
          ['إجمالي المصروفات: ${fmt(r.fold<double>(0, (x, e) => x + _n(e['amount'])))} ج.م']);
    case 'returns':
      final r = await d.rawQuery('SELECT * FROM returns WHERE $between ORDER BY id', a);
      return Report(reportKinds[kind]!, ['التاريخ', 'رقم الفاتورة', 'السبب', 'القيمة'],
          [for (final e in r) ['${e['created_at']}', '${e['sale_id']}', '${e['reason']}', fmt(_n(e['total']))]],
          ['إجمالي المرتجعات: ${fmt(r.fold<double>(0, (x, e) => x + _n(e['total'])))} ج.م']);
  }
  throw Exception('تقرير غير معروف');
}
