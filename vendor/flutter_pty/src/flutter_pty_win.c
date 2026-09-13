#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <Windows.h>

#include "flutter_pty.h"

#include "include/dart_api.h"
#include "include/dart_api_dl.h"
#include "include/dart_native_api.h"

static BOOL argument_requires_quotes(const WCHAR *argument)
{
    if (argument[0] == 0)
    {
        return TRUE;
    }
    while (*argument != 0)
    {
        if (*argument == L' ' || *argument == L'\t' || *argument == L'\n' ||
            *argument == L'\v' || *argument == L'"')
        {
            return TRUE;
        }
        argument++;
    }
    return FALSE;
}

static WCHAR *append_quoted_argument(WCHAR *output, const WCHAR *argument)
{
    if (!argument_requires_quotes(argument))
    {
        while (*argument != 0)
        {
            *output++ = *argument++;
        }
        return output;
    }

    *output++ = L'"';
    int backslashes = 0;
    while (*argument != 0)
    {
        if (*argument == L'\\')
        {
            backslashes++;
            argument++;
            continue;
        }
        if (*argument == L'"')
        {
            for (int i = 0; i < backslashes * 2 + 1; i++)
            {
                *output++ = L'\\';
            }
            *output++ = *argument++;
            backslashes = 0;
            continue;
        }
        for (int i = 0; i < backslashes; i++)
        {
            *output++ = L'\\';
        }
        backslashes = 0;
        *output++ = *argument++;
    }
    for (int i = 0; i < backslashes * 2; i++)
    {
        *output++ = L'\\';
    }
    *output++ = L'"';
    return output;
}

static LPWSTR utf8_to_wide(const char *value, int *length)
{
    int required = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, NULL, 0);
    if (required == 0)
    {
        return NULL;
    }
    LPWSTR result = malloc(required * sizeof(WCHAR));
    if (result == NULL)
    {
        return NULL;
    }
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, result, required) == 0)
    {
        free(result);
        return NULL;
    }
    *length = required - 1;
    return result;
}

static LPWSTR build_command(char *executable, char **arguments)
{
    int argument_count = 0;
    if (arguments != NULL)
    {
        while (arguments[argument_count] != NULL)
        {
            argument_count++;
        }
    }
    if (argument_count == 0 && executable == NULL)
    {
        return NULL;
    }

    size_t command_capacity = 1;
    for (int i = 0; i < (argument_count == 0 ? 1 : argument_count); i++)
    {
        const char *argument = argument_count == 0 ? executable : arguments[i];
        int wide_length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, argument, -1, NULL, 0);
        if (wide_length == 0)
        {
            return NULL;
        }
        command_capacity += (size_t)(wide_length - 1) * 2 + 3;
    }

    LPWSTR command = malloc(command_capacity * sizeof(WCHAR));
    if (command == NULL)
    {
        return NULL;
    }

    WCHAR *cursor = command;
    for (int i = 0; i < (argument_count == 0 ? 1 : argument_count); i++)
    {
        const char *argument = argument_count == 0 ? executable : arguments[i];
        int wide_length = 0;
        LPWSTR wide_argument = utf8_to_wide(argument, &wide_length);
        if (wide_argument == NULL)
        {
            free(command);
            return NULL;
        }
        if (cursor != command)
        {
            *cursor++ = L' ';
        }
        cursor = append_quoted_argument(cursor, wide_argument);
        free(wide_argument);
    }
    *cursor = 0;

    return command;
}

static LPWSTR build_environment(char **environment)
{
    size_t block_length = 1;
    if (environment != NULL)
    {
        for (int i = 0; environment[i] != NULL; i++)
        {
            int required = MultiByteToWideChar(
                CP_UTF8, MB_ERR_INVALID_CHARS, environment[i], -1, NULL, 0);
            if (required == 0 || block_length > SIZE_MAX - (size_t)required)
            {
                return NULL;
            }
            block_length += (size_t)required;
        }
    }

    LPWSTR environment_block = malloc(block_length * sizeof(WCHAR));
    if (environment_block == NULL)
    {
        return NULL;
    }

    LPWSTR cursor = environment_block;
    if (environment != NULL)
    {
        for (int i = 0; environment[i] != NULL; i++)
        {
            int required = MultiByteToWideChar(
                CP_UTF8, MB_ERR_INVALID_CHARS, environment[i], -1, NULL, 0);
            if (required == 0 ||
                MultiByteToWideChar(
                    CP_UTF8,
                    MB_ERR_INVALID_CHARS,
                    environment[i],
                    -1,
                    cursor,
                    required) == 0)
            {
                free(environment_block);
                return NULL;
            }
            cursor += required;
        }
    }
    *cursor = 0;
    return environment_block;
}

