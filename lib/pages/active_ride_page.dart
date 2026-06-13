import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import '../models/user.dart' as model;
import 'chat_detail_page.dart';
import 'passenger_feedback_page.dart';
import 'reportlocationpage.dart';

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
    // NEW: Get current position and draw the first path to the passenger
    Geolocator.getCurrentPosition().then((Position pos) {
      _getPolyline(
        LatLng(pos.latitude, pos.longitude), // Start at Driver
        LatLng(
            double.parse(widget.rideData['pickup_latitude'].toString()),
            double.parse(widget.rideData['pickup_longitude'].toString())
        ), // End at Pickup
      );
    });
    // Explicitly clear local collections to ensure a fresh start
    _markers.clear();
    _polylines.clear();
    _polylineCoordinates.clear();

    _currentStatus = widget.rideData['status'] ?? 'accepting';

    _initMarkers();

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

  // Inside _ActiveRidePageState in ActiveRidePage.dart

  void _subscribeToBookingChanges() {
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
        // Use .toLowerCase() and .trim() to be 100% sure
        final String newStatus = (payload.newRecord['status'] as String)
            .toLowerCase()
            .trim();

        if (mounted) {
          setState(() {
            _currentStatus = newStatus;
          });

          if (newStatus == 'paid') {
            debugPrint("✅ Realtime: Payment confirmed!");
            _showSuccessOverlay(); // Show the snackbar
            _showPaymentSummary(); // Open the rating dialog
          }
        }
      },
    ).subscribe();
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
          .select()
          .or(
          'status.eq.accepting,status.eq.on_way,status.eq.picked_up,status.eq.paid') // Only active statuses
          .order('created_at', ascending: false) // Get the latest one
          .limit(1)
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
      // 1. Update Supabase
      await _supabase.from('bookings').update({'status': newStatus}).eq(
          'id', widget.rideData['id']);

      if (!mounted) return;

      // 2. Get current positions for routing
      Position currentPos = await Geolocator.getCurrentPosition();
      LatLng driverLatLng = LatLng(currentPos.latitude, currentPos.longitude);

      final pickup = LatLng(
        double.parse(widget.rideData['pickup_latitude'].toString()),
        double.parse(widget.rideData['pickup_longitude'].toString()),
      );
      final destination = LatLng(
        double.parse(widget.rideData['destination_latitude'].toString()),
        double.parse(widget.rideData['destination_longitude'].toString()),
      );

      setState(() {
        _currentStatus = newStatus;
        _markers.clear();

        // --- PHASE 2: PASSENGER IN CAR -> HEADING TO DESTINATION ---
        if (newStatus == 'picked_up') {
          _markers.add(Marker(
            markerId: const MarkerId('destination'),
            position: destination,
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueRed),
            infoWindow: const InfoWindow(title: "Drop-off Location"),
          ));

          // Redraw curvy polyline from current location to final destination
          _getPolyline(driverLatLng, destination);
        }

        // --- PHASE 1: DRIVING TO PICKUP ---
        else {
          _markers.add(Marker(
            markerId: const MarkerId('pickup'),
            position: pickup,
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen),
            infoWindow: const InfoWindow(title: "Pickup Passenger"),
          ));

          // Redraw curvy polyline from driver to passenger
          _getPolyline(driverLatLng, pickup);
        }
      });

      // 3. AUTO-ZOOM CAMERA
      final controller = await _mapController.future;
      LatLng target = newStatus == 'picked_up' ? destination : pickup;

      // Fit both driver and the next goal in view
      LatLngBounds bounds = LatLngBounds(
        southwest: LatLng(
          driverLatLng.latitude < target.latitude
              ? driverLatLng.latitude
              : target.latitude,
          driverLatLng.longitude < target.longitude
              ? driverLatLng.longitude
              : target.longitude,
        ),
        northeast: LatLng(
          driverLatLng.latitude > target.latitude
              ? driverLatLng.latitude
              : target.latitude,
          driverLatLng.longitude > target.longitude
              ? driverLatLng.longitude
              : target.longitude,
        ),
      );
      controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 70));

      if (newStatus == 'completed' || newStatus == 'paid') {
        _showPaymentSummary();
      }
    } catch (e) {
      debugPrint("Update Error: $e");
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


  Future<void> _getPolyline(LatLng start, LatLng end) async {
    PolylinePoints polylinePoints = PolylinePoints();
    PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
      request: PolylineRequest(
        origin: PointLatLng(start.latitude, start.longitude),
        destination: PointLatLng(end.latitude, end.longitude),
        mode: TravelMode.driving,
      ),
      googleApiKey: _googleApiKey,
    );

    if (result.points.isNotEmpty) {
      setState(() {
        _polylineCoordinates.clear();
        for (var point in result.points) {
          _polylineCoordinates.add(LatLng(point.latitude, point.longitude));
        }
        _polylines.clear(); // Important: remove old lines before adding new one
        _polylines.add(Polyline(
          polylineId: const PolylineId("active_route"),
          points: _polylineCoordinates,
          color: _currentStatus == 'picked_up' ? Colors.green : const Color(
              0xFF0D47A1),
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


  void _showReportLocationSheet(LatLng location, String address) {
    final List<Map<String, dynamic>> flags = [
      {'label': 'Crowded', 'icon': Icons.groups, 'color': Colors.orange},
      {'label': 'No Parking', 'icon': Icons.local_parking, 'color': Colors.red},
      {'label': 'Dimly Lit', 'icon': Icons.nights_stay, 'color': Colors.indigo},
      {'label': 'Traffic Jam', 'icon': Icons.traffic, 'color': Colors.amber},
      {
        'label': 'High Risk',
        'icon': Icons.report_problem,
        'color': Colors.redAccent
      },
      {'label': 'Easy Drop', 'icon': Icons.check_circle, 'color': Colors.green},
    ];

    showModalBottomSheet(
      context: context,
      isDismissible: false, // Force them to choose or skip
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) =>
          Padding(
            padding: const EdgeInsets.fromLTRB(25, 20, 25, 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40,
                    height: 5,
                    decoration: BoxDecoration(color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(10))),
                const SizedBox(height: 20),
                const Text("How is the location right now?", style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 5),
                Text(address, textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                const SizedBox(height: 25),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 15,
                      crossAxisSpacing: 15,
                      childAspectRatio: 0.9
                  ),
                  itemCount: flags.length,
                  itemBuilder: (context, index) {
                    return InkWell(
                      onTap: () =>
                          _submitLocationReport(
                              flags[index]['label'], location, address),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 25,
                            backgroundColor: flags[index]['color'].withOpacity(
                                0.1),
                            child: Icon(flags[index]['icon'],
                                color: flags[index]['color']),
                          ),
                          const SizedBox(height: 8),
                          Text(flags[index]['label'], style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    );
                  },
                ),
                TextButton(
                  onPressed: () => _navigateToMain(),
                  child: const Text(
                      "Skip Reporting", style: TextStyle(color: Colors.grey)),
                )
              ],
            ),
          ),
    );
  }

  Future<void> _submitLocationReport(String label, LatLng pos,
      String address) async {
    final now = DateTime.now();
    final int hour = now.hour;
    String timeOfDay;

    // Logic to categorize actual time
    if (hour >= 5 && hour < 12)
      timeOfDay = "Morning";
    else if (hour >= 12 && hour < 17)
      timeOfDay = "Afternoon";
    else if (hour >= 17 && hour < 20)
      timeOfDay = "Evening";
    else
      timeOfDay = "Night";

    try {
      await _supabase.from('location_reports').insert({
        'location_address': address,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'flag_label': label,
        'reported_at': now.toIso8601String(), // The actual timestamp
        'time_of_day': timeOfDay, // The easy category
        'driver_id': widget.driverUser.id
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Thanks! Marked as $label for $timeOfDay hours.")),
        );
        _navigateToMain();
      }
    } catch (e) {
      debugPrint("Report Error: $e");
      _navigateToMain();
    }
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
      isEnabled = false; // Button disabled while waiting for passenger to pay
    } else if (_currentStatus == 'paid') {
      // NEW: Button changes to green and allows opening the rating form
      buttonText = "PAYMENT RECEIVED - RATE NOW";
      buttonColor = Colors.green;
      isEnabled = true;
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
          onPressed: isEnabled
              ? () {
            if (_currentStatus == 'paid') {
              // If they are in 'paid' status, clicking the button opens the rating dialog
              _showPaymentSummary();
            } else if (nextStatus != null) {
              _updateRideStatus(nextStatus);
            }
          }
              : null,
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
            title: const Text("Trip Summary"),
            content: const Text(
                "Payment received. Please report the location status and rate your passenger."),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D47A1)),
                  onPressed: () {
                    Navigator.pop(context); // Close dialog

                    final LatLng destLocation = LatLng(
                      double.parse(
                          widget.rideData['destination_latitude'].toString()),
                      double.parse(
                          widget.rideData['destination_longitude'].toString()),
                    );

                    // NAVIGATE TO THE NEW DEDICATED PAGE
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ReportLocationPage(
                              location: destLocation,
                              address: widget.rideData['destination_address'] ??
                                  "Unknown",
                              driverUser: widget.driverUser,
                              rideInfo: {
                                'bookingId': widget.rideData['id'],
                                'passengerId': widget.rideData['passenger_id'],
                                'passengerName': widget
                                    .rideData['passenger_name'],
                              },
                            ),
                      ),
                    );
                  },
                  child: const Text(
                      "NEXT", style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
    );
  }
}