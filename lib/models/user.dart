class User {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String address;
  final String age;
  final String gender;
  final String dob;
  final String nric;
  final String password;
   bool riskPreferencesFilled;
  String? profilePicUrl; // ADD THIS LINE

  // Vehicle data
  final String carModel;
  final String carPlate;
  final String carColor;
  final String carYear;


  User({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
    required this.age,
    required this.gender,
    required this.dob,
    required this.nric,
    required this.password,
    required this.carModel,
    required this.carPlate,
    required this.carColor,
    required this.carYear,
    this.riskPreferencesFilled = false,
    this.profilePicUrl,
  });

  /// Factory for safe initialization in UI before data is loaded
  factory User.empty() {
    return User(
      id: '',
      name: '',
      email: '',
      phone: '',
      address: '',
      age: '',
      gender: '',
      dob: '',
      nric: '',
      password: '',
      carModel: '',
      carPlate: '',
      carColor: '',
      carYear: '',
    );
  }

  /// Map Supabase join query results to the User model.
  /// This handles cases where linked tables (vehicles/identities)
  /// are returned as lists by the Supabase PostgREST client.
  factory User.fromMap(Map<String, dynamic> map) {
    final vehicle = (map['vehicles'] as List?)?.isNotEmpty == true
        ? map['vehicles'].first
        : {};
    final identity = (map['identities'] as List?)?.isNotEmpty == true
        ? map['identities'].first
        : {};

    return User(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'] ?? '',
      address: map['address'] ?? '',
      age: map['age']?.toString() ?? '',
      gender: map['gender'] ?? '',
      dob: map['dob'] ?? '',
      nric: identity['nric'] ?? '',
      password: map['password'] ?? '',
      carModel: vehicle['car_model'] ?? '',
      carPlate: vehicle['car_plate'] ?? '',
      carColor: vehicle['car_color'] ?? '',
      carYear: vehicle['car_year']?.toString() ?? '',
      // ADD THIS LINE TO READ FROM SUPABASE
      riskPreferencesFilled: map['risk_preferences_filled'] ?? false,
      profilePicUrl: map['profile_pic_url'],
    );
  }
}
