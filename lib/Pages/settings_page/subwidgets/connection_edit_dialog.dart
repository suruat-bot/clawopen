import 'package:flutter/material.dart';
import 'package:reins/Models/connection.dart';
import 'package:reins/Models/ollama_request_state.dart';
import 'package:reins/Providers/connection_provider.dart';
import 'package:provider/provider.dart';

class ConnectionEditDialog extends StatefulWidget {
  final Connection? connection;

  const ConnectionEditDialog({super.key, this.connection});

  @override
  State<ConnectionEditDialog> createState() => _ConnectionEditDialogState();
}

class _ConnectionEditDialogState extends State<ConnectionEditDialog> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _authTokenController = TextEditingController();
  final _agentIdController = TextEditingController();

  ConnectionType _type = ConnectionType.ollama;
  bool _isDefault = false;
  bool _obscureToken = true;

  OllamaRequestState _testState = OllamaRequestState.uninitialized;
  String? _errorText;

  bool get _isEditing => widget.connection != null;

  @override
  void initState() {
    super.initState();
    if (widget.connection != null) {
      final conn = widget.connection!;
      _nameController.text = conn.name;
      _urlController.text = conn.baseUrl;
      _authTokenController.text = conn.authToken ?? '';
      _agentIdController.text = conn.agentId;
      _type = conn.type;
      _isDefault = conn.isDefault;
    } else {
      _agentIdController.text = 'main';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _authTokenController.dispose();
    _agentIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  _isEditing ? 'Edit Connection' : 'Add Connection',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    children: [
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Connection Name',
                          hintText: 'My Ollama Server',
                          border: OutlineInputBorder(),
                        ),
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<ConnectionType>(
                        value: _type,
                        decoration: const InputDecoration(
                          labelText: 'Type',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: ConnectionType.ollama,
                            child: Text('Ollama'),
                          ),
                          DropdownMenuItem(
                            value: ConnectionType.openclaw,
                            child: Text('OpenClaw Gateway'),
                          ),
                          DropdownMenuItem(
                            value: ConnectionType.openaiCompatible,
                            child: Text('OpenAI-Compatible'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _type = value;
                              _testState = OllamaRequestState.uninitialized;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _urlController,
                        keyboardType: TextInputType.url,
                        onChanged: (_) => setState(() {
                          _errorText = null;
                          _testState = OllamaRequestState.uninitialized;
                        }),
                        decoration: InputDecoration(
                          labelText: 'Base URL',
                          hintText: _type == ConnectionType.ollama
                              ? 'http://localhost:11434'
                              : _type == ConnectionType.openclaw
                                  ? 'http://192.168.1.100:17585'
                                  : 'https://api.openai.com',
                          border: const OutlineInputBorder(),
                          errorText: _errorText,
                          helperText: _type == ConnectionType.openaiCompatible
                              ? 'Works with OpenAI, Groq, OpenRouter, Together, NVIDIA NIM, Mistral, DeepSeek, etc.'
                              : null,
                          helperMaxLines: 2,
                        ),
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                      ),
                      if (_type == ConnectionType.openclaw ||
                          _type == ConnectionType.openaiCompatible) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _authTokenController,
                          obscureText: _obscureToken,
                          onChanged: (_) => setState(() {
                            _testState = OllamaRequestState.uninitialized;
                          }),
                          decoration: InputDecoration(
                            labelText: _type == ConnectionType.openaiCompatible
                                ? 'API Key'
                                : 'Auth Token (optional)',
                            hintText: _type == ConnectionType.openaiCompatible
                                ? 'sk-...'
                                : 'Gateway authentication token',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(_obscureToken
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () =>
                                  setState(() => _obscureToken = !_obscureToken),
                            ),
                          ),
                          onTapOutside: (_) =>
                              FocusManager.instance.primaryFocus?.unfocus(),
                        ),
                      ],
                      if (_type == ConnectionType.openclaw) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _agentIdController,
                          onChanged: (_) => setState(() {
                            _testState = OllamaRequestState.uninitialized;
                          }),
                          decoration: const InputDecoration(
                            labelText: 'Agent ID',
                            hintText: 'main',
                            border: OutlineInputBorder(),
                            helperText: 'The agent to use (default: main)',
                          ),
                          onTapOutside: (_) =>
                              FocusManager.instance.primaryFocus?.unfocus(),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('Default Connection'),
                        subtitle: const Text(
                            'New chats will use this connection by default'),
                        value: _isDefault,
                        onChanged: (value) =>
                            setState(() => _isDefault = value),
                        contentPadding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 16),
                      // Test Connection button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _testState == OllamaRequestState.loading
                              ? null
                              : _handleTestConnection,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Test Connection'),
                              const SizedBox(width: 10),
                              Container(
                                width: MediaQuery.of(context)
                                    .textScaler
                                    .scale(10),
                                height: MediaQuery.of(context)
                                    .textScaler
                                    .scale(10),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _statusColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: _handleSave,
                        child: Text(_isEditing ? 'Update' : 'Add'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color get _statusColor {
    switch (_testState) {
      case OllamaRequestState.error:
        return Colors.red;
      case OllamaRequestState.loading:
        return Colors.orange;
      case OllamaRequestState.success:
        return Colors.green;
      case OllamaRequestState.uninitialized:
        return Colors.grey;
    }
  }

  Future<void> _handleTestConnection() async {
    if (_urlController.text.isEmpty) {
      setState(() {
        _errorText = 'Please enter a URL';
        _testState = OllamaRequestState.error;
      });
      return;
    }

    setState(() {
      _errorText = null;
      _testState = OllamaRequestState.loading;
    });

    try {
      final conn = _buildConnection();
      final provider = context.read<ConnectionProvider>();
      final result = await provider.testConnection(conn);

      if (!mounted) return;

      setState(() {
        _testState = result
            ? OllamaRequestState.success
            : OllamaRequestState.error;
        if (!result) {
          _errorText = 'Could not connect. Check URL and ensure the server is running.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testState = OllamaRequestState.error;
        _errorText = 'Connection failed: ${e.toString()}';
      });
    }
  }

  String get _defaultName {
    switch (_type) {
      case ConnectionType.ollama:
        return 'Ollama';
      case ConnectionType.openclaw:
        return 'OpenClaw Gateway';
      case ConnectionType.openaiCompatible:
        return 'OpenAI-Compatible';
    }
  }

  Connection _buildConnection() {
    return Connection(
      id: widget.connection?.id,
      name: _nameController.text.isEmpty ? _defaultName : _nameController.text,
      type: _type,
      baseUrl: _urlController.text,
      authToken: (_type == ConnectionType.openclaw ||
              _type == ConnectionType.openaiCompatible)
          ? (_authTokenController.text.isEmpty
              ? null
              : _authTokenController.text)
          : null,
      agentId: _type == ConnectionType.openclaw
          ? (_agentIdController.text.isEmpty ? 'main' : _agentIdController.text)
          : 'main',
      isDefault: _isDefault,
    );
  }

  void _handleSave() {
    if (_urlController.text.isEmpty) {
      setState(() {
        _errorText = 'Please enter a URL';
      });
      return;
    }

    final conn = _buildConnection();
    final provider = context.read<ConnectionProvider>();

    if (_isEditing) {
      provider.updateConnection(conn);
    } else {
      provider.addConnection(conn);
    }

    if (_isDefault) {
      provider.setDefault(conn.id);
    }

    Navigator.pop(context);
  }
}
