Ok First I made [SDL-LuaJIT](https://github.com/thenumbernine/SDLLuaJIT-android) by starting with the SDL-android project and throwing LuaJIT into it.

This was great but it couldn't touch the UI thread.

So I redid it, stripped out SDL, made a bare-bones-Android-Activity with LuaJIT.  All UI thread.  That's the [LuaJIT-Android](https://github.com/thenumbernine/LuaJIT-android) project.

Then I added multithreading.  Got a GLSurfaceView to work.  But those are stuck in Java and hard-capped FPS at 30 or 60 or so, not the much higher rates I saw in SDL-android.

So this is my attemp to start with LuaJIT-android multithreading and reinsert SDLActivity into it.
