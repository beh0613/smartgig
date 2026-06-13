import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user.dart' as model;

class PassengerFeedbackPage extends StatefulWidget {
  final String bookingId;
  final String passengerId;
  final String passengerName;
  final model.User driverUser;
  final VoidCallback? onComplete;
  // Recommended: Pass actual coordinates from the active ride
  final double destLat;
  final double destLng;

  const PassengerFeedbackPage({
    super.key,
    required this.bookingId,
    required this.passengerId,
    required this.passengerName,
    required this.driverUser,
    this.onComplete,
    this.destLat = 6.4675, // Defaulting to your hardcoded values if not provided
    this.destLng = 100.5055,
  });

  @override
  State<PassengerFeedbackPage> createState() => _PassengerFeedbackPageState();
}

class _PassengerFeedbackPageState extends State<PassengerFeedbackPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _commentController = TextEditingController();

  double _rating = 5.0;
  bool _hadAbnormalRequest = false;
  double _abnormalSeverity = 1.0;
  bool _isSubmitting = false;

  final Map<String, bool> _attitudeTags = {
    'Polite': false,
    'Quiet': false,
    'Punctual': false,
    'Disrespectful': false,
    'Safety Concern': false,
    'Helpful': false,
  };

  Color _getSeverityColor(double level) {
    if (level <= 1) return Colors.amber;
    if (level <= 3) return Colors.orange;
    return Colors.red[900]!;
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.blueGrey, letterSpacing: 1.5)),
          const SizedBox(width: 12),
          Expanded(child: Divider(color: Colors.grey[200], thickness: 1)),
        ],
      ),
    );
  }

  // VALIDATION & SUBMISSION
  // VALIDATION & SUBMISSION
  Future<void> _submitFeedback() async {
    final String comment = _commentController.text.trim();
    // Use the validated ID from the widget
    final String driverId = widget.driverUser.id;

    // 1. Safety Guard: Check for empty UUID before hitting Supabase
    if (driverId.isEmpty) {
      debugPrint("🚨 Error: Driver ID is empty in Feedback Page.");
      _showCustomAlert("Session Error", "User ID not found. Please try again.");
      return;
    }

    // 2. HARD VALIDATION: Ensure flags are set for low ratings
    if (_rating <= 2 && comment.isEmpty) {
      _showCustomAlert("Comment Required", "Please explain why the rating is low.");
      return;
    }

    if (_hadAbnormalRequest && comment.length < 5) {
      _showCustomAlert("More Info Needed", "Please describe the abnormal request in the comments.");
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final selectedTags = _attitudeTags.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList();

      final payload = {
        'booking_id': widget.bookingId,
        'passenger_id': widget.passengerId,
        'driver_id': driverId, // Correctly mapped to UUID
        'rating': _rating.toInt(),
        'abnormal_request': _hadAbnormalRequest,
        'abnormal_severity': _hadAbnormalRequest ? _abnormalSeverity.toInt() : 0,
        'attitude_tags': selectedTags,
        'comment': comment,
        'created_at': DateTime.now().toIso8601String(),
      };

      // 3. ATOMIC UPDATE: Save feedback and mark booking as finished
      await Future.wait([
        _supabase.from('passenger_feedback').insert(payload),
        _supabase.from('bookings').update({'status': 'completed'}).eq('id', widget.bookingId),
      ]);

      if (mounted) {
        debugPrint("✅ Feedback saved successfully for Booking: ${widget.bookingId}");

        // Return to main map and refresh the driver's state
        Navigator.pushNamedAndRemoveUntil(
            context,
            '/main',
                (route) => false,
            arguments: {'user': widget.driverUser}
        );
      }
    } catch (e) {
      debugPrint("🚨 Feedback Submission Error: $e");
      // If you still see 22P02 here, double-check that driverId isn't ""
      _showCustomAlert("Error", "Failed to save rating: $e");
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showCustomAlert(String title, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.black87, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFE),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        title: const Text("Feedback To Passenger"),
        // Added the back icon manually
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () {
            // This takes the user back to the ReportLocationPage
            Navigator.pop(context);
          },
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // HEADER
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(25),
              color: Colors.white,
              child: Column(
                children: [
                  const CircleAvatar(radius: 40, backgroundColor: Color(0xFFF1F3F4), child: Icon(Icons.person, size: 40, color: Colors.blueGrey)),
                  const SizedBox(height: 10),
                  Text(widget.passengerName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) => IconButton(
                      icon: Icon(index < _rating ? Icons.star_rounded : Icons.star_outline_rounded, color: index < _rating ? Colors.amber[600] : Colors.grey[200], size: 45),
                      onPressed: () => setState(() => _rating = index + 1.0),
                    )),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  _buildSectionHeader("PASSENGER ATTITUDE"),
                  Wrap(
                    spacing: 10,
                    children: _attitudeTags.keys.map((tag) => FilterChip(
                      label: Text(tag, style: TextStyle(fontSize: 12, color: _attitudeTags[tag]! ? Colors.white : Colors.black87)),
                      selected: _attitudeTags[tag]!,
                      selectedColor: const Color(0xFF0D47A1),
                      onSelected: (val) => setState(() => _attitudeTags[tag] = val),
                    )).toList(),
                  ),

                  _buildSectionHeader("PASSENGER BEHAVIORAL"),
                  Container(
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text("Report Abnormal Request?", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          value: _hadAbnormalRequest,
                          activeColor: _getSeverityColor(_abnormalSeverity),
                          onChanged: (val) => setState(() => _hadAbnormalRequest = val),
                        ),
                        if (_hadAbnormalRequest) ...[
                          Slider(
                            value: _abnormalSeverity, min: 1, max: 5, divisions: 4,
                            activeColor: _getSeverityColor(_abnormalSeverity),
                            onChanged: (val) => setState(() => _abnormalSeverity = val),
                          ),
                        ]
                      ],
                    ),
                  ),

                  _buildSectionHeader("DETAILED FEEDBACK"),
                  TextField(
                    controller: _commentController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: "Why was the rating low or what happened?",
                      filled: true, fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                    ),
                  ),

                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity, height: 55,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D47A1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                      onPressed: _isSubmitting ? null : _submitFeedback,
                      child: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : const Text("SUBMIT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}