static LPWSTR build_working_directory(char *working_directory)
{
    if (working_directory == NULL)
    {
        return NULL;
    }

    int working_directory_length = 0;
    return utf8_to_wide(working_directory, &working_directory_length);
}

typedef struct ReadLoopOptions
{
    HANDLE fd;

    Dart_Port port;

    HANDLE hMutex;

    BOOL ackRead;

} ReadLoopOptions;

static DWORD WINAPI read_loop(LPVOID arg)
{
    ReadLoopOptions *options = (ReadLoopOptions *)arg;

    char buffer[1024];

    while (1)
    {
        DWORD readlen = 0;

        if (options->ackRead)
        {
            WaitForSingleObject(options->hMutex, INFINITE);
        }

        BOOL ok = ReadFile(options->fd, buffer, sizeof(buffer), &readlen, NULL);

        if (!ok)
        {
            break;
        }

        if (readlen <= 0)
        {
            break;
        }

        Dart_CObject result;
        result.type = Dart_CObject_kTypedData;
        result.value.as_typed_data.type = Dart_TypedData_kUint8;
        result.value.as_typed_data.length = readlen;
        result.value.as_typed_data.values = (uint8_t *)buffer;

        Dart_PostCObject_DL(options->port, &result);
    }

    return 0;
}

static void start_read_thread(HANDLE fd, Dart_Port port, HANDLE mutex, BOOL ackRead)
{
    ReadLoopOptions *options = malloc(sizeof(ReadLoopOptions));

    options->fd = fd;
    options->port = port;
    options->hMutex = mutex;
    options->ackRead = ackRead;

    DWORD thread_id;

    HANDLE thread = CreateThread(NULL, 0, read_loop, options, 0, &thread_id);

    if (thread == NULL)
    {
        free(options);
    }
}

typedef struct WaitExitOptions
{
    HANDLE pid;

    Dart_Port port;

    HANDLE hMutex;
} WaitExitOptions;

static DWORD WINAPI wait_exit_thread(LPVOID arg)
{
    WaitExitOptions *options = (WaitExitOptions *)arg;

    DWORD exit_code = 0;

    WaitForSingleObject(options->pid, INFINITE);

    GetExitCodeProcess(options->pid, &exit_code);

    CloseHandle(options->pid);
    CloseHandle(options->hMutex);

    Dart_PostInteger_DL(options->port, exit_code);

    return 0;
}

static void start_wait_exit_thread(HANDLE pid, Dart_Port port, HANDLE mutex)
{
    WaitExitOptions *options = malloc(sizeof(WaitExitOptions));

    options->pid = pid;
    options->port = port;
    options->hMutex = mutex;

    DWORD thread_id;

    HANDLE thread = CreateThread(NULL, 0, wait_exit_thread, options, 0, &thread_id);

    if (thread == NULL)
    {
        free(options);
    }
}

typedef struct PtyHandle
{
    PHANDLE inputWriteSide;

    PHANDLE outputReadSide;

    HPCON hPty;

    DWORD dwProcessId;

    BOOL ackRead;

    HANDLE hMutex;

} PtyHandle;

char *error_message = NULL;

