const mainGroupName = 'TENVPN';
const autoGroupName = 'Авто';
const manualGroupName = 'Вручную';
const autoPrimaryGroupName = 'Авто · обычные';
const autoWhitelistGroupName = 'Авто · белые списки';
const awgDefaultName = '🛡 Протокол Амнезия';
const awgSectionTitle = 'Протокол Амнезия';

/// Hidden tiers inside «Авто»; the UI looks through them to the real server.
const autoTierGroupNames = {autoPrimaryGroupName, autoWhitelistGroupName};

// Dart's \w is ASCII-only even in unicode mode, hence the explicit ranges.
final whitelistWords = RegExp(
  r'бел[а-яё]*\s+спис[а-яё]*',
  caseSensitive: false,
);

const reservedProxyNames = {
  mainGroupName,
  autoGroupName,
  manualGroupName,
  autoPrimaryGroupName,
  autoWhitelistGroupName,
  'DIRECT',
  'REJECT',
  'REJECT-DROP',
  'PASS',
  'COMPATIBLE',
  'GLOBAL',
};
