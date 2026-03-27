#include <jni.h>
#include <stdio.h>

/*
This is a closure for LuaJIT to set ...
*/
int (*SDL_main_callback)() = NULL;

/*
This is called from libSDL3.so , which is called from SDLActivity.
Mind you, this is on a separate Lua state from the launcher
and it's also on a separate java thread from the Android UI thread.
I'm calling it as-is without subclassing/modification of SDLActivity, so args is going to be empty.
*/
JNIEXPORT int SDL_main(int argc, char** argv) {
	if (SDL_main_callback) {
		return SDL_main_callback();
	} else {
		fprintf(stderr, "SDL_main_callback is NULL!");
	}
}
