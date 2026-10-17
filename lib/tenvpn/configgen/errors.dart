enum ConfigGenErrorCode {
  empty,
  // Remnawave's answer to a User-Agent that does not start with `mihomo`.
  shareLinks,
  html,
  invalidYaml,
  notAConfig,
  noProxies,
  awgInvalid,
}

final class ConfigGenException implements Exception {
  final ConfigGenErrorCode code;
  final String? detail;

  const ConfigGenException(this.code, [this.detail]);

  String get message => switch (code) {
    ConfigGenErrorCode.empty => 'Подписка пришла пустой.',
    ConfigGenErrorCode.shareLinks =>
      'Сервер отдал ссылки вместо настроек приложения. '
          'Обновите приложение или напишите в поддержку.',
    ConfigGenErrorCode.html =>
      'Вместо подписки пришла веб-страница. '
          'Проверьте ссылку и интернет: возможно, сеть требует входа.',
    ConfigGenErrorCode.invalidYaml =>
      'Подписка повреждена: не удалось прочитать настройки.',
    ConfigGenErrorCode.notAConfig =>
      'По ссылке лежат не настройки подключения.',
    ConfigGenErrorCode.noProxies => 'В подписке нет ни одного сервера.',
    ConfigGenErrorCode.awgInvalid =>
      'Не удалось прочитать запасное подключение (AmneziaWG).',
  };

  @override
  String toString() => detail == null ? message : '$message ($detail)';
}
