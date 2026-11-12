import 'dart:io';

import 'package:flutter/material.dart';

import '../services/updater.dart';

bool _running = false;

/// Startup (and manual) update flow: check manifest, then download right away
/// with a progress dialog; Android then shows its one-tap install prompt.
Future<void> checkForUpdate(BuildContext context, {bool manual = false}) async {
  if (_running) {
    if (manual) _snack(context, 'Already checking for updates…');
    return;
  }
  if (!Platform.isAndroid) {
    if (manual) _snack(context, 'Auto-update is Android-only for now.');
    return;
  }
  _running = true;
  try {
    final info = await Updater.check();
    if (!context.mounted) return;
    if (info == null) {
      if (manual) _snack(context, "You're on the latest build.");
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpdateDialog(info: info),
    );
  } catch (e) {
    if (manual && context.mounted) _snack(context, 'Update check failed: $e');
  } finally {
    _running = false;
  }
}

void _snack(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.info});
  final UpdateInfo info;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  UpdateProgress? _p;

  @override
  void initState() {
    super.initState();
    Updater.install(widget.info).listen((p) {
      if (!mounted) return;
      setState(() => _p = p);
      if (p.stage == 'installing') Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final err = p?.stage == 'error';
    return AlertDialog(
      title: Text('Updating to ${widget.info.version}'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (widget.info.notes.isNotEmpty) ...[
          Text(widget.info.notes, maxLines: 6, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
        ],
        if (err)
          Text('Update failed: ${p!.error}\n\nIf asked, allow "Install unknown apps" for Parallax News, then try again from Settings.')
        else ...[
          LinearProgressIndicator(value: p?.percent == null ? null : p!.percent! / 100),
          const SizedBox(height: 8),
          Text(p?.percent == null ? 'Starting download…' : 'Downloading ${p!.percent}%'),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(err ? 'Close' : 'Hide')),
      ],
    );
  }
}
