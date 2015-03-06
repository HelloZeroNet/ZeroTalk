class TopicList extends Class
	constructor: ->
		@thread_sorter = null


	actionList: ->
		$(".topics-loading").cssLater("top", "0px", 200)
		@loadTopics("noanim")

		# Show create new topic form
		$(".topic-new-link").on "click", =>
			$(".topic-new").fancySlideDown()
			$(".topic-new-link").slideUp()
			return false

		# Create new topic
		$(".topic-new .button-submit").on "click", =>
			if Users.to_name[Users.my_address] # Check if user exits
				@submitCreateTopic()
			else
				Page.cmd "wrapperNotification", ["info", "Please, request access before posting."]
			return false


	loadTopics: (type="normal", cb=false) ->
		@logStart "Load topics..."
		Page.cmd "fileQuery", ["data/users/*/data.json", "topics"], (topics) =>
			topics.sort (a, b) -> # Sort by date
				return a.added - b.added
			last_elem = null

			for topic in topics
				topic_address = topic.topic_id + "_" + Users.to_id[topic.inner_path]
				elem = $("#topic_"+topic_address)
				if elem.length == 0 # Create if not exits yet
					elem = $(".topics-list .topic.template").clone().removeClass("template").attr("id", "topic_"+topic_address)
					if type != "noanim"
						elem.cssSlideDown()
					elem.appendTo(".topics")
				@applyTopicData(elem, topic)

			$("body").css({"overflow": "auto", "height": "auto"}) # Auto height body

			# Hide loading

			if parseInt($(".topics-loading").css("top")) > -30 # Loading visible, animate it
				$(".topics-loading").css("top", "-30px")
			else
				$(".topics-loading").remove()

			@logEnd "Load topics..."

			Page.addInlineEditors()

			if Page.site_info.tasks == 0 # No tasks active, sort it now
				@loadTopicsStat(type)
			else # Workers active, wait 100ms before sort
				clearInterval(@thread_sorter)
				@thread_sorter = setTimeout (=>
					@loadTopicsStat(type)
				), 100


			if cb then cb()


	# Load all user data to fill last comments
	loadTopicsStat: (type="normal") =>
		@logStart "Load topics stats..."
		Page.cmd "fileQuery", ["data/users/*/data.json", ""], (users) =>
			$(".topics").css("opacity", 1)
			stats = []
			my_topic_votes = {}
			# Analyze user data files
			for user in users
				user_id = Users.to_id[user.inner_path]
				for topic in user.topics
					topic_address = "#{topic.topic_id}_#{user_id}"
					if not stats[topic_address]?
						stats[topic_address] = {"comments": 0, "last": {"added": topic.added}, "votes": 1}

				# Topic votes
				for topic_address, vote of user["topic_votes"]
					topic_address = topic_address.replace("@", "_")
					stats[topic_address] ?= {"comments": 0, "last": null, "votes": 1}
					if vote == 1 then stats[topic_address]["votes"] += 1

				# My votes
				if user_id == Users.my_id
					my_topic_votes = user["topic_votes"]

				# Get latest comment and count of topic
				for topic_address, comments of user["comments"]
					topic_address = topic_address.replace("@", "_")
					for comment in comments
						stats[topic_address] ?= {"comments": 0, "last": null, "votes": 1}
						last = stats[topic_address]["last"]
						stats[topic_address]["comments"] += 1
						if not last or comment["added"] > last["added"]
							comment["auth_address"] = user["inner_path"]
							stats[topic_address]["last"] = comment

			# Set html elements
			for topic_address, stat of stats
				elem = $("#topic_#{topic_address}")
				# Comments
				if stat.comments > 0 and type != "full"
					$(".comment-num", elem).text "#{stat.comments} comment"
					$(".added", elem).text "last "+Time.since(stat["last"]["added"])
				# Votes
				if my_topic_votes?[topic_address.replace("_", "@")] # Voted on it
					$(".score-inactive .score-num", elem).text stat["votes"]-1
					$(".score-active .score-num", elem).text stat["votes"]
					$(".score", elem).addClass("active")
				else # Not voted on it
					$(".score-inactive .score-num", elem).text stat["votes"]
					$(".score-active .score-num", elem).text stat["votes"]+1
				$(".score", elem).off("click").on "click", @submitTopicVote


			# Sort topics
			if type != "full"
				topics = ([topic_address, stat.last.added] for topic_address, stat of stats)
				topics.sort (a, b) -> # Sort by date
					return a[1] - b[1]

				for topic in topics
					topic_address = topic[0]
					elem = $("#topic_#{topic_address}")
					elem.prependTo ".topics"
					# Visited
					visited = Page.local_storage["topic.#{topic_address}.visited"]
					if not visited
						elem.addClass("visit-none")
					else if visited < topic[1]
						elem.addClass("visit-newcomment")
			@logEnd "Load topics stats..."



	applyTopicData: (elem, topic, type="normal") ->
		title_hash = topic.title.replace(/[#,"'?& ]/g, "+").replace(/[+]+/g, "+").replace(/[+]+$/, "")
		user_id = Users.to_id[topic.inner_path]
		topic_address = topic.topic_id+"@"+user_id
		$(".title .title-link", elem).text(topic.title)
		$(".title .title-link, a.image, .comment-num", elem).attr("href", "?Topic:#{topic_address}/#{title_hash}")
		elem.data "topic_address", topic_address

		# Get links in body
		body = topic.body
		match = topic.body.match /http[s]{0,1}:\/\/[^"', $]+/
		if match # Link type topic
			url = match[0]
			if type != "full" then body = body.replace /http[s]{0,1}:\/\/[^"' $]+/g, "" # Remove links
			$(".image .icon", elem).removeClass("icon-topic-chat").addClass("icon-topic-link")
			$(".link", elem).css("display", "").attr "href", url.replace(/http:\/\/(127.0.0.1|localhost):43110/, "")
			$(".link .link-url", elem).text(url)
		else # Normal type topic
			$(".image .icon", elem).removeClass("icon-topic-link").addClass("icon-topic-chat")
			$(".link", elem).css("display", "none")

		if type == "full" # Markdon syntax at topic page
			$(".body", elem).html Text.toMarked(body, {"sanitize": true})
		else
			$(".body", elem).text body

		user_name = Users.to_name[topic.inner_path]
		$(".user_name", elem).text(user_name)
		if type == "full" then $(".added", elem).text Time.since(topic.added)

		# My topic
		if topic.inner_path == Users.my_address
			$(elem).attr("data-object", "Topic:#{topic_address}").attr("data-deletable", "yes")
			$(".title .title-link", elem).attr("data-editable", "title").data("content", topic.title)
			$(".body", elem).attr("data-editable", "body").data("content", topic.body)


	submitCreateTopic: ->
		if not Page.hasOpenPort() then return false

		title = $(".topic-new #topic_title").val()
		body = $(".topic-new #topic_body").val()
		#if not body then return $(".topic-new #topic_body").focus()
		if not title then return $(".topic-new #topic_title").focus()

		$(".topic-new .button-submit").addClass("loading")
		inner_path = "data/users/#{Users.my_address}/data.json"
		Page.cmd "fileGet", [inner_path], (data) =>
			data = JSON.parse(data)
			data.topics.push {
				"topic_id": data.next_topic_id,
				"title": title,
				"body": body,
				"added": Time.timestamp()
			}
			data.next_topic_id += 1
			Page.writePublish inner_path, Page.jsonEncode(data), (res) =>
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
					Page.cmd "wrapperNotification", ["error", "File write error: #{res}"]


	submitTopicVote: (e) =>
		if not Users.my_name # Not registered
			Page.cmd "wrapperNotification", ["info", "Please, request access before posting."]
			return false
		elem = $(e.currentTarget)
		elem.toggleClass("active").addClass("loading")
		inner_path = "data/users/#{Users.my_address}/data.json"
		Page.cmd "fileGet", [inner_path], (data) =>
			data = JSON.parse(data)
			data.topic_votes ?= {}
			topic_address = elem.parents(".topic").data("topic_address")
			if elem.hasClass("active")
				data.topic_votes[topic_address] = 1
			else
				delete data.topic_votes[topic_address]
			Page.writePublish inner_path, Page.jsonEncode(data), (res) =>
				elem.removeClass("loading")
				if res == true
					@log "File written"
				else
					elem.toggleClass("active") # Change back
					#Page.cmd "wrapperNotification", ["error", "File write error: #{res}"]
		
		return false
			

window.TopicList = new TopicList()