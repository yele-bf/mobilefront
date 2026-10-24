import 'package:flutter_test/flutter_test.dart';
import 'package:yele/constants/config.dart';

void main() {
  test('server display name matches the configured backend hostname', () {
    expect(serverDisplayName, Uri.parse(API_BASE_URL).host);
    expect(serverDisplayName, 'mobiletest-j0c6.onrender.com');
  });
}
