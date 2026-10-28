//
//  QemuBridge.h
//  JITerm
//
//  Тонкая C-обёртка над QEMU, собранным как динамическая библиотека
//  (qemu-aarch64-softmmu.framework из UTM): загрузка через dlopen,
//  запуск в отдельном потоке, перехват exit() и проверка JIT.
//

#ifndef QemuBridge_h
#define QemuBridge_h

#include <stdbool.h>
#include <stddef.h>

typedef void (*jt_qemu_exit_cb)(int status, void *ctx);

/// Загружает библиотеку QEMU и запускает её в отдельном потоке.
/// argv[0] должен содержать имя программы. Колбэк вызывается из потока QEMU
/// после завершения (status == 0 — штатное выключение).
/// Возвращает 0 при успехе, иначе -1 и текст ошибки в errbuf.
int jt_qemu_start(const char *dylib_path, int argc, const char *const *argv,
                  jt_qemu_exit_cb cb, void *ctx, char *errbuf, size_t errlen);

/// true, если QEMU уже запускался в этом процессе (повторный запуск невозможен).
bool jt_qemu_was_started(void);

/// true, если процессу разрешено выполнять JIT-код (подключён отладчик, CS_DEBUGGED).
bool jt_jit_enabled(void);

/// Перенаправляет stdout/stderr процесса в файл (журнал QEMU).
bool jt_redirect_stdio(const char *path);

#endif /* QemuBridge_h */
