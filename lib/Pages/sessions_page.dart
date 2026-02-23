import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:clawopen/Models/connection.dart';
import 'package:clawopen/Models/openclaw_session.dart';
import 'package:clawopen/Providers/connection_provider.dart';
import 'package:clawopen/Services/openclaw_service.dart';

class SessionsPage extends StatefulWidget {
  const SessionsPage({super.key});

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  List<OpenClawSession> _sessions = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchSessions();
  }

  Future<void> _fetchSessions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final connProvider = context.read<ConnectionProvider>();
      final openclawConns = connProvider.connections
          .where((c) => c.type == ConnectionType.openclaw)
          .toList();

      final allSessions = <OpenClawSession>[];
      for (final conn in openclawConns) {
        try {
          final service = connProvider.getService(conn.id) as OpenClawService;
          final rawSessions = await service.listSessions();
          for (final raw in rawSessions) {
            allSessions
                .add(OpenClawSession.fromJson(raw, connectionId: conn.id));
          }
        } catch (_) {
          // Connection might be offline
        }
      }

      if (mounted) {
        setState(() {
          _sessions = allSessions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Sessions', style: GoogleFonts.pacifico()),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchSessions,
          ),
        ],
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                color: Theme.of(context).colorScheme.error, size: 48),
            const SizedBox(height: 16),
            Text('Failed to load sessions',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextButton(onPressed: _fetchSessions, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_sessions.isEmpty) {
      return Center(
        child: Text(
          'No active sessions',
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
      onRefresh: _fetchSessions,
      child: ListView.builder(
        itemCount: _sessions.length,
        itemBuilder: (context, index) {
          final session = _sessions[index];
          return _SessionTile(
            session: session,
            onTap: () => _showSessionHistory(session),
          );
        },
      ),
    );
  }

  Future<void> _showSessionHistory(OpenClawSession session) async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _SessionDetailPage(session: session),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final OpenClawSession session;
  final VoidCallback onTap;

  const _SessionTile({required this.session, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final connProvider = context.read<ConnectionProvider>();
    final conn = connProvider.getConnection(session.connectionId);

    return ListTile(
      leading: const Icon(Icons.chat_bubble_outline),
      title: Text(
        session.shortKey,
        style: GoogleFonts.kodeMono(
          textStyle: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
      subtitle: Text([
        if (session.agentId != null) 'Agent: ${session.agentId}',
        if (conn != null) conn.name,
        if (session.messageCount > 0) '${session.messageCount} messages',
      ].join(' · ')),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _SessionDetailPage extends StatefulWidget {
  final OpenClawSession session;

  const _SessionDetailPage({required this.session});

  @override
  State<_SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends State<_SessionDetailPage> {
  List<OpenClawSessionMessage> _messages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    setState(() => _isLoading = true);

    try {
      final connProvider = context.read<ConnectionProvider>();
      final service = connProvider.getService(widget.session.connectionId)
          as OpenClawService;
      final rawMessages =
          await service.getSessionHistory(widget.session.sessionKey);

      if (mounted) {
        setState(() {
          _messages = rawMessages
              .map((m) => OpenClawSessionMessage.fromJson(m))
              .toList();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.session.shortKey,
          style: GoogleFonts.kodeMono(
            textStyle: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _messages.isEmpty
                ? Center(
                    child: Text(
                      'No messages in this session',
                      style:
                          Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.color
                                    ?.withOpacity(0.6),
                              ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isUser = msg.role == 'user';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              isUser
                                  ? Icons.person_outline
                                  : Icons.smart_toy_outlined,
                              size: 20,
                              color: isUser
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                      .colorScheme
                                      .secondary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isUser ? 'User' : 'Assistant',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  SelectableText(
                                    msg.content,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
