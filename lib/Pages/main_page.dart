import 'package:flutter/material.dart';
import 'package:clawopen/Pages/chat_page/chat_page.dart';
import 'package:clawopen/Widgets/chat_app_bar.dart';
import 'package:clawopen/Widgets/chat_drawer.dart';
import 'package:responsive_framework/responsive_framework.dart';

class ClawOpenMainPage extends StatelessWidget {
  const ClawOpenMainPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (ResponsiveBreakpoints.of(context).isMobile) {
      return _ClawOpenMobileMainPage();
    } else {
      return _ClawOpenLargeMainPage();
    }
  }
}

class _ClawOpenMobileMainPage extends StatelessWidget {
  const _ClawOpenMobileMainPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: ChatAppBar(),
      body: SafeArea(child: ChatPage()),
      drawer: ChatDrawer(),
    );
  }
}

class _ClawOpenLargeMainPage extends StatelessWidget {
  const _ClawOpenLargeMainPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            ChatDrawer(),
            Expanded(child: ChatPage()),
          ],
        ),
      ),
    );
  }
}
