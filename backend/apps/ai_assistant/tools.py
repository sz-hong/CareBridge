"""
OpenAI Function Calling tool definitions for the AI assistant.

These tools allow GPT-4o to query backend data on behalf of the user
during a conversation (e.g. "How is grandma's blood pressure this week?").
"""
import json
import logging

from apps.care_log.models import CareLog
from apps.board.models import BoardRequest
from apps.health.models import HealthAlert, HealthData
from apps.leave.models import Leave
from apps.sos.models import SOSRecord
from apps.todo.models import Todo

from .domain_queries import (
    query_board_requests,
    query_care_logs,
    query_events,
    query_expenses,
    query_family_members,
    query_health_alerts,
    query_health_data,
    query_leaves,
    query_medication_confirmations,
    query_medications,
    query_sos_status,
    query_todos,
)

logger = logging.getLogger(__name__)

# --------------------------------------------------------------------------
# Tool definitions (OpenAI function-calling schema)
# --------------------------------------------------------------------------

TOOL_DEFINITIONS = [
    {
        "type": "function",
        "function": {
            "name": "query_health_data",
            "description": (
                "Query the elder's health data. Returns recent vital signs "
                "such as heart rate, blood oxygen, step count, and active energy."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "data_type": {
                        "type": "string",
                        "enum": list(HealthData.Type.values),
                        "description": "Type of health data to query. Omit to get all types.",
                    },
                    "days": {
                        "type": "integer",
                        "description": "Number of past days to look back (default 7).",
                    },
                },
                "required": [],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "query_care_logs",
            "description": (
                "Query recent care log entries (meals, medication, vitals, "
                "activity, and notes)."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "log_type": {
                        "type": "string",
                        "enum": list(CareLog.Type.values),
                        "description": "Filter by log type. Omit for all types.",
                    },
                    "days": {
                        "type": "integer",
                        "description": "Number of past days (default 7).",
                    },
                },
                "required": [],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "query_medications",
            "description": "Query the elder's current medications and schedules.",
            "parameters": {
                "type": "object",
                "properties": {
                    "active_only": {
                        "type": "boolean",
                        "description": "If true, only return active medications.",
                    },
                },
                "required": [],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "query_expenses",
            "description": "Query care-related expenses and monthly totals.",
            "parameters": {
                "type": "object",
                "properties": {
                    "days": {
                        "type": "integer",
                        "description": "Number of past days (default 30).",
                    },
                },
                "required": [],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "query_events",
            "description": "Query upcoming calendar events (appointments, leave, etc.).",
            "parameters": {
                "type": "object",
                "properties": {
                    "days_ahead": {
                        "type": "integer",
                        "description": "Number of days ahead to look (default 14).",
                    },
                },
                "required": [],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "query_todos",
            "description": (
                "Query household and care task todos for the current family. "
                "Returns AI-safe fields only."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "status": {
                        "type": "string",
                        "enum": list(Todo.Status.values),
                        "description": "Filter by todo status.",
                    },
                    "priority": {
                        "type": "string",
                        "enum": list(Todo.Priority.values),
                        "description": "Filter by priority.",
                    },
                    "days_ahead": {
                        "type": "integer",
                        "description": "Limit to todos due within this many days.",
                    },
                },
                "required": [],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "query_board_requests",
            "description": (
                "Query family board purchase or supply requests for the current family. "
                "Returns AI-safe fields only."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "status": {
                        "type": "string",
                        "enum": list(BoardRequest.Status.values),
                        "description": "Filter by request status.",
                    },
                    "category": {
                        "type": "string",
                        "enum": list(BoardRequest.Category.values),
                        "description": "Filter by request category.",
                    },
                    "days": {
                        "type": "integer",
                        "description": "Number of past days to look back (default 30).",
                    },
                },
                "required": [],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "query_leaves",
            "description": (
                "Query caregiver leave requests and family vote status. "
                "Returns AI-safe fields only."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "status": {
                        "type": "string",
                        "enum": list(Leave.Status.values),
                        "description": "Filter by leave status.",
                    },
                    "days": {
                        "type": "integer",
                        "description": "Number of past days to look back (default 30).",
                    },
                },
                "required": [],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "query_health_alerts",
            "description": (
                "Query recent health alerts for abnormal vitals in the current family."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "severity": {
                        "type": "string",
                        "enum": list(HealthAlert.Severity.values),
                        "description": "Filter by alert severity.",
                    },
                    "acknowledged": {
                        "type": "boolean",
                        "description": "Filter by whether the alert was acknowledged.",
                    },
                    "days": {
                        "type": "integer",
                        "description": "Number of past days to look back (default 30).",
                    },
                },
                "required": [],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "query_medication_confirmations",
            "description": (
                "Query recent medication confirmation records for the current family. "
                "Does not expose confirmation photos or URLs."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "days": {
                        "type": "integer",
                        "description": "Number of past days to look back (default 7).",
                    },
                },
                "required": [],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "query_sos_status",
            "description": (
                "Query recent SOS records for the current family. "
                "Does not expose precise location or notified member IDs."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "status": {
                        "type": "string",
                        "enum": list(SOSRecord.Status.values),
                        "description": "Filter by SOS status.",
                    },
                    "days": {
                        "type": "integer",
                        "description": "Number of past days to look back (default 30).",
                    },
                },
                "required": [],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "query_family_members",
            "description": (
                "Query basic family member names, roles, languages, and primary status. "
                "Does not expose email, phone, avatar URL, or device data."
            ),
            "parameters": {
                "type": "object",
                "properties": {},
                "required": [],
            },
        },
    },
]

# --------------------------------------------------------------------------
# Tool execution functions
# --------------------------------------------------------------------------


def execute_tool(tool_name, arguments, user):
    """Execute a tool call and return the result as a string."""
    try:
        args = json.loads(arguments) if isinstance(arguments, str) else arguments
    except json.JSONDecodeError:
        args = {}
    if not isinstance(args, dict):
        args = {}

    handler = TOOL_HANDLERS.get(tool_name)
    if not handler:
        return json.dumps({"error": f"Unknown tool: {tool_name}"})

    try:
        result = handler(args, user)
        return json.dumps(result, default=str, ensure_ascii=False)
    except Exception as e:
        logger.exception("Tool execution error: %s", tool_name)
        return json.dumps({"error": str(e)})


TOOL_HANDLERS = {
    "query_health_data": query_health_data,
    "query_care_logs": query_care_logs,
    "query_medications": query_medications,
    "query_expenses": query_expenses,
    "query_events": query_events,
    "query_todos": query_todos,
    "query_board_requests": query_board_requests,
    "query_leaves": query_leaves,
    "query_health_alerts": query_health_alerts,
    "query_medication_confirmations": query_medication_confirmations,
    "query_sos_status": query_sos_status,
    "query_family_members": query_family_members,
}
