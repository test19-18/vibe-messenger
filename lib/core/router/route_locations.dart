const publicAuthPaths = <String>{'/login', '/register', '/reset-password'};

String? validatedInternalRedirect(String? location) {
  if (location == null ||
      !location.startsWith('/') ||
      location.startsWith('//') ||
      location.contains('\\')) {
    return null;
  }

  final uri = Uri.tryParse(location);
  if (uri == null ||
      uri.hasScheme ||
      uri.host.isNotEmpty ||
      uri.path.startsWith('//') ||
      publicAuthPaths.contains(uri.path)) {
    return null;
  }
  return location;
}

String publicAuthLocation(String path, {String? from}) {
  assert(publicAuthPaths.contains(path), 'Expected a public auth path.');
  final destination = validatedInternalRedirect(from);
  return Uri(
    path: path,
    queryParameters: destination == null ? null : {'from': destination},
  ).toString();
}
