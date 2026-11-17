// Copyright (C) 2026 Ludovico Venturi
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPLv3 section 7 apply; see ADDITIONAL_TERMS.md.

import 'package:daily_notes/database/app_database.dart';
import 'package:daily_notes/database/attachment_storage.dart';
import 'package:daily_notes/database/note_dao.dart';
import 'package:daily_notes/models/attachment.dart';
import 'package:daily_notes/models/note.dart';
import 'package:material_ui/material_ui.dart';

class NotesProvider with ChangeNotifier {
  static final NotesProvider instance = NotesProvider._init();

  NotesProvider._init();

  List<Note> notes = [];
  List<EntryAttachment> attachments = [];

  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  @visibleForTesting
  set isLoaded(bool value) => _isLoaded = value;

  Future<void> load() async {
    notes = await NoteDao.getAll();
    attachments = await NoteDao.getAllAttachments();
    _isLoaded = true;
    notifyListeners();
  }

  List<EntryAttachment> getForNote(Note note) {
    final result = attachments.where((a) => a.entryId == note.id).toList();
    result.sort((a, b) => b.rank.compareTo(a.rank));
    return result;
  }

  /// Saves [note] with exactly [newAttachments]. Files of attachments that are
  /// no longer present are deleted.
  Future<Note> save(Note note, List<EntryAttachment> newAttachments) async {
    final previous =
        note.id == null ? const <EntryAttachment>[] : getForNote(note);
    final (saved, savedAttachments) = await NoteDao.save(note, newAttachments);

    attachments = [
      ...attachments.where((a) => a.entryId != saved.id),
      ...savedAttachments,
    ];
    notes = [saved, ...notes.where((n) => n.id != saved.id)]
      ..sort((a, b) => b.timeModified.compareTo(a.timeModified));

    final keptFiles = {for (final a in savedAttachments) a.filePath};
    for (final attachment in previous) {
      if (!keptFiles.contains(attachment.filePath)) {
        await AttachmentStorage.instance
            .delete(attachment.filePath, attachment.type);
      }
    }
    await AppDatabase.instance.updateExternalDatabase();
    notifyListeners();
    return saved;
  }

  Future<void> remove(Note note) async {
    final id = note.id;
    if (id == null) return;
    final removed = getForNote(note);
    await NoteDao.remove(id);
    notes = notes.where((n) => n.id != id).toList();
    attachments = attachments.where((a) => a.entryId != id).toList();
    for (final attachment in removed) {
      await AttachmentStorage.instance
          .delete(attachment.filePath, attachment.type);
    }
    await AppDatabase.instance.updateExternalDatabase();
    notifyListeners();
  }
}
