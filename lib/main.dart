import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app/app.dart';
import 'core/constants/hive_keys.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  GoogleFonts.config.allowRuntimeFetching = false;

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

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