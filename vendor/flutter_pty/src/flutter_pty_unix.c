
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include <errno.h>
#include <pthread.h>
#include <string.h>
#include <unistd.h>
#include <termios.h>
#include <sys/ioctl.h>
#include <sys/wait.h>

#include "forkpty.h"
#include "flutter_pty.h"

#include "include/dart_api.h"
#include "include/dart_api_dl.h"
#include "include/dart_native_api.h"

typedef struct WriteChunk
{
    struct WriteChunk *next;

    size_t length;

    char data[];

} WriteChunk;

typedef struct PtyHandle
{
    int ptm;

    int pid;

    pthread_mutex_t mutex;

    bool ackRead;

    /* 입력은 전용 스레드가 쓴다. Dart 스레드에서 write()가 막히면(자식이 입력을
     * 읽지 않아 tty 입력 큐가 가득 참) 호출한 isolate의 이벤트 루프 전체가 멈춘다. */
    pthread_mutex_t writeLock;

    pthread_cond_t writeReady;

    WriteChunk *writeHead;

    WriteChunk *writeTail;

    size_t writePending;

    bool writeClosed;

} PtyHandle;

typedef struct ReadLoopOptions
{
    int fd;

    pthread_mutex_t *mutex;

    Dart_Port port;

    bool waitForReadAck;

} ReadLoopOptions;

char *error_message = NULL;

static void *read_loop(void *arg)
{
    ReadLoopOptions *options = (ReadLoopOptions *)arg;

    char buffer[1024];

    while (1)
    {
        if (options->waitForReadAck)
        {
            // if we are in ack mode then we get a mutex here that is
            // freed again once the chunk of data has been processed
            pthread_mutex_lock(options->mutex);
        }
        ssize_t n = read(options->fd, buffer, sizeof(buffer));

        if (n < 0)
        {
            // TODO: handle error
            break;
        }

        if (n == 0)
        {
            break;
        }

        Dart_CObject result;
        result.type = Dart_CObject_kTypedData;
        result.value.as_typed_data.type = Dart_TypedData_kUint8;
        result.value.as_typed_data.length = n;
        result.value.as_typed_data.values = (uint8_t *)buffer;

        Dart_PostCObject_DL(options->port, &result);
    }

    return NULL;
}

static void start_read_thread(int fd, Dart_Port port, pthread_mutex_t *mutex, bool waitForReadAck)
{
    ReadLoopOptions *options = malloc(sizeof(ReadLoopOptions));

    options->fd = fd;

    options->port = port;

    options->mutex = mutex;

    options->waitForReadAck = waitForReadAck;

    pthread_t _thread;

    pthread_create(&_thread, NULL, &read_loop, options);
}

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

static void close_write_queue(PtyHandle *handle)
{
    pthread_mutex_lock(&handle->writeLock);
    handle->writeClosed = true;
    pthread_cond_signal(&handle->writeReady);
    pthread_mutex_unlock(&handle->writeLock);
}

static void *write_loop(void *arg)
{
    PtyHandle *handle = (PtyHandle *)arg;

    while (1)
    {
        pthread_mutex_lock(&handle->writeLock);
        while (handle->writeHead == NULL && !handle->writeClosed)
        {
            pthread_cond_wait(&handle->writeReady, &handle->writeLock);
        }
        if (handle->writeClosed)
        {
            drop_pending_writes(handle);
            pthread_mutex_unlock(&handle->writeLock);
            return NULL;
        }
        /* 머리 청크는 이 스레드만 꺼내므로 락 밖에서 써도 안전하다. */
        WriteChunk *chunk = handle->writeHead;
        pthread_mutex_unlock(&handle->writeLock);

        size_t offset = 0;
        bool failed = false;
        while (offset < chunk->length)
        {
            ssize_t n = write(handle->ptm, chunk->data + offset, chunk->length - offset);
            if (n < 0)
            {
                if (errno == EINTR)
                {
                    continue;
                }
                failed = true;
                break;
            }
            offset += (size_t)n;
        }

        pthread_mutex_lock(&handle->writeLock);
        handle->writeHead = chunk->next;
        if (handle->writeHead == NULL)
        {
            handle->writeTail = NULL;
        }
        handle->writePending -= chunk->length;
        if (failed)
        {
            handle->writeClosed = true;
        }
        pthread_mutex_unlock(&handle->writeLock);
        free(chunk);
    }
}

