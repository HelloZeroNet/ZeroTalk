# Variable namings:
# comment_uri: #{comment_id}_#{topic_id}_#{topic_user_id}
# topic_uri: #{topic_id}_#{topic_user_id}


class ZeroTalk extends ZeroFrame
	init: ->
		@log "inited!"
		@site_info = null  # Last site info response
		@server_info = null  # Last server info response
		@local_storage = {}  # Visited topics
		@site_address = null  # Site bitcoin address

		# Autoexpand
		for textarea in $("textarea")
			@autoExpand $(textarea)
		

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
			@site_address = site.address
			@setSiteinfo(site)
			User.updateMyInfo =>
				@routeUrl(window.location.search.substring(1))

		@cmd "serverInfo", {}, (ret) => # Get server info
			@server_info = ret
			version = parseInt(@server_info.version.replace(/\./g, ""))
			if version < 31
				@cmd "wrapperNotification", ["error", "ZeroTalk requires ZeroNet 0.3.1, please update!"]


	# All page content loaded
	onPageLoaded: ->
		$("body").addClass("loaded") # Back/forward button keep position support


	routeUrl: (url) ->
		@log "Routing url:", url
		if match = url.match /Topic:([0-9]+)_([0-9a-zA-Z]+)/  # Topic
			$("body").addClass("page-topic")
			TopicShow.actionShow parseInt(match[1]), Text.toBitcoinAddress(match[2])
			
		else if match = url.match /Topics:([0-9]+)_([0-9a-zA-Z]+)/  # Sub-topics
			$("body").addClass("page-topics")
			TopicList.actionList parseInt(match[1]), Text.toBitcoinAddress(match[2])
			
		else  # Main
			$("body").addClass("page-main")
			TopicList.actionList()


	addInlineEditors: ->
		@logStart "Adding inline editors"
		elems = $("[data-editable]") 
		for elem in elems
			elem = $(elem)
			if not elem.data("editor") and not elem.hasClass("editor")
				editor = new InlineEditor(elem, @getContent, @saveContent, @getObject)
				elem.data("editor", editor)
		@logEnd "Adding inline editors"


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

		User.getData (data) =>
			if type == "Topic"
				[topic_id, user_address] = id.split("_")
				topic_id = parseInt(topic_id)

				topic = (topic for topic in data.topic when topic.topic_id == topic_id)[0] 

				if delete_object # Delete
					data.topic.splice(data.topic.indexOf(topic), 1)
				else # Update
					topic[elem.data("editable")] = content

			if type == "Comment"
				[comment_uri, topic_uri] = id.split("@")
				[comment_id, user_address] = comment_uri.split("_")
				[topic_id, topic_creator_address] = topic_uri.split("_")
				comment_id = parseInt(comment_id)

				comment = (comment for comment in data.comment[topic_uri] when comment.comment_id == comment_id)[0]

				if delete_object # Delete
					data.comment[topic_uri].splice(data.comment[topic_uri].indexOf(comment), 1)
				else # Update
					comment[elem.data("editable")] = content

			User.publishData data, (res) =>
				if res
					if delete_object # Delete
						if cb then cb(true)
						elem.fancySlideUp()
					else # Update
						if type == "Topic"
							if $("body").hasClass("page-main") or $("body").hasClass("page-topics") then TopicList.loadTopics "list", ( -> if cb then cb(true) )
							if $("body").hasClass("page-topic") then TopicShow.loadTopic ( -> if cb then cb(true) )
						if type == "Comment"
							TopicShow.loadComments "normal", ( -> if cb then cb(true) )
				else
					if cb then cb(false)


	# Incoming request from ZeroNet API
	onRequest: (cmd, message) ->
		if cmd == "setSiteInfo" # Site updated
			@actionSetSiteInfo(message)
		else
			@log "Unknown command", message


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


	# Siteinfo changed
	actionSetSiteInfo: (res) =>
		site_info = res.params
		@setSiteinfo(site_info)
		if site_info.event and site_info.event[0] == "file_done" and site_info.event[1].match /.*users.*data.json$/  # Data changed
			RateLimit 500, =>
				if $("body").hasClass("page-topic")
					TopicShow.loadTopic()
					TopicShow.loadComments()
				if $("body").hasClass("page-main") or $("body").hasClass("page-topics")
					TopicList.loadTopics()



	setSiteinfo: (site_info) =>
		@site_info = site_info
		User.checkCert()


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
