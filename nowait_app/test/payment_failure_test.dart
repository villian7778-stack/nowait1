import 'package:flutter_test/flutter_test.dart';
import 'package:nowait_app/services/payment_service.dart';

void main() {
  test('pulls description + reason out of Razorpay JSON message', () {
    const msg = '{"error":{"code":"BAD_REQUEST_ERROR","description":"Payment failed","reason":"payment_failed"}}';
    expect(PaymentService.describeFailure(msg, null), 'Payment failed: Payment failed (payment_failed)');
  });

  test('uses response body map when present', () {
    final body = {'error': {'description': 'International cards are not supported', 'reason': 'international_transaction_not_allowed'}};
    expect(PaymentService.describeFailure('x', body),
        'Payment failed: International cards are not supported (international_transaction_not_allowed)');
  });

  test('plain text message is kept', () {
    expect(PaymentService.describeFailure('Network error', null), 'Payment failed: Network error');
  });

  test('nothing known falls back to generic', () {
    expect(PaymentService.describeFailure(null, null), 'Payment failed');
    expect(PaymentService.describeFailure('not json {', null), 'Payment failed: not json {');
  });

  test('describeFailure surfaces "already paid" description from UPI error body', () {
    // Razorpay UPI "order is already paid" error — description must be surfaced.
    final body = {
      'error': {
        'description': 'Your payment has been declined as the order is already paid.',
        'reason': 'order_already_paid',
      }
    };
    expect(PaymentService.describeFailure(null, body), contains('already paid'));
  });
}
