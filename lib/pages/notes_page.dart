// Copyright (C) 2026 Ludovico Venturi
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPLv3 section 7 apply; see ADDITIONAL_TERMS.md.

import 'package:daily_notes/l10n/generated/app_localizations.dart';
import 'package:daily_notes/models/note.dart';
import 'package:daily_notes/pages/note_edit_page.dart';
import 'package:daily_notes/providers/notes_provider.dart';
import 'package:daily_notes/widgets/attachment_cover_thumbnail.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Notes that are not tied to a date, shown as a grid of cards.
class NotesPage extends StatelessWidget {
  const NotesPage({super.key});

  Future<void> _open(BuildContext context, [Note? note]) =>
      Navigator.of(context).push(MaterialPageRoute(
        allowSnapshotting: false,
        builder: (context) => NoteEditPage(note: note),
      ));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.watch<NotesProvider>();
    final notes = provider.notes;

    return Stack(
      children: [
        if (notes.isEmpty)
          _EmptyState(
              title: l10n.notesEmptyTitle, text: l10n.notesEmptyDescription)
        else
          GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 240,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.85,
            ),
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index];
              return _NoteCard(
                note: note,
                onTap: () => _open(context, note),
              );
            },
          ),
        Align(
          alignment: AlignmentDirectional.bottomEnd,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FloatingActionButton(
              heroTag: 'notes-add-button',
              tooltip: l10n.actionAddNote,
              onPressed: () => _open(context),
              child: const Icon(Icons.add_rounded),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.onTap});

  final Note note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<NotesProvider>();
    final covers = provider
        .getForNote(note)
        .where((attachment) => attachment.type.isVisual)
        .toList();
    final text = note.text.trim();
    final hasOtherAttachments =
        covers.isEmpty && provider.getForNote(note).isNotEmpty;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (covers.isNotEmpty)
              Expanded(
                flex: 3,
                child: AttachmentCoverThumbnail(candidates: covers),
              ),
            if (hasOtherAttachments)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Icon(Icons.attach_file_rounded,
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            if (text.isNotEmpty)
              Expanded(
                flex: covers.isEmpty ? 1 : 2,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    text,
                    overflow: TextOverflow.fade,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sticky_note_2_rounded,
                size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
