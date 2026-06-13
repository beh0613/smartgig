import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user.dart' as model;
import 'passenger_feedback_page.dart';

class ReportLocationPage extends StatefulWidget {
  final LatLng location;
  final String address;
  final Map<String, dynamic> rideInfo;
  final model.User driverUser;

  const ReportLocationPage({
    super.key,
    required this.location,
    required this.address,
    required this.rideInfo,
    required this.driverUser,
  });

  @override
  State<ReportLocationPage> createState() => _ReportLocationPageState();
}

class _ReportLocationPageState extends State<ReportLocationPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isSubmitting = false;

  // NEW: Track the selected flag for highlighting
  String? _selectedFlag;

  // The core list of flags
  final List<Map<String, dynamic>> flags = [
    {'label': 'Crowded', 'icon': Icons.groups_rounded, 'color': Colors.orange},
    {
      'label': 'No Parking',
      'icon': Icons.local_parking_rounded,
      'color': Colors.redAccent
    },
    {
      'label': 'Dimly Lit',
      'icon': Icons.nights_stay_rounded,
      'color': Colors.indigo
    },
    {
      'label': 'Traffic Jam',
      'icon': Icons.traffic_rounded,
      'color': Colors.amber
    },
    {
      'label': 'High Risk',
      'icon': Icons.warning_amber_rounded,
      'color': Colors.deepOrange
    },
    {
      'label': 'Easy Drop',
      'icon': Icons.check_circle_rounded,
      'color': Colors.green
    },
  ];

  Future<void> _submitReport(String label) async {
    setState(() {
      _selectedFlag = label; // Highlight the selection immediately
      _isSubmitting = true;
    });

    final now = DateTime.now();
    final int hour = now.hour;
    String timeOfDay = (hour >= 5 && hour < 12) ? "Morning"
        : (hour >= 12 && hour < 17) ? "Afternoon"
        : (hour >= 17 && hour < 20) ? "Evening" : "Night";

    try {
      await _supabase.from('location_reports').insert({
        'location_address': widget.address,
        'latitude': widget.location.latitude,
        'longitude': widget.location.longitude,
        'flag_label': label,
        'reported_at': now.toIso8601String(),
        'time_of_day': timeOfDay,
        'driver_id': widget.driverUser.id
      });

      if (mounted) {
        setState(() => _isSubmitting = false); // Stop loading before moving
        _goToFeedback();
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      _goToFeedback();
    }
  }

  // --- NEW: Custom Flag Dialog ---
  void _showCustomFlagDialog() {
    final TextEditingController customController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) =>
          AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Text("Custom Location Flag",
                style: TextStyle(fontWeight: FontWeight.bold)),
            content: TextField(
              controller: customController,
              decoration: const InputDecoration(
                hintText: "e.g., Road Construction, Event Nearby",
                border: OutlineInputBorder(),
              ),
              maxLength: 25,
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D47A1)),
                onPressed: () {
                  if (customController.text
                      .trim()
                      .isNotEmpty) {
                    Navigator.pop(context);
                    _submitReport(customController.text.trim());
                  }
                },
                child: const Text(
                    "Submit", style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
    );
  }

  void _goToFeedback() {
    Navigator.push( // CHANGED from pushReplacement to push
      context,
      MaterialPageRoute(
        builder: (context) =>
            PassengerFeedbackPage(
              bookingId: widget.rideInfo['bookingId']?.toString() ?? '',
              passengerId: widget.rideInfo['passengerId']?.toString() ?? '',
              passengerName: widget.rideInfo['passengerName']?.toString() ??
                  'Passenger',
              driverUser: widget.driverUser,
              destLat: widget.location.latitude,
              destLng: widget.location.longitude,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: const Text("Trip Completion", style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 1.2)),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                // STEP INDICATOR
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(radius: 5, backgroundColor: Color(0xFF0D47A1)),
                    SizedBox(width: 8),
                    CircleAvatar(radius: 5, backgroundColor: Color(0xFFE0E0E0)),
                  ],
                ),
                const SizedBox(height: 30),

                // --- HEADER ICON (PULSING PIN) ---
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0D47A1).withOpacity(0.12),
                        blurRadius: 40,
                        offset: const Offset(0, 10),
                      )
                    ],
                  ),
                  child: const Icon(
                      Icons.where_to_vote_rounded, // The "Checked Pin" icon
                      size: 48,
                      color: Color(0xFF0D47A1)
                  ),
                ),

                const SizedBox(height: 24),

