import 'package:flutter_test/flutter_test.dart';
import 'package:nowait_app/services/auth_service.dart';
import 'package:nowait_app/services/payment_service.dart';

Map<String, dynamic> _prefill({Map<String, dynamic>? server, String? contact, String? email}) =>
    PaymentService.checkoutOptions(
      keyId: 'rzp_test_x', orderId: 'order_1', amountPaise: 4900, description: 'Plan',
      serverPrefill: server, contact: contact, email: email,
    )['prefill'] as Map<String, dynamic>;

void main() {
  tearDown(() => AuthService.instance.profile = null);

  group('mobile number for Razorpay', () {
    for (final (raw, expected) in [
      ('9876543210', '+919876543210'),
      ('+91 98765-43210', '+919876543210'),
      ('919876543210', '+919876543210'),
      ('09876543210', '+919876543210'),
      ('+919876543210', '+919876543210'),
      ('', ''),
    ]) {
      test("'$raw' -> '$expected'", () => expect(PaymentService.normalizeIndianMobile(raw), expected));
    }
  });

  test('the server\'s details are used, so every owner gets mobile and email filled in', () {
    // The case that made checkout ask: the saved profile has no email (older account).
    AuthService.instance.profile = {'name': 'Asha', 'phone': '9876543210', 'email': null};
    final p = _prefill(server: {'name': 'Asha Patil', 'email': 'asha@example.com', 'contact': '+919876543210'});
    expect(p, {'contact': '+919876543210', 'email': 'asha@example.com', 'name': 'Asha Patil'});
  });

  test('without server details, the saved profile is used, mobile with +91', () {
    AuthService.instance.profile = {'name': 'Ravi', 'phone': '98765 43210', 'email': 'ravi@example.com'};
    expect(_prefill(), {'contact': '+919876543210', 'email': 'ravi@example.com', 'name': 'Ravi'});
  });

  test('blank values are left out, never sent empty', () {
    AuthService.instance.profile = {'name': '', 'phone': '', 'email': ''};
    expect(_prefill(server: {'email': '  '}), isEmpty);
  });
}
