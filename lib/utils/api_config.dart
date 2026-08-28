class ApiConfig {
  // Récupération de l'URL injectée à la compilation
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    // Valeur par défaut si aucun argument n'est passé (ex: débug local)
    defaultValue: 'http://10.0.2.2:8080/api',
  );

  // Exemples d'endpoints centralisés à partir de baseUrl
  static String get commandsEndpoint => '$baseUrl/commands';
  static String get customersEndpoint => '$baseUrl/customers';
  static String get syncEndpoint => '$baseUrl/sync';
}