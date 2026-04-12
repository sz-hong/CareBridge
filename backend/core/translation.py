import json
import logging

from django.conf import settings
from openai import OpenAI

logger = logging.getLogger(__name__)

SUPPORTED_LANGUAGES = {
    'zh-TW': 'Traditional Chinese (Taiwan)',
    'id': 'Indonesian',
    'vi': 'Vietnamese',
    'tl': 'Tagalog',
}


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

    # Filter out source language from targets
    target_langs = [lang for lang in target_langs if lang != source_lang]
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
    source_description = f'{source_lang} ({SUPPORTED_LANGUAGES[source_lang]})'

    prompt = (
        f'Translate the following text from {source_description} into these languages: '
        f'{target_descriptions}.\n\n'
        f'Return ONLY a valid JSON object where keys are the language codes and values '
        f'are the translated strings. Do not include any explanation or markdown formatting.\n\n'
        f'Text to translate:\n{text}'
    )

    try:
        response = client.chat.completions.create(
            model=model,
            messages=[
                {
                    'role': 'system',
                    'content': (
                        'You are a professional translator specializing in caregiving '
                        'terminology. Return only valid JSON, no markdown.'
                    ),
                },
                {'role': 'user', 'content': prompt},
            ],
            temperature=0.3,
            max_tokens=2048,
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
