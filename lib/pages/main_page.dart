import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import '../models/user.dart' as model;
import 'active_ride_page.dart';
import 'package:smartgig/state/driver_state.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'passenger_feedback_page.dart';


class MainPage extends StatefulWidget {
  const MainPage({super.key, required this.user});
  final model.User user;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final Completer<GoogleMapController> _controller = Completer<GoogleMapController>();
  final SupabaseClient _supabase = Supabase.instance.client;
  final String _prettyMapStyle = '''[{"featureType":"poi","stylers":[{"visibility":"off"}]},{"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},{"featureType":"transit","stylers":[{"visibility":"off"}]}]''';
  StreamSubscription<Position>? _positionStream;
  StreamSubscription? _bookingStream;
  // 1. Add this variable at the top of _MainPageState
  StreamSubscription? _activeRideStatusStream;
  // State Variables
  bool _isTracking = DriverState.isOnline;
  bool _mapReady = false;
  double _totalEarnings = 0.0;
  bool _isLoading = true;
  Map<String, dynamic>? currentRideData;

  final List<LatLng> _routePoints = [];
  Set<Polyline> _polylines = {};
  Set<Marker> _rideMarkers = {};
  Map<String, BitmapDescriptor> _customIcons = {};
  // ADD THIS HERE:
  final List<Map<String, dynamic>> flags = [
    {'label': 'Crowded', 'icon': Icons.groups_rounded, 'color': Colors.orange},
    {'label': 'No Parking', 'icon': Icons.local_parking_rounded, 'color': Colors.redAccent},
    {'label': 'Dimly Lit', 'icon': Icons.nights_stay_rounded, 'color': Colors.indigo},
    {'label': 'Traffic Jam', 'icon': Icons.traffic_rounded, 'color': Colors.amber},
    {'label': 'High Risk', 'icon': Icons.warning_amber_rounded, 'color': Colors.deepOrange},
    {'label': 'Easy Drop', 'icon': Icons.check_circle_rounded, 'color': Colors.green},
  ];
  // Update this to your FastAPI Server IP
  // Update your API URL to the new Cloud Run address

  final String _baseApiUrl = "https://my-container-service-385992390190.us-central1.run.app/get_risk";

  static const CameraPosition _kInitialPosition = CameraPosition(
    target: LatLng(6.4675, 100.5055),
    zoom: 15.0,
  );

  // 1. Add this variable to your _MainPageState variables
  Map<String, bool> _driverPreferences = {};
  Map<String, double> _driverWeights = {};
  bool _isLoadingPreferences = true;

// 2. Add this function to fetch preferences from Supabase
  // Inside _MainPageState


