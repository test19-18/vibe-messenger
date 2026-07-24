import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/screen_protection_service.dart';

final screenProtectionServiceProvider = Provider<ScreenProtectionService>((
  ref,
) {
  return ScreenProtectionService(const MethodChannelScreenProtectionApi());
});
