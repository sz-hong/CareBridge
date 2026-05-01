"""
OpenAI Function Calling tool definitions for the AI assistant.

These tools allow GPT-4o to query backend data on behalf of the user
during a conversation (e.g. "How is grandma's blood pressure this week?").
"""
import json
import logging

from .domain_queries import (
    query_care_logs,
    query_events,
    query_expenses,
    query_health_data,
    query_medications,
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
                        "enum": [
                            "heart_rate", "blood_oxygen",
                            "step_count", "active_energy",
                        ],
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
                        "enum": [
                            "medication", "vital", "meal",
                            "activity", "note",
                        ],
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
}
