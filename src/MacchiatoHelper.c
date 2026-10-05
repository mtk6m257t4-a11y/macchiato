#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static const char *daemonPath = "/Library/LaunchDaemons/local.codex.macchiato.closedlid.plist";
static const char *daemonTarget = "system/local.codex.macchiato.closedlid";
static const char *version = "1.5";
static const char daemonPlist[] =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
    "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
    "<plist version=\"1.0\"><dict>"
    "<key>Label</key><string>local.codex.macchiato.closedlid</string>"
    "<key>ProgramArguments</key><array>"
    "<string>/Library/PrivilegedHelperTools/MacchiatoHelper</string>"
    "<string>restore</string></array>"
    "<key>RunAtLoad</key><true/>"
    "</dict></plist>\n";

static int run(const char *path, char *const arguments[]) {
    pid_t pid = 0;
    int error = posix_spawn(&pid, path, NULL, NULL, arguments, environ);
    if (error != 0) {
        fprintf(stderr, "%s: %s\n", path, strerror(error));
        return 1;
    }
    int status = 0;
    while (waitpid(pid, &status, 0) < 0) {
        if (errno != EINTR) {
            perror("waitpid");
            return 1;
        }
    }
    return WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 0 : 1;
}

static int setSleepDisabled(int enabled) {
    char *arguments[] = {
        "/usr/bin/pmset", "-a", "disablesleep", enabled ? "1" : "0", NULL
    };
    return run(arguments[0], arguments);
}

static int bootout(void) {
    char *arguments[] = {"/bin/launchctl", "bootout", (char *)daemonTarget, NULL};
    return run(arguments[0], arguments);
}

static int bootstrap(void) {
    char *arguments[] = {"/bin/launchctl", "bootstrap", "system", (char *)daemonPath, NULL};
    return run(arguments[0], arguments);
}

static int writeDaemon(void) {
    char temporary[] = "/Library/LaunchDaemons/.macchiato.XXXXXX";
    int descriptor = mkstemp(temporary);
    if (descriptor < 0) {
        perror("mkstemp");
        return 1;
    }
    size_t remaining = sizeof(daemonPlist) - 1;
    const char *cursor = daemonPlist;
    while (remaining > 0) {
        ssize_t written = write(descriptor, cursor, remaining);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) {
            perror("write");
            close(descriptor);
            unlink(temporary);
            return 1;
        }
        cursor += written;
        remaining -= (size_t)written;
    }
    int preparationFailed = 0;
    if (fchown(descriptor, 0, 0) != 0) preparationFailed = 1;
    if (fchmod(descriptor, 0644) != 0) preparationFailed = 1;
    if (fsync(descriptor) != 0) preparationFailed = 1;
    if (close(descriptor) != 0) preparationFailed = 1;
    if (preparationFailed) {
        perror("prepare startup job");
        unlink(temporary);
        return 1;
    }
    if (rename(temporary, daemonPath) != 0) {
        perror("install startup job");
        unlink(temporary);
        return 1;
    }
    return 0;
}

static int turnOn(void) {
    if (writeDaemon() != 0) return 1;
    (void)bootout(); // A previous version may already have registered this label.
    if (bootstrap() != 0) {
        unlink(daemonPath);
        return 1;
    }
    if (setSleepDisabled(1) != 0) {
        (void)bootout();
        unlink(daemonPath);
        return 1;
    }
    return 0;
}

static int turnOff(void) {
    if (setSleepDisabled(0) != 0) return 1;
    (void)bootout();
    if (unlink(daemonPath) != 0 && errno != ENOENT) {
        perror("remove startup job");
        (void)setSleepDisabled(1);
        (void)bootstrap();
        return 1;
    }
    return 0;
}

int main(int argc, char *argv[]) {
    if (argc == 2 && strcmp(argv[1], "--version") == 0) {
        puts(version);
        return 0;
    }
    if (argc == 2 && strcmp(argv[1], "--print-plist") == 0) {
        fputs(daemonPlist, stdout);
        return 0;
    }
    if (geteuid() != 0) {
        fputs("Macchiato helper requires administrator authorization.\n", stderr);
        return 1;
    }
    if (argc != 2) {
        fputs("Usage: helper on|off|restore\n", stderr);
        return 1;
    }
    if (strcmp(argv[1], "on") == 0) return turnOn();
    if (strcmp(argv[1], "off") == 0) return turnOff();
    if (strcmp(argv[1], "restore") == 0) {
        struct stat information;
        if (lstat(daemonPath, &information) != 0 ||
            !S_ISREG(information.st_mode) || information.st_uid != 0) {
            fputs("No trusted Macchiato startup job found.\n", stderr);
            return 1;
        }
        return setSleepDisabled(1);
    }
    fputs("Unknown helper action.\n", stderr);
    return 1;
}
