import 'package:flutter/foundation.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/session_service.dart';
import '../models/shipment_group_model.dart';

class ShipmentGroupService {
  ShipmentGroupService._();
  static final ShipmentGroupService instance = ShipmentGroupService._();

  /// Fetches shipment groups filtered server-side by direction (INBOUND/OUTBOUND).
  /// Excludes groups where attributeDate2 is set (already loaded + left premises).
  Future<List<ShipmentGroup>> fetchGroups({
    required String direction, // "INBOUND" or "OUTBOUND"
    int limit  = 100,
    int offset = 0,
  }) async {
    final query = Uri.encodeComponent('attribute5 eq "$direction" and not attributeDate2 pr');
    final path  = '${AppConstants.pathShipmentGroups}'
        '?limit=$limit&offset=$offset'
        '&q=$query'
        '&expand=refnums,sourceLocation,destLocation'
        '&fields=shipGroupXid,numberOfShipments,totalWeight,totalVolume,'
        'attributeNumber1,attribute2,attribute5,attributeDate5,attributeDate6,refnums,'
        'sourceLocation.locationName,destLocation.locationName';

    if (kDebugMode) {
      debugPrint('=== fetchGroups ($direction) ===');
      debugPrint('path: $path');
    }

    final data  = await ApiClient.instance.get(path);

    if (data is! Map<String, dynamic>) {
      if (kDebugMode) debugPrint('fetchGroups: unexpected response type: ${data.runtimeType}');
      return [];
    }
    final rawItems = data['items'];
    if (rawItems != null && rawItems is! List) {
      if (kDebugMode) debugPrint('fetchGroups: items is not a List — got ${rawItems.runtimeType}');
      return [];
    }
    final items = (rawItems as List<dynamic>?) ?? [];

    if (kDebugMode) debugPrint('items: ${items.length}');

    // Location names are expanded inline — no extra round-trips needed.
    final groups = <ShipmentGroup>[];
    for (int i = 0; i < items.length; i++) {
      try {
        final j = items[i];
        if (j is! Map<String, dynamic>) continue;
        groups.add(ShipmentGroup.fromJson(j));
      } catch (e) {
        if (kDebugMode) debugPrint('fetchGroups: parse error at index $i: $e');
      }
    }
    return groups;
  }

  /// Fetches a single group by GID with location names resolved inline.
  Future<ShipmentGroup> fetchById(String groupId) async {
    final domain = await SessionService.instance.domain;
    final gid    = groupId.contains('.') ? groupId : '$domain.$groupId';

    if (kDebugMode) debugPrint('=== fetchById: $gid ===');

    const fields = 'shipGroupXid,numberOfShipments,totalWeight,totalVolume,'
        'attributeNumber1,attribute2,attribute5,attributeDate5,attributeDate6,'
        'refnums,sourceLocation.locationName,destLocation.locationName';

    final data = await ApiClient.instance.get(
      '${AppConstants.pathShipmentGroups}/$gid'
      '?expand=refnums,sourceLocation,destLocation'
      '&fields=$fields',
    );

    return ShipmentGroup.fromJson(data as Map<String, dynamic>);
  }
}