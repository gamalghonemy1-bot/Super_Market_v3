import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

String nowStr() => DateTime.now().toString().substring(0, 19);

class CartLine {
  final int productId;
  final String name;
  double qty;
  double price;
  CartLine(this.productId, this.name, this.qty, this.price);
  double get total => qty * price;
}

const _schema = <String>[
  'CREATE TABLE users(id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT UNIQUE NOT NULL, password_hash TEXT NOT NULL, full_name TEXT, role TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1)',
  'CREATE TABLE categories(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL)',
  'CREATE TABLE suppliers(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT, address TEXT)',
  "CREATE TABLE products(id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT, name TEXT NOT NULL, barcode TEXT UNIQUE, category_id INTEGER, unit TEXT DEFAULT 'قطعة', cost_price REAL NOT NULL DEFAULT 0, sell_price REAL NOT NULL DEFAULT 0, qty REAL NOT NULL DEFAULT 0, min_qty REAL NOT NULL DEFAULT 0, supplier_id INTEGER, expiry_date TEXT, created_at TEXT)",
  "CREATE TABLE sales(id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, subtotal REAL, discount REAL, total REAL, paid REAL, remaining REAL, method TEXT, status TEXT NOT NULL DEFAULT 'active', cancel_reason TEXT, cancelled_by INTEGER, created_at TEXT)",
  'CREATE TABLE sale_items(id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER NOT NULL, product_id INTEGER NOT NULL, name TEXT, qty REAL, price REAL, cost_price REAL, FOREIGN KEY(sale_id) REFERENCES sales(id), FOREIGN KEY(product_id) REFERENCES products(id))',
  'CREATE TABLE stock_movements(id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL, type TEXT, qty REAL, ref_id INTEGER, note TEXT, user_id INTEGER, created_at TEXT)',
  'CREATE TABLE purchases(id INTEGER PRIMARY KEY AUTOINCREMENT, supplier_id INTEGER, total REAL, paid REAL, remaining REAL, user_id INTEGER, created_at TEXT)',
  'CREATE TABLE purchase_items(id INTEGER PRIMARY KEY AUTOINCREMENT, purchase_id INTEGER, product_id INTEGER, qty REAL, cost_price REAL)',
  'CREATE TABLE expenses(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, amount REAL, user_id INTEGER, created_at TEXT)',
  'CREATE TABLE treasury(id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT, amount REAL, note TEXT, user_id INTEGER, created_at TEXT)',
  'CREATE TABLE returns(id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER, reason TEXT, total REAL, user_id INTEGER, created_at TEXT)',
  'CREATE TABLE return_items(id INTEGER PRIMARY KEY AUTOINCREMENT, return_id INTEGER, product_id INTEGER, qty REAL, price REAL, cost_price REAL, restock INTEGER)',
  'CREATE TABLE audit_log(id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, action TEXT, details TEXT, created_at TEXT)',
  'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT)',
  'CREATE TABLE supplier_payments(id INTEGER PRIMARY KEY AUTOINCREMENT, supplier_id INTEGER NOT NULL, amount REAL NOT NULL, user_id INTEGER, created_at TEXT)',
  'CREATE TABLE shifts(id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, opening REAL NOT NULL, opened_at TEXT NOT NULL, closed_at TEXT, expected REAL, actual REAL, diff REAL, note TEXT)',
];

class AppDb {
  AppDb._();
  static final AppDb I = AppDb._();
  static String? testPath;
  Database? _db;

  static String hash(String p) =>
      sha256.convert(utf8.encode('rif_v1:$p')).toString();

  Future<Database> get db async => _db ??= await _open();

  Future<void> reset() async {
    await _db?.close();
    _db = null;
  }

  Future<Database> _open() async {
    final path = testPath ?? join(await getDatabasesPath(), 'rif_market_v3.db');
    return openDatabase(
      path,
      version: 1,
      onConfigure: (d) async => await d.execute('PRAGMA foreign_keys = ON'),
      onCreate: (d, v) async {
        for (final s in _schema) {
          await d.execute(s);
        }
        await d.insert('users', {
          'username': 'admin',
          'password_hash': hash('admin123'),
          'full_name': 'أستاذ يوسف',
          'role': 'admin',
          'active': 1
        });
        final defaults = {
          'store_name': 'سوبر ماركت الريف المصري',
          'branch': 'فرع العاصمة',
          'manager': 'أستاذ يوسف',
          'dark': '0'
        };
        for (final e in defaults.entries) {
          await d.insert('settings', {'key': e.key, 'value': e.value});
        }
      },
    );
  }

