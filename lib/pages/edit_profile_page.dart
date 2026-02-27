import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

class EditProfilePage extends StatefulWidget {
  final User user;
  const EditProfilePage({super.key, required this.user});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final AuthService _auth = AuthService();
  bool _isSaving = false;
  bool _isIdentityUnlocked = false;

  // Controllers
  late TextEditingController _nameCtr;
  late TextEditingController _phoneCtr;
  late TextEditingController _addressCtr;
  late TextEditingController _nricCtr;

  // Document Paths
  String? _icFront, _icBack, _license;
  String? _icFrontName, _icBackName, _licenseName;

  @override
  void initState() {
    super.initState();
    _nameCtr = TextEditingController(text: widget.user.name);
    _phoneCtr = TextEditingController(text: widget.user.phone);
    _addressCtr = TextEditingController(text: widget.user.address);
    _nricCtr = TextEditingController(text: widget.user.nric);
  }

  String _maskNRIC(String nric) {
    if (nric.length < 6) return nric;
    return nric.replaceRange(nric.length - 6, nric.length, "******");
  }

  Future<void> _pickFile(String type) async {
    if (!_isIdentityUnlocked) return;

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        if (type == 'front') {
          _icFront = result.files.single.path;
          _icFrontName = result.files.single.name;
        } else if (type == 'back') {
          _icBack = result.files.single.path;
          _icBackName = result.files.single.name;
        } else if (type == 'license') {
          _license = result.files.single.path;
          _licenseName = result.files.single.name;
        }
      });
    }
  }

  void _showPasswordDialog() {
    final passwordCtr = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Security Verification"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Please enter your password to edit Identity Documents.",
            ),
            const SizedBox(height: 15),
            TextField(
              controller: passwordCtr,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Password",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              // Note: You should call a method in AuthService to verify the password
              bool isValid = await _auth.verifyPassword(passwordCtr.text);
              if (isValid) {
                setState(() => _isIdentityUnlocked = true);
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Incorrect Password"),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text("Verify"),
          ),
        ],
      ),
    );
  }

  Future<void> _handleUpdate() async {
    setState(() => _isSaving = true);

    Map<String, dynamic> updateData = {
      'name': _nameCtr.text.trim(),
      'phone': _phoneCtr.text.trim(),
      'address': _addressCtr.text.trim(),
    };

    if (_isIdentityUnlocked) {
      updateData.addAll({
        'nric': _nricCtr.text.trim(),
        // Add logic in AuthService to handle these file paths for storage upload
        'icFront': _icFront,
        'icBack': _icBack,
        'license': _license,
      });
    }

    final error = await _auth.updateUserDetails(
      userId: widget.user.id,
      updateData: updateData,
    );

    setState(() => _isSaving = false);

    if (error == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Profile updated!")));
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $error")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      appBar: AppBar(
        title: const Text(
          "Edit Profile",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel("Basic Information"),
            _buildInputCard("Full Name", _nameCtr, Icons.person_outline),
            const SizedBox(height: 15),
            _buildInputCard(
              "Phone Number",
              _phoneCtr,
              Icons.phone_android_outlined,
            ),
            const SizedBox(height: 15),
            _buildInputCard(
              "Home Address",
              _addressCtr,
              Icons.location_on_outlined,
              maxLines: 2,
            ),

            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _sectionLabel("Identity Verification"),
                if (!_isIdentityUnlocked)
                  TextButton.icon(
                    onPressed: _showPasswordDialog,
                    icon: const Icon(Icons.lock_open, size: 16),
                    label: const Text("Unlock to Edit"),
                  ),
              ],
            ),

            _buildNRICField(),

            const SizedBox(height: 20),
            _sectionLabel("Legal Documents"),
            _buildDocumentCard(
              "IC Front",
              _icFrontName ?? "Original File Stored",
              Icons.contact_mail_outlined,
              () => _pickFile('front'),
            ),
            _buildDocumentCard(
              "IC Back",
              _icBackName ?? "Original File Stored",
              Icons.badge_outlined,
              () => _pickFile('back'),
            ),
            _buildDocumentCard(
              "License",
              _licenseName ?? "Original File Stored",
              Icons.assignment_ind_outlined,
              () => _pickFile('license'),
            ),

            const SizedBox(height: 40),
            _isSaving
                ? const Center(child: CircularProgressIndicator())
                : _buildSaveButton(),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.blueGrey[400],
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildNRICField() {
    return Opacity(
      opacity: _isIdentityUnlocked ? 1.0 : 0.6,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Icon(Icons.credit_card, color: Colors.blue[900]),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "NRIC Number",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  _isIdentityUnlocked
                      ? TextField(
                          controller: _nricCtr,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        )
                      : Text(
                          _maskNRIC(widget.user.nric),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ],
              ),
            ),
            if (!_isIdentityUnlocked)
              const Icon(Icons.lock, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildInputCard(
    String label,
    TextEditingController controller,
    IconData icon, {
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.blue[900]),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }

  Widget _buildDocumentCard(
    String title,
    String? fileName,
    IconData icon,
    VoidCallback onTap,
  ) {
    bool isEnabled = _isIdentityUnlocked;
    return Opacity(
      opacity: isEnabled ? 1.0 : 0.5,
      child: GestureDetector(
        onTap: isEnabled ? onTap : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: fileName!.contains("Original")
                  ? Colors.grey.shade200
                  : Colors.green,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.blue[900]),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      fileName,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.cloud_upload_outlined, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue[900],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        onPressed: _handleUpdate,
        child: const Text(
          "SAVE CHANGES",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
