import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user.dart' as model;

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Helper method for file uploads
  /// Now includes logic to check if the file is already a URL
  Future<String?> _uploadFile(
    String localPath,
    String userId,
    String folder,
  ) async {
    if (localPath.isEmpty) return null;

    // If the path already starts with 'http', it's already uploaded. Return as is.
    if (localPath.startsWith('http')) return localPath;

    try {
      final file = File(localPath);
      final fileExt = localPath.split('.').last;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final path = '$userId/$folder/$fileName';

      await _supabase.storage
          .from('documents')
          .upload(
            path,
            file,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
          );

      return _supabase.storage.from('documents').getPublicUrl(path);
    } catch (e) {
      print("DEBUG: Upload Error ($folder): $e");
      return null;
    }
  }

  /// Verifies if the provided password is correct for the current user
  Future<bool> verifyPassword(String password) async {
    try {
      final email = _supabase.auth.currentUser?.email;
      if (email == null) return false;

      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return response.session != null;
    } catch (e) {
      return false;
    }
  }

  /// Handles multi-table updates for Personal Info and Identity
  Future<String?> updateUserDetails({
    required String userId,
    required Map<String, dynamic> updateData,
  }) async {
    try {
      // 1. Separate data for different tables
      final userData = {
        if (updateData.containsKey('name')) 'name': updateData['name'],
        if (updateData.containsKey('phone')) 'phone': updateData['phone'],
        if (updateData.containsKey('address')) 'address': updateData['address'],
      };

      final identityData = {
        if (updateData.containsKey('nric')) 'nric': updateData['nric'],
      };

      // 2. Handle File Uploads for Identity if present
      if (updateData.containsKey('icFront')) {
        identityData['ic_front_path'] = await _uploadFile(
          updateData['icFront'],
          userId,
          'identity',
        );
      }
      if (updateData.containsKey('icBack')) {
        identityData['ic_back_path'] = await _uploadFile(
          updateData['icBack'],
          userId,
          'identity',
        );
      }
      if (updateData.containsKey('license')) {
        identityData['license_path'] = await _uploadFile(
          updateData['license'],
          userId,
          'identity',
        );
      }

      // 3. Execute Updates
      if (userData.isNotEmpty) {
        await _supabase.from('users').update(userData).eq('id', userId);
      }

      if (identityData.isNotEmpty) {
        await _supabase
            .from('identities')
            .update(identityData)
            .eq('user_id', userId);
      }

      return null; // Success
    } catch (e) {
      print("DEBUG: Update Error: $e");
      return e.toString();
    }
  }

  /// Handles Vehicle Updates
  Future<String?> updateVehicleDetails({
    required String userId,
    required Map<String, dynamic> vehicleData,
  }) async {
    try {
      final dataToUpdate = {
        'car_model': vehicleData['carModel'],
        'car_plate': vehicleData['carPlate'],
        'car_color': vehicleData['carColor'],
        'car_year': int.tryParse(vehicleData['carYear'].toString()),
      };

      // Handle Vehicle File Uploads (Optional updates)
      if (vehicleData.containsKey('regForm')) {
        dataToUpdate['reg_form_path'] = await _uploadFile(
          vehicleData['regForm'],
          userId,
          'vehicle',
        );
      }
      // ... Repeat for roadTax and insurance if you add them to the edit form

      await _supabase
          .from('vehicles')
          .update(dataToUpdate)
          .eq('user_id', userId);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // --- Keep your existing completeRegistration and login methods below ---

  Future<String?> completeRegistration({
    required String userId,
    required Map<String, dynamic> userData,
    required String nric,
    required Map<String, dynamic> vehicleData,
    String? icFront,
    String? icBack,
    String? license,
    String? regForm,
    String? roadTax,
    String? insurance,
  }) async {
    try {
      String? icFrontUrl = await _uploadFile(icFront ?? '', userId, 'identity');
      String? icBackUrl = await _uploadFile(icBack ?? '', userId, 'identity');
      String? licenseUrl = await _uploadFile(license ?? '', userId, 'identity');
      String? regUrl = await _uploadFile(regForm ?? '', userId, 'vehicle');
      String? taxUrl = await _uploadFile(roadTax ?? '', userId, 'vehicle');
      String? insUrl = await _uploadFile(insurance ?? '', userId, 'vehicle');

      await _supabase.from('users').insert({
        'id': userId,
        'name': userData['name'],
        'email': userData['email'],
        'phone': userData['phone'],
        'address': userData['address'],
        'age': int.tryParse(userData['age'].toString()),
        'gender': userData['gender'],
        'dob': userData['dob'],
        'created_at': DateTime.now().toIso8601String(),
        'password': userData['password'],
      });

      await _supabase.from('identities').insert({
        'user_id': userId,
        'nric': nric,
        'ic_front_path': icFrontUrl,
        'ic_back_path': icBackUrl,
        'license_path': licenseUrl,
      });

      await _supabase.from('vehicles').insert({
        'user_id': userId,
        'car_model': vehicleData['carModel'],
        'car_plate': vehicleData['carPlate'],
        'car_color': vehicleData['carColor'],
        'car_year': int.tryParse(vehicleData['carYear'].toString()),
        'reg_form_path': regUrl,
        'road_tax_path': taxUrl,
        'insurance_path': insUrl,
      });

      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<model.User?> login(String email, String password) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final String? userId = response.user?.id;
      if (userId != null) {
        final data = await _supabase
            .from('users')
            .select('*, vehicles (*), identities (*)')
            .eq('id', userId)
            .single();
        return model.User.fromMap(data);
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
