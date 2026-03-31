-- this is the LuaJIT app's main.lua is currently pointed
-- it is distinct of the SDLLuaJIT in that it has a minimal bootstrap that points it squarely to lua-java and the assets apk loader
-- from there I will load more files from here
-- and then write stupid android apps
local assert = require 'ext.assert'
local table = require 'ext.table'
local path = require 'ext.path'
local ffi = require 'ffi'
local J = require 'java'


-- used often enough
local Activity = J.android.app.Activity
local Intent = J.android.content.Intent
local LinearLayout = J.android.widget.LinearLayout
local ViewGroup = J.android.view.ViewGroup


--print('_G='..tostring(_G)..', jniEnv='..tostring(J._ptr))
--print('Android API:', J.android.os.Build.VERSION.SDK_INT)	-- says 30
--print('Android API:', activity:getApplicationContext():getApplicationInfo().targetSdkVersion)	-- says 36


local activity
local callbacks = {}

-- maybe I should by default make all handlers that call through to super ...
do
	local callbackNames = {}
	for name,methodsForName in pairs(Activity._methods) do
		for _,method in ipairs(methodsForName) do
			if method._class == 'android.app.Activity' then
				callbackNames[name] = true	-- do as a set so multiple signature methods will only get one callback (since lua invokes it by name below)
			end
		end
	end
	for name in pairs(callbackNames) do
		-- set up default callback handler to run super() of whatever args we are given
		callbacks[name] = function(activity, ...)
			local super = activity.super
			return super[name](super, ...)
		end
	end
end


----------- some support functions

local nextMenuID = 0
local function getNextMenu()
	nextMenuID = nextMenuID + 1
	return nextMenuID
end

local nextActivityID = J.android.app.Activity.RESULT_FIRST_USER
local function getNextActivity()
	nextActivityID = nextActivityID + 1
	return nextActivityID
end

