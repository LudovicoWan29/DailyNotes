// Copyright (C) 2026 Ludovico Venturi
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPLv3 section 7 apply; see ADDITIONAL_TERMS.md.

import 'dart:async';
import 'dart:io';

import 'package:daily_notes/database/attachment_storage.dart';
import 'package:daily_notes/l10n/generated/app_localizations.dart';
import 'package:daily_notes/models/attachment.dart';
import 'package:daily_notes/models/note.dart';
import 'package:daily_notes/pages/audio_recorder_page.dart';
import 'package:daily_notes/pages/full_screen_text_editor_page.dart';
import 'package:daily_notes/providers/notes_provider.dart';
import 'package:daily_notes/widgets/app_dialog.dart';
import 'package:daily_notes/widgets/content_width_limit.dart';
import 'package:daily_notes/widgets/editor_action_bar.dart';
import 'package:daily_notes/widgets/editor_action_bar/editor_keyboard_session.dart';
import 'package:daily_notes/widgets/editor_action_bar/toolbar_menu_action.dart';
import 'package:daily_notes/widgets/entry_attachment_actions.dart';
import 'package:daily_notes/widgets/entry_attachment_editable_list.dart';
import 'package:daily_notes/widgets/entry_text_edit.dart';
import 'package:daily_notes/widgets/failure_dialog.dart';
import 'package:daily_notes/widgets/icons/svg_icon.dart';
import 'package:daily_notes/widgets/large_attachment_warning.dart';
import 'package:daily_notes/widgets/markdown_preview_controller.dart';
import 'package:easy_debounce/easy_debounce.dart';
import 'package:material_ui/material_ui.dart';

/// Creates or edits a note that is not tied to a day. It works like the daily
/// entry page, without the date and the mood.
class NoteEditPage extends StatefulWidget {
  const NoteEditPage({super.key, this.note});

  final Note? note;

  @override
  State<NoteEditPage> createState() => _NoteEditPageState();
}

