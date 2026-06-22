import json
import logging
import re
import sys

from django.conf import settings
from openai import OpenAI

logger = logging.getLogger(__name__)

SUPPORTED_LANGUAGES = {
    'zh-TW': 'Traditional Chinese (Taiwan)',
    'id': 'Indonesian',
    'vi': 'Vietnamese',
    'tl': 'Tagalog',
}

PROTECTED_PLACEHOLDER = '__CB_PROTECTED_{index}__'

PROTECTED_ENTITY_PATTERNS = [
    # Taiwan phone numbers and common local phone formatting.
    re.compile(r'(?<!\w)(?:\+?886[-\s]?)?0\d{1,2}[-\s]?\d{3,4}[-\s]?\d{3,4}(?!\w)'),
    # Taiwan national ID / common document number shape.
    re.compile(r'\b[A-Z][12]\d{8}\b'),
    # Clock times.
    re.compile(r'\b(?:[01]?\d|2[0-3]):[0-5]\d\b'),
    # ISO-like dates.
    re.compile(r'\b\d{4}[-/]\d{1,2}[-/]\d{1,2}\b'),
    # Medication dose and common clinical units.
    re.compile(
        r'\b\d+(?:\.\d+)?\s?'
        r'(?:mg|mcg|g|kg|ml|mL|L|cc|IU|U|units?|tabs?|tablets?|capsules?|'
        r'drops?|patch(?:es)?|puffs?)\b',
        re.IGNORECASE,
    ),
    # Common medication names and medication-name suffixes. Keep this before
    # model-code matching so drug names near doses become their own spans.
    re.compile(
        r'\b(?:Aspirin|Metformin|Amlodipine|'
        r'[A-Z][A-Za-z]*(?:pril|sartan|statin|olol|dipine|formin|cillin|'
        r'mycin|prazole|azole|vir|mab|nib|ide|ine|rin))\b'
    ),
    # Brand + model/code, e.g. Omron HEM-7121.
    re.compile(r'\b[A-Z][A-Za-z]+(?:\s+[A-Z]{2,}[A-Z0-9]*-\d[A-Z0-9-]*)\b'),
    # Product, medication, and medical device codes with digits.
    re.compile(r'\b[A-Z]{1,6}[A-Z0-9]*[- ]?\d{2,}[A-Z0-9-]*\b'),
    # English facility/store names.
    re.compile(
        r'\b(?:[A-Z][A-Za-z&.\'-]*\s+){0,6}'
        r'(?:Hospital|Clinic|Pharmacy|Drugstore|Store)\b'
    ),
    # Chinese facility/store names.
    re.compile(r'[\u4e00-\u9fffA-Za-z0-9&.\'-]+(?:醫院|診所|藥局|藥房|商店|店)'),
    # Basic address fragments.
    re.compile(
        r'(?:\d+[\w\s,.-]*(?:Road|Rd\.?|Street|St\.?|Avenue|Ave\.?)|'
        r'[\u4e00-\u9fff\d]+(?:路|街|巷|弄|號))',
        re.IGNORECASE,
    ),
]


def normalize_language(language):
    return language if language in SUPPORTED_LANGUAGES else 'zh-TW'


def protected_entity_map(text, target_langs=None):
    if not text or not str(text).strip():
        return {}
    targets = list(target_langs or SUPPORTED_LANGUAGES.keys())
    targets = [normalize_language(lang) for lang in targets]
    targets = list(dict.fromkeys(targets))
    return {lang: str(text) for lang in targets}


def _is_unmocked_test_run():
    return (
        'test' in sys.argv
        and type(translate_text).__module__ != 'unittest.mock'
    )


def _add_term_spans(text, term, spans):
    if not term or not str(term).strip():
        return
    term = str(term).strip()
    for match in re.finditer(re.escape(term), text):
        spans.append((match.start(), match.end()))


