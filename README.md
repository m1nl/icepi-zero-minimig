# Minimig AGA
Ported to IcePi Zero and FleaFPGA Ohm

### Foreword

[minimig](http://en.wikipedia.org/wiki/Minimig) (short for Mini Amiga) is an open source re-implementation of an Amiga using a field-programmable gate array (FPGA). Original minimig author is Dennis van Weeren.

[Amiga](http://en.wikipedia.org/wiki/Amiga_500) was an amazing personal computer, announced around 1984, which - at the time - far surpassed any other personal computer on the market, with advanced graphic & sound capabilities, not to mention its great OS with preemptive multitasking capabilities.

This minimig variant has been upgraded with [AGA chipset](http://en.wikipedia.org/wiki/Amiga_Advanced_Graphics_Architecture) capabilites, which allows it to emulate the latest Amiga models ([Amiga 1200](http://en.wikipedia.org/wiki/Amiga_1200), [Amiga 4000](http://en.wikipedia.org/wiki/Amiga_4000) and (partially) [Amiga CD32](http://en.wikipedia.org/wiki/Amiga_CD32)). Ofcourse it also supports previous OCS/ECS Amigas like [Amiga 500](http://en.wikipedia.org/wiki/Amiga_500), [Amiga 600](http://en.wikipedia.org/wiki/Amiga_600) etc.

## Core features supported

* chipset variants : OCS, ECS, AGA
* chipRAM : 0.5MB - 2.0MB
* slowRAM : 0.0MB - 1.5MB
* fastRAM : 0.0MB - 24MB
* CPU core : 68000, 68010, 68020
* kickstart : 1.2 - 3.2 (256kB, 512kB & 1MB kickstart ROMs currently supported)
* floppy disks : 1-4 floppies (supports ADF floppy image format), with normal & turbo speeds
* hard disks : 1-2 hard disk images (supports whole disk images, partition images, using whole SD card and using SD card partition)
* video standard : PAL / NTSC
* supports HDMI video output with sound
* peripherals : 2 x USB HID ports with FPGA USB controllers
* has an implementation of the [Akiko](https://en.wikipedia.org/wiki/Amiga_custom_chips#Akiko) chunky to planar converter

## USB support

Please keep in mind that the board is FPGA-based, and the USB HID controller is implemented in gateware. There is no dedicated USB controller chip on the board itself. As a result, some USB HID devices may not be compatible with the board.

I have tested the following devices and can confirm they work properly:
- 8BitDo Pro 3 utilizing bundled 2.4G wireless dongle
- 8BitDo Ultimate 2C wireless utilizing bundled 2.4G wireless dongle (non-Bluetooth version)
- Logitech, Inc. Unifying Receiver w/ Y-R0012
- Logitech, Inc. Unifying Receiver w/ K400r
- SpeedLink COMPETITION PRO Extra USB Joystick
- Legacy Logitech low-speed mouse
- IBM Corp. NetVista Full Width Keyboard
- Keychron C3 Pro
- Keychron K2

Not working:
- 8BitDo 8BitDo Retro Keyboard Receiver (2dc8:5201)
- 8BitDo 8BitDo Retro 87 Adapter X (2dc8:202e)

The 8BitDo retro keyboard does not send report events even after successful enumeration. It appears the keyboard exposes two interfaces (mouse + keyboard), and both must be enumerated before reports start being received. There are also reports that this keyboard supports only NKRO and not 6KRO, despite BOOT protocol support (typically associated with 6KRO) being required by the HID standard. Further work may be done to add support for this keyboard, but no guarantees can be made given the extent of changes that may be required.

Other low-speed and full-speed USB 2.0 HID devices should generally work as well. However, avoid composite devices that include built-in USB hub or keyboard + mouse functionality. Each port supports only a single device, as it has a separate USB soft controller attached to it.

## Usage

### Hardware

To use this Minimig core, you will at the minimum need an SD/SDHC card, formatted with the FAT32 filesystem, USB HID keyboard / mouse and a HDMI monitor / TV.

IcePi Zero core is compatible with [IcePi Carrier](https://github.com/MiSTle-Dev/Boards/tree/main/icepi_carrier) board so you can use more USB ports or have better USB compatibility. Only USB / HID features of FPGA Companion firmware are in use.

FleaFPGA Ohm core retains original [pin assignments](https://github.com/Basman74/Minimig_ECS/blob/master/Minimig_setup_README.pdf) except for analog audio and 30/15kHz video output select. Ping me if you need IcePi carrier-compatible build.

### Installing from binary release for IcePi Zero

* download latest release from GitHub
* copy `832OSDU0.bin` file to root directory of your SD card
* flash bitstream to flash memory using openFPGALoader
```
$ openFPGALoader -b icepi-zero --write-flash fpga/icepi-zero/Minimig_IcePi-Zero/minimig_icepi-zero_Minimig_IcePi-Zero.bit
```
* alternatively, use web flasher available here http://ofl.trabucayre.com/ - Chrome works best, for Windows use Zadig (https://zadig.akeo.ie/) to install WinUSB driver
* don't forget to place kickstart ROM of your choosing on the root of the SD card (these are still copyrighted, so either copy the ROM from your real Amiga, or buy AmigaForever)
* place some ADF (floppy disk images) of your favourite games / demos / programs on your SD card
* optionally place minimig.bal, minimig.art & minimig.cop files on the root of your SD card for a nice bootup animation
* enjoy minimig! :)

### Installing from binary release for FleaFPGA Ohm

* download latest release from GitHub
* copy `832OSDU0.bin` file to root directory of your SD card
* refer to original instructions in the [FleaFPGA-JTAG flasher repository](https://github.com/XarkLabs/FleaFPGA-JTAG) on how to flash bitstream

### Building minimig-mist from sources

* checkout the source 
* download / install [Lattice Diamond](https://www.latticesemi.com/en/Products/DesignSoftwareAndIP/FPGAandLDS/LatticeDiamond)
* compile firmware and prepare boot ROM
```
$ git submodule update --init
$ cd fw
$ make
```
* copy `832OSDU0.bin` file to root directory of your SD card
* build the core using Lattice Diamond GUI (project file in fpga/icepi-zero/ or fpga/fleaohm/)
* for IcePi Zero flash bitstream to flash memory using openFPGALoader
```
$ openFPGALoader -b icepi-zero --write-flash fpga/icepi-zero/Minimig_IcePi-Zero/minimig_icepi-zero_Minimig_IcePi-Zero.bit
```
* for FleaFPGA Ohm open XCF file in Diamond from File List, right click on first row, Device Properties, pick bit file and click Load from file button and **save XCF file**, then:
```
diamond/3.14/bin/lin64/ddtcmd -oft -fullvme -if fpga/fleaohm/Minimig_FleaOhm/Minimig_FleaOhm.xcf  -nocompress -noheader -of fpga/fleaohm/Minimig_FleaOhm/Minimig_FleaOhm.vme
```
* for FleaFPGA Ohm flash .vme according to instructions from [FleaFPGA-JTAG flasher repository](https://github.com/XarkLabs/FleaFPGA-JTAG)
* don't forget to place kickstart ROM of your choosing on the root of the SD card (these are still copyrighted, so either copy the ROM from your real Amiga, or buy AmigaForever)
* place some ADF (floppy disk images) of your favourite games / demos / programs on your SD card
* optionally place minimig.bal, minimig.art & minimig.cop files on the root of your SD card for a nice bootup animation
* enjoy minimig! :)

### Additional remarks

You will also need a Kickstart ROM image file, which you can obtain by copying Kickstart ROM IC from your actual Amiga, or by buying an [Amiga Forever](http://www.amigaforever.com/) software pack. The Kickstart image should be placed on the root of the SD card with the name KICK.ROM. Minimig also supports the [AROS](http://aros.sourceforge.net/) Kickstart ROM replacement.

The minimig can read any ADF floppy images you place on the SD card. I recommend at least Workbench 1.3 or 3.1 (AmigaOS), some of the Amigas great games (I recommend Ruff'n'Tumble) or some of the amazing demos from the vast Amiga demoscene (like State of the Art from Spaceballs).

The minimig can also use HDF harddisk images, which can be created with [WinUAE](http://www.winuae.net/).

### Recommended minimig config

* for ECS games / demos : CPU=68000, Turbo=NONE, Chipset=ECS, chipRAM=0.5MB, slowRAM=0.5MB, Kickstart 1.3
* for A1200-era AGA games / demos : CPU=68020, Turbo=NONE, Chipset=AGA, chipRAM=2MB, slowRAM=0MB, fastRAM=2MB or more, Kickstart 3.1
* for modern AGA games / demos (Outrun port by Reassembler / DoomAttack) : CPU=68020, Chipset=AGA, chipRAM=2MB, slowRAM=0MB, fastRAM=FULL, Turbo=FULL, Overclock=ON, Kickstart 3.1

For Workbench usage, you can try turning TURBO=FULL for a speed increase.

### Notes regarding games compatiblity

* Pinball Fantasies AGA - use CPU=68020, Chipset=AGA, chipRAM=2MB and fastRAM=2MB, Kickstart 3.1 ; with more fastRAM, it hangs

### Controlling minimig

Keyboard special keys:

* F12, Print Screen - OSD menu (F12 does not work with IcePi Carrier board)
* Hold Windows key and direction keys - move mouse (Workbench only)
* Hold Windows key and press left ALT - left mouse click (Workbench only)

## Links & more info

Rok Krajnc's page [somuch.guru](http://somuch.guru/).

Further info about minimig can be found on the [Minimig Discussion Forum](http://www.minimig.net/).

The Turbo Chameleon 64 - [Individual Computers](http://wiki.icomp.de/wiki/Chameleon)

MiST board support & other cores on the [MiST Project Page](https://github.com/mist-devel/mist-board/wiki)

## Credits

This project contains code written by:

* Jakub Bednarski
* Sascha Boing
* Tobias Gubener
* Till Harbaum
* Rok Krajnc
* Alastair M. Robinson
* Gyorgy Szombathelyi
* Dennis van Weeren
* Mateusz Nalewajski

All code is copyright © 2005 - 2026 and the property of its respective authors.

## License

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

## Sources

This sourcecode is based on Rok's previous project ([minimig-de1](https://github.com/rkrajnc/minimig-de1)), and it continues from there. It was split into a new project to allow changes that would never fit in the FPGA on the DE1 board.

Original minimig sources from Dennis van Weeren with updates by Jakub Bednarski are published on [Google Code](http://code.google.com/p/minimig/).

Some minimig updates are published on the [Minimig Discussion Forum](http://www.minimig.net/), done by Sascha Boing.

ARM firmware updates and minimig-tc64 port changes by Christian Vogelsang ([minimig_tc64](https://github.com/cnvogelg/minimig_tc64)) and A.M. Robinson ([minimig_tc64](https://github.com/robinsonb5/minimig_tc64)).

MiST board & firmware by Till Harbaum ([MiST](https://github.com/mist-devel)).

TG68K.C core by Tobias Gubener ([TG68K.C](https://github.com/TobiFlex/TG68K.C)).
