COMMON_INFO_TYPES = [
    'EMAIL_ADDRESS',
    'PHONE_NUMBER',
    'CREDIT_CARD_NUMBER',
    'PERSON_NAME',
    'STREET_ADDRESS',
    'DATE_OF_BIRTH',
    'MEDICAL_RECORD_NUMBER',
]

CUSTOM_REGEX_INFO_TYPES = {
    'TAIWAN_PHONE_NUMBER': r'(?<!\d)(?:\+?886[-\s]?)?0?9\d{2}[-\s]?\d{3}[-\s]?\d{3}(?!\d)',
    'TAIWAN_NATIONAL_ID': r'\b[A-Z][12]\d{8}\b',
    'TAIWAN_ARC_ID': r'\b[A-Z][A-D]\d{8}\b',
    'NHI_CARD_NUMBER': r'\b\d{12}\b',
    'BANK_ACCOUNT': r'\b\d{3,4}[-\s]?\d{6,14}\b',
    'CREDIT_CARD_NUMBER': r'\b(?:\d[ -]*?){13,19}\b',
    'EMAIL_ADDRESS': r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
}


def default_info_types():
    custom_names = [
        name for name in CUSTOM_REGEX_INFO_TYPES
        if name not in COMMON_INFO_TYPES
    ]
    return COMMON_INFO_TYPES + custom_names