FFI_PLUGIN_EXPORT PtyHandle *pty_create(PtyOptions *options)
{
    HANDLE inputReadSide = NULL;
    HANDLE inputWriteSide = NULL;

    HANDLE outputReadSide = NULL;
    HANDLE outputWriteSide = NULL;

    if (!CreatePipe(&inputReadSide, &inputWriteSide, NULL, 0))
    {
        error_message = "Failed to create input pipe";
        return NULL;
    }

    if (!CreatePipe(&outputReadSide, &outputWriteSide, NULL, 0))
    {
        error_message = "Failed to create output pipe";
        return NULL;
    }

    COORD size;

    size.X = options->cols;
    size.Y = options->rows;

    HPCON hPty;

    HRESULT result = CreatePseudoConsole(size, inputReadSide, outputWriteSide, 0, &hPty);

    if (FAILED(result))
    {
        error_message = "Failed to create pseudo console";
        return NULL;
    }

    STARTUPINFOEX startupInfo;

    ZeroMemory(&startupInfo, sizeof(startupInfo));
    startupInfo.StartupInfo.cb = sizeof(startupInfo);

    startupInfo.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    startupInfo.StartupInfo.hStdInput = NULL;
    startupInfo.StartupInfo.hStdOutput = NULL;
    startupInfo.StartupInfo.hStdError = NULL;

    SIZE_T bytesRequired;
    InitializeProcThreadAttributeList(NULL, 1, 0, &bytesRequired);
    startupInfo.lpAttributeList = (PPROC_THREAD_ATTRIBUTE_LIST)malloc(bytesRequired);

    BOOL ok = InitializeProcThreadAttributeList(startupInfo.lpAttributeList, 1, 0, &bytesRequired);

    if (!ok)
    {
        error_message = "Failed to initialize proc thread attribute list";
        return NULL;
    }

    ok = UpdateProcThreadAttribute(startupInfo.lpAttributeList,
                                   0,
                                   PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
                                   hPty,
                                   sizeof(hPty),
                                   NULL,
                                   NULL);

    if (!ok)
    {
        error_message = "Failed to update proc thread attribute list";
        return NULL;
    }

    LPWSTR command = build_command(options->executable, options->arguments);

    LPWSTR environment_block = build_environment(options->environment);

    LPWSTR working_directory = build_working_directory(options->working_directory);

    PROCESS_INFORMATION processInfo;
    ZeroMemory(&processInfo, sizeof(processInfo));

    Sleep(1000);

    ok = CreateProcessW(NULL,
                        command,
                        NULL,
                        NULL,
                        FALSE,
                        EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
                        environment_block,
                        working_directory,
                        &startupInfo.StartupInfo,
                        &processInfo);

    if (command != NULL)
    {
        free(command);
    }

    if (environment_block != NULL)
    {
        free(environment_block);
    }

    if (working_directory != NULL)
    {
        free(working_directory);
    }

    if (!ok)
    {
        error_message = "Failed to create process";
        DWORD error = GetLastError();
        printf("error no: %d\n", error);
        return NULL;
    }

    // free(startupInfo.lpAttributeList);

    // CloseHandle(processInfo.hThread);

    HANDLE mutex = CreateSemaphore(
        NULL, // default security attributes
        1,    // initial count
        1,    // maximum count
        NULL);

    start_read_thread(outputReadSide, options->stdout_port, mutex, options->ackRead);

    start_wait_exit_thread(processInfo.hProcess, options->exit_port, mutex);

    PtyHandle *pty = malloc(sizeof(PtyHandle));

    if (pty == NULL)
    {
        error_message = "Failed to allocate pty handle";
        return NULL;
    }

    pty->inputWriteSide = inputWriteSide;
    pty->outputReadSide = outputReadSide;
    pty->hPty = hPty;
    pty->dwProcessId = processInfo.dwProcessId;
    pty->ackRead = options->ackRead;
    pty->hMutex = mutex;

    return pty;
}

FFI_PLUGIN_EXPORT void pty_write(PtyHandle *handle, char *buffer, int length)
{
    DWORD bytesWritten;

    WriteFile(handle->inputWriteSide, buffer, length, &bytesWritten, NULL);

    FlushFileBuffers(handle->inputWriteSide);

    return;
}

FFI_PLUGIN_EXPORT void pty_ack_read(PtyHandle *handle)
{
    if (handle->ackRead)
    {
        ReleaseSemaphore(handle->hMutex, 1, NULL);
    }
}

FFI_PLUGIN_EXPORT int pty_resize(PtyHandle *handle, int rows, int cols)
{
    COORD size;

    size.X = cols;
    size.Y = rows;

    return ResizePseudoConsole(handle->hPty, size);
}

FFI_PLUGIN_EXPORT int pty_getpid(PtyHandle *handle)
{
    return (int)handle->dwProcessId;
}

FFI_PLUGIN_EXPORT char *pty_error()
{
    return error_message;
}