  Future<void> _loadDriverPreferences() async {
    try {
      final data = await _supabase
          .from('driver_risk_preferences')
          .select()
          .eq('user_id', widget.user.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          // High-precision split for 6 indicators
          const double balancedWeight = 100.0 / 6.0; // Results in 16.666666666666668

          _driverWeights = {
            'abnormal_request': (data?['weight_request'] ?? balancedWeight).toDouble(),
            'crime_index': (data?['weight_crime'] ?? balancedWeight).toDouble(),
            'road_accident': (data?['weight_accident'] ?? balancedWeight).toDouble(),
            'road_condition': (data?['weight_condition'] ?? balancedWeight).toDouble(),
            'weather': (data?['weight_weather'] ?? balancedWeight).toDouble(),
            'lighting': (data?['weight_lighting'] ?? balancedWeight).toDouble(),
          };
          _isLoadingPreferences = false;
        });
      }
    } catch (e) {
      debugPrint("⛔ Preference Load Error: $e");
    }
  }

  double _calculateRiskAdjustedPrice(double originalPrice, double destinationScore) {
    // We only apply surge if the destination risk is above 20%
    if (destinationScore <= 30) return originalPrice;

    // Calculate blocks of 10% above the 20% threshold
    double riskExcess = destinationScore - 30;
    double incrementBlocks = riskExcess;

    // Example: +5% original price per 10% risk block
    double premiumRate = 0.05;
    double multiplier = 1 + (incrementBlocks * premiumRate);

    return originalPrice * multiplier;
  }

  Future<Map<String, String>?> _getTravelStats(LatLng origin, LatLng dest) async {
    try {
      final String apiKey = "AIzaSyAzflTPOWSb2yJ7LuN8sMvtXIwXOpWu1o8";
      final url = "https://maps.googleapis.com/maps/api/distancematrix/json"
          "?origins=${origin.latitude},${origin.longitude}"
          "&destinations=${dest.latitude},${dest.longitude}"
          "&key=$apiKey";

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['rows'][0]['elements'][0]['status'] == "OK") {
          final element = data['rows'][0]['elements'][0];
          return {
            "dist": element['distance']['text'],
            "time": element['duration']['text'],
          };
        }
      }
    } catch (e) {
      debugPrint("Distance Matrix Error: $e");
    }
    return null;
  }

  // 1. IMPROVED: Location Report Fetch with 2-Hour window for testing
  Future<Map<String, dynamic>?> _getPreviousLocationReports(double lat, double lng) async {
    try {
      final now = DateTime.now().toUtc();
      // Expanded lookback for testing - reports from the last 24 hours
      final windowStart = now.subtract(const Duration(hours: 24)).toIso8601String();

      debugPrint("📡 DB SEARCH: Lat: $lat, Lng: $lng");

      final response = await _supabase
          .from('location_reports')
          .select()
          .gte('latitude', lat - 0.005) // ~500m buffer
          .lte('latitude', lat + 0.005)
          .gte('longitude', lng - 0.005)
          .lte('longitude', lng + 0.005)
          .gte('reported_at', windowStart)
          .order('reported_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null) {
        debugPrint("🚩 DB MATCH: Found ${response['flag_label']} (ID: ${response['id']})");
      } else {
        debugPrint("⚪ DB NULL: No recent flags found at this coordinate.");
      }

      return response;
    } catch (e) {
      debugPrint("❌ DB ERROR: $e");
      return null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // You can keep this part just to verify the user session is active
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic> && args.containsKey('user')) {
      debugPrint("👤 Session active for: ${(args['user'] as model.User).id}");
    }
    // REMOVED: triggerLocationReport block (it's now its own page!)
  }



  // Update this function in your _MainPageState
  void _updateRideMarkers(double pLat, double pLon, double dLat, double dLon, {Map<String, dynamic>? details}) {
    setState(() {
      Set<Marker> newMarkers = {
        // 1. STANDARD PICKUP MARKER (Azure)
        Marker(
          markerId: const MarkerId('pickup_point'),
          position: LatLng(pLat, pLon),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
        // 2. STANDARD DESTINATION FLAG (Green)
        Marker(
          markerId: const MarkerId('destination_point'),
          position: LatLng(dLat, dLon),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      };

      // 3. WAZE-STYLE HAZARD FLAGS (Only if details exist)
      if (details != null) {
        if ((details['road_accident'] ?? 0) > 50) {
          newMarkers.add(Marker(
            markerId: const MarkerId('hazard_accident'),
            position: LatLng(pLat + 0.0005, pLon + 0.0005), // Slight offset
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
            infoWindow: const InfoWindow(title: "Accident Warning"),
          ));
        }
        if ((details['crime_index'] ?? 0) > 50) {
          newMarkers.add(Marker(
            markerId: const MarkerId('hazard_crime'),
            position: LatLng(dLat - 0.0005, dLon - 0.0005),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: const InfoWindow(title: "Safety Alert"),
          ));
        }
      }

      _rideMarkers = newMarkers;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadDriverPreferences();
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
    _activeRideStatusStream?.cancel();
    super.dispose();
  }


  // Add a variable to your State class in main_page.dart
  String? _lastCompletedRideId;

// Update the function signature
  Future<void> _checkActiveRide({String? ignoreId}) async {
    try {
      final response = await _supabase
          .from('ride_assignments')
          .select('*, bookings!inner(*)')
          .eq('driver_id', widget.user.id)
          .filter('bookings.status', 'in', '("accepting","on_way","picked_up","paid")')
          .order('accepted_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null || response['bookings'] == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final rideData = Map<String, dynamic>.from(response['bookings'] as Map);
      final String currentRideId = rideData['id'].toString();

      // NEW CHECK: If this is the ride we JUST finished, don't redirect!
      if (currentRideId == ignoreId || currentRideId == _lastCompletedRideId) {
        debugPrint("Skipping redirect for recently completed ride: $currentRideId");
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      if (mounted) {
        Navigator.pushReplacementNamed(
          context,
          '/active_ride',
          arguments: {'rideData': rideData, 'driverUser': widget.user},
        );
      }
    } catch (e) {
      debugPrint("⛔ Error: $e");
    }
  }

  // 2. Add this method to load them (Call this in initState)
  Future<void> _loadCustomMarkerIcons() async {
    final ImageConfiguration config = createLocalImageConfiguration(context, size: const Size(48, 48));

    // Map your labels to your asset paths
    Map<String, String> assetPaths = {
      'crowded': 'assets/images/crowded_icon.png',
      'no parking': 'assets/images/parking_icon.png',
      'accident': 'assets/images/accident_icon.png',
      'high risk': 'assets/images/warning_icon.png',
    };

    for (var entry in assetPaths.entries) {
      _customIcons[entry.key] = await BitmapDescriptor.fromAssetImage(config, entry.value);
    }
  }
  // --- UPDATED API CALL (Supports Dynamic Weighting) ---
  // --- UPDATED API CALL ---
  Future<Map<String, dynamic>?> _getRiskScore(double lat, double lon, String? passengerId) async {
    try {
      debugPrint("📡 REQUESTING RISK → User: ${widget.user.id}, Passenger: $passengerId");

      final response = await http.post(
        Uri.parse(_baseApiUrl),
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: jsonEncode({
          "lat": lat,
          "lon": lon,
          "user_id": widget.user.id,
          "passenger_id": passengerId ?? "",
        }),
      ).timeout(const Duration(seconds: 150));

      debugPrint("📡 API Status: ${response.statusCode}");

      if (response.statusCode == 200) {
        final Map<String, dynamic> rawData = jsonDecode(response.body);

        // Create a default map to merge with whatever the API sends
        // Inside _getRiskScore()
        final Map<String, double> defaultDetails = {
          "abnormal_request": 0.0,
          "crime_index": 0.0, // CHANGED from reported_crime
          "road_accident": 0.0,
          "road_condition": 0.0,
          "weather": 0.0,
          "lighting": 0.0,
        };

        final Map<String, dynamic> incomingDetails = Map<String, dynamic>.from(rawData['details'] ?? {});

        final Map<String, dynamic> processedData = {
          "risk_score": (rawData['risk_score'] ?? 0.0).toDouble(),
          "details": defaultDetails.map((key, defaultValue) {
            // Ensure we keep the full double from the API
            return MapEntry(key, (incomingDetails[key] ?? defaultValue).toDouble());
          }),
        };

        debugPrint("✅ Processed with Defaults: $processedData");
        return processedData;
      } else {
        debugPrint("⚠️ API Error Body: ${response.body}");
      }
    } catch (e) {
      debugPrint("🚨 RISK API FAILED: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Analysis Error: $e"),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    return null;
  }

  Future<List<LatLng>> _getRoutePolyline(double sLat, double sLon, double eLat, double eLon) async {
    List<LatLng> polylineCoordinates = [];
    PolylinePoints polylinePoints = PolylinePoints();

    PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
      googleApiKey: "AIzaSyAzflTPOWSb2yJ7LuN8sMvtXIwXOpWu1o8",
      request: PolylineRequest(
        origin: PointLatLng(sLat, sLon),
        destination: PointLatLng(eLat, eLon),
        mode: TravelMode.driving,
      ),
    );

    if (result.points.isNotEmpty) {
      for (var point in result.points) {
        polylineCoordinates.add(LatLng(point.latitude, point.longitude));
      }
    }
    return polylineCoordinates;
  }

  // You will need this import at the top of your file:
// import 'package:flutter_polyline_points/flutter_polyline_points.dart';

  Future<List<LatLng>> _getRoadPath(double sLat, double sLon, double eLat, double eLon) async {
    PolylinePoints polylinePoints = PolylinePoints();
    List<LatLng> roadCoordinates = [];

    try {
      PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
        googleApiKey: "AIzaSyAzflTPOWSb2yJ7LuN8sMvtXIwXOpWu1o8", // Using your key
        request: PolylineRequest(
          origin: PointLatLng(sLat, sLon),
          destination: PointLatLng(eLat, eLon),
          mode: TravelMode.driving,
        ),
      );

      if (result.points.isNotEmpty) {
        for (var point in result.points) {
          roadCoordinates.add(LatLng(point.latitude, point.longitude));
        }
      }
    } catch (e) {
      debugPrint("Road Path Error: $e");
    }

    // Return a straight line as a fallback if API fails
    return roadCoordinates.isEmpty ? [LatLng(sLat, sLon), LatLng(eLat, eLon)] : roadCoordinates;
  }

  Future<void> _fetchNearbyRides(Position position) async {
    if (!_isTracking || !mounted) return;

    try {
      // 1. Setup the Time Window (30 minutes ago)
      final DateTime now = DateTime.now().toUtc();
      final String windowStart = now.subtract(const Duration(minutes: 30)).toIso8601String();

      // 2. Spatial Bounding Box (Approx 0.5 degrees = ~55km radius)
      // This pre-filters data on the server so your app doesn't lag
      const double latOffset = 1.5;
      const double lngOffset = 1.5;

      debugPrint("📡 Syncing Map: Scanning 50km radius from ${position.latitude}, ${position.longitude}");

      // 3. Parallel Fetch with Server-Side Filtering
      final results = await Future.wait([
        _supabase
            .from('bookings')
            .select()
            .eq('status', 'pending')
            .gte('pickup_latitude', position.latitude - latOffset)
            .lte('pickup_latitude', position.latitude + latOffset)
            .gte('pickup_longitude', position.longitude - lngOffset)
            .lte('pickup_longitude', position.longitude + lngOffset),
        _supabase
            .from('location_reports')
            .select()
            .gte('reported_at', windowStart)
            .gte('latitude', position.latitude - latOffset)
            .lte('latitude', position.latitude + latOffset),
      ]);

      final List<dynamic> rideData = results[0];
      final List<dynamic> reportData = results[1];

      Set<Marker> newMarkers = {};

      // 4. Process Pending Rides (Azure Pins) - 50km Limit
      for (var ride in rideData) {
        double pLat = double.parse(ride['pickup_latitude'].toString());
        double pLng = double.parse(ride['pickup_longitude'].toString());

        // Precise distance check using Haversine formula
        double dist = Geolocator.distanceBetween(
          position.latitude, position.longitude, pLat, pLng,
        );

        // 50000 meters = 50km (Covers Changlun to Arau/Kangar/Alor Setar)
        if (dist <= 10000000) {
          newMarkers.add(
            Marker(
              markerId: MarkerId("ride_${ride['id']}"),
              position: LatLng(pLat, pLng),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
              infoWindow: InfoWindow(
                title: "RM${ride['total_price']}",
                snippet: "${(dist / 1000).toStringAsFixed(1)}km away • Tap to view risk",
                onTap: () => _showRideRequestSheet(ride),
              ),
            ),
          );
        }
      }

      // 5. Process Recent Community Flags (Orange/Custom Pins)
      for (var report in reportData) {
        double rLat = double.parse(report['latitude'].toString());
        double rLng = double.parse(report['longitude'].toString());

        double distToReport = Geolocator.distanceBetween(
          position.latitude, position.longitude, rLat, rLng,
        );

        // Only show safety flags within the same 50km radius
        if (distToReport <= 50000) {
          String dbLabel = report['flag_label'].toString().toLowerCase();
          BitmapDescriptor markerIcon = _customIcons[dbLabel] ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);

          newMarkers.add(
            Marker(
              markerId: MarkerId("report_${report['id']}"),
              position: LatLng(rLat, rLng),
              icon: markerIcon,
              infoWindow: InfoWindow(
                title: report['flag_label'],
                snippet: "Reported near your service area",
              ),
            ),
          );
        }
      }

      // 6. Final State Update
      if (mounted) {
        setState(() {
          _rideMarkers = newMarkers;
        });
        debugPrint("✅ Sync Complete: ${newMarkers.length} markers active within 50km.");
      }
    } catch (e) {
      debugPrint("🚨 Sync Error: $e");
    }
  }


  void _showRideRequestSheet(Map<String, dynamic> ride) async {
    // 1. Extract Coordinates
    double pLat = double.parse(ride['pickup_latitude'].toString());
    double pLon = double.parse(ride['pickup_longitude'].toString());
    double dLat = double.parse(ride['destination_latitude'].toString());
    double dLon = double.parse(ride['destination_longitude'].toString());

    final String? pId = ride['passenger_id']?.toString();

    // Update map markers and zoom
    _updateRideMarkers(pLat, pLon, dLat, dLon);
    _zoomToFitRide(LatLng(pLat, pLon), LatLng(dLat, dLon));

    // Show Loading UI
    _showAnalysisUI(ride, null, null, null);
    _performAnalysis(ride, pLat, pLon, dLat, dLon, pId);
    try {
      // 2. Fetch Risk Scores from API
      final pickupData = await _getRiskScore(pLat, pLon, pId);
      final destData = await _getRiskScore(dLat, dLon, pId);

      // 3. Fetch the real community flag from Supabase
      // This will be null if no report exists within the 500m buffer
      var communityReport = await _getPreviousLocationReports(dLat, dLon);

      if (!mounted) return;

      // Close the loading bottom sheet before showing the result
      Navigator.pop(context);

      // 4. Pass the real data (communityReport might be null)
      _showAnalysisUI(ride, pickupData, destData, communityReport);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint("Analysis Error: $e");
    }
  }

  // 2. Extracted logic to allow "Tap to Retry"
  Future<void> _performAnalysis(Map<String, dynamic> ride, double pLat, double pLon, double dLat, double dLon, String? pId) async {
    try {
      // 3. Make the analysis feel "Longer" (e.g., 2.5 seconds minimum)
      // This gives the AI appearance of deep calculation
      final stopwatch = Stopwatch()..start();

      final results = await Future.wait([
        _getRiskScore(pLat, pLon, pId),
        _getRiskScore(dLat, dLon, pId),
        _getPreviousLocationReports(dLat, dLon),
      ]);

      // Ensure at least 2.5 seconds have passed
      final int elapsed = stopwatch.elapsedMilliseconds;
      if (elapsed < 2500) {
        await Future.delayed(Duration(milliseconds: 2500 - elapsed));
      }

      if (!mounted) return;

      // Close the loading sheet
      Navigator.pop(context);

      // Show the actual results
      _showAnalysisUI(ride, results[0] as Map<String, dynamic>?, results[1] as Map<String, dynamic>?, results[2] as Map<String, dynamic>?);

    } catch (e) {
      debugPrint("Analysis Failed: $e");
      if (mounted) {
        Navigator.pop(context); // Close loading sheet
        // Show error state with a "Tap to Retry" button
        _showErrorSheet(ride, pLat, pLon, dLat, dLon, pId);
      }
    }
  }

  void _showErrorSheet(Map<String, dynamic> ride, double pLat, double pLon, double dLat, double dLon, String? pId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 50, color: Colors.redAccent),
            const SizedBox(height: 15),
            const Text("Analysis Timeout", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 8),
            const Text("We couldn't reach the Safety AI. Please check your connection.", textAlign: TextAlign.center),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D47A1),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _showRideRequestSheet(ride); // Restart the process
                },
                child: const Text("TAP TO RETRY ANALYSIS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }

  void _zoomToFitRide(LatLng pickup, LatLng destination) async {
    final GoogleMapController controller = await _controller.future;

    // Calculate the bounds that contain both points
    LatLngBounds bounds;
    if (pickup.latitude > destination.latitude && pickup.longitude > destination.longitude) {
      bounds = LatLngBounds(southwest: destination, northeast: pickup);
    } else if (pickup.longitude > destination.longitude) {
      bounds = LatLngBounds(southwest: LatLng(pickup.latitude, destination.longitude), northeast: LatLng(destination.latitude, pickup.longitude));
    } else if (pickup.latitude > destination.latitude) {
      bounds = LatLngBounds(southwest: LatLng(destination.latitude, pickup.longitude), northeast: LatLng(pickup.latitude, destination.longitude));
    } else {
      bounds = LatLngBounds(southwest: pickup, northeast: destination);
    }

    controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100)); // 100 is padding
  }


  Future<BitmapDescriptor> _getBitmapFromIcon(IconData iconData, Color color) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    const double size = 130.0; // Slightly larger for crispness

    // 1. Shadow for the icon
    final Paint shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(const Offset(size/2, size/2 + 3), size/2 - 5, shadowPaint);

    // 2. White Badge Circle
    canvas.drawCircle(const Offset(size/2, size/2), size/2 - 5, Paint()..color = Colors.white);

    // 3. Colored Ring
    canvas.drawCircle(const Offset(size/2, size/2), size/2 - 5, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7);

    // 4. Icon
    TextPainter textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(iconData.codePoint),
      style: TextStyle(fontSize: 75.0, fontFamily: iconData.fontFamily, color: color),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2));

    final image = await pictureRecorder.endRecording().toImage(size.toInt(), size.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  void _showAnalysisUI(
      Map<String, dynamic> ride,
      Map<String, dynamic>? pickupRisk,
      Map<String, dynamic>? destRisk,
      Map<String, dynamic>? communityReport,
      ) {
    // Local state variables for the bottom sheet
    bool isPickupSelected = true;
    bool isMapExpanded = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          if (pickupRisk == null || destRisk == null) return _buildLoadingState();

          // 1. Coordinate Extraction
          final double pLat = double.parse(ride['pickup_latitude'].toString());
          final double pLon = double.parse(ride['pickup_longitude'].toString());
          final double dLat = double.parse(ride['destination_latitude'].toString());
          final double dLon = double.parse(ride['destination_longitude'].toString());

          // Driver current position for "To Pickup" routing
          final double drLat = _routePoints.isNotEmpty ? _routePoints.last.latitude : pLat;
          final double drLon = _routePoints.isNotEmpty ? _routePoints.last.longitude : pLon;

          // 2. Pricing Logic
          final double originalPrice = double.parse(ride['total_price'].toString());
          final double destinationScore = (destRisk['risk_score'] ?? 0.0).toDouble();
          final double adjustedPrice = _calculateRiskAdjustedPrice(originalPrice, destinationScore);
          final bool isSurged = adjustedPrice > originalPrice;

          // 3. Risk Context
          final activeData = isPickupSelected ? pickupRisk : destRisk;
          final double currentScore = (activeData['risk_score'] ?? 0.0).toDouble();
          final Map<String, dynamic> details = Map<String, dynamic>.from(activeData['details'] ?? {});
          final visual = getRiskVisual(currentScore);
          final Color themeColor = Color(int.parse(visual['color']!.replaceAll('#', '0xFF')));

          return Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Grab handle
                  Center(
                      child: Container(
                          width: 45, height: 4,
                          decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(10))
                      )
                  ),
                  const SizedBox(height: 20),

                  // ADDRESS HEADER SECTION
                  // 🚀 UPDATED: DYNAMIC ADDRESS HEADER SECTION
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      children: [
                        _buildLocationRow(
                          isPickupSelected ? Icons.my_location : Icons.circle, // Dynamic Icon
                          Colors.blue,
                          isPickupSelected ? "Your Current Position" : "Pickup Point", // Dynamic Label
                          isPickupSelected
                              ? "Route from your current location" // Informative text for driver
                              : (ride['pickup_address'] ?? "Fetching address..."),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 7),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(width: 1, height: 15, color: Colors.grey[300]),
                          ),
                        ),
                        _buildLocationRow(
                          Icons.location_on,
                          Colors.red,
                          isPickupSelected ? "Pickup Point" : "Destination", // Dynamic Label
                          isPickupSelected
                              ? (ride['pickup_address'] ?? "Fetching address...")
                              : (ride['destination_address'] ?? "Fetching destination..."),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- MAP SECTION WITH DYNAMIC ROUTING ---
                  Stack(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        height: isMapExpanded ? 400 : 220,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20)],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: _buildPrettyMiniMap(
                            // START: Driver Location if Pickup, else Passenger Pickup
                            isPickupSelected ? drLat : pLat,
                            isPickupSelected ? drLon : pLon,
                            // END: Passenger Pickup if Pickup, else Passenger Destination
                            isPickupSelected ? pLat : dLat,
                            isPickupSelected ? pLon : dLon,
                            isPickupSelected,
                            communityReport,
                            pLat, pLon, dLat, dLon,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: GestureDetector(
                          onTap: () => setModalState(() => isMapExpanded = !isMapExpanded),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isMapExpanded ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                              color: const Color(0xFF0D47A1),
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // --- TRIP STATISTICS SECTION ---
                  FutureBuilder<Map<String, String>?>(
                    future: isPickupSelected
                        ? _getTravelTime(startLat: drLat, startLon: drLon, endLat: pLat, endLon: pLon)
                        : _getTravelTime(startLat: pLat, startLon: pLon, endLat: dLat, endLon: dLon),
                    builder: (context, snapshot) {
                      final String distance = snapshot.data?['distance'] ?? "Calculating...";
                      final String duration = snapshot.data?['duration'] ?? "...";

                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey[900],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatColumn(
                                isPickupSelected ? Icons.directions_car_rounded : Icons.map_rounded,
                                isPickupSelected ? "To Pickup" : "Trip Dist.",
                                distance
                            ),
                            Container(width: 1, height: 30, color: Colors.white24),
                            _buildStatColumn(
                                Icons.timer_rounded,
                                "Est. Time",
                                duration
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  _buildToggleTabs(
                      isPickupSelected,
                          (val) => setModalState(() => isPickupSelected = val)
                  ),

                  if (!isPickupSelected && communityReport != null)
                    _buildCommunityAlert(communityReport),

                  const SizedBox(height: 25),

                  _buildParallelRiskAnalysis(details, themeColor, currentScore, visual['status']!),

                  const SizedBox(height: 30),

                  // DYNAMIC SECTION HEADERS
                  // --- Update these lines in your build method ---

                  if (_driverPreferences['abnormal_request'] ?? true) ...[
                    _buildSectionHeader("PASSENGER PROFILE"),
                    // ADDED 'abnormal_request' as the 3rd argument
                    _buildRiskIndicator("Behavioral Risk", details['abnormal_request'], 'abnormal_request'),
                    const SizedBox(height: 10),
                  ],

                  _buildSectionHeader("ENVIRONMENTAL RISKS"),

                  if (_driverPreferences['crime_index'] ?? true)
                    _buildRiskIndicator("Crime Rate", details['crime_index'], 'crime_index'), // ADDED key

                  if (_driverPreferences['road_accident'] ?? true)
                    _buildRiskIndicator("Accident History", details['road_accident'], 'road_accident'), // ADDED key

                  if (_driverPreferences['road_condition'] ?? true)
                    _buildRiskIndicator("Road Infrastructure", details['road_condition'], 'road_condition'), // ADDED key

                  if (_driverPreferences['weather'] ?? true)
                    _buildRiskIndicator("Weather Conditions", details['weather'], 'weather'), // ADDED key

                  if (_driverPreferences['lighting'] ?? true)
                    _buildRiskIndicator("Lighting", details['lighting'], 'lighting'), // ADDED key

                  const Divider(height: 40, thickness: 1),

                  // PRICING FOOTER
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(isSurged ? "Safety Adjusted Fare" : "Estimated Fare",
                              style: TextStyle(color: isSurged ? Colors.deepOrange : Colors.blueGrey, fontWeight: FontWeight.bold)),
                          if (isSurged)
                            const Text("Includes Destination Risk Premium", style: TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (isSurged)
                            Text("RM ${originalPrice.toStringAsFixed(2)}",
                                style: const TextStyle(fontSize: 14, color: Colors.grey, decoration: TextDecoration.lineThrough)),
                          Text("RM ${adjustedPrice.toStringAsFixed(2)}",
                              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: isSurged ? Colors.deepOrange : Colors.green[700])),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  _buildActionButtons(ride, adjustedPrice),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      // RESET LOGIC: When exiting the sheet, restore all available job markers and re-center map
      _getCurrentLocation().then((position) {
        if (mounted) {
          _fetchNearbyRides(position);
          _controller.future.then((c) => c.animateCamera(
            CameraUpdate.newLatLngZoom(LatLng(position.latitude, position.longitude), 15),
          ));
        }
      });
    });
  }

// --- UPDATED STAT COLUMN HELPER (Fixes FontWeight.black error) ---
  Widget _buildStatColumn(IconData icon, String label, String value) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.blue[400], size: 14),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _buildToggleTabs(bool isPickupSelected, Function(bool) onToggle) {
    return Container(
      height: 54,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          _buildPrettyTab("PICKUP", isPickupSelected, () => onToggle(true)),
          _buildPrettyTab("DESTINATION", !isPickupSelected, () => onToggle(false)),
        ],
      ),
    );
  }
  // Modern Toggle Tab
  Widget _buildPrettyTab(String label, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)] : [],
          ),
          child: Text(label, style: TextStyle(color: isSelected ? const Color(0xFF0D47A1) : Colors.black45, fontWeight: FontWeight.w800, fontSize: 12)),
        ),
      ),
    );
  }

  Widget _buildPrettyMiniMap(
      double startLat, double startLon, double endLat, double endLon,
      bool isPickupSelected, Map<String, dynamic>? communityReport,
      double pLat, double pLon, double dLat, double dLon) {
    return Container(
      // REMOVED fixed height to allow AnimatedContainer in _showAnalysisUI to control it
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        // BoxShadow moved to the parent Stack in _showAnalysisUI to prevent clipping
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: FutureBuilder<List<LatLng>>(
          future: _getRoadPath(startLat, startLon, endLat, endLon),
          builder: (context, pathSnapshot) {
            final List<LatLng> polyPoints = pathSnapshot.data ?? [LatLng(startLat, startLon), LatLng(endLat, endLon)];

            return FutureBuilder<BitmapDescriptor>(
              future: (!isPickupSelected && communityReport != null)
                  ? _getBitmapFromIcon(
                  flags.firstWhere(
                          (f) => f['label'].toLowerCase() == communityReport['flag_label'].toString().toLowerCase(),
                      orElse: () => flags[4]
                  )['icon'],
                  flags.firstWhere(
                          (f) => f['label'].toLowerCase() == communityReport['flag_label'].toString().toLowerCase(),
                      orElse: () => flags[4]
                  )['color']
              )
                  : Future.value(BitmapDescriptor.defaultMarkerWithHue(
                  isPickupSelected ? BitmapDescriptor.hueAzure : BitmapDescriptor.hueGreen
              )),
              builder: (context, iconSnapshot) {
                return GoogleMap(
                  key: UniqueKey(),
                  // Zoom 15.0 for Pickup (Driver needs to see exact house)
                  // Zoom 14.0 for Destination (Driver needs to see area context)
                  initialCameraPosition: CameraPosition(
                      target: LatLng(endLat, endLon),
                      zoom: isPickupSelected ? 15.0 : 14.0
                  ),
                  markers: {
                    Marker(
                      markerId: const MarkerId('start'),
                      position: LatLng(startLat, startLon),
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                          isPickupSelected ? BitmapDescriptor.hueBlue : BitmapDescriptor.hueAzure),
                    ),
                    Marker(
                      markerId: const MarkerId('end'),
                      position: LatLng(endLat, endLon),
                      icon: iconSnapshot.data ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                    ),
                  },
                  polylines: {
                    Polyline(
                      polylineId: const PolylineId("path"),
                      points: polyPoints,
                      color: const Color(0xFF2563EB),
                      width: 6,
                    ),
                  },
                  onMapCreated: (controller) {
                    controller.setMapStyle(_prettyMapStyle);
                  },
                  // Disable internal gestures if you want the "Maximize" button
                  // to be the primary way to interact with the map
                  scrollGesturesEnabled: true,
                  zoomGesturesEnabled: true,
                  myLocationButtonEnabled: false,
                );
              },
            );
          },
        ),
      ),
    );
  }

