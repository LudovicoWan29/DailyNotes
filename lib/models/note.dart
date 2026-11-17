// Copyright (C) 2026 Ludovico Venturi
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPLv3 section 7 apply; see ADDITIONAL_TERMS.md.

const String notesTable = 'notes';
const String noteAttachmentsTable = 'note_attachments';

class NoteFields {
  static const String id = 'id';
  static const String text = 'text';
  static const String timeCreate = 'time_create';
  static const String timeModified = 'time_modified';
}

/// Column holding the owning note in [noteAttachmentsTable]. The other columns
/// match [EntryAttachmentFields].
const String noteAttachmentNoteId = 'note_id';

/// A note that is not tied to a calendar day.
class Note {
  final int? id;
  final String text;
  final DateTime timeCreate;
  final DateTime timeModified;

  const Note({
    this.id,
    required this.text,
    required this.timeCreate,
    required this.timeModified,
  });

  Note copy({
    int? id,
    String? text,
    DateTime? timeCreate,
    DateTime? timeModified,
  }) =>
      Note(
        id: id ?? this.id,
        text: text ?? this.text,
        timeCreate: timeCreate ?? this.timeCreate,
        timeModified: timeModified ?? this.timeModified,
      );

  static Note fromJson(Map<String, Object?> json) => Note(
        id: json[NoteFields.id] as int?,
        text: json[NoteFields.text] as String,
        timeCreate: DateTime.parse(json[NoteFields.timeCreate] as String),
        timeModified: DateTime.parse(json[NoteFields.timeModified] as String),
      );

  Map<String, Object?> toJson() => {
        NoteFields.id: id,
        NoteFields.text: text,
        NoteFields.timeCreate: timeCreate.toIso8601String(),
        NoteFields.timeModified: timeModified.toIso8601String(),
      };
}
