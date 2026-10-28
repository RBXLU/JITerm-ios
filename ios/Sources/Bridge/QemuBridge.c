//
//  QemuBridge.c
//  JITerm
//

#include "QemuBridge.h"

#include <TargetConditionals.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <pthread.h>
#include <pthread/qos.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// Сигнатуры из форка QEMU от UTM (см. UTM/Services/UTMQemuSystem.m)
typedef int (*qemu_init_fn)(int argc, const char *argv[], const char *envp[]);
typedef void (*qemu_main_loop_fn)(void);
typedef void (*qemu_cleanup_fn)(void);

extern char **environ;
extern int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);

#define CS_OPS_STATUS 0
#define CS_DEBUGGED   0x10000000

static struct {
    qemu_init_fn init;
    qemu_main_loop_fn main_loop;
    qemu_cleanup_fn cleanup;
    int argc;
    char **argv;
    jt_qemu_exit_cb cb;
    void *ctx;
    pthread_t thread;
    volatile bool started;
} g_qemu;

static void report_exit(int status) {
    jt_qemu_exit_cb cb = g_qemu.cb;
    g_qemu.cb = NULL;
    if (cb) {
        cb(status, g_qemu.ctx);
    }
}

// QEMU при фатальных ошибках вызывает exit(). Чтобы не убить всё приложение,
// завершаем только поток QEMU (тот же приём использует UTM).
static void exit_trap(void) {
    if (g_qemu.started && pthread_equal(pthread_self(), g_qemu.thread)) {
        fflush(stdout);
        fflush(stderr);
        report_exit(-1);
        pthread_exit(NULL);
    }
}

static void *qemu_thread_main(void *unused) {
    (void)unused;
    int ret = g_qemu.init(g_qemu.argc, (const char **)g_qemu.argv, (const char **)environ);
    if (ret == 0) {
        g_qemu.main_loop();
        g_qemu.cleanup();
    }
    fflush(stdout);
    fflush(stderr);
    report_exit(ret);
    return NULL;
}

static void set_error(char *errbuf, size_t errlen, const char *msg) {
    if (errbuf && errlen > 0) {
        snprintf(errbuf, errlen, "%s", msg ? msg : "unknown error");
    }
}

int jt_qemu_start(const char *dylib_path, int argc, const char *const *argv,
                  jt_qemu_exit_cb cb, void *ctx, char *errbuf, size_t errlen) {
    if (g_qemu.started) {
        set_error(errbuf, errlen, "QEMU уже запускался в этом процессе. Перезапустите приложение.");
        return -1;
    }
    void *handle = dlopen(dylib_path, RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        set_error(errbuf, errlen, dlerror());
        return -1;
    }
    g_qemu.init = (qemu_init_fn)dlsym(handle, "qemu_init");
    g_qemu.main_loop = (qemu_main_loop_fn)dlsym(handle, "qemu_main_loop");
    g_qemu.cleanup = (qemu_cleanup_fn)dlsym(handle, "qemu_cleanup");
    if (!g_qemu.init || !g_qemu.main_loop || !g_qemu.cleanup) {
        set_error(errbuf, errlen, "в библиотеке QEMU нет qemu_init/qemu_main_loop/qemu_cleanup");
        return -1;
    }

    g_qemu.argc = argc;
    g_qemu.argv = calloc((size_t)argc + 1, sizeof(char *));
    for (int i = 0; i < argc; i++) {
        g_qemu.argv[i] = strdup(argv[i]);
    }
    g_qemu.cb = cb;
    g_qemu.ctx = ctx;

    static bool trap_installed = false;
    if (!trap_installed) {
        atexit(exit_trap);
        trap_installed = true;
    }

    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, 8 * 1024 * 1024);
    pthread_attr_set_qos_class_np(&attr, QOS_CLASS_USER_INTERACTIVE, 0);
    g_qemu.started = true;
    int err = pthread_create(&g_qemu.thread, &attr, qemu_thread_main, NULL);
    pthread_attr_destroy(&attr);
    if (err != 0) {
        g_qemu.started = false;
        set_error(errbuf, errlen, strerror(err));
        return -1;
    }
    pthread_detach(g_qemu.thread);
    return 0;
}

bool jt_qemu_was_started(void) {
    return g_qemu.started;
}

bool jt_jit_enabled(void) {
#if TARGET_OS_SIMULATOR
    return true;
#else
    int flags = 0;
    if (csops(getpid(), CS_OPS_STATUS, &flags, sizeof(flags)) != 0) {
        return false;
    }
    return (flags & CS_DEBUGGED) != 0;
#endif
}

bool jt_redirect_stdio(const char *path) {
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) {
        return false;
    }
    setvbuf(stdout, NULL, _IOLBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    dup2(fd, STDOUT_FILENO);
    dup2(fd, STDERR_FILENO);
    close(fd);
    return true;
}
