import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class Contact {
  final int? id;
  final String name;
  final String description;

  const Contact({this.id, required this.name, required this.description});

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'description': description,
      };

  factory Contact.fromMap(Map<String, dynamic> map) => Contact(
        id: map['id'] as int?,
        name: map['name'] as String,
        description: map['description'] as String,
      );
}

class ContactsService {
  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'contacts.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE contacts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            description TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Future<int> addContact(String name, String description) async {
    final db = await database;
    return db.insert('contacts', {'name': name, 'description': description});
  }

  Future<List<Contact>> searchContacts(String query) async {
    final db = await database;
    final q = '%$query%';
    final results = await db.query(
      'contacts',
      where: 'name LIKE ? OR description LIKE ?',
      whereArgs: [q, q],
    );
    return results.map(Contact.fromMap).toList();
  }

  Future<List<Contact>> getAllContacts() async {
    final db = await database;
    final results = await db.query('contacts', orderBy: 'name');
    return results.map(Contact.fromMap).toList();
  }

  Future<void> updateContact(int id, {String? name, String? description}) async {
    final db = await database;
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (description != null) updates['description'] = description;
    if (updates.isNotEmpty) {
      await db.update('contacts', updates, where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> deleteContact(int id) async {
    final db = await database;
    await db.delete('contacts', where: 'id = ?', whereArgs: [id]);
  }
}