  Future<String> getSetting(String k) async {
    final d = await db;
    final r = await d.query('settings', where: 'key=?', whereArgs: [k]);
    return r.isEmpty ? '' : (r.first['value'] as String? ?? '');
  }

  Future<void> setSetting(String k, String v) async {
    final d = await db;
    await d.insert('settings', {'key': k, 'value': v},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> audit(int? uid, String action, String details) async {
    final d = await db;
    await d.insert('audit_log', {
      'user_id': uid,
      'action': action,
      'details': details,
      'created_at': nowStr()
    });
  }

  Future<Map<String, Object?>?> login(String u, String p) async {
    final d = await db;
    final r = await d.query('users',
        where: 'username=? AND password_hash=? AND active=1',
        whereArgs: [u.trim(), hash(p)]);
    if (r.isEmpty) return null;
    await audit(r.first['id'] as int, 'login', u);
    return r.first;
  }

  Future<List<Map<String, Object?>>> users() async =>
      (await db).query('users', orderBy: 'id');

  Future<void> addUser(String u, String p, String name, String role) async {
    if (u.trim().isEmpty || p.length < 4) {
      throw Exception('اسم المستخدم مطلوب وكلمة المرور 4 أحرف على الأقل');
    }
    try {
      await (await db).insert('users', {
        'username': u.trim(),
        'password_hash': hash(p),
        'full_name': name,
        'role': role,
        'active': 1
      });
    } on DatabaseException {
      throw Exception('اسم المستخدم موجود بالفعل');
    }
  }

  Future<void> setPassword(int id, String p) async {
    if (p.length < 4) throw Exception('كلمة المرور 4 أحرف على الأقل');
    await (await db).update('users', {'password_hash': hash(p)},
        where: 'id=?', whereArgs: [id]);
  }

  Future<void> setActive(int id, bool a) async => (await db)
      .update('users', {'active': a ? 1 : 0}, where: 'id=?', whereArgs: [id]);

  Future<List<Map<String, Object?>>> products([String q = '']) async {
    final d = await db;
    if (q.trim().isEmpty) return d.query('products', orderBy: 'name');
    final like = '%${q.trim()}%';
    return d.query('products',
        where: 'name LIKE ? OR barcode LIKE ? OR code LIKE ?',
        whereArgs: [like, like, like],
        orderBy: 'name',
        limit: 50);
  }

  Future<Map<String, Object?>?> productByBarcode(String b) async {
    final r = await (await db)
        .query('products', where: 'barcode=?', whereArgs: [b.trim()]);
    return r.isEmpty ? null : r.first;
  }

  Future<void> saveProduct(Map<String, Object?> p, int uid) async {
    if ((p['name'] as String).trim().isEmpty) throw Exception('اسم الصنف مطلوب');
    if ((p['barcode'] as String?)?.trim().isEmpty ?? true) p['barcode'] = null;
    final d = await db;
    try {
      await d.transaction((t) async {
        final id = p['id'] as int?;
        final newQty = (p['qty'] as num).toDouble();
        if (id == null) {
          p.remove('id');
          p['created_at'] = nowStr();
          final nid = await t.insert('products', p);
          if (newQty != 0) {
            await t.insert('stock_movements', {
              'product_id': nid, 'type': 'opening', 'qty': newQty,
              'note': 'رصيد افتتاحي', 'user_id': uid, 'created_at': nowStr()
            });
          }
          await t.insert('audit_log', {'user_id': uid, 'action': 'product_add', 'details': '${p['name']}', 'created_at': nowStr()});
        } else {
          final old = await t.query('products', where: 'id=?', whereArgs: [id]);
          final oldQty = (old.first['qty'] as num).toDouble();
          await t.update('products', p, where: 'id=?', whereArgs: [id]);
          if (oldQty != newQty) {
            await t.insert('stock_movements', {
              'product_id': id, 'type': 'adjust', 'qty': newQty - oldQty,
              'note': 'تعديل يدوي', 'user_id': uid, 'created_at': nowStr()
            });
          }
          await t.insert('audit_log', {'user_id': uid, 'action': 'product_edit', 'details': '${p['name']}', 'created_at': nowStr()});
        }
      });
    } on DatabaseException {
      throw Exception('الباركود مستخدم لصنف آخر');
    }
  }

  Future<void> deleteProduct(int id, int uid) async {
    final d = await db;
    final used = await d.query('sale_items',
        where: 'product_id=?', whereArgs: [id], limit: 1);
    if (used.isNotEmpty) {
      throw Exception('لا يمكن حذف صنف عليه حركات بيع');
    }
    await d.transaction((t) async {
      await t.delete('stock_movements', where: 'product_id=?', whereArgs: [id]);
      await t.delete('products', where: 'id=?', whereArgs: [id]);
      await t.insert('audit_log', {'user_id': uid, 'action': 'product_delete', 'details': '$id', 'created_at': nowStr()});
    });
  }

  Future<int> createSale({
    required List<CartLine> lines,
    required double discount,
    required double paid,
    required String method,
    required int userId,
  }) async {
    if (lines.isEmpty) throw Exception('الفاتورة فارغة');
    final d = await db;
    return d.transaction<int>((t) async {
      double subtotal = 0;
      final costs = <int, double>{};
      for (final l in lines) {
        if (l.qty <= 0 || l.price < 0) throw Exception('كمية أو سعر غير صحيح: ${l.name}');
        final r = await t.query('products', where: 'id=?', whereArgs: [l.productId]);
        if (r.isEmpty) throw Exception('الصنف غير موجود: ${l.name}');
        final stock = (r.first['qty'] as num).toDouble();
        if (stock < l.qty) throw Exception('الكمية غير كافية للصنف ${l.name} (المتاح $stock)');
        costs[l.productId] = (r.first['cost_price'] as num).toDouble();
        subtotal += l.total;
      }
      if (discount < 0 || discount > subtotal) throw Exception('قيمة الخصم غير صحيحة');
      final total = subtotal - discount;
      final remaining = math.max(0.0, total - paid);
      final sid = await t.insert('sales', {
        'user_id': userId, 'subtotal': subtotal, 'discount': discount,
        'total': total, 'paid': paid, 'remaining': remaining,
        'method': method, 'status': 'active', 'created_at': nowStr()
      });
      for (final l in lines) {
        await t.insert('sale_items', {
          'sale_id': sid, 'product_id': l.productId, 'name': l.name,
          'qty': l.qty, 'price': l.price, 'cost_price': costs[l.productId]
        });
        await t.rawUpdate('UPDATE products SET qty = qty - ? WHERE id=?', [l.qty, l.productId]);
        await t.insert('stock_movements', {
          'product_id': l.productId, 'type': 'sale', 'qty': -l.qty,
          'ref_id': sid, 'user_id': userId, 'created_at': nowStr()
        });
      }
      await t.insert('audit_log', {'user_id': userId, 'action': 'sale', 'details': 'فاتورة $sid بإجمالي $total', 'created_at': nowStr()});
      return sid;
    });
  }

  Future<void> cancelSale(int saleId, String reason, int userId) async {
    if (reason.trim().isEmpty) throw Exception('سبب الإلغاء مطلوب');
    final d = await db;
    await d.transaction((t) async {
      final s = await t.query('sales', where: 'id=?', whereArgs: [saleId]);
      if (s.isEmpty || s.first['status'] != 'active') throw Exception('الفاتورة ملغاة بالفعل');
      await t.update('sales', {'status': 'cancelled', 'cancel_reason': reason, 'cancelled_by': userId}, where: 'id=?', whereArgs: [saleId]);
      final items = await t.query('sale_items', where: 'sale_id=?', whereArgs: [saleId]);
      for (final i in items) {
        await t.rawUpdate('UPDATE products SET qty = qty + ? WHERE id=?', [i['qty'], i['product_id']]);
        await t.insert('stock_movements', {
          'product_id': i['product_id'], 'type': 'cancel', 'qty': i['qty'],
          'ref_id': saleId, 'note': reason, 'user_id': userId, 'created_at': nowStr()
        });
      }
      await t.insert('audit_log', {'user_id': userId, 'action': 'sale_cancel', 'details': 'فاتورة $saleId: $reason', 'created_at': nowStr()});
    });
  }

  Future<List<Map<String, Object?>>> sales() async => (await db).rawQuery(
      'SELECT s.*, u.full_name AS user_name FROM sales s LEFT JOIN users u ON u.id=s.user_id ORDER BY s.id DESC LIMIT 200');

  Future<List<Map<String, Object?>>> saleItems(int id) async =>
      (await db).query('sale_items', where: 'sale_id=?', whereArgs: [id]);

  // ================= المرحلة 2 =================
  // ---------- الموردون ----------
  Future<List<Map<String, Object?>>> suppliers() async =>
      (await db).query('suppliers', orderBy: 'name');

  Future<void> saveSupplier(Map<String, Object?> s) async {
    if (((s['name'] as String?) ?? '').trim().isEmpty) {
      throw Exception('اسم المورد مطلوب');
    }
    final d = await db;
    if (s['id'] == null) {
      s.remove('id');
      await d.insert('suppliers', s);
    } else {
      await d.update('suppliers', s, where: 'id=?', whereArgs: [s['id']]);
    }
  }

  Future<double> supplierBalance(int id) async {
    final d = await db;
    final a = await d.rawQuery(
        'SELECT COALESCE(SUM(remaining),0) r FROM purchases WHERE supplier_id=?', [id]);
    final b = await d.rawQuery(
        'SELECT COALESCE(SUM(amount),0) p FROM supplier_payments WHERE supplier_id=?', [id]);
    return (a.first['r'] as num).toDouble() - (b.first['p'] as num).toDouble();
  }

  Future<void> paySupplier(int id, double amt, int uid) async {
    if (amt <= 0) throw Exception('المبلغ غير صحيح');
    if (amt > await supplierBalance(id) + 0.0001) {
      throw Exception('المبلغ أكبر من المستحق للمورد');
    }
    final d = await db;
    await d.insert('supplier_payments',
        {'supplier_id': id, 'amount': amt, 'user_id': uid, 'created_at': nowStr()});
    await audit(uid, 'supplier_pay', 'مورد $id مبلغ $amt');
  }

  Future<List<Map<String, Object?>>> supplierStatement(int id) async =>
      (await db).rawQuery(
          "SELECT 'فاتورة شراء #' || id AS title, total AS debit, paid AS credit, created_at FROM purchases WHERE supplier_id=? "
          "UNION ALL SELECT 'دفعة للمورد', 0, amount, created_at FROM supplier_payments WHERE supplier_id=? "
          'ORDER BY created_at',
          [id, id]);

  // ---------- المشتريات (CartLine.price = سعر التكلفة) ----------
  Future<int> createPurchase({
    int? supplierId,
    required List<CartLine> lines,
    required double paid,
    required int userId,
  }) async {
    if (lines.isEmpty) throw Exception('الفاتورة فارغة');
    final d = await db;
    return d.transaction<int>((t) async {
      double total = 0;
      for (final l in lines) {
        if (l.qty <= 0 || l.price < 0) throw Exception('كمية أو سعر غير صحيح: ${l.name}');
        total += l.total;
      }
      if (paid < 0 || paid > total + 0.0001) throw Exception('المدفوع أكبر من إجمالي الفاتورة');
      final pid = await t.insert('purchases', {
        'supplier_id': supplierId, 'total': total, 'paid': paid,
        'remaining': total - paid, 'user_id': userId, 'created_at': nowStr()
      });
      for (final l in lines) {
        await t.insert('purchase_items', {
          'purchase_id': pid, 'product_id': l.productId, 'qty': l.qty, 'cost_price': l.price
        });
        await t.rawUpdate(
            'UPDATE products SET qty = qty + ?, cost_price = ? WHERE id=?',
            [l.qty, l.price, l.productId]);
        await t.insert('stock_movements', {
          'product_id': l.productId, 'type': 'purchase', 'qty': l.qty,
          'ref_id': pid, 'user_id': userId, 'created_at': nowStr()
        });
      }
      await t.insert('audit_log', {'user_id': userId, 'action': 'purchase', 'details': 'فاتورة شراء $pid بإجمالي $total', 'created_at': nowStr()});
      return pid;
    });
  }

  // ---------- الجرد وحركة الصنف والتنبيهات ----------
  Future<double> stocktake(int productId, double counted, int uid) async {
    if (counted < 0) throw Exception('الكمية غير صحيحة');
    final d = await db;
    return d.transaction<double>((t) async {
      final r = await t.query('products', where: 'id=?', whereArgs: [productId]);
      if (r.isEmpty) throw Exception('الصنف غير موجود');
      final diff = counted - (r.first['qty'] as num).toDouble();
      if (diff == 0) return 0.0;
      await t.update('products', {'qty': counted}, where: 'id=?', whereArgs: [productId]);
      await t.insert('stock_movements', {
        'product_id': productId, 'type': diff < 0 ? 'shortage' : 'surplus',
        'qty': diff, 'note': 'جرد', 'user_id': uid, 'created_at': nowStr()
      });
      await t.insert('audit_log', {'user_id': uid, 'action': 'stocktake', 'details': '${r.first['name']}: $diff', 'created_at': nowStr()});
      return diff;
    });
  }

  Future<List<Map<String, Object?>>> movements(int productId) async =>
      (await db).rawQuery(
          'SELECT m.*, u.full_name AS user_name FROM stock_movements m LEFT JOIN users u ON u.id=m.user_id WHERE m.product_id=? ORDER BY m.id DESC LIMIT 200',
          [productId]);

  Future<List<Map<String, Object?>>> lowStock() async => (await db).query('products',
      where: 'qty>0 AND qty<=min_qty', orderBy: 'name');

  Future<List<Map<String, Object?>>> outOfStock() async =>
      (await db).query('products', where: 'qty<=0', orderBy: 'name');

  Future<List<Map<String, Object?>>> expiringSoon() async => (await db).rawQuery(
      "SELECT * FROM products WHERE expiry_date IS NOT NULL AND expiry_date<>'' AND date(expiry_date) <= date('now','+30 day') ORDER BY expiry_date");

  // ---------- المرتجعات ----------
  Future<Map<String, Object?>?> saleById(int id) async {
    final r = await (await db).query('sales', where: 'id=?', whereArgs: [id]);
    return r.isEmpty ? null : r.first;
  }

  Future<List<Map<String, Object?>>> returnableItems(int saleId) async =>
      (await db).rawQuery(
          'SELECT si.*, si.qty - COALESCE((SELECT SUM(ri.qty) FROM return_items ri JOIN returns r ON r.id=ri.return_id WHERE r.sale_id=si.sale_id AND ri.product_id=si.product_id),0) AS left_qty FROM sale_items si WHERE si.sale_id=?',
          [saleId]);

  /// qtys: رقم سطر الفاتورة (sale_items.id) -> الكمية المرتجعة
  Future<int> createReturn({
    required int saleId,
    required Map<int, double> qtys,
    required String reason,
    required bool restock,
    required int userId,
  }) async {
    if (reason.trim().isEmpty) throw Exception('سبب المرتجع مطلوب');
    final d = await db;
    return d.transaction<int>((t) async {
      final s = await t.query('sales', where: 'id=?', whereArgs: [saleId]);
      if (s.isEmpty || s.first['status'] != 'active') throw Exception('الفاتورة غير صالحة للمرتجع');
      final subtotal = (s.first['subtotal'] as num).toDouble();
      final factor = subtotal > 0 ? (s.first['total'] as num).toDouble() / subtotal : 1.0;
      final rows = <Map<String, Object?>>[];
      double total = 0;
      for (final e in qtys.entries) {
        if (e.value <= 0) continue;
        final it = await t.rawQuery(
            'SELECT si.*, si.qty - COALESCE((SELECT SUM(ri.qty) FROM return_items ri JOIN returns r ON r.id=ri.return_id WHERE r.sale_id=si.sale_id AND ri.product_id=si.product_id),0) AS left_qty FROM sale_items si WHERE si.id=? AND si.sale_id=?',
            [e.key, saleId]);
        if (it.isEmpty) throw Exception('سطر غير موجود في الفاتورة');
        if (e.value > (it.first['left_qty'] as num).toDouble() + 0.0001) {
          throw Exception('كمية المرتجع أكبر من المتاح للصنف ${it.first['name']}');
        }
        final unit = (it.first['price'] as num).toDouble() * factor;
        total += e.value * unit;
        rows.add({...it.first, 'ret_qty': e.value, 'unit': unit});
      }
      if (rows.isEmpty) throw Exception('حدد كمية مرتجعة واحدة على الأقل');
      final rid = await t.insert('returns', {
        'sale_id': saleId, 'reason': reason, 'total': total,
        'user_id': userId, 'created_at': nowStr()
      });
      for (final r in rows) {
        await t.insert('return_items', {
          'return_id': rid, 'product_id': r['product_id'], 'qty': r['ret_qty'],
          'price': r['unit'], 'cost_price': r['cost_price'], 'restock': restock ? 1 : 0
        });
        if (restock) {
          await t.rawUpdate('UPDATE products SET qty = qty + ? WHERE id=?', [r['ret_qty'], r['product_id']]);
          await t.insert('stock_movements', {
            'product_id': r['product_id'], 'type': 'return', 'qty': r['ret_qty'],
            'ref_id': rid, 'note': reason, 'user_id': userId, 'created_at': nowStr()
          });
        }
      }
      await t.insert('audit_log', {'user_id': userId, 'action': 'return', 'details': 'مرتجع $rid من فاتورة $saleId بقيمة $total', 'created_at': nowStr()});
      return rid;
    });
  }

  // ---------- الخزينة والورديات ----------
  Future<Map<String, Object?>?> openShift() async {
    final r = await (await db).query('shifts', where: 'closed_at IS NULL', limit: 1);
    return r.isEmpty ? null : r.first;
  }

  Future<void> startShift(double opening, int uid) async {
    if (opening < 0) throw Exception('الرصيد غير صحيح');
    if (await openShift() != null) throw Exception('توجد وردية مفتوحة بالفعل');
    await (await db).insert('shifts',
        {'user_id': uid, 'opening': opening, 'opened_at': nowStr()});
    await audit(uid, 'shift_open', 'رصيد بداية $opening');
  }

  Future<void> addTreasury(String type, double amt, String note, int uid) async {
    if (amt <= 0) throw Exception('المبلغ غير صحيح');
    if (await openShift() == null) throw Exception('افتح وردية أولاً');
    await (await db).insert('treasury', {
      'type': type, 'amount': amt, 'note': note, 'user_id': uid, 'created_at': nowStr()
    });
    await audit(uid, 'treasury_$type', '$amt $note');
  }

  Future<void> addExpense(String title, double amt, int uid) async {
    if (title.trim().isEmpty) throw Exception('بيان المصروف مطلوب');
    if (amt <= 0) throw Exception('المبلغ غير صحيح');
    await (await db).insert('expenses',
        {'title': title.trim(), 'amount': amt, 'user_id': uid, 'created_at': nowStr()});
    await audit(uid, 'expense', '$title $amt');
  }

  Future<double> expectedCash(Map<String, Object?> shift) async {
    final d = await db;
    final since = shift['opened_at'] as String;
    Future<double> sum(String sql) async =>
        ((await d.rawQuery(sql, [since])).first.values.first as num? ?? 0).toDouble();
    final sales = await sum(
        "SELECT COALESCE(SUM(MIN(paid,total)),0) FROM sales WHERE status='active' AND method='نقدي' AND created_at>=?");
    final dep = await sum("SELECT COALESCE(SUM(amount),0) FROM treasury WHERE type='deposit' AND created_at>=?");
    final wd = await sum("SELECT COALESCE(SUM(amount),0) FROM treasury WHERE type='withdraw' AND created_at>=?");
    final ex = await sum('SELECT COALESCE(SUM(amount),0) FROM expenses WHERE created_at>=?');
    final sp = await sum('SELECT COALESCE(SUM(amount),0) FROM supplier_payments WHERE created_at>=?');
    final pp = await sum('SELECT COALESCE(SUM(paid),0) FROM purchases WHERE created_at>=?');
    final rt = await sum('SELECT COALESCE(SUM(total),0) FROM returns WHERE created_at>=?');
    return (shift['opening'] as num).toDouble() + sales + dep - wd - ex - sp - pp - rt;
  }

  /// يرجع الفرق (الفعلي - المتوقع)
  Future<double> closeShift(double actual, String note, int uid) async {
    if (actual < 0) throw Exception('المبلغ غير صحيح');
    final s = await openShift();
    if (s == null) throw Exception('لا توجد وردية مفتوحة');
    final exp = await expectedCash(s);
    final diff = actual - exp;
    await (await db).update(
        'shifts',
        {'closed_at': nowStr(), 'expected': exp, 'actual': actual, 'diff': diff, 'note': note},
        where: 'id=?',
        whereArgs: [s['id']]);
    await audit(uid, 'shift_close', 'متوقع $exp فعلي $actual فرق $diff');
    return diff;
  }

  Future<double> cashBalance() async {
    final s = await openShift();
    if (s != null) return expectedCash(s);
    final r = await (await db).query('shifts',
        where: 'closed_at IS NOT NULL', orderBy: 'id DESC', limit: 1);
    return r.isEmpty ? 0.0 : (r.first['actual'] as num).toDouble();
  }

  Future<List<Map<String, Object?>>> shifts() async => (await db).rawQuery(
      'SELECT s.*, u.full_name AS user_name FROM shifts s LEFT JOIN users u ON u.id=s.user_id ORDER BY s.id DESC LIMIT 30');

  // ---------- لوحة التحكم (المرحلة 2) ----------
  Future<Map<String, double>> dashboard() async {
    final d = await db;
    final today = nowStr().substring(0, 10);
    Future<double> one(String sql) async =>
        ((await d.rawQuery(sql, [today])).first.values.first as num? ?? 0).toDouble();
    final sales = await one("SELECT COALESCE(SUM(total),0) FROM sales WHERE status='active' AND date(created_at)=?");
    final count = await one("SELECT COUNT(*) FROM sales WHERE status='active' AND date(created_at)=?");
    final cogs = await one("SELECT COALESCE(SUM(si.cost_price*si.qty),0) FROM sale_items si JOIN sales s ON s.id=si.sale_id WHERE s.status='active' AND date(s.created_at)=?");
    final ret = await one('SELECT COALESCE(SUM(total),0) FROM returns WHERE date(created_at)=?');
    final retCost = await one('SELECT COALESCE(SUM(ri.cost_price*ri.qty),0) FROM return_items ri JOIN returns r ON r.id=ri.return_id WHERE ri.restock=1 AND date(r.created_at)=?');
    final exp = await one('SELECT COALESCE(SUM(amount),0) FROM expenses WHERE date(created_at)=?');
    final purch = await one('SELECT COALESCE(SUM(total),0) FROM purchases WHERE date(created_at)=?');
    final st = await d.rawQuery(
        'SELECT COALESCE(SUM(qty*cost_price),0) val, '
        'COALESCE(SUM(CASE WHEN qty<=0 THEN 1 ELSE 0 END),0) outc, '
        'COALESCE(SUM(CASE WHEN qty>0 AND qty<=min_qty THEN 1 ELSE 0 END),0) lowc FROM products');
    return {
      'sales': sales,
      'count': count,
      // صافي الربح = المبيعات - المرتجعات - تكلفة المباع (بعد استرداد تكلفة المرتجع الصالح) - المصروفات
      'profit': sales - ret - (cogs - retCost) - exp,
      'stockValue': (st.first['val'] as num).toDouble(),
      'out': (st.first['outc'] as num).toDouble(),
      'low': (st.first['lowc'] as num).toDouble(),
      'purchases': purch,
      'cash': await cashBalance(),
    };
  }
}
