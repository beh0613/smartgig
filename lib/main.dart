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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await supabase.Supabase.initialize(
      url: 'https://vbuptyttwvomexfjkizm.supabase.co',
      anonKey:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZidXB0eXR0d3ZvbWV4ZmpraXptIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjcxNDE2NjcsImV4cCI6MjA4MjcxNzY2N30.Qx0WSDPen9Qlmtk8FK48H_GHXPig_-YmGKlSiuNJRLg',
    );
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
      debugShowCheckedModeBanner: false,
      title: 'UUM Driver Auth',
      theme: AppTheme.lightTheme,
      initialRoute: '/',
      routes: {
        '/': (context) => const WelcomePage(),
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegisterPage(),

        // ------------------------------
        // Identity Verification
        // ------------------------------
        '/identity_verify': (context) {
          final args =
          ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
          return IdentityVerificationPage(userData: args ?? {});
        },

        // ------------------------------
        // Car Verification
        // ------------------------------
        '/car_verify': (context) {
          final args =
          ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
          return CarVerificationPage(userData: args ?? {});
        },

        // ------------------------------
// EDIT PROFILE (Fix applied)
// ------------------------------
        '/edit_profile': (context) {
          final args = ModalRoute.of(context)!.settings.arguments;

          if (args is model.User) {
            return EditProfilePage(user: args);
          }

          if (args is Map<String, dynamic>) {
            return EditProfilePage(
              user: model.User.fromMap(args),
            );
          }

          return _errorPage("Edit Profile data missing");
        },

        // ------------------------------
        // MAIN PAGE (Fix applied)
        // ------------------------------
        '/main': (context) {
          final args = ModalRoute.of(context)!.settings.arguments;

          if (args is model.User) {
            return MainPage(user: args);
          }

          if (args is Map<String, dynamic>) {
            return MainPage(user: model.User.fromMap(args));
          }

          return _errorPage("Dashboard data missing");
        },

        '/finance_page': (context) => const FinancePage(),

        // ------------------------------
        // MESSAGE PAGE (Fix applied)
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

          if (args is model.User) {
            return MessagePage(user: args);
          }

          return _errorPage("Message data incompatible");
        },

        // ------------------------------
        // DRIVER DASHBOARD (Fix applied)
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
            return DriverDashboard(user: args);
          }

          return _errorPage("Dashboard data incompatible");
        },

        // ------------------------------
        // PROFILE DETAILS (Fix applied)
        // ------------------------------
        '/profile_details': (context) {
          final args = ModalRoute.of(context)!.settings.arguments;

          if (args is model.User) {
            return ProfileDetailsPage(user: args);
          }

          if (args is Map<String, dynamic>) {
            return ProfileDetailsPage(
              user: model.User.fromMap(args),
            );
          }

          return _errorPage("Profile data missing");
        },

        // ------------------------------
        // ACTIVE RIDE PAGE (Fix applied)
        // ------------------------------
        '/active_ride': (context) {
          final args = ModalRoute.of(context)!.settings.arguments;

          if (args is Map<String, dynamic>) {
            final driverData = args['driverUser'];

            final driver = driverData is model.User
                ? driverData
                : model.User.fromMap(driverData as Map<String, dynamic>);

            return ActiveRidePage(
              rideData: args['rideData'] as Map<String, dynamic>,
              driverUser: driver,
            );
          }

          return _errorPage("Ride data missing");
        },
      },
    );
  }
}

// ------------------------------
// Error page helper
// ------------------------------
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
