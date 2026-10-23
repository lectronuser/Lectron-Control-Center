import 'package:flutter/material.dart';

import '../core/board_controller.dart';
import '../core/models.dart';
import 'theme.dart';
import 'widgets.dart';

/// Yellow banners with the vehicle's missing sensors and setup steps; [only] limits them to some pages' fixes.
class IssueBanners extends StatelessWidget {
  const IssueBanners(this.c, {super.key, this.only});
  final BoardController c;
  final Set<AppPage>? only;

  @override
  Widget build(BuildContext context) {
    if (!(c.storage.getBool('banners') ?? true)) return const SizedBox.shrink();
    final issues = [
      for (final i in c.vehicleIssues())
        if (only == null || (i.fix != null && only!.contains(i.fix)) || (only!.isEmpty && i.fix == null)) i,
    ];
    if (issues.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final issue in issues) _Banner(c, issue)],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.c, this.issue);
  final BoardController c;
  final VehicleIssue issue;

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
            TextButton(onPressed: () => c.removedOnPurpose(issue.key), child: Text('Removed on purpose')),
          if (issue.fix != null && issue.fix != c.page)
            OutlinedButton(
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              onPressed: () => c.showPage(issue.fix!),
              child: Text(issue.action ?? 'Open'),
            ),
          IconButton(
            tooltip: 'Hide for this session',
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
              'Changed since boot: ${changed.map((e) => '${e.$1} ${e.$2 == null ? '' : '(${formatParam(e.$2!)} → ${formatParam(c.params[e.$1] ?? 0)})'}').join(', ')}',
              style: const TextStyle(color: AppColors.warn, fontSize: 12.5),
            ),
          ),
          TextButton(onPressed: () => c.revertToBoot(page), child: Text('Revert to boot values')),
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
