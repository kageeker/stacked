import 'package:mockito/mockito.dart';
import 'package:stacked_tools/src/locator.dart';
import 'package:stacked_tools/src/services/process_service.dart';
import 'package:test/test.dart';

import '../helpers/test_helpers.dart';

ProcessService _getService() => ProcessService();

void main() {
  group('ProcessService -', () {
    setUp(() => registerServices());
    tearDown(() => locator.reset());
    group('runFormat -', () {
      test('when called should run `flutter format .` ', () async {
        var _clog = getAndRegisterColorizedLogService();
        var service = _getService();
        await service.runFormat();
        verify(_clog.stackedOutput(message: 'Running flutter format . ...'));
      });
      test('when called with appName should run `flutter format .` in appName ',
          () async {
        var _clog = getAndRegisterColorizedLogService();
        var service = _getService();
        await service.runFormat(appName: 'test');
        verify(_clog.stackedOutput(
            message: 'Running flutter format . in test/...'));
      });
      test(
          'when called should run `flutter format .` and format the folders and output a success message',
          () async {
        var _clog = getAndRegisterColorizedLogService();
        var service = _getService();
        await service.runFormat();
        verify(_clog.success(message: 'Command complete. ExitCode: 0'));
      });
    });
  });
}
