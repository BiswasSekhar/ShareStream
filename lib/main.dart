import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'providers/room_provider.dart';
import 'screens/home_screen.dart';
import 'screens/developer_screen.dart';

import 'utils/app_logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger.init();
  await dotenv.load(fileName: '.env');
  MediaKit.ensureInitialized();

  runApp(const ShareStreamApp());
}

class ShareStreamApp extends StatelessWidget {
  const ShareStreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => RoomProvider())],
      child: MaterialApp(
        title: 'ShareStream',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const HomeScreen(),
        onGenerateRoute: (settings) {
          final uri = Uri.parse(settings.name ?? '');
          if (uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'join') {
            final code = uri.pathSegments.length > 1
                ? uri.pathSegments[1]
                : null;
            return MaterialPageRoute(
              builder: (_) => HomeScreen(arguments: code),
              settings: settings,
            );
          }
          if (uri.pathSegments.isNotEmpty &&
              uri.pathSegments.first == 'developer') {
            return MaterialPageRoute(
              builder: (_) => const DeveloperScreen(),
              settings: settings,
            );
          }
          return null;
        },
      ),
    );
  }
}
