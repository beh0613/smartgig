import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import '../models/user.dart' as model;
import 'active_ride_page.dart';

// Persistent state class to keep driver online status during navigation
class DriverState {
  static bool isOnline = false;
}

class MainPage extends StatefulWidget {
  const MainPage({super.key, required this.user});
  final model.User user;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final Completer<GoogleMapController> _controller = Completer<GoogleMapController>();
  final SupabaseClient _supabase = Supabase.instance.client;

  StreamSubscription<Position>? _positionStream;
  StreamSubscription? _bookingStream;

  // State Variables
  bool _isTracking = DriverState.isOnline;
  bool _mapReady = false;
  double _totalEarnings = 0.0;
  bool _isLoading = true;
  Map<String, dynamic>? currentRideData;

  final List<LatLng> _routePoints = [];
  Set<Polyline> _polylines = {};
  Set<Marker> _rideMarkers = {};

  // Update this to your FastAPI Server IP
  // Update your API URL to the new Cloud Run address
  final String _baseApiUrl = "https://trust-model-service-385992390190.asia-southeast1.run.app/get_risk";

  static const CameraPosition _kInitialPosition = CameraPosition(
    target: LatLng(6.4675, 100.5055),
    zoom: 15.0,
  );

  @override
  void initState() {
    super.initState();
    _checkActiveRide();
    _fetchEarnings();
    if (_isTracking) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startLocationUpdates();
        _setupRealtimeBookingListener();
      });
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _bookingStream?.cancel();
    super.dispose();
  }

  Future<void> _checkActiveRide() async {
    try {
      final data = await _supabase
          .from('bookings')
          .select()
          .or('status.eq.accepting,status.eq.on_way,status.eq.picked_up,status.eq.paid')
          .maybeSingle();

      if (data != null && mounted) {
        setState(() => currentRideData = data);
      }
    } catch (e) {
      debugPrint("Check active ride error: $e");
    }
  }

  // --- UPDATED API CALL (Supports Dynamic Weighting) ---
  // --- UPDATED API CALL ---
  Future<Map<String, dynamic>?> _getRiskScore(double lat, double lon, String? passengerId) async {
    try {
      debugPrint("📡 REQUESTING RISK → User: ${widget.user.id}, Passenger: $passengerId");

      final response = await http.post(
        Uri.parse(_baseApiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "lat": lat,
          "lon": lon,
          "user_id": widget.user.id,
          "passenger_id": passengerId ?? "", // Send the ID to the backend
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint("🚨 RISK API FAILED: $e");
    }
    return null;
  }

  Future<void> _fetchNearbyRides(Position position) async {
    if (!_isTracking || !mounted) return;
    try {
      final List<dynamic> data = await _supabase.from('bookings').select().eq('status', 'pending');
      Set<Marker> newMarkers = {};

      for (var ride in data) {
        double pLat = double.parse(ride['pickup_latitude'].toString());
        double pLng = double.parse(ride['pickup_longitude'].toString());

        double dist = Geolocator.distanceBetween(
          position.latitude, position.longitude, pLat, pLng,
        );

        if (dist <= 10000) {
          newMarkers.add(
            Marker(
              markerId: MarkerId(ride['id'].toString()),
              position: LatLng(pLat, pLng),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
              infoWindow: InfoWindow(
                title: "RM${ride['total_price']}",
                snippet: "Tap to view safety risk",
                onTap: () => _showRideRequestSheet(ride),
              ),
            ),
          );
        }
      }
      if (mounted) setState(() => _rideMarkers = newMarkers);
    } catch (e) {
      debugPrint("Fetch Error: $e");
    }
  }

  void _showRideRequestSheet(Map<String, dynamic> ride) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Analyzing Safety Risks based on your settings..."), duration: Duration(seconds: 2)),
    );

    // Extract passenger_id from the ride map (ensure your Supabase query selects this column)
    final String? pId = ride['passenger_id']?.toString();

    final pickupRisk = await _getRiskScore(
      double.parse(ride['pickup_latitude'].toString()),
      double.parse(ride['pickup_longitude'].toString()),
      pId, // Pass it here
    );

    final destRisk = await _getRiskScore(
      double.parse(ride['destination_latitude'].toString()),
      double.parse(ride['destination_longitude'].toString()),
      pId, // Pass it here
    );

    bool isPickupSelected = true;
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final activeData = isPickupSelected ? pickupRisk : destRisk;
          final double score = (activeData?['risk_score'] ?? 0.0).toDouble();
          final Map<String, dynamic> details = activeData?['details'] ?? {};
          final visual = getRiskVisual(score);
          final Color themeColor = Color(int.parse(visual['color']!.replaceAll('#', '0xFF')));

          // CATEGORY 1: Passenger Behavioral only
          final passengerCategory = <String, dynamic>{};
          // CATEGORY 2: The other 5 indicators
          final environmentCategory = <String, dynamic>{};

          details.forEach((key, value) {
            if (key == 'abnormal_request') {
              passengerCategory[key] = value;
            } else {
              environmentCategory[key] = value;
            }
          });

          return Padding(
            padding: const EdgeInsets.fromLTRB(25, 25, 25, 40),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Safety Risk Analysis", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),

                  Container(
                    height: 45,
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        _buildToggleTab("PICKUP", isPickupSelected, () => setModalState(() => isPickupSelected = true)),
                        _buildToggleTab("DESTINATION", !isPickupSelected, () => setModalState(() => isPickupSelected = false)),
                      ],
                    ),
                  ),
                  // ... inside builder ...
                  const SizedBox(height: 30),

