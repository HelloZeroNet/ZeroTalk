class ZeroTalk extends ZeroFrame
	init: ->
		@log "inited!"
		@site_info = null
		@server_info = null
		@local_storage = {}
		@publishing = false

		#@user_id_db = {} # { "address": 1 }
		#@user_address_db = {} # { 1: "address" }
		#@user_name_db = {} # { "address": "username" }

		#@user_max_size = null # Max total file size allowed to user

		# Autoexpand
		for textarea in $("textarea")
			@autoExpand $(textarea)

		# Sign up
		$(".button.signup").on "click", =>
			@buttonSignup()
			return false

		# Markdown help
		$(".editbar .icon-help").on "click", =>
			$(".editbar .markdown-help").css("display", "block")
			$(".editbar .markdown-help").toggleClassLater("visible", 10)
			$(".editbar .icon-help").toggleClass("active")
			return false


	# Wrapper websocket connection ready
	onOpenWebsocket: (e) =>
		@cmd "wrapperSetViewport", "width=device-width, initial-scale=1.0"
		@cmd "wrapperGetLocalStorage", [], (res) =>
			res ?= {}
			@local_storage = res

		@cmd "siteInfo", {}, (site) =>
			@setSiteinfo(site)
			Users.loadDb => # Load user DB then route url
				Users.updateMyInfo()
				@routeUrl(window.location.search.substring(1))

		@cmd "serverInfo", {}, (ret) => # Get server info
			@server_info = ret
			version = parseInt(@server_info.version.replace(/\./g, ""))
			if version < 20
				@cmd "wrapperNotification", ["error", "ZeroTalk requires ZeroNet 0.2.0, please update!"]


	# All page content loaded
	onPageLoaded: ->
		$("body").addClass("loaded") # Back/forward button keep position support


	routeUrl: (url) ->
		@log "Routing url:", url
		if match = url.match /Topic:([0-9]+)@([0-9]+)/
			$("body").addClass("page-topic")
			TopicShow.actionShow parseInt(match[1]), parseInt(match[2])
		else
			$("body").addClass("page-main")
			TopicList.actionList()


	addInlineEditors: ->
		elems = $("[data-editable]") 
		for elem in elems
			elem = $(elem)
			if not elem.data("editor") and not elem.hasClass("editor")
				editor = new InlineEditor(elem, @getContent, @saveContent, @getObject)
				elem.data("editor", editor)


	# Get content
	getContent: (elem, raw=false) =>
		return elem.data("content")


	# Returns the elem parent object
	getObject: (elem) =>
		if elem.data("object") 
			return elem
		else
			return elem.parents("[data-object]") 


	# Save content
	saveContent: (elem, content, cb=false) =>
		if elem.data("deletable") and content == null # Its a delete request 
			delete_object = true
		else
			delete_object = false

		object = @getObject(elem)
		[type, id] = object.data("object").split(":") 

		inner_path = "data/users/#{Users.my_address}/data.json"
		@cmd "fileGet", [inner_path], (data) =>
			data = JSON.parse(data)

			if type == "Topic"
				[topic_id, user_id] = id.split("@")
				topic_id = parseInt(topic_id)

				topic = (topic for topic in data.topics when topic.topic_id == topic_id)[0] 

				if delete_object # Delete
					data.topics.splice(data.topics.indexOf(topic), 1)
				else # Update
					topic[elem.data("editable")] = content

			if type == "Comment"
				[comment_id, topic_id, topic_user_id] = id.split("@")
				comment_id = parseInt(comment_id)
				topic_address = topic_id+"@"+topic_user_id

				comment = (comment for comment in data.comments[topic_address] when comment.comment_id == comment_id)[0]

				if delete_object # Delete
					data.comments[topic_address].splice(data.comments[topic_address].indexOf(comment), 1)
				else # Update
					comment[elem.data("editable")] = content


			@writePublish inner_path, @jsonEncode(data), (res) =>
				if res == true
					if delete_object # Delete
						if cb then cb(true)
						elem.fancySlideUp()
					else # Update
						if type == "Topic"
							if $("body").hasClass("page-main") then TopicList.loadTopics "normal", ( -> if cb then cb(true) )
							if $("body").hasClass("page-topic") then TopicShow.loadTopic ( -> if cb then cb(true) )
						if type == "Comment"
							TopicShow.loadComments "normal", ( -> if cb then cb(true) )
				else
					if cb then cb(false)



	buttonSignup: ->
		if not @hasOpenPort() then return false

		@cmd "wrapperPrompt", ["Username you want to register:"], (user_name) => # Prompt the username
			$(".button.signup").addClass("loading") 
			$.post("http://demo.zeronet.io/ZeroTalk/signup.php", {"user_name": user_name, "auth_address": Users.my_address}).always (res) =>
				if res == "OK"
					@cmd "wrapperNotification", ["done", "Your registration has been sent!", 10000]
				else
					$(".button.signup").removeClass("loading") 
					@cmd "wrapperNotification", ["error", "Error: #{res.responseText}"]


	jsonEncode: (obj) ->
		return btoa(unescape(encodeURIComponent(JSON.stringify(obj, undefined, '\t'))))


	writePublish: (inner_path, data, cb) ->
		if @publishing
			@cmd "wrapperNotification", ["error", "Publishing in progress, please wait until its finished."]
			cb(false)
			return false
		@publishing = true
		@cmd "fileWrite", [inner_path, data], (res) =>
			if res != "ok" # fileWrite failed
				@cmd "wrapperNotification", ["error", "File write error: #{res}"]
				cb(false)
				@publishing = false
				return false

			@cmd "sitePublish", {"inner_path": inner_path}, (res) =>
				@publishing = false
				if res == "ok"
					cb(true)
				else
					cb(res)

					
	hasOpenPort: ->
		if @server_info.ip_external 
			return true
		else # No port open
			@cmd "wrapperNotification", ["error", "To publish new content please open port <b>#{@server_info.fileserver_port}</b> on your router"]
			return false


	# Route incoming requests
	route: (cmd, message) ->
		if cmd == "setSiteInfo" # Site updated
			@actionSetSiteInfo(message)
		else
			@log "Unknown command", message


	# Siteinfo changed
	actionSetSiteInfo: (res) =>
		site_info = res.params
		@setSiteinfo(site_info)
		if site_info.event and site_info.event[0] == "file_done" and site_info.event[1] == "data/users/#{Users.my_address}/data.json" # Registration successful
			Users.updateMyInfo() # Set my info
		if site_info.event and site_info.event[0] == "file_done" and site_info.event[1] == "data/users/content.json" # New user
			Users.loadDb() # Reload userdb
		if site_info.event and site_info.event[0] == "file_done" and site_info.event[1].match /.*users.*data.json$/  # Data changed
			LimitRate (=>
				if $("body").hasClass("page-topic")
					TopicShow.loadTopic()
					TopicShow.loadComments()
				if $("body").hasClass("page-main")
					TopicList.loadTopics()
			), 500



	setSiteinfo: (site_info) =>
		@site_info = site_info
		Users.my_address = site_info.auth_address


	autoExpand: (elem) ->
		editor = elem[0]
		# Autoexpand
		if elem.height() > 0 then elem.height(1)

		elem.on "input", ->
			if editor.scrollHeight > elem.height()
				old_height = elem.height()
				elem.height(1)
				new_height = editor.scrollHeight
				new_height += parseFloat elem.css("borderTopWidth")
				new_height += parseFloat elem.css("borderBottomWidth")
				new_height -= parseFloat elem.css("paddingTop")
				new_height -= parseFloat elem.css("paddingBottom")

				min_height = parseFloat(elem.css("lineHeight"))*2 # 2 line minimum
				if new_height < min_height then new_height = min_height+4

				elem.height(new_height-4)
		if elem.height() > 0 then elem.trigger "input"
		else elem.height("48px")


window.Page = new ZeroTalk()
