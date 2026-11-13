import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/domain/thapar_email.dart';

void main() {
  group('ThaparEmail.isValid accepts', () {
    for (final e in [
      'student@thapar.edu',
      'a@thapar.edu',
      'first.last@thapar.edu',
      'first_last@thapar.edu',
      'first-last@thapar.edu',
      'name+tag@thapar.edu',
      'abc123@thapar.edu',
      'STUDENT@THAPAR.EDU',
      'Student@Thapar.Edu',
      '  student@thapar.edu  ',
      '\tstudent@thapar.edu\n',
    ]) {
      test('"$e"', () => expect(ThaparEmail.isValid(e), isTrue));
    }
  });

  group('ThaparEmail.isValid rejects', () {
    final bad = <String, String>{
      'empty': '',
      'blank': '   ',
      'no at': 'studentthapar.edu',
      'no local part': '@thapar.edu',
      'no domain': 'student@',
      'wrong tld': 'student@thapar.com',
      'gmail': 'student@gmail.com',
      'subdomain': 'a@x.thapar.edu',
      'deep subdomain': 'a@mail.cs.thapar.edu',
      'lookalike suffix': 'student@thapar.edu.evil.com',
      'lookalike hyphen': 'student@thapar-edu.com',
      'lookalike prefix': 'student@notthapar.edu',
      'lookalike prefix 2': 'student@xthapar.edu',
      'lookalike char': 'student@thapar.edu.in',
      'lookalike typo': 'student@thaper.edu',
      'lookalike typo 2': 'student@thapar.ed',
      'trailing dot domain': 'student@thapar.edu.',
      'double at': 'a@b@thapar.edu',
      'at in local quoted': '"a@b"@thapar.edu',
      'space in local': 'stu dent@thapar.edu',
      'space before domain': 'student@ thapar.edu',
      'newline injection': 'student@thapar.edu\nBcc: evil@x.com',
      'comma list': 'a@thapar.edu,b@evil.com',
      'semicolon list': 'a@thapar.edu;b@evil.com',
      'leading dot local': '.a@thapar.edu',
      'trailing dot local': 'a.@thapar.edu',
      'double dot local': 'a..b@thapar.edu',
      'angle brackets': '<a@thapar.edu>',
      'display name form': 'Name <a@thapar.edu>',
      'cyrillic a lookalike in domain': 'a@thаpar.edu',
      'cyrillic lookalike in local': 'аbc@thapar.edu',
      'unicode full-width at': 'a＠thapar.edu',
      'url style': 'http://thapar.edu',
      'userinfo trick': 'thapar.edu@evil.com',
      'userinfo trick 2': 'a@thapar.edu@evil.com',
      'percent hack': 'a%evil.com@thapar.edu',
      'bang path': 'evil.com!a@thapar.edu',
    };
    bad.forEach((name, value) {
      test(name, () => expect(ThaparEmail.isValid(value), isFalse, reason: value));
    });

    test('null', () => expect(ThaparEmail.isValid(null), isFalse));
    test('over-long input', () {
      expect(ThaparEmail.isValid('${'a' * 250}@thapar.edu'), isFalse);
    });
  });

  test('normalize lower-cases and trims', () {
    expect(ThaparEmail.normalize('  Student@THAPAR.edu '), 'student@thapar.edu');
  });

  test('domain constant', () => expect(ThaparEmail.domain, 'thapar.edu'));
}
