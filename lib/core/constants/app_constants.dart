import 'package:flutter/material.dart';

class AppConstants {
  AppConstants._();

  // ─── Prefs Keys ───────────────────────────────────────────────────────────
  static const String prefInstanceUrl = 'instance_url';
  static const String prefAuthHeader  = 'auth_header';
  static const String prefUserId      = 'user_id';
  static const String prefUser        = 'user';
  static const String prefDomain      = 'domain';
  static const String prefLastTeam    = 'fp_last_team';

  // ─── Default ──────────────────────────────────────────────────────────────
  static const String defaultInstanceUrl =
      'https://otmgtm-test-bttfusion.otmgtm.me-jeddah-1.ocs.oraclecloud.com';
  static const String defaultDomain = 'DEMO';

  // ─── API Paths ────────────────────────────────────────────────────────────
  static const String pathValidateLogin =
      '/logisticsRestApi/resources-int/v2/items/DEFAULT?fields=itemXid';
  static const String pathShipmentGroups =
      '/logisticsRestApi/resources-int/v2/shipmentGroups';
  static const String pathLocations =
      '/logisticsRestApi/resources-int/v2/locations';
  static const String pathDocuments =
      '/logisticsRestApi/resources-int/v2/documents';

  // ─── Document Upload ──────────────────────────────────────────────────────
  static const int maxDocuments = 20;  // ← changed from 5 to 20
  static const int imageQuality = 85;
  static const int imageMaxWidth = 1920;
  static const int imageMaxHeight = 1080;

  static const List<String> docTypes = [
    'POD', 'BOL', 'Invoice', 'Packing List',
    'Inspection', 'Customs', 'Other',
  ];

  // ─── Nokia Brand Colors ───────────────────────────────────────────────────
  static const Color nokiaBlue       = Color(0xFF124191); // Primary
  static const Color nokiaBrightBlue = Color(0xFF005AFF); // Accent
  static const Color navy            = Color(0xFF124191); // alias → nokiaBlue
  static const Color blue            = Color(0xFF005AFF); // alias → nokiaBrightBlue
  static const Color inboundGreen    = Color(0xFF0D7A4E);
  static const Color outboundOrange  = Color(0xFFC45E00);
  static const Color bgGrey          = Color(0xFFF4F6FB);
  static const Color borderGrey      = Color(0xFFE2E8F0);
  static const Color textGrey        = Color(0xFF8892A4);
  static const Color errorRed        = Color(0xFFE01E35);
}