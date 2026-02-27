import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user.dart' as model; //
import 'active_ride_page.dart';

class DriverState {
  static bool isOnline = false;
  // Store the active ride data here so it persists across pages
  static Map<String, dynamic>? currentRideData;
}

class DriverDashboard extends StatefulWidget {
  final model.User user; //
  final Map<String, dynamic>? initialActiveRide; // ADD THIS LINE

  const DriverDashboard({
    super.key,
    required this.user,
    this.initialActiveRide
  });

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  final SupabaseClient _supabase = Supabase.instance.client;
  double _totalEarnings = 0.0;
  bool _isLoading = true;
  bool _isSaving = false;

  // Track if the preference form is completed
  late bool _isPreferenceFilled;

  // The 6 specific Risk Indicators requested
  final Map<String, bool> _riskPrefs = {
    'reported_crime': false,
    'abnormal_request': false,
    'road_accident': false,
    'road_condition': false,
    'weather': false,
    'lightning': false,
  };

  @override
  void initState() {
    super.initState();
    _isPreferenceFilled = widget.user.riskPreferencesFilled; // From your users table
    if (widget.initialActiveRide != null) {
      DriverState.currentRideData = widget.initialActiveRide;
    }
    _fetchRealtimeStats();
    _checkActiveRide();
    if (_isPreferenceFilled) {
      _loadExistingPreferences();
    }
  }