-- [=======[ menu for watching RAM
do
	local isWatchingRAM
	local statsLoopHandler
	local statsLoopRunnable

	local prevOnCreate = callbacks.onCreate
	callbacks.onCreate = function(activity, savedInstanceState, ...)
		prevOnCreate(activity, savedInstanceState, ...)

		statsLoopHandler = J.android.os.Handler(J.android.os.Looper:getMainLooper())

		local StatsLoopRunnable = J.Runnable:_subclass{
			methods = {
				run = {
					isPublic = true,
					sig = {'void'},
					value = function(this)
						local Debug = J.android.os.Debug
						local mem = Debug.MemoryInfo()
						Debug:getMemoryInfo(mem)
						print(os.date()..' mem: '..tostring(mem:getTotalPss())..'kb')
						if isWatchingRAM then
							statsLoopHandler:postDelayed(this, 1000)
						end
					end,
				},
			}
		}
		statsLoopRunnable = StatsLoopRunnable()
	end

	local prevOnResume = callbacks.onResume
	callbacks.onResume = function(activity)
		prevOnResume(activity)
		if statsLoopHandler
		and statsLoopRunnable
		and isWatchingRAM
		then
			statsLoopHandler:post(statsLoopRunnable)
		end
	end

	local prevOnPause = callbacks.onPause
	callbacks.onPause = function(activity)
		prevOnPause(activity)
		if statsLoopHandler and statsLoopRunnable then
			statsLoopHandler:removeCallbacks(statsLoopRunnable)
		end
	end

	local menuToggleStats = getNextMenu()
	local prevOnCreateOptionsMenu = callbacks.onCreateOptionsMenu
	callbacks.onCreateOptionsMenu = function(activity, menu, ...)
		prevOnCreateOptionsMenu(activity, menu, ...)
		menu:add(0, menuToggleStats, 0, 'RAM...')
		return true
	end

	local prevOnOptionsItemSelected = callbacks.onOptionsItemSelected
	callbacks.onOptionsItemSelected = function(activity, item, ...)
		if item:getItemId() == menuToggleStats then
			isWatchingRAM = not isWatchingRAM
			if isWatchingRAM then
				statsLoopHandler:post(statsLoopRunnable)
			else
				statsLoopHandler:removeCallbacks(statsLoopRunnable)
			end
			return true
		end
		return prevOnOptionsItemSelected(activity, item, ...)
	end
end
--]=======]
-- [=======[ attempt at just outputting the out.txt file
do
	local logScrollView
	--local viewSwitcher
	local logUpdateLoopHandler
	local logUpdateLoopRunnable

	local prevOnCreate = callbacks.onCreate
	callbacks.onCreate = function(activity, savedInstanceState, ...)
		prevOnCreate(activity, savedInstanceState, ...)

		local textView = J.android.widget.TextView(activity)
		textView:setLayoutParams(ViewGroup.LayoutParams(
			ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT
		))
		textView:setPadding(16, 16, 16, 16)
		textView:setTypeface(J.android.graphics.Typeface.MONOSPACE)
		textView:setTextSize(J.android.util.TypedValue.COMPLEX_UNIT_SP, 12)

		logScrollView = J.android.widget.ScrollView(activity)
		logScrollView:setLayoutParams(ViewGroup.LayoutParams(
			ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT
		))
		logScrollView:addView(textView)

		local ScrollToBottomRunnable = J.Runnable:_cbClass(function()
			logScrollView:fullScroll(J.android.view.View.FOCUS_DOWN)
		end)

		local logFile = J.java.io.File'out.txt'
		local lastTextTime = logFile:lastModified()
		textView:setText(path'out.txt':read() or '')
		logUpdateLoopHandler = J.android.os.Handler(J.android.os.Looper:getMainLooper())

		local LogUpdateLoopRunnable = J.Runnable:_subclass{
			methods = {
				run = {
					isPublic = true,
					sig = {'void'},
					value = function(this)
						local thisTextTime = logFile:lastModified()
						if thisTextTime > lastTextTime then
							lastTextTime = thisTextTime

							local isAtBottom = logScrollView:canScrollVertically(1)

							textView:setText(path'out.txt':read() or '')

							if isAtBottom then
								logScrollView:post(ScrollToBottomRunnable())
							end
						end
						logUpdateLoopHandler:postDelayed(this, 1000)
					end,
				},
			}
		}
		logUpdateLoopRunnable = LogUpdateLoopRunnable()

print"onCreate DONE"
	end

	local prevOnResume = callbacks.onResume
	callbacks.onResume = function(activity)
		prevOnResume(activity)
		if logUpdateLoopHandler and logUpdateLoopRunnable then
			logUpdateLoopHandler:post(logUpdateLoopRunnable)
		end
	end

	local prevOnPause = callbacks.onPause
	callbacks.onPause = function(activity)
		prevOnPause(activity)
		if logUpdateLoopHandler and logUpdateLoopRunnable then
			logUpdateLoopHandler:removeCallbacks(logUpdateLoopRunnable)
		end
	end

	local menuOpenLog = getNextMenu()
	local prevOnCreateOptionsMenu = callbacks.onCreateOptionsMenu
	callbacks.onCreateOptionsMenu = function(activity, menu, ...)
		prevOnCreateOptionsMenu(activity, menu, ...)
		menu:add(0, menuOpenLog, 0, 'Log...')
		return true
	end

	local prevOnOptionsItemSelected = callbacks.onOptionsItemSelected
	callbacks.onOptionsItemSelected = function(activity, item, ...)
		if item:getItemId() == menuOpenLog then
			-- [[ open the log ... but doesn't use back buttons
			activity:setContentView(logScrollView)
			--]]
			--[[ open ?
			viewSwitcher:showNext()	-- do you have any control over what view is going to be shown, or did retards make Android?
			--]]
			return true
		end
		return prevOnOptionsItemSelected(activity, item, ...)
	end
end
--]=======]
-- [=======[ SDL
do
	local Button = J.android.widget.Button

	local sdlLaunchLayout
	local cwdRow
	local fileRow
	local projectRow
	local launchRow

	local pickCwdFolder = getNextActivity()
	local pickProjectFolder = getNextActivity()
	local pickLaunchFile = getNextActivity()

	local function launchSDL(activity)
		-- ok so we have this libmain which is the project C contribution
		-- it's usually got the lua call code
		-- but I also for this project squeezed in the SDL_main function as well, which is just a trampoline back to luajit world:
		-- however it's gonna run on a separate thread
		-- so it's gotta run on a separate Lua state ...
		local LiteThread = require 'thread.lite'
		_G.sdlMainThread = LiteThread{
			init = function(th)
				th.lua('appFilesDir = ...', tostring(activity:getFilesDir():getAbsolutePath()))
				th.lua('runDir = ...', tostring(cwdRow.edit:getText()))
				th.lua('runFile = ...', tostring(fileRow.edit:getText()))
				th.lua('projectDir = ...', tostring(projectRow.edit:getText()))
				th.lua('runArg = ...', tostring(launchRow.edit:getText()))
			end,
			code = [=[
print 'here from within the SDL_main thread'

xpcall(function()

	local ffi = require 'ffi'
	print('ffi.os', ffi.os)
	print('ffi.arch', ffi.arch)

	local libDir = appFilesDir..'/lib'

	ffi.cdef[[int chdir(const char *path);]]
	local function chdir(s)
		local res = ffi.C.chdir((assert(s)))
		assert(res==0, 'chdir '..tostring(s)..' failed')
	end

	package.path = table.concat({
		'./?.lua',
		projectDir..'/?.lua',
		projectDir..'/?/?.lua',
	}, ';')
	package.cpath = table.concat({
		'./?.so',
		projectDir..'/?.so',
		projectDir..'/?/init.so',
	}, ';')

	ffi.cdef[[int setenv(const char*,const char*,int);]]
	ffi.C.setenv('LUA_PATH', package.path, 1)
	ffi.C.setenv('LUA_CPATH', package.cpath, 1)

	local function exec(cmd)
		if not os.execute(cmd) then
			print('FAILED: '..cmd)
		end
	end

-- TODO all this but only when it's needed ...
-- you can use distinfo digraph to tell what libs are being used.

	exec('mkdir -p '..libDir)
	local function setuplib(projectName, libLoadName)
		local libFileName = 'lib'..libLoadName..'.so'
		exec(('cp %q %q'):format(
			projectDir..'/'..projectName..'/bin/Android/arm/'..libFileName,
			libDir..'/')
		)
		require 'ffi.load'[libLoadName] = libDir..'/'..libFileName
	end
	local function setupsymlink(libFileName)
		local dst = libDir..'/'..libFileName
		exec('rm '..dst)
		exec('ln -s /system/lib/'..libFileName..' '..dst)
	end

	setuplib('audio', 'ogg')
	setuplib('audio', 'openal')
	setuplib('audio', 'vorbis')
	setuplib('audio', 'vorbisenc')	-- needs vorbis
	setuplib('audio', 'vorbisfile')	-- needs vorbis

	setuplib('gui', 'brotlicommon')		-- libbrotlicommon used by libbrotlidec
	setuplib('gui', 'brotlidec')				-- libbrotlidec used by libfreetype
	setuplib('gui', 'bz2')							-- libbz2 used by libfreetype
	setuplib('gui', 'freetype')

	setuplib('image', 'z')							-- libz used by libpng
	setuplib('image', 'png')
	setuplib('image', 'jpeg')
	setuplib('image', 'tiff')

	setuplib('imgui', 'cimgui_sdl3')

	-- wait is it already there?
	exec(('cp %q %q'):format('libc++_shared.so', libDir..'/'))

	-- vulkan
	setupsymlink'libvulkan.so'
	require 'ffi.load'.vulkan = libDir..'/libvulkan.so'

	local arg = {runArg}

	if runFile:match'%.rua$' then
		require 'ext'
		require 'ext.ctypes'
		require 'langfix'
	end
	chdir(runDir)
	print('starting loadfile...')
	assert(loadfile(assert(runFile)))(table.unpack(arg))

	print'DONE SDL_main_callback'
end, function(err)
	print('SDL_main_callback err\n'..err..'\n'..debug.traceback())
end)
]=]
		}
		function sdlMainThread:close() end	-- I don't trust lite thread GC with lua-java ...
		ffi.cdef[[void*(*SDL_main_callback)(void*);]]
		local main = ffi.load'main'

		-- TODO on checking liteThread status, I think I'm gonna need a mutex per Lua State to make sure two separate threads don't access it at the same time.
		main.SDL_main_callback = ffi.cast('void*', ffi.cast('uintptr_t', sdlMainThread.funcptr))


		local SDLActivity = J.org.libsdl.app.SDLActivity
		local sdlIntent = Intent(activity, SDLActivity.class)
		activity:startActivity(sdlIntent)
	end

	local prevOnCreate = callbacks.onCreate
	callbacks.onCreate = function(activity, savedInstanceState, ...)
		prevOnCreate(activity, savedInstanceState, ...)

		-- doing this is required for SDLActivity:nativeSetenv to work:
		J.System:loadLibrary'SDL3'

		-- tell SDL don't quit the app when you finish.
		-- is nativeSetenv the same as SDL_SetHint?  it maps to setenv() ... is it only so for before SDL_Init runs?
		local SDLActivity = J.org.libsdl.app.SDLActivity
		assert(require 'java.class':isa(SDLActivity), "failed to find org.libsdl.app.SDLActivity")
		SDLActivity:nativeSetenv("SDL_ANDROID_ALLOW_RECREATE_ACTIVITY", "1")

		-- now we want a textarea or button for gettign a dir list , and then list to show all .lua files or other dirs in the dir
		-- and we want a way to pick the launch cwd and launch args.
		-- saving them in the bundle would be nice too.
		--[[
		what will we need?
		- cwd
		- launch .lua file
		- package.path and package.cpath
		- maybe a checkbox for using the assets loader
		- also looks like any .so used (in bin/Android/arm folder) will need to be copied back into the /data/data/package/lib/ folder
		- ... or symlink'd ?

		- then make sure activity has all we want, like orientation
		- and make sure activity is fullscreen, no title bar ...
		--]]
		sdlLaunchLayout = LinearLayout(activity)
		sdlLaunchLayout:setOrientation(LinearLayout.VERTICAL)
		sdlLaunchLayout:setLayoutParams(LinearLayout.LayoutParams(
			LinearLayout.LayoutParams.MATCH_PARENT,
			LinearLayout.LayoutParams.MATCH_PARENT
		))

		local function addRow(args)
			local row = LinearLayout(activity)
			row:setOrientation(LinearLayout.HORIZONTAL)
			row:setLayoutParams(LinearLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT,
				ViewGroup.LayoutParams.WRAP_CONTENT
			))

			local edit = J.android.widget.EditText(activity)
			edit:setLayoutParams(LinearLayout.LayoutParams(
				0,
				ViewGroup.LayoutParams.WRAP_CONTENT,
				1	-- weight
			))
			if args.hint then edit:setHint(args.hint) end
			if args.text then edit:setText(args.text) end
			row:addView(edit)

			if args.click then
				local button = Button(activity)
				button:setText(args.button or '...')
				button:setOnClickListener(J.android.view.View.OnClickListener(args.click))
				row:addView(button)
			end

			sdlLaunchLayout:addView(row)

			return {
				edit = edit,
				button = button,
				row = row,
			}
		end
		projectRow = addRow{
			hint = 'projectDir',
			text = '/sdcard/Documents/Projects/lua',

			-- dir choose
			click = function()
				local intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
				intent:addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
				activity:startActivityForResult(intent, pickProjectFolder)
			end,
		}
		cwdRow = addRow{
			hint = 'cwd',

			-- TODO save in bundle and initialize as whatever teh external sd card dir is
			text = '/sdcard/Documents/Projects/lua/gl/tests',

			-- dir chooser here
			click = function()
				local intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
				intent:addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
				activity:startActivityForResult(intent, pickCwdFolder)
			end,
		}
		fileRow = addRow{
			hint = 'run',
			text = '/sdcard/Documents/Projects/lua/gl/tests/test_tex.lua',
			-- file chooser here
			click = function()
				local intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
				intent:addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
				activity:startActivityForResult(intent, pickLaunchFile)
			end,
		}

		-- local packageRow = addRow()	-- TODO package.path and package.cpath ...

		launchRow = addRow{
			hint = 'args',
			button = 'Go!',
			click = function()
				-- TODO how to get back to this ...
				launchSDL(activity)
			end,
		}

		activity:setContentView(sdlLaunchLayout)
	end

	local sdlMenu = getNextMenu()
	local prevOnCreateOptionsMenu = callbacks.onCreateOptionsMenu
	callbacks.onCreateOptionsMenu = function(activity, menu, ...)
		menu:add(0, sdlMenu, 0, 'SDL...')
		return prevOnCreateOptionsMenu(activity, menu, ...)
	end

	local prevOnOptionsItemSelected = callbacks.onOptionsItemSelected
	callbacks.onOptionsItemSelected = function(activity, item, ...)
		if item:getItemId() == sdlMenu then
			activity:setContentView(sdlLaunchLayout)
			return true
		end
		return prevOnOptionsItemSelected(activity, item, ...)
	end

	local prevOnActivityResult = callbacks.onActivityResult
	callbacks.onActivityResult = function(activity, requestCode, resultCode, data)
		prevOnActivityResult(activity, requestCode, resultCode, data)

		local requestIntVal = requestCode:intValue()
		if requestIntVal == pickCwdFolder then
			if resultCode:intValue() == Activity.RESULT_OK then
				local treeUri = data:getData()
				cwdRow.edit:setText(treeUri)
			end
		elseif requestIntVal == getNextActivity() then
			if resultCode:intValue() == Activity.RESULT_OK then
				local treeUri = data:getData()
				projectRow.edit:setText(treeUri)
			end
		elseif requestIntVal == pickLaunchFile then
			if resultCode:intValue() == Activity.RESULT_OK then
				local treeUri = data:getData()
				fileRow.edit:setText(treeUri)
			end
		end
	end

	--[[ TODO this wont work for SDLActivity, only the main UI laucnher's back button
	-- how to handle SDLActivity's backbutton?
	-- maybe I need to subclass it finally...
	local prevOnBackPressed = callbacks.onBackPressed
	callbacks.onBackPressed = function(activity, ...)
		-- terminate sdl activity?
		-- just switch back to sdl view?
		return activity:setContentView(sdlLaunchLayout)
		--return prevOnBackPressed(activity, ...)
	end
	--]]
end
--]=======]

return function(methodName, activity_, ...)
	collectgarbage()
	activity = activity_
	return assert.index(callbacks, methodName)(activity_, ...)
end