// --- TITLE ---
                const Text(
                    "Arrived at Destination",
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                        color: Color(0xFF1E293B)
                    )
                ),

                const SizedBox(height: 12),

// --- PRETTY ADDRESS PILL ---
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D47A1).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF0D47A1).withOpacity(0.1)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFF0D47A1)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          widget.address,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: const Color(0xFF64748B),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                // GRID SECTION
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 1.4
                  ),
                  itemCount: flags.length + 1,
                  // +1 for the "Other" button
                  itemBuilder: (context, index) {
                    if (index == flags.length) {
                      // THE "OTHER" BUTTON
                      return _buildFlagCard(
                        label: "Other...",
                        icon: Icons.add_circle_outline_rounded,
                        color: Colors.blueGrey,
                        onTap: _showCustomFlagDialog,
                      );
                    }
                    final flag = flags[index];
                    return _buildFlagCard(
                      label: flag['label'],
                      icon: flag['icon'],
                      color: flag['color'],
                      onTap: () => _submitReport(flag['label']),
                    );
                  },
                ),

                const SizedBox(height: 40),
                TextButton(
                  onPressed: _isSubmitting ? null : _goToFeedback,
                  child: Text("Skip for now", style: TextStyle(
                      color: Colors.grey[400], fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
          if (_isSubmitting)
            Container(color: Colors.white.withOpacity(0.8),
                child: const Center(child: CircularProgressIndicator(
                    color: Color(0xFF0D47A1)))),
        ],
      ),
    );
  }

  Widget _buildFlagCard({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap
  }) {
    bool isSelected = _selectedFlag == label;

    return GestureDetector(
      onTap: _isSubmitting ? null : onTap,
      child: AnimatedScale(
        scale: isSelected ? 1.05 : 1.0, // Subtle "pop" effect when selected
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutQuart,
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(28),
            // Floating glass effect
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? color.withOpacity(0.3)
                    : Colors.black.withOpacity(0.03),
                blurRadius: isSelected ? 30 : 15,
                offset: isSelected ? const Offset(0, 12) : const Offset(0, 8),
                spreadRadius: isSelected ? 2 : -2,
              ),
            ],
            border: Border.all(
              color: isSelected ? color.withOpacity(0.5) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Stack(
              children: [
                // Background abstract glow for selected state
                if (isSelected)
                  Positioned(
                    top: -20, right: -20,
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: color.withOpacity(0.1),
                    ),
                  ),

                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // THE ICON HERO
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        padding: EdgeInsets.all(isSelected ? 16 : 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isSelected
                                ? [color, color.withOpacity(0.7)]
                                : [
                              color.withOpacity(0.1),
                              color.withOpacity(0.05)
                            ],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: isSelected ? [
                            BoxShadow(
                              color: color.withOpacity(0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            )
                          ] : [],
                        ),
                        child: Icon(
                          icon,
                          color: isSelected ? Colors.white : color,
                          size: isSelected ? 32 : 28,
                        ),
                      ),
                      const SizedBox(height: 14),
                      // THE TEXT
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 300),
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.w900 : FontWeight
                              .w600,
                          fontSize: 12,
                          color: isSelected ? color : const Color(0xFF4A4E69),
                          letterSpacing: isSelected ? 0.2 : 0,
                        ),
                        child: Text(label),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}