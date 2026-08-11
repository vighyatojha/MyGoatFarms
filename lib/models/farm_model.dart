import 'package:cloud_firestore/cloud_firestore.dart';

class FarmModel {
  final String id;
  final String farmName;
  final String ownerName;
  final String mobileNumber;
  final String email;
  final String address;
  final String logoUrl;
  final String authUid;

  FarmModel({
    required this.id,
    required this.farmName,
    required this.ownerName,
    required this.mobileNumber,
    required this.email,
    required this.address,
    required this.logoUrl,
    required this.authUid,
  });

  factory FarmModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return FarmModel(
      id: doc.id,
      farmName: data['farmName'] ?? '',
      ownerName: data['ownerName'] ?? '',
      mobileNumber: data['mobileNumber'] ?? '',
      email: data['email'] ?? '',
      address: data['address'] ?? '',
      logoUrl: data['logoUrl'] ?? '',
      authUid: data['authUid'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'farmName': farmName,
      'ownerName': ownerName,
      'mobileNumber': mobileNumber,
      'email': email,
      'address': address,
      'logoUrl': logoUrl,
      'authUid': authUid,
    };
  }
}