def _protected_spans(text, protected_terms=None):
    spans = []
    for term in protected_terms or []:
        _add_term_spans(text, term, spans)
    for pattern in PROTECTED_ENTITY_PATTERNS:
        spans.extend((match.start(), match.end()) for match in pattern.finditer(text))

    if not spans:
        return []

    # Prefer longer spans when two detections overlap.
    spans.sort(key=lambda item: (item[0], -(item[1] - item[0])))
    selected = []
    covered_until = -1
    for start, end in spans:
        if start < covered_until:
            continue
        selected.append((start, end))
        covered_until = end
    return selected


def _mask_protected_entities(text, protected_terms=None):
    spans = _protected_spans(text, protected_terms=protected_terms)
    if not spans:
        return text, {}

    masked_parts = []
    replacements = {}
    cursor = 0
    for index, (start, end) in enumerate(spans):
        placeholder = PROTECTED_PLACEHOLDER.format(index=index)
        masked_parts.append(text[cursor:start])
        masked_parts.append(placeholder)
        replacements[placeholder] = text[start:end]
        cursor = end
    masked_parts.append(text[cursor:])
    return ''.join(masked_parts), replacements


def _restore_protected_entities(text, replacements, original_text):
    restored = text
    for placeholder, original in replacements.items():
        if placeholder not in restored:
            logger.warning(
                'Translation dropped protected placeholder %s; falling back',
                placeholder,
            )
            return original_text
        restored = restored.replace(placeholder, original)
    return restored


def translate_for_user(
    text,
    user=None,
    source_lang=None,
    target_langs=None,
    mode='mixed_text',
    protected_terms=None,
):
    """
    Best-effort dynamic text translation.

    Returns a JSON-friendly mapping that always includes the source text keyed
    by source language. Translation failures are logged and fall back to the
    source language only so API writes do not fail because OpenAI is unavailable.
    """
    if not text or not str(text).strip():
        return {}

    if mode == 'protected_entity':
        return protected_entity_map(text, target_langs=target_langs)
    if mode not in {'mixed_text', 'translatable_text'}:
        raise ValueError(f'Unsupported translation mode: {mode}')

    original_text = str(text)
    source = normalize_language(
        source_lang or getattr(user, 'language', None) or 'zh-TW'
    )
    targets = list(target_langs or SUPPORTED_LANGUAGES.keys())
    targets = [normalize_language(lang) for lang in targets]
    targets = list(dict.fromkeys(targets))
    translated = {source: original_text}

    # Translate into every requested language. `source` is only the author's
    # *account-language* hint, NOT the actual language of the text: a caregiver
    # whose UI is zh-TW may type Vietnamese, in which case a zh-TW translation
    # is still required. We therefore do not exclude `source` here — the model
    # detects the real language and returns the text unchanged for whichever
    # language it is already written in (see translate_text), so the
    # source-language slot ends up holding a genuine translation when the text
    # was authored in a different language.
    request_targets = list(targets)
    if not request_targets:
        return translated
    if _is_unmocked_test_run():
        return translated

    if mode == 'mixed_text':
        text_for_translation, replacements = _mask_protected_entities(
            original_text,
            protected_terms=protected_terms,
        )
    else:
        text_for_translation = original_text
        replacements = {}

    try:
        translated_payload = translate_text(
            text_for_translation, source, request_targets
        )
        for lang in request_targets:
            value = translated_payload.get(lang, text_for_translation)
            if replacements:
                value = _restore_protected_entities(
                    value, replacements, original_text
                )
            translated[lang] = value
    except Exception as exc:
        logger.warning('Dynamic translation failed: %s', exc)
    return translated


def translate_content_fields(
    content,
    user=None,
    keys=None,
    source_lang=None,
    protected_keys=None,
    protected_terms=None,
):
    """
    Translate selected string leaves in JSON content while preserving shape.
    """
    if not isinstance(content, dict):
        return {}
    key_filter = set(keys or [])
    protected_key_filter = set(protected_keys or [])
    translated = {}
    for key, value in content.items():
        if isinstance(value, str) and (not key_filter or key in key_filter):
            if key in protected_key_filter:
                payload = protected_entity_map(value)
            else:
                payload = translate_for_user(
                    value,
                    user=user,
                    source_lang=source_lang,
                    mode='mixed_text',
                    protected_terms=protected_terms,
                )
            if payload:
                translated[key] = payload
        elif isinstance(value, dict):
            nested = translate_content_fields(
                value,
                user=user,
                keys=keys,
                source_lang=source_lang,
                protected_keys=protected_keys,
                protected_terms=protected_terms,
            )
            if nested:
                translated[key] = nested
    return translated


