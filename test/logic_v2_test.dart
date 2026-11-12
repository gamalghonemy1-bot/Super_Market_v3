import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:rif_market/db.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    await AppDb.I.reset();
    AppDb.testPath = inMemoryDatabasePath;
  });

  Future<int> addProduct({double qty = 100}) async {
    await AppDb.I.saveProduct({
      'name': 'سكر', 'barcode': '111', 'unit': 'كيلو',
      'cost_price': 10.0, 'sell_price': 15.0, 'qty': qty, 'min_qty': 5.0
    }, 1);
    return (await AppDb.I.productByBarcode('111'))!['id'] as int;
  }

  test('purchase updates stock, cost and supplier balance', () async {
    await AppDb.I.saveSupplier({'name': 'مورد', 'phone': '010'});
    final sup = (await AppDb.I.suppliers()).first['id'] as int;
    final id = await addProduct(qty: 0);
    await AppDb.I.createPurchase(
        supplierId: sup, lines: [CartLine(id, 'سكر', 10, 12)], paid: 50, userId: 1);
    final p = (await AppDb.I.productByBarcode('111'))!;
    expect(p['qty'], 10);
    expect(p['cost_price'], 12);
    expect(await AppDb.I.supplierBalance(sup), 70);
    await AppDb.I.paySupplier(sup, 70, 1);
    expect(await AppDb.I.supplierBalance(sup), 0);
    expect(() => AppDb.I.paySupplier(sup, 1, 1), throwsException);
  });

  test('return restocks and adjusts profit; over-return rejected', () async {
    final id = await addProduct();
    final sid = await AppDb.I.createSale(
        lines: [CartLine(id, 'سكر', 4, 15)], discount: 0, paid: 60, method: 'نقدي', userId: 1);
    final item = (await AppDb.I.returnableItems(sid)).first['id'] as int;
    await AppDb.I.createReturn(
        saleId: sid, qtys: {item: 1}, reason: 'تالف', restock: true, userId: 1);
    expect((await AppDb.I.productByBarcode('111'))!['qty'], 97);
    expect((await AppDb.I.dashboard())['profit'], 15);
    expect(
        () => AppDb.I.createReturn(
            saleId: sid, qtys: {item: 4}, reason: 'x', restock: true, userId: 1),
        throwsException);
  });

  test('stocktake records shortage movement', () async {
    final id = await addProduct(qty: 10);
    final diff = await AppDb.I.stocktake(id, 8, 1);
    expect(diff, -2);
    expect((await AppDb.I.productByBarcode('111'))!['qty'], 8);
    final m = await AppDb.I.movements(id);
    expect(m.first['type'], 'shortage');
  });

  test('shift expected cash and difference', () async {
    final id = await addProduct();
    await AppDb.I.startShift(100, 1);
    expect(() => AppDb.I.startShift(50, 1), throwsException);
    await AppDb.I.createSale(
        lines: [CartLine(id, 'سكر', 3, 15)], discount: 0, paid: 45, method: 'نقدي', userId: 1);
    await AppDb.I.addTreasury('deposit', 20, '', 1);
    await AppDb.I.addTreasury('withdraw', 10, '', 1);
    await AppDb.I.addExpense('كهرباء', 5, 1);
    expect(await AppDb.I.cashBalance(), 150);
    final diff = await AppDb.I.closeShift(148, '', 1);
    expect(diff, -2);
    expect(await AppDb.I.openShift(), isNull);
    expect(await AppDb.I.cashBalance(), 148);
    // المصروف يخصم من صافي الربح: 45 - 30 - 5
    expect((await AppDb.I.dashboard())['profit'], 10);
  });

  test('seller account can log in', () async {
    await AppDb.I.addUser('ali', '1234', 'علي', 'seller');
    final u = await AppDb.I.login('ali', '1234');
    expect(u, isNotNull);
    expect(u!['role'], 'seller');
  });
}
