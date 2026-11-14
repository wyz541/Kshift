#ifndef KSHIFT_FFI_H
#define KSHIFT_FFI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct KshiftClientHandle KshiftClientHandle;

uint32_t kshift_ffi_schema_version(void);
KshiftClientHandle *kshift_client_new(void);
void kshift_client_free(KshiftClientHandle *handle);
char *kshift_client_projects_json(const KshiftClientHandle *handle);
char *kshift_client_snapshot_json(
    const KshiftClientHandle *handle,
    const char *project_id
);
char *kshift_client_execute_json(
    KshiftClientHandle *handle,
    const char *project_id,
    const char *request_json
);
void kshift_string_free(char *value);

#ifdef __cplusplus
}
#endif

#endif
