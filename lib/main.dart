import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'pages/login_page.dart';
import 'pages/register_page.dart';
import 'pages/identity_verification_page.dart';
import 'pages/car_verification_page.dart';
import 'pages/main_page.dart';
import 'pages/driver_dashboard.dart';
import 'pages/welcomePage.dart';
import 'pages/profile_details_page.dart';
import 'pages/edit_profile_page.dart';
import 'styles/app_theme.dart';
import 'models/user.dart' as model;
import 'pages/message_page.dart';
import 'pages/finance_page.dart';
import 'pages/active_ride_page.dart';
import 'state/driver_state.dart';
import 'pages/reset_password_page.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await supabase.Supabase.initialize(
      url: 'https://vbuptyttwvomexfjkizm.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZidXB0eXR0d3ZvbWV4ZmpraXptIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjcxNDE2NjcsImV4cCI6MjA4MjcxNzY2N30.Qx0WSDPen9Qlmtk8FK48H_GHXPig_-YmGKlSiuNJRLg',
    );

    // 🚀 UNIFIED STREAM LISTENER: Handles Deep Links Globally
    supabase.Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      final event = data.event;
      final session = data.session;

      // 1️⃣ Handle Forgot Password link interception
      if (event == supabase.AuthChangeEvent.passwordRecovery) {
        navigatorKey.currentState?.pushNamed('/reset_password');
      }

      // 2️⃣ Handle Email Signup Link verification confirmation
      else if (event == supabase.AuthChangeEvent.signedIn && session != null) {
        final user = session.user;

        try {
          // Fetch the profile state from your database
          final profileResponse = await supabase.Supabase.instance.client
              .from('users')
              .select()
              .eq('id', user.id)
              .maybeSingle();

          if (profileResponse != null && profileResponse['gmail_confirmation_status'] == false) {
            // Update the verification status inside public schema
            await supabase.Supabase.instance.client
                .from('users')
                .update({'gmail_confirmation_status': true})
                .eq('id', user.id);

            // Construct the clean map data profile payload to push forward
            final Map<String, dynamic> stepArgs = Map<String, dynamic>.from(profileResponse);
            stepArgs['id'] = user.id;

            // Route directly into identity verification forms safely
            navigatorKey.currentState?.pushNamedAndRemoveUntil(
              '/identity_verify',
                  (route) => false,
              arguments: stepArgs,
            );
          }
        } catch (e) {
          debugPrint("⛔ DEEP LINK PROFILE ROUTER ERROR: $e");
        }
      }
    });

    // ⚠️ Force logout for cold-boot persistence memory debugging
    // Remove or comment out this block when deploying to production!
    await supabase.Supabase.instance.client.auth.signOut();

  } catch (e) {
    debugPrint("Supabase Init Error: $e");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'UUM Driver Auth',
      theme: AppTheme.lightTheme,
      initialRoute: '/',
      routes: {
        '/': (context) => const WelcomePage(),
        '/login': (context) => const LoginPage(),
        '/reset_password': (context) => const ResetPasswordPage(),
        '/register': (context) => const RegisterPage(),
        '/finance_page': (context) => const FinancePage(),

        // ------------------------------
        // Identity Verification
        // ------------------------------
        '/identity_verify': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
          return IdentityVerificationPage(userData: args ?? {});
        },

        // ------------------------------
        // Car Verification
        // ------------------------------
        '/car_verify': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
          return CarVerificationPage(userData: args ?? {});
        },

        // ------------------------------
        // EDIT PROFILE
        // ------------------------------
        '/edit_profile': (context) {
          final args = ModalRoute.of(context)!.settings.arguments;
          if (args is model.User) return EditProfilePage(user: args);
          if (args is Map<String, dynamic>) {
            return EditProfilePage(user: model.User.fromMap(args));
          }
          return _errorPage("Edit Profile data missing");
        },

        // ------------------------------
        // MAIN PAGE
        // ------------------------------
        '/main': (context) {
          final args = ModalRoute.of(context)!.settings.arguments;
          if (args is model.User) return MainPage(user: args);
          if (args is Map<String, dynamic>) {
            return MainPage(user: model.User.fromMap(args));
          }
          return _errorPage("Dashboard data missing");
        },

        // ------------------------------
        // MESSAGE PAGE
        // ------------------------------
        '/message_page': (context) {
          final args = ModalRoute.of(context)!.settings.arguments;
          if (args is Map<String, dynamic>) {
            final userData = args['user'];
            final user = userData is model.User
                ? userData
                : model.User.fromMap(userData as Map<String, dynamic>);
            return MessagePage(
              user: user,
              initialActiveRide: args['activeRide'] as Map<String, dynamic>?,
            );
          }
          if (args is model.User) return MessagePage(user: args);
          return _errorPage("Message data incompatible");
        },

        // ------------------------------
        // DYNAMIC ROUTES (Using Arguments)
        // ------------------------------
        '/driver_dashboard': (context) {
          final args = ModalRoute.of(context)!.settings.arguments;

          if (args is Map<String, dynamic>) {
            final userData = args['user'];
            final user = userData is model.User
                ? userData
                : model.User.fromMap(userData as Map<String, dynamic>);

            return DriverDashboard(
              user: user,
              initialActiveRide: args['activeRide'] as Map<String, dynamic>?,
            );
          }

          if (args is model.User) {
            return DriverDashboard(
              user: args,
              initialActiveRide: DriverState.currentRideData,
            );
          }

          return _errorPage("Dashboard data incompatible");
        },

        // ------------------------------
        // PROFILE DETAILS
        // ------------------------------
        '/profile_details': (context) {
          final args = ModalRoute.of(context)!.settings.arguments;
          if (args is model.User) return ProfileDetailsPage(user: args);
          if (args is Map<String, dynamic>) {
            return ProfileDetailsPage(user: model.User.fromMap(args));
          }
          return _errorPage("Profile data missing");
        },

        // ------------------------------
        // ACTIVE RIDE PAGE
        // ------------------------------
        '/active_ride': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;

          if (args is Map) {
            try {
              final rawRideData = args['rideData'];
              final driverData = args['driverUser'];

              if (rawRideData == null || driverData == null) {
                return _errorPage("Missing Required Ride Data");
              }

              final rideData = Map<String, dynamic>.from(rawRideData as Map);
              final status = rideData['status']?.toString().toLowerCase();
              if (status == 'completed' || status == 'cancelled') {
                return _errorPage("This ride has already ended.");
              }

              model.User? driver;
              if (driverData is model.User) {
                driver = driverData;
              } else if (driverData is Map) {
                driver = model.User.fromMap(Map<String, dynamic>.from(driverData));
              }

              return ActiveRidePage(
                rideData: rideData,
                driverUser: driver!,
              );
            } catch (e) {
              debugPrint("⛔ ROUTER ERROR: $e");
              return _errorPage("Data format error");
            }
          }
          return _errorPage("No ride data received");
        },

        '/dashboard': (context) {
          final args = ModalRoute.of(context)!.settings.arguments;
          if (args is model.User) {
            return DriverDashboard(user: args);
          }
          return const LoginPage();
        },
      },
    );
  }
}

Widget _errorPage(String message) {
  return Scaffold(
    body: Center(
      child: Text(
        message,
        style: const TextStyle(fontSize: 18, color: Colors.red),
      ),
    ),
  );
}