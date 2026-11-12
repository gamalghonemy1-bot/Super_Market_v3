import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:rif_market/backup.dart';
import 'package:rif_market/db.dart';
import 'package:rif_market/reports.dart';
import 'package:rif_market/voice_parser.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    await AppDb.I.reset();
    AppDb.testPath = inMemoryDatabasePath;
  });

  Future<int> addProduct(String name, String barcode, {double qty = 100}) async {
    await AppDb.I.saveProduct({
      'name': name, 'barcode': barcode, 'unit': 'قطعة',
      'cost_price': 10.0, 'sell_price': 15.0, 'qty': qty, 'min_qty': 5.0
    }, 1);
    return (await AppDb.I.productByBarcode(barcode))!['id'] as int;
  }

  test('voice parser handles the spec example', () {
    final products = [
      {'id': 1, 'name': 'سكر'},
      {'id': 2, 'name': 'زيت عباد الشمس'},
      {'id': 3, 'name': 'شاي ليبتون'},
    ];
    final r = parseVoice('أضف 2 كيلو سكر و3 زجاجات زيت وعلبة شاي', products);
    expect(r.length, 3);
    expect(r[0].product!['id'], 1);
    expect(r[0].qty, 2);
    expect(r[1].product!['id'], 2);
    expect(r[1].qty, 3);
    expect(r[2].product!['id'], 3);
    expect(r[2].qty, 1);
  });

  test('voice parser flags unknown items and never invents products', () {
    final r = parseVoice('اضف اتنين كيلو سكر و علبه جبنه', [
      {'id': 1, 'name': 'سكر'}
    ]);
    expect(r[0].qty, 2);
    expect(r[0].product, isNotNull);
    expect(r[1].product, isNull);
  });

  test('reports: items and profit', () async {
    final id = await addProduct('سكر', '111');
    await AppDb.I.createSale(
        lines: [CartLine(id, 'سكر', 3, 15)], discount: 0, paid: 45, method: 'نقدي', userId: 1);
    await AppDb.I.addExpense('كهرباء', 5, 1);
    final today = nowStr().substring(0, 10);
    final items = await buildReport('items', today, today);
    expect(items.rows.first[0], 'سكر');
    expect(items.rows.first[1], '3');
    final profit = await buildReport('profit', today, today);
    final net = profit.rows.firstWhere((r) => r[0] == 'صافي الربح');
    expect(net[1], '10'); // 45 - 30 - 5
    final sales = await buildReport('sales', today, today);
    expect(sales.rows.first[4], '45');
  });

  test('backup and restore bring back the old data', () async {
    final tmp = Directory.systemTemp.createTempSync('rif_test');
    addTearDown(() async {
      await AppDb.I.reset();
      tmp.deleteSync(recursive: true);
    });
    await AppDb.I.reset();
    AppDb.testPath = '${tmp.path}/t.db';
    await addProduct('سكر', '111');
    final bak = await BackupService.create(tmp, 'b.db');
    await addProduct('ارز', '222');
    expect((await AppDb.I.products()).length, 2);
    await BackupService.restore(bak, tmp);
    final after = await AppDb.I.products();
    expect(after.length, 1);
    expect(after.first['name'], 'سكر');
  });

  test('restore rejects a non-database file', () async {
    final tmp = Directory.systemTemp.createTempSync('rif_test2');
    addTearDown(() async {
      await AppDb.I.reset();
      tmp.deleteSync(recursive: true);
    });
    await AppDb.I.reset();
    AppDb.testPath = '${tmp.path}/t.db';
    await addProduct('سكر', '111');
    final bad = File('${tmp.path}/bad.db')..writeAsStringSync('not a database');
    expect(() => BackupService.restore(bad, tmp), throwsException);
    expect((await AppDb.I.products()).length, 1);
  });
}
