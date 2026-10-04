import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'app.dart';
import 'services/native_crypto.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop platforms (Linux, Windows) need sqflite FFI factory.
  if (Platform.isLinux || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Load the native C++ crypto library (liboctra_native.so).
  // Throws StateError if the library cannot be loaded — no Dart fallback.
  NativeCrypto.init();

  // Mobile-only: edge-to-edge mode and portrait lock.
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  runApp(OctopusWalletApp());
}
