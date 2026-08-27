class AppException implements Exception {
  final String code;
  final String message;

  AppException(this.code, this.message);

  factory AppException.fromRaw(dynamic error) {
    final String str = error.toString().replaceAll("Exception: ", "").replaceAll("Exception", "").trim();

    String code = "UNKNOWN_ERROR";
    String message = str;

    if (str.contains('|')) {
      final parts = str.split('|');
      code = parts[0].trim();
      message = parts.sublist(1).join('|').trim();
    }

    // Traduction & clarification explicite des erreurs de Quota / Limite
    final lowerCode = code.toLowerCase();
    final lowerMsg = message.toLowerCase();

    if (lowerCode.contains("quota") ||
        lowerCode.contains("limit") ||
        lowerMsg.contains("limite") ||
        lowerMsg.contains("quota") ||
        lowerMsg.contains("maximum")) {
      return AppException(
        "QUOTA_EXCEEDED",
        "Vous avez atteint la limite maximale d'utilisateurs autorisée par votre formule d'abonnement actuelle.",
      );
    }

    return AppException(code, message.isNotEmpty ? message : "Une erreur inattendue est survenue.");
  }

  @override
  String toString() => "$code|$message";
}