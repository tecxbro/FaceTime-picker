# Local identity sources

The `local` branch supports three mutually exclusive modes.

## Terminal

Default when no identity-source environment variables are present. Enter one or more numbers separated by commas. The source is loaded once and is not refreshed.

## SQLite

Set `FACETIME_PICKER_SQLITE_PATH`. FaceTime Picker opens the database with `SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX` and runs:

```sql
SELECT "phone_number"
FROM "trusted_callers"
WHERE "enabled" = 1;
```

Table and column names can be changed through environment variables. They must match `[A-Za-z_][A-Za-z0-9_]*`.

## JSON

Set `FACETIME_PICKER_IDENTITY_FILE` to a local JSON file. The supported envelope is:

```json
{
  "schemaVersion": 1,
  "trustedCallers": [
    {"phoneNumber": "+1 202 555 0147", "enabled": true}
  ],
  "cacheTTLSeconds": 30
}
```

A bare array of caller records is also accepted.
