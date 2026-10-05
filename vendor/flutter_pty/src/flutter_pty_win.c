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

    CloseHandle(options->fd);
    free(options);
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
    else
    {
        CloseHandle(thread);
    }
}

typedef enum WriteKind
{
    WRITE_DATA,
    WRITE_RESIZE,
} WriteKind;

typedef struct WriteChunk
{
    struct WriteChunk *next;

    WriteKind kind;

    COORD size;

    DWORD length;

    char data[];

} WriteChunk;

typedef struct PtyHandle
{
    HPCON hPty;

    DWORD dwProcessId;

    BOOL ackRead;

    HANDLE hMutex;

    /* 입력과 resize는 전용 스레드가 처리한다. Dart 스레드에서 WriteFile이나
     * ResizePseudoConsole이 conhost를 기다리며 막히면 호출한 isolate의
     * 이벤트 루프 전체가 멈춘다(로컬 데몬이 ping에도 응답하지 못함). */
    HANDLE inputPipe;

    HANDLE writerThread;

    CRITICAL_SECTION writeLock;

    CONDITION_VARIABLE writeReady;

    WriteChunk *writeHead;

    WriteChunk *writeTail;

    SIZE_T writePending;

    BOOL writeClosed;

} PtyHandle;

static void drop_pending_writes(PtyHandle *handle)
{
    WriteChunk *chunk = handle->writeHead;
    handle->writeHead = NULL;
    handle->writeTail = NULL;
    handle->writePending = 0;
    while (chunk != NULL)
    {
        WriteChunk *next = chunk->next;
        free(chunk);
        chunk = next;
    }
}

static DWORD WINAPI write_loop(LPVOID arg)
{
    PtyHandle *handle = (PtyHandle *)arg;

    while (1)
    {
        EnterCriticalSection(&handle->writeLock);
        while (handle->writeHead == NULL && !handle->writeClosed)
        {
            SleepConditionVariableCS(&handle->writeReady, &handle->writeLock, INFINITE);
        }
        if (handle->writeClosed)
        {
            drop_pending_writes(handle);
            LeaveCriticalSection(&handle->writeLock);
            return 0;
        }
        /* 머리 청크는 이 스레드만 꺼내므로 락 밖에서 처리해도 안전하다. */
        WriteChunk *chunk = handle->writeHead;
        LeaveCriticalSection(&handle->writeLock);

        BOOL failed = FALSE;
        if (chunk->kind == WRITE_RESIZE)
        {
            ResizePseudoConsole(handle->hPty, chunk->size);
        }
        else
        {
            DWORD offset = 0;
            while (offset < chunk->length)
            {
                DWORD written = 0;
                if (!WriteFile(handle->inputPipe, chunk->data + offset, chunk->length - offset, &written, NULL) ||
                    written == 0)
                {
                    failed = TRUE;
                    break;
                }
                offset += written;
            }
        }

        EnterCriticalSection(&handle->writeLock);
        handle->writeHead = chunk->next;
        if (handle->writeHead == NULL)
        {
            handle->writeTail = NULL;
        }
        handle->writePending -= chunk->length;
        if (failed)
        {
            handle->writeClosed = TRUE;
        }
        LeaveCriticalSection(&handle->writeLock);
        free(chunk);
    }
}

static int enqueue_write(PtyHandle *handle, WriteChunk *chunk)
{
    int status = PTY_WRITE_QUEUED;
    EnterCriticalSection(&handle->writeLock);
    if (handle->writeClosed)
    {
        status = PTY_WRITE_CLOSED;
    }
    else if (handle->writePending + chunk->length > PTY_WRITE_QUEUE_LIMIT)
    {
        status = PTY_WRITE_FULL;
    }
    else
    {
        if (handle->writeTail == NULL)
        {
            handle->writeHead = chunk;
        }
        else
        {
            handle->writeTail->next = chunk;
        }
        handle->writeTail = chunk;
        handle->writePending += chunk->length;
        WakeConditionVariable(&handle->writeReady);
    }
    LeaveCriticalSection(&handle->writeLock);

    if (status != PTY_WRITE_QUEUED)
    {
        free(chunk);
    }
    return status;
}

/* 자식 종료 뒤 PTY 자원을 정리한다. 입력 스레드가 WriteFile에 막혀 있을 수
 * 있으므로 끝날 때까지 동기 I/O를 취소한 뒤 의사 콘솔(conhost)을 닫는다.
 * 의사 콘솔이 닫히면 출력 파이프가 끊겨 읽기 스레드도 끝난다. */
static void release_pty(PtyHandle *handle)
{
    EnterCriticalSection(&handle->writeLock);
    handle->writeClosed = TRUE;
    WakeConditionVariable(&handle->writeReady);
    LeaveCriticalSection(&handle->writeLock);

    if (handle->writerThread != NULL)
    {
        while (WaitForSingleObject(handle->writerThread, 100) == WAIT_TIMEOUT)
        {
            CancelSynchronousIo(handle->writerThread);
        }
        CloseHandle(handle->writerThread);
        handle->writerThread = NULL;
    }

    ClosePseudoConsole(handle->hPty);
    CloseHandle(handle->inputPipe);
}

typedef struct WaitExitOptions
{
    HANDLE pid;
    HANDLE job;

    Dart_Port port;

    PtyHandle *handle;
} WaitExitOptions;