def translate_board_items(items, user=None, source_lang=None):
    if not isinstance(items, list):
        return items
    translated_items = []
    for item in items:
        if not isinstance(item, dict):
            translated_items.append(item)
            continue
        translated_item = dict(item)
        name = translated_item.get('name')
        payload = translate_for_user(
            name,
            user=user,
            source_lang=source_lang,
            mode='mixed_text',
        )
        if payload:
            translated_item['name_translated'] = payload
        translated_items.append(translated_item)
    return translated_items


def translate_text(text, source_lang, target_langs):
    """
    Translate text from source_lang to one or more target languages
    using the OpenAI API.

    Args:
        text (str): The text to translate.
        source_lang (str): Source language code (e.g. 'zh-TW', 'id', 'vi', 'tl').
        target_langs (list[str]): List of target language codes to translate into.

    Returns:
        dict: A mapping of language code -> translated text.
              e.g. {'id': '...', 'vi': '...'}
    """
    if not text or not text.strip():
        return {lang: '' for lang in target_langs}

    # Validate languages
    all_langs = set([source_lang] + list(target_langs))
    for lang in all_langs:
        if lang not in SUPPORTED_LANGUAGES:
            raise ValueError(
                f"Unsupported language: '{lang}'. "
                f"Supported: {list(SUPPORTED_LANGUAGES.keys())}"
            )

    # Translate into every requested language. `source_lang` is only a hint
    # (the author's account language); the model detects the text's actual
    # language and returns it unchanged for whichever target it already matches.
    target_langs = list(dict.fromkeys(target_langs))
    if not target_langs:
        return {}

    api_key = getattr(settings, 'OPENAI_API_KEY', None)
    if not api_key:
        raise RuntimeError('OPENAI_API_KEY is not configured in Django settings.')

    model = getattr(settings, 'OPENAI_MODEL', 'gpt-4o')
    client = OpenAI(api_key=api_key)

    target_descriptions = ', '.join(
        f'{code} ({SUPPORTED_LANGUAGES[code]})' for code in target_langs
    )
    target_codes = ', '.join(target_langs)

    prompt = (
        f'Detect the language the message below is actually written in, then '
        f'translate the message into each of these languages: {target_descriptions}.\n'
        f'If the message is already written in one of those languages, return it '
        f'unchanged for that language.\n\n'
        f'Return ONLY a valid JSON object whose keys are exactly these language codes: '
        f'{target_codes}, and whose values are the message rendered in that language. '
        f'Do not include any explanation or markdown formatting.\n'
        f'Do not translate, alter, remove, or reorder tokens that look like '
        f'__CB_PROTECTED_0__; copy each protected token exactly as provided.\n\n'
        f'Message:\n{text}'
    )

    try:
        response = client.chat.completions.create(
            model=model,
            messages=[
                {
                    'role': 'system',
                    'content': (
                        'You are a professional translator specializing in caregiving '
                        'terminology. Preserve protected placeholder tokens exactly. '
                        'Return only valid JSON, no markdown.'
                    ),
                },
                {'role': 'user', 'content': prompt},
            ],
            temperature=0.3,
            max_completion_tokens=2048,
        )

        response_text = response.choices[0].message.content.strip()
        translations = json.loads(response_text)

        # Validate that all requested languages are present
        result = {}
        for lang in target_langs:
            if lang in translations:
                result[lang] = translations[lang]
            else:
                logger.warning(
                    'Translation for language %s not found in API response', lang
                )
                result[lang] = text  # Fallback to original text

        return result

    except json.JSONDecodeError:
        logger.exception('Failed to parse translation API response as JSON')
        return {lang: text for lang in target_langs}
    except Exception:
        logger.exception('OpenAI API error during translation')
        raise
