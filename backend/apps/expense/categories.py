EXPENSE_CATEGORY_CODES = {
    'medical',
    'food',
    'daily',
    'transport',
    'other',
}

EXPENSE_CATEGORY_ALIASES = {
    '醫療保健': 'medical',
    '醫療': 'medical',
    '醫療用品': 'medical',
    '藥品': 'medical',
    '處方藥': 'medical',
    '日常飲食': 'food',
    '飲食': 'food',
    '食品': 'food',
    '食物': 'food',
    '生活用品': 'daily',
    '日用品': 'daily',
    '用品': 'daily',
    '交通': 'transport',
    '交通費': 'transport',
    '其他': 'other',
    '其他支出': 'other',
}


def normalize_expense_category(value):
    if not isinstance(value, str):
        return 'other'

    raw = value.strip()
    if not raw:
        return 'other'

    normalized = raw.lower()
    if normalized in EXPENSE_CATEGORY_CODES:
        return normalized

    return EXPENSE_CATEGORY_ALIASES.get(raw, 'other')


def normalize_expense_items(items):
    if not isinstance(items, list):
        return []

    normalized_items = []
    for item in items:
        if not isinstance(item, dict):
            normalized_items.append(item)
            continue

        normalized_item = dict(item)
        normalized_item['category'] = normalize_expense_category(
            normalized_item.get('category')
        )
        normalized_items.append(normalized_item)
    return normalized_items
