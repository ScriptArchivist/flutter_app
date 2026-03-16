class ApiException implements Exception {
  final String message;
  ApiException(this.message);
}

String parseError(dynamic data) {
  if (data is Map && data["error"] != null) {
    return data["error"]["message"];
  }

  if (data is Map && data["detail"] != null) {
    return data["detail"].toString();
  }

  return "Unknown error";
}