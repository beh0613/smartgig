import 'package:flutter/material.dart';
import '../models/user.dart';

class ProfileDetailsPage extends StatelessWidget {
  final User user;

  const ProfileDetailsPage({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      appBar: AppBar(
        title: const Text(
          "Profile Details",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
        child: Column(
          children: [
            _buildProfileHero(),
            const SizedBox(height: 30),

            // --- SAFETY PREFERENCES ---
            _sectionHeader("Safety Preferences"),
            _buildInfoGroup([
              _preferenceRow(
                Icons.gpp_maybe_outlined,
                "Trust Risk Indicator",
                "Receive alerts based on passenger safety scores",
                true, // This would ideally come from user.trustRiskIndicator
              ),
            ]),

            const SizedBox(height: 25),

            // --- PERSONAL INFO ---
            _sectionHeader("Personal Information"),
            _buildInfoGroup([
              _infoRow(Icons.person_outline_rounded, "Full Name", user.name),
              _infoRow(Icons.email_outlined, "Email Address", user.email),
              _infoRow(Icons.phone_iphone_rounded, "Phone Number", user.phone),
              _infoRow(Icons.location_on_outlined, "Address", user.address),
              _infoRow(
                Icons.cake_outlined,
                "Age / Gender",
                "${user.age} / ${user.gender}",
              ),
            ]),

            const SizedBox(height: 25),

            _sectionHeader("Identity & Legal"),
            _buildInfoGroup([
              _infoRow(Icons.badge_outlined, "NRIC Number", user.nric),
            ]),

            const SizedBox(height: 25),

            _sectionHeader("Vehicle Information"),
            _buildInfoGroup([
              _infoRow(
                Icons.directions_car_filled_outlined,
                "Model",
                user.carModel,
              ),
              _infoRow(Icons.pin_outlined, "Plate Number", user.carPlate),
              _infoRow(Icons.palette_outlined, "Colour", user.carColor),
              _infoRow(
                Icons.event_note_outlined,
                "Manufacturing Year",
                user.carYear,
              ),
            ]),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // --- 1. PROFILE HERO ---
  Widget _buildProfileHero() {
    return Center(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.blue.shade900, width: 2),
            ),
            child: CircleAvatar(
              radius: 50,
              backgroundColor: Colors.blue[900],
              child: Text(
                user.name.isNotEmpty ? user.name.substring(0, 1).toUpperCase() : "?",
                style: const TextStyle(
                  fontSize: 40,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 15),
          Text(
            user.name,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              "VERIFIED DRIVER",
              style: TextStyle(
                color: Colors.green[700],
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- 2. INFO GROUPING ---
  Widget _buildInfoGroup(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  // Row for Safety Preferences (Toggle style)
  Widget _preferenceRow(IconData icon, String title, String subtitle, bool value) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue[800], size: 24),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeColor: Colors.blue[900],
            onChanged: (bool newValue) {
              // Note: To make this interactive, convert this class to StatefulWidget
              // and update the Supabase user profile here.
            },
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.blueGrey[400], size: 22),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- 3. UI HELPERS ---
  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 5, bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Colors.blueGrey[300],
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}