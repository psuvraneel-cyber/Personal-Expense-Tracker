import 'package:flutter/material.dart';
import 'package:pet/premium/models/family_member.dart';
import 'package:pet/premium/repositories/family_repository.dart';
import 'package:uuid/uuid.dart';

class FamilyProvider extends ChangeNotifier {
  final FamilyRepository _repository = FamilyRepository();
  final Uuid _uuid = const Uuid();

  List<FamilyMember> _members = [];
  bool _isLoading = false;

  List<FamilyMember> get members => _members;
  bool get isLoading => _isLoading;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    _members = await _repository.getAll();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> addMember({required String name, double? monthlyLimit}) async {
    final member = FamilyMember(
      id: _uuid.v4(),
      name: name,
      role: 'member',
      monthlyLimit: monthlyLimit,
    );
    await _repository.upsert(member);
    _members.add(member);
    notifyListeners();
  }

  Future<void> removeMember(String id) async {
    await _repository.delete(id);
    _members.removeWhere((m) => m.id == id);
    notifyListeners();
  }

  void clearData() {
    _members = [];
    _isLoading = false;
    notifyListeners();
  }
}
