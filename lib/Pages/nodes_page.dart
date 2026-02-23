import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:reins/Models/openclaw_event.dart';
import 'package:reins/Models/openclaw_node.dart';
import 'package:reins/Providers/openclaw_provider.dart';

class NodesPage extends StatelessWidget {
  const NodesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Nodes', style: GoogleFonts.pacifico()),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<OpenClawProvider>().refreshNodes(),
          ),
        ],
      ),
      body: SafeArea(
        child: Consumer<OpenClawProvider>(
          builder: (context, provider, _) {
            if (provider.wsState == OpenClawWsState.disconnected) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off,
                        size: 48,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.4)),
                    const SizedBox(height: 16),
                    Text('Not connected to any gateway',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color
                                  ?.withOpacity(0.6),
                            )),
                  ],
                ),
              );
            }

            final nodes = provider.nodes;

            if (nodes.isEmpty) {
              return Center(
                child: Text(
                  'No paired nodes',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.color
                            ?.withOpacity(0.6),
                      ),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: nodes.length,
              itemBuilder: (context, index) => _NodeTile(node: nodes[index]),
            );
          },
        ),
      ),
    );
  }
}

class _NodeTile extends StatelessWidget {
  final OpenClawNode node;

  const _NodeTile({required this.node});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _platformIcon,
                  size: 24,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        node.platformLabel,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.color
                                  ?.withOpacity(0.6),
                            ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: node.isOnline
                        ? Colors.green.withOpacity(0.15)
                        : Colors.grey.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    node.isOnline ? 'Online' : 'Offline',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: node.isOnline ? Colors.green : Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            if (node.capabilities.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: node.capabilities
                    .map((cap) => Chip(
                          label: Text(cap,
                              style: Theme.of(context).textTheme.labelSmall),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData get _platformIcon {
    switch (node.platform?.toLowerCase()) {
      case 'ios':
        return Icons.phone_iphone;
      case 'android':
        return Icons.phone_android;
      case 'macos':
        return Icons.laptop_mac;
      default:
        return Icons.devices;
    }
  }
}
