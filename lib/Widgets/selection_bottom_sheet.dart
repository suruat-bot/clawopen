import 'package:flutter/material.dart';
import 'package:clawopen/Models/ollama_request_state.dart';
import 'package:async/async.dart';

class SelectionBottomSheet<T> extends StatefulWidget {
  final Widget header;
  final Future<List<T>> Function() fetchItems;
  final T? currentSelection;

  const SelectionBottomSheet({
    super.key,
    required this.header,
    required this.fetchItems,
    required this.currentSelection,
  });

  @override
  State<SelectionBottomSheet<T>> createState() => _SelectionBottomSheetState();
}

class _SelectionBottomSheetState<T> extends State<SelectionBottomSheet<T>> {
  static final _itemsBucket = PageStorageBucket();

  T? _selectedItem;
  List<T> _items = [];
  List<T> _filteredItems = [];
  String _searchQuery = '';

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  var _state = OllamaRequestState.uninitialized;
  late CancelableOperation _fetchOperation;

  @override
  void initState() {
    super.initState();

    // Load the previous state of the items list
    _items = _itemsBucket.readState(context, identifier: widget.key) ?? [];
    _filteredItems = _items;
    _selectedItem = widget.currentSelection;

    _fetchOperation = CancelableOperation.fromFuture(_fetchItems());
  }

  @override
  void dispose() {
    _fetchOperation.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchItems() async {
    setState(() {
      _state = OllamaRequestState.loading;
    });

    try {
      _items = await widget.fetchItems();

      _state = OllamaRequestState.success;

      if (mounted) {
        _itemsBucket.writeState(context, _items, identifier: widget.key);
      }
    } catch (e) {
      _state = OllamaRequestState.error;
    }

    if (mounted) {
      _applyFilter();
      setState(() {});
    }
  }

  void _applyFilter() {
    if (_searchQuery.isEmpty) {
      _filteredItems = _items;
    } else {
      final query = _searchQuery.toLowerCase();
      _filteredItems = _items.where((item) {
        return item.toString().toLowerCase().contains(query);
      }).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: widget.header),
              if (_items.isNotEmpty && _state == OllamaRequestState.loading)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: CircularProgressIndicator(),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Search field
          TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            decoration: InputDecoration(
              hintText: 'Search models...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                          _applyFilter();
                        });
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
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
                _applyFilter();
              });
            },
            onTapOutside: (_) => _searchFocusNode.unfocus(),
          ),
          const SizedBox(height: 4),
          // Item count
          if (_items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  Text(
                    _searchQuery.isEmpty
                        ? '${_items.length} models'
                        : '${_filteredItems.length} of ${_items.length} models',
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
          const Divider(),
          Expanded(
            child: _buildBody(context),
          ),
          const Divider(),
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop(widget.currentSelection);
              Navigator.of(context).pushNamed('/models');
            },
            icon: const Icon(Icons.apps, size: 18),
            label: const Text('Browse All Models'),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(widget.currentSelection);
                },
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  if (_selectedItem != null) {
                    Navigator.of(context).pop(_selectedItem);
                  }
                },
                child: const Text('Select'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_state == OllamaRequestState.error) {
      return Center(
        child: Text(
          'An error occurred while fetching the items.'
          '\nCheck your server connection and try again.',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    } else if (_state == OllamaRequestState.loading && _items.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    } else if (_state == OllamaRequestState.success || _items.isNotEmpty) {
      if (_items.isEmpty) {
        return Center(child: Text('No items found.'));
      }

      if (_filteredItems.isEmpty) {
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

      return RefreshIndicator(
        onRefresh: () async {
          _fetchOperation = CancelableOperation.fromFuture(_fetchItems());
        },
        child: ListView.builder(
          itemCount: _filteredItems.length,
          itemBuilder: (context, index) {
            final item = _filteredItems[index];

            return RadioListTile(
              title: Text(item.toString()),
              value: item,
              groupValue: _selectedItem,
              onChanged: (value) {
                setState(() {
                  _selectedItem = value;
                });
              },
            );
          },
        ),
      );
    } else {
      return const SizedBox.shrink();
    }
  }
}

Future<T> showSelectionBottomSheet<T>({
  ValueKey? key,
  required BuildContext context,
  required Widget header,
  required Future<List<T>> Function() fetchItems,
  required T currentSelection,
}) async {
  return await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return SelectionBottomSheet(
            key: key,
            header: header,
            fetchItems: fetchItems,
            currentSelection: currentSelection,
          );
        },
      );
    },
    isDismissible: false,
    enableDrag: false,
  );
}