// PARALLEL ANALYSIS CARD
                  _buildParallelRiskAnalysis(details, themeColor, score, visual['status']!),

                  const SizedBox(height: 30),
// ... rest of indicators ...

                  // --- CATEGORY 1: PASSENGER BEHAVIORAL ---
                  if (passengerCategory.isNotEmpty) ...[
                    _buildSectionHeader("PASSENGER PROFILE"),
                    ...passengerCategory.entries.map((e) => _buildRiskIndicator(_formatKey(e.key), e.value)),
                    const SizedBox(height: 15),
                  ],

                  // --- CATEGORY 2: EXTERNAL ENVIRONMENT (THE OTHER 5) ---
                  if (environmentCategory.isNotEmpty) ...[
                    _buildSectionHeader("ENVIRONMENTAL & AREA RISKS"),
                    ...environmentCategory.entries.map((e) => _buildRiskIndicator(_formatKey(e.key), e.value)),
                  ],

                  const Divider(height: 40),
                  Text("📍 Pickup: ${ride['pickup_address']}", style: const TextStyle(fontSize: 13, color: Colors.black87)),
                  const SizedBox(height: 8),
                  Text("🏁 Destination: ${ride['destination_address']}", style: const TextStyle(fontSize: 13, color: Colors.black87)),
                  const SizedBox(height: 15),
                  Text("Fare: RM ${ride['total_price']}", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green)),
                  const SizedBox(height: 25),
                  _buildActionButtons(ride),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatKey(String key) {
    switch(key) {
      case 'abnormal_request': return 'Abnormal Passenger Behavioral'; // The single category
      case 'reported_crime': return 'Reported Crime Rate';
      case 'road_accident': return 'Road Accident History';
      case 'road_condition': return 'Road Infrastructure';
      case 'weather': return 'Weather Conditions';
      case 'lightning': return 'Lightning';
      default: return key.toUpperCase();
    }
  }

  Map<String, String> getRiskVisual(double score) {
    if (score <= 20) return {"status": "VERY SAFE", "color": "#008000"};
    if (score <= 40) return {"status": "MODERATE SAFE", "color": "#FFD700"}; // Improved Gold for visibility
    if (score <= 60) return {"status": "MODERATE RISKY", "color": "#FFA500"};
    if (score <= 80) return {"status": "HIGH RISK", "color": "#FF0000"};
    return {"status": "VERY HIGH RISK", "color": "#8B0000"};
  }

  // --- ACTIONS ---
  Future<void> _acceptRide(Map<String, dynamic> ride) async {
    try {
      await _supabase.from('bookings').update({'status': 'accepting'}).eq('id', ride['id']);
      await _supabase.from('ride_assignments').insert({'booking_id': ride['id'], 'driver_id': widget.user.id});
      setState(() => currentRideData = ride);
      if (!mounted) return;
      Navigator.pop(context);
      Navigator.push(context, MaterialPageRoute(builder: (context) => ActiveRidePage(rideData: ride, driverUser: widget.user)));
    } catch (e) {
      debugPrint("Accept Error: $e");
    }
  }

  void _toggleOnlineStatus() async {
    setState(() {
      _isTracking = !_isTracking;
      DriverState.isOnline = _isTracking;
      if (!_isTracking) {
        _routePoints.clear();
        _polylines.clear();
        _rideMarkers.clear();
        _positionStream?.cancel();
        _bookingStream?.cancel();
      }
    });

    if (_isTracking) {
      final position = await _getCurrentLocation();
      final map = await _controller.future;
      map.animateCamera(CameraUpdate.newLatLngZoom(LatLng(position.latitude, position.longitude), 15));
      _startLocationUpdates();
      _setupRealtimeBookingListener();
    }
  }

  // --- MAP & LOCATION ---
  void _setupRealtimeBookingListener() {
    _bookingStream?.cancel();
    _bookingStream = _supabase.from('bookings').stream(primaryKey: ['id']).eq('status', 'pending').listen((data) async {
      if (_isTracking) {
        Position pos = await _getCurrentLocation();
        _fetchNearbyRides(pos);
      }
    });
  }

  Future<void> _startLocationUpdates() async {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15),
    ).listen((Position position) async {
      if (!_isTracking || !mounted) return;
      final LatLng currentLatLng = LatLng(position.latitude, position.longitude);
      setState(() {
        _routePoints.add(currentLatLng);
        _polylines = {
          Polyline(polylineId: const PolylineId('driver_route'), points: List.from(_routePoints), color: const Color(0xFF1E88E5), width: 5),
        };
      });
      _fetchNearbyRides(position);
      final controller = await _controller.future;
      controller.animateCamera(CameraUpdate.newLatLng(currentLatLng));
    });
  }

  Future<void> _fetchEarnings() async {
    try {
      final response = await _supabase.from('payments').select('amount, bookings!inner(ride_assignments!inner(driver_id))').eq('bookings.ride_assignments.driver_id', widget.user.id);
      double earnings = 0;
      if (response is List) {
        for (var row in response) earnings += double.tryParse(row['amount'].toString()) ?? 0.0;
      }
      if (mounted) setState(() { _totalEarnings = earnings; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<Position> _getCurrentLocation() async => await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _kInitialPosition,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            polylines: _polylines,
            markers: _rideMarkers,
            onMapCreated: (controller) { _controller.complete(controller); setState(() => _mapReady = true); },
          ),
          if (_mapReady) Positioned(top: 60, left: 20, right: 20, child: _buildTopStatusPill()),
          if (_mapReady) Positioned(bottom: 125, left: 0, right: 0, child: _buildGoOnlineAction()),
          if (_mapReady) Align(alignment: Alignment.bottomCenter, child: _buildFloatingBottomNav(context)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Text(
              title,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.blueGrey[400], letterSpacing: 1.1)
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: Colors.grey[200], thickness: 1)),
        ],
      ),
    );
  }

  // --- UI WIDGETS ---
  Widget _buildTopStatusPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            const Icon(Icons.account_balance_wallet_rounded, color: Colors.green, size: 20),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('WALLET', style: TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold)),
              Text(_isLoading ? '...' : 'RM ${_totalEarnings.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
          ]),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: _isTracking ? Colors.green[50] : Colors.red[50], borderRadius: BorderRadius.circular(15)),
            child: Text(_isTracking ? "ONLINE" : "OFFLINE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _isTracking ? Colors.green : Colors.red)),
          )
        ],
      ),
    );
  }

  Widget _buildGoOnlineAction() {
    return Center(
      child: GestureDetector(
        onTap: _toggleOnlineStatus,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
          decoration: BoxDecoration(color: _isTracking ? Colors.blueGrey[900] : const Color(0xFF0D47A1), borderRadius: BorderRadius.circular(30)),
          child: Text(_isTracking ? 'GO OFFLINE' : 'GO ONLINE', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildFloatingBottomNav(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(25, 0, 25, 30),
      height: 70,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(35), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15)]),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _navIcon(Icons.home_rounded, "Home", true, () {}),
          _navIcon(Icons.directions_car, "Active", false, () {
            if (currentRideData != null) {
              Navigator.pushReplacementNamed(context, '/active_ride', arguments: {'rideData': currentRideData, 'driverUser': widget.user});
            }
          }),
          _navIcon(Icons.chat_bubble_outline, "Inbox", false, () {
            Navigator.pushReplacementNamed(context, '/message_page', arguments: {'user': widget.user, 'activeRide': currentRideData});
          }),
          _navIcon(Icons.grid_view_rounded, "Dashboard", false, () {
            Navigator.pushReplacementNamed(context, '/driver_dashboard', arguments: {'user': widget.user, 'activeRide': currentRideData});
          }),
        ],
      ),
    );
  }

  Widget _navIcon(IconData icon, String label, bool isActive, VoidCallback onTap) {
    final Color color = isActive ? Colors.blue[900]! : Colors.grey;
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: color), Text(label, style: TextStyle(fontSize: 10, color: color))]));
  }



  Widget _buildParallelRiskAnalysis(Map<String, dynamic> details, Color themeColor, double score, String status) {
    bool isYellow = score > 20 && score <= 40;
    Color mainColor = isYellow ? const Color(0xFFFFD700) : themeColor;

    const Color backgroundSlate = Color(0xFF1E293B);
    const Color borderSlate = Color(0xFF334155);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: backgroundSlate,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: borderSlate, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              children: [
                Text("RADAR ANALYSIS",
                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 2, color: mainColor.withOpacity(0.7))),
                const SizedBox(height: 15),
                Transform(
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateX(-0.4),
                  alignment: FractionalOffset.center,
                  child: AspectRatio(
                    aspectRatio: 1.1,
                    child: RadarChart(
                        RadarChartData(
                          dataSets: [
                            RadarDataSet(
                              fillColor: mainColor.withOpacity(0.25),
                              borderColor: mainColor,
                              borderWidth: 4.0,
                              entryRadius: 5.0,
                              dataEntries: [
                                RadarEntry(value: (details['abnormal_request'] ?? 0).toDouble()),
                                RadarEntry(value: (details['reported_crime'] ?? 0).toDouble()),
                                RadarEntry(value: (details['road_accident'] ?? 0).toDouble()),
                                RadarEntry(value: (details['road_condition'] ?? 0).toDouble()),
                                RadarEntry(value: (details['weather'] ?? 0).toDouble()),
                                RadarEntry(value: (details['lightning'] ?? 0).toDouble()),
                              ],
                            ),
                          ],

                          radarShape: RadarShape.circle,
                          radarBackgroundColor: Colors.transparent,

                          // OUTER CIRCLE
                          radarBorderData: const BorderSide(
                            color: Colors.white,
                            width: 2.0,
                          ),

                          // INNER CIRCLES
                          gridBorderData: const BorderSide(
                            color: Colors.white,
                            width: 1.5,
                          ),

                          // ✅ THIS IS THE MISSING PART (tick lines)
                          tickBorderData: const BorderSide(
                            color: Colors.white,
                            width: 1.5,
                          ),

                          tickCount: 3,

                          ticksTextStyle: const TextStyle(
                            color: Colors.white, // can keep white or transparent
                            fontSize: 0, // hide numbers
                          ),

                          titleTextStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),

                          titlePositionPercentageOffset: 0.35,

                          getTitle: (index, angle) {
                            switch (index) {
                              case 0:
                                return const RadarChartTitle(text: 'BEHAVIOR');
                              case 1:
                                return const RadarChartTitle(text: 'CRIME');
                              case 2:
                                return const RadarChartTitle(text: 'ACCIDENT');
                              case 3:
                                return const RadarChartTitle(text: 'INFRA');
                              case 4:
                                return const RadarChartTitle(text: 'WEATHER');
                              case 5:
                                return const RadarChartTitle(text: 'LIGHT');
                              default:
                                return const RadarChartTitle(text: '');
                            }
                          },
                        )
                    ),
                  ),
                ),
              ],
            ),
          ),

          // SEPARATOR
          Container(
            height: 100, width: 1.5,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [Colors.transparent, borderSlate, Colors.transparent],
                  begin: Alignment.topCenter, end: Alignment.bottomCenter
              ),
            ),
          ),

          // RIGHT SIDE: HUD
          Expanded(
            flex: 4,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      height: 90, width: 90,
                      child: CircularProgressIndicator(
                        value: score / 100,
                        strokeWidth: 9,
                        backgroundColor: Colors.white.withOpacity(0.05),
                        valueColor: AlwaysStoppedAnimation<Color>(mainColor),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Column(
                      children: [
                        Text("${score.toStringAsFixed(0)}%",
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.5)),
                        Text("RISK", style: TextStyle(fontSize: 7, fontWeight: FontWeight.w900, color: mainColor.withOpacity(0.5))),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: mainColor.withOpacity(0.3), width: 1),
                  ),
                  child: Text(status, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: mainColor, letterSpacing: 0.5)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNeonBadge(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Text(status, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: color, letterSpacing: 0.5)),
    );
  }
  Widget _buildStatusPill(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Text(status, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5)),
    );
  }

  Widget _buildRiskIndicator(String label, dynamic value) {
    final double score = (value ?? 0.0).toDouble();
    final visual = getRiskVisual(score);
    final Color color = Color(int.parse(visual['color']!.replaceAll('#', '0xFF')));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              Text("${score.toStringAsFixed(0)}%", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score / 100,
              backgroundColor: Colors.grey[100],
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildActionButtons(Map<String, dynamic> ride) {
    return Row(children: [
      Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text("DECLINE", style: TextStyle(color: Colors.red)))),
      const SizedBox(width: 15),
      Expanded(child: ElevatedButton(onPressed: () => _acceptRide(ride), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D47A1)), child: const Text("ACCEPT", style: TextStyle(color: Colors.white)))),
    ]);
  }

  Widget _buildToggleTab(String label, bool isSelected, VoidCallback onTap) {
    return Expanded(child: GestureDetector(onTap: onTap, child: Container(alignment: Alignment.center, decoration: BoxDecoration(color: isSelected ? const Color(0xFF0D47A1) : Colors.transparent, borderRadius: BorderRadius.circular(10)), child: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.black54, fontWeight: FontWeight.bold, fontSize: 11)))));
  }
}