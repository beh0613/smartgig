import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user.dart' as model;
import '../pages/reset_password_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final _emailCtr = TextEditingController();
  final _passCtr = TextEditingController();

  bool _isLoading = false;
  bool _showPassword = false;
  bool _isEmailValid = false;
  bool _obscurePassword = true;

  final Color primaryDark = const Color(0xFF0F172A);
  final Color electricIndigo = const Color(0xFF6366F1);
  final Color softGrey = const Color(0xFF94A3B8);

  late AnimationController _passwordAnimController;
  late Animation<double> _passwordFade;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  late final StreamSubscription<AuthState> _authSubscription; // 1. Define the sub
  @override
  void initState() {
    super.initState();
    _passwordAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _passwordFade = CurvedAnimation(
      parent: _passwordAnimController,
      curve: Curves.easeOutBack,
    );

    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;

      // 🚨 THIS IS THE KEY PART
      if (event == AuthChangeEvent.passwordRecovery) {
        print("DEBUG: Recovery mode detected!");
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ResetPasswordPage()),
          );
        }
      }
    });

    _emailCtr.addListener(() {
      final isValid = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(_emailCtr.text);
      if (isValid != _isEmailValid) setState(() => _isEmailValid = isValid);
    });

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _shakeAnimation = Tween<double>(begin: 0, end: 12).chain(
      CurveTween(curve: Curves.elasticIn),
    ).animate(_shakeController);
  }

  @override
  void dispose() {
    _passwordAnimController.dispose();
    _authSubscription.cancel();
    _shakeController.dispose(); // add this
    _emailCtr.dispose();
    _passCtr.dispose();
    super.dispose();
  }

  void _onContinuePressed() {
    setState(() => _showPassword = true);
    _passwordAnimController.forward();
  }

  Future<void> _handleSecureLogin() async {
    setState(() => _isLoading = true);

    try {
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailCtr.text.trim(),
        password: _passCtr.text.trim(),
      );

      if (res.user != null) {
        // 🚀 FETCH REAL DATA FROM DB
        final response = await Supabase.instance.client
            .from('users')
            .select('''
      *,
      vehicles(*),
      identities(*)
    ''')
            .eq('id', res.user!.id)
            .single();

        final myUser = model.User.fromMap(response);

        if (!mounted) return;

        Navigator.pushNamedAndRemoveUntil(
          context,
          '/driver_dashboard',
              (route) => false,
          arguments: myUser,
        );
      }
    } catch (e) {
      if (mounted) {
        _shakeController.forward(from: 0);

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text("Login Failed"),
            content: const Text(
              "Email or password is incorrect. Please try again.",
            ),
            actions: [
              TextButton(
                child: const Text("OK"),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGmailLogin() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId: '385992390190-kd9ch5n2opoptqs4d6abemml819v8uct.apps.googleusercontent.com',
        scopes: ['email', 'profile'],
      );

      // 🚀 FORCE ABSOLUTE LOGOUT FOR BOTH SERVICES
      await googleSignIn.signOut();
      await Supabase.instance.client.auth.signOut();

      // 🚀 PROMPT USER TO CHOOSE AN ACCOUNT
      final GoogleSignInAccount? gmailUser = await googleSignIn.signIn();

      if (gmailUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication gmailAuth = await gmailUser.authentication;

      // 🚀 AUTHENTICATE WITH THE SPECIFIC SELECTED ACCOUNT DELEGATE
      final AuthResponse res = await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: gmailAuth.idToken!,
        accessToken: gmailAuth.accessToken!,
      );

      if (res.user != null) {
        // FETCH REAL DATA FROM DB
        final response = await Supabase.instance.client
            .from('users')
            .select('*, vehicles(*)')
            .eq('id', res.user!.id)
            .single();

        Map<String, dynamic> userMap = Map<String, dynamic>.from(response);

        if ((userMap['email'] == null || userMap['email'] == '') && res.user?.email != null) {
          userMap['email'] = res.user!.email;

          await Supabase.instance.client
              .from('users')
              .update({'email': res.user!.email})
              .eq('id', res.user!.id);
        }

        final myUser = model.User.fromMap(userMap);
        if (!mounted) return;

        Navigator.pushNamedAndRemoveUntil(
            context,
            '/driver_dashboard',
                (route) => false,
            arguments: myUser
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Login Failed: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailCtr.text.trim();

    if (!_isEmailValid || email.isEmpty) {
      _shakeController.forward(from: 0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter your valid work email first."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      // 💡 Supabase sends the reset link to the user's Gmail
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        // Change 'io.smartgig.app' to your actual app scheme set in Supabase dashboard
        redirectTo: 'io.smartgig.app://reset-password',
      );
      print("Reset call successful");
      if (mounted) {
        _showSuccessDialog(
            "Reset Link Sent",
            "A secure link has been sent to $email. Please check your Gmail inbox to set a new password."
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

// Helper for clean dialogs
  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold))
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          _buildAnimatedBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    _buildEliteLogo(),
                    const SizedBox(height: 16),
                    _buildHeroText(),
                    const SizedBox(height: 48),
                    _buildAuthCard(),
                    const SizedBox(height: 32),
                    _buildFooter(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroText() {
    return Column(
      // Tell the column to shrink-wrap its children
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "SmartGig",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w900,
            color: primaryDark,
            letterSpacing: -1.5,
          ),
        ),
        const SizedBox(height: 4), // Add a tiny gap
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            "The Future of Flexible Work",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: softGrey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAuthCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(35),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(35),
            border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5),
          ),
          child: Column(
            children: [
              _buildGmailButton(),
              const SizedBox(height: 28),
              _buildModernDivider(),
              const SizedBox(height: 28),
              _buildInputField(
                  controller: _emailCtr,
                  hint: "Work Email",
                  icon: Icons.email_outlined,
                  enabled: !_showPassword
              ),
              SizeTransition(
                sizeFactor: _passwordFade,
                child: FadeTransition(
                  opacity: _passwordFade,
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      AnimatedBuilder(
                        animation: _shakeAnimation,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(_shakeAnimation.value, 0),
                            child: child,
                          );
                        },
                        child: _buildInputField(
                          controller: _passCtr,
                          hint: "Security Key",
                          icon: Icons.lock_open_rounded,
                          isPassword: true,
                        ),
                      ),

                      // 🚀 ADDED: Forgot Password Link
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _handleForgotPassword,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            "Forgot Security Key?",
                            style: TextStyle(
                              color: electricIndigo,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24), // Adjusted spacing
              _isLoading
                  ? CircularProgressIndicator(color: electricIndigo)
                  : _buildPrimaryButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGmailButton() {
    return Container(
      // Remove the Row wrapper from line 241 in your build method if this is the only item
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _handleGmailLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: primaryDark,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min, // <--- Add this
          children: [
            Image.asset(
                'assets/gmail.png',
                height: 22
            ),
            const SizedBox(width: 12),
            const Text("Login with Gmail", style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField({required TextEditingController controller, required String hint, required IconData icon, bool isPassword = false, bool enabled = true}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: TextField(
        controller: controller,
        obscureText: isPassword ? _obscurePassword : false,
        enabled: enabled,
        style: const TextStyle(fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: electricIndigo, size: 22),
          hintText: hint,
          hintStyle: TextStyle(color: softGrey, fontSize: 14),

          // 👁 Password toggle button
          suffixIcon: isPassword
              ? IconButton(
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_off
                  : Icons.visibility,
              color: softGrey,
            ),
            onPressed: () {
              setState(() {
                _obscurePassword = !_obscurePassword;
              });
            },
          )
              : null,

          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
        ),
      )
    );
  }

  Widget _buildPrimaryButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      height: 62,
      child: ElevatedButton(
        onPressed: _isEmailValid
            ? (_showPassword ? _handleSecureLogin : _onContinuePressed)
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isEmailValid ? primaryDark : const Color(0xFFCBD5E1),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: _isEmailValid ? 8 : 0,
        ),
        child: Text(
          _showPassword ? "ENTER WORKSPACE" : "CONTINUE",
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedBackground() {
    return Stack(
      children: [
        Positioned(top: -50, left: -50, child: _buildBlurCircle(400, electricIndigo.withOpacity(0.08))),
        Positioned(bottom: 100, right: -100, child: _buildBlurCircle(350, const Color(0xFFF43F5E).withOpacity(0.05))),
      ],
    );
  }

  Widget _buildBlurCircle(double size, Color color) {
    return Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: color));
  }

  Widget _buildModernDivider() {
    return Row(children: [
      Expanded(child: Divider(color: softGrey.withOpacity(0.2))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text("OR SECURE LOGIN", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: softGrey, letterSpacing: 1.5))),
      Expanded(child: Divider(color: softGrey.withOpacity(0.2))),
    ]);
  }

  Widget _buildFooter() {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text("New to the platform?", style: TextStyle(color: softGrey)),
      TextButton(onPressed: () => Navigator.pushNamed(context, '/register'), child: Text("Register", style: TextStyle(color: primaryDark, fontWeight: FontWeight.w900))),
    ]);
  }

  Widget _buildEliteLogo() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: electricIndigo.withOpacity(0.2), width: 2)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: Image.asset('assets/logo.jpg', height: 100, width: 100, fit: BoxFit.cover),
      ),
    );
  }
}