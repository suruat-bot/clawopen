import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:clawopen/Models/ollama_request_state.dart';
import 'package:clawopen/Services/openclaw_service.dart';

class OpenClawSettings extends StatefulWidget {
  const OpenClawSettings({super.key});

  @override
  State<OpenClawSettings> createState() => _OpenClawSettingsState();
}

class _OpenClawSettingsState extends State<OpenClawSettings> {
  final _settingsBox = Hive.box('settings');

  final _gatewayUrlController = TextEditingController();
  final _authTokenController = TextEditingController();
  final _agentIdController = TextEditingController();

  OllamaRequestState _requestState = OllamaRequestState.uninitialized;
  bool get _isLoading => _requestState == OllamaRequestState.loading;

  String? _errorText;
  bool _isEnabled = false;
  bool _obscureToken = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    _isEnabled = _settingsBox.get('openclawEnabled', defaultValue: false);
    _gatewayUrlController.text = _settingsBox.get('openclawGatewayUrl', defaultValue: '');
    _authTokenController.text = _settingsBox.get('openclawAuthToken', defaultValue: '');
    _agentIdController.text = _settingsBox.get('openclawAgentId', defaultValue: 'main');

    // Test connection if already configured
    if (_isEnabled && _gatewayUrlController.text.isNotEmpty) {
      _testConnection();
    }
  }

  @override
  void dispose() {
    _gatewayUrlController.dispose();
    _authTokenController.dispose();
    _agentIdController.dispose();
    super.dispose();
  }

  void _saveSettings() {
    _settingsBox.put('openclawEnabled', _isEnabled);
    _settingsBox.put('openclawGatewayUrl', _gatewayUrlController.text);
    _settingsBox.put('openclawAuthToken', _authTokenController.text);
    _settingsBox.put('openclawAgentId', _agentIdController.text.isEmpty ? 'main' : _agentIdController.text);
  }

  Future<void> _testConnection() async {
    if (_gatewayUrlController.text.isEmpty) {
      setState(() {
        _errorText = 'Please enter a Gateway URL';
        _requestState = OllamaRequestState.error;
      });
      return;
    }

    setState(() {
      _errorText = null;
      _requestState = OllamaRequestState.loading;
    });

    try {
      final service = OpenClawService(
        baseUrl: _gatewayUrlController.text,
        authToken: _authTokenController.text,
        agentId: _agentIdController.text.isEmpty ? 'main' : _agentIdController.text,
      );

      final isConnected = await service.testConnection();

      if (!mounted) return;

      if (isConnected) {
        _requestState = OllamaRequestState.success;
        _saveSettings();
      } else {
        _requestState = OllamaRequestState.error;
        _errorText = 'Could not connect to Gateway. Check URL and ensure Gateway is running.';
      }
    } catch (e) {
      _requestState = OllamaRequestState.error;
      _errorText = 'Connection failed: ${e.toString()}';
    } finally {
      setState(() {});
    }
  }

  Color get _connectionStatusColor {
    switch (_requestState) {
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'OpenClaw Gateway',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            Switch(
              value: _isEnabled,
              onChanged: (value) {
                setState(() {
                  _isEnabled = value;
                  if (!value) {
                    _requestState = OllamaRequestState.uninitialized;
                  }
                });
                _saveSettings();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Connect to an OpenClaw Gateway for cloud-backed AI chat.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
              ),
        ),
        if (_isEnabled) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _gatewayUrlController,
            keyboardType: TextInputType.url,
            onChanged: (_) {
              setState(() {
                _errorText = null;
                _requestState = OllamaRequestState.uninitialized;
              });
            },
            decoration: InputDecoration(
              labelText: 'Gateway URL',
              hintText: 'http://192.168.1.100:17585',
              border: const OutlineInputBorder(),
              errorText: _errorText,
              suffixIcon: IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: () => _showInfoBottomSheet(context),
              ),
            ),
            onTapOutside: (PointerDownEvent event) {
              FocusManager.instance.primaryFocus?.unfocus();
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _authTokenController,
            obscureText: _obscureToken,
            onChanged: (_) {
              setState(() {
                _requestState = OllamaRequestState.uninitialized;
              });
            },
            decoration: InputDecoration(
              labelText: 'Auth Token (optional)',
              hintText: 'Gateway authentication token',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscureToken ? Icons.visibility_off : Icons.visibility),
                onPressed: () {
                  setState(() {
                    _obscureToken = !_obscureToken;
                  });
                },
              ),
            ),
            onTapOutside: (PointerDownEvent event) {
              FocusManager.instance.primaryFocus?.unfocus();
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _agentIdController,
            onChanged: (_) {
              setState(() {
                _requestState = OllamaRequestState.uninitialized;
              });
            },
            decoration: const InputDecoration(
              labelText: 'Agent ID',
              hintText: 'main',
              border: OutlineInputBorder(),
              helperText: 'The agent to use (default: main)',
            ),
            onTapOutside: (PointerDownEvent event) {
              FocusManager.instance.primaryFocus?.unfocus();
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _testConnection,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Test Connection'),
                  const SizedBox(width: 10),
                  Container(
                    width: MediaQuery.of(context).textScaler.scale(10),
                    height: MediaQuery.of(context).textScaler.scale(10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _connectionStatusColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _showInfoBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          bottom: false,
          minimum: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'What is OpenClaw Gateway?',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'OpenClaw is an AI agent platform that can connect to multiple LLM providers (OpenAI, Anthropic, local models, etc.).\n\n'
                'The Gateway is a server component that:\n'
                '• Routes your messages to configured AI models\n'
                '• Manages sessions and conversation history\n'
                '• Provides tools and capabilities to the AI\n\n'
                'To use OpenClaw Gateway:\n'
                '1. Install OpenClaw on a computer or server\n'
                '2. Run: openclaw gateway start\n'
                '3. Enable the chatCompletions HTTP endpoint in config\n'
                '4. Enter the Gateway URL above\n\n'
                'Learn more at: https://docs.openclaw.ai',
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}
