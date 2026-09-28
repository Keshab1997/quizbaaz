#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generate the complete Class-10 (India/CBSE) subject-chapter list for QuizBaaz.

Creates:
  1. assets/data/chapters_list.json  — full index (15 categories, ~100 chapters)
  2. Skeleton question files         — one JSON per chapter (questions: [])
  3. docs/09_CLASS10_SUBJECT_CHAPTER_LIST.md — human-readable reference

Existing files with real questions are mapped to their matching NCERT chapter.
"""
import json, os, glob

QDIR = 'assets/data/questions'
COMING = 'Questions coming soon — প্রশ্ন শীঘ্রই যোগ হবে'

def qcount(fname):
    p = os.path.join(QDIR, fname)
    return len(json.load(open(p, encoding='utf-8')).get('questions', [])) if os.path.exists(p) else 0

# (file, chapter_id, number, title, title_bn, description, mapped?)
def C(f, cid, n, t, tb, d, mapped=False):
    return dict(file=f, cid=cid, n=n, t=t, tb=tb, d=d, mapped=mapped)

CATS = [
  # ───────────────────────── MATHEMATICS (NCERT 14) ─────────────────────────
  dict(id='cat_math', name='Mathematics (গণিত) — Class 10', icon='assets/icons/coin_and_gem_3d.png',
       color='#F59E0B', chapters=[
    C('class10_math_ch1.json',  'math_ch_01', 1, 'Real Numbers', 'বাস্তব সংখ্যা', 'Euclid division, HCF/LCM, irrationality proofs'),
    C('class10_math_ch2.json',  'math_ch_02', 2, 'Polynomials', 'বহুপদী রাশি', 'Zeros, relationship between zeros & coefficients'),
    C('class10_math_ch3.json',  'math_ch_03', 3, 'Pair of Linear Equations in Two Variables', 'দুই চলকের রৈখিক সমীকরণ যুগ্ম', 'Graphical & algebraic methods, consistency'),
    C('class10_math_ch4.json',  'math_ch_04', 4, 'Quadratic Equations', 'দ্বিঘাত সমীকরণ', 'Roots, factorisation, discriminant, word problems', True),
    C('class10_math_ch5.json',  'math_ch_05', 5, 'Arithmetic Progressions', 'সমান্তরিক ধারা (A.P.)', 'nth term, sum of first n terms'),
    C('class10_math_ch6.json',  'math_ch_06', 6, 'Triangles', 'ত্রিভুজ', 'Similarity, BPT, Pythagoras theorem'),
    C('class10_math_ch7.json',  'math_ch_07', 7, 'Coordinate Geometry', 'স্থানাঙ্ক জ্যামিতি', 'Distance, section formula, area of triangle'),
    C('class10_math_ch8.json',  'math_ch_08', 8, 'Introduction to Trigonometry', 'ত্রিকোণমিতির সূচনা', 'Ratios, identities, standard angles'),
    C('class10_math_ch9.json',  'math_ch_09', 9, 'Some Applications of Trigonometry', 'ত্রিকোণমিতির প্রয়োগ (উচ্চতা ও দূরত্ব)', 'Heights and distances'),
    C('class10_math_ch10.json', 'math_ch_10', 10, 'Circles', 'বৃত্ত', 'Tangent theorems, number of tangents'),
    C('class10_math_ch11.json', 'math_ch_11', 11, 'Areas Related to Circles', 'বৃত্ত সংক্রান্ত ক্ষেত্রফল', 'Sector, segment, combinations of figures'),
    C('class10_math_ch12.json', 'math_ch_12', 12, 'Surface Areas and Volumes', 'পৃষ্ঠতলের ক্ষেত্রফল ও আয়তন', 'Combination of solids'),
    C('class10_math_ch13.json', 'math_ch_13', 13, 'Statistics', 'পরিসংখ্যান', 'Mean, median, mode, ogive'),
    C('class10_math_ch14.json', 'math_ch_14', 14, 'Probability', 'সম্ভাবনা', 'Theoretical & empirical probability'),
  ]),
  # ─────────────────── PHYSICAL SCIENCE: PHYSICS + CHEMISTRY (8) ─────────────
  dict(id='cat_phys_sci', name='Physical Science — Physics & Chemistry (ভৌতবিজ্ঞান)', icon='assets/icons/chapter_quiz_3d.png',
       color='#3B82F6', chapters=[
    C('class10_phys_ch1.json', 'phys_ch_01', 1, 'Chemical Reactions & Equations', 'রাসায়নিক বিক্রিয়া ও সমীকরণ', 'Combination, decomposition, displacement, redox', True),
    C('class10_phys_ch2.json', 'phys_ch_02', 2, 'Acids, Bases and Salts', 'অ্যাসিড, ক্ষার ও লবণ', 'pH scale, neutralization, important salts'),
    C('class10_phys_ch3.json', 'phys_ch_03', 3, 'Metals and Non-metals', 'ধাতু ও অধাতু', 'Reactivity series, extraction, corrosion'),
    C('class10_phys_ch4.json', 'phys_ch_04', 4, 'Carbon and its Compounds', 'কার্বন ও তার যৌগ', 'Bonding, homologous series, ethanol & ethanoic acid'),
    C('class10_phys_ch5.json', 'phys_ch_05', 5, 'Light — Reflection and Refraction', 'আলো — প্রতিফলন ও প্রতিসরণ', 'Mirrors, lenses, power, lens formula'),
    C('class10_phys_ch6.json', 'phys_ch_06', 6, 'The Human Eye and the Colourful World', 'মানব চোখ ও রঙিন জগৎ', 'Defects of vision, prism, scattering, dispersion'),
    C('class10_phys_ch7.json', 'phys_ch_07', 7, 'Electricity', 'তড়িৎ', 'Ohm’s law, resistivity, heating effect'),
    C('class10_phys_ch8.json', 'phys_ch_08', 8, 'Magnetic Effects of Electric Current', 'বিদ্যুৎ প্রবাহের চৌম্বক প্রভাব', 'Solenoid, motor, generator, domestic circuits'),
  ]),
  # ──────────────────────────── LIFE SCIENCE (5) ────────────────────────────
  dict(id='cat_life_sci', name='Life Science / Biology (জীববিজ্ঞান)', icon='assets/icons/practice_target_3d.png',
       color='#10B981', chapters=[
    C('class10_bio_ch1.json', 'bio_ch_01', 1, 'Life Processes', 'জীবন প্রক্রিয়া', 'Nutrition, respiration, transport, excretion', True),
    C('class10_bio_ch2.json', 'bio_ch_02', 2, 'Control and Coordination', 'নিয়ন্ত্রণ ও সমন্বয়', 'Nervous system, reflex action, hormones'),
    C('class10_bio_ch3.json', 'bio_ch_03', 3, 'How do Organisms Reproduce?', 'জীবের প্রজনন', 'Asexual & sexual reproduction, reproduction health'),
    C('class10_bio_ch4.json', 'bio_ch_04', 4, 'Heredity', 'বংশগতি', 'Mendel’s laws, sex determination, traits'),
    C('class10_bio_ch5.json', 'bio_ch_05', 5, 'Our Environment', 'আমাদের পরিবেশ', 'Food chain, trophic levels, ozone depletion'),
  ]),
  # ───────────────────────────── HISTORY (5) ────────────────────────────────
  dict(id='cat_history', name='History — India & the Contemporary World II (ইতিহাস)', icon='assets/icons/battle_swords_3d.png',
       color='#E11D48', chapters=[
    C('history_ch1.json', 'hist_ch_01', 1, 'The Rise of Nationalism in Europe', 'ইউরোপে জাতীয়তাবাদের উত্থান', 'French Revolution, unification of Germany & Italy'),
    C('history_ch2.json', 'hist_ch_02', 2, 'Nationalism in India', 'ভারতে জাতীয়তাবাদ', 'Freedom movement, civil disobedience, partition', True),
    C('history_ch3.json', 'hist_ch_03', 3, 'The Making of a Global World', 'একটি বিশ্বব্যাপী বিশ্বের নির্মাণ', 'Silk route, Great Depression, Bretton Woods'),
    C('history_ch4.json', 'hist_ch_04', 4, 'Print Culture and the Modern World', 'মুদ্রণ সংস্কৃতি ও আধুনিক বিশ্ব', 'Print revolution, press in India'),
    C('history_ch5.json', 'hist_ch_05', 5, 'The Age of Industrialisation', 'শিল্পায়নের যুগ', 'Factories, workers, industrial growth in India'),
  ]),
  # ──────────────────────────── GEOGRAPHY (7) ───────────────────────────────
  dict(id='cat_geography', name='Geography — Contemporary India II (ভূগোল)', icon='assets/icons/chapter_quiz_3d.png',
       color='#059669', chapters=[
    C('class10_geo_ch1.json', 'geo_ch_01', 1, 'Resources and Development', 'সম্পদ ও উন্নয়ন', 'Types of resources, soil erosion, conservation'),
    C('class10_geo_ch2.json', 'geo_ch_02', 2, 'Forest and Wildlife Resources', 'বন ও বন্যপ্রাণী সম্পদ', 'Biodiversity, conservation projects'),
    C('class10_geo_ch3.json', 'geo_ch_03', 3, 'Water Resources', 'জল সম্পদ', 'Dams, rainwater harvesting, water scarcity'),
    C('class10_geo_ch4.json', 'geo_ch_04', 4, 'Agriculture', 'কৃষি', 'Cropping patterns, institutional reforms, food security'),
    C('class10_geo_ch5.json', 'geo_ch_05', 5, 'Minerals and Energy Resources', 'খনিজ ও শক্তি সম্পদ', 'Ferrous/non-ferrous, conventional & non-conventional energy'),
    C('class10_geo_ch6.json', 'geo_ch_06', 6, 'Manufacturing Industries', 'উৎপাদন শিল্প', 'Types, location factors, industrial pollution'),
    C('class10_geo_ch7.json', 'geo_ch_07', 7, 'Lifelines of National Economy', 'জাতীয় অর্থনীতির জীবনরেখা', 'Roadways, railways, ports, international trade'),
  ]),
  # ────────────────────── POLITICAL SCIENCE (5) ─────────────────────────────
  dict(id='cat_polsci', name='Political Science — Democratic Politics II (রাষ্ট্রবিজ্ঞান)', icon='assets/icons/gift_box_3d.png',
       color='#7C3AED', chapters=[
    C('class10_polsci_ch1.json', 'polsci_ch_01', 1, 'Power Sharing', 'ক্ষমতার বণ্টন', 'Belgium & Sri Lanka, forms of power sharing'),
    C('class10_polsci_ch2.json', 'polsci_ch_02', 2, 'Federalism', 'যুক্তরাষ্ট্রবাদ', 'Union & state lists, decentralisation, language policy'),
    C('class10_polsci_ch3.json', 'polsci_ch_03', 3, 'Gender, Religion and Caste', 'লিঙ্গ, ধর্ম ও জাতি', 'Communalism, caste in politics, feminist movements'),
    C('class10_polsci_ch4.json', 'polsci_ch_04', 4, 'Political Parties', 'রাজনৈতিক দলসমূহ', 'National & state parties, challenges, reforms'),
    C('class10_polsci_ch5.json', 'polsci_ch_05', 5, 'Outcomes of Democracy', 'গণতন্ত্রের পরিণাম', 'Accountability, inequality, dignity & freedom'),
  ]),
  # ──────────────────────────── ECONOMICS (4) ───────────────────────────────
  dict(id='cat_economics', name='Economics — Understanding Economic Development (অর্থনীতি)', icon='assets/icons/coin_and_gem_3d.png',
       color='#D97706', chapters=[
    C('class10_eco_ch1.json', 'eco_ch_01', 1, 'Development', 'উন্নয়ন', 'Income & other criteria, HDI, sustainability'),
    C('class10_eco_ch2.json', 'eco_ch_02', 2, 'Sectors of the Indian Economy', 'ভারতীয় অর্থনীতির খাতসমূহ', 'Primary/secondary/tertiary, organised vs unorganised'),
    C('class10_eco_ch3.json', 'eco_ch_03', 3, 'Money and Credit', 'অর্থ ও ঋণ', 'Barter, loans, SHGs, formal vs informal credit'),
    C('class10_eco_ch4.json', 'eco_ch_04', 4, 'Globalisation and the Indian Economy', 'বিশ্বায়ন ও ভারতীয় অর্থনীতি', 'MNCs, WTO, fair globalisation'),
  ]),
  # ───────────────────── COMPUTER SCIENCE & IT (4) ──────────────────────────
  dict(id='cat_cs_it', name='Computer Science & IT (কম্পিউটার ও আইটি)', icon='assets/icons/shop_stall_3d.png',
       color='#6366F1', chapters=[
    C('class10_cs_ch1.json', 'cs_ch_01', 1, 'HTML, Web Design & Networking', 'HTML, ওয়েব ডিজাইন ও নেটওয়ার্কিং', 'Tags, links, images, network basics', True),
    C('class10_cs_ch2.json', 'cs_ch_02', 2, 'Digital Documentation (Advanced)', 'উন্নত ডিজিটাল ডকুমেন্টেশন', 'Styles, images, TOC — LibreOffice Writer'),
    C('class10_cs_ch3.json', 'cs_ch_03', 3, 'Electronic Spreadsheet (Advanced)', 'উন্নত ইলেকট্রনিক স্প্রেডশিট', 'Scenarios, goal seek, macros, linking — Calc'),
    C('class10_cs_ch4.json', 'cs_ch_04', 4, 'Database Management System', 'ডেটাবেজ ম্যানেজমেন্ট সিস্টেম', 'Tables, keys, queries, forms — Base'),
  ]),
  # ───────────────────────── GENERAL CATEGORIES ─────────────────────────────
  dict(id='cat_gen_sci', name='General Science & Space (সাধারণ বিজ্ঞান ও মহাকাশ)', icon='assets/icons/streak_fire_3d.png',
       color='#14B8A6', chapters=[
    C('sci_ch_01.json', 'sci_ch_01', 1, 'Solar System & Space Exploration', 'সৌরজগৎ ও মহাকাশ গবেষণা', 'Planets, missions, ISRO & NASA feats', True),
  ]),
  dict(id='cat_literature', name='Literature — Bengali & English (সাহিত্য)', icon='assets/icons/chapter_quiz_3d.png',
       color='#EC4899', chapters=[
    C('literature_ch1.json', 'lit_ch_01', 1, 'Bengali Literature & Great Writers', 'বাংলা সাহিত্য ও বিখ্যাত লেখক', 'Rabindranath, Bankim, Sarat Chandra & more', True),
  ]),
  dict(id='cat_gk', name='General Knowledge (সাধারণ জ্ঞান — GK)', icon='assets/icons/practice_target_3d.png',
       color='#06B6D4', chapters=[
    C('gk_ch1.json', 'gk_ch_01', 1, 'World & India Superlatives, Discoveries & Awards', 'বিশ্ব ও ভারত — সর্বাধিক, আবিষ্কার ও পুরস্কার', 'Superlatives, inventions, awards', True),
  ]),
  dict(id='cat_current_affairs', name='Current Affairs (সাম্প্রতিক ঘটনাবলী)', icon='assets/icons/streak_fire_3d.png',
       color='#8B5CF6', chapters=[
    C('current_affairs_ch1.json', 'ca_ch_01', 1, 'Current Affairs: Summits, Sports & Science', 'সাম্প্রতিক: শীর্ষ সম্মেলন, খেলা ও বিজ্ঞান', 'Latest summits, sports, science events', True),
  ]),
]

# ── 1. Skeleton files for chapters that don't exist yet ─────────────────────
created, kept = 0, 0
for cat in CATS:
    for ch in cat['chapters']:
        path = os.path.join(QDIR, ch['file'])
        if os.path.exists(path):
            kept += 1
            continue
        skeleton = {
            'chapter_id': ch['cid'],
            'chapter_title': ch['t'],
            'chapter_title_bn': ch['tb'],
            'class_standard': 'Class 10',
            'questions': [],
        }
        with open(path, 'w', encoding='utf-8') as fh:
            json.dump(skeleton, fh, ensure_ascii=False, indent=2)
            fh.write('\n')
        created += 1
print(f'skeletons created: {created}, existing kept: {kept}')

# ── 2. Build chapters_list.json ─────────────────────────────────────────────
out_cats = []
for cat in CATS:
    chapters = []
    for ch in cat['chapters']:
        n = qcount(ch['file'])
        mapped = ch['mapped']
        chapters.append({
            'chapter_id': ch['cid'],
            'chapter_number': ch['n'],
            'title': ch['t'],
            'title_bn': ch['tb'],
            'description': ch['d'] if mapped else f"{ch['d']} ({COMING})",
            'total_questions': n,
            'json_file': f"{QDIR}/{ch['file']}",
            'is_unlocked': True,
            'stars': 3 if mapped else 0,
            'best_score': 100 if mapped else 0,
        })
    out_cats.append({
        'category_id': cat['id'],
        'category_name': cat['name'],
        'category_icon': cat['icon'],
        'color_hex': cat['color'],
        'total_chapters': len(chapters),
        'chapters': chapters,
    })

index = {
    'board_name': 'Class 10 Board Examination & Competitive Prep (১০ম শ্রেণি ও প্রতিযোগিতা কুইজ)',
    'categories': out_cats,
}
with open('assets/data/chapters_list.json', 'w', encoding='utf-8') as fh:
    json.dump(index, fh, ensure_ascii=False, indent=2)
    fh.write('\n')
total_ch = sum(len(c['chapters']) for c in out_cats)
print(f'chapters_list.json: {len(out_cats)} categories, {total_ch} chapters')

# ── 3. Markdown reference doc ───────────────────────────────────────────────
lines = [
    '# 📚 Class 10 (India) — সম্পূর্ণ Subject & Chapter List',
    '',
    '> CBSE/NCERT অনুসারে তৈরি। ✅ = এই chapter-এ এখন প্রশ্ন আছে,',
    '> ⬜ = প্রশ্ন শীঘ্রই যোগ হবে (skeleton file তৈরি — শুধু `questions` array ফিল করলেই হবে)।',
    '',
]
for cat in out_cats:
    lines.append(f"## {cat['category_name']}")
    lines.append('')
    lines.append('| # | Chapter | বাংলা | প্রশ্ন | File |')
    lines.append('|---|---------|-------|-------|------|')
    for ch in cat['chapters']:
        mark = '✅' if ch['total_questions'] > 0 else '⬜'
        lines.append(f"| {mark} {ch['chapter_number']} | {ch['title']} | {ch['title_bn'] or ''} | {ch['total_questions']} | `{ch['json_file'].split('/')[-1]}` |")
    lines.append('')
lines += [
    '## ➕ নতুন প্রশ্ন যোগ করার নিয়ম',
    '',
    'প্রতিটা chapter file-এর `questions` array-তে এই format-এ object যোগ করুন:',
    '',
    '```json',
    '{',
    '  "id": "math_ch_02_q01",',
    '  "question": "English question text?",',
    '  "question_bn": "বাংলা প্রশ্ন?",',
    '  "options": ["A", "B", "C", "D"],',
    '  "correct_index": 2,',
    '  "explanation": "কেন এটাই সঠিক উত্তর",',
    '  "points": 10,',
    '  "time_limit_sec": 30',
    '}',
    '```',
    '',
    '⚠️ প্রশ্ন যোগ করার পর `chapters_list.json`-এ ওই chapter-এর `total_questions` সংখ্যাটা আপডেট করতে ভুলবেন না।',
]
with open('docs/09_CLASS10_SUBJECT_CHAPTER_LIST.md', 'w', encoding='utf-8') as fh:
    fh.write('\n'.join(lines) + '\n')
print('docs/09_CLASS10_SUBJECT_CHAPTER_LIST.md written')
