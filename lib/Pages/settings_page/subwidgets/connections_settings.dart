import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clawopen/Models/connection.dart';
import 'package:clawopen/Providers/connection_provider.dart';

import 'connection_edit_dialog.dart';

class ConnectionsSettings extends StatefulWidget {
  const ConnectionsSettings({super.key});

  @override
  State<ConnectionsSettings> createState() => _ConnectionsSettingsState();
}

class _ConnectionsSettingsState extends State<ConnectionsSettings> {
  @override
  void initState() {
    super.initState();
    // Refresh all connection statuses on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ConnectionProvider>().refreshAllStatuses();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionProvider>(
      builder: (context, provider, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Connections',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _showEditDialog(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Manage your Ollama servers and OpenClaw gateways.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.color
                        ?.withOpacity(0.7),
                  ),
            ),
            const SizedBox(height: 12),
            if (provider.connections.isEmpty)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('No connections configured'),
                  subtitle:
                      const Text('Tap + to add an Ollama or OpenClaw connection'),
                ),
              )
            else
              ...provider.connections.map((conn) {
                final isOnline = provider.connectionStatuses[conn.id] ?? false;
                return Dismissible(
                  key: ValueKey(conn.id),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (_) => _confirmDelete(context, conn),
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    color: Theme.of(context).colorScheme.error,
                    child: Icon(Icons.delete,
                        color: Theme.of(context).colorScheme.onError),
                  ),
                  child: Card(
                    child: ListTile(
                      leading: Icon(
                        conn.type == ConnectionType.ollama
                            ? Icons.dns_outlined
                            : conn.type == ConnectionType.openclaw
                                ? Icons.cloud_outlined
                                : Icons.api_outlined,
                      ),
                      title: Row(
                        children: [
                          Expanded(child: Text(conn.name)),
                          if (conn.isDefault)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(
                                Icons.star,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        conn.baseUrl,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isOnline ? Colors.green : Colors.red,
                        ),
                      ),
                      onTap: () => _showEditDialog(context, connection: conn),
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  Future<bool> _confirmDelete(
      BuildContext context, Connection connection) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Connection'),
        content: Text(
            'Are you sure you want to delete "${connection.name}"? Chats using this connection will fall back to the default.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<ConnectionProvider>().deleteConnection(connection.id);
              Navigator.pop(context, true);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showEditDialog(BuildContext context, {Connection? connection}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => ConnectionEditDialog(connection: connection),
    );
  }
}
