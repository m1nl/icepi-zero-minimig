/*
Copyright 2008, 2009 Jakub Bednarski

This file is part of Minimig

Minimig is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3 of the License, or
(at your option) any later version.

Minimig is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#include "hardware.h"
#include "config.h"

void EnableIECSerial() {
    config.misc |= (1 << PLATFORM_IECSERIAL);
    PLATFORM = config.misc; // A write to this register triggers a reconfig
}

void DisableIECSerial() {
    config.misc &= ~(1 << PLATFORM_IECSERIAL);
    PLATFORM = config.misc; // A write to this register triggers a reconfig
}
