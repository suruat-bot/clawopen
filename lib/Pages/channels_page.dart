import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:clawopen/Models/openclaw_channel.dart';
import 'package:clawopen/Models/openclaw_event.dart';
import 'package:clawopen/Providers/openclaw_provider.dart';

class ChannelsPage extends StatefulWidget {
  const ChannelsPage({super.key});

  @override
  State<ChannelsPage> createState() => _ChannelsPageState();
}

class _ChannelsPageState extends State<ChannelsPage> {
  List<OpenClawChannel> _channels = [];
  bool _loading = true;
  String? _error;
  String? _debugInfo;

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  Future<void> _loadChannels() async {
    setState(() {
      _loading = true;
      _error = null;
      _debugInfo = null;
    });
    try {
      final provider = context.read<OpenClawProvider>();
      final channels = await provider.getChannels();
      if (mounted) {
        String? debug;
        if (channels.isEmpty) {
          // Fetch raw debug info to help diagnose why channels are empty
          debug = await provider.getRawConfigDebug();
        }
        setState(() {
          _channels = channels;
          _debugInfo = debug;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final debug =
            await context.read<OpenClawProvider>().getRawConfigDebug();
        setState(() {
          _error = e.toString();
          _debugInfo = debug;
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggleChannel(OpenClawChannel channel, bool enabled) async {
    // Optimistic update
    setState(() {
      final idx = _channels.indexWhere(
        (c) => c.name == channel.name && c.connectionId == channel.connectionId,
      );
      if (idx != -1) {
        _channels[idx] = _channels[idx].copyWith(enabled: enabled);
      }
    });

    try {
      await context.read<OpenClawProvider>().setChannelEnabled(
            channel.connectionId,
            channel.name,
            enabled,
          );
    } catch (e) {
      // Revert on failure
      if (mounted) {
        setState(() {
          final idx = _channels.indexWhere(
            (c) =>
                c.name == channel.name &&
                c.connectionId == channel.connectionId,
          );
          if (idx != -1) {
            _channels[idx] = _channels[idx].copyWith(enabled: !enabled);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update ${channel.displayName}: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Channels', style: GoogleFonts.pacifico()),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadChannels,
          ),
        ],
      ),
      body: SafeArea(
        child: Consumer<OpenClawProvider>(
          builder: (context, provider, _) {
            if (provider.wsState == OpenClawWsState.disconnected) {
              return _centered(
                icon: Icons.cloud_off,
                message: 'Not connected to any gateway',
              );
            }

            if (_loading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (_error != null) {
              return _centered(
                icon: Icons.error_outline,
                message: 'Could not load channels',
                detail: _error,
                debugInfo: _debugInfo,
              );
            }

            if (_channels.isEmpty) {
              return _centered(
                icon: Icons.cell_tower,
                message: 'No channels configured',
                detail: 'Add channel configuration to your gateway\'s openclaw.json',
                debugInfo: _debugInfo,
              );
            }

            // Group by connection
            final byConnection = <String, List<OpenClawChannel>>{};
            for (final ch in _channels) {
              byConnection
                  .putIfAbsent(ch.connectionId, () => [])
                  .add(ch);
            }

            final multipleConnections = byConnection.length > 1;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final entry in byConnection.entries) ...[
                  if (multipleConnections) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8, left: 4),
                      child: Text(
                        entry.value.first.connectionName,
                        style:
                            Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                    ),
                  ],
                  Card(
                    child: Column(
                      children: [
                        for (int i = 0; i < entry.value.length; i++) ...[
                          _ChannelTile(
                            channel: entry.value[i],
                            onToggle: (enabled) =>
                                _toggleChannel(entry.value[i], enabled),
                          ),
                          if (i < entry.value.length - 1)
                            const Divider(height: 1, indent: 56),
                        ],
                      ],
                    ),
                  ),
                  if (multipleConnections) const SizedBox(height: 16),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _centered({
    required IconData icon,
    required String message,
    String? detail,
    String? debugInfo,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 48),
          Icon(
            icon,
            size: 48,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.color
                      ?.withOpacity(0.6),
                ),
            textAlign: TextAlign.center,
          ),
          if (detail != null) ...[
            const SizedBox(height: 8),
            Text(
              detail,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.color
                        ?.withOpacity(0.5),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
          if (debugInfo != null) ...[
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                debugInfo,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  final OpenClawChannel channel;
  final ValueChanged<bool> onToggle;

  const _ChannelTile({required this.channel, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        channel.icon,
        color: channel.enabled
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
      ),
      title: Text(channel.displayName),
      subtitle: Text(
        channel.enabled ? 'Active' : 'Disabled',
        style: TextStyle(
          color: channel.enabled ? Colors.green : Colors.grey,
          fontSize: 12,
        ),
      ),
      trailing: Switch(
        value: channel.enabled,
        onChanged: onToggle,
      ),
    );
  }
}
