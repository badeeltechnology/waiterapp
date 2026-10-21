import 'package:flutter_test/flutter_test.dart';
import 'package:servepos_waiter/core/server_url.dart';

void main() {
  group('normalizeServerUrl', () {
    String n(String s) => normalizeServerUrl(s).url;

    test('adds https when no scheme', () {
      expect(n('demo.myapp.qa'), 'https://demo.myapp.qa');
    });

    test('strips trailing slashes, whitespace and quotes', () {
      expect(n('  https://demo.myapp.qa/// '), 'https://demo.myapp.qa');
      expect(n('"demo.myapp.qa"'), 'https://demo.myapp.qa');
    });

    test('strips desk paths, query and fragment', () {
      expect(n('https://demo.myapp.qa/app/pos-invoice/new?x=1#y'), 'https://demo.myapp.qa');
      expect(n('https://demo.myapp.qa/desk#List/Item'), 'https://demo.myapp.qa');
      expect(n('demo.myapp.qa/app'), 'https://demo.myapp.qa');
      expect(n('https://demo.myapp.qa/login'), 'https://demo.myapp.qa');
      expect(n('https://demo.myapp.qa/api/method/frappe.ping'), 'https://demo.myapp.qa');
    });

    test('keeps a sub-path site and port', () {
      expect(n('https://host.qa:8443/erp/app/home'), 'https://host.qa:8443/erp');
    });

    test('lowercases scheme and host', () {
      expect(n('HTTPS://Demo.MyApp.QA'), 'https://demo.myapp.qa');
    });

    test('classifies security', () {
      expect(normalizeServerUrl('https://a.qa').security, UrlSecurity.secure);
      expect(normalizeServerUrl('http://a.qa').security, UrlSecurity.insecurePublic);
      expect(normalizeServerUrl('http://localhost:8000').security, UrlSecurity.insecureLocal);
      expect(normalizeServerUrl('http://10.0.0.5').security, UrlSecurity.insecureLocal);
      expect(normalizeServerUrl('http://192.168.1.20:8000/app').security, UrlSecurity.insecureLocal);
      expect(normalizeServerUrl('http://172.16.0.1').security, UrlSecurity.insecureLocal);
      expect(normalizeServerUrl('http://172.31.255.1').security, UrlSecurity.insecureLocal);
      expect(normalizeServerUrl('http://172.32.0.1').security, UrlSecurity.insecurePublic);
      expect(normalizeServerUrl('http://8.8.8.8').security, UrlSecurity.insecurePublic);
    });

    test('rejects junk', () {
      expect(() => normalizeServerUrl(''), throwsA(isA<ServerUrlException>()));
      expect(() => normalizeServerUrl('ftp://x.qa'), throwsA(isA<ServerUrlException>()));
      expect(() => normalizeServerUrl('https://'), throwsA(isA<ServerUrlException>()));
      expect(() => normalizeServerUrl('https://bad host!'), throwsA(isA<ServerUrlException>()));
    });
  });
}
