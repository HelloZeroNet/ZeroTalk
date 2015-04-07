class TopicList extends Class
	constructor: ->
		@thread_sorter = null
		@parent_topic_hash = undefined
		@topic_parent_hashes = {}


	actionList: (parent_topic_id, parent_topic_user_id) ->
		$(".topics-loading").cssLater("top", "0px", 200)
		#@loadTopics("noanim")

		# Topic group listing
		if parent_topic_id
			$(".topics-title").html("&nbsp;")
			@parent_topic_hash = "#{parent_topic_id}@#{parent_topic_user_id}"

			# Update visited info
			Page.local_storage["topic.#{parent_topic_id}_#{parent_topic_user_id}.visited"] = Time.timestamp()
			Page.cmd "wrapperSetLocalStorage", Page.local_storage
		else
			$(".topics-title").html("Newest topics")

		@loadTopics("noanim")

		# Show create new topic form
		$(".topic-new-link").on "click", =>
			$(".topic-new").fancySlideDown()
			$(".topic-new-link").slideUp()
			return false

		# Create new topic
		$(".topic-new .button-submit").on "click", =>
			@submitCreateTopic()
			return false


	dbloadTopics: (type="list", cb=false) ->
		@logStart "Load topics..."
		topic_group_action = {}
		topic_group_after = {}
		if @parent_topic_hash
			where = "WHERE parent_topic_hash = '#{@parent_topic_hash}' OR row_topic_hash = '#{@parent_topic_hash}'"
		else
			where = ""
		last_elem = $(".topics-list .topic.template")

		Page.cmd "dbQuery", ["
		 SELECT 
		  COUNT(comment_id) AS comments_num, MAX(comment.added) AS last_comment,
		  topic.*, 
		  topic_creator_user.user_name AS topic_creator_user_name, 
		  topic_creator_user.user_id AS topic_creator_user_id,
		  topic_creator_user.path AS topic_creator_file,
		  topic.topic_id || '@' || topic_creator_user.user_id AS row_topic_hash,
		  (SELECT COUNT(*) FROM topic_vote WHERE topic_vote.topic_hash = topic.topic_id || '@' || topic_creator_user.user_id)+1 AS votes
		 FROM topic 
		 LEFT JOIN json AS topic_creator_json ON (topic_creator_json.json_id = topic.json_id) 
		 LEFT JOIN user AS topic_creator_user ON (topic_creator_json.path = topic_creator_user.path)
		 LEFT JOIN comment ON (comment.topic_hash = row_topic_hash)
		 #{where}
		 GROUP BY topic.topic_id, topic.json_id 
		 ORDER BY CASE WHEN last_comment THEN last_comment ELSE topic.added END DESC"], (topics) =>
			for topic in topics
				# Save the latest action of topic group
				if topic.parent_topic_hash and not topic_group_action[topic.parent_topic_hash] 
					if topic.last_comment
						topic_group_action[topic.parent_topic_hash] = topic.last_comment
					else
						topic_group_action[topic.parent_topic_hash] = topic.added
					topic_group_after[topic.parent_topic_hash] = last_elem

				# Skip it if we not in the subcategory
				if topic.parent_topic_hash and @parent_topic_hash != topic.parent_topic_hash then continue 

				# Parent topic for group that we currently listing
				if @parent_topic_hash and topic.row_topic_hash == @parent_topic_hash
					topic_parent = topic
					continue # Dont display it

				if topic.type == "group" then topic.last_comment = topic_group_action[topic.row_topic_hash]

				topic_address = topic.row_topic_hash.replace("@","_")

				elem = $("#topic_"+topic_address)
				if elem.length == 0 # Create if not exits yet
					elem = $(".topics-list .topic.template").clone().removeClass("template").attr("id", "topic_"+topic_address)
					if type != "noanim" then elem.cssSlideDown()

				if topic.type == "group"
					if topic_group_after[topic.row_topic_hash] # Has after
						elem.insertBefore topic_group_after[topic.row_topic_hash].nextAll(":not(.topic-group):first") # Add before the next non-topic group
						# Sorting messed, dont insert next item after it: Do not update last elem
					else
						elem.insertAfter(last_elem)
						last_elem = elem
				else
					elem.insertAfter(last_elem)
					last_elem = elem
				
				
				@applyTopicData(elem, topic)

			Page.addInlineEditors()


			$("body").css({"overflow": "auto", "height": "auto"}) # Auto height body

			@logEnd "Load topics..."
			
			# Hide loading
			if parseInt($(".topics-loading").css("top")) > -30 # Loading visible, animate it
				$(".topics-loading").css("top", "-30px")
			else
				$(".topics-loading").remove()

			# Set sub-title listing title
			if @parent_topic_hash
				$(".topics-title").html("<span class='parent-link'><a href='?Main'>Main</a> &rsaquo;</span> #{topic_parent.title}")

			$(".topics").css("opacity", 1)

			if cb then cb()



	loadTopics: (type="list", cb=false) ->
		if Page.has_db then return @dbloadTopics(type, cb)

		@logStart "Load topics..."
		Page.cmd "fileQuery", ["data/users/*/data.json", "topics"], (topics) =>
			topics.sort (a, b) -> # Sort by date
				return a.added - b.added
			last_elem = null
			topic_parent = null

			for topic in topics
				topic_address = topic.topic_id + "_" + Users.to_id[topic.inner_path]
				topic_hash = topic_address.replace("_", "@")

				# Parent topic that we currently listing
				if topic_hash == @parent_topic_hash
					topic_parent = topic
				
				# Store topic parents
				if topic.parent_topic_hash
					@topic_parent_hashes[topic_hash] = topic.parent_topic_hash

				# Filter topics by parent
				if topic.parent_topic_hash != @parent_topic_hash then continue

				# Create or update html element
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

			# Set sub-title listing title
			if @parent_topic_hash
				$(".topics-title").html("<span class='parent-link'><a href='?Main'>Main</a> &rsaquo;</span> #{topic_parent.title}")

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
	loadTopicsStat: (type="list") =>
		@logStart "Load topics stats..."
		Page.cmd "fileQuery", ["data/users/*/data.json", ""], (users) =>
			$(".topics").css("opacity", 1)
			stats = {}
			comment_stats = {}
			my_topic_votes = {}
			my_comment_votes = {}
			# Analyze user data files
			for user in users
				user_id = Users.to_id[user.inner_path]
				for topic in user.topics
					topic_address = "#{topic.topic_id}_#{user_id}"
					if not stats[topic_address]?
						stats[topic_address] = {"comments": 0, "last": {"added": topic.added}, "votes": 1}
					if not stats[topic_address]["last"]
						stats[topic_address]["last"] = {"added": topic.added}

					if topic.parent_topic_hash # Group stat
						parent_topic_id = topic.parent_topic_hash.replace("@", "_")
						stats[parent_topic_id] ?= {"comments": 0, "last": {"added": topic.added}, "votes": 1}
						stats[parent_topic_id]["last"] ?= {"added": topic.added}
						stats[parent_topic_id]["group"] = true
						if topic.added > stats[parent_topic_id]["last"]["added"]
							stats[parent_topic_id]["last"]["added"] = topic.added

					# Set title of topic
					if type == "show" and topic_address.replace("_", "@") == TopicShow.topic.parent_topic_hash
						$(".topic-title").html("
							<span class='parent-link'><a href='?Main'>Main</a> &rsaquo;</span>
							<span class='parent-link'><a href='?Topics:#{topic.topic_id}@#{user_id}/#{Text.toUrl(topic.title)}'>#{topic.title}</a> &rsaquo;</span>
							#{TopicShow.topic.title}")

				# Topic votes
				for topic_address, vote of user["topic_votes"]
					topic_address = topic_address.replace("@", "_")
					stats[topic_address] ?= {"comments": 0, "last": null, "votes": 1}
					if vote == 1 then stats[topic_address]["votes"] += 1

				# Comment votes
				if type == "show"
					for comment_address, vote of user["comment_votes"]
						comment_address = comment_address.replace("@", "_")
						comment_stats[comment_address] ?= 1
						if vote == 1 then comment_stats[comment_address] += 1

				# My votes
				if user_id == Users.my_id
					if user["topic_votes"] then my_topic_votes = user["topic_votes"]
					if user["comment_votes"] then my_comment_votes = user["comment_votes"]

				# Get latest comment and count of topic
				for topic_hash, comments of user["comments"]
					topic_address = topic_hash.replace("@", "_")
					for comment in comments
						stats[topic_address] ?= {"comments": 0, "last": null, "votes": 1}
						last = stats[topic_address]["last"]
						stats[topic_address]["comments"] += 1
						if not last or comment["added"] > last["added"]
							comment["auth_address"] = user["inner_path"]
							stats[topic_address]["last"] = comment

						# Topic group stat
						parent_topic_address = @topic_parent_hashes[topic_hash]?.replace("@", "_")
						if parent_topic_address # Topic has parent
							stats[parent_topic_address] ?= {"comments": 0, "last": null, "votes": 1}
							last = stats[parent_topic_address]["last"]
							stats[parent_topic_address]["comments"] += 1
							if not last or comment["added"] > last["added"]
								comment["auth_address"] = user["inner_path"]
								stats[parent_topic_address]["last"] = $.extend({}, comment) # Copy the comment obj



			# Set html elements
			for topic_address, stat of stats
				elem = $("#topic_#{topic_address}")
				stat["last"] ?= {"added": 0} # Deleted topics
				# Comments
				if type != "show"
					if stat.group
						$(".comment-num", elem).text "last activity"
						$(".added", elem).text Time.since(stat["last"]["added"])
					else if stat.comments > 0
						$(".comment-num", elem).text "#{stat.comments} comment"
						$(".added", elem).text "last "+Time.since(stat["last"]["added"])
					else
						$(".comment-num", elem).text "0 comments"
						$(".added", elem).text Time.since(stat["last"]["added"])

				# Votes
				if my_topic_votes[topic_address.replace("_", "@")] # Voted on it
					$(".score-inactive .score-num", elem).text stat["votes"]-1
					$(".score-active .score-num", elem).text stat["votes"]
					$(".score", elem).addClass("active")
				else # Not voted on it
					$(".score-inactive .score-num", elem).text stat["votes"]
					$(".score-active .score-num", elem).text stat["votes"]+1
				$(".score", elem).off("click").on "click", @submitTopicVote


			# Sort topics
			if type != "show"
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

			# Set comment votes html
			if type == "show"
				for comment_address, votes of comment_stats
					elem =$("#comment_score_#{comment_address}")
					if my_comment_votes[comment_address.replace("_", "@")] # Voted onit
						$(".score-inactive .score-num", elem).text votes-1
						$(".score-active .score-num", elem).text votes
						elem.addClass("active")
					else # Not voted on it
						$(".score-inactive .score-num", elem).text votes
						$(".score-active .score-num", elem).text votes+1
			@logEnd "Load topics stats..."



	applyTopicData: (elem, topic, type="list") ->
		title_hash = Text.toUrl(topic.title)
		if topic.row_topic_hash # DB
			topic_address = topic.row_topic_hash
		else # Filequery
			user_id = Users.to_id[topic.inner_path]
			topic_address = topic.topic_id+"@"+user_id
		$(".title .title-link", elem).text(topic.title)
		$(".title .title-link, a.image, .comment-num", elem).attr("href", "?Topic:#{topic_address}/#{title_hash}")
		elem.data "topic_address", topic_address

		# Get links in body
		body = topic.body
		url_match = topic.body.match /http[s]{0,1}:\/\/[^"', $]+/
		if topic.type == "group" # Group type topic
			$(elem).addClass("topic-group")
			$(".image .icon", elem).removeClass("icon-topic-chat").addClass("icon-topic-group")
			$(".link", elem).css("display", "none")
			#$(".info", elem).css("display", "none")
			$(".title .title-link, a.image, .comment-num", elem).attr("href", "?Topics:#{topic_address}/#{title_hash}")
		else if url_match # Link type topic
			url = url_match[0]
			if type != "show" then body = body.replace /http[s]{0,1}:\/\/[^"' $]+$/g, "" # Remove links from end
			$(".image .icon", elem).removeClass("icon-topic-chat").addClass("icon-topic-link")
			$(".link", elem).css("display", "").attr "href", url.replace(/http:\/\/(127.0.0.1|localhost):43110/, "")
			$(".link .link-url", elem).text(url)
		else # Normal type topic
			$(".image .icon", elem).removeClass("icon-topic-link").addClass("icon-topic-chat")
			$(".link", elem).css("display", "none")

		if type == "show" # Markdon syntax at topic page
			$(".body", elem).html Text.toMarked(body, {"sanitize": true})
		else
			$(".body", elem).text body

		if Page.has_db # Apply db data
			# Last activity and comment num
			if type != "show"
				last_action = Math.max(topic.last_comment, topic.added)
				if topic.type == "group"
					$(".comment-num", elem).text "last activity"
					$(".added", elem).text Time.since(last_action)
				else if topic.comments_num > 0
					$(".comment-num", elem).text "#{topic.comments_num} comment"
					$(".added", elem).text "last "+Time.since(last_action)
				else
					$(".comment-num", elem).text "0 comments"
					$(".added", elem).text Time.since(last_action)
			# Creator address
			$(".user_name", elem).text(topic.topic_creator_user_name).attr("title", topic.topic_creator_file.replace("/data.json", ""))
			# Apply topic score
			if Users.my_topic_votes[topic_address] # Voted on topic
				$(".score-inactive .score-num", elem).text topic.votes-1
				$(".score-active .score-num", elem).text topic.votes
				$(".score", elem).addClass("active")
			else # Not voted on it
				$(".score-inactive .score-num", elem).text topic.votes
				$(".score-active .score-num", elem).text topic.votes+1
			$(".score", elem).off("click").on "click", @submitTopicVote
			# Visited
			visited = Page.local_storage["topic.#{topic_address.replace("@","_")}.visited"]
			if not visited
				elem.addClass("visit-none")
			else if visited < last_action
				elem.addClass("visit-newcomment")

		else # Apply filequery data
			user_name = Users.to_name[topic.inner_path]
			$(".user_name", elem).text(user_name).attr("title", topic.inner_path)
		
		if type == "show" then $(".added", elem).text Time.since(topic.added)


		# My topic
		if topic.inner_path == Users.my_address or topic.topic_creator_user_id == Users.my_id
			$(elem).attr("data-object", "Topic:#{topic_address}").attr("data-deletable", "yes")
			$(".title .title-link", elem).attr("data-editable", "title").data("content", topic.title)
			$(".body", elem).attr("data-editable", "body").data("content", topic.body)


	submitCreateTopic: ->
		# if not Page.hasOpenPort() then return false
		if not Users.my_name # Not registered
			Page.cmd "wrapperNotification", ["info", "Please, request access before posting."]
			return false

		title = $(".topic-new #topic_title").val()
		body = $(".topic-new #topic_body").val()
		#if not body then return $(".topic-new #topic_body").focus()
		if not title then return $(".topic-new #topic_title").focus()

		$(".topic-new .button-submit").addClass("loading")
		inner_path = "data/users/#{Users.my_address}/data.json"
		Page.cmd "fileGet", [inner_path], (data) =>
			data = JSON.parse(data)
			topic = {
				"topic_id": data.next_topic_id,
				"title": title,
				"body": body,
				"added": Time.timestamp()
			}
			if @parent_topic_hash then topic.parent_topic_hash = @parent_topic_hash
			data.topics.push topic
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