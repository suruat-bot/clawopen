import 'package:clawopen/Models/ollama_chat.dart';

class ChatConfigureArguments {
  String? systemPrompt;
  OllamaChatOptions chatOptions;
  OpenClawThinkingLevel? thinkingLevel;

  ChatConfigureArguments({
    required this.systemPrompt,
    required this.chatOptions,
    this.thinkingLevel,
  });

  static get defaultArguments => ChatConfigureArguments(
        systemPrompt: null,
        chatOptions: OllamaChatOptions(),
      );
}
