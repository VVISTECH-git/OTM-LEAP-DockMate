import 'package:flutter/foundation.dart';
import '../models/shipment_group_model.dart';
import '../services/shipment_group_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/api_client.dart';

enum LoadState { idle, loading, success, error }

class ShipmentGroupsProvider extends ChangeNotifier {
  /// Static weak reference so ApiClient can call reset() without BuildContext.
  static ShipmentGroupsProvider? instanceForReset;
  List<ShipmentGroup> _groups = [];
  LoadState _state = LoadState.idle;
  String    _error = '';

  ShipmentGroupsProvider() { instanceForReset = this; }

  @override
  void dispose() {
    if (instanceForReset == this) instanceForReset = null;
    super.dispose();
  }

  // Default: OUTBOUND on first login.
  String _team        = 'outbound';
  String _searchQuery = '';

  // ─── Getters ──────────────────────────────────────────────────────────────

  LoadState get state    => _state;
  String get error       => _error;
  String get team        => _team;
  String get searchQuery => _searchQuery;
  bool get isInbound     => _team == 'inbound';

  List<ShipmentGroup> get groups {
    if (_searchQuery.isEmpty) return _groups;
    final q = _searchQuery.toLowerCase();
    return _groups.where((g) =>
        g.shipGroupXid.toLowerCase().contains(q) ||
        g.truckPlate.toLowerCase().contains(q)).toList();
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<void> init() async {
    // Restore last used team, fallback to outbound.
    final saved = await SessionService.instance.lastTeam;
    _team = saved.isNotEmpty ? saved : 'outbound';
    await load();
  }

  Future<void> load() async {
    _state = LoadState.loading;
    _error = '';
    notifyListeners();

    try {
      _groups = await ShipmentGroupService.instance.fetchGroups(
        direction: isInbound ? 'INBOUND' : 'OUTBOUND',
      );
      if (kDebugMode) debugPrint('Provider: loaded ${_groups.length} groups ($_team)');
      _state = LoadState.success;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Provider error: $e');
        if (e is ApiException) {
          debugPrint('ApiException status: ${e.statusCode}, body: ${e.message}');
        }
      }
      _error = e.toString().replaceAll('Exception: ', '');
      _state = LoadState.error;
    }

    notifyListeners();
  }

  /// Switch tab and trigger a fresh server-side fetch.
  Future<void> switchTeam() async {
    _team        = isInbound ? 'outbound' : 'inbound';
    _searchQuery = '';
    await SessionService.instance.setLastTeam(_team);
    await load();
  }

  void setSearch(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// Wipes in-memory state so a re-login on a different account never
  /// sees the previous user's shipment groups.
  void reset() {
    _groups      = [];
    _state       = LoadState.idle;
    _error       = '';
    _team        = 'outbound';
    _searchQuery = '';
    notifyListeners();
  }
}
