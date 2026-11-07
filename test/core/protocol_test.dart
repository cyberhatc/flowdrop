import 'package:flutter_test/flutter_test.dart';
import 'package:flowdrop/core/protocol/constants.dart';
import 'package:flowdrop/core/protocol/device.dart';
import 'package:flowdrop/core/protocol/offers.dart';

DeviceInfo sampleDevice() => const DeviceInfo(
  id: 'device-1',
  name: 'Test Laptop',
  platform: 'windows',
  publicKey: 'cHViag==',
  fingerprint:
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  addresses: ['192.168.1.10'],
  port: FlowDropProtocol.defaultPort,
  protocolVersion: FlowDropProtocol.version,
);

void main() {
  group('DeviceInfo', () {
    test('round-trips through JSON', () {
      final device = sampleDevice();
      final restored = DeviceInfo.fromJson(device.toJson());
      expect(restored.id, device.id);
      expect(restored.name, device.name);
      expect(restored.fingerprint, device.fingerprint);
      expect(restored.addresses, ['192.168.1.10']);
      expect(restored.isCompatible, isTrue);
    });

    test('rejects missing id, fingerprint and port', () {
      expect(() => DeviceInfo.fromJson({}), throwsA(isA<FormatException>()));
      expect(
        () => DeviceInfo.fromJson({'id': 'x'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('flags incompatible protocol versions', () {
      final json = sampleDevice().toJson()..['version'] = 99;
      final restored = DeviceInfo.fromJson(json);
      expect(restored.isCompatible, isFalse);
    });
  });

  group('OfferRequest', () {
    test('round-trips files and text', () {
      final offer = OfferRequest(
        sessionId: 's1',
        sender: sampleDevice(),
        text: 'hello',
        files: const [
          OfferedFile(id: 'f1', name: 'a.txt', size: 5, mime: 'text/plain'),
        ],
      );
      final restored = OfferRequest.fromJson(offer.toJson());
      expect(restored.sessionId, 's1');
      expect(restored.files.first.name, 'a.txt');
      expect(restored.totalSize, 5);
      expect(restored.text, 'hello');
    });

    test('rejects empty offers', () {
      expect(
        () => OfferRequest.fromJson({
          'sessionId': 's1',
          'sender': sampleDevice().toJson(),
          'files': <dynamic>[],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects duplicate file ids', () {
      final file = const OfferedFile(id: 'f1', name: 'a.txt', size: 1);
      expect(
        () => OfferRequest(
          sessionId: 's1',
          sender: sampleDevice(),
          files: [file, file],
        ),
        isNotNull,
      );
      expect(
        () => OfferRequest.fromJson({
          'sessionId': 's1',
          'sender': sampleDevice().toJson(),
          'files': [file.toJson(), file.toJson()],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects negative and oversized file sizes', () {
      expect(
        () => OfferedFile.fromJson({'id': 'f', 'name': 'n', 'size': -1}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => OfferedFile.fromJson({
          'id': 'f',
          'name': 'n',
          'size': FlowDropProtocol.maxFileSize + 1,
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('OfferResponse / PairRequest', () {
    test('offer response round-trips upload urls', () {
      final response = OfferResponse(
        accepted: true,
        sessionId: 's1',
        uploadUrls: const {'f1': '/v1/upload/s1/f1'},
      );
      final restored = OfferResponse.fromJson(response.toJson());
      expect(restored.accepted, isTrue);
      expect(restored.uploadUrls['f1'], '/v1/upload/s1/f1');
    });

    test('pair request rejects missing signature', () {
      expect(
        () => PairRequest.fromJson({
          'token': 't',
          'device': sampleDevice().toJson(),
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
