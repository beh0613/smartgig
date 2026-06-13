import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p; // Add path: ^1.8.3 to pubspec.yaml
import 'car_verification_page.dart';

class IdentityVerificationPage extends StatefulWidget {
  final Map<String, dynamic> userData;
  const IdentityVerificationPage({super.key, required this.userData});

  @override
  State<IdentityVerificationPage> createState() =>
      _IdentityVerificationPageState();
}

class _IdentityVerificationPageState extends State<IdentityVerificationPage> {
  final _nricCtr = TextEditingController();

  // Paths for new files picked
  String? _icFrontPath, _icBackPath, _licensePath;

  // Display names (Existing URLs or new file names)
  String? _icFrontName, _icBackName, _licenseName;

  @override
  void initState() {
    super.initState();
    _loadExistingUserData();
  }

  /// Extracts existing data from the userData map passed from the Dashboard
  void _loadExistingUserData() {
    if (widget.userData.isEmpty) return;

    setState(() {
      // 1. Retrieve NRIC
      if (widget.userData['nric'] != null) {
        _nricCtr.text = widget.userData['nric'].toString();
      }

      // 2. Retrieve existing document filenames
      // We extract the filename from the URL or Path for a cleaner UI
      if (widget.userData['icFront'] != null) {
        _icFrontName = _formatFileName(widget.userData['icFront']);
      }
      if (widget.userData['icBack'] != null) {
        _icBackName = _formatFileName(widget.userData['icBack']);
      }
      if (widget.userData['license'] != null) {
        _licenseName = _formatFileName(widget.userData['license']);
      }
    });
  }

  /// Helper to clean up long URLs/Paths into short filenames
  String _formatFileName(String path) {
    String name = p.basename(path).split('?').first;
    // If it's a long Supabase URL, we show a friendly label
    return name.length > 25 ? "Existing_Document.pdf" : name;
  }

  Future<void> _pickFile(String type) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        if (type == 'front') {
          _icFrontPath = result.files.single.path;
          _icFrontName = result.files.single.name;
        } else if (type == 'back') {
          _icBackPath = result.files.single.path;
          _icBackName = result.files.single.name;
        } else if (type == 'license') {
          _licensePath = result.files.single.path;
          _licenseName = result.files.single.name;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      appBar: AppBar(
        title: const Text(
          "Identity Verification",
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
            _buildStepper(),
            const SizedBox(height: 30),

            _sectionLabel("Official Identification"),
            _buildNRICField(),

            const SizedBox(height: 35),

            _sectionLabel("Required Documents"),
            _buildDocumentCard(
              "IC Front View",
              _icFrontName,
              Icons.contact_mail_outlined,
              () => _pickFile('front'),
            ),
            _buildDocumentCard(
              "IC Back View",
              _icBackName,
              Icons.badge_outlined,
              () => _pickFile('back'),
            ),
            _buildDocumentCard(
              "Driving License",
              _licenseName,
              Icons.assignment_ind_outlined,
              () => _pickFile('license'),
            ),

            const SizedBox(height: 40),
            _buildNextButton(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // --- UI COMPONENTS ---

  Widget _buildStepper() {
    bool isUpdate = widget.userData['id'] != null;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.blue[900],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            isUpdate ? "EDIT MODE" : "STEP 1 OF 2",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(child: Container(height: 2, color: Colors.grey[300])),
        CircleAvatar(
          radius: 12,
          backgroundColor: Colors.grey[300],
          child: const Icon(Icons.check, size: 12, color: Colors.white),
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
          fontWeight: FontWeight.w800,
          color: Colors.blueGrey[400],
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildNRICField() {
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
        controller: _nricCtr,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: "NRIC Number",
          prefixIcon: Icon(Icons.credit_card_rounded, color: Colors.blue[900]),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
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
    bool hasFile = fileName != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: hasFile ? Colors.green.withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: hasFile ? Colors.green : Colors.grey.shade200,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: hasFile ? Colors.green[100] : Colors.blue[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                hasFile ? Icons.check_circle_rounded : icon,
                color: hasFile ? Colors.green[700] : Colors.blue[900],
              ),
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
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    hasFile ? fileName : "Tap to upload (PDF/JPG/PNG)",
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              hasFile ? Icons.edit_document : Icons.add_a_photo_outlined,
              size: 20,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNextButton() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue[900],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          elevation: 5,
        ),
        onPressed: _handleNext,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "CONTINUE TO VEHICLE",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            SizedBox(width: 10),
            Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }

  void _handleNext() {
    if (_nricCtr.text.isEmpty ||
        _icFrontName == null ||
        _icBackName == null ||
        _licenseName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("All NRIC and documents are required"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // 🚀 Keep everything from before, ensuring 'id' stays intact
    Map<String, dynamic> updatedData = Map<String, dynamic>.from(widget.userData);

    updatedData.addAll({
      'nric': _nricCtr.text.trim(),
    });

    if (_icFrontPath != null) updatedData['icFront'] = _icFrontPath;
    if (_icBackPath != null) updatedData['icBack'] = _icBackPath;
    if (_licensePath != null) updatedData['license'] = _licensePath;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CarVerificationPage(userData: updatedData),
      ),
    );
  }
}
