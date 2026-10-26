import 'package:flutter/material.dart';

import 'i18n.dart';

import '../core/board_controller.dart';
import '../core/models.dart';
import 'theme.dart';
import 'widgets.dart';

/// Always-visible button in the top bar with the number of open issues: missing sensors, setup steps and
/// PreArm reasons. It opens the list.
class IssuesButton extends StatelessWidget {
  const IssuesButton(this.c, {super.key});
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final issues = c.target == null ? const <VehicleIssue>[] : c.vehicleIssues();
    final prearm = c.target == null ? const <String>[] : c.prearmReasons;
    final count = issues.length + prearm.length;
    final error = prearm.isNotEmpty || issues.any((i) => i.tone == Tone.err);
    final color = count == 0 ? AppColors.ok : (error ? AppColors.err : AppColors.warn);
    return Tooltip(
      message: tr('Missing sensors, setup steps and arming checks'),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.6)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        onPressed: c.target == null ? null : () => showIssuesDialog(context, c),
        icon: Icon(count == 0 ? Icons.check_circle_outline : Icons.warning_amber, size: 16),
        label: Text(count == 0 ? tr('No issues') : '$count ${tr(count == 1 ? 'issue' : 'issues')}'),
      ),
    );
  }
}

/// The open issues and the PreArm reasons in one list, kept up to date while it is open.
Future<void> showIssuesDialog(BuildContext context, BoardController c) => showDialog<void>(
  context: context,
  builder: (context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final issues = c.vehicleIssues();
      final reasons = c.prearmReasons;
      return AlertDialog(
        title: Text(tr('Issues'), style: Theme.of(context).textTheme.titleMedium),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionTitle('Setup'),
                if (issues.isEmpty) Muted('Nothing missing.'),
                for (final issue in issues) _Banner(c, issue, onOpen: () => Navigator.pop(context)),
                SectionTitle('Arming checks'),
                if (reasons.isEmpty)
                  Muted(
                    c.prearmHealthy == true
                        ? 'No failing checks reported. The vehicle is ready to arm.'
                        : 'No failing checks reported yet. Run the checks to ask the vehicle.',
                  ),
                for (final r in reasons)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline, size: 16, color: AppColors.err),
                        const SizedBox(width: 8),
                        Expanded(child: SelectableText(r)),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                Muted('PreArm reasons are collected from the messages of the last minute.', size: 12),
              ],
            ),
          ),
        ),
        actions: [
          if (c.isArdupilot)
            OutlinedButton.icon(
              onPressed: c.runPrearmChecks,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(tr('Run checks')),
            ),
          FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('Close'))),
        ],
      );
    },
  ),
);

class _Banner extends StatelessWidget {
  const _Banner(this.c, this.issue, {required this.onOpen});
  final BoardController c;
  final VehicleIssue issue;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final color = issue.tone == Tone.err ? AppColors.err : AppColors.warn;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(issue.tone == Tone.err ? Icons.error_outline : Icons.warning_amber, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(issue.text, style: TextStyle(color: color, fontSize: 13)),
          ),
          if (issue.removable)
            TextButton(onPressed: () => c.removedOnPurpose(issue.key), child: Text(tr('Removed on purpose'))),
          if (issue.fix != null)
            OutlinedButton(
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              onPressed: () {
                onOpen();
                c.showPage(issue.fix!);
              },
              child: Text(tr(issue.action ?? 'Open')),
            ),
          IconButton(
            tooltip: tr('Hide for this session'),
            onPressed: () => c.dismissIssue(issue.key),
            icon: const Icon(Icons.close, size: 16),
          ),
        ],
      ),
    );
  }
}

/// Yellow box listing this page's settings written since boot, with "Revert to boot values".
class ChangedSinceBoot extends StatelessWidget {
  const ChangedSinceBoot(this.c, this.page, {super.key});
  final BoardController c;
  final AppPage page;

  @override
  Widget build(BuildContext context) {
    final changed = c.changedOnPage(page);
    if (changed.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.warn.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warn.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.history, size: 18, color: AppColors.warn),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${tr('Changed since boot:')} ${changed.map((e) => '${e.$1} ${e.$2 == null ? '' : '(${formatParam(e.$2!)} → ${formatParam(c.params[e.$1] ?? 0)})'}').join(', ')}',
              style: const TextStyle(color: AppColors.warn, fontSize: 12.5),
            ),
          ),
          TextButton(onPressed: () => c.revertToBoot(page), child: Text(tr('Revert to boot values'))),
        ],
      ),
    );
  }
}

/// A row of labelled values for the information cards.
class InfoRows extends StatelessWidget {
  const InfoRows(this.rows, {super.key});
  final List<(String, String, Tone)> rows;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final (key, value, tone) in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3.5),
          child: Row(
            children: [
              Muted(key),
              const SizedBox(width: 16),
              Expanded(
                child: SelectableText(
                  value,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: monoStyle.copyWith(color: toneColor(tone)),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
