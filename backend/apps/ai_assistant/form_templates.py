import json
from pathlib import Path


TEMPLATE_DIR = Path(__file__).with_name("subsidy_form_templates")
MAX_UPLOADED_TEMPLATE_BYTES = 1_000_000


class FormTemplateError(ValueError):
    pass


def load_subsidy_form_template(form_type):
    path = TEMPLATE_DIR / f"{form_type}.json"
    if not path.exists():
        raise FormTemplateError(f"Unsupported subsidy form template: {form_type}")
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def uploaded_subsidy_form_template(uploaded_file):
    payload = uploaded_file.read(MAX_UPLOADED_TEMPLATE_BYTES + 1)
    if len(payload) > MAX_UPLOADED_TEMPLATE_BYTES:
        raise FormTemplateError("Uploaded form template is too large.")

    text = payload.decode("utf-8", errors="replace").strip()
    if not text:
        raise FormTemplateError("Uploaded form template is empty.")

    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        parsed = {
            "form_type": "uploaded_template",
            "display_name": uploaded_file.name,
            "official_source": "User uploaded form template",
            "raw_template_text": text,
        }
    else:
        if not isinstance(parsed, dict):
            raise FormTemplateError("Uploaded JSON template must be an object.")
        parsed.setdefault("form_type", "uploaded_template")
        parsed.setdefault("display_name", uploaded_file.name)
        parsed.setdefault("official_source", "User uploaded form template")

    parsed["uploaded_filename"] = uploaded_file.name
    return parsed
