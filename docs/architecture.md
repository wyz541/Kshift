---
slug: /docs/r1-architecture
title: Kshift R1 architecture
type: reference
status: review
updated: "2026-11-13"
keywords:
  - Rust server
  - PostgreSQL 18
  - revision
  - transactional outbox
  - concurrency
description: 描述 Kshift R1 server 的事务、revision、outbox 和错误边界。
---

# Kshift R1 architecture

## Ownership

| Module | Owns | Does not own |
| --- | --- | --- |
| `kshift-domain` | invariants and business types | I/O and wire formats |
| `kshift-contract` | protobuf, typed errors, conversions | database access |
| `kshift-server` | authentication, authorization, transactions and streaming | UI state |
| PostgreSQL 18 | durable data, constraints and schema version | client authentication |

## Write transaction

Every command uses one PostgreSQL transaction.

1. Lock the idempotency key.
2. Return the stored result when `(client_id, command_id)` exists.
3. Lock the project row and check `expected_project_revision`.
4. Check the project role.
5. Apply one business change.
6. Write the audit row.
7. Increment the project revision.
8. Encode and insert one outbox event.
9. Send `pg_notify` with only `project_id`.
10. Store the encoded command result.
11. Commit all rows together.

A failure rolls back the business row, audit row, revision, outbox row and
idempotency row.

## Revision rules

- A project starts at revision 1 after `CreateProject`.
- Every successful write adds exactly one revision.
- `change_event` is unique on `(project_id, revision)`.
- A stale project precondition returns `ABORTED` and current revision details.
- A stale entity version returns `ABORTED` and entity version details.
- The server does not merge conflicts.

## Event stream

- The outbox is the source of truth.
- PostgreSQL notification only wakes stream readers.
- A stream reads events in revision order.
- Retention removes events after 7 days by default.
- A missing revision produces `ResetRequired`.
- A schema mismatch produces `ResetRequired`.
- A slow stream closes when its bounded channel is full.
- The client reconnects with exponential backoff and fetches a snapshot after reset.

## Limits

| Resource | Default |
| --- | ---: |
| unary RPC | 100 |
| write transaction | 8 |
| event stream | 32 |
| event stream per user | 1 |
| outbox event channel | 64 |
| request timeout | 15 seconds |
| write timeout | 10 seconds |
| heartbeat | 15 seconds |
| unary request size | 1 MiB |
| unary response size | 16 MiB |
| snapshot size | 16 MiB |
| event size | 256 KiB |
| attachment cache item | 256 MiB |

All queues and semaphores are bounded.

## Error mapping

| API error | gRPC code | typed detail |
| --- | --- | --- |
| invalid command | `INVALID_ARGUMENT` | `ERROR_CODE_INVALID_INPUT` |
| missing or invalid token | `UNAUTHENTICATED` | `ERROR_CODE_AUTH_REQUIRED` |
| project isolation | `PERMISSION_DENIED` | `ERROR_CODE_FORBIDDEN` |
| revision conflict | `ABORTED` | current revision and entity version |
| stale event cursor | `FAILED_PRECONDITION` or stream `ResetRequired` | current and retained revision |
| capacity exhausted | `RESOURCE_EXHAUSTED` | limit message |
| internal failure | `INTERNAL` | generic public message |
