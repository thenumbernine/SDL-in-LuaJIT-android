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
	-- ok so we have this libmain which is the project C contribution
	-- it's usually got the lua call code
	-- but I also for this project squeezed in the SDL_main function as well, which is just a trampoline back to luajit world:
	-- however it's gonna run on a separate thread
	-- so it's gotta run on a separate Lua state ...
	local LiteThread = require 'thread.lite'
	_G.sdlMainThread = LiteThread{
		code = [[
print 'here from within the SDL_main thread'

local unistd = requrie 'ffi.req' 'c.unistd'
while true do
	unistd.sleep(1)
end

]]
	}
print('sdlMainThread.funcptr', sdlMainThread.funcptr)
	ffi.cdef[[void*(*SDL_main_callback)(void*);]]
	local main = ffi.load'main'
	main.SDL_main_callback = ffi.cast('void*(*)(void*)', sdlMainThread.funcptr)
print('main.SDL_main_callback', main.SDL_main_callback)

	local sdlMenu = getNextMenu()
	local prevOnCreateOptionsMenu = callbacks.onCreateOptionsMenu
	callbacks.onCreateOptionsMenu = function(activity, menu, ...)
		menu:add(0, sdlMenu, 0, 'SDL...')
		return prevOnCreateOptionsMenu(activity, menu, ...)
	end

	local prevOnOptionsItemSelected = callbacks.onOptionsItemSelected
	callbacks.onOptionsItemSelected = function(activity, item, ...)
		if item:getItemId() == sdlMenu then
			local SDLActivity = J.org.libsdl.app.SDLActivity
print('SDLActivity', SDLActivity)
			assert(require 'java.class':isa(SDLActivity), "failed to find org.libsdl.app.SDLActivity")
			local sdlIntent = Intent(activity, SDLActivity.class)
			sdlIntent:putExtra('SDL_LIB_NAME', 'main')
			activity:startActivity(sdlIntent)
print('done starting activity')
			return true
		end
		return prevOnOptionsItemSelected(activity, item, ...)
	end
end
--]=======]

return function(methodName, activity_, ...)
	collectgarbage()
	activity = activity_
	return assert.index(callbacks, methodName)(activity_, ...)
end
