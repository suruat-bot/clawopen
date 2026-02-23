import 'package:flutter/material.dart';

/// Represents a configured chat channel on an OpenClaw Gateway.
class OpenClawChannel {
  final String name;
  final bool enabled;
  final String connectionId;
  final String connectionName;

  const OpenClawChannel({
    required this.name,
    required this.enabled,
    required this.connectionId,
    required this.connectionName,
  });

  OpenClawChannel copyWith({bool? enabled}) => OpenClawChannel(
        name: name,
        enabled: enabled ?? this.enabled,
        connectionId: connectionId,
        connectionName: connectionName,
      );

  /// Human-readable display name.
  String get displayName {
    const names = {
      'telegram': 'Telegram',
      'whatsapp': 'WhatsApp',
      'discord': 'Discord',
      'slack': 'Slack',
      'signal': 'Signal',
      'imessage': 'iMessage',
      'teams': 'Microsoft Teams',
      'mattermost': 'Mattermost',
      'googlechat': 'Google Chat',
      'nostr': 'Nostr',
      'zalo': 'Zalo',
      'line': 'LINE',
      'feishu': 'Feishu',
      'matrix': 'Matrix',
      'irc': 'IRC',
      'nextcloud': 'Nextcloud Talk',
      'synology': 'Synology Chat',
    };
    return names[name.toLowerCase()] ??
        '${name[0].toUpperCase()}${name.substring(1)}';
  }

  /// Material icon for the channel.
  IconData get icon {
    switch (name.toLowerCase()) {
      case 'telegram':
        return Icons.send;
      case 'whatsapp':
        return Icons.phone_in_talk;
      case 'discord':
        return Icons.headset_mic;
      case 'slack':
        return Icons.workspaces;
      case 'signal':
        return Icons.lock;
      case 'imessage':
        return Icons.chat_bubble;
      case 'teams':
        return Icons.video_call;
      case 'mattermost':
        return Icons.forum;
      case 'googlechat':
        return Icons.chat;
      case 'nostr':
        return Icons.bolt;
      case 'matrix':
        return Icons.grid_view;
      case 'irc':
        return Icons.terminal;
      default:
        return Icons.chat_bubble_outline;
    }
  }
}
