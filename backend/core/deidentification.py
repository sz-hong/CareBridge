from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Protocol

from django.conf import settings

from core.pii_patterns import COMMON_INFO_TYPES, CUSTOM_REGEX_INFO_TYPES, default_info_types


HIGH_RISK_LIKELIHOODS = {'LIKELY', 'VERY_LIKELY'}


@dataclass
class PIIFinding:
    info_type: str
    quote: str
    likelihood: str = 'POSSIBLE'

    def to_dict(self):
        return {
            'info_type': self.info_type,
            'likelihood': self.likelihood,
            'quote_length': len(self.quote or ''),
        }


@dataclass
class DeidentificationResult:
    text: str
    findings: list[PIIFinding]

    @property
    def high_risk(self):
        return any(f.likelihood in HIGH_RISK_LIKELIHOODS for f in self.findings)

    def findings_as_dicts(self):
        return [finding.to_dict() for finding in self.findings]


@dataclass
class RedactedFile:
    bytes: bytes
    mime_type: str
    findings: list[PIIFinding]

    @property
    def high_risk(self):
        return any(f.likelihood in HIGH_RISK_LIKELIHOODS for f in self.findings)

    def findings_as_dicts(self):
        return [finding.to_dict() for finding in self.findings]


class DeidentificationClient(Protocol):
    def deidentify_text(self, text: str) -> DeidentificationResult:
        ...

    def redact_image(self, image_bytes: bytes, mime_type: str) -> RedactedFile:
        ...

    def inspect_text(self, text: str) -> list[PIIFinding]:
        ...


class MockDeidentificationClient:
    def inspect_text(self, text: str) -> list[PIIFinding]:
        findings: list[PIIFinding] = []
        for info_type, pattern in CUSTOM_REGEX_INFO_TYPES.items():
            for match in re.finditer(pattern, text, flags=re.IGNORECASE):
                findings.append(PIIFinding(info_type=info_type, quote=match.group(0)))
        return findings

    def deidentify_text(self, text: str) -> DeidentificationResult:
        findings: list[PIIFinding] = []
        redacted = text
        for info_type, pattern in CUSTOM_REGEX_INFO_TYPES.items():
            compiled = re.compile(pattern, flags=re.IGNORECASE)
            for match in list(compiled.finditer(redacted)):
                findings.append(PIIFinding(info_type=info_type, quote=match.group(0)))
            redacted = compiled.sub(f'[{info_type}]', redacted)
        return DeidentificationResult(text=redacted, findings=findings)

    def redact_image(self, image_bytes: bytes, mime_type: str) -> RedactedFile:
        return RedactedFile(bytes=image_bytes, mime_type=mime_type, findings=[])


class GoogleDLPDeidentificationClient:
    def __init__(self):
        project = getattr(settings, 'GOOGLE_CLOUD_PROJECT', '')
        if not project:
            raise RuntimeError('GOOGLE_CLOUD_PROJECT must be set when DLP_PROVIDER=google_dlp')
        self.project = project
        self.location = getattr(settings, 'GOOGLE_DLP_LOCATION', 'global')
        self.min_likelihood = getattr(settings, 'DLP_MIN_LIKELIHOOD', 'LIKELY')
        configured_info_types = getattr(settings, 'DLP_INFO_TYPES', default_info_types())
        self.info_types = list(dict.fromkeys(
            info_type for info_type in configured_info_types
            if info_type in COMMON_INFO_TYPES
        ))
        self.custom_info_types = {
            name: pattern for name, pattern in CUSTOM_REGEX_INFO_TYPES.items()
            if name in configured_info_types and name not in COMMON_INFO_TYPES
        }

    @property
    def parent(self):
        return f'projects/{self.project}/locations/{self.location}'

    def _client(self):
        try:
            from google.cloud import dlp_v2
        except ImportError as exc:
            raise RuntimeError(
                'google-cloud-dlp is required when DLP_PROVIDER=google_dlp'
            ) from exc
        return dlp_v2.DlpServiceClient()

    def _inspect_config(self):
        return {
            'min_likelihood': self.min_likelihood,
            'include_quote': True,
            'info_types': [{'name': info_type} for info_type in self.info_types],
            'custom_info_types': [
                {
                    'info_type': {'name': name},
                    'regex': {'pattern': pattern},
                }
                for name, pattern in self.custom_info_types.items()
            ],
        }

    def _image_redaction_configs(self):
        configs = []
        seen = set()
        for info_type in [*self.info_types, *self.custom_info_types.keys()]:
            if info_type in seen:
                continue
            seen.add(info_type)
            configs.append({'info_type': {'name': info_type}})
        return configs

    def inspect_text(self, text: str) -> list[PIIFinding]:
        response = self._client().inspect_content(
            request={
                'parent': self.parent,
                'inspect_config': self._inspect_config(),
                'item': {'value': text},
            }
        )
        return _findings_from_google_response(response.result.findings)

    def deidentify_text(self, text: str) -> DeidentificationResult:
        findings = self.inspect_text(text)
        response = self._client().deidentify_content(
            request={
                'parent': self.parent,
                'inspect_config': self._inspect_config(),
                'deidentify_config': {
                    'info_type_transformations': {
                        'transformations': [
                            {
                                'primitive_transformation': {
                                    'replace_with_info_type_config': {}
                                }
                            }
                        ]
                    }
                },
                'item': {'value': text},
            }
        )
        return DeidentificationResult(
            text=response.item.value,
            findings=findings,
        )

    def redact_image(self, image_bytes: bytes, mime_type: str) -> RedactedFile:
        content_type_index = {
            'image/jpeg': 1,
            'image/jpg': 1,
            'image/bmp': 2,
            'image/png': 3,
            'image/svg+xml': 4,
            'application/pdf': 8,
        }.get(mime_type, 6 if mime_type.startswith('image/') else 0)

        response = self._client().redact_image(
            request={
                'parent': self.parent,
                'inspect_config': self._inspect_config(),
                'image_redaction_configs': self._image_redaction_configs(),
                'byte_item': {
                    'type_': content_type_index,
                    'data': image_bytes,
                },
            }
        )
        findings = []
        if getattr(response, 'inspect_result', None):
            findings = _findings_from_google_response(response.inspect_result.findings)
        return RedactedFile(
            bytes=bytes(response.redacted_image),
            mime_type=mime_type,
            findings=findings,
        )


def _findings_from_google_response(findings):
    parsed = []
    if not isinstance(findings, list) and not hasattr(findings, '__iter__'):
        return parsed
    for finding in findings:
        info_type = getattr(getattr(finding, 'info_type', None), 'name', 'UNKNOWN')
        quote = getattr(finding, 'quote', '')
        likelihood = getattr(finding, 'likelihood', 'LIKELIHOOD_UNSPECIFIED')
        if not isinstance(likelihood, str):
            likelihood = getattr(likelihood, 'name', str(likelihood))
        parsed.append(
            PIIFinding(
                info_type=info_type,
                quote=quote,
                likelihood=likelihood.replace('Likelihood.', ''),
            )
        )
    return parsed


def get_deidentification_client() -> DeidentificationClient:
    provider = getattr(settings, 'DLP_PROVIDER', 'mock')
    if provider == 'google_dlp':
        return GoogleDLPDeidentificationClient()
    return MockDeidentificationClient()


def prepare_text_for_gpt(raw_text: str) -> str:
    return get_deidentification_client().deidentify_text(raw_text).text
