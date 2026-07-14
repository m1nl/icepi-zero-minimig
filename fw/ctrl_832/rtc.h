#ifndef RTC_H
#define RTC_H

#define RTCBASE 0x0fffff72
#define HW_RTC(x) *(volatile unsigned short *)(RTCBASE+x)

void HandleRTC();

#endif

