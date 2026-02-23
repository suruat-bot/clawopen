import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:reins/Models/connection.dart';
import 'package:reins/Models/settings_route_arguments.dart';
import 'package:reins/Providers/connection_provider.dart';
import 'package:reins/Models/openclaw_event.dart';
import 'package:reins/Providers/model_provider.dart';
import 'package:reins/Providers/openclaw_provider.dart';

import 'subwidgets/subwidgets.dart';

class SettingsPage extends StatelessWidget {
  final SettingsRouteArguments? arguments;

  const SettingsPage({super.key, this.arguments});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings', style: GoogleFonts.pacifico()),
      ),
      body: SafeArea(
        child: _SettingsPageContent(arguments: arguments),
      ),
    );
  }
}

class _SettingsPageContent extends StatelessWidget {
  final SettingsRouteArguments? arguments;

  const _SettingsPageContent({required this.arguments});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        ThemesSettings(),
        SizedBox(height: 16),
        ConnectionsSettings(),
        SizedBox(height: 16),
        _MyModelsCard(),
        SizedBox(height: 16),
        _OpenClawCardsSection(),
        ReinsSettings(),
      ],
    );
  }
}

class _MyModelsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Consumer<ModelProvider>(
        builder: (context, modelProvider, _) {
          final count = modelProvider.myModels.length;
          return ListTile(
            leading: const Icon(Icons.star_outline),
            title: const Text('My Models'),
            subtitle: Text(
              count == 0
                  ? 'No models added yet'
                  : '$count model${count == 1 ? '' : 's'} selected',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/models'),
          );
        },
      ),
    );
  }
}

class _OpenClawCardsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionProvider>(
      builder: (context, connProvider, _) {
        final hasOpenClaw = connProvider.connections
            .any((c) => c.type == ConnectionType.openclaw);
        if (!hasOpenClaw) return const SizedBox.shrink();

        return Column(
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Sessions'),
                subtitle: const Text('View active gateway sessions'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).pushNamed('/sessions'),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Consumer<OpenClawProvider>(
                builder: (context, ocProvider, _) {
                  final nodeCount = ocProvider.nodes.length;
                  return ListTile(
                    leading: const Icon(Icons.devices),
                    title: const Text('Nodes'),
                    subtitle: Text(
                      nodeCount == 0
                          ? 'View paired devices'
                          : '$nodeCount node${nodeCount == 1 ? '' : 's'} available',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).pushNamed('/nodes'),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}
