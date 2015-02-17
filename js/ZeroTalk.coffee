class ZeroTalk extends ZeroFrame
	init: ->
		@log "inited!"
		@site_info = null
		@server_info = null
		@local_storage = {}

		@user_id_db = {} # { "address": 1 }
		@user_address_db = {} # { 1: "address" }
		@user_name_db = {} # { "address": "username" }

		@user_max_size = null # Max total file size allowed to user

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


	# All page content loaded
	pageLoaded: ->
		$("body").addClass("loaded") # Back/forward button keep position support


	# Wrapper websocket connection ready
	onOpenWebsocket: (e) =>
		@cmd "wrapperSetViewport", "width=device-width, initial-scale=1.0"
		@cmd "wrapperGetLocalStorage", [], (res) =>
			res ?= {}
			@local_storage = res

		@cmd "siteInfo", {}, (site) =>
			@setSiteinfo(site)
			@loadUserDb => # Load user DB then route url
				@updateUserInfo()
				@routeUrl(window.location.search.substring(1))

		@cmd "serverInfo", {}, (ret) => # Get server info
			@server_info = ret
			version = parseInt(@server_info.version.replace(/\./g, ""))
			if version < 20
				@cmd "wrapperNotification", ["error", "ZeroTalk requires ZeroNet 0.2.0, please update!"]


	routeUrl: (url) ->
		@log "Routing url:", url
		if match = url.match /Topic:([0-9]+)@([0-9]+)/
			$("body").addClass("page-topic")
			@pageTopic parseInt(match[1]), parseInt(match[2])
		else
			$("body").addClass("page-main")
			@pageMain()


	# - Pages -


	pageMain: ->
		$(".topics-loading").cssLater("top", "0px", 200)
		@loadTopics("noanim")

		# Show create new topic form
		$(".topic-new-link").on "click", =>
			$(".topic-new").fancySlideDown()
			$(".topic-new-link").slideUp()
			return false

		# Create new topic
		$(".topic-new .button-submit").on "click", =>
			if @user_name_db[@site_info.auth_address] # Check if user exits
				@buttonCreateTopic()
			else
				@cmd "wrapperNotification", ["info", "Please, request access before posting."]
			return false



	loadTopics: (type="normal", cb=false) ->
		s = (+ new Date)
		@cmd "fileQuery", ["data/users/*/data.json", "topics"], (topics) =>
			topics.sort (a, b) -> # Sort by date
				return a.added - b.added
			last_elem = null

			for topic in topics
				topic_address = topic.topic_id + "_" + @user_id_db[topic.inner_path]
				elem = $("#topic_"+topic_address)
				if elem.length == 0 # Create if not exits yet
					elem = $(".topics-list .topic.template").clone().removeClass("template").attr("id", "topic_"+topic_address)
					if type != "noanim"
						elem.cssSlideDown()
				@applyTopicData(elem, topic)

				if last_elem # Add after last elem
					last_elem.after(elem)
				else # Add to top
					elem.prependTo(".topics")
			$("body").css({"overflow": "auto", "height": "auto"}) # Auto height body

			# Hide loading
			if parseInt($(".topics-loading").css("top")) == 0 # Loading visible, animate it
				$(".topics-loading").css("top", "-30px").removeLater()
			else
				$(".topics-loading").remove()

			@log "Topics loaded in", (+ new Date)-s

			@addInlineEditors()

			@loadTopicsStat(type)

			if cb then cb()


	# Load all user data to fill last comments
	loadTopicsStat: (type="normal") =>
		s = (+ new Date)
		@cmd "fileQuery", ["data/users/*/data.json", ""], (users) =>
			$(".topics").css("opacity", 1)
			stats = []
			# Analyze user data files
			for user in users
				for topic_address, comments of user["comments"]
					topic_address = topic_address.replace("@", "_")
					for comment in comments
						stats[topic_address] ?= {"comments": 0, "last": null}
						last = stats[topic_address]["last"]
						stats[topic_address]["comments"] += 1
						if not last or comment["added"] > last["added"]
							comment["auth_address"] = user["inner_path"]
							stats[topic_address]["last"] = comment

			# Set html elements
			for topic_address, stat of stats
				$("#topic_#{topic_address} .comment-num").text "#{stat.comments} comment"
				$("#topic_#{topic_address} .added").text "last "+@formatSince(stat["last"]["added"])


			# Sort topics
			topics = ([topic_address, stat.last.added] for topic_address, stat of stats)
			topics.sort (a, b) -> # Sort by date
				return a[1] - b[1]

			for topic in topics
				topic_address = topic[0]
				elem = $("#topic_#{topic_address}")
				elem.prependTo ".topics"
				# Visited
				visited = @local_storage["topic.#{topic_address}.visited"]
				if not visited
					elem.addClass("visit-none")
				else if visited < topic[1]
					elem.addClass("visit-newcomment")

			@log "Topics stats loaded in", (+ new Date)-s



	pageTopic: (topic_id, topic_user_id) ->
		@topic_id = topic_id
		@topic_user_id = topic_user_id

		@loadTopic()
		@loadComments("noanim")

		@local_storage["topic.#{topic_id}_#{topic_user_id}.visited"] = @timestamp()
		@cmd "wrapperSetLocalStorage", @local_storage

		$(".comment-new .button-submit").on "click", =>
			if @user_name_db[@site_info.auth_address] # Check if user exits
				@buttonComment()
			else
				@cmd "wrapperNotification", ["info", "Please, request access before posting."]
			return false


	loadTopic: (cb=false)->
		topic_user_address = @user_address_db[@topic_user_id]
		# Load topic data
		@cmd "fileQuery", ["data/users/#{topic_user_address}/data.json", "topics.topic_id=#{@topic_id}"], (topic) =>
			topic = topic[0]
			topic["inner_path"] = topic_user_address # add user address
			@applyTopicData($(".topic-full"), topic, "full")
			$(".topic-full").css("opacity", 1)
			#$(".username-my").text(@user_name_db[user_address])
			$("body").addClass("page-topic")

			if cb then cb()


	loadComments: (type="normal", cb=false) ->
		topic_address = @topic_id+"@"+@topic_user_id
		# Load comments
		@cmd "fileQuery", ["data/users/*/data.json", "comments.#{topic_address}"], (comments) =>
			comments.sort (a, b) -> # Sort by date desc
				return b.added - a.added

			for comment in comments
				comment_address = "#{comment.comment_id}_#{comment.inner_path}"
				elem = $("#comment_"+comment_address)
				if elem.length == 0# Create if not exits
					elem = $(".comment.template").clone().removeClass("template").attr("id", "comment_"+comment_address).data("topic_address", topic_address)
					if type != "noanim"
						elem.cssSlideDown()
				@applyCommentData(elem, comment)
				elem.appendTo(".comments")

			$("body").css({"overflow": "auto", "height": "auto"})

			@addInlineEditors()

			if cb then cb()


	# - EOF Pages -


	# Update elem based on data of topic dict
	applyTopicData: (elem, topic, type="normal") ->
		title_hash = topic.title.replace(/[#,"'?& ]/g, "+").replace(/[+]+/g, "+").replace(/[+]+$/, "")
		user_id = @user_id_db[topic.inner_path]
		$(".title .title-link", elem).text(topic.title)
		$(".title .title-link, a.image, .comment-num", elem).attr("href", "?Topic:#{topic.topic_id}@#{user_id}/#{title_hash}")

		# Get links in body
		body = topic.body
		match = topic.body.match /http[s]{0,1}:\/\/[^"' $]+/
		if match # Link type topic
			if type != "full" then body = body.replace /http[s]{0,1}:\/\/[^"' $]+/g, "" # Remove links
			$(".image .icon", elem).removeClass("icon-topic-chat").addClass("icon-topic-link")
			$(".link", elem).css("display", "").attr("href", match[0])
			$(".link .link-url", elem).text(match[0])
		else # Normal type topic
			$(".image .icon", elem).removeClass("icon-topic-link").addClass("icon-topic-chat")
			$(".link", elem).css("display", "none")

		if type == "full" # Markdon syntax at topic page
			$(".body", elem).html marked(body, {"sanitize": true})
		else
			$(".body", elem).text body

		$(".username", elem).text(@user_name_db[topic.inner_path])
		$(".added", elem).text @formatSince(topic.added)

		# My topic
		if topic.inner_path == @site_info.auth_address
			$(elem).attr("data-object", "Topic:#{topic.topic_id}@#{user_id}").attr("data-deletable", "yes")
			$(".title .title-link", elem).attr("data-editable", "title").data("content", topic.title)
			$(".body", elem).attr("data-editable", "body").data("content", topic.body)



	# Update elem based on data of comment dict
	applyCommentData: (elem, comment) ->
		username = @user_name_db[comment.inner_path]
		$(".body", elem).html(marked(comment.body, {"sanitize": true}))
		$(".username", elem).text(username)
		$(".added", elem).text @formatSince(comment.added)


		# My comment
		if comment.inner_path == @site_info.auth_address
			user_id = @user_id_db[comment.inner_path]
			comment_id = elem.attr("id").replace("comment_", "").replace(/_.*$/, "")
			topic_address = elem.data("topic_address")
			$(elem).attr("data-object", "Comment:#{comment_id}@#{topic_address}").attr("data-deletable", "yes")
			$(".body", elem).attr("data-editable", "body").data("content", comment.body)


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

		inner_path = "data/users/#{@site_info.auth_address}/data.json"
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
							if $("body").hasClass("page-main") then @loadTopics "normal", ( -> if cb then cb(true) )
							if $("body").hasClass("page-topic") then @loadTopic ( -> if cb then cb(true) )
						if type == "Comment"
							@loadComments "normal", ( -> if cb then cb(true) )
				else
					if cb then cb(false)


	loadUserDb: (cb = null) ->
		@log "Loading userdb"
		@cmd "fileGet", ["data/users/content.json"], (data) =>
			data = JSON.parse(data)
			for path, user of data["includes"]
				address = user.signers[0]
				@user_id_db[address] = user.user_id
				@user_address_db[user.user_id] = address
				@user_name_db[address] = user.user_name
				if address == @site_info["auth_address"] # Current user
					@user_max_size = user.max_size
			if cb then cb()


	updateUserInfo: ->
		address = @site_info["auth_address"]
		user_name = @user_name_db[address] # Set my info
		if user_name # Registered user
			if $(".head-user.visitor").css("display") != "none" # Just registered successfuly
				$(".head-user.visitor").css("display", "none")
				@cmd "wrapperNotification", ["done", "Hello <b>#{user_name}</b>!<br>Congratulations, your registration is done!", 10000]
				$(".button.signup").removeClass("loading") 

			$(".head-user.registered").css("display", "")
			$(".username-my").text(user_name)
			@cmd "fileGet", ["data/users/#{address}/content.json"], (content) =>
				content = JSON.parse(content)
				sum = 0
				for relative_path, details of content.files
					sum += details.size
				$(".head-user .size").text("Used: #{(sum/1000).toFixed(1)}k / #{parseInt(@user_max_size/1000)}k")
				$(".head-user .size-used").width(parseFloat(sum/@user_max_size)*100)


		else # Not registered yet
			$(".head-user.visitor").css("display", "")
			$(".username-my").text("Visitor")


	buttonSignup: ->
		if not @needOpenPort() then return false

		@cmd "wrapperPrompt", ["Username you want to register:"], (user_name) => # Prompt the username
			$(".button.signup").addClass("loading") 
			$.post("http://demo.zeronet.io/ZeroTalk/signup.php", {"user_name": user_name, "auth_address": @site_info.auth_address}).always (res) =>
				if res == "OK"
					@cmd "wrapperNotification", ["done", "Your registration has been sent!", 10000]
				else
					$(".button.signup").removeClass("loading") 
					@cmd "wrapperNotification", ["error", "Error: #{res.responseText}"]


	buttonCreateTopic: ->
		if not @needOpenPort() then return false

		title = $(".topic-new #topic_title").val()
		body = $(".topic-new #topic_body").val()
		#if not body then return $(".topic-new #topic_body").focus()
		if not title then return $(".topic-new #topic_title").focus()

		$(".topic-new .button-submit").addClass("loading")
		inner_path = "data/users/#{@site_info.auth_address}/data.json"
		@cmd "fileGet", [inner_path], (data) =>
			data = JSON.parse(data)
			data.topics.push {
				"topic_id": data.next_topic_id,
				"title": title,
				"body": body,
				"added": @timestamp()
			}
			data.next_topic_id += 1
			@writePublish inner_path, @jsonEncode(data), (res) =>
				$(".topic-new .button-submit").removeClass("loading")
				if res == true
					@log "File written"
					$(".topic-new").slideUp()
					$(".topic-new-link").slideDown()
					setTimeout (=>
						@loadTopics()
					), 600
					$(".topic-new #topic_body").val("")
					$(".topic-new #topic_title").val("")

				else
					@cmd "wrapperNotification", ["error", "File write error: #{res}"]


	buttonComment: ->
		if not @needOpenPort() then return false

		body = $(".comment-new #comment_body").val()
		if not body then $(".comment-new #comment_body").focus()
		topic_address = @topic_id+"@"+@topic_user_id

		$(".comment-new .button-submit").addClass("loading")
		inner_path = "data/users/#{@site_info.auth_address}/data.json"
		@cmd "fileGet", [inner_path], (data) =>
			data = JSON.parse(data)
			data.comments[topic_address] ?= []
			data.comments[topic_address].push {
				"comment_id": data.next_message_id, 
				"body": body,
				"added": @timestamp()
			}
			data.next_message_id += 1
			@writePublish inner_path, @jsonEncode(data), (res) =>
				$(".comment-new .button-submit").removeClass("loading")
				if res == true
					@log "File written"
					@loadComments()
					$(".comment-new #comment_body").val("")



	jsonEncode: (obj) ->
		return btoa(unescape(encodeURIComponent(JSON.stringify(obj, undefined, '\t'))))


	writePublish: (inner_path, data, cb) ->
		@cmd "fileWrite", [inner_path, data], (res) =>
			if res != "ok" # fileWrite failed
				@cmd "wrapperNotification", ["error", "File write error: #{res}"]
				cb(false)
				return false

			@cmd "sitePublish", {"inner_path": inner_path}, (res) =>
				if res == "ok"
					cb(true)
				else
					cb(res)

					
	needOpenPort: ->
		if @server_info.ip_external 
			return true
		else # No port open
			@cmd "wrapperNotification", ["error", "To signup please open port <b>#{@server_info.fileserver_port}</b> on your router"]
			return false




	# - Date -

	formatSince: (time) ->
		now = +(new Date)/1000
		secs = now - time
		if secs < 60
			back = "Just now"
		else if secs < 60*60
			back = "#{Math.round(secs/60)} minutes ago"
		else if secs < 60*60*24
			back = "#{Math.round(secs/60/60)} hours ago"
		else if secs < 60*60*24*3
			back = "#{Math.round(secs/60/60/24)} days ago"
		else
			back = "on "+@formatDate(time)
		back = back.replace(/1 ([a-z]+)s/, "1 $1") # 1 days ago fix
		return back


	formatDate: (timestamp, format="short") ->
		parts = (new Date(timestamp*1000)).toString().split(" ")
		if format == "short"
			display = parts.slice(1, 4)
		else
			display = parts.slice(1, 5)
		return display.join(" ").replace(/( [0-9]{4})/, ",$1")


	timestamp: (date="") ->
		if date == "now" or date == ""
			return parseInt(+(new Date)/1000)
		else
			return parseInt(Date.parse(date)/1000)


	# Route incoming requests
	route: (cmd, message) ->
		if cmd == "setSiteInfo" # Site updated
			@actionSetSiteInfo(message)
		else
			@log "Unknown command", message


	# Siteinfo changed
	actionSetSiteInfo: (res) =>
		@setSiteinfo(res.params)
		if res.params.event and res.params.event[0] == "file_done" and res.params.event[1] == "data/users/#{@site_info.auth_address}/data.json" # Registration successful
			@updateUserInfo() # Set my info
		if res.params.event and res.params.event[0] == "file_done" and res.params.event[1] == "data/users/content.json" # New user
			@loadUserDb() # Reload userdb
		if res.params.event and res.params.event[0] == "file_done" and res.params.event[1].match /.*users.*data.json$/  # Data changed
			if $("body").hasClass("page-topic")
				@loadTopic()
				@loadComments()
			if $("body").hasClass("page-main")
				@loadTopics()



	setSiteinfo: (site_info) =>
		@site_info = site_info


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

		# Tab key support
		###
		elem.on 'keydown', (e) ->
			if e.which == 9
				e.preventDefault()
				s = this.selectionStart
				val = elem.val()
				elem.val(val.substring(0,this.selectionStart) + "\t" + val.substring(this.selectionEnd))
				this.selectionEnd = s+1; 
		###


window.zero_talk = new ZeroTalk()
