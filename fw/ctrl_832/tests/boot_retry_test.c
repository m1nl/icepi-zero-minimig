/* Exercise the production main loop with failed SD/mount attempts and UI retries. */
#include <assert.h>
#include <setjmp.h>
#include <stdio.h>

#include "../hardware.h"

#undef PLATFORM
#define PLATFORM 0
#undef HW_SPI
static volatile unsigned char spi_registers[16];
#define HW_SPI(x) spi_registers[x]

#define INTERRUPTS_H
#define AUX_SPI_H
static void (*interrupt_handler)(void);
static int interrupts_enabled, ui_active;
static void DisableInterrupts(void) { interrupts_enabled = 0; }
static void EnableInterrupts(void) {
    assert(interrupt_handler != NULL);
    interrupts_enabled = 1;
}
static void SetIntHandler(void (*handler)(void)) {
    DisableInterrupts();
    interrupt_handler = handler;
}
static int AckInterrupt(void) { return 0; }

#define main firmware_main
#include "../main.c"
#undef main

#define SD_FAILURES 128
static jmp_buf finished;
static unsigned int attempts, completed_boots, ui_calls, error_pages, disk_calls;
static int guest_held;
static int space_down;
static unsigned int video_restores;
configTYPE config;
int ErrorMask, ErrorFatal;

void setstack(void) {}
void ClearError(int category) {
    assert(category == ERROR_ALL || category == ERROR_FILESYSTEM);
    if (category == ERROR_ALL) ErrorMask = ErrorFatal = 0;
    else ErrorMask &= ~(1 << category);
}
void FatalError(int category, const char *message, int a, int b) {
    (void)message; (void)a; (void)b;
    ErrorMask |= 1 << category;
    ErrorFatal = 1;
}
void OsdDoReset(int enter, int leave) {
    (void)enter;
    guest_held = !!(leave & SPI_CPU_HLT);
    if (!guest_held && completed_boots == 5)
        assert(config.video_mode == 0 && video_restores == 3);
}
unsigned char MMC_Init(void) {
    assert(!ui_active && guest_held && !interrupts_enabled);
    assert(interrupt_handler != NULL);
    ++attempts;
    if (attempts <= SD_FAILURES) {
        /* Preserve detailed SD diagnostics rather than replacing the report. */
        ErrorMask |= 1 << ERROR_SDCARD;
        return 0;
    }
    return 1;
}
unsigned int FindDrive(void) {
    /* One mount failure exercises the fallback fatal error report. */
    return attempts != SD_FAILURES + 1;
}
void ChangeDirectory(unsigned long directory) { assert(directory == DIRECTORY_ROOT); }
void LoadConfigurationTitles(void) {}
void SetConfigurationFilename(int slot) { assert(slot == 0); }
unsigned char LoadConfiguration(fileTYPE *cfgfile) {
    assert(!cfgfile);
    config.video_mode = (completed_boots & 1) ? 2 : 1;
    /* Second boot releases Space during loading; third presses it during loading. */
    if (completed_boots == 1) space_down = 0;
    if (completed_boots == 2) space_down = 1;
    return 1;
}
void RestoreDefaultVideoMode(void) { config.video_mode = 0; ++video_restores; }
int ApplyConfiguration(char reload, char drives, char ignoreoverclock) {
    (void)ignoreoverclock;
    if (reload) {
        assert(drives && guest_held && !ErrorFatal);
        assert(config.video_mode == ((completed_boots == 1 || completed_boots == 2) ? 0 :
            ((completed_boots & 1) ? 2 : 1)));
        if (completed_boots == 4) space_down = 1; /* Space arrives during ROM loading. */
        ++completed_boots;
    }
    return 1;
}
void fpga_init(void) { assert(!ErrorFatal); }
unsigned char OsdGetCtrl(void) { return KEY_F2; }
char BootPrint(const char *text) { (void)text; return 0; }
void BootPrintEx(char *text) { (void)text; }
int drivesounds_init(const char *filename) { (void)filename; return 0; }
int drivesounds_loaded(void) { return 0; }
void drivesounds_enable(int type) { (void)type; }
int drivesounds_fill(void) { return 0; }
void audio_clear(void) {}
void KeyboardService(void) {}
void KeyboardPoll(void) { EnableInterrupts(); }
int KeyboardKeyDown(unsigned char key) { assert(key == KEY_SPACE); return space_down; }
void aux_hid_inthandler(void) {}
void c64keys_inthandler(void) {}
void usbhid_inthandler(void) {}
void akiko_inthandler(void) {}
int c64keyboard_checkreset(void) { return 0; }
void HandleRTC(void) {}
void HandleFDD(unsigned char a, unsigned char b, unsigned char c, unsigned char d) {
    (void)a; (void)b; (void)c; (void)d;
    assert(!ErrorFatal && completed_boots && !guest_held);
    ++disk_calls;
}
void HandleIDE(unsigned int a, unsigned int b) { (void)a; (void)b; assert(!ErrorFatal); }
void UpdateDriveStatus(void) {}
void ShowError(void) { assert(ErrorFatal && guest_held); ++error_pages; }
void HandleUI(void) {
    unsigned int before = attempts;
    assert(!ui_active && interrupts_enabled);
    ui_active = 1;
    ++ui_calls;
    if (ErrorFatal) {
        assert(!completed_boots && !disk_calls);
        assert(ErrorMask & (1 << ERROR_SDCARD));
        ClearError(ERROR_ALL); /* Fatal error menu's Reboot action. */
        RequestColdBoot();
    } else if (completed_boots < 5) {
        space_down = completed_boots == 1;
        RequestColdBoot(); /* Normal menu's Reboot action. */
        RequestColdBoot(); /* Multiple pending requests coalesce. */
    } else {
        assert(completed_boots == 5 && attempts == SD_FAILURES + 6);
        assert(disk_calls == 5 && error_pages == SD_FAILURES + 1);
        assert(ui_calls == SD_FAILURES + 6 && video_restores == 3);
        ui_active = 0;
        longjmp(finished, 1);
    }
    assert(attempts == before); /* Requests must return without executing a boot. */
    ui_active = 0;
}

int main(void) {
    if (!setjmp(finished)) firmware_main();
    puts("PASS: repeated SD/mount failures, deferred UI retries, recovery, normal reboot and early interrupt setup");
    puts("PASS: Space cold boot overrides loaded modes, detects presses during config/ROM loading before reset release and is not sticky");
    return 0;
}