typedef struct WaitExitOptions
{
    int pid;

    Dart_Port port;

    PtyHandle *handle;

} WaitExitOptions;

static void *wait_exit_thread(void *arg)
{
    WaitExitOptions *options = (WaitExitOptions *)arg;

    int status;

    waitpid(options->pid, &status, 0);

    if (WIFEXITED(status))
    {
        Dart_PostInteger_DL(options->port, WEXITSTATUS(status));
    }
    else if (WIFSIGNALED(status))
    {
        Dart_PostInteger_DL(options->port, -WTERMSIG(status));
    }

    close_write_queue(options->handle);
    free(options);

    return NULL;
}

static void start_wait_exit_thread(int pid, Dart_Port port, PtyHandle *handle)
{
    WaitExitOptions *options = malloc(sizeof(WaitExitOptions));

    options->pid = pid;

    options->port = port;

    options->handle = handle;

    pthread_t _thread;

    pthread_create(&_thread, NULL, &wait_exit_thread, options);
}

static void set_environment(char **environment)
{
    // The child inherits the Flutter host process environment after forkpty.
    // Development hosts such as Codex may set NO_COLOR/FORCE_COLOR for their
    // own output; leaking those controls into an interactive shell makes TUIs
    // such as Claude Code incorrectly select a monochrome renderer. Remove the
    // inherited policy first. Explicit entries supplied by the caller below
    // can still opt back into either variable.
    unsetenv("NO_COLOR");
    unsetenv("FORCE_COLOR");

    if (environment == NULL)
    {
        return;
    }

    while (*environment != NULL)
    {
        putenv(*environment);
        environment++;
    }
}

FFI_PLUGIN_EXPORT PtyHandle *pty_create(PtyOptions *options)
{
    struct winsize ws;

    ws.ws_row = options->rows;
    ws.ws_col = options->cols;

    int ptm;

    int pid = pty_forkpty(&ptm, NULL, NULL, &ws);

    if (pid < 0)
    {
        error_message = "pty_forkpty failed";
        perror("pty_forkpty");
        return NULL;
    }

    if (pid == 0)
    {
        set_environment(options->environment);

        if (options->working_directory != NULL && strlen(options->working_directory) > 0)
        {
            chdir(options->working_directory);
        }

        int ok = execvp(options->executable, options->arguments);

        if (ok < 0)
        {
            perror("execvp");
        }
    }

    PtyHandle *handle = (PtyHandle *)malloc(sizeof(PtyHandle));

    handle->ptm = ptm;
    handle->pid = pid;
    pthread_mutex_init(&handle->mutex, NULL);
    handle->ackRead = options->ackRead;

    pthread_mutex_init(&handle->writeLock, NULL);
    pthread_cond_init(&handle->writeReady, NULL);
    handle->writeHead = NULL;
    handle->writeTail = NULL;
    handle->writePending = 0;
    handle->writeClosed = false;

    pthread_t writer;
    if (pthread_create(&writer, NULL, &write_loop, handle) == 0)
    {
        pthread_detach(writer);
    }
    else
    {
        handle->writeClosed = true;
    }

    start_read_thread(ptm, options->stdout_port, &handle->mutex, options->ackRead);

    start_wait_exit_thread(pid, options->exit_port, handle);

    return handle;
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
    chunk->length = (size_t)length;
    memcpy(chunk->data, buffer, (size_t)length);

    pthread_mutex_lock(&handle->writeLock);
    int status = PTY_WRITE_QUEUED;
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
        pthread_cond_signal(&handle->writeReady);
    }
    pthread_mutex_unlock(&handle->writeLock);

    if (status != PTY_WRITE_QUEUED)
    {
        free(chunk);
    }
    return status;
}

FFI_PLUGIN_EXPORT void pty_ack_read(PtyHandle *handle)
{
    if (handle->ackRead)
    {
        // frees the mutex so that the next chunk of data can be read
        pthread_mutex_unlock(&handle->mutex);
    }
}

FFI_PLUGIN_EXPORT int pty_resize(PtyHandle *handle, int rows, int cols)
{
    struct winsize ws;

    ws.ws_row = rows;
    ws.ws_col = cols;

    return ioctl(handle->ptm, TIOCSWINSZ, &ws);
}

FFI_PLUGIN_EXPORT int pty_getpid(PtyHandle *handle)
{
    return handle->pid;
}

FFI_PLUGIN_EXPORT char *pty_error(void)
{
    return NULL;
}
