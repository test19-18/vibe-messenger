import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_messenger/core/router/route_locations.dart';

void main() {
  group('validatedInternalRedirect', () {
    test('accepts protected app locations', () {
      expect(
        validatedInternalRedirect('/conversation/id?title=%D0%A7%D0%B0%D1%82'),
        '/conversation/id?title=%D0%A7%D0%B0%D1%82',
      );
    });

    test('rejects external, protocol-relative and auth locations', () {
      expect(validatedInternalRedirect('https://example.com'), isNull);
      expect(validatedInternalRedirect('//example.com'), isNull);
      expect(validatedInternalRedirect('/\\example.com'), isNull);
      expect(validatedInternalRedirect('/login'), isNull);
    });
  });

  test('publicAuthLocation safely preserves an internal destination', () {
    final location = publicAuthLocation(
      '/register',
      from: '/conversation/id?title=Vibe',
    );
    final uri = Uri.parse(location);

    expect(uri.path, '/register');
    expect(uri.queryParameters['from'], '/conversation/id?title=Vibe');
  });
}
