import 'package:flutter/material.dart';
import '../models/user.dart' as model;

class FinancePage extends StatelessWidget {
  const FinancePage({super.key});

  @override
  Widget build(BuildContext context) {
    // Extract user data from arguments to ensure persistence
    final args = ModalRoute.of(context)?.settings.arguments;
    final model.User user = args is model.User ? args : model.User.empty();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA), // Matches Dashboard background
      body: Stack(
        children: [
          // --- MAIN CONTENT ---
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(25, 80, 25, 120), // Bottom padding for Nav
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    "Finance",
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)
                ),
                const SizedBox(height: 25),

                // Wallet Balance Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(25),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.blue.withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 8)
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                          "Total Balance",
                          style: TextStyle(color: Colors.white70, fontSize: 16)
                      ),
                      const SizedBox(height: 8),
                      const Text(
                          "RM 450.80",
                          style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () {
                          // TODO: Implement Withdrawal Logic
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF0D47A1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text("Withdraw to Bank"),
                      )
                    ],
                  ),
                ),

                const SizedBox(height: 35),
                const Text(
                    "Recent Transactions",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                ),
                const SizedBox(height: 15),

                _buildTransactionTile("Ride Income #882", "Today, 12:40 PM", "+ RM 15.00", Colors.green),
                _buildTransactionTile("Ride Income #881", "Today, 10:20 AM", "+ RM 10.00", Colors.green),
                _buildTransactionTile("Platform Fee", "Yesterday", "- RM 2.00", Colors.red),
                _buildTransactionTile("Ride Income #879", "Yesterday", "+ RM 22.00", Colors.green),
              ],
            ),
          ),

          // --- FLOATING NAVIGATION ---
          Align(
            alignment: Alignment.bottomCenter,
            child: _buildFloatingBottomNav(context, user),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionTile(String title, String time, String amt, Color col) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(time, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              ]
          ),
          Text(
              amt,
              style: TextStyle(color: col, fontWeight: FontWeight.bold, fontSize: 16)
          ),
        ],
      ),
    );
  }
}

// --- NAVIGATION HELPERS ---

Widget _buildFloatingBottomNav(BuildContext context, model.User user) {
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
        _navIcon(
          context,
          Icons.home_outlined,
          "Home",
          false,
              () => Navigator.pushReplacementNamed(context, '/main', arguments: user),
        ),

        // FINANCE (Active)
        _navIcon(
          context,
          Icons.account_balance_wallet_rounded,
          "Finance",
          true,
              () {}, // Already on Finance page
        ),

        _navIcon(
          context,
          Icons.chat_bubble_outline_rounded,
          "Message",
          false,
              () => Navigator.pushReplacementNamed(context, '/message_page', arguments: user),
        ),

        _navIcon(
          context,
          Icons.grid_view_rounded,
          "Dashboard",
          false,
              () => Navigator.pushReplacementNamed(context, '/driver_dashboard', arguments: user),
        ),
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
        Text(
            label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? activeColor : inactiveColor
            )
        ),
      ],
    ),
  );
}