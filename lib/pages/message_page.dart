import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user.dart' as model;
import 'chat_detail_page.dart';
import 'active_ride_page.dart';
import 'package:smartgig/state/driver_state.dart';


class MessagePage extends StatefulWidget {
  final model.User user;

  final Map<String, dynamic>? initialActiveRide; // ADD THIS LINE

  const MessagePage({
    super.key,
    required this.user,
    this.initialActiveRide
  });

  @override
  State<MessagePage> createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  RealtimeChannel? _rideSubscription; //
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkActiveRide(); // Initial check
    // If data was passed from the previous page, use it immediately
    if (widget.initialActiveRide != null) {
      DriverState.currentRideData = widget.initialActiveRide;
    }
    _setupRideListener(); // Start real-time sync
  }

  @override
  void dispose() {
    // Clean up subscription to prevent memory leaks
    if (_rideSubscription != null) {
      _supabase.removeChannel(_rideSubscription!);
    }
    super.dispose();
  }

  // Initial Check to populate the state immediately
  Future<void> _checkActiveRide() async {
    try {
      // 1. Query ride_assignments to find the current job for THIS driver
      // We use bookings!inner to ensure we only get assignments that have a valid booking
      final response = await _supabase
          .from('ride_assignments')
          .select('''
          *,
          bookings!inner (
            *
          )
        ''')
          .eq('driver_id', widget.user.id) // Using your 'user' variable
          .filter('bookings.status', 'in', '("accepting","on_way","picked_up","paid")')
          .order('accepted_at', ascending: false)
          .limit(1)
          .maybeSingle();

      // If no active ride is found, stop here and let the driver see the "Search" UI
      if (response == null || response['bookings'] == null) {
        debugPrint("No active assignment found for driver: ${widget.user.id}");
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // 2. Extract and format the booking data
      final rideData = Map<String, dynamic>.from(response['bookings'] as Map);

      // 3. Navigate to the Active Ride Page
      if (mounted) {
        Navigator.pushReplacementNamed(
          context,
          '/active_ride',
          arguments: {
            'rideData': rideData,
            'driverUser': widget.user, // Passing the user object to the next page
          },
        );
      }

    } catch (e) {
      debugPrint("⛔ Check Active Ride Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Real-time listener: This keeps the data alive even if the page re-builds
  void _setupRideListener() {
    _rideSubscription = _supabase
        .channel('active_ride_sync')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'bookings',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'driver_id',
        value: widget.user.id,
      ),
      callback: (payload) {
        // Re-fetch data whenever any change happens to this driver's bookings
        _checkActiveRide();
      },
    )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 80, 0, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 25),
                  child: Text("Messages",
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _supabase
                        .from('ride_assignments')
                        .stream(primaryKey: ['id'])
                        .eq('driver_id', widget.user.id)
                        .order('accepted_at', ascending: false),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Center(child: Text("No active conversations"));
                      }
                      final assignments = snapshot.data!;
                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 120),
                        itemCount: assignments.length,
                        itemBuilder: (context, index) {
                          final assignment = assignments[index];
                          final String bookingId = assignment['booking_id'].toString();
                          return _buildChatTile(
                              context,
                              "Passenger (Ride #${bookingId.substring(0, 5)})",
                              "Tap to chat about this ride",
                              "Now",
                              false,
                              bookingId,
                              widget.user
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _buildFloatingBottomNav(context, widget.user),
          ),
        ],
      ),
    );
  }

  // --- UI HELPERS ---

  Widget _buildChatTile(BuildContext context, String name, String msg, String time, bool unread, String bookingId, model.User user) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 25, vertical: 8),
      leading: CircleAvatar(
        radius: 25,
        backgroundColor: Colors.blue[50],
        child: Text(name[0], style: const TextStyle(color: Color(0xFF0D47A1), fontWeight: FontWeight.bold)),
      ),
      title: Text(name, style: TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.normal)),
      subtitle: Text(msg, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(time, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatDetailPage(
              bookingId: bookingId,
              passengerName: name,
              driverUser: user,
            ),
          ),
        );
      },
    );
  }

  Widget _buildFloatingBottomNav(BuildContext context, model.User user) {
    return Container(
      margin: const EdgeInsets.fromLTRB(25, 0, 25, 30),
      height: 70,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(35),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _navIcon(context, Icons.home_outlined, "Home", false, () {
            Navigator.pushReplacementNamed(context, '/main', arguments: user);
          }),

          _navIcon(context, Icons.directions_car_outlined, "Active Ride", false, () async {
            // Re-check once manually if it's missing
            if (DriverState.currentRideData == null) {
              await _checkActiveRide();
            }

            if (DriverState.currentRideData != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ActiveRidePage(
                    rideData: DriverState.currentRideData!,
                    driverUser: user,
                  ),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("No active ride found. Refreshing..."),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }),

          _navIcon(context, Icons.chat_bubble_rounded, "Message", true, () {}),

          _navIcon(context, Icons.grid_view_rounded, "Dashboard", false, () {
            Navigator.pushReplacementNamed(context, '/driver_dashboard', arguments: user);
          }),
        ],
      ),
    );
  }

  Widget _navIcon(BuildContext context, IconData icon, String label, bool isActive, VoidCallback onTap) {
    final Color activeColor = Colors.blue[900]!;
    final Color inactiveColor = Colors.grey[400]!;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: isActive ? activeColor : inactiveColor, size: 26),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: isActive ? FontWeight.bold : FontWeight.normal, color: isActive ? activeColor : inactiveColor)),
        ],
      ),
    );
  }
}