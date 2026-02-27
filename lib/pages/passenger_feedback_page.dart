import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user.dart' as model;

class PassengerFeedbackPage extends StatefulWidget {
  final String bookingId;
  final String passengerId;
  final String passengerName;
  final model.User driverUser;

  const PassengerFeedbackPage({
    super.key,
    required this.bookingId,
    required this.passengerId,
    required this.passengerName,
    required this.driverUser,
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

  // --- UPDATED SUBMIT LOGIC WITH DEBUGGING ---
  Future<void> _submitFeedback() async {
    final String comment = _commentController.text.trim();

    debugPrint("🚀 SUBMISSION STARTED");
    debugPrint("⭐ Rating: $_rating");
    debugPrint("⚠️ Abnormal: $_hadAbnormalRequest");

    // 1. VALIDATION CHECK
    if (_rating < 3 && !_hadAbnormalRequest && comment.isEmpty) {
      debugPrint("❌ VALIDATION FAILED: Low rating requires comment");
      _showCustomAlert("Comment Required", "Please explain why the rating is low.");
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final selectedTags = _attitudeTags.entries.where((e) => e.value).map((e) => e.key).toList();

      final payload = {
        'booking_id': widget.bookingId,
        'passenger_id': widget.passengerId,
        'driver_id': widget.driverUser.id,
        'rating': _rating.toInt(), // <--- Add .toInt() here
        'abnormal_request': _hadAbnormalRequest,
        'abnormal_severity': _hadAbnormalRequest ? _abnormalSeverity.toInt() : 0, // <--- Add .toInt() here
        'attitude_tags': selectedTags,
        'comment': comment,
        'created_at': DateTime.now().toIso8601String(),
      };

      debugPrint("📤 SENDING PAYLOAD: $payload");

      final response = await _supabase.from('passenger_feedback').insert(payload).select();

      debugPrint("✅ SUCCESS: $response");

      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/driver_dashboard', (route) => false, arguments: widget.driverUser);
      }
    } catch (e) {
      debugPrint("🚨 SUPABASE ERROR: $e");
      _showCustomAlert("Database Error", e.toString());
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
      appBar: AppBar(elevation: 0, backgroundColor: Colors.white, foregroundColor: Colors.black87, title: const Text("Trip Summary")),
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