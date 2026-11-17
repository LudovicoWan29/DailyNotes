// Copyright (C) 2026 Demizo and contributors
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPLv3 section 7 apply; see ADDITIONAL_TERMS.md.

import 'package:daily_notes/config_provider.dart';
import 'package:daily_notes/l10n/generated/app_localizations.dart';
import 'package:daily_notes/models/attachment.dart';
import 'package:daily_notes/utils/file_size_format.dart';
import 'package:daily_notes/widgets/app_dialog.dart';
import 'package:daily_notes/widgets/attachment_type_presentation.dart';
import 'package:daily_notes/widgets/file_size_row.dart';
import 'package:material_ui/material_ui.dart';

/// Warns that an attachment is large, unless the user turned the warning off.
Future<void> showLargeAttachmentWarning(BuildContext context,
    AttachmentType type, String name, int sizeBytes) async {
  if (ConfigProvider.instance.get(Settings.suppressLargeAttachmentWarning) ||
      !context.mounted) {
    return;
  }

  var suppress = false;
  await showAppDialog(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setLocalState) => AlertDialog(
        title: Text(
            AppLocalizations.of(dialogContext)!.largeAttachmentWarningTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(dialogContext)!
                .largeAttachmentWarningDescription),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: FileSizeRow(
                icon: type.icon,
                label: name,
                sizeText: formatFileSize(
                    sizeBytes, AppLocalizations.of(dialogContext)!.localeName),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: suppress,
              onChanged: (value) =>
                  setLocalState(() => suppress = value ?? false),
              title: Text(AppLocalizations.of(dialogContext)!.dontShowAgain),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (suppress) {
                await ConfigProvider.instance
                    .set(Settings.suppressLargeAttachmentWarning, true);
              }
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: Text(MaterialLocalizations.of(dialogContext).okButtonLabel),
          ),
        ],
      ),
    ),
  );
}
