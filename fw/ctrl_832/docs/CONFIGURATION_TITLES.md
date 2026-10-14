# Configuration slot titles

Place an optional `MINMGAA.TXT` in the SD-card root:

```ini
# Slot 0 is MINMGAA.CFG; slots 1-4 are MINMGAA1.CFG through MINMGAA4.CFG.
0=Default A500
1=A1200 Workbench
2=A500 Games
3=CD32
4=Diagnostics
```

Custom titles appear in both Load and Save, prefixed by the slot number. A title can
contain up to **63 printable ASCII characters**. The OSD displays 25 characters
beside the leading space and slot prefix, or 17 when the ` (empty)` suffix is present. Longer
selected titles scroll after 1.5 seconds, retaining the prefix and suffix.
Text beyond 63 characters is discarded.
In Save, `1* Title` marks an existing configuration; `1: Title` marks an empty
slot. The menu includes an overwrite-marker legend.
Unused slots show ` (empty)`, reducing the displayed title to 17 characters.
All labels are left aligned. Unnamed slots show `0: Default` or
`N: Configuration slot N`. Unused numbered slots show
` N: Configuration N (empty)` to fit the OSD width without scrolling. All configuration
labels, including the active profile indicator, start with one space.

The Misc page shows the active slot and title, or the filename when loaded
through Other. When no valid configuration was loaded, it shows Built-in defaults.
Browsing or saving another slot does not change the active profile indicator.
The indicator identifies the loaded profile even if its settings have been edited.

Names are read at firmware startup. Restart after editing the file. The file
does not change configuration filenames or contents, and saving a configuration
does not modify it. Load still disables slots whose configuration file is absent.

LF, CRLF and CR line endings, an optional UTF-8 BOM, and a final line without a
newline are accepted. Spaces and tabs around the slot number, `=`, and title
are ignored; tabs within a title become spaces. Only slot numbers 0-4 are valid.
Blank lines, comment lines beginning with `#` or `;`, and malformed entries are
ignored. Comments must be on their own lines. The last valid entry for a slot
wins; an empty title restores its fallback label. Missing files and unnamed
slots use `Default` and `Configuration slot 1` through `Configuration slot 4`.

The parser regression test can be run from the repository root with:

```sh
gcc -std=c99 -D__geta4= -Ifw/ctrl_832 -IEightThirtyTwo/lib832 \
    -ffunction-sections -fdata-sections fw/ctrl_832/config.c \
    fw/ctrl_832/tests/configuration_titles.c -Wl,--gc-sections \
    -o /tmp/minimig-configuration-titles-test
/tmp/minimig-configuration-titles-test
```
