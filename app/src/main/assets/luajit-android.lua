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

local function getFilesForFolderChooserData(activity, data)
	local files = {}
	local treeUri = data:getData()
	activity:getContentResolver():takePersistableUriPermission(treeUri, J.android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)

	--[[ androidx method
	local directory = J.androidx.documentfile.provider.DocumentFile:fromTreeUri(activity, treeUri)
	for file in directory:listFiles():_iter() do
		table.insert(files, {
			type = file:getType(),
			uri = file:getUri(),
		})
	end
	--]]
	-- [[
	local DocumentsContract = J.android.provider.DocumentsContract
	local childrenUri = DocumentsContract:buildChildDocumentsUriUsingTree(
		treeUri,
		DocumentsContract:getTreeDocumentId(treeUri)
	)
	-- build string from Lua table...
	local cols = J:_newArray(J.String, 3);
	cols[0] = DocumentsContract.Document.COLUMN_DISPLAY_NAME;
	cols[1] = DocumentsContract.Document.COLUMN_DOCUMENT_ID;
	cols[2] = DocumentsContract.Document.COLUMN_MIME_TYPE;
	local cursor = activity:getContentResolver():query(childrenUri, cols, nil, nil, nil)
	while cursor:moveToNext() do
		local displayName = cursor:getString(0)
		local docId = cursor:getString(1)
		local fileType = cursor:getString(2)
		local fileUri = DocumentsContract:buildDocumentUriUsingTree(treeUri, docId)
		table.insert(files, {
			type = fileType and tostring(fileType),
			uri = fileUri,
		})
	end
	cursor:close()
	--]]

	return files
end

