import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app/app.dart';
import 'core/constants/hive_keys.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait for consistent UX
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize Hive local storage
  await Hive.initFlutter();
  await _openHiveBoxes();

  runApp(
    const ProviderScope(
      child: ThaparStepUpApp(),
    ),
  );
}

Future<void> _openHiveBoxes() async {
  await Hive.openBox(HiveKeys.userBox);
  await Hive.openBox(HiveKeys.activityBox);
  await Hive.openBox(HiveKeys.challengeBox);
  await Hive.openBox(HiveKeys.walletBox);
  await Hive.openBox(HiveKeys.sessionBox);
  await Hive.openBox(HiveKeys.settingsBox);
  await Hive.openBox(HiveKeys.betBox);
  await Hive.openBox(HiveKeys.sportBuddyBox);
  await Hive.openBox(HiveKeys.leaderboardBox);
}