  void _setupPaymentListener() {
    _supabase
        .channel('public:payments')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'payments',
      callback: (payload) {
        // Whenever a new payment is inserted, refresh the stats
        _fetchRealtimeStats();
      },
    )
        .subscribe();
  }

  // Fetch specific risk booleans from driver_risk_preferences
  Future<void> _loadExistingPreferences() async {
    try {
      final data = await _supabase
          .from('driver_risk_preferences')
          .select()
          .eq('user_id', widget.user.id)
          .maybeSingle();

      if (data != null && mounted) {
        setState(() {
          _riskPrefs['reported_crime'] = data['reported_crime'] ?? false;
          _riskPrefs['abnormal_request'] = data['abnormal_request'] ?? false;
          _riskPrefs['road_accident'] = data['road_accident'] ?? false;
          _riskPrefs['road_condition'] = data['road_condition'] ?? false;
          _riskPrefs['weather'] = data['weather'] ?? false;
          _riskPrefs['lightning'] = data['lightning'] ?? false;
        });
      }
    } catch (e) {
      debugPrint("Load Prefs Error: $e");
    }
  }

  // --- UPDATED METHOD: SAVES TO BOTH TABLES ---
  Future<void> _submitPreferences() async {
    setState(() => _isSaving = true);
    try {
      // 1. Upsert detailed preferences
      await _supabase.from('driver_risk_preferences').upsert({
        'user_id': widget.user.id,
        'reported_crime': _riskPrefs['reported_crime'],
        'abnormal_request': _riskPrefs['abnormal_request'],
        'road_accident': _riskPrefs['road_accident'],
        'road_condition': _riskPrefs['road_condition'],
        'weather': _riskPrefs['weather'],
        'lightning': _riskPrefs['lightning'],
        'completed': true,
      });

      // 2. Update the main users table flag
      // 2. Update the main users table completion flag
      final userUpdateResponse = await _supabase
          .from('users')
          .update({'risk_preferences_filled': true})
          .match({'id': widget.user.id}) // Use match instead of eq for better reliability
          .select(); // Calling .select() confirms if the update actually returned data

      if (userUpdateResponse.isEmpty) {
        debugPrint("⚠️ Warning: Users table was NOT updated. Check RLS policies.");
      }

      if (mounted) {
        setState(() {
          _isPreferenceFilled = true;
          _isSaving = false;

        });

        // 3. Update the local object (This works now because we removed 'final')
        widget.user.riskPreferencesFilled = true;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Safety preferences synced successfully"),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint("Update Error: $e");
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to update: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }


  Future<void> _checkActiveRide() async {
    try {
      final data = await _supabase
          .from('bookings')
          .select()
      // Checks for any ride assigned to this driver that is not yet finished
          .eq('driver_id', widget.user.id)
          .or('status.eq.accepting,status.eq.on_way,status.eq.picked_up')
          .maybeSingle();

      if (data != null && mounted) {
        setState(() {
          // FIX: Assign to the static global variable
          DriverState.currentRideData = data;
        });
      }
    } catch (e) {
      debugPrint("Check active ride error: $e");
    }
  }
  /// Fetches total earnings for the current driver from the 'bookings' table
  Future<void> _fetchRealtimeStats() async {
    try {
      // We select amount from payments, joining through bookings
      // to verify the driver_id in ride_assignments
      final response = await _supabase
          .from('payments')
          .select('''
          amount,
          bookings!inner (
            id,
            ride_assignments!inner (
              driver_id
            )
          )
        ''')
          .eq('bookings.ride_assignments.driver_id', widget.user.id);

      double earnings = 0;
      if (response is List) {
        for (var row in response) {
          // Parse the 'amount' field from each successful payment record
          final double? val = double.tryParse(row['amount'].toString());
          if (val != null) {
            earnings += val;
          }
        }
      }

      if (mounted) {
        setState(() {
          _totalEarnings = earnings;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Earnings Fetch Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      body: RefreshIndicator(
        onRefresh: _fetchRealtimeStats,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildPremiumHeader(context),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 25),
                    _buildStatGrid(),

                    const SizedBox(height: 30),
                    _sectionHeader("Trust Risk Indicators"),
                    _buildRiskPreferenceCard(),

                    const SizedBox(height: 25),
                    _sectionHeader("Personal Account"),
                    _buildProfileCard(context),
                    const SizedBox(height: 25),
                    _sectionHeader("Vehicle Details"),
                    _buildVehicleCard(context),
                    const SizedBox(height: 30),
                    _buildSupportSection(),
                    const SizedBox(height: 120),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildFloatingBottomNav(context),
      extendBody: true,
    );
  }

  Widget _buildRiskPreferenceCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
        // Highlight border if they haven't filled it yet
        border: !_isPreferenceFilled
            ? Border.all(color: Colors.orange.withOpacity(0.5), width: 2)
            : null,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                _isPreferenceFilled ? Icons.verified_user : Icons.gpp_maybe_rounded,
                color: _isPreferenceFilled ? Colors.blue[900] : Colors.orange,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "Risk Monitoring Preferences",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "Select which risks you want to identify during your shift:",
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          const Divider(height: 30),
          ..._riskPrefs.keys.map((key) {
            return CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                key.replaceAll('_', ' ').toUpperCase(),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              value: _riskPrefs[key],
              activeColor: Colors.blue[900],
              dense: true,
              onChanged: (val) => setState(() => _riskPrefs[key] = val!),
            );
          }).toList(),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _submitPreferences,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[900],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 0,
              ),
              child: _isSaving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(_isPreferenceFilled ? "Update Preferences" : "Confirm & Save"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 60, left: 25, right: 25, bottom: 40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[900]!, const Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(40),
          bottomRight: Radius.circular(40),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "DASHBOARD",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                onPressed: () => _showLogoutDialog(context),
                icon: const Icon(Icons.power_settings_new, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              const CircleAvatar(
                radius: 30,
                backgroundColor: Colors.white24,
                child: Icon(Icons.person, color: Colors.white, size: 35),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Hello, ${widget.user.name.split(' ')[0]}!", //
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      "UUM Official Driver",
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatGrid() {
    return Row(
      children: [
        _statCard("Trust Score", "4.9", Icons.stars_rounded, Colors.orange),
        const SizedBox(width: 15),
        _statCard(
            "Earnings",
            _isLoading ? "..." : "RM ${_totalEarnings.toStringAsFixed(2)}",
            Icons.payments_rounded,
            Colors.green
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color iconColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 28),
            const SizedBox(height: 15),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context) {
    return _infoWrapper(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          widget.user.name, //
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(widget.user.email), //
        trailing: IconButton(
          icon: const Icon(Icons.edit_note_rounded, color: Colors.blue),
          onPressed: () => Navigator.pushNamed(
            context,
            '/edit_profile',
            arguments: widget.user,
          ),
        ),
      ),
    );
  }

  Widget _buildVehicleCard(BuildContext context) {
    return _infoWrapper(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.directions_car_filled_rounded, color: Colors.blueGrey),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.user.carModel, //
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  "${widget.user.carPlate} • ${widget.user.carColor}", //
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pushNamed(
              context,
              '/car_verify',
              arguments: {'isUpdate': true, 'id': widget.user.id, 'user_object': widget.user},
            ),
            icon: const Icon(Icons.edit_note_rounded, color: Colors.blue),
          ),
        ],
      ),
    );
  }

  Widget _buildSupportSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue[900],
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Row(
        children: [
          Icon(Icons.headset_mic_rounded, color: Colors.white, size: 30),
          SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Support Center",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                Text(
                  "uumdriver2025@gmail.com",
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Colors.grey[500],
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _infoWrapper({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildFloatingBottomNav(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(25, 0, 25, 30),
      height: 70,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(35),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _navIcon(Icons.home_outlined, "Home", false,
                  () => Navigator.pushReplacementNamed(context, '/main', arguments: widget.user)),
          _navIcon(Icons.directions_car_outlined, "Active Ride", false, () {
            // Check global state for an active ride
            if (DriverState.currentRideData != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ActiveRidePage(
                    rideData: DriverState.currentRideData!,
                    driverUser: widget.user,
                  ),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("No active ride in progress"),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }),
          _navIcon(Icons.chat_bubble_outline_rounded, "Message", false,
                  () => Navigator.pushReplacementNamed(context, '/message_page', arguments: widget.user)),
          _navIcon(Icons.grid_view_rounded, "Dashboard", true, () {}),
        ],
      ),
    );
  }

  Widget _navIcon(IconData icon, String label, bool isActive, VoidCallback onTap) {
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
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? activeColor : inactiveColor,
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Sign Out"),
        content: const Text("Are you sure you want to logout?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false),
            child: const Text("Logout", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}