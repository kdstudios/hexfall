import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'persistence/app_state.dart';
import 'persistence/key_value_store.dart';
import 'services/audio_service.dart';
import 'services/haptics.dart';
import 'services/sound_library.dart';
import 'theme/hexfall_theme.dart';
import 'ui/screens/menu_screens.dart';
import 'ui/widgets/sci_fi.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    // Right-click is a game input (flag), so suppress the browser's menu.
    await BrowserContextMenu.disableContextMenu();
  }

  KeyValueStore store;
  try {
    store = await PrefsStore.open();
  } catch (_) {
    store = MemoryStore(); // storage unavailable: game still playable
  }
  final app = await AppState.load(store);

  final sounds = await SoundLibrary.load(store);

  AudioService audio;
  try {
    audio = PlayersAudio(sounds);
  } catch (_) {
    audio = SilentAudio();
  }

  final services = Services(
    app: app,
    audio: audio,
    haptics: Haptics(enabled: app.settings.haptics),
    sounds: sounds,
  );
  runApp(HexfallApp(services: services));
}

class HexfallApp extends StatelessWidget {
  const HexfallApp({super.key, required this.services});

  final Services services;

  @override
  Widget build(BuildContext context) {
    return ServicesScope(
      services: services,
      child: ListenableBuilder(
        listenable: services.app,
        builder: (context, _) => MaterialApp(
          title: 'HEXFALL',
          debugShowCheckedModeBanner: false,
          theme: HexfallTheme.materialTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(services.app.settings.uiScale),
            ),
            child: child!,
          ),
          home: const MainMenuScreen(),
        ),
      ),
    );
  }
}
