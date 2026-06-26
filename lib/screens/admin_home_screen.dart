import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import 'admin_screen.dart';

class AdminHomeScreen extends StatelessWidget {
  final String uid;
  final UserProfile profile;

  const AdminHomeScreen({super.key, required this.uid, required this.profile});

  @override
  Widget build(BuildContext context) => AdminScreen(uid: uid, profile: profile);
}