-- [=======[ attempt at just outputting the out.txt file
do
	local logScrollView
	--local viewSwitcher
	local logObserver
	local logUpdater

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

		--[=[ still segfaulting
print('creating ObserverRunnable...')
		local ObserverRunnable = J.Runnable:_subclass{
			isPublic = true,
			fields = {
				textView = {
					isPublic = true,
					isStatic = true,
					sig = textView._classpath,
				},
			},
			methods = {
				run = {
					isPublic = true,
					sig = {'void'},
					newLuaState = true,	-- back to the old thread but let's be safe?
					value = function(J, this)
						-- refreshFileContent:
						this.textView:setText(path'out.txt':read() or '')
					end,
				},
			}
		}
		ObserverRunnable.textView = textView
print('created ObserverRunnable.')

print('activity._classpath', activity._classpath)
print('ObserverRunnable._classpath', ObserverRunnable._classpath)
print('creating FileObserver...')
		local Observer = J.android.os.FileObserver:_subclass{
			isPublic = true,
			fields = {
				activity = {
					isPublic = true,
					sig = activity._classpath,
				},
				-- if I pass runnable in here, lua-java tries to query its class's reflection and android segfaults because android is retarded
				runnableClass = {
					isPublic = true,
					sig = 'java.lang.Class',
				},
			},
			methods = {
				onEvent = {
					isPublic = true,
					sig = {'void', 'int', 'java.lang.String'},
					newLuaState = true,	-- new thread, new lua state
					value = function(J, this, event, path)	-- newLuaState means 'J' first
						--[[
						this.activity:runOnUiThread(this.runnable)
						--]]
						-- [[ hmm segfaulting but outside of this call
						local ctor = this.runnableClass:getDeclaredConstructor()
						local runnable = ctor:newInstance()
						this.activity:runOnUiThread(runnable:_cast'java.lang.Runnable')
						--]]
					end,
				},
			},
		}
print('created FileObserver.')
		local fileToWatch = J.java.io.File(activity:getFilesDir(), 'out.txt')
		logObserver = Observer(fileToWatch:getPath(), Observer.MODIFY)
		logObserver.activity = activity
		logObserver.runnableClass = ObserverRunnable.class

		-- refreshFileContent:
		textView:setText(path'out.txt':read() or '')

		-- this gets a weird error:
		-- luajit: [string "java.jnienv"]:531: JVM java.lang.NullPointerException: Attempt to invoke interface method 'int java.util.List.size()' on a null object reference
		logObserver:startWatching()
		--]=]
		-- [=[ same but without FileObserver, just run a callback and watch the file and update
		local logFile = J.java.io.File'out.txt'
		local lastTextTime = logFile:lastModified()
		textView:setText(path'out.txt':read() or '')
		local Looper = J.android.os.Looper
		handler = J.android.os.Handler(Looper:getMainLooper())

		logUpdater = J.Runnable(function()
			local thisTextTime = logFile:lastModified()
			if thisTextTime > lastTextTime then
				lastTextTime = thisTextTime

				local isAtBottom = logScrollView:canScrollVertically(1)

				textView:setText(path'out.txt':read() or '')

				if isAtBottom then
					logScrollView:post(ScrollToBottomRunnable())
				end
			end
			handler:postDelayed(this, 2000)
		end)
		--]=]


		--[[ single view
		activity:setContentView(logScrollView)
		--]]
		--[[ view switcher
		viewSwitcher = J.android.widget.ViewSwitcher(activity)
		viewSwitcher:addView(logScrollView)
		--]]

print"onCreate DONE"
	end

	local prevOnResume = callbacks.onResume
	callbacks.onResume = function(activity)
		prevOnResume(activity)
		if logUpdater then
			handler:post(logUpdater)
		end
	end

	local prevOnPause = callbacks.onPause
	callbacks.onPause = function(activity)
		prevOnPause(activity)
		if logUpdater then
			handler:removeCallbacks(logUpdater)
		end
	end

	local prevOnDestroy = callbacks.onDestroy
	callbacks.onDestroy = function(activity)
		prevOnDestroy(activity)
		if logObserver then
			logObserver:stopWatching()
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
--[=======[ bluetooth scanner example ... gets back nothing and no errors *shrug*
do
	local BluetoothDevice = J.android.bluetooth.BluetoothDevice

	local receiver, bluetoothAdapter

	local prevOnCreate = callbacks.onCreate
	callbacks.onCreate = function(activity, savedInstanceState, ...)
		prevOnCreate(activity, savedInstanceState, ...)

		bluetoothAdapter = J.android.bluetooth.BluetoothAdapter:getDefaultAdapter()

		local BroadcastReceiver = J.android.content.BroadcastReceiver
		local Receiver = BroadcastReceiver:_subclass{
			isPublic = true,
			methods = {
				{
					name = 'onReceive',
					isPublic = true,
					sig = {'void', 'android.content.Context', 'android.content.Intent'},
					value = function(this, context, intent)
						local action = intent:getAction()
						if BluetoothDevice.ACTION_FOUND:equals(action) then
							local device = intent:getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
							local deviceName = device:getName()
							local deviceHardwareAddress = device:getAddress() -- MAC address
							-- Hidden devices will appear here if they are transmitting
print('found', deviceHardwareAddress, deviceName)
						end
					end,
				},
			},
		}
		receiver = Receiver()
print('registering receiver', receiver)

		local filter = J.android.content.IntentFilter(BluetoothDevice.ACTION_FOUND)
		activity:registerReceiver(receiver, filter)

		if not (bluetoothAdapter
		and bluetoothAdapter:isEnabled())
		then
			print('BLUETOOTH IS NOT ENABLED')
			return
		end

		bluetoothAdapter:startDiscovery()
print('onCreate DONE')
	end

	local prevOnDestroy = callbacks.onDestroy
	callbacks.onDestroy = function(activity, ...)
print('unregistering receiver', receiver)
		activity:unregisterReceiver(receiver)

		if bluetoothAdapter then
			bluetoothAdapter:cancelDiscovery()
		end

		prevOnDestroy(activity, ...)
	end
end
--]=======]
-- [=======[ directory image gallery example
do
	local ImageView = J.android.widget.ImageView

	local menuPickGalleryFolder = getNextMenu()
	local menuPickGalleryFolderOpen = getNextActivity()

	local galleryRootLayout
	local gridLayout

	-- these callbacks are centered around the original activity
	-- you can make a new activity and then provide its callbacks in Lua
		-- in order of how Android handles it:
	local prevOnCreate = callbacks.onCreate
	callbacks.onCreate = function(activity, ...)
		prevOnCreate(activity, ...)

		galleryRootLayout = LinearLayout(activity)
		galleryRootLayout:setLayoutParams(ViewGroup.LayoutParams(-1, -1))

		local toolbar = J.android.widget.Toolbar(activity)
		toolbar:setTitle'Image Preview Grid'
		toolbar:setBackgroundColor(0xFF6200EE)
		toolbar:setTitleTextColor(0xFFFFFFFF)
		galleryRootLayout:addView(toolbar)

		local scrollView = J.android.widget.ScrollView(activity)
		scrollView:setLayoutParams(LinearLayout.LayoutParams(-1, -1))

		gridLayout = J.android.widget.GridLayout(activity)
		gridLayout:setColumnCount(3)
		gridLayout:setLayoutParams(ViewGroup.LayoutParams(-1, -2))	-- WRAP_CONTENT height

		scrollView:addView(gridLayout)
		galleryRootLayout:addView(scrollView)

		--[[
		activity:setContentView(galleryRootLayout)
		--]]
	end

	local prevOnCreateOptionsMenu = callbacks.onCreateOptionsMenu
	callbacks.onCreateOptionsMenu = function(activity, menu, ...)
		menu:add(0, menuPickGalleryFolder, 0, 'Pictures...')
		return prevOnCreateOptionsMenu(activity, menu, ...)
	end

	local prevOnOptionsItemSelected = callbacks.onOptionsItemSelected
	callbacks.onOptionsItemSelected = function(activity, item, ...)
		if item:getItemId() == menuPickGalleryFolder then
			local intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
			intent:addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
			activity:startActivityForResult(intent, menuPickGalleryFolderOpen)
			return true
		end
		return prevOnOptionsItemSelected(activity, item, ...)
	end

	local prevOnActivityResult = callbacks.onActivityResult
	callbacks.onActivityResult = function(activity, requestCode, resultCode, data)
		prevOnActivityResult(activity, requestCode, resultCode, data)

		if requestCode:intValue() == menuPickGalleryFolderOpen
		and resultCode:intValue() == Activity.RESULT_OK
		then
			local files = getFilesForFolderChooserData(activity, data)

			gridLayout:removeAllViews()
			local size = activity:getResources():getDisplayMetrics().widthPixels / 3
			for _,file in ipairs(files) do
				local fileType = file.type
				if fileType and fileType:match'^image/' then
					-- ... do something here
					local img = ImageView(activity)
					img:setLayoutParams(ViewGroup.LayoutParams(size, size))
					img:setScaleType(ImageView.ScaleType.CENTER_CROP)
					img:setImageURI(file.uri)
					gridLayout:addView(img)
				end
			end

			-- finally, show the galleryRootLayout
			activity:setContentView(galleryRootLayout)
		end
	end
end
--]=======]
-- [=======[ audio player also?
do
	local menuPickMusicFolder = getNextMenu()
	local menuPickMusicFolderOpen = getNextActivity()

	local musicListView

	local prevOnCreate = callbacks.onCreate
	callbacks.onCreate = function(activity, ...)
		prevOnCreate(activity, ...)

		musicListView = J.android.widget.ListView(activity)
	end

	local prevOnCreateOptionsMenu = callbacks.onCreateOptionsMenu
	callbacks.onCreateOptionsMenu = function(activity, menu, ...)
		menu:add(0, menuPickMusicFolder, 0, 'Music...')
		return prevOnCreateOptionsMenu(activity, menu, ...)
	end

	local prevOnOptionsItemSelected = callbacks.onOptionsItemSelected
	callbacks.onOptionsItemSelected = function(activity, item, ...)
		if item:getItemId() == menuPickMusicFolder then
			local intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
			intent:addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
			activity:startActivityForResult(intent, menuPickMusicFolderOpen)
			return true
		end
		return prevOnOptionsItemSelected(activity, item, ...)
	end

	local prevOnActivityResult = callbacks.onActivityResult
	callbacks.onActivityResult = function(activity, requestCode, resultCode, data)
		prevOnActivityResult(activity, requestCode, resultCode, data)

		if requestCode:intValue() == menuPickMusicFolderOpen
		and resultCode:intValue() == Activity.RESULT_OK
		then
			-- clear old files
			musicListView:setAdapter(nil)

			-- do your thing
			local files = getFilesForFolderChooserData(activity, data)

			local audios = table()
_G.audios = audios	-- don't gc
			for _,file in ipairs(files) do
				local fileType = file.type
				if fileType and fileType:match'^audio/' then
					audios:insert(file)
				end
			end
			audios:sort(function(a,b) return tostring(a.uri) < tostring(b.uri) end)
			if #audios == 0 then
				print"COULDN'T FIND ANY AUDIO"
			else
				local MediaPlayer = J.android.media.MediaPlayer

				local mediaPlayer

				local isPaused 			-- because mediaplayer doesn't even know if it is paused. jk it does but whoever desigend the API didn't care to let you know.
				local audioIndex = 0	-- bump and play
				local currentPlayingIndex
				local function playNextTrack()
					if mediaPlayer then mediaPlayer:release() end

					-- load the next track from audios
					audioIndex = audioIndex + 1
					if audioIndex > #audios then return end

					currentPlayingIndex = audioIndex

					-- I guess you have to remake it for each song
					isPaused = false
					mediaPlayer = MediaPlayer:create(activity, audios[audioIndex].uri)
					mediaPlayer:setOnCompletionListener(MediaPlayer.OnCompletionListener(playNextTrack))
					mediaPlayer:start()
				end

				local ListViewAdapter = J.android.widget.BaseAdapter:_subclass{
					isPublic = true,
					methods = {
						getCount = {
							isPublic = true,
							sig = {'int'},
							value = function(this) return #audios end,
						},
						getItem = {
							isPublic = true,
							sig = {'java.lang.Object', 'int'},
							value = function(this, position) return audios[position+1].uri end,
						},
						getItemId = {
							isPublic = true,
							sig = {'long', 'int'},
							value = function(this, position) return position end,
						},
						getView = {
							isPublic = true,
							sig = {'android.view.View', 'int', 'android.view.View', 'android.view.ViewGroup'},
							value = function(this, position, convertView, parent)
								local View = J.android.view.View
								local Button = J.android.widget.Button

								local layout = LinearLayout(activity)
								layout:setOrientation(LinearLayout.HORIZONTAL)
								layout:setPadding(20, 20, 20, 20)

								local textView = J.android.widget.TextView(activity)
								textView:setText(tostring(audios[position+1].uri))
								textView:setLayoutParams(LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1))
								layout:addView(textView)

								local playButton = Button(activity)
								playButton:setText("Play")
								playButton:setOnClickListener(View.OnClickListener(function()
									if position+1 == currentPlayingIndex
									and mediaPlayer
									then
										if isPaused then
											isPaused = false
											mediaPlayer:start()
										else
											isPaused = true
											mediaPlayer:pause()
										end
									else
										audioIndex = position	-- index-1, but index is 1-based and position is 0-based
										playNextTrack()
									end
								end))
								layout:addView(playButton)

								return layout
							end,
						},
					},
				}

				musicListView:setAdapter(ListViewAdapter())

				playNextTrack()

				activity:setContentView(musicListView)
			end
		end
	end
end
--]=======]
-- [=======[ GLES view
do
	local GLSurfaceView = J.android.opengl.GLSurfaceView

	local prevOnCreate = callbacks.onCreate
	callbacks.onCreate = function(activity, ...)
		prevOnCreate(activity, ...)

		_G.glView = GLSurfaceView(activity)
		glView:setEGLContextClientVersion(3) -- GLES3.0

-- [====[ fps test.  make some empty lite-thread functions and test their call rate.
--]====]
-- [====[ do something GL:
		local Renderer = GLSurfaceView.Renderer:_subclass{
			isPublic = true,
			methods = {
				onSurfaceCreated = {
					isPublic = true,
					newLuaState = true,
					sig = {'void', 'javax.microedition.khronos.opengles.GL10', 'javax.microedition.khronos.egl.EGLConfig'},
					value = function(J, this, gl10, eglConfig)
						-- this is run in the GL thread's separate lua state

xpcall(function()

	-- even with EGL swap interval disabled ... still runs at 30 fps
	local ffi = require 'ffi'
	ffi.cdef[[
typedef unsigned int EGLBoolean;
typedef int32_t EGLint;
typedef void *EGLDisplay;
EGLDisplay eglGetDisplay(void*);
EGLBoolean eglSwapInterval(EGLDisplay, EGLint);
]]
	local egllib = ffi.load'EGL'
	local display = egllib.eglGetDisplay(nil)
	egllib.eglSwapInterval(display, 0)	-- setting 0 setting 1 doesnt change the cap at 30fps

	-- hmm, can I just require 'gl' and everything will work fine?
	-- is there a libGL that ffi.load can just link into?
	-- more importantly, do i want to add gl/ to the assets/ folder?
	-- or should that just be for sub-projects?

	local gl = J.android.opengl.GLES30

	local glVersion = gl:glGetString(gl.GL_VERSION)
	print('glVersion', glVersion)
	local glslVersion = gl:glGetString(gl.GL_SHADING_LANGUAGE_VERSION)
	print('glslVersion', glslVersion)


	local versionHeader = '#version 320 es\n'
	local vertexShaderID = gl:glCreateShader(gl.GL_VERTEX_SHADER)
	local code = versionHeader..[[
precision highp float;
in vec2 vertex;
in vec3 color;
out vec4 colorv;
void main() {
	colorv = vec4(color, 1.);
	gl_Position = vec4(vertex, 0., 1.);
}
]]
	gl:glShaderSource(vertexShaderID, code)
	gl:glCompileShader(vertexShaderID)
	local status = J:_newArray('int', 1)
	gl:glGetShaderiv(vertexShaderID, gl.GL_COMPILE_STATUS, status, 0)
	print('vertex shader compile status', status[0])
	local log = gl:glGetShaderInfoLog(vertexShaderID)
	print'log:'
	print(log)

	local fragmentShaderID = gl:glCreateShader(gl.GL_FRAGMENT_SHADER)
	local code = versionHeader..[[
precision highp float;
in vec4 colorv;
out vec4 fragColor;
void main() {
	fragColor = colorv;
}
]]
	gl:glShaderSource(fragmentShaderID, code)
	gl:glCompileShader(fragmentShaderID)
	local status = J:_newArray('int', 1)
	gl:glGetShaderiv(fragmentShaderID, gl.GL_COMPILE_STATUS, status, 0)
	print('fragment shader compile status', status[0])
	local log = gl:glGetShaderInfoLog(fragmentShaderID)
	print'log:'
	print(log)

	programID = gl:glCreateProgram()
	gl:glAttachShader(programID, vertexShaderID)
	gl:glAttachShader(programID, fragmentShaderID)
	gl:glLinkProgram(programID)
	gl:glDetachShader(programID, vertexShaderID)
	gl:glDetachShader(programID, fragmentShaderID)
	local status = J:_newArray('int', 1)
	gl:glGetProgramiv(programID, gl.GL_LINK_STATUS, status, 0)
	print('program link status', status[0])
	local log = gl:glGetProgramInfoLog(programID)
	print'log:'
	print(log)

	local FloatBuffer = J.java.nio.FloatBuffer

	-- weird, FloatBuffer:allocate + :array() didn't error and didn't show anything,
	-- but newArray'float' + FloatBuffer:wrap() did show stuff and work.
	local vertexDataArray = J:_newArray('float', 6)
	for i,v in ipairs{
		-5/6, -4/6,
		5/6, -4/6,
		0, 6/6
	} do
		vertexDataArray[i-1] = v
	end
	local vertexData = FloatBuffer:wrap(vertexDataArray)

	do
		local id = J:_newArray('int', 1)
		gl:glGenBuffers(1, id, 0)
		vertexBufferID = id[0]
		gl:glBindBuffer(gl.GL_ARRAY_BUFFER, vertexBufferID)
		gl:glBufferData(gl.GL_ARRAY_BUFFER, #vertexDataArray * 4, vertexData, gl.GL_STATIC_DRAW)
		gl:glBindBuffer(gl.GL_ARRAY_BUFFER, 0)
	end

	local colorDataArray = J:_newArray('float', 9)
	for i,v in ipairs{
		1, 0, 0,
		0, 1, 0,
		0, 0, 1
	} do
		colorDataArray[i-1] = v
	end
	local colorData = FloatBuffer:wrap(colorDataArray)

	do
		local id = J:_newArray('int', 1)
		gl:glGenBuffers(1, id, 0)
		colorBufferID = id[0]
		gl:glBindBuffer(gl.GL_ARRAY_BUFFER, colorBufferID)
		gl:glBufferData(gl.GL_ARRAY_BUFFER, #colorDataArray * 4, colorData, gl.GL_STATIC_DRAW)
		gl:glBindBuffer(gl.GL_ARRAY_BUFFER, 0)
	end

	vertexAttrLoc = gl:glGetAttribLocation(programID, 'vertex')
	colorAttrLoc = gl:glGetAttribLocation(programID, 'color')

	-- [[ vao or not
	local id = J:_newArray('int', 1)
	gl:glGenVertexArrays(1, id, 0)
	vaoID = id[0]
	gl:glBindVertexArray(vaoID)

	gl:glEnableVertexAttribArray(vertexAttrLoc)
	gl:glBindBuffer(gl.GL_ARRAY_BUFFER, vertexBufferID)
	gl:glVertexAttribPointer(vertexAttrLoc, 2, gl.GL_FLOAT, false, 0, 0)
	gl:glBindBuffer(gl.GL_ARRAY_BUFFER, 0)

	gl:glEnableVertexAttribArray(colorAttrLoc)
	gl:glBindBuffer(gl.GL_ARRAY_BUFFER, colorBufferID)
	gl:glVertexAttribPointer(colorAttrLoc, 3, gl.GL_FLOAT, false, 0, 0)
	gl:glBindBuffer(gl.GL_ARRAY_BUFFER, 0)

	gl:glBindVertexArray(0)
	--]]

end, function(err)
	-- TODO this is a good argument to remove the xpcall altogether from lite-thread and make them handle their own errors
	print('onSurfaceCreated err: '..err..'\n'..debug.traceback())
end)
					end,
				},
				onSurfaceChanged = {
					isPublic = true,
					newLuaState = true,
					sig = {'void', 'javax.microedition.khronos.opengles.GL10', 'int', 'int'},
					value = function(J, this, gl10, width_, height_)
						-- this is run in the GL thread's separate lua state

	width = width_
	height = height_

	local gl = J.android.opengl.GLES30
	gl:glViewport(0,0,width,height)
					end,
				},
				onDrawFrame = {
					isPublic = true,
					newLuaState = true,
					sig = {'void', 'javax.microedition.khronos.opengles.GL10'},
					value = function(J, this, gl10)
						-- this is run in the GL thread's separate lua state
xpcall(function()

	local t = require 'ext.timer'.getTime()
	local tsec = math.floor(t)

	local gl = J.android.opengl.GLES30


	--[[
	local r = .5 + .5 * math.cos(t)
	local g = .5 + .5 * math.cos(t * 1.2)
	local b = .5 + .5 * math.cos(t * 1.4)
	gl:glClearColor(r, g, b, 1)
	--]]
	gl:glClear(gl.GL_COLOR_BUFFER_BIT)

	-- do something GL here

	gl:glUseProgram(programID)

	if vaoID then
		gl:glBindVertexArray(vaoID)
	else
		gl:glEnableVertexAttribArray(vertexAttrLoc)
		gl:glBindBuffer(gl.GL_ARRAY_BUFFER, vertexBufferID)
		gl:glVertexAttribPointer(vertexAttrLoc, 2, gl.GL_FLOAT, false, 0, 0)
		gl:glBindBuffer(gl.GL_ARRAY_BUFFER, 0)

		gl:glEnableVertexAttribArray(colorAttrLoc)
		gl:glBindBuffer(gl.GL_ARRAY_BUFFER, colorBufferID)
		gl:glVertexAttribPointer(colorAttrLoc, 3, gl.GL_FLOAT, false, 0, 0)
		gl:glBindBuffer(gl.GL_ARRAY_BUFFER, 0)
	end

	gl:glDrawArrays(gl.GL_TRIANGLES, 0, 3)

	if vaoID then
		gl:glBindVertexArray(0)
	else
		gl:glDisableVertexAttribArray(vertexAttrLoc)
		gl:glDisableVertexAttribArray(colorAttrLoc)
	end

	gl:glUseProgram(0)

	-- memory?
	fps = (fps or 0) + 1
	if not lastTime or lastTime ~= tsec then
		lastTime = tsec

		local Debug = J.android.os.Debug
		local mem = Debug.MemoryInfo()
		Debug:getMemoryInfo(mem)
		print('fps '..fps..' mem: '..tostring(mem:getTotalPss())..'kb')
		fps = 0
	end

	-- [[ without collectgarbage() the OS would kill the app after a few minutes
	-- with collectgarbage() it ran forever, and hovered at 60MB memory usage
	collectgarbage()
	--]]

end, function(err)
	-- TODO this is a good argument to remove the xpcall altogether from lite-thread and make them handle their own errors
	print('onDrawFrame err: '..err..'\n'..debug.traceback())
end)
					end,
				},
			},
		}
--]====]

		-- now, if the Renderer does die, checking its state can be done with ...
		--require 'java.luaclass'.savedClosures[Renderer._classpath][i].thread:showErr()
		-- a mouthful
		-- but
		-- don't do that before it's done running
		-- or you could get a race condition on the sub lua State
		-- (now how to detect if it's done running or not...)

		_G.renderer = Renderer()
		glView:setRenderer(renderer)

		--[[ "Note that GLSurfaceView naturally synchronizes with the display's VSync. To push frames faster than the screen can show, you may need to bypass GLSurfaceView and use a raw SurfaceHolder or SurfaceTexture."
		-- hmmm
		-- FrameRateCompatibility is missing anyways
		activity
			:getWindow()
			:getAttributes()
			:setFrameRate(120, J.android.view.Window.FrameRateCompatibility.FRAME_RATE_COMPATIBILITY_DEFAULT)
		--]]
	end

	local glMenuPickFolder = getNextMenu()
	local prevOnCreateOptionsMenu = callbacks.onCreateOptionsMenu
	callbacks.onCreateOptionsMenu = function(activity, menu, ...)
		menu:add(0, glMenuPickFolder, 0, 'GLES...')
		return prevOnCreateOptionsMenu(activity, menu, ...)
	end

	local prevOnOptionsItemSelected = callbacks.onOptionsItemSelected
	callbacks.onOptionsItemSelected = function(activity, item, ...)
		if item:getItemId() == glMenuPickFolder then
			activity:setContentView(glView)
			return true
		end
		return prevOnOptionsItemSelected(activity, item, ...)
	end

	local prevOnPause = callbacks.onPause
	callbacks.onPause = function(activity, ...)
		prevOnPause(activity, ...)
		if glView ~= nil then
			glView:onPause()
		end
	end

	local prevOnResume = callbacks.onResume
	callbacks.onResume = function(activity, ...)
		prevOnResume(activity, ...)
		if glView ~= nil then
			glView:onResume()
		end
	end
end
--]=======]
-- [=======[  bluetooth le scanner example
do
	local PackageManager = J.android.content.pm.PackageManager

	local function proceedWithScan()

		local bluetoothManager = activity:getSystemService(J.android.content.Context.BLUETOOTH_SERVICE)
			:_cast(J.android.bluetooth.BluetoothManager)
		local bluetoothLeScanner = bluetoothManager:getAdapter():getBluetoothLeScanner()

		local LeScanCallback = J.android.bluetooth.le.ScanCallback:_subclass{
			methods = {
				onScanResult = {
					isPublic = true,
					sig = {'void', 'int', 'android.bluetooth.le.ScanResult'},
					value = function(this, callbackType, result)
						local device = result:getDevice()
						local name = device:getName()
						local address = device:getAddress()
						local rssi = result:getRssi()
						print("BLE_SCAN Found: " .. name .. " [" .. address .. "] RSSI: " .. rssi)
					end,
				},
				onScanFailed = {
					isPublic = true,
					sig = {'void', 'int'},
					value = function(this, errorCode)
						print("BLE_SCAN Scan failed with error: " .. errorCode)
					end,
				},
			},
		}
		bluetoothLeScanner:startScan(LeScanCallback())
	end

	local menuScanBluetooth = getNextMenu()
	local prevOnCreateOptionsMenu = callbacks.onCreateOptionsMenu
	callbacks.onCreateOptionsMenu = function(activity, menu, ...)
		menu:add(0, menuScanBluetooth, 0, 'BT LE Scan...')
		return prevOnCreateOptionsMenu(activity, menu, ...)
	end

	local btScanActivityCode = getNextActivity()
	local prevOnOptionsItemSelected = callbacks.onOptionsItemSelected
	callbacks.onOptionsItemSelected = function(activity, item, ...)
		if item:getItemId() == menuScanBluetooth then
			-- FUN RETARDED FACT ABOUT GOOGLE
			-- THE CONSTANT BLUETOOTH_SCAN IS MISSING WHEN YOU NEED IT,
			-- BUT IT MAGICALLY APPEARS ONLY AFTER YOU DON'T NEED IT
			-- GENUIS, GOOGLE.
			--if activity:checkSelfPermission(J.android.Manifest.permission.BLUETOOTH_SCAN)
			if activity:checkSelfPermission'android.permission.BLUETOOTH_SCAN'
			~= PackageManager.PERMISSION_GRANTED
			then
				local perms = J:_newArray(J.String, 1)
				perms[0] = 'android.permission.BLUETOOTH_SCAN'
				activity:requestPermissions(perms, btScanActivityCode)
			else
				proceedWithScan()
			end
			return true
		end

		return prevOnOptionsItemSelected(activity, item, ...)
	end

	local prevOnRequestPermissionsResult = callbacks.prevOnRequestPermissionsResult
	callbacks.onRequestPermissionsResult = function(activity, requestCode, permissions, grantResults, ...)
		-- ... could be deviceId or empty
		if requestCode == btScanActivityCode then
			if #grantResults.length > 0
			and grantResults[0] == PackageManager.PERMISSION_GRANTED
			then
				proceedWithScan()
			else
				print("BT_ERROR User denied Bluetooth Scan permission.")
			end
		end
	end
end
--]=======]
--[=======[ how about an editor UI for the whole thing, so I don't have to keep editing stuff and adb-pushing it?
-- but really ... I don't want to make an editor.  mine would suck.
-- instead, how about I plug vim into all this?  have it invoke termux-vim or something?
do
	local editorView
	local editorTextView
	local fontSize = 20




	local prevOnCreate = callbacks.onCreate
	callbacks.onCreate = function(activity, ...)
		prevOnCreate(activity, ...)

		-- build UI for editor

		local RelativeLayout = J.android.widget.RelativeLayout
		editorView = RelativeLayout(activity)
		editorView:setLayoutParams(RelativeLayout.LayoutParams(
			ViewGroup.LayoutParams.MATCH_PARENT,
			ViewGroup.LayoutParams.MATCH_PARENT
		))

		local bottomMenu
		do
			bottomMenu = LinearLayout(activity)
			bottomMenu:setId(View:generateViewId())
			bottomMenu:setOrientation(LinearLayout.HORIZONTAL)
			local params = RelativeLayout.LayoutParams(
				RelativeLayout.LayoutParams.MATCH_PARENT,
				RelativeLayout.LayoutParams.WRAP_CONTENT
			)
			params:addRule(RelativeLayout.ALIGN_PARENT_BOTTOM)
			bottomMenu:setLayoutParams(params)

			local function changeChapter(delta)
				local i = allChapters:find(currentChapter)
				if i then	-- won't find if we're not viewing a chapter (mabye grey out or hide icons?)
					local newChapter = allChapters[i+delta]
					if newChapter then
						showAndAddHistory{
							currentChapter = newChapter,
							currentBook = newChapter.book,
							showID = showIDs.verses,
						}
					end
				end
			end

			local uiFontSize = 20

			local buttonPrev = Button(activity)
			buttonPrev:setText'<'
			buttonPrev:setTextSize(TypedValue.COMPLEX_UNIT_SP, uiFontSize)
			buttonPrev:setLayoutParams(LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1))
			buttonPrev:setOnClickListener(View.OnClickListener(function()
				changeChapter(-1)
			end))
			bottomMenu:addView(buttonPrev)

			local buttonFontMinus = Button(activity)
			buttonFontMinus:setText'-'
			buttonFontMinus:setTextSize(TypedValue.COMPLEX_UNIT_SP, uiFontSize)
			buttonFontMinus:setLayoutParams(LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1))
			buttonFontMinus:setOnClickListener(View.OnClickListener(function()
				fontSize = math.max(4, fontSize - 2)
				refreshFontSize()
			end))
			bottomMenu:addView(buttonFontMinus)

			local buttonFontPlus = Button(activity)
			buttonFontPlus:setText'+'
			buttonFontPlus:setTextSize(TypedValue.COMPLEX_UNIT_SP, uiFontSize)
			buttonFontPlus:setLayoutParams(LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1))
			buttonFontPlus:setOnClickListener(View.OnClickListener(function()
				fontSize = fontSize + 2	-- upper bound?  exponential curve?
				refreshFontSize()
			end))
			bottomMenu:addView(buttonFontPlus)

			local buttonNext = Button(activity)
			buttonNext:setText'>'
			buttonNext:setTextSize(TypedValue.COMPLEX_UNIT_SP, uiFontSize)
			buttonNext:setLayoutParams(LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1))
			buttonNext:setOnClickListener(View.OnClickListener(function()
				changeChapter(1)
			end))
			bottomMenu:addView(buttonNext)
		end

		local readerScrollView = J.android.widget.ScrollView(activity)
		local params = RelativeLayout.LayoutParams(
			ViewGroup.LayoutParams.MATCH_PARENT,
			ViewGroup.LayoutParams.MATCH_PARENT
		)
		params:addRule(RelativeLayout.ALIGN_PARENT_TOP)
		params:addRule(RelativeLayout.ABOVE, bottomMenu:getId())
		readerScrollView:setLayoutParams(params)
		editorView:addView(readerScrollView)

		editorTextView = J.android.widget.TextView(activity)
		editorTextView:setLayoutParams(ViewGroup.LayoutParams(
			ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT
		))
		editorTextView:setPadding(16, 16, 16, 16)
		refreshFontSize()
		editorTextView:setTextIsSelectable(true)
		readerScrollView:addView(editorTextView)

		-- has to be added last? or order doesn't matter because the ALIGN_PARENT_TOP rule?
		editorView:addView(bottomMenu)
	end

	local menuEditFile = getNextMenu()
	local prevOnCreateOptionsMenu = callbacks.onCreateOptionsMenu
	callbacks.onCreateOptionsMenu = function(activity, menu, ...)
		menu:add(0, menuEditFile, 0, 'Open...')
		return prevOnCreateOptionsMenu(activity, menu, ...)
	end

	local prevOnOptionsItemSelected = callbacks.onOptionsItemSelected
	callbacks.onOptionsItemSelected = function(activity, item, ...)
		if item:getItemId() == menuEditFile then
			-- do open folder and choose file

			return true
		end
		return prevOnOptionsItemSelected(activity, item, ...)
	end
end
--]=======]

collectgarbage()
return function(methodName, activity_, ...)
	activity = activity_
	return assert.index(callbacks, methodName)(activity_, ...)
end
