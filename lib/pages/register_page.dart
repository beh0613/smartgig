import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
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

  bool _isLoading = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _passwordsMatch = true;
  String? _error;

  bool _isDialogOpen = false;

  @override
  void dispose() {
    _nameCtr.dispose();
    _emailCtr.dispose();
    _phoneCtr.dispose();
    _addressCtr.dispose();
    _ageCtr.dispose();
    _passCtr.dispose();
    _confirmCtr.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _handleSignUp() async {
    setState(() {
      _error = null;
      _isLoading = true;
    });

    try {
      // 1️⃣ Form Validation Bound Checks
      if (_nameCtr.text.isEmpty ||
          _emailCtr.text.isEmpty ||
          _phoneCtr.text.isEmpty ||
          _selectedDate == null ||
          _passCtr.text.isEmpty) {
        setState(() {
          _error = "Please fill all required fields";
          _isLoading = false;
        });
        return;
      }

      if (!_passwordsMatch) {
        setState(() {
          _error = "Passwords do not match";
          _isLoading = false;
        });
        return;
      }

      // 2️⃣ Register User inside Supabase Auth Engine
      final response = await supabase.Supabase.instance.client.auth.signUp(
        email: _emailCtr.text.trim(),
        password: _passCtr.text,
        emailRedirectTo: 'io.supabase.flutter://login-callback',
      );

      final user = response.user;
      if (user == null) throw Exception("User creation failed");

      // 3️⃣ Upsert Pending Driver Record Payload Immediately
      // Saves state variables safely into database before the user leaves the application to verify email
      await supabase.Supabase.instance.client.from('users').upsert({
        'id': user.id,
        'name': _nameCtr.text.trim(),
        'email': _emailCtr.text.trim(),
        'phone': _phoneCtr.text.trim(),
        'address': _addressCtr.text.trim(),
        'age': int.tryParse(_ageCtr.text),
        'gender': _gender,
        'dob': DateFormat('yyyy-MM-dd').format(_selectedDate!),
        'gmail_confirmation_status': false, // Flipped to true by global stream listener in main.dart upon click
      });

      // 4️⃣ Show User Verification Dialog Prompt
      if (!_isDialogOpen && mounted) {
        _isDialogOpen = true;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text("Confirmation Link Sent"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text("A verification activation path has been pushed to your email inbox. Please view your Gmail on this mobile device and select the confirmation link to begin verification."),
                SizedBox(height: 20),
                CircularProgressIndicator(),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _isDialogOpen = false;
                  Navigator.pushReplacementNamed(context, '/login');
                },
                child: const Text("GO TO LOGIN"),
              )
            ],
          ),
        );
      }
    } on supabase.AuthException catch (e) {
      setState(() { _error = e.message; });
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account - Step 1'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "PERSONAL DETAILS",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Divider(),

            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: CustomTextField(
                    controller: _nameCtr,
                    hint: "Full Name",
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 1,
                  child: CustomTextField(
                    controller: _ageCtr,
                    hint: "Age",
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            CustomTextField(
              controller: _emailCtr,
              hint: "Email Address",
              keyboardType: TextInputType.emailAddress,
            ),

            const SizedBox(height: 12),

            CustomTextField(
              controller: _phoneCtr,
              hint: "Phone Number",
              keyboardType: TextInputType.phone,
            ),

            const SizedBox(height: 12),

            CustomTextField(
              controller: _addressCtr,
              hint: "Home Address",
            ),

            const SizedBox(height: 12),

            const Text("Gender"),
            Row(
              children: [
                Radio(
                  value: 'Male',
                  groupValue: _gender,
                  onChanged: (value) {
                    setState(() { _gender = value!; });
                  },
                ),
                const Text("Male"),
                Radio(
                  value: 'Female',
                  groupValue: _gender,
                  onChanged: (value) {
                    setState(() { _gender = value!; });
                  },
                ),
                const Text("Female"),
              ],
            ),

            const SizedBox(height: 10),

            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListTile(
                title: Text(
                  _selectedDate == null
                      ? "Select Date of Birth"
                      : "DOB: ${DateFormat('yyyy-MM-dd').format(_selectedDate!)}",
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () => _selectDate(context),
              ),
            ),

            const SizedBox(height: 25),

            const Text(
              "SECURITY",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Divider(),

            CustomTextField(
              controller: _passCtr,
              hint: "Password",
              obscure: _obscurePass,
              onChanged: (value) {
                setState(() {
                  _passwordsMatch = _passCtr.text == _confirmCtr.text;
                });
              },
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePass ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () {
                  setState(() { _obscurePass = !_obscurePass; });
                },
              ),
            ),

            const SizedBox(height: 12),

            CustomTextField(
              controller: _confirmCtr,
              hint: "Confirm Password",
              obscure: _obscureConfirm,
              onChanged: (value) {
                setState(() {
                  _passwordsMatch = _passCtr.text == _confirmCtr.text;
                });
              },
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () {
                  setState(() { _obscureConfirm = !_obscureConfirm; });
                },
              ),
            ),

            if (!_passwordsMatch)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  "Passwords do not match",
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ),

            const SizedBox(height: 20),

            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),

            const SizedBox(height: 10),

            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _handleSignUp,
                child: const Text(
                  "NEXT: IDENTITY VERIFICATION",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),

            const SizedBox(height: 10),

            Center(
              child: TextButton(
                onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
                child: const Text("Already have an account? Login here"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}