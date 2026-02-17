#define MISS 0xff
#define OSD 0x80
#define KEY_MENU 0x69

// keycode translation table
const unsigned short usb2ami[256] = {
  MISS,  // 00: NoEvent
  MISS,  // 01: Overrun Error
  MISS,  // 02: POST fail
  MISS,  // 03: ErrorUndefined
  0x20,  // 04: a
  0x35,  // 05: b
  0x33,  // 06: c
  0x22,  // 07: d
  0x12,  // 08: e
  0x23,  // 09: f
  0x24,  // 0a: g
  0x25,  // 0b: h
  0x17,  // 0c: i
  0x26,  // 0d: j
  0x27,  // 0e: k
  0x28,  // 0f: l
  0x37,  // 10: m
  0x36,  // 11: n
  0x18,  // 12: o
  0x19,  // 13: p
  0x10,  // 14: q
  0x13,  // 15: r
  0x21,  // 16: s
  0x14,  // 17: t
  0x16,  // 18: u
  0x34,  // 19: v
  0x11,  // 1a: w
  0x32,  // 1b: x
  0x15,  // 1c: y
  0x31,  // 1d: z
  0x01,  // 1e: 1
  0x02,  // 1f: 2
  0x03,  // 20: 3
  0x04,  // 21: 4
  0x05,  // 22: 5
  0x06,  // 23: 6
  0x07,  // 24: 7
  0x08,  // 25: 8
  0x09,  // 26: 9
  0x0a,  // 27: 0
  0x44,  // 28: Return
  0x45,  // 29: Escape
  0x41,  // 2a: Backspace
  0x42,  // 2b: Tab
  0x40,  // 2c: Space
  0x0b,  // 2d: -
  0x0c,  // 2e: =
  0x1a,  // 2f: [
  0x1b,  // 30: ]
  0x0d,  // 31: backslash (only on us keyboards)
  0x2b,  // 32: Europe 1 (only on international keyboards)
  0x29,  // 33: ; 
  0x2a,  // 34: '
  0x00,  // 35: `
  0x38,  // 36: ,
  0x39,  // 37: .
  0x3a,  // 38: /
  0x62,  // 39: Caps Lock
  0x50,  // 3a: F1
  0x51,  // 3b: F2
  0x52,  // 3c: F3
  0x53,  // 3d: F4
  0x54,  // 3e: F5
  0x55,  // 3f: F6
  0x56,  // 40: F7
  0x57,  // 41: F8
  0x58,  // 42: F9
  0x59,  // 43: F10
  0x5f,  // 44: F11
  KEY_MENU,  // 45: F12 (OSD)
  0x6e,  // 46: Print Screen (OSD)
  MISS,  // 47: Scroll Lock (OSD)
  0x6f,  // 48: Pause
  0x0d,  // 49: backslash to avoid panic in Germany ;)
  0x6a,  // 4a: Home
  0x6c,  // 4b: Page Up (OSD)
  0x46,  // 4c: Delete
  MISS,  // 4d: End
  0x6d,  // 4e: Page Down (OSD)
  0x4e,  // 4f: Right Arrow
  0x4f,  // 50: Left Arrow
  0x4d,  // 51: Down Arrow
  0x4c,  // 52: Up Arrow
  MISS,  // 53: Num Lock
  0x5c,  // 54: KP /
  0x5d,  // 55: KP *
  0x4a,  // 56: KP -
  0x5e,  // 57: KP +
  0x43,  // 58: KP Enter
  0x1d,  // 59: KP 1
  0x1e,  // 5a: KP 2
  0x1f,  // 5b: KP 3
  0x2d,  // 5c: KP 4
  0x2e,  // 5d: KP 5
  0x2f,  // 5e: KP 6
  0x3d,  // 5f: KP 7
  0x3e,  // 60: KP 8
  0x3f,  // 61: KP 9
  0x0f,  // 62: KP 0
  0x3c,  // 63: KP .
  0x30,  // 64: Europe 2
  MISS,  // 65: App
  MISS,  // 66: Power
  MISS,  // 67: KP =
  0x5a,  // 68: KP (
  0x5b,  // 69: KP )
  MISS,  // 6a: F15
  0x5f,  // 6b: help (for keyrah)
  MISS,  // 6c: F17
  MISS,  // 6d: F18
  MISS,  // 6e: F19
  MISS,  // 6f: F20
  MISS,  // 70: F21
  MISS,  // 71: F22
  MISS,  // 72: F23
  MISS,  // 73: F24
  MISS,  // 74: Exe
  MISS,  // 75: Help
  MISS,  // 76: Menu
  MISS,  // 77: Sel
  MISS,  // 78: Stop
  MISS,  // 79: Again
  MISS,  // 7a: Undo
  MISS,  // 7b: Cut
  MISS,  // 7c: Copy
  MISS,  // 7d: Paste
  MISS,  // 7e: Find
  MISS,  // 7f: Mute
  // Non-standard hack for modifiers
  0x63,  // 80: L Ctrl
  0x60,  // 81: L Shift
  0x64,  // 82: L Alt
  0x66,  // 83: L Super
  0x63,  // 84: R Ctrl
  0x61,  // 85: R Shift
  0x65,  // 86: R Alt
  0x67,  // 87: R Amiga
};

#define HIDKEY_NUMLOCK 0x53
#define HIDKEY_UP 0x52
#define HIDKEY_DOWN 0x51
#define HIDKEY_LEFT 0x50
#define HIDKEY_RIGHT 0x4f
#define HIDQUAL_LCTRL 0x01
#define HIDQUAL_LALT 0x04



