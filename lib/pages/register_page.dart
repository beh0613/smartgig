import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    as supabase; // Prefix to avoid conflict with project User model
import '../widgets/custom_textfield.dart';
import 'package:intl/intl.dart';
import 'identity_verification_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _nameCtr = TextEditingController();
  final _emailCtr = TextEditingController();
  final _phoneCtr = TextEditingController();
  final _addressCtr = TextEditingController();
  final _ageCtr = TextEditingController();
  final _passCtr = TextEditingController();
  final _confirmCtr = TextEditingController();

  String _gender = 'Male';
  DateTime? _selectedDate;
  String? _error;
  bool _isLoading = false;

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _handleSignUp() async {
    setState(() => _error = null);

    // 1. Validation Logic
    if (_nameCtr.text.isEmpty ||
        _emailCtr.text.isEmpty ||
        _phoneCtr.text.isEmpty ||
        _selectedDate == null ||
        _passCtr.text.isEmpty) {
      setState(() => _error = 'Please fill all fields and select DOB');
      return;
    }

    if (_passCtr.text != _confirmCtr.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 2. Register in Supabase Auth
      // Because Option B is chosen (Confirm Email OFF), this returns a user AND session immediately
      final response = await supabase.Supabase.instance.client.auth.signUp(
        email: _emailCtr.text.trim(),
        password: _passCtr.text,
      );

      final String? userId = response.user?.id;

      if (userId != null) {
        // 3. Bundle user data to pass to the next page
        Map<String, dynamic> tempUserData = {
          'id': userId,
          'name': _nameCtr.text.trim(),
          'email': _emailCtr.text.trim(),
          'phone': _phoneCtr.text.trim(),
          'address': _addressCtr.text.trim(),
          'age': _ageCtr.text.trim(),
          'gender': _gender,
          'dob': DateFormat('yyyy-MM-dd').format(_selectedDate!),
          'password': _passCtr.text,
        };

        if (!mounted) return;

        // 4. Navigate to Identity Verification Page immediately
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                IdentityVerificationPage(userData: tempUserData),
          ),
        );

        // 5. User Feedback
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Account created! Let's verify your documents."),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } on supabase.AuthException catch (e) {
      // Handle "User already exists" (422) or other auth errors
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = "An unexpected error occurred.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // UI code remains the same as your provided version
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account - Step 1'),
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "PERSONAL DETAILS",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const Divider(),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: CustomTextField(
                    controller: _nameCtr,
                    hint: 'Full Name',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 1,
                  child: CustomTextField(
                    controller: _ageCtr,
                    hint: 'Age',
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            CustomTextField(
              controller: _emailCtr,
              hint: 'Email Address',
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            CustomTextField(
              controller: _phoneCtr,
              hint: 'Phone Number (e.g. 0123456789)',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            CustomTextField(controller: _addressCtr, hint: 'Home Address'),
            const SizedBox(height: 12),
            const Text("Gender", style: TextStyle(fontWeight: FontWeight.w500)),
            Row(
              children: [
                Radio<String>(
                  value: 'Male',
                  groupValue: _gender,
                  onChanged: (v) => setState(() => _gender = v!),
                ),
                const Text("Male"),
                const SizedBox(width: 20),
                Radio<String>(
                  value: 'Female',
                  groupValue: _gender,
                  onChanged: (v) => setState(() => _gender = v!),
                ),
                const Text("Female"),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListTile(
                title: Text(
                  _selectedDate == null
                      ? 'Select Date of Birth'
                      : 'DOB: ${DateFormat('yyyy-MM-dd').format(_selectedDate!)}',
                  style: TextStyle(
                    color: _selectedDate == null
                        ? Colors.grey[600]
                        : Colors.black,
                  ),
                ),
                trailing: const Icon(Icons.calendar_today, color: Colors.blue),
                onTap: () => _selectDate(context),
              ),
            ),
            const SizedBox(height: 25),
            const Text(
              "SECURITY",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const Divider(),
            const SizedBox(height: 10),
            CustomTextField(
              controller: _passCtr,
              hint: 'Password',
              obscure: true,
            ),
            const SizedBox(height: 12),
            CustomTextField(
              controller: _confirmCtr,
              hint: 'Confirm Password',
              obscure: true,
            ),
            const SizedBox(height: 20),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 15),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A8A),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _handleSignUp,
                      child: const Text(
                        'NEXT: IDENTITY VERIFICATION',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
            const SizedBox(height: 15),
            Center(
              child: TextButton(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/login'),
                child: const Text('Already have an account? Login here'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
