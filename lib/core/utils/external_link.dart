/// Turns an API-supplied URL into a link that is safe to open.
///
/// Only absolute `http`/`https` URLs are accepted. Anything else (for example
/// `javascript:`, `data:` or a relative path) yields null, so a malformed or
/// hostile `siteUrl` in a response can never be launched as a script or an
/// unexpected scheme.
Uri? safeExternalUri(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  return uri;
}
