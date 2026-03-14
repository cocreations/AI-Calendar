import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart';

const listEventsTool = Tool(
  name: 'list_events',
  description:
      'List calendar events within a date range. Use this to check what events exist.',
  inputSchema: InputSchema(
    properties: {
      'calendar_ids': {
        'type': 'array',
        'items': {'type': 'string'},
        'description':
            'List of calendar IDs to search. Pick based on the prompt rules for each calendar.',
      },
      'start_date': {
        'type': 'string',
        'description': 'Start date/time in ISO 8601 format (e.g. 2025-03-14T00:00:00)',
      },
      'end_date': {
        'type': 'string',
        'description': 'End date/time in ISO 8601 format (e.g. 2025-03-14T23:59:59)',
      },
    },
    required: ['calendar_ids', 'start_date', 'end_date'],
  ),
);

const createEventTool = Tool(
  name: 'create_event',
  description: 'Create a new calendar event.',
  inputSchema: InputSchema(
    properties: {
      'calendar_id': {
        'type': 'string',
        'description': 'The calendar ID to create the event in.',
      },
      'summary': {
        'type': 'string',
        'description': 'Title/summary of the event.',
      },
      'start': {
        'type': 'string',
        'description': 'Start date/time in ISO 8601 format.',
      },
      'end': {
        'type': 'string',
        'description': 'End date/time in ISO 8601 format.',
      },
      'description': {
        'type': 'string',
        'description': 'Optional description for the event.',
      },
      'location': {
        'type': 'string',
        'description': 'Optional location for the event.',
      },
    },
    required: ['calendar_id', 'summary', 'start', 'end'],
  ),
);

const updateEventTool = Tool(
  name: 'update_event',
  description: 'Update an existing calendar event. First use list_events to find the event ID.',
  inputSchema: InputSchema(
    properties: {
      'calendar_id': {
        'type': 'string',
        'description': 'The calendar ID containing the event.',
      },
      'event_id': {
        'type': 'string',
        'description': 'The event ID to update.',
      },
      'summary': {
        'type': 'string',
        'description': 'New title/summary (optional).',
      },
      'start': {
        'type': 'string',
        'description': 'New start date/time in ISO 8601 format (optional).',
      },
      'end': {
        'type': 'string',
        'description': 'New end date/time in ISO 8601 format (optional).',
      },
      'description': {
        'type': 'string',
        'description': 'New description (optional).',
      },
      'location': {
        'type': 'string',
        'description': 'New location (optional).',
      },
    },
    required: ['calendar_id', 'event_id'],
  ),
);

const deleteEventTool = Tool(
  name: 'delete_event',
  description: 'Delete a calendar event. First use list_events to find the event ID.',
  inputSchema: InputSchema(
    properties: {
      'calendar_id': {
        'type': 'string',
        'description': 'The calendar ID containing the event.',
      },
      'event_id': {
        'type': 'string',
        'description': 'The event ID to delete.',
      },
    },
    required: ['calendar_id', 'event_id'],
  ),
);

const searchContactsTool = Tool(
  name: 'search_contacts',
  description:
      'Search saved contacts/people by name or description. Use when the user asks about a person.',
  inputSchema: InputSchema(
    properties: {
      'query': {
        'type': 'string',
        'description': 'Search term to match against contact names and descriptions.',
      },
    },
    required: ['query'],
  ),
);

const addContactTool = Tool(
  name: 'add_contact',
  description:
      'Save a new contact/person with a description. Use when the user wants to remember someone.',
  inputSchema: InputSchema(
    properties: {
      'name': {
        'type': 'string',
        'description': 'The person\'s name.',
      },
      'description': {
        'type': 'string',
        'description': 'A description to help remember this person.',
      },
    },
    required: ['name', 'description'],
  ),
);

final allTools = [
  ToolDefinition.custom(listEventsTool),
  ToolDefinition.custom(createEventTool),
  ToolDefinition.custom(updateEventTool),
  ToolDefinition.custom(deleteEventTool),
  ToolDefinition.custom(searchContactsTool),
  ToolDefinition.custom(addContactTool),
];
