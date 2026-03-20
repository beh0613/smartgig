// lib/state/driver_state.dart

class DriverState {
  /// Tracks if the driver is currently "On Shift" or "Off Shift"
  /// Used to toggle visibility for passenger ride requests
  static bool isOnline = false;

  /// Holds the active booking data from Supabase
  /// Set this to null when a ride is completed or cancelled
  static Map<String, dynamic>? currentRideData;

  /// Optional: Helper to check if a driver is currently busy
  static bool get isBusy => currentRideData != null;
}