static DWORD WINAPI wait_exit_thread(LPVOID arg)
{
    WaitExitOptions *options = (WaitExitOptions *)arg;

    DWORD exit_code = 0;

    WaitForSingleObject(options->pid, INFINITE);

    GetExitCodeProcess(options->pid, &exit_code);

    CloseHandle(options->job); /* KILL_ON_JOB_CLOSE also terminates descendants. */
    CloseHandle(options->pid);

    Dart_PostInteger_DL(options->port, exit_code);

    release_pty(options->handle);

    free(options);
    return 0;
}

static void start_wait_exit_thread(HANDLE pid, Dart_Port port, HANDLE job, PtyHandle *handle)
{
    WaitExitOptions *options = malloc(sizeof(WaitExitOptions));

    options->pid = pid;
    options->job = job;
    options->port = port;
    options->handle = handle;

    DWORD thread_id;

    HANDLE thread = CreateThread(NULL, 0, wait_exit_thread, options, 0, &thread_id);

    if (thread == NULL)
    {
        free(options);
    }
    else
    {
        CloseHandle(thread);
    }
}

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

    /* conhost가 PTY 쪽 파이프 끝을 복제해 가지므로 우리 사본은 바로 닫는다.
     * 쥐고 있으면 conhost가 끝나도 출력 파이프가 끊기지 않아 읽기 스레드가
     * 영원히 ReadFile에서 기다린다. */
    CloseHandle(inputReadSide);
    CloseHandle(outputWriteSide);

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
                        EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT | CREATE_SUSPENDED,
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
        ClosePseudoConsole(hPty);
        CloseHandle(inputWriteSide);
        CloseHandle(outputReadSide);
        return NULL;
    }

    HANDLE job = CreateJobObjectW(NULL, NULL);
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits;
    ZeroMemory(&limits, sizeof(limits));
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (job == NULL ||
        !SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof(limits)) ||
        !AssignProcessToJobObject(job, processInfo.hProcess))
    {
        TerminateProcess(processInfo.hProcess, 1);
        CloseHandle(processInfo.hThread);
        CloseHandle(processInfo.hProcess);
        if (job != NULL) CloseHandle(job);
        ClosePseudoConsole(hPty);
        CloseHandle(inputWriteSide);
        CloseHandle(outputReadSide);
        error_message = "Failed to assign PTY process to owned Job Object";
        return NULL;
    }
    if (ResumeThread(processInfo.hThread) == (DWORD)-1)
    {
        CloseHandle(job);
        CloseHandle(processInfo.hThread);
        CloseHandle(processInfo.hProcess);
        ClosePseudoConsole(hPty);
        CloseHandle(inputWriteSide);
        CloseHandle(outputReadSide);
        error_message = "Failed to resume owned PTY process";
        return NULL;
    }
    CloseHandle(processInfo.hThread);

    HANDLE mutex = CreateSemaphore(
        NULL, // default security attributes
        1,    // initial count
        1,    // maximum count
        NULL);

    PtyHandle *pty = malloc(sizeof(PtyHandle));

    if (pty == NULL)
    {
        /* 출력/종료 스레드 없이 자식을 남기지 않도록 job을 닫아 종료시킨다. */
        CloseHandle(job);
        CloseHandle(processInfo.hProcess);
        ClosePseudoConsole(hPty);
        CloseHandle(inputWriteSide);
        CloseHandle(outputReadSide);
        error_message = "Failed to allocate pty handle";
        return NULL;
    }

    pty->hPty = hPty;
    pty->dwProcessId = processInfo.dwProcessId;
    pty->ackRead = options->ackRead;
    pty->hMutex = mutex;
    pty->inputPipe = inputWriteSide;
    InitializeCriticalSection(&pty->writeLock);
    InitializeConditionVariable(&pty->writeReady);
    pty->writeHead = NULL;
    pty->writeTail = NULL;
    pty->writePending = 0;
    pty->writeClosed = FALSE;

    DWORD writer_id;
    pty->writerThread = CreateThread(NULL, 0, write_loop, pty, 0, &writer_id);
    if (pty->writerThread == NULL)
    {
        pty->writeClosed = TRUE;
    }

    start_read_thread(outputReadSide, options->stdout_port, mutex, options->ackRead);

    start_wait_exit_thread(processInfo.hProcess, options->exit_port, job, pty);

    return pty;
}

FFI_PLUGIN_EXPORT int pty_write(PtyHandle *handle, char *buffer, int length)
{
    if (length <= 0)
    {
        return PTY_WRITE_QUEUED;
    }

    WriteChunk *chunk = malloc(sizeof(WriteChunk) + (size_t)length);
    if (chunk == NULL)
    {
        return PTY_WRITE_FULL;
    }
    chunk->next = NULL;
    chunk->kind = WRITE_DATA;
    chunk->length = (DWORD)length;
    memcpy(chunk->data, buffer, (size_t)length);
    return enqueue_write(handle, chunk);
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
    WriteChunk *chunk = malloc(sizeof(WriteChunk));
    if (chunk == NULL)
    {
        return -1;
    }
    chunk->next = NULL;
    chunk->kind = WRITE_RESIZE;
    chunk->size.X = (SHORT)cols;
    chunk->size.Y = (SHORT)rows;
    chunk->length = 0;
    return enqueue_write(handle, chunk) == PTY_WRITE_QUEUED ? 0 : -1;
}

FFI_PLUGIN_EXPORT int pty_getpid(PtyHandle *handle)
{
    return (int)handle->dwProcessId;
}

FFI_PLUGIN_EXPORT char *pty_error()
{
    return error_message;
}
