import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user.dart' as model; //
import 'active_ride_page.dart';
import '../state/driver_state.dart'; // Adjust path if needed
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart'; // Add this line!
import 'dart:typed_data';

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
// The Background Solid Wave
class HeaderArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()
      ..shader = LinearGradient(
        colors: [const Color(0xFF0D47A1), const Color(0xFF1976D2)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Offset.zero & size);

    var path = Path();
    path.lineTo(0, size.height - 40); // Start slightly above the bottom
    // A smooth, single arc from left to right
    path.quadraticBezierTo(
        size.width / 2, size.height,
        size.width, size.height - 40
    );
    path.lineTo(size.width, 0);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

// The Translucent Glass Wave
class GlassWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    var path = Path();
    path.lineTo(0, size.height - 30);
    path.quadraticBezierTo(size.width / 2, size.height, size.width, size.height - 30);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }
  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class _DriverDashboardState extends State<DriverDashboard> {
  final SupabaseClient _supabase = Supabase.instance.client;
  double _totalEarnings = 0.0;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isOnline = false;
  // Tracks if the driver is using default or personalized mode
  bool _useDefaultMode = true;
  // Total weight of selected indicators (only used in Personalized Mode)
  int _totalWeight = 0;
  // Track if the preference form is completed
  late bool _isPreferenceFilled;

  String? _profileImageUrl; // Add this
  final ImagePicker _picker = ImagePicker(); // Add this


  String _lastReportedFlag = "None";
  String _lastReportedLocation = "No recent reports";
  bool _isReportLoading = true;
  // 1. Updated Keys
  final Map<String, bool> _riskPrefs = {
    'abnormal_request': false,
    'crime_index': false,
    'road_accident': false,
    'road_condition': false,
    'weather': false,
    'lighting': false,
  };

// 2. Updated Weights
  final Map<String, int> _riskWeights = {
    'abnormal_request': 0,
    'crime_index': 0,
    'road_accident': 0,
    'road_condition': 0,
    'weather': 0,
    'lighting': 0,
  };

  // Helper getter to calculate the total sum


  @override
  void initState() {
    super.initState();
    _loadExistingPreferences();
    _isPreferenceFilled = widget.user.riskPreferencesFilled; // From your users table
    if (widget.initialActiveRide != null) {
      DriverState.currentRideData = widget.initialActiveRide;
    }
    _fetchRealtimeStats();
    _fetchLatestSafetyReport();
    _checkActiveRide();
    _setupPaymentListener();

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

  String _getGreeting() {
    final hour = DateTime.now().hour;

    if (hour < 12) {
      return "Good Morning";
    } else if (hour < 17) {
      return "Good Afternoon";
    } else {
      return "Good Evening";
    }
  }



  Future<void> _uploadProfilePicture() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
    );

    if (image == null) return;

    setState(() => _isLoading = true);

    try {
      // 2. Read as bytes (Uint8List)
      final Uint8List fileBytes = await image.readAsBytes();
      final fileName = '${widget.user.id}_profile.jpg';

      // 3. CHANGE .upload() TO .uploadBinary()
      await _supabase.storage.from('avatars').uploadBinary(
        fileName,
        fileBytes,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg', // Optional: tells Supabase it's an image
          upsert: true,
        ),
      );

      // 4. Get the URL
      final String publicUrl = _supabase.storage.from('avatars').getPublicUrl(fileName);

      // 5. Update Database
      await _supabase
          .from('users')
          .update({'profile_pic_url': publicUrl})
          .eq('id', widget.user.id);

      setState(() {
        _profileImageUrl = publicUrl;
        widget.user.profilePicUrl = publicUrl;
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile picture updated!")),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint("Upload Error: $e");
    }
  }




  Future<void> _fetchLatestSafetyReport() async {
    try {
      final response = await _supabase
          .from('location_reports')
          .select('flag_label, location_address')
          .eq('driver_id', widget.user.id)
          .order('reported_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (mounted) {
        setState(() {
          if (response != null) {
            _lastReportedFlag = response['flag_label'] ?? "Clear";
            _lastReportedLocation = response['location_address'] ?? "Unknown";
          }
          _isReportLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error: $e");
      if (mounted) setState(() => _isReportLoading = false);
    }
  }

  // Fetch specific risk booleans from driver_risk_preferences
  Future<void> _loadExistingPreferences() async {
    try {
      // 1. First, check the flag in the 'users' table
      final userRes = await _supabase
          .from('users')
          .select('risk_preferences_filled')
          .eq('id', widget.user.id)
          .maybeSingle();

      // 2. Fetch the actual weights
      final response = await _supabase
          .from('driver_risk_preferences')
          .select()
          .eq('user_id', widget.user.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          // If 'risk_preferences_filled' is false, we are in Default Mode
          _useDefaultMode = !(userRes?['risk_preferences_filled'] ?? false);

          if (response != null) {
            // Map Boolean Chips
            _riskPrefs['abnormal_request'] = response['abnormal_request'] ?? false;
            _riskPrefs['crime_index'] = response['crime_index'] ?? false;
            _riskPrefs['road_accident'] = response['road_accident'] ?? false;
            _riskPrefs['road_condition'] = response['road_condition'] ?? false;
            _riskPrefs['weather'] = response['weather'] ?? false;
            _riskPrefs['lighting'] = response['lighting'] ?? false;

            // Map Integer Weights for Sliders
            _riskWeights['abnormal_request'] = response['weight_request'] ?? 0;
            _riskWeights['crime_index'] = response['weight_crime'] ?? 0;
            _riskWeights['road_accident'] = response['weight_accident'] ?? 0;
            _riskWeights['road_condition'] = response['weight_condition'] ?? 0;
            _riskWeights['weather'] = response['weight_weather'] ?? 0;
            _riskWeights['lighting'] = response['weight_lighting'] ?? 0;
          }
        });
      }
    } catch (e) {
      debugPrint("Error syncing preferences: $e");
    }
  }


  // --- UPDATED METHOD: SAVES TO BOTH TABLES ---
  Future<void> _submitPreferences() async {
    setState(() => _isSaving = true);

    try {
      // 1. Prepare the Preference Data Map
      Map<String, dynamic> updateData = {'user_id': widget.user.id};

      if (_useDefaultMode) {
        // 🚀 FIXED: Every indicator is now exactly 16.67% (100 / 6)
        const double balancedWeight = 16.67;

        updateData.addAll({
          'abnormal_request': true, 'weight_request': balancedWeight,
          'crime_index': true,      'weight_crime': balancedWeight,
          'road_accident': true,    'weight_accident': balancedWeight,
          'road_condition': true,   'weight_condition': balancedWeight,
          'weather': true,          'weight_weather': balancedWeight,
          'lighting': true,         'weight_lighting': balancedWeight,
          'completed': true,
        });
      } else {
        // PERSONALIZED MODE: Validation
        if (_totalWeight != 100) {
          setState(() => _isSaving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Total weight must equal 100%"),
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }

        updateData.addAll({
          'abnormal_request': _riskPrefs['abnormal_request'],
          'weight_request': _riskWeights['abnormal_request'],
          'crime_index': _riskPrefs['crime_index'],
          'weight_crime': _riskWeights['crime_index'],
          'road_accident': _riskPrefs['road_accident'],
          'weight_accident': _riskWeights['road_accident'],
          'road_condition': _riskPrefs['road_condition'],
          'weight_condition': _riskWeights['road_condition'],
          'weather': _riskPrefs['weather'],
          'weight_weather': _riskWeights['weather'],
          'lighting': _riskPrefs['lighting'],
          'weight_lighting': _riskWeights['lighting'],
          'completed': true,
        });
      }

      // 2. Push to driver_risk_preferences table
      await _supabase.from('driver_risk_preferences').upsert(updateData);

      // 3. Update local user flag in the 'users' table
      bool isFilled = !_useDefaultMode;

      await _supabase
          .from('users')
          .update({'risk_preferences_filled': isFilled})
          .match({'id': widget.user.id});

      if (mounted) {
        setState(() {
          _isPreferenceFilled = isFilled;
          _isSaving = false;
          widget.user.riskPreferencesFilled = isFilled;

          if (_useDefaultMode) {
            // Reset UI state to reflect the balanced default
            _riskPrefs.updateAll((key, value) => true);
            // For the Sliders/UI text, we use the rounded integer 17
            _riskWeights.updateAll((key, value) => 17);
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_useDefaultMode
                ? "Safety Mode: All Indicators Balanced (16.67%)"
                : "Personalized Preferences Saved!"),
            backgroundColor: _useDefaultMode ? Colors.blueGrey[800] : Colors.green[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _isSaving = false);
      debugPrint("Submit Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to save preferences. Please try again.")),
      );
    }
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

  // UI Building Methods
  Widget _buildRiskPreferenceCard() {
    // Active indicators for sliders
    final activeKeys = _riskPrefs.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();

    // Calculate total weight dynamically
    _totalWeight = activeKeys.fold(0, (sum, key) => sum + _riskWeights[key]!);

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(0), // Margin handled by parent Column padding
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mode toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Risk Analysis Mode",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                ToggleButtons(
                  isSelected: [_useDefaultMode, !_useDefaultMode],
                  borderRadius: BorderRadius.circular(8),
                  selectedColor: Colors.white,
                  fillColor: Colors.blue[900],
                  constraints: const BoxConstraints(minHeight: 32, minWidth: 80),
                  children: const [
                    Text("Default", style: TextStyle(fontSize: 12)),
                    Text("Personal", style: TextStyle(fontSize: 12)),
                  ],
                  onPressed: (index) {
                    setState(() {
                      _useDefaultMode = index == 0;
                      // If switching to Personal, ensure we show the sliders
                      if (!_useDefaultMode) {
                        _isPreferenceFilled = true;
                      }
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 15),

            if (_useDefaultMode) ...[
              // Information for Default Mode
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[100]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[900], size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        "Default Mode calculates risk using all indicators with equal importance for maximum safety.",
                        style: TextStyle(fontSize: 11, color: Color(0xFF0D47A1)),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Personalized Selection
              const Text("1. Select Indicators",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 0,
                children: _riskPrefs.keys.map((key) {
                  return FilterChip(
                    label: Text(key.replaceAll('_', ' ').toUpperCase(),
                        style: const TextStyle(fontSize: 10)),
                    selected: _riskPrefs[key]!,
                    selectedColor: Colors.blue[100],
                    checkmarkColor: Colors.blue[900],
                    onSelected: (val) => setState(() {
                      _riskPrefs[key] = val;
                      if (!val) _riskWeights[key] = 0;
                    }),
                  );
                }).toList(),
              ),
              if (activeKeys.isNotEmpty) ...[
                const Divider(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("2. Assign Weightage",
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _totalWeight == 100 ? Colors.green[50] : Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "Total: $_totalWeight%",
                        style: TextStyle(
                          color: _totalWeight == 100 ? Colors.green[700] : Colors.red[700],
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                ...activeKeys.map((key) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(key.replaceAll('_', ' ').toUpperCase(),
                                style: const TextStyle(fontSize: 11)),
                            Text("${_riskWeights[key]}%",
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          ],
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                          ),
                          child: Slider(
                            value: _riskWeights[key]!.toDouble(),
                            min: 0,
                            max: 100,
                            divisions: 20,
                            activeColor: Colors.blue[900],
                            inactiveColor: Colors.blue[50],
                            onChanged: (val) => setState(() => _riskWeights[key] = val.toInt()),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],

            const SizedBox(height: 20),

            // Action Button to Save Preferences
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _submitPreferences,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[900],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _isSaving
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
                    : Text(
                  _useDefaultMode ? "Enable All & Apply" : "Save Preferences",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumHeader(BuildContext context) {
    const midnightBlue = Color(0xFF0A1931);
    const deepSapphire = Color(0xFF185ADB);
    // 🔍 DEBUG: Print the image URL to the console
    debugPrint("📸 CURRENT IMAGE URL: ${widget.user.profilePicUrl}");

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 32),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [midnightBlue, deepSapphire],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("SMARTGIG PORTAL",
                  style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
              IconButton(
                  onPressed: () => _showLogoutDialog(context),
                  icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 20)),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              GestureDetector(
                onTap: _uploadProfilePicture,
                child: Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24, width: 1)),
                      child: CircleAvatar(
                        radius: 38,
                        backgroundColor: Colors.white.withOpacity(0.1),

                        // 1. Set the image only if the URL exists
                        backgroundImage: (widget.user.profilePicUrl != null && widget.user.profilePicUrl!.isNotEmpty)
                            ? NetworkImage(widget.user.profilePicUrl!)
                            : null,

                        // 2. ONLY provide the error handler if there is an image to actually have an error.
                        // This prevents the "Failed assertion: line 80" error.
                        onBackgroundImageError: (widget.user.profilePicUrl != null && widget.user.profilePicUrl!.isNotEmpty)
                            ? (exception, stackTrace) {
                          debugPrint("Profile Image Load Failed: $exception");
                        }
                            : null,

                        // 3. Initials appear as a fallback when the image is null or loading
                        child: (widget.user.profilePicUrl == null || widget.user.profilePicUrl!.isEmpty)
                            ? Text(
                          widget.user.name.isNotEmpty ? widget.user.name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                            : null,
                      ),
                    ),
                    if (_isLoading)
                      const Positioned.fill(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent)),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(color: Colors.cyanAccent, shape: BoxShape.circle),
                        child: const Icon(Icons.camera_alt_rounded, size: 14, color: Color(0xFF0D47A1)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_getGreeting(),
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13, fontWeight: FontWeight.w500)),
                    Text(
                      widget.user.name.toUpperCase(), // 🚀 FIXED: Force Uppercase
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2), // Adjusted letter spacing
                    ),
                    Text(
                      widget.user.email.toLowerCase(),
                      style: const TextStyle(
                          color: Color(0xFFFDE68A), // Soft Amber/Gold
                          fontSize: 12,
                          fontWeight: FontWeight.w600
                      ),
                    ),
      const SizedBox(height: 10),
      // 🚀 MUTED SILVER BADGE (Replaces Neon Blue/Cyan)
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: const Text(
          "CAMPUS PARTNER",
          style: TextStyle(
              color: Color(0xFFCBD5E1), // Light Slate/Silver
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8
          ),
                    ),
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
        // SQUARE 1: SAFETY STATUS (Interactive)
        Expanded(
          child: GestureDetector(
            onTap: () => _showSafetyDetails(context), // Trigger the detail view
            child: Container(
              height: 160,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(
                          Icons.shield_rounded,
                          color: _lastReportedFlag == "Clear" ? Colors.green : Colors.orange,
                          size: 22
                      ),
                      const Icon(Icons.unfold_more_rounded, color: Colors.grey, size: 16),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    _isReportLoading ? "..." : _lastReportedFlag.toUpperCase(),
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.blue[900],
                        letterSpacing: -0.5
                    ),
                  ),
                  const Text(
                    "ACTIVE FLAG",
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.1),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(width: 16),

        // SQUARE 2: EARNINGS (Static)
        Expanded(
          child: Container(
            height: 160,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [const Color(0xFF0D47A1), Colors.blue[700]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue[900]!.withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.account_balance_wallet_rounded, color: Colors.white70, size: 22),
                const Spacer(),
                Text(
                  _isLoading ? "..." : "RM ${_totalEarnings.toStringAsFixed(2)}",
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.white
                  ),
                ),
                const Text(
                  "TOTAL REVENUE",
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white60, letterSpacing: 1.1),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showSafetyDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 20),
            const Text("Safety Report Detail", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(height: 30),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.flag_rounded, color: Colors.blue[900]),
              title: const Text("Current Flag"),
              subtitle: Text(_lastReportedFlag, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.location_on_rounded, color: Colors.redAccent),
              title: const Text("Reported Location"),
              subtitle: Text(_lastReportedLocation, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[900],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text("Close", style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _statCard(String label, String value, IconData icon, Color iconColor) {
    return Expanded(
      child: Container(
        height: 140, // Fixed height keeps the grid symmetrical
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 22),
            const Spacer(),
            Text(
              value,
              maxLines: 1, // Prevents layout breaking
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 18, // Slightly smaller to fit destinations
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5
              ),
            ),
            Text(
              label,
              style: TextStyle(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildProfileCard(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // 🚀 Option A: Tapping the whole card takes them to Profile Details
        Navigator.pushNamed(
          context,
          '/profile_details',
          arguments: widget.user,
        );
      },
      child: _infoWrapper(
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(Icons.person_outline_rounded, color: Color(0xFF185ADB)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.user.name.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF0A1931)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.user.email,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),

            // 🚀 ADDED HERE: Interactive Edit Profile Action Button
            IconButton(
              icon: const Icon(Icons.edit_note_rounded, color: Colors.blue),
              onPressed: () async {
                // Navigate to EditProfilePage and wait to see if changes were saved
                final shouldRefresh = await Navigator.pushNamed(
                  context,
                  '/edit_profile',
                  arguments: widget.user,
                );

                // If the user updated data, trigger a refresh on the dashboard
                if (shouldRefresh == true && mounted) {
                  _fetchRealtimeStats();
                }
              },
            ),
          ],
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
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white, width: 1.5), // Subtle "shine"
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A237E).withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, 12),
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
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                /// Logout Icon
                /// Logout Icon Container
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.redAccent.shade200, Colors.red.shade800],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.exit_to_app_rounded, // prettier logout icon
                    color: Colors.white,
                    size: 32,
                  ),
                ),

                const SizedBox(height: 20),

                /// Title
                const Text(
                  "Sign Out",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                /// Message
                const Text(
                  "Are you sure you want to logout from your driver account?",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 30),

                /// Buttons
                Row(
                  children: [

                    /// Cancel Button
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        child: const Text("Cancel"),
                      ),
                    ),

                    const SizedBox(width: 12),

                    /// Logout Button
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () async {
                          // 1. Trigger the sign out immediately
                          await Supabase.instance.client.auth.signOut();

                          // 2. Clear Google Sign In session (Important for the account picker we discussed!)
                          await GoogleSignIn().signOut();

                          if (context.mounted) {
                            // 3. This one command closes the dialog AND moves to login,
                            // removing all previous screens from the stack.
                            Navigator.pushNamedAndRemoveUntil(
                              context,
                              '/login',
                                  (route) => false,
                            );
                          }
                        },
                        child: const Text(
                          "Logout",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}