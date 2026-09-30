#ifndef SUTRA_FFI_H
#define SUTRA_FFI_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SutraDbHandle SutraDbHandle;

/// Opens or creates the SQLite database at the specified path.
SutraDbHandle* sutra_db_open(const char* path);

/// Closes and frees a SutraDbHandle.
void sutra_db_close(SutraDbHandle* handle);

/// Captures a new thread and persists it into the SQLite database.
/// Returns thread JSON (must be freed with sutra_free_string).
char* sutra_capture(
    SutraDbHandle* handle,
    const char* title,
    const char* notes,
    const char* cue_type,
    const char* app_name,
    const char* url,
    const char* file_path,
    int32_t line_number,
    int64_t due_at
);

/// Lists threads with optional status filter ("waiting", "later", "done", or NULL for all).
/// Returns JSON array string (must be freed with sutra_free_string).
char* sutra_list(SutraDbHandle* handle, const char* status);

/// Searches threads using the embedded SQLite FTS5 index.
/// Returns JSON array string (must be freed with sutra_free_string).
char* sutra_search(SutraDbHandle* handle, const char* query);

/// Updates the status of a thread ("waiting", "later", "done").
/// Returns 0 on success, -1 on failure.
int32_t sutra_update_status(SutraDbHandle* handle, const char* id, const char* new_status);

/// Snoozes a thread for the given number of hours.
/// Returns 0 on success, -1 on failure.
int32_t sutra_snooze(SutraDbHandle* handle, const char* id, int64_t hours);

/// Frees a string returned by any sutra_* function.
void sutra_free_string(char* ptr);

#ifdef __cplusplus
}
#endif

#endif /* SUTRA_FFI_H */
