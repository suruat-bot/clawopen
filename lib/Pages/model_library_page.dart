import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:clawopen/Models/connection.dart';
import 'package:clawopen/Models/ollama_model.dart';
import 'package:clawopen/Providers/connection_provider.dart';
import 'package:clawopen/Providers/model_provider.dart';

class ModelLibraryPage extends StatefulWidget {
  const ModelLibraryPage({super.key});

  @override
  State<ModelLibraryPage> createState() => _ModelLibraryPageState();
}

class _ModelLibraryPageState extends State<ModelLibraryPage> {
  List<OllamaModel> _allModels = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchModels();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchModels() async {
    setState(() => _isLoading = true);
    try {
      final connectionProvider = context.read<ConnectionProvider>();
      final models = await connectionProvider.fetchAllModels();
      if (mounted) {
        setState(() {
          _allModels = models;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<OllamaModel> get _filteredModels {
    if (_searchQuery.isEmpty) return _allModels;
    final query = _searchQuery.toLowerCase();
    return _allModels.where((m) {
      return m.name.toLowerCase().contains(query) ||
          (m.connectionName?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  /// Group models by connection name.
  Map<String, List<OllamaModel>> get _groupedModels {
    final map = <String, List<OllamaModel>>{};
    for (final model in _filteredModels) {
      final group = model.connectionName ?? 'Unknown';
      map.putIfAbsent(group, () => []).add(model);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Model Library', style: GoogleFonts.pacifico()),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search models...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
              ),
            ),
            // Model count
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Consumer<ModelProvider>(
                builder: (context, modelProvider, _) {
                  final addedCount = _allModels
                      .where((m) => modelProvider.isAdded(
                          m.name, m.connectionId))
                      .length;
                  return Row(
                    children: [
                      Text(
                        _searchQuery.isEmpty
                            ? '$addedCount of ${_allModels.length} models added'
                            : '${_filteredModels.length} results',
                        style:
                            Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.color
                                      ?.withOpacity(0.6),
                                ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 1),
            // Model list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _allModels.isEmpty
                      ? Center(
                          child: Text(
                            'No models found.\nCheck your connections in Settings.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.color
                                      ?.withOpacity(0.6),
                                ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _fetchModels,
                          child: _buildGroupedList(),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedList() {
    final groups = _groupedModels;

    if (groups.isEmpty) {
      return Center(
        child: Text(
          'No models matching "$_searchQuery"',
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

    return Consumer<ModelProvider>(
      builder: (context, modelProvider, _) {
        return ListView.builder(
          itemCount: groups.entries.fold<int>(
              0, (sum, entry) => sum + 1 + entry.value.length),
          itemBuilder: (context, index) {
            // Walk through groups to find the right item
            int current = 0;
            for (final entry in groups.entries) {
              if (index == current) {
                // Section header
                final connectionProvider = context.read<ConnectionProvider>();
                final conn = connectionProvider.connections
                    .where((c) => c.name == entry.key)
                    .firstOrNull;
                return _buildSectionHeader(
                    context, entry.key, conn, entry.value);
              }
              current++;
              if (index < current + entry.value.length) {
                final model = entry.value[index - current];
                return _buildModelTile(context, model, modelProvider);
              }
              current += entry.value.length;
            }
            return const SizedBox.shrink();
          },
        );
      },
    );
  }

  Widget _buildSectionHeader(BuildContext context, String connectionName,
      Connection? conn, List<OllamaModel> models) {
    final modelProvider = context.read<ModelProvider>();
    final allAdded = models.every(
        (m) => modelProvider.isAdded(m.name, m.connectionId));

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
      child: Row(
        children: [
          Icon(
            conn?.type == ConnectionType.ollama
                ? Icons.dns_outlined
                : conn?.type == ConnectionType.openclaw
                    ? Icons.cloud_outlined
                    : Icons.api_outlined,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              connectionName,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          Text(
            '${models.length} models',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.color
                      ?.withOpacity(0.5),
                ),
          ),
          IconButton(
            icon: Icon(
              allAdded ? Icons.remove_circle_outline : Icons.add_circle_outline,
              size: 20,
              color: allAdded
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
            ),
            tooltip: allAdded ? 'Remove all' : 'Add all',
            onPressed: () {
              if (allAdded) {
                for (final m in models) {
                  if (m.connectionId != null) {
                    modelProvider.removeModel(m.name, m.connectionId!);
                  }
                }
              } else {
                for (final m in models) {
                  modelProvider.addModel(m);
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModelTile(
      BuildContext context, OllamaModel model, ModelProvider modelProvider) {
    final isAdded = modelProvider.isAdded(model.name, model.connectionId);

    return ListTile(
      dense: true,
      title: Text(model.name),
      subtitle: model.details.family.isNotEmpty
          ? Text(
              model.details.family,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.color
                        ?.withOpacity(0.5),
                  ),
            )
          : null,
      trailing: IconButton(
        icon: Icon(
          isAdded ? Icons.check_circle : Icons.add_circle_outline,
          color: isAdded
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        onPressed: () {
          if (isAdded) {
            modelProvider.removeModel(model.name, model.connectionId!);
          } else {
            modelProvider.addModel(model);
          }
        },
      ),
    );
  }
}