// Separate Helper Widget with Case-Insensitive Matching
  Widget _buildCommunityAlert(Map<String, dynamic> report) {
    // Case-insensitive lookup in the flags list
    // Inside _buildCommunityAlert
    final Map<String, dynamic> flagMatch = flags.firstWhere(
          (f) => f['label'].toString().toLowerCase() == report['flag_label'].toString().toLowerCase(),
      orElse: () => {
        'label': report['flag_label'],
        'icon': Icons.campaign_rounded,
        'color': Colors.amber
      },
    );

    final Color themeColor = flagMatch['color'] as Color;

    return Container(
      margin: const EdgeInsets.only(top: 15),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: themeColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: themeColor.withOpacity(0.3), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: themeColor.withOpacity(0.15), shape: BoxShape.circle),
            child: Icon(flagMatch['icon'] as IconData, color: themeColor, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "COMMUNITY ALERT",
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: themeColor, letterSpacing: 1.2),
                ),
                const SizedBox(height: 4),
                Text(
                  "Flagged as: ${report['flag_label']}",
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 2),
                Text(
                  "Time: ${report['time_of_day']} • ${report['location_address']}",
                  style: TextStyle(fontSize: 11, color: Colors.blueGrey[400]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


// Helper for cleaner address rows
  Widget _buildAddressRow(IconData icon, String label, String address) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(color: Colors.black87, fontSize: 13),
              children: [
                TextSpan(text: "$label: ", style: const TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: address),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 2. Create the listener function
  void _listenToActiveRideStatus(String bookingId) {
    _activeRideStatusStream?.cancel();

    _activeRideStatusStream = _supabase
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('id', bookingId)
        .listen((List<Map<String, dynamic>> data) {
      if (data.isNotEmpty && mounted) {
        final updatedRide = data.first;
        final String status = updatedRide['status'].toString().toLowerCase();

        // IMPORTANT: Only clear the ride if it is 'completed' or 'cancelled'
        if (status == 'completed' || status == 'cancelled') {
          setState(() => currentRideData = null);
        } else {
          setState(() {
            currentRideData = updatedRide;
          });
        }
      }
    });
  }

  Widget _buildLoadingState() {
    return Container(
      height: 400,
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 60, height: 60,
            child: CircularProgressIndicator(
              color: Color(0xFF0D47A1),
              strokeWidth: 6,
            ),
          ),
          const SizedBox(height: 30),
          const Text(
              "SMARTGIG AI ANALYZING...",
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Color(0xFF0D47A1))
          ),
          const SizedBox(height: 15),
          Text(
              "Cross-referencing crime data, weather patterns, and passenger behavioral history for your safety.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 13, height: 1.5)
          ),
          const SizedBox(height: 30),
          // Simple text button if they want to cancel and try again manually
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("CANCEL", style: TextStyle(color: Colors.grey[400], fontSize: 12, fontWeight: FontWeight.bold))
          )
        ],
      ),
    );
  }

  // Inside _formatKey()
  String _formatKey(String key) {
    switch(key) {
      case 'abnormal_request': return 'Abnormal Passenger Behavioral';
      case 'crime_index': return 'Reported Crime Rate'; // CHANGED from reported_crime
      case 'road_accident': return 'Road Accident History';
      case 'road_condition': return 'Road Infrastructure';
      case 'weather': return 'Weather Conditions';
      case 'lighting': return 'Lighting';
      default: return key.toUpperCase().replaceAll('_', ' ');
    }
  }

  Map<String, String> getRiskVisual(double score) {
    if (score <= 20) {
      return {"status": "VERY SAFE", "color": "#008000"}; // Green
    } else if (score <= 40) {
      return {"status": "MODERATE SAFE", "color": "#FFFF00"}; // Yellow
    } else if (score <= 60) {
      return {"status": "MODERATE RISKY", "color": "#FFA500"}; // Orange
    } else if (score <= 80) {
      return {"status": "HIGH RISK", "color": "#FF0000"}; // Red
    } else {
      // This covers 81-100 AND anything above 100
      return {"status": "VERY HIGH RISK", "color": "#8B0000"}; // Dark Red
    }
  }

  Future<Map<String, String>?> _getTravelTime({
    required double startLat,
    required double startLon,
    required double endLat,
    required double endLon
  }) async {
    try {
      final String apiKey = "AIzaSyAzflTPOWSb2yJ7LuN8sMvtXIwXOpWu1o8";
      final String url =
          "https://maps.googleapis.com/maps/api/distancematrix/json"
          "?origins=$startLat,$startLon"
          "&destinations=$endLat,$endLon"
          "&mode=driving"
          "&key=$apiKey";

      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == "OK" && data['rows'][0]['elements'][0]['status'] == "OK") {
          final element = data['rows'][0]['elements'][0];
          return {
            "duration": element['duration']['text'] ?? "N/A",
            "distance": element['distance']['text'] ?? "N/A",
          };
        }
      }
    } catch (e) {
      debugPrint("Travel Calculation Error: $e");
    }
    return null;
  }



  // --- ACTIONS ---
  Future<void> _acceptRide(Map<String, dynamic> ride, double finalPrice) async {
    try {
      // Update booking with status AND the new high-risk price
      await _supabase.from('bookings').update({
        'status': 'accepting',
        'total_price': finalPrice, // Save the dynamic price
      }).eq('id', ride['id']);

      await _supabase.from('ride_assignments').insert({
        'booking_id': ride['id'],
        'driver_id': widget.user.id
      });

      if (!mounted) return;
      setState(() => currentRideData = Map.from(ride)..['total_price'] = finalPrice);

      Navigator.pop(context);
      Navigator.pushNamed(context, '/active_ride', arguments: {'rideData': currentRideData, 'driverUser': widget.user});
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

  Widget buildIndicatorProgressBar(double currentScore, double weight) {
    // Calculate the percentage relative to the weight (e.g., 7.2 / 17.0)
    double progressFraction = (currentScore / weight).clamp(0.0, 1.0);
    double displayPercentage = progressFraction * 100;

    // Get the color based on the normalized 0-100 scale
    Color barColor = _getBarColor(displayPercentage);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Indicator Impact: ${displayPercentage.toStringAsFixed(1)}%"),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progressFraction,
          backgroundColor: Colors.grey[300],
          color: barColor,
          minHeight: 10,
        ),
      ],
    );
  }

  Color _getBarColor(double score) {
    if (score <= 15) return const Color(0xFF7CFC00); // Light Green
    if (score <= 30) return const Color(0xFF008000); // Green
    if (score <= 45) return const Color(0xFFFFFF00); // Yellow
    if (score <= 60) return const Color(0xFFFFA500); // Orange
    if (score <= 80) return const Color(0xFFFF0000); // Red
    return const Color(0xFF8B0000); // Dark Red
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
              Navigator.pushNamed(
                context,
                '/active_ride',
                arguments: {
                  'rideData': currentRideData, // This key must match the router
                  'driverUser': widget.user,    // This key must match the router
                },
              );
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

  Widget _buildLocationRow(IconData icon, Color color, String type, String address) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start, // Aligns icon with the first line of text
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                type.toUpperCase(),
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: Colors.grey[500],
                    letterSpacing: 1.2
                ),
              ),
              const SizedBox(height: 1),
              Text(
                address,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B), // Midnight Slate color
                    height: 1.2
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildParallelRiskAnalysis(Map<String, dynamic> details, Color themeColor, double score, String status) {
    // Maintaining your previous color logic
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
                    style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        color: mainColor.withOpacity(0.7))),
                const SizedBox(height: 15),
                AspectRatio(
                  aspectRatio: 1.1,
                  child: RadarChart(
                    RadarChartData(
                      dataSets: [
                        RadarDataSet(
                          fillColor: mainColor.withOpacity(0.25),
                          borderColor: mainColor,
                          borderWidth: 3.0,
                          entryRadius: 4.0,
                          dataEntries: [
                            RadarEntry(value: (details['abnormal_request'] ?? 0).toDouble()),
                            RadarEntry(value: (details['crime_index'] ?? 0).toDouble()),
                            RadarEntry(value: (details['road_accident'] ?? 0).toDouble()),
                            RadarEntry(value: (details['road_condition'] ?? 0).toDouble()),
                            RadarEntry(value: (details['weather'] ?? 0).toDouble()),
                            RadarEntry(value: (details['lighting'] ?? 0).toDouble()),
                          ],
                        ),
                      ],
                      // MATCHING THE REFERENCE IMAGE DESIGN:
                      radarShape: RadarShape.circle, // Circular grid like the image
                      radarBackgroundColor: Colors.transparent,

                      // The outer border line
                      radarBorderData: BorderSide(color: Colors.white.withOpacity(0.2), width: 1),

                      // The circular grid lines
                      gridBorderData: BorderSide(color: Colors.white.withOpacity(0.2), width: 1),

                      // The "Spoke" lines connecting the center to the labels
                      tickBorderData: BorderSide(color: Colors.white.withOpacity(0.2), width: 1),

                      tickCount: 4, // Number of concentric circles
                      ticksTextStyle: const TextStyle(color: Colors.transparent, fontSize: 0),

                      titleTextStyle: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w600
                      ),

                      titlePositionPercentageOffset: 0.15,
                      getTitle: (index, angle) {
                        const labels = [
                          'Abnormal Request', 'Crime Index', 'Road Accident',
                          'Road Infrastructure', 'Weather', 'Lighting'
                        ];
                        return RadarChartTitle(text: labels[index]);
                      },
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
                        Text(score.toStringAsFixed(2),
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: -1.0
                            )),
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

  // Update your call in the build method to pass the key:
// _buildRiskIndicator("Crime Rate", details['crime_index'], 'crime_index'),

  Widget _buildRiskIndicator(String label, dynamic value, String weightKey) {
    // 1. Get the weight for this specific key (Default should be ~16.67 for 6 items)
    final double personalizedMax = _driverWeights[weightKey] ?? 16.666;
    final double rawScore = (value ?? 0.0).toDouble();

    // 2. Calculate impact fraction (How much of the total weight is "filled")
    double progressFraction = 0.0;
    if (personalizedMax > 0) {
      progressFraction = (rawScore / personalizedMax).clamp(0.0, 1.0);
    }

    // 3. UI Calculations
    double displayPercentage = progressFraction * 100;

    // Use a fixed color scheme or your existing getRiskVisual
    final visual = getRiskVisual(displayPercentage);
    final Color riskBarColor = Color(int.parse(visual['color']!.replaceAll('#', '0xFF')));

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blueGrey[800])),
              // Update your text widget in main_page.dart
              Text(
                "${rawScore.toStringAsFixed(2)}% / ${personalizedMax.toStringAsFixed(2)}%",
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  // Background Track
                  Container(
                    height: 8,
                    width: constraints.maxWidth,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  // Progress Fill
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    height: 8,
                    width: constraints.maxWidth * progressFraction,
                    decoration: BoxDecoration(
                      color: riskBarColor,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: riskBarColor.withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(Map<String, dynamic> ride, double finalPrice) {
    return Row(children: [
      Expanded(
          child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("DECLINE", style: TextStyle(color: Colors.red))
          )
      ),
      const SizedBox(width: 15),
      Expanded(
          child: ElevatedButton(
            // PASS BOTH ARGUMENTS HERE
              onPressed: () => _acceptRide(ride, finalPrice),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D47A1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
              ),
              child: const Text("ACCEPT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
          )
      ),
    ]);
  }
}