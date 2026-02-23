import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:clawopen/Constants/constants.dart';
import 'package:clawopen/Models/settings_route_arguments.dart';
import 'package:clawopen/Pages/chat_page/chat_page_view_model.dart';
import 'package:clawopen/Pages/main_page.dart';
import 'package:clawopen/Pages/settings_page/settings_page.dart';
import 'package:clawopen/Pages/model_library_page.dart';
import 'package:clawopen/Pages/sessions_page.dart';
import 'package:clawopen/Pages/nodes_page.dart';
import 'package:clawopen/Pages/channels_page.dart';
import 'package:clawopen/Providers/chat_provider.dart';
import 'package:clawopen/Providers/connection_provider.dart';
import 'package:clawopen/Providers/model_provider.dart';
import 'package:clawopen/Providers/openclaw_provider.dart';
import 'package:clawopen/Services/services.dart';
import 'package:clawopen/Utils/material_color_adapter.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:clawopen/Utils/request_review_helper.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'dart:io' show Platform;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialize PathManager
  await PathManager.initialize();

  // Initialize Hive
  if (Platform.isLinux) {
    Hive.init(PathManager.instance.documentsDirectory.path);
  } else {
    await Hive.initFlutter();
  }

  Hive.registerAdapter(MaterialColorAdapter());

  await Hive.openBox('settings');

  // Initialize RequestReviewHelper and request review if needed
  final reviewHelper = await RequestReviewHelper.initialize();

  await reviewHelper.incrementCount(isLaunch: true);

  try {
    final inAppReview = InAppReview.instance;
    if (await inAppReview.isAvailable() && reviewHelper.shouldRequestReview()) {
      await inAppReview.requestReview();
    }
  } catch (_) {
    // Review prompt may fail if view controller isn't ready yet
  }

  runApp(
    MultiProvider(
      providers: [
        Provider(create: (_) => DatabaseService()),
        Provider(create: (_) => PermissionService()),
        Provider(create: (_) => ImageService()),
        ChangeNotifierProvider(
          create: (_) => ConnectionProvider(Hive.box('settings')),
        ),
        ChangeNotifierProvider(
          create: (_) => ModelProvider(Hive.box('settings')),
        ),
        ChangeNotifierProvider(
          create: (context) => OpenClawProvider(
            connectionProvider: context.read<ConnectionProvider>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => ChatProvider(
            connectionProvider: context.read<ConnectionProvider>(),
            modelProvider: context.read<ModelProvider>(),
            databaseService: context.read<DatabaseService>(),
            openclawProvider: context.read<OpenClawProvider>(),
          ),
        ),
        Provider(
          create: (context) => ChatPageViewModel(
            permissionService: context.read<PermissionService>(),
            imageService: context.read<ImageService>(),
          ),
        ),
      ],
      child: const ClawOpenApp(),
    ),
  );
}

class ClawOpenApp extends StatelessWidget {
  const ClawOpenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Hive.box('settings').listenable(
        keys: ['color', 'brightness'],
      ),
      builder: (context, box, _) {
        return MaterialApp(
          title: AppConstants.appName,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              brightness: _brightness ?? MediaQuery.platformBrightnessOf(context),
              dynamicSchemeVariant: DynamicSchemeVariant.neutral,
              seedColor: box.get('color', defaultValue: Colors.grey),
            ),
            appBarTheme: const AppBarTheme(centerTitle: true),
            useMaterial3: true,
          ),
          builder: (context, child) => ResponsiveBreakpoints.builder(
            breakpoints: [
              const Breakpoint(start: 0, end: 450, name: MOBILE),
              const Breakpoint(start: 451, end: 800, name: TABLET),
              const Breakpoint(start: 801, end: 1920, name: DESKTOP),
            ],
            useShortestSide: true,
            child: child!,
          ),
          onGenerateRoute: (settings) {
            if (settings.name == '/') {
              return MaterialPageRoute(
                builder: (context) => const ClawOpenMainPage(),
              );
            }

            if (settings.name == '/settings') {
              final args = settings.arguments as SettingsRouteArguments?;

              return MaterialPageRoute(
                builder: (context) => SettingsPage(arguments: args),
              );
            }

            if (settings.name == '/models') {
              return MaterialPageRoute(
                builder: (context) => const ModelLibraryPage(),
              );
            }

            if (settings.name == '/sessions') {
              return MaterialPageRoute(
                builder: (context) => const SessionsPage(),
              );
            }

            if (settings.name == '/nodes') {
              return MaterialPageRoute(
                builder: (context) => const NodesPage(),
              );
            }

            if (settings.name == '/channels') {
              return MaterialPageRoute(
                builder: (context) => const ChannelsPage(),
              );
            }

            assert(false, 'Need to implement ${settings.name}');
            return null;
          },
        );
      },
    );
  }

  Brightness? get _brightness {
    final brightnessValue = Hive.box('settings').get('brightness');
    if (brightnessValue == null) return null;
    return brightnessValue == 1 ? Brightness.light : Brightness.dark;
  }
}
