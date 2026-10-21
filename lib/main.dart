import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.production();
  runApp(WaiterApp(services: services));
  await services.init();
}
