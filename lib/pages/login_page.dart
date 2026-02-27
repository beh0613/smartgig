import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../pages/driver_dashboard.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtr = TextEditingController();
  final _passCtr = TextEditingController();
  final AuthService _auth = AuthService();

  bool _isLoading = false;
  String? _errorMessage;
  bool _isPasswordVisible = false;

  // SmartGig Professional Palette
  final Color navyDeep = const Color(0xFF0F172A); // Slate 900
  final Color indigoAccent = const Color(0xFF6366F1); // Indigo 500
  final Color surfaceLight = const Color(0xFFF8FAFC); // Slate 50

  @override
  void dispose() {
    _emailCtr.dispose();
    _passCtr.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    final email = _emailCtr.text.trim();
    final password = _passCtr.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Email and password are required');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await _auth.login(email, password);
      if (user != null) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => DriverDashboard(user: user)),
        );
      } else {
        setState(() => _errorMessage = 'Invalid credentials. Please try again.');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Authentication server unreachable.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: surfaceLight,
      body: SingleChildScrollView( // Parent scroll prevents "half-blank" ghost space
        child: Column(
          children: [
            // 1. Rebranded Header with Gradient
            Container(
              height: MediaQuery.of(context).size.height * 0.4,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [navyDeep, indigoAccent],
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(
                        Icons.shield_rounded,
                        size: 55,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "SMARTGIG",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.5,
                      ),
                    ),
                    const Text(
                      "LOCATION-AWARE TRUST SYSTEM",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 2. The Overlapping Login Card (Uses Transform to overlap smoothly)
            Transform.translate(
              offset: const Offset(0, -40),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 25,
                      offset: const Offset(0, 12),
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Authenticate",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Enter your credentials to access the trust engine.",
                      style: TextStyle(color: Colors.blueGrey, fontSize: 13),
                    ),
                    const SizedBox(height: 35),

                    // Email Input
                    _buildLabel("Email Address"),
                    _buildTextField(
                      controller: _emailCtr,
                      hint: "e.g., driver@smartgig.io",
                      icon: Icons.alternate_email_rounded,
                    ),

                    const SizedBox(height: 24),

                    // Password Input
                    _buildLabel("Security Password"),
                    _buildTextField(
                      controller: _passCtr,
                      hint: "••••••••",
                      icon: Icons.lock_outline_rounded,
                      isPassword: true,
                    ),

                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                        ),
                      ),

                    const SizedBox(height: 40),

                    // Action Button
                    _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: ElevatedButton(
                        onPressed: _handleLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: navyDeep,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          "SIGN IN",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 30),

                    // Footer Link
                    Center(
                      child: GestureDetector(
                        onTap: () => Navigator.pushReplacementNamed(context, '/register'),
                        child: RichText(
                          text: TextSpan(
                            text: "New to SmartGig? ",
                            style: const TextStyle(color: Colors.grey, fontSize: 14),
                            children: [
                              TextSpan(
                                text: "Create Account",
                                style: TextStyle(
                                  color: indigoAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Bottom spacing to prevent sticking to the edge
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword && !_isPasswordVisible,
      decoration: InputDecoration(
        filled: true,
        fillColor: surfaceLight,
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
        prefixIcon: Icon(icon, color: indigoAccent, size: 20),
        suffixIcon: isPassword
            ? IconButton(
          icon: Icon(
            _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
            size: 18,
            color: Colors.grey,
          ),
          onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
        )
            : null,
        contentPadding: const EdgeInsets.symmetric(vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: indigoAccent.withOpacity(0.5), width: 1.5),
        ),
      ),
    );
  }
}