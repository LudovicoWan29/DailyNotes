// Copyright (C) 2026 Ludovico Venturi
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPLv3 section 7 apply; see ADDITIONAL_TERMS.md.

import 'dart:typed_data';

import 'package:daily_notes/database/app_database.dart';
import 'package:daily_notes/database/attachment_storage.dart';
import 'package:daily_notes/models/attachment.dart';
import 'package:daily_notes/models/note.dart';
import 'package:daily_notes/providers/entry_attachments_provider.dart';
import 'package:daily_notes/providers/notes_provider.dart';
import 'package:daily_notes/storage/in_memory_file_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late InMemoryFileStore images;
  final provider = NotesProvider.instance;
  final time = DateTime(2025, 6, 3, 21, 15);

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    databaseFactory = databaseFactoryFfi;
    database = await databaseFactory.openDatabase(inMemoryDatabasePath);
    AppDatabase.instance.database = database;
    await AppDatabase.instance.createSchema(database);
    images = InMemoryFileStore();
    AttachmentStorage.instance.overrideStores(images, InMemoryFileStore());
    await provider.load();
  });

  tearDown(() async {
    AttachmentStorage.instance.clearStoreOverrides();
    AppDatabase.instance.database = null;
    await database.close();
  });

  EntryAttachment photo(String name, int rank) => EntryAttachment(
      entryId: null,
      type: AttachmentType.image,
      filePath: name,
      rank: rank,
      timeCreate: time);

  Future<void> storeFile(String name) => images.write(name, Uint8List(1));

  test('saves a note with photos and reloads it', () async {
    final saved = await provider.save(
        Note(text: 'hello', timeCreate: time, timeModified: time),
        [photo('a.jpg', 1), photo('b.jpg', 0)]);

    expect(saved.id, isNotNull);
    await provider.load();
    expect(provider.notes.single.text, 'hello');
    expect(provider.getForNote(provider.notes.single).map((a) => a.filePath),
        ['a.jpg', 'b.jpg']);
  });

  test('deletes the files of photos removed from a note', () async {
    await storeFile('a.jpg');
    await storeFile('b.jpg');
    final saved = await provider.save(
        Note(text: '', timeCreate: time, timeModified: time),
        [photo('a.jpg', 1), photo('b.jpg', 0)]);

    await provider.save(saved, [photo('a.jpg', 0)]);

    expect(provider.attachments.map((a) => a.filePath), ['a.jpg']);
    expect(await images.list(), ['a.jpg']);
  });

  test('removing a note deletes its photos', () async {
    await storeFile('a.jpg');
    final saved = await provider.save(
        Note(text: 'x', timeCreate: time, timeModified: time),
        [photo('a.jpg', 0)]);

    await provider.remove(saved);

    expect(provider.notes, isEmpty);
    expect(provider.attachments, isEmpty);
    expect(await images.list(), isEmpty);
  });

  test('the newest edited note comes first', () async {
    await provider.save(
        Note(text: 'old', timeCreate: time, timeModified: time), const []);
    await provider.save(
        Note(
            text: 'new',
            timeCreate: time,
            timeModified: time.add(const Duration(hours: 1))),
        const []);

    expect(provider.notes.map((n) => n.text), ['new', 'old']);
  });

  test('photos of notes are protected from garbage collection', () async {
    await storeFile('keep.jpg');
    await storeFile('orphan.jpg');
    await provider.save(Note(text: '', timeCreate: time, timeModified: time),
        [photo('keep.jpg', 0)]);
    EntryAttachmentsProvider.instance.isLoaded = true;
    addTearDown(() => EntryAttachmentsProvider.instance.isLoaded = false);

    await AttachmentStorage.instance.garbageCollectAttachments();

    expect(await images.list(), ['keep.jpg']);
  });
}
