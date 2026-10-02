#!/usr/bin/env python3
"""Validates the trilingual question banks under `assets/data/`.

Run this before committing any batch of questions — especially AI-generated
ones, which fail in quiet, plausible-looking ways: an option list that lost a
language, a `correct_index` pointing past the end, the same question id reused
across two chapters, or an answer whose translations do not line up.

    python3 tool/validate_questions.py            # report
    python3 tool/validate_questions.py --strict   # also fail on warnings
    python3 tool/validate_questions.py --stats    # coverage table only

Exit code is non-zero when there are errors, so it can gate a commit.
"""
import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / 'assets' / 'data'
CHAPTERS_LIST = DATA / 'chapters_list.json'
DAILY_QUIZ = DATA / 'daily_quiz.json'

LANGUAGES = ['en', 'bn', 'hi']
REQUIRED_LANGUAGES = ['en', 'bn', 'hi']

MIN_OPTIONS = 2
MAX_OPTIONS = 6

# Latin letter runs this short are symbols or units ("cm", "Hz", "pH", "D"); the
# few longer unit symbols that appear in the banks are listed explicitly.
NEUTRAL_UNIT_SYMBOLS = frozenset({
    'kPa', 'MPa', 'GPa', 'kHz', 'MHz', 'GHz', 'kWh', 'mol', 'atm', 'rpm', 'ppm',
})
LATIN_RUN = re.compile(r'[A-Za-z]+')
FORMULA_CHARS = re.compile(r'[0-9=+−×÷·/:^²³°%<>-]')


def is_language_neutral(text):
    """True for ratios, measurements and formulas: `1 : 2`, `50 Hz`,
    `H = I² · R · t`. Their only Latin letters are symbols or units.

    Those read the same in every language, so an identical bn/hi copy is
    expected rather than a skipped translation. The text must also contain a
    digit or an operator, so two short words ("It is") still count as prose.
    Keep in step with `_isLanguageNeutral` in question_validator.dart.
    """
    if not FORMULA_CHARS.search(text):
        return False
    return all(len(run) <= 2 or run in NEUTRAL_UNIT_SYMBOLS
               for run in LATIN_RUN.findall(text))


class Report:
    def __init__(self):
        self.errors = []
        self.warnings = []

    def error(self, where, message):
        self.errors.append(f'{where}: {message}')

    def warn(self, where, message):
        self.warnings.append(f'{where}: {message}')


def localized(raw):
    """Normalises a LocalizedText JSON value to {lang: text}."""
    if raw is None:
        return {}
    if isinstance(raw, str):
        return {'en': raw.strip()} if raw.strip() else {}
    if isinstance(raw, dict):
        return {k: v.strip() for k, v in raw.items()
                if isinstance(v, str) and v.strip()}
    return {}


def check_localized(report, where, field, raw, *, required=True):
    """Verifies one translatable field and returns the languages it covers."""
    values = localized(raw)

    if not values:
        if required:
            report.error(where, f'{field} is empty')
        return values

    if isinstance(raw, str):
        report.warn(where, f'{field} is a bare string — English only')

    if 'en' not in values:
        report.error(where, f'{field} has no English text (it is the fallback)')

    for lang in values:
        if lang not in LANGUAGES:
            report.warn(where, f'{field} has unexpected language "{lang}"')

    missing = [l for l in REQUIRED_LANGUAGES if l not in values]
    if missing:
        report.warn(where, f'{field} missing {", ".join(missing)}')

    # Untranslated copy-paste: identical text in two languages usually means
    # the translation step was skipped. Mirrors `_looksUntranslated` in
    # lib/data/services/question_validator.dart — keep the two in step.
    #
    # Single tokens are exempt: 'H2O', 'NaCl', '1947' and technical terms the
    # classroom keeps in English ('Router') legitimately read the same in all
    # three languages. Requiring a space isolates real prose.
    #
    # Ratios, measurements and formulas that do contain a space ('1 : 2',
    # '50 Hz', 'H = I² · R · t') are exempt too: see is_language_neutral().
    #
    # Deliberate difference from the Dart validator: this is a *warning* here
    # and a *rejection* there. Assets are hand-authored and reviewed, so the
    # author gets the final say; a generated draft can simply be regenerated.
    for lang in ('bn', 'hi'):
        if lang in values and 'en' in values and values[lang] == values['en']:
            english = values['en'].strip()
            if ' ' not in english:
                continue
            if any(ord(c) > 0x24F for c in english):
                continue  # already non-Latin, so not a skipped translation
            if is_language_neutral(english):
                continue  # reads the same in every language
            report.warn(where, f'{field}.{lang} is identical to English')

    return values


