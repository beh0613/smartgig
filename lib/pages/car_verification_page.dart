import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/auth_service.dart';
import '../models/user.dart';

class CarVerificationPage extends StatefulWidget {
  final Map<String, dynamic> userData;
  const CarVerificationPage({super.key, required this.userData});

  @override
  State<CarVerificationPage> createState() => _CarVerificationPageState();
}

class _CarVerificationPageState extends State<CarVerificationPage> {
  final _plateCtr = TextEditingController();
  final _modelCtr = TextEditingController();
  final _colorCtr = TextEditingController();
  final _yearCtr = TextEditingController();

  String? _regFormPath, _roadTaxPath, _insurancePath;
  String? _regFileName, _roadTaxFileName, _insFileName;

  final AuthService _auth = AuthService();
  bool _isLoading = false;

  Future<void> _pickFile(String type) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'png', 'jpeg'],
    );

    if (result != null) {
      setState(() {
        if (type == 'reg') {
          _regFormPath = result.files.single.path;
          _regFileName = result.files.single.name;
        } else if (type == 'tax') {
          _roadTaxPath = result.files.single.path;
          _roadTaxFileName = result.files.single.name;
        } else if (type == 'ins') {
          _insurancePath = result.files.single.path;
          _insFileName = result.files.single.name;
        }
      });
    }
  }

  void _submit() async {
    if (_plateCtr.text.isEmpty ||
        _modelCtr.text.isEmpty ||
        _regFormPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Please provide plate number and upload the Registration Form",
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final result = await _auth.completeRegistration(
      userId: widget.userData['id'],
      userData: widget.userData,
      nric: widget.userData['nric'],
      license: widget.userData['license'],
      icFront: widget.userData['icFront'],
      icBack: widget.userData['icBack'],
      vehicleData: {
        'carModel': _modelCtr.text.trim(),
        'carPlate': _plateCtr.text.trim(),
        'carColor': _colorCtr.text.trim(),
        'carYear': _yearCtr.text.trim(),
      },
      regForm: _regFormPath,
      roadTax: _roadTaxPath,
      insurance: _insurancePath,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result == null) {
      _showSuccessDialog();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $result"), backgroundColor: Colors.red),
      );
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Icon(Icons.check_circle, color: Colors.green, size: 50),
        content: const Text(
          "Registration complete! Our team will verify your documents within 24 hours.",
          textAlign: TextAlign.center,
        ),
        actions: [
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[900],
              ),
              onPressed: () => Navigator.pushNamedAndRemoveUntil(
                context,
                '/login',
                (r) => false,
              ),
              child: const Text(
                "BACK TO LOGIN",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // Check if we are in update mode
    if (widget.userData['isUpdate'] == true) {
      final User existingUser = widget.userData['user_object'];
      _plateCtr.text = existingUser.carPlate;
      _modelCtr.text = existingUser.carModel;
      _colorCtr.text = existingUser.carColor;
      _yearCtr.text = existingUser.carYear;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      appBar: AppBar(
        title: const Text(
          "Final Step",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStepper(),
                const SizedBox(height: 30),

                _sectionLabel("Vehicle Specifications"),
                _buildTextField(
                  _modelCtr,
                  "Car Model (e.g., Myvi 1.5)",
                  Icons.directions_car,
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(_plateCtr, "Plate No", Icons.tag),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: _buildTextField(
                        _yearCtr,
                        "Year",
                        Icons.event,
                        isNumeric: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                _buildTextField(_colorCtr, "Body Color", Icons.palette),

                const SizedBox(height: 35),

                _sectionLabel("Official Documents (PDF/JPG)"),
                _buildUploadCard(
                  "Registration Form (VOC)",
                  _regFileName,
                  () => _pickFile('reg'),
                ),
                _buildUploadCard(
                  "Road Tax Sticker",
                  _roadTaxFileName,
                  () => _pickFile('tax'),
                ),
                _buildUploadCard(
                  "Insurance Cover Note",
                  _insFileName,
                  () => _pickFile('ins'),
                ),

                const SizedBox(height: 40),
                _buildSubmitButton(),
                const SizedBox(height: 20),
              ],
            ),
          ),
          if (_isLoading) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  // --- UI COMPONENTS ---

  Widget _buildStepper() {
    return Row(
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: Colors.blue[900],
          child: const Icon(Icons.check, size: 16, color: Colors.white),
        ),
        Expanded(child: Container(height: 2, color: Colors.blue[900])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.blue[900]!),
          ),
          child: Text(
            "STEP 2 OF 2",
            style: TextStyle(
              color: Colors.blue[900],
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
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

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool isNumeric = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.blue[900], size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildUploadCard(String title, String? fileName, VoidCallback onTap) {
    bool hasFile = fileName != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: hasFile ? Colors.green.withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: hasFile ? Colors.green : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            Icon(
              hasFile ? Icons.check_circle : Icons.upload_file,
              color: hasFile ? Colors.green : Colors.blueGrey,
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    hasFile ? fileName : "Tap to upload",
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue[900],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          elevation: 4,
        ),
        onPressed: _submit,
        child: const Text(
          "SUBMIT VERIFICATION",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.blue[900]),
              const SizedBox(height: 20),
              const Text(
                "Processing Application...",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
