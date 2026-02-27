import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import '../models/user.dart' as model;
import 'chat_detail_page.dart';
import 'passenger_feedback_page.dart';

class ActiveRidePage extends StatefulWidget {
  final Map<String, dynamic> rideData;
  final model.User driverUser;

  const ActiveRidePage({super.key, required this.rideData, required this.driverUser});

  @override
  State<ActiveRidePage> createState() => _ActiveRidePageState();
}

class _ActiveRidePageState extends State<ActiveRidePage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final Completer<GoogleMapController> _mapController = Completer<
      GoogleMapController>();

  // FIX: Removed the 'supabase.' prefix
  RealtimeChannel? _statusSubscription;

  // Journey State
  bool _isJourneyStarted = false;
  String _currentStatus = 'accepting';
  StreamSubscription<Position>? _positionStream;

  // Map Components
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final List<LatLng> _polylineCoordinates = [];

  final String _googleApiKey = "AIzaSyAzflTPOWSb2yJ7LuN8sMvtXIwXOpWu1o8";

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.rideData['status'] ?? 'accepting';

    _initMarkers();
    _getPolyline();
    _checkCurrentStatus();
    _subscribeToBookingChanges();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    if (_statusSubscription != null) {
      _supabase.removeChannel(_statusSubscription!);
    }
    super.dispose();
  }

  // --- REALTIME LOGIC ---
  void _subscribeToBookingChanges() {
    // FIX: Use the classes directly without 'supabase.' prefix
    _statusSubscription = _supabase
        .channel('public:bookings:id=${widget.rideData['id']}')
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'bookings',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: widget.rideData['id'],
      ),
      callback: (payload) {
        final String newStatus = payload.newRecord['status'];
        if (mounted) {
          setState(() {
            _currentStatus = newStatus;
          });
          if (newStatus == 'paid') {
            _showSuccessOverlay();
          }
        }
      },
    )
        .subscribe();
  }

  void _showSuccessOverlay() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Payment Confirmed by Passenger!"),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ),
    );
  }

  // --- NAVIGATION & STATUS ---

  void _navigateToMain() {
    Navigator.pushReplacementNamed(
        context, '/main', arguments: widget.driverUser);
  }

  Future<void> _checkCurrentStatus() async {
    try {
      final data = await _supabase
          .from('bookings')
          .select('status')
          .eq('id', widget.rideData['id'])
          .single();

      final status = data['status'] as String;
      if (mounted) {
        setState(() {
          _currentStatus = status;
          if (status == 'on_way' || status == 'picked_up' || status == 'paid') {
            _isJourneyStarted = true;
            _startLiveTracking();
          }
        });
      }
    } catch (e) {
      debugPrint("Error fetching status: $e");
    }
  }

  Future<void> _updateRideStatus(String newStatus) async {
    try {
      await _supabase.from('bookings').update({'status': newStatus}).eq(
          'id', widget.rideData['id']);
      setState(() {
        _currentStatus = newStatus;
        if (newStatus == 'on_way') {
          _isJourneyStarted = true;
          _startLiveTracking();
        }
      });

      // Changed Logic here
      if (newStatus == 'completed') {
        _showPaymentSummary();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")));
    }
  }

  // --- MAP LOGIC ---

  void _initMarkers() {
    final pickup = LatLng(
      double.parse(widget.rideData['pickup_latitude'].toString()),
      double.parse(widget.rideData['pickup_longitude'].toString()),
    );
    final destination = LatLng(
      double.parse(widget.rideData['destination_latitude'].toString()),
      double.parse(widget.rideData['destination_longitude'].toString()),
    );

    setState(() {
      _markers.addAll([
        Marker(
          markerId: const MarkerId('pickup'),
          position: pickup,
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen),
        ),
        Marker(
          markerId: const MarkerId('destination'),
          position: destination,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      ]);
    });
  }

  Future<void> _getPolyline() async {
    PolylinePoints polylinePoints = PolylinePoints();
    PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
      request: PolylineRequest(
        origin: PointLatLng(
          double.parse(widget.rideData['pickup_latitude'].toString()),
          double.parse(widget.rideData['pickup_longitude'].toString()),
        ),
        destination: PointLatLng(
          double.parse(widget.rideData['destination_latitude'].toString()),
          double.parse(widget.rideData['destination_longitude'].toString()),
        ),
        mode: TravelMode.driving,
      ),
      googleApiKey: _googleApiKey,
    );

    if (result.points.isNotEmpty) {
      _polylineCoordinates.clear();
      for (var point in result.points) {
        _polylineCoordinates.add(LatLng(point.latitude, point.longitude));
      }
      setState(() {
        _polylines.add(Polyline(
          polylineId: const PolylineId("route"),
          points: _polylineCoordinates,
          color: const Color(0xFF0D47A1),
          width: 6,
        ));
      });
    }
  }

  Future<void> _startLiveTracking() async {
    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 10),
    ).listen((Position position) async {
      final controller = await _mapController.future;
      controller.animateCamera(CameraUpdate.newLatLng(
          LatLng(position.latitude, position.longitude)));
    });
  }

  // --- UI COMPONENTS ---

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _navigateToMain();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_getStatusTitle()),
          backgroundColor: const Color(0xFF0D47A1),
          foregroundColor: Colors.white,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back), onPressed: _navigateToMain),
        ),
        body: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: LatLng(
                    double.parse(widget.rideData['pickup_latitude'].toString()),
                    double.parse(widget.rideData['pickup_longitude'].toString())
                ),
                zoom: 15,
              ),
              onMapCreated: (controller) => _mapController.complete(controller),
              myLocationEnabled: true,
              markers: _markers,
              polylines: _polylines,
            ),
            if (_currentStatus == 'accepting')
              Positioned(
                  top: 20, left: 20, right: 20, child: _buildPassengerCard()),
            Align(alignment: Alignment.bottomCenter,
                child: _buildBottomActions()),
          ],
        ),
      ),
    );
  }

  String _getStatusTitle() {
    switch (_currentStatus) {
      case 'on_way':
        return "Driving to Passenger";
      case 'picked_up':
        return "Waiting for Payment";
      case 'paid':
        return "Payment Received";
      case 'completed':
        return "Trip Finished";
      default:
        return "Trip Details";
    }
  }

  Widget _buildBottomActions() {
    String buttonText;
    String? nextStatus;
    Color buttonColor = const Color(0xFF0D47A1);
    bool isEnabled = true;

    if (_currentStatus == 'accepting') {
      buttonText = "START JOURNEY (TO PICKUP)";
      nextStatus = 'on_way';
    } else if (_currentStatus == 'on_way') {
      buttonText = "PASSENGER PICKED UP";
      nextStatus = 'picked_up';
      buttonColor = Colors.orange;
    } else if (_currentStatus == 'picked_up') {
      buttonText = "WAITING FOR PAYMENT...";
      buttonColor = Colors.grey;
      isEnabled = false;
    } else if (_currentStatus == 'paid') {
      buttonText = "COMPLETE TRIP";
      nextStatus = 'completed';
      buttonColor = Colors.green;
    } else {
      buttonText = "TRIP COMPLETED";
      isEnabled = false;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(25, 20, 25, 40),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 60,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: buttonColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15))
          ),
          onPressed: isEnabled && nextStatus != null ? () =>
              _updateRideStatus(nextStatus!) : null,
          child: Text(buttonText, style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildPassengerCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
                backgroundColor: Color(0xFF0D47A1),
                child: Icon(Icons.person, color: Colors.white)
            ),
            title: const Text("Passenger",
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            subtitle: Text(widget.rideData['passenger_name'] ?? "User",
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 18)),
            trailing: IconButton(
              icon: const Icon(
                  Icons.chat_bubble_rounded, color: Color(0xFF0D47A1)),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        ChatDetailPage(
                          bookingId: widget.rideData['id'],
                          passengerName: widget.rideData['passenger_name'] ??
                              "Passenger",
                          driverUser: widget.driverUser,
                        ),
                  ),
                );
              },
            ),
          ),
          const Divider(),
          _locationRow(
              Icons.location_on, "Pickup", widget.rideData['pickup_address']),
          const SizedBox(height: 10),
          _locationRow(Icons.flag, "Destination",
              widget.rideData['destination_address']),
        ],
      ),
    );
  }

  Widget _locationRow(IconData icon, String label, String address) {
    return Row(
      children: [
        Icon(icon, color: Colors.blueGrey, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
              Text(address, style: const TextStyle(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  void _showPaymentSummary() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Column(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 60),
                SizedBox(height: 10),
                Text("Trip Completed!", textAlign: TextAlign.center),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Earnings for this trip:"),
                const SizedBox(height: 10),
                Text("RM ${widget.rideData['total_price']}",
                    style: const TextStyle(fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.green)),
              ],
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D47A1)),
                  onPressed: () {
                    Navigator.of(context).pop(); // Close dialog
                    // NAVIGATE TO FEEDBACK PAGE
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PassengerFeedbackPage(
                          bookingId: widget.rideData['id'],
                          // FIX: Pass the passenger_id from your rideData map
                          passengerId: widget.rideData['passenger_id'].toString(),
                          passengerName: widget.rideData['passenger_name'] ?? "Passenger",
                          driverUser: widget.driverUser,
                        ),
                      ),
                    );
                  },
                  child: const Text(
                      "RATE PASSENGER", style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
    );
  }
}