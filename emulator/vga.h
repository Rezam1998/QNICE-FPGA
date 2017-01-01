/*
** Header file for the VGA emulation.
**
** done by sy2002 in December 2016 .. Januar 2017
*/

#ifndef _QEMU_VGA
#define _QEMU_VGA

#include "SDL.h"

typedef int (vga_tft)(void*);

int vga_init();
void vga_shutdown();
int vga_create_thread(vga_tft thread_func, void* param);
int vga_main_loop();

#endif