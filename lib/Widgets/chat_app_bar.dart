import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:reins/Constants/constants.dart';
import 'package:reins/Models/connection.dart';
import 'package:reins/Widgets/chat_configure_bottom_sheet.dart';
import 'package:reins/Widgets/ollama_bottom_sheet_header.dart';
import 'package:reins/Widgets/selection_bottom_sheet.dart';
import 'package:provider/provider.dart';
import 'package:reins/Providers/chat_provider.dart';
import 'package:reins/Providers/connection_provider.dart';
import 'package:responsive_framework/responsive_framework.dart';

class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);
    final connectionProvider = Provider.of<ConnectionProvider>(context);

    return AppBar(
      title: Column(
        children: [
          Text(AppConstants.appName, style: GoogleFonts.pacifico()),
          if (chatProvider.currentChat != null)
            InkWell(
              onTap: () {
                _handleModelSelectionButton(context);
              },
              customBorder: StadiumBorder(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Builder(builder: (context) {
                      final connId = chatProvider.currentChat!.connectionId;
                      final conn = connId != null
                          ? connectionProvider.getConnection(connId)
                          : null;
                      if (conn?.type == ConnectionType.openclaw)
                        return Padding(
                          padding: const EdgeInsets.only(right: 4.0),
                          child: Icon(
                            Icons.cloud_outlined,
                            size: 12,
                            color: Theme.of(context).textTheme.labelSmall?.color,
                          ),
                        );
                      return const SizedBox.shrink();
                    }),
                    Text(
                      chatProvider.currentChat!.model,
                      style: GoogleFonts.kodeMono(
                        textStyle: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.tune),
          onPressed: () {
            _handleConfigureButton(context);
          },
        ),
      ],
      forceMaterialTransparency: !ResponsiveBreakpoints.of(context).isMobile,
    );
  }

  Future<void> _handleModelSelectionButton(BuildContext context) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    final models = await chatProvider.fetchAvailableModels();

    final selectedModelName = await showSelectionBottomSheet(
      key: ValueKey("model-selection"),
      context: context,
      header: OllamaBottomSheetHeader(title: "Change The Model"),
      fetchItems: () async =>
          models.map((model) => model.toString()).toList(),
      currentSelection: chatProvider.currentChat!.model,
    );

    if (selectedModelName != null) {
      // Find the actual model name (without connection prefix) from the display string
      final selectedModel = models.where(
        (m) => m.toString() == selectedModelName,
      ).firstOrNull;
      if (selectedModel != null) {
        await chatProvider.updateCurrentChat(newModel: selectedModel.name);
      }
    }
  }

  Future<void> _handleConfigureButton(BuildContext context) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    final arguments = chatProvider.currentChatConfiguration;

    final ChatConfigureBottomSheetAction? action = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Padding(
          padding: MediaQuery.of(context).viewInsets,
          child: ChatConfigureBottomSheet(arguments: arguments),
        );
      },
    );

    // If the user deletes the chat, we don't need to update the chat.
    if (action == ChatConfigureBottomSheetAction.delete) return;

    await chatProvider.updateCurrentChat(
      newSystemPrompt: arguments.systemPrompt,
      newOptions: arguments.chatOptions,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
