import '../services/app_settings_service.dart';

String formatDisplayNumber(
  num value, {
  int fractionDigits = 2,
  bool? fixedDecimals,
}) {
  final useFixed = fixedDecimals ?? AppSettingsService.instance.showFixedDecimals;
  var formatted = value.toStringAsFixed(fractionDigits);
  if (!useFixed) {
    formatted = formatted.replaceFirst(RegExp(r'\.?0+$'), '');
  }
  if (formatted == '-0') return '0';
  return formatted;
}

String formatMoney(num value) {
  return formatDisplayNumber(value, fractionDigits: 0, fixedDecimals: true);
}

