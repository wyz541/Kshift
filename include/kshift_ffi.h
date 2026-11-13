#ifndef KSHIFT_FFI_H
#define KSHIFT_FFI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void *KshiftClientHandle;
typedef void *KshiftSubscriptionHandle;
typedef void *KshiftCancelHandle;

typedef enum KshiftStatus {
  KSHIFT_STATUS_OK = 0,
  KSHIFT_STATUS_INVALID_ARGUMENT = 1,
  KSHIFT_STATUS_INVALID_HANDLE = 2,
  KSHIFT_STATUS_INVALID_STATE = 3,
  KSHIFT_STATUS_INVALID_UTF8 = 4,
  KSHIFT_STATUS_MESSAGE_TOO_LARGE = 5,
  KSHIFT_STATUS_DEADLINE_EXCEEDED = 6,
  KSHIFT_STATUS_CANCELLED = 7,
  KSHIFT_STATUS_UNAUTHENTICATED = 8,
  KSHIFT_STATUS_PERMISSION_DENIED = 9,
  KSHIFT_STATUS_NOT_FOUND = 10,
  KSHIFT_STATUS_CONFLICT = 11,
  KSHIFT_STATUS_RESET_REQUIRED = 12,
  KSHIFT_STATUS_RESOURCE_EXHAUSTED = 13,
  KSHIFT_STATUS_UNAVAILABLE = 14,
  KSHIFT_STATUS_PROTOCOL_ERROR = 15,
  KSHIFT_STATUS_INTERNAL = 16
} KshiftStatus;

typedef struct KshiftSlice {
  const uint8_t *data;
  size_t len;
} KshiftSlice;

typedef struct KshiftBuffer {
  uint8_t *data;
  size_t len;
  size_t capacity;
} KshiftBuffer;

typedef struct KshiftClientConfig {
  KshiftSlice endpoint_utf8;
  KshiftSlice ca_pem;
  KshiftSlice tls_domain_utf8;
  uint64_t default_deadline_ms;
  size_t max_response_bytes;
} KshiftClientConfig;

/* Every string and JSON input uses an explicit byte length. */
KshiftStatus kshift_client_create(const KshiftClientConfig *config,
                                  KshiftClientHandle *out_client);
KshiftStatus kshift_client_destroy(KshiftClientHandle client);

/* Tokens are bounded ASCII bytes. They are never logged or returned. */
KshiftStatus kshift_client_update_token(KshiftClientHandle client,
                                        KshiftSlice token_utf8);
KshiftStatus kshift_client_clear_token(KshiftClientHandle client);
KshiftStatus kshift_client_clear_caches(KshiftClientHandle client);
KshiftStatus kshift_client_clear_project_cache(KshiftClientHandle client,
                                                KshiftSlice project_id_utf8);
KshiftStatus kshift_client_cache_attachment(KshiftClientHandle client,
                                            KshiftSlice sha256_hex_utf8,
                                            KshiftSlice bytes);
KshiftStatus kshift_client_get_cached_attachment(KshiftClientHandle client,
                                                 KshiftSlice sha256_hex_utf8,
                                                 KshiftBuffer *out_bytes);
KshiftStatus kshift_client_clear_attachment_cache(KshiftClientHandle client);

KshiftStatus kshift_client_list_projects(KshiftClientHandle client,
                                         uint64_t deadline_ms,
                                         KshiftCancelHandle cancel,
                                         KshiftBuffer *out_json);
KshiftStatus kshift_client_get_snapshot(KshiftClientHandle client,
                                         KshiftSlice project_id_utf8,
                                         uint64_t deadline_ms,
                                         KshiftCancelHandle cancel,
                                         KshiftBuffer *out_json);
KshiftStatus kshift_client_get_cached_snapshot(KshiftClientHandle client,
                                                KshiftSlice project_id_utf8,
                                                KshiftBuffer *out_json);
KshiftStatus kshift_client_execute_command(KshiftClientHandle client,
                                            KshiftSlice command_json,
                                            uint64_t deadline_ms,
                                            KshiftCancelHandle cancel,
                                            KshiftBuffer *out_json);

KshiftStatus kshift_client_watch_project(KshiftClientHandle client,
                                          KshiftSlice project_id_utf8,
                                          uint64_t since_revision,
                                          KshiftCancelHandle cancel,
                                          KshiftSubscriptionHandle *out_subscription);
/* Returns one JSON ClientEvent. timeout_ms=0 polls without waiting. */
KshiftStatus kshift_subscription_next(KshiftSubscriptionHandle subscription,
                                       uint64_t timeout_ms,
                                       KshiftBuffer *out_json);
KshiftStatus kshift_subscription_destroy(KshiftSubscriptionHandle subscription);

KshiftStatus kshift_cancel_token_create(KshiftCancelHandle *out_cancel);
KshiftStatus kshift_cancel_token_cancel(KshiftCancelHandle cancel);
KshiftStatus kshift_cancel_token_destroy(KshiftCancelHandle cancel);

/* The JSON projection of the most recent error on this thread. */
KshiftStatus kshift_last_error_json(KshiftBuffer *out_json);

/* Copy the JSON error projection. The caller must call kshift_buffer_free once. */
KshiftStatus kshift_buffer_free(KshiftBuffer *buffer);

const char *kshift_status_name(KshiftStatus status);

#ifdef __cplusplus
}
#endif

#endif
