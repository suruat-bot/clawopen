import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:reins/Providers/openclaw_provider.dart';

/// Shows pending OpenClaw tool approval requests as a banner.
class ApprovalBanner extends StatelessWidget {
  const ApprovalBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<OpenClawProvider>(
      builder: (context, provider, _) {
        if (provider.pendingApprovals.isEmpty) {
          return const SizedBox.shrink();
        }

        final approval = provider.pendingApprovals.first;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.security,
                  size: 20,
                  color: Theme.of(context).colorScheme.onTertiaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Approval Required',
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onTertiaryContainer,
                                ),
                      ),
                      Text(
                        approval.toolName,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onTertiaryContainer
                                  .withOpacity(0.8),
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () =>
                      provider.resolveApproval(approval.requestId, false),
                  style: TextButton.styleFrom(
                    foregroundColor:
                        Theme.of(context).colorScheme.onTertiaryContainer,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Deny'),
                ),
                FilledButton(
                  onPressed: () =>
                      provider.resolveApproval(approval.requestId, true),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Approve'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
