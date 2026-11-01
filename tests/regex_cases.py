"""Check imported regular expressions against an independent Python re oracle."""
import itertools
import re


def verify_regex(lua):
    module = lua.eval("require('modules/regex')")
    if isinstance(module, tuple):
        module = module[0]
    patterns = [
        '', 'a', 'ab', 'a|b', '(?:ab|ba)+', 'a*', 'a+', 'a?',
        'a{2}', 'a{1,3}', 'a{2,}', '(ab)*', '(a*)*', '[a-c]+',
        '^[^b]+$', r'\d+', r'\D+', r'\s*', r'\S+', r'\w+', r'\W+',
        r'\bword\b', r'\Bword\B', '.*测试', '[一-龥]+', '[😀-🙏]',
        '(?i)AB', '(?m)^b$', '(?s)a.b', 'a(?=b)', 'a(?!b)',
        '(?<=a)b', '(?<!a)b', '^(?:a|ab)+b$', r'\u4E2D\x61',
        'a.*?b', '^$', '^a?$', 'a(?:b|)$', '[^a-c]', '[a-c\\d]+',
        r'(a)\1', r'(.+)\1{2,}', r'(a|ab)\1', r'(?:(a)|b)\1',
        r'(a)?b\1', r'(a)(b)\2\1', r'(?i)(ab)\1',
    ]
    texts = [''.join(p) for length in range(6) for p in itertools.product('ab', repeat=length)]
    texts += ['word', ' word ', 'sword!', '中文测试', '中a', '😀', '🙏', '早上好',
              '12', 'a12', ' \t\n', 'a\nb', 'a\nb\n', 'Aba', 'AB', 'ABC', '!!!']
    count = 0
    for pattern in patterns:
        compiled = module.compile(pattern)
        if isinstance(compiled, tuple):
            raise AssertionError(f'regex did not compile: {pattern!r}: {compiled}')
        for text in texts:
            actual = module.test(compiled, text)
            if isinstance(actual, tuple):
                raise AssertionError(f'regex evaluation failed: {pattern!r}: {actual}')
            expected = re.search(pattern, text, flags=re.ASCII) is not None
            assert bool(actual) == expected, (pattern, text, actual, expected)
            count += 1
    for pattern in ('[', '(abc', 'a{4,2}', r'\9', r'\p{L}', '(?unknown)'):
        failed = module.compile(pattern)
        assert isinstance(failed, tuple) and failed[0] is None, pattern
    compiled = module.compile('^(a+)+b$')
    bounded = module.test(compiled, 'a' * 200)
    assert bounded is False or isinstance(bounded, tuple) and bounded[0] is False
    print(f'Imported regex: {count} matches checked against Python re')