def check_question(report, where, question, seen_ids):
    qid = question.get('id')
    if not qid or not isinstance(qid, str):
        report.error(where, 'missing "id"')
    else:
        if qid in seen_ids:
            report.error(where, f'duplicate id "{qid}" (also in {seen_ids[qid]})')
        else:
            seen_ids[qid] = where
        where = f'{where} [{qid}]'

    coverage = {}
    coverage['question'] = check_localized(
        report, where, 'question', question.get('question'))

    options = question.get('options')
    if not isinstance(options, list):
        report.error(where, '"options" must be a list')
        return coverage

    if not (MIN_OPTIONS <= len(options) <= MAX_OPTIONS):
        report.error(
            where,
            f'{len(options)} options — expected {MIN_OPTIONS}-{MAX_OPTIONS}')

    per_language_counts = Counter()
    rendered = defaultdict(list)
    for i, option in enumerate(options):
        values = check_localized(report, where, f'options[{i}]', option)
        for lang in values:
            per_language_counts[lang] += 1
            rendered[lang].append(values[lang])

    # Two identical options make the question unanswerable in that language.
    for lang, texts in rendered.items():
        duplicates = [t for t, n in Counter(texts).items() if n > 1]
        if duplicates:
            report.error(
                where,
                f'duplicate option text in "{lang}": {duplicates[0]!r}')

    index = question.get('correct_index')
    if not isinstance(index, int):
        report.error(where, '"correct_index" must be an integer')
    elif not (0 <= index < len(options)):
        report.error(
            where,
            f'correct_index {index} is outside 0..{len(options) - 1}')

    check_localized(report, where, 'explanation',
                    question.get('explanation'), required=False)

    for field, low, high in (('points', 1, 1000),
                             ('time_limit_sec', 5, 300)):
        if field in question:
            value = question[field]
            if not isinstance(value, int) or not (low <= value <= high):
                report.error(where, f'{field}={value!r} outside {low}..{high}')

    coverage['options'] = per_language_counts
    return coverage


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--strict', action='store_true',
                        help='treat warnings as failures')
    parser.add_argument('--stats', action='store_true',
                        help='print the coverage table only')
    args = parser.parse_args()

    report = Report()
    seen_ids = {}
    totals = Counter()
    per_chapter = []

    # ------------------------------------------------------ chapters_list --
    chapters = json.loads(CHAPTERS_LIST.read_text(encoding='utf-8'))
    declared_files = {}
    for cat in chapters.get('categories', []):
        cwhere = f"chapters_list.json/{cat.get('category_id', '?')}"
        check_localized(report, cwhere, 'category_name',
                        cat.get('category_name'))
        for ch in cat.get('chapters', []):
            where = f"{cwhere}/{ch.get('chapter_id', '?')}"
            check_localized(report, where, 'title', ch.get('title'))
            path = ch.get('json_file', '')
            if not path:
                report.error(where, 'missing "json_file"')
            elif not (ROOT / path).exists():
                report.error(where, f'json_file not found: {path}')
            else:
                declared_files[path] = ch

    # ---------------------------------------------------------- questions --
    bank_files = sorted((DATA / 'questions').glob('*.json'))
    for path in bank_files:
        rel = path.relative_to(ROOT).as_posix()
        data = json.loads(path.read_text(encoding='utf-8'))
        questions = data.get('questions', [])

        if rel not in declared_files:
            report.warn(rel, 'bank is not referenced by chapters_list.json')

        check_localized(report, rel, 'chapter_title', data.get('chapter_title'))

        counts = Counter()
        for i, question in enumerate(questions):
            coverage = check_question(report, f'{rel}#{i}', question, seen_ids)
            qcov = coverage.get('question', {})
            for lang in REQUIRED_LANGUAGES:
                if lang in qcov:
                    counts[lang] += 1

        totals['questions'] += len(questions)
        for lang in REQUIRED_LANGUAGES:
            totals[lang] += counts[lang]
        per_chapter.append((rel, len(questions), counts))

        # Keep the advertised count honest — the chapter card shows it.
        declared = declared_files.get(rel, {}).get('total_questions')
        if declared is not None and declared != len(questions):
            report.error(
                rel,
                f'chapters_list says total_questions={declared} '
                f'but the bank has {len(questions)}')

    # -------------------------------------------------------- daily  quiz --
    daily = json.loads(DAILY_QUIZ.read_text(encoding='utf-8'))
    for i, question in enumerate(daily.get('questions', [])):
        check_question(report, f'daily_quiz.json#{i}', question, seen_ids)
    totals['daily'] = len(daily.get('questions', []))

    # ------------------------------------------------------------- output --
    print(f'Chapter banks : {len(bank_files)}')
    print(f'Questions     : {totals["questions"]} '
          f'(+{totals["daily"]} in the daily bank)')
    if totals['questions']:
        for lang in REQUIRED_LANGUAGES:
            n = totals[lang]
            pct = 100 * n / totals['questions']
            print(f'  {lang}: {n:5d}/{totals["questions"]}  {pct:5.1f}%')

    if args.stats:
        print()
        for rel, n, counts in per_chapter:
            if n:
                cover = ' '.join(f'{l}:{counts[l]}' for l in REQUIRED_LANGUAGES)
                print(f'{n:4d}  {cover}   {rel}')
        return 0

    if report.warnings:
        print(f'\n{len(report.warnings)} warning(s):')
        for w in report.warnings[:40]:
            print('  -', w)
        if len(report.warnings) > 40:
            print(f'  … and {len(report.warnings) - 40} more')

    if report.errors:
        print(f'\n{len(report.errors)} error(s):')
        for e in report.errors[:40]:
            print('  -', e)
        if len(report.errors) > 40:
            print(f'  … and {len(report.errors) - 40} more')
        return 1

    if args.strict and report.warnings:
        print('\nFailing because --strict was given.')
        return 1

    print('\nQuestion banks are valid ✅')
    return 0


if __name__ == '__main__':
    sys.exit(main())
