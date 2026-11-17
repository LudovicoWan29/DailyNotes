// Copyright (C) 2026 Ludovico Venturi
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPLv3 section 7 apply; see ADDITIONAL_TERMS.md.

import 'package:daily_notes/database/app_database.dart';
import 'package:daily_notes/models/attachment.dart';
import 'package:daily_notes/models/note.dart';
import 'package:logging/logging.dart';
import 'package:sqflite/sqflite.dart';

/// Stores notes and their attachments. Attachments reuse [EntryAttachment]
/// with [EntryAttachment.entryId] holding the note id.
class NoteDao {
  static final Logger _logger = Logger('NoteDao');

  static Map<String, Object?> _attachmentRow(EntryAttachment attachment) => {
        EntryAttachmentFields.id: attachment.id,
        noteAttachmentNoteId: attachment.entryId,
        EntryAttachmentFields.type: attachment.type.name,
        EntryAttachmentFields.filePath: attachment.filePath,
        EntryAttachmentFields.rank: attachment.rank,
        EntryAttachmentFields.timeCreate:
            attachment.timeCreate.toIso8601String(),
      };

  static EntryAttachment? _parseAttachment(Map<String, Object?> row) {
    final json = {
      ...row,
      EntryAttachmentFields.entryId: row[noteAttachmentNoteId]
    };
    final attachment = EntryAttachment.tryFromJson(json);
    if (attachment == null) {
      _logger.warning(
          'Skipping note attachment ${row[EntryAttachmentFields.id]} of unknown type ${row[EntryAttachmentFields.type]}');
    }
    return attachment;
  }

  static Future<List<Note>> getAll() async {
    final rows = await AppDatabase.instance.database!
        .query(notesTable, orderBy: '${NoteFields.timeModified} DESC');
    return rows.map(Note.fromJson).toList();
  }

  static Future<List<EntryAttachment>> getAllAttachments() async {
    final rows = await AppDatabase.instance.database!.query(
        noteAttachmentsTable,
        orderBy: '${EntryAttachmentFields.rank} DESC');
    return [
      for (final row in rows)
        if (_parseAttachment(row) case final attachment?) attachment,
    ];
  }

  /// Inserts or updates [note] and replaces its attachments with
  /// [attachments], in one transaction.
  static Future<(Note, List<EntryAttachment>)> save(
      Note note, List<EntryAttachment> attachments) {
    return AppDatabase.instance.database!.transaction((txn) async {
      final int id;
      if (note.id == null) {
        id = await txn.insert(notesTable, note.toJson());
      } else {
        id = note.id!;
        await txn.update(notesTable, note.toJson(),
            where: '${NoteFields.id} = ?', whereArgs: [id]);
      }
      await txn.delete(noteAttachmentsTable,
          where: '$noteAttachmentNoteId = ?', whereArgs: [id]);
      final saved = <EntryAttachment>[];
      for (final attachment in attachments) {
        final row = _attachmentRow(attachment.copy(entryId: id))
          ..remove(EntryAttachmentFields.id);
        final attachmentId = await txn.insert(noteAttachmentsTable, row);
        saved.add(attachment.copy(id: attachmentId, entryId: id));
      }
      return (note.copy(id: id), saved);
    });
  }

  static Future<void> remove(int id, {DatabaseExecutor? executor}) async {
    final db = AppDatabase.executorOr(executor);
    await db.delete(noteAttachmentsTable,
        where: '$noteAttachmentNoteId = ?', whereArgs: [id]);
    await db.delete(notesTable, where: '${NoteFields.id} = ?', whereArgs: [id]);
  }
}