class _NoteEditPageState extends State<NoteEditPage>
    with WidgetsBindingObserver {
  static const _saveDebounceKey = 'save-note';

  Note? _note;
  late List<EntryAttachment> _attachments;
  late String _savedText;
  late List<String> _savedFiles;
  int _pendingAttachmentCount = 0;
  bool _deleting = false;
  bool _closing = false;
  Future<void> _saveQueue = Future.value();

  final FocusNode _focusNode = FocusNode();
  final MarkdownPreviewController _textController = MarkdownPreviewController();
  final UndoHistoryController _undoController = UndoHistoryController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _note = widget.note;
    _attachments = _note == null
        ? []
        : [for (final a in NotesProvider.instance.getForNote(_note!)) a.copy()];
    _savedText = _note?.text ?? '';
    _savedFiles = [for (final a in _attachments) a.filePath];
    _textController.text = _savedText;
    _textController.addListener(_scheduleSave);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    EasyDebounce.cancel(_saveDebounceKey);
    _focusNode.dispose();
    _textController.dispose();
    _undoController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden) _save();
  }

  void _scheduleSave() {
    EasyDebounce.debounce(_saveDebounceKey, const Duration(seconds: 5), _save);
  }

  String get _text => _textController.text;

  bool get _hasContent => _text.trim().isNotEmpty || _attachments.isNotEmpty;

  bool get _hasChanges {
    if (_text != _savedText) return true;
    final files = [for (final a in _attachments) a.filePath];
    if (files.length != _savedFiles.length) return true;
    for (var i = 0; i < files.length; i++) {
      if (files[i] != _savedFiles[i]) return true;
    }
    return false;
  }

  Future<void> _save() {
    // Saves run one after another so a note is never created twice.
    return _saveQueue = _saveQueue.then((_) => _saveNow());
  }

  Future<void> _saveNow() async {
    if (_deleting) return;
    if (_note == null && !_hasContent) return;
    if (_note != null && !_hasChanges) return;

    final now = DateTime.now();
    final text = _text;
    final attachments = [for (final a in _attachments) a.copy()];
    final note = _note ?? Note(text: text, timeCreate: now, timeModified: now);
    final saved = await NotesProvider.instance
        .save(note.copy(text: text, timeModified: now), attachments);

    _note = saved;
    _savedText = text;
    _savedFiles = [for (final a in attachments) a.filePath];
    final persisted = {
      for (final a in NotesProvider.instance.getForNote(saved)) a.filePath: a.id
    };
    _attachments = [
      for (final a in _attachments)
        a.copy(id: persisted[a.filePath], entryId: saved.id)
    ];
    if (mounted) setState(() {});
  }

  Future<void> _saveAndClose() async {
    if (_closing) return;
    _closing = true;
    EasyDebounce.cancel(_saveDebounceKey);
    try {
      await _save();
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _openFullScreenEditor() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        allowSnapshotting: false,
        builder: (context) => FullScreenTextEditorPage(
          initialText: _textController.text,
        ),
      ),
    );
    if (result != null) _textController.text = result;
  }

  void _showDeletePopup() {
    if (_note == null && !_hasContent) {
      Navigator.of(context).pop();
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    showAppDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.noteDeleteTitle),
        content: Text(l10n.noteDeleteDescription),
        actions: [
          TextButton(
            child: Text(MaterialLocalizations.of(context).deleteButtonTooltip),
            onPressed: () async {
              _deleting = true;
              EasyDebounce.cancel(_saveDebounceKey);
              final navigator = Navigator.of(context);
              final note = _note;
              final unsaved = [for (final a in _attachments) a];
              navigator.pop(); // dialog
              navigator.pop(); // page
              if (note != null) {
                await NotesProvider.instance.remove(note);
              } else {
                await _deleteFiles(unsaved);
              }
            },
          ),
          TextButton(
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFiles(List<EntryAttachment> attachments) async {
    for (final attachment in attachments) {
      await AttachmentStorage.instance
          .delete(attachment.filePath, attachment.type);
    }
  }

  Future<void> _addAttachments(List<NewAttachment> newAttachments) async {
    setState(() {
      _attachments = EntryAttachment.appendRanked(_attachments, newAttachments,
          entryId: _note?.id);
    });
    await _save();
  }

  Future<void> _importAttachments(
      Future<List<PendingAttachment>> picking) async {
    final List<PendingAttachment> pending;
    try {
      pending = await picking;
    } catch (error) {
      await _showAttachmentFailure(error);
      return;
    }
    if (pending.isEmpty) return;
    if (!mounted) {
      await EntryAttachmentActions.discardAll(pending);
      return;
    }

    setState(() => _pendingAttachmentCount += pending.length);
    final large = pending.where((attachment) => attachment.isLarge).firstOrNull;
    if (large != null) {
      unawaited(showLargeAttachmentWarning(
          context, large.type, large.name, large.sizeBytes!));
    }

    Object? failure;
    var stored = const <NewAttachment>[];
    try {
      stored = await EntryAttachmentActions.storeAll(pending,
          isCancelled: () => !mounted);
    } catch (error) {
      failure = error;
    } finally {
      _pendingAttachmentCount -= pending.length;
      if (stored.isEmpty && mounted) setState(() {});
    }
    if (stored.isNotEmpty) {
      if (mounted) {
        await _addAttachments(stored);
      } else {
        await EntryAttachmentActions.deleteStoredAttachments(stored);
      }
    }
    if (failure != null || (mounted && stored.length < pending.length)) {
      await _showAttachmentFailure(failure);
    }
  }

  Future<void> _showAttachmentFailure(Object? error) async {
    if (!mounted) return;
    await showFailureDialog(context,
        description:
            AppLocalizations.of(context)!.attachmentAddErrorDescription,
        error: error);
  }

  Future<void> _recordAudio() async {
    final attachment = await Navigator.of(context).push<NewAttachment>(
      MaterialPageRoute(
        allowSnapshotting: false,
        fullscreenDialog: true,
        builder: (context) => const AudioRecorderPage(),
      ),
    );
    if (attachment == null) return;
    await _addAttachments([attachment]);
    final sizeBytes = await AttachmentStorage.instance
        .sizeBytes(attachment.filePath, attachment.type);
    if (sizeBytes != null && attachment.type.isLarge(sizeBytes) && mounted) {
      await showLargeAttachmentWarning(
          context, attachment.type, attachment.filePath, sizeBytes);
    }
  }

  List<ToolbarAction> _buildMainActions(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return [
      ToolbarAction(
        icon: const SvgIcon('assets/icons/attach_file.svg'),
        menu: [
          ToolbarMenuAction(
            icon: Icons.mic_rounded,
            label: l10n.actionAddAudio,
            onSelected: () =>
                _importAttachments(EntryAttachmentActions.pickAudioFile()),
          ),
          ToolbarMenuAction(
            icon: Icons.videocam_rounded,
            label: l10n.actionAddVideo,
            onSelected: () => _importAttachments(
                EntryAttachmentActions.pickVideosFromGallery()),
          ),
          ToolbarMenuAction(
            icon: Icons.photo_rounded,
            label: l10n.actionAddImage,
            onSelected: () =>
                _importAttachments(EntryAttachmentActions.pickFromGallery()),
          ),
        ],
      ),
      ToolbarAction(
        icon: const Icon(Icons.photo_camera_rounded),
        menu: [
          ToolbarMenuAction(
            icon: Icons.mic_rounded,
            label: l10n.actionRecordAudio,
            onSelected: _recordAudio,
          ),
          if (Platform.isAndroid) ...[
            ToolbarMenuAction(
              icon: Icons.videocam_rounded,
              label: l10n.actionTakeVideo,
              onSelected: () =>
                  _importAttachments(EntryAttachmentActions.takeVideo()),
            ),
            ToolbarMenuAction(
              icon: Icons.photo_camera_rounded,
              label: l10n.actionTakePhoto,
              onSelected: () =>
                  _importAttachments(EntryAttachmentActions.takePhoto()),
            ),
          ],
        ],
      ),
    ];
  }

  Widget _buildTextEditorSliver(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Builder(
        builder: (context) => GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            EditorKeyboardSessionScope.maybeOf(context)?.resume();
            _focusNode.requestFocus();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: EntryTextEditor(
                    text: _savedText,
                    focusNode: _focusNode,
                    textEditingController: _textController,
                    undoHistoryController: _undoController,
                    onExpand: _openFullScreenEditor,
                  ),
                ),
                SizedBox(height: 16 + EditorActionBar.reservedHeight(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = EditorActionBarOverlay.keyboardInsetOf(context);

    return PopScope(
      onPopInvokedWithResult: (didPop, result) async {
        if (!_deleting) await _save();
      },
      child: Scaffold(
        appBar: AppBar(
          iconTheme: Theme.of(context).iconTheme,
          leading: IconButton(
            icon: const Icon(Icons.delete),
            tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
            onPressed: _showDeletePopup,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.check_rounded),
              tooltip: MaterialLocalizations.of(context).okButtonLabel,
              onPressed: _saveAndClose,
            ),
          ],
        ),
        body: EditorActionBarOverlay(
          keyboardInset: keyboardInset,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final capPadding = EdgeInsets.symmetric(
                  horizontal: contentSideInset(constraints.maxWidth));
              return CustomScrollView(
                slivers: [
                  if (_attachments.isNotEmpty || _pendingAttachmentCount > 0)
                    SliverPadding(
                      padding: capPadding,
                      sliver: SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: EntryAttachmentEditableList(
                            attachments: _attachments,
                            pendingCount: _pendingAttachmentCount,
                            onAttachmentsChanged: (attachments) async {
                              _attachments = attachments;
                              await _save();
                            },
                          ),
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: capPadding,
                    sliver: _buildTextEditorSliver(context),
                  ),
                ],
              );
            },
          ),
          actionBar: EditorActionBar(
            controller: _textController,
            undoController: _undoController,
            focusNode: _focusNode,
            mainActions: _buildMainActions(context),
          ),
        ),
      ),
    );
  }
}
