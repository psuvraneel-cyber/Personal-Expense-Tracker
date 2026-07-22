import 'package:flutter/material.dart';
import 'package:pet/premium/models/linked_account.dart';
import 'package:pet/premium/repositories/linked_account_repository.dart';
import 'package:pet/premium/services/bank_integration_provider.dart';
import 'package:pet/premium/services/mock_bank_integration.dart';

class LinkedAccountProvider extends ChangeNotifier {
  final LinkedAccountRepository _repository = LinkedAccountRepository();
  final BankIntegrationProvider _provider = MockBankIntegrationProvider();

  bool isTesting = false;

  List<LinkedAccount> _accounts = [];
  bool _isLoading = false;

  List<LinkedAccount> get accounts => _accounts;
  bool get isLoading => _isLoading;
  String get providerName => _provider.name;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    _accounts = await _repository.getAll();
    if (_accounts.isEmpty && isTesting) {
      _accounts = await _provider.listLinkedAccounts();
      for (final account in _accounts) {
        await _repository.upsert(account);
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> connectMockAccount() async {
    if (!isTesting) {
      throw UnsupportedError('Mock bank connection is disabled in production.');
    }
    await _provider.connectAccount();
    final refreshed = await _provider.listLinkedAccounts();
    for (final account in refreshed) {
      await _repository.upsert(account);
    }
    _accounts = await _repository.getAll();
    notifyListeners();
  }

  Future<void> disconnectAccount(String id) async {
    await _provider.disconnectAccount(id);
    await _repository.delete(id);
    _accounts.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  void clearData() {
    _accounts = [];
    _isLoading = false;
    notifyListeners();
  }
}
