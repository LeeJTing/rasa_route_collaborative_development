import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'client/views/main_shell_view/main_shell_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://odtmtukexckfjbuqkxyo.supabase.co',
    publishableKey: 'sb_publishable_Z3WBHi4Q87UtlPX2-9wgxg_jspPG7uc',
  );

  runApp(const RasaRouteApp());
}

class RasaRouteApp extends StatelessWidget {
  const RasaRouteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rasa Route',
      debugShowCheckedModeBanner: false,

      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFFFFF8E7),

        colorScheme: const ColorScheme.light(
          primary: Color(0xFFFF9700),
          secondary: Color(0xFFF0B400),
          surface: Color(0xFFFFF8E7),
        ),
      ),

      home: const MainShellView(),
    );
  }
}