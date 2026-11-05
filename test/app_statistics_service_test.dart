import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nazzelha/services/app_statistics_service.dart';

void main() {
  test(
      'loads real platform totals while native startup does not count as a website visit',
      () async {
    var requests = 0;
    final service = AppStatisticsService(client: MockClient((request) async {
      requests++;
      expect(request.url.path, '/api/stats');
      return http.Response(
          '{"visits":27,"downloads":{"windows":5,"android":9,"stale":false}}',
          200);
    }));
    await service.recordWebsiteVisit();
    expect(requests, 0);
    final stats = await service.load();
    expect([stats.visits, stats.windows, stats.android], [27, 5, 9]);
    service.dispose();
  });
  test('unknown download totals stay unknown and service errors can be retried',
      () async {
    var attempt = 0;
    final service = AppStatisticsService(
        client: MockClient((_) async => ++attempt == 1
            ? http.Response('unavailable', 503)
            : http.Response('{"visits":1,"downloads":null}', 200)));
    await expectLater(service.load(), throwsException);
    final stats = await service.load();
    expect(stats.visits, 1);
    expect(stats.windows, isNull);
    expect(stats.android, isNull);
    service.dispose();
  });
}
