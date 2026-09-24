import 'package:flutter_test/flutter_test.dart';

import 'package:media_tracker/services/isbn.dart';

void main() {
  group('cleanIsbn', () {
    test('strips separators and the ISBN prefix', () {
      expect(cleanIsbn('978-0-306-40615-7'), '9780306406157');
      expect(cleanIsbn('978 0 306 40615 7'), '9780306406157');
      expect(cleanIsbn('ISBN 978-0-306-40615-7'), '9780306406157');
      expect(cleanIsbn('ISBN-13: 978-0-306-40615-7'), '9780306406157');
      expect(cleanIsbn('isbn 10 0-306-40615-2'), '0306406152');
      expect(cleanIsbn('ISBN13:9780306406157'), '9780306406157');
    });

    test('upper-cases the trailing X', () {
      expect(cleanIsbn('0-9752298-0-x'), '097522980X');
      expect(cleanIsbn('097522980x'), '097522980X');
    });

    test('returns an empty string for unusable input', () {
      expect(cleanIsbn(''), '');
      expect(cleanIsbn('   '), '');
      expect(cleanIsbn('ISBN'), '');
      expect(cleanIsbn('ISBN-13:'), '');
    });
  });

  group('parseIsbn — valid', () {
    test('accepts a valid ISBN-13', () {
      final isbn = parseIsbn('978-0-306-40615-7');
      expect(isbn, isNotNull);
      expect(isbn!.value, '9780306406157');
      expect(isbn.format, IsbnFormat.isbn13);
    });

    test('accepts a valid ISBN-10', () {
      final isbn = parseIsbn('0-306-40615-2');
      expect(isbn, isNotNull);
      expect(isbn!.value, '0306406152');
      expect(isbn.format, IsbnFormat.isbn10);
    });

    test('accepts an ISBN-10 with X as the check digit (upper and lower)', () {
      for (final input in ['097522980X', '097522980x', '0-9752298-0-X']) {
        final isbn = parseIsbn(input);
        expect(isbn, isNotNull, reason: input);
        expect(isbn!.value, '097522980X');
        expect(isbn.format, IsbnFormat.isbn10);
      }
    });

    test('accepts spaces, dashes and an ISBN prefix', () {
      expect(parseIsbn('ISBN 978 0 306 40615 7')?.value, '9780306406157');
      expect(parseIsbn('ISBN-10: 0306406152')?.value, '0306406152');
      expect(
        parseIsbn('  isbn-13: 978-0-306-40615-7 ')?.value,
        '9780306406157',
      );
    });

    test('tolerates typographic dashes and non-breaking spaces', () {
      expect(parseIsbn('978–0–306–40615–7')?.value, '9780306406157');
      expect(
        parseIsbn('978\u00a00306\u00a040615\u00a07')?.value,
        '9780306406157',
      );
    });
  });

  group('parseIsbn — invalid', () {
    test('rejects a broken ISBN-13 check digit', () {
      // 9780306406157 is valid, the last digit flipped to 8 is not.
      expect(parseIsbn('9780306406158'), isNull);
      expect(parseIsbn('978-0-306-40615-8'), isNull);
    });

    test('rejects a broken ISBN-10 check digit', () {
      expect(parseIsbn('0306406153'), isNull);
      expect(parseIsbn('097522980Y'), isNull);
    });

    test('rejects a 10-character body with X in a digit position', () {
      expect(parseIsbn('030640615X'), isNull);
      expect(parseIsbn('X306406152'), isNull);
    });

    test('rejects input that is too short or too long', () {
      expect(parseIsbn('123456789'), isNull); // 9 chars
      expect(parseIsbn('123456789012'), isNull); // 12 chars
      expect(parseIsbn('12345678901234'), isNull); // 14 chars
    });

    test('rejects empty input', () {
      expect(parseIsbn(''), isNull);
      expect(parseIsbn('   '), isNull);
      expect(parseIsbn('ISBN-13:'), isNull);
    });

    test('rejects ordinary non-ISBN text and plain numbers', () {
      expect(parseIsbn('inception'), isNull);
      expect(parseIsbn('herr der ringe'), isNull);
      expect(parseIsbn('12345'), isNull);
      // A 13-digit order number whose check digit does not fit.
      expect(parseIsbn('1234567890123'), isNull);
    });
  });

  test('isIsbn mirrors parseIsbn', () {
    expect(isIsbn('978-0-306-40615-7'), isTrue);
    expect(isIsbn('not an isbn'), isFalse);
  });

  test('Isbn has value equality', () {
    expect(
      parseIsbn('9780306406157'),
      const Isbn(value: '9780306406157', format: IsbnFormat.isbn13),
    );
  });
}
