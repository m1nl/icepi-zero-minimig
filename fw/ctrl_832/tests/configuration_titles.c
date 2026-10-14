/* Host regression test: exercise the firmware parser against a mocked FAT file. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "config.h"
#include "errors.h"
#include "osd.h"

static unsigned char contents[4096];
static unsigned long content_size, directory=123;
static int present=1, fail_sector=-1, reads, advances, clears;
static configTYPE binary_config;
static int configuration_present=1;

char BootPrint(const char *text) { (void)text; return 0; }

unsigned long CurrentDirectory(void) { return directory; }
void ChangeDirectory(unsigned long value) { directory=value; }
void ClearError(int category) { assert(category==ERROR_FILESYSTEM); ++clears; }
unsigned int FileOpen(fileTYPE *f, const char *name)
{
    assert(directory==DIRECTORY_ROOT);
    memset(f, 0, sizeof(*f));
    memcpy(f->name, name, 11);
    if(!strcmp(name, "MINMGAA TXT"))
    {
        f->size=content_size;
        return present;
    }
    assert(!strncmp(name, "MINMGAA", 7));
    f->size=sizeof(binary_config);
    return configuration_present;
}
unsigned int FileRead(fileTYPE *f, unsigned char *buffer)
{
    unsigned long offset=f->sector*512, count=content_size-offset;
    ++reads;
    if((int)f->sector==fail_sector) return 0;
    if(memcmp(f->name, "MINMGAA TXT", 11))
    {
        assert(sizeof(binary_config)<=512);
        memset(buffer, 0, 512);
        memcpy(buffer, &binary_config, sizeof(binary_config));
        return 1;
    }
    assert(offset<content_size);
    if(count>512) count=512;
    memset(buffer, 0xa5, 512); /* Padding must never enter the parser. */
    memcpy(buffer, contents+offset, count);
    return 1;
}
unsigned int FileNextSector(fileTYPE *f)
{
    ++advances;
    ++f->sector;
    assert(f->sector*512<content_size);
    return 1;
}
static void load(const char *text)
{
    content_size=strlen(text);
    memcpy(contents, text, content_size);
    reads=advances=0;
    LoadConfigurationTitles();
    assert(directory==123);
}
static void expect(unsigned int slot, const char *title)
{
    assert(!strcmp(GetConfigurationTitle(slot), title));
}
static void expect_label(unsigned int slot, int exists, int saving, const char *expected)
{
    char label[CONFIG_SLOT_LABEL_LENGTH+1];
    FormatConfigurationSlotLabel(label, slot, exists, saving);
    assert(!strcmp(label, expected));
    assert(strlen(label)<=CONFIG_SLOT_LABEL_LENGTH);
}
static void expect_scrolled(unsigned int slot, int exists, int saving, unsigned int offset, const char *expected)
{
    char label[CONFIG_SLOT_LABEL_LENGTH+1];
    FormatConfigurationSlotLabelAtOffset(label, slot, exists, saving, offset);
    assert(!strcmp(label, expected));
    assert(strlen(label)<=CONFIG_SLOT_LABEL_LENGTH);
}
static void expect_active(const char *expected)
{
    char label[CONFIG_SLOT_LABEL_LENGTH+1];
    FormatActiveConfigurationLabel(label);
    assert(!strcmp(label, expected));
}
int main(void)
{
    unsigned int glyphs=0, pixels=22;
    while(pixels<OSDLINELEN-8) { ++glyphs; pixels+=8; }
    assert(CONFIG_TITLE_LENGTH+4==glyphs);
    load("\xef\xbb\xbf# comment\r\n 0 = Default A500 \r\n1=A1200\n2=Games\r3=CD32\n4=Diagnostics");
    expect(0, "Default A500"); expect(1, "A1200"); expect(4, "Diagnostics");
    load(";comment\n5=invalid\n10=invalid\n-1=invalid\n1 no equals\n2=Bad\x01title\n3=Bad\xfftitle\n4=   \n");
    expect(0, "Default"); expect(1, "Configuration slot 1"); expect(2, "Configuration slot 2"); expect(3, "Configuration slot 3"); expect(4, "Configuration slot 4");
    load("1=First\n1 = Last\tTitle \t\n2=Name\n2=\n");
    expect(1, "Last Title"); expect(2, "Configuration slot 2");
    load("0=ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789\n1=Next");
    expect(0, "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"); expect(1, "Next");
    expect_label(0, 1, 0, " 0: ABCDEFGHIJKLMNOPQRSTUVWXY");
    expect_label(0, 1, 1, " 0* ABCDEFGHIJKLMNOPQRSTUVWXY");
    expect_label(0, 0, 0, " 0: ABCDEFGHIJKLMNOPQ (empty)");
    expect_label(0, 0, 1, " 0: ABCDEFGHIJKLMNOPQ (empty)");
    expect_scrolled(0, 1, 0, 1, " 0: BCDEFGHIJKLMNOPQRSTUVWXYZ");
    expect_scrolled(0, 1, 1, 1, " 0* BCDEFGHIJKLMNOPQRSTUVWXYZ");
    expect_scrolled(0, 0, 1, 1, " 0: BCDEFGHIJKLMNOPQR (empty)");
    expect_scrolled(0, 1, 0, 36, " 0:    ABCDEFGHIJKLMNOPQRSTUV");
    expect_scrolled(0, 1, 0, 39, " 0: ABCDEFGHIJKLMNOPQRSTUVWXY");
    expect_scrolled(1, 1, 0, 5, " 1: Next");
    expect_scrolled(2, 0, 1, 1, " 2: Configuration 2 (empty)");
    assert(strlen(GetConfigurationDisplayTitle(2, 0)) <= CONFIG_TITLE_LENGTH-CONFIG_EMPTY_SUFFIX_LENGTH);
    expect_label(2, 1, 0, " 2: Configuration slot 2");
    expect_label(2, 1, 1, " 2* Configuration slot 2");
    expect_label(2, 0, 0, " 2: Configuration 2 (empty)");
    expect_label(2, 0, 1, " 2: Configuration 2 (empty)");
    /* A very long line crossing sectors must not become another entry. */
    memset(contents, 'x', 1100);
    memcpy(contents, "0=", 2);
    memcpy(contents+1100, "\n1=Next", 7);
    content_size=1107;
    reads=advances=0;
    LoadConfigurationTitles();
    assert(strlen(GetConfigurationTitle(0))==CONFIG_TITLE_STORAGE_LENGTH);
    expect_label(0, 1, 0, " 0: xxxxxxxxxxxxxxxxxxxxxxxxx"); expect(1, "Next");
    assert(reads==3 && advances==2);
    /* A title and its delimiter can straddle a sector boundary. */
    memset(contents, ' ', 510);
    memcpy(contents+510, "3=Boundary", 10);
    content_size=520;
    LoadConfigurationTitles(); expect(3, "Boundary");
    /* No final advance for an exactly one-sector file. */
    memset(contents, ' ', 512); memcpy(contents, "4=Exact\n", 8);
    content_size=512; advances=0;
    LoadConfigurationTitles(); expect(4, "Exact"); assert(advances==0);
    fail_sector=1;
    memset(contents, ' ', 600); memcpy(contents, "1=Partial\n", 10);
    content_size=600;
    LoadConfigurationTitles(); expect(1, "Configuration slot 1");
    fail_sector=-1;
    load(""); assert(reads==0); expect(0, "Default");
    expect_label(0, 1, 0, " 0: Default");
    expect_label(0, 1, 1, " 0* Default");
    expect_label(0, 0, 0, " 0: Default (empty)");
    expect_label(0, 0, 1, " 0: Default (empty)");
    present=0; clears=0;
    load("1=Absent"); expect(1, "Configuration slot 1"); assert(clears==1 && reads==0);
    expect(CONFIG_SLOT_COUNT, "");
    /* Active profile follows successful loads, never just browsing Save slots. */
    expect_active(" Active: Built-in defaults");
    present=1;
    load("3=Games profile");
    memcpy(binary_config.id, "MNMGCFGA", 8);
    binary_config.version=CONFIG_VERSION;
    SetConfigurationFilename(3);
    assert(LoadConfiguration(NULL));
    expect_active(" Active: 3: Games profile");
    SetConfigurationFilename(4);
    expect_active(" Active: 3: Games profile");
    fail_sector=0;
    assert(!LoadConfiguration(NULL));
    expect_active(" Active: 3: Games profile");
    fail_sector=-1;
    {
        fileTYPE other;
        memset(&other, 0, sizeof(other));
        other.size=sizeof(binary_config);
        memcpy(other.name, "OTHER   CFG", 11);
        strcpy(other.long_name, "Custom Workbench.CFG");
        assert(LoadConfiguration(&other));
        expect_active(" Active: Custom Workbench.CFG");
        other.long_name[0]=0;
        assert(LoadConfiguration(&other));
        expect_active(" Active: OTHER.CFG");
    }
    binary_config.id[0]='?';
    assert(!LoadConfiguration(NULL));
    expect_active(" Active: Built-in defaults");
    configuration_present=0;
    SetConfigurationFilename(0);
    assert(!LoadConfiguration(NULL));
    expect_active(" Active: Built-in defaults");
    puts("Configuration title, scrolling, and active profile tests passed.");
    return 0;
}
