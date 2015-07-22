class TopicList extends Class
	constructor: ->
		@thread_sorter = null
		@parent_topic_uri = undefined
		@topic_parent_uris = {}
		@topic_sticky_uris = { "2_1J3rJ8ecnwH2EPYa6MrgZttBNc61ACFiCj": 1, "1_1J3rJ8ecnwH2EPYa6MrgZttBNc61ACFiCj": 1 }


	actionList: (parent_topic_id, parent_topic_user_address) ->
		$(".topics-loading").cssLater("top", "0px", 200)

		# Topic group listing
		if parent_topic_id
			$(".topics-title").html("&nbsp;")
			@parent_topic_uri = "#{parent_topic_id}_#{parent_topic_user_address}"

			# Update visited info
			Page.local_storage["topic.#{parent_topic_id}_#{parent_topic_user_address}.visited"] = Time.timestamp()
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


	loadTopics: (type="list", cb=false) ->
		@logStart "Load topics..."
		if @parent_topic_uri # Topic group listing
			where = "WHERE parent_topic_uri = '#{@parent_topic_uri}' OR row_topic_uri = '#{@parent_topic_uri}'"
		else # Main listing
			where = "WHERE topic.type IS NULL AND topic.parent_topic_uri IS NULL "
		last_elem = $(".topics-list .topic.template")

		query = """
			SELECT
			 COUNT(comment_id) AS comments_num, MAX(comment.added) AS last_comment, topic.added as last_added,
			 topic.*,
			 topic_creator_user.value AS topic_creator_user_name,
			 topic_creator_content.directory AS topic_creator_address,
			 topic.topic_id || '_' || topic_creator_content.directory AS row_topic_uri,
			 NULL AS row_topic_sub_uri,
			 (SELECT COUNT(*) FROM topic_vote WHERE topic_vote.topic_uri = topic.topic_id || '_' || topic_creator_content.directory)+1 AS votes
			FROM topic
			LEFT JOIN json AS topic_creator_json ON (topic_creator_json.json_id = topic.json_id)
			LEFT JOIN json AS topic_creator_content ON (topic_creator_content.directory = topic_creator_json.directory AND topic_creator_content.file_name = 'content.json')
			LEFT JOIN keyvalue AS topic_creator_user ON (topic_creator_user.json_id = topic_creator_content.json_id AND topic_creator_user.key = 'cert_user_id')
			LEFT JOIN comment ON (comment.topic_uri = row_topic_uri)
			#{where}
			GROUP BY topic.topic_id, topic.json_id
		"""

		if not @parent_topic_uri # Union topic groups
			query += """

				UNION ALL

				SELECT
				 COUNT(comment_id) AS comments_num, MAX(comment.added) AS last_comment, MAX(topic_sub.added) AS last_added,
				 topic.*,
				 topic_creator_user.value AS topic_creator_user_name,
				 topic_creator_content.directory AS topic_creator_address,
				 topic.topic_id || '_' || topic_creator_content.directory AS row_topic_uri,
				 topic_sub.topic_id || '_' || topic_sub_creator_content.directory AS row_topic_sub_uri,
				 (SELECT COUNT(*) FROM topic_vote WHERE topic_vote.topic_uri = topic.topic_id || '_' || topic_creator_content.directory)+1 AS votes
				FROM topic
				LEFT JOIN json AS topic_creator_json ON (topic_creator_json.json_id = topic.json_id)
				LEFT JOIN json AS topic_creator_content ON (topic_creator_content.directory = topic_creator_json.directory AND topic_creator_content.file_name = 'content.json')
				LEFT JOIN keyvalue AS topic_creator_user ON (topic_creator_user.json_id = topic_creator_content.json_id AND topic_creator_user.key = 'cert_user_id')
				LEFT JOIN topic AS topic_sub ON (topic_sub.parent_topic_uri = topic.topic_id || '_' || topic_creator_content.directory)
				LEFT JOIN json AS topic_sub_creator_json ON (topic_sub_creator_json.json_id = topic_sub.json_id)
				LEFT JOIN json AS topic_sub_creator_content ON (topic_sub_creator_content.directory = topic_sub_creator_json.directory AND topic_sub_creator_content.file_name = 'content.json')
				LEFT JOIN comment ON (comment.topic_uri = row_topic_sub_uri)
				WHERE topic.type = "group"
				GROUP BY topic.topic_id
			"""

		Page.cmd "dbQuery", [query], (topics) =>
			topics.sort (a,b) ->
				booster_a = booster_b = 0
				# Boost position to top for sticky topics
				if window.TopicList.topic_sticky_uris[a.row_topic_uri]
					booster_a = window.TopicList.topic_sticky_uris[a.row_topic_uri]*10000000
				if window.TopicList.topic_sticky_uris[b.row_topic_uri]
					booster_b = window.TopicList.topic_sticky_uris[b.row_topic_uri]*10000000
				return Math.max(b.last_comment+booster_b, b.last_added+booster_b)-Math.max(a.last_comment+booster_a, a.last_added+booster_a)

			for topic in topics
				topic_uri = topic.row_topic_uri
				if topic.last_added
					topic.added = topic.last_added

				# Parent topic for group that we currently listing
				if @parent_topic_uri and topic_uri == @parent_topic_uri
					topic_parent = topic
					continue # Dont display it

				elem = $("#topic_"+topic_uri)
				if elem.length == 0 # Create if not exits yet
					elem = $(".topics-list .topic.template").clone().removeClass("template").attr("id", "topic_"+topic_uri)
					if type != "noanim" then elem.cssSlideDown()

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
			if @parent_topic_uri
				$(".topics-title").html("<span class='parent-link'><a href='?Main'>Main</a> &rsaquo;</span> #{topic_parent.title}")

			$(".topics").css("opacity", 1)

			if cb then cb()


	applyTopicData: (elem, topic, type="list") ->
		title_hash = Text.toUrl(topic.title)
		topic_uri = topic.row_topic_uri
		$(".title .title-link", elem).text(topic.title)
		$(".title .title-link, a.image, .comment-num", elem).attr("href", "?Topic:#{topic_uri}/#{title_hash}")
		elem.data "topic_uri", topic_uri

		# Get links in body
		body = topic.body
		url_match = body.match /http[s]{0,1}:\/\/[^"', \r\n)$]+/
		if topic.type == "group" # Group type topic
			$(elem).addClass("topic-group")
			$(".image .icon", elem).removeClass("icon-topic-chat").addClass("icon-topic-group")
			$(".link", elem).css("display", "none")
			#$(".info", elem).css("display", "none")
			$(".title .title-link, a.image, .comment-num", elem).attr("href", "?Topics:#{topic_uri}/#{title_hash}")
		else if url_match # Link type topic
			url = url_match[0]
			if type != "show" then body = body.replace /http[s]{0,1}:\/\/[^"' \r\n)$]+$/g, "" # Remove links from end
			$(".image .icon", elem).removeClass("icon-topic-chat").addClass("icon-topic-link")
			$(".link", elem).css("display", "").attr "href", Text.fixLink(url)
			$(".link .link-url", elem).text(url)
		else # Normal type topic
			$(".image .icon", elem).removeClass("icon-topic-link").addClass("icon-topic-chat")
			$(".link", elem).css("display", "none")

		if type == "show" # Markdon syntax at topic show
			$(".body", elem).html Text.toMarked(body, {"sanitize": true})
		else # No format on listing
			$(".body", elem).text body

		if window.TopicList.topic_sticky_uris[topic_uri]
			elem.addClass("topic-sticky")

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

		# Creator address and user name
		$(".user_name", elem)
			.text(topic.topic_creator_user_name.replace(/@.*/, ""))
			.attr("title", topic.topic_creator_user_name+": "+topic.topic_creator_address)

		# Apply topic score
		if User.my_topic_votes[topic_uri] # Voted on topic
			$(".score-inactive .score-num", elem).text topic.votes-1
			$(".score-active .score-num", elem).text topic.votes
			$(".score", elem).addClass("active")
		else # Not voted on it
			$(".score-inactive .score-num", elem).text topic.votes
			$(".score-active .score-num", elem).text topic.votes+1
		$(".score", elem).off("click").on "click", @submitTopicVote
		# Visited
		visited = Page.local_storage["topic.#{topic_uri}.visited"]
		if not visited
			elem.addClass("visit-none")
		else if visited < last_action
			elem.addClass("visit-newcomment")

		if type == "show" then $(".added", elem).text Time.since(topic.added)


		# My topic
		if topic.topic_creator_address == Page.site_info.auth_address
			$(elem).attr("data-object", "Topic:#{topic_uri}").attr("data-deletable", "yes")
			$(".title .title-link", elem).attr("data-editable", "title").data("content", topic.title)
			$(".body", elem).attr("data-editable", "body").data("content", topic.body)


	submitCreateTopic: ->
		# if not Page.hasOpenPort() then return false
		if not Page.site_info.cert_user_id # No selected cert
			Page.cmd "wrapperNotification", ["info", "Please, your choose account before creating a topic."]
			return false

		title = $(".topic-new #topic_title").val()
		body = $(".topic-new #topic_body").val()
		#if not body then return $(".topic-new #topic_body").focus()
		if not title then return $(".topic-new #topic_title").focus()

		$(".topic-new .button-submit").addClass("loading")
		User.getData (data) =>
			topic = {
				"topic_id": data.next_topic_id,
				"title": title,
				"body": body,
				"added": Time.timestamp()
			}
			if @parent_topic_uri then topic.parent_topic_uri = @parent_topic_uri
			data.topic.push topic
			data.next_topic_id += 1
			User.publishData data, (res) =>
				$(".topic-new .button-submit").removeClass("loading")
				$(".topic-new").slideUp()
				$(".topic-new-link").slideDown()
				setTimeout (=>
					@loadTopics()
				), 600
				$(".topic-new #topic_body").val("")
				$(".topic-new #topic_title").val("")


	submitTopicVote: (e) =>
		if not Page.site_info.cert_user_id # No selected cert
			Page.cmd "wrapperNotification", ["info", "Please, your choose account before upvoting."]
			return false

		elem = $(e.currentTarget)
		elem.toggleClass("active").addClass("loading")
		inner_path = "data/users/#{User.my_address}/data.json"
		User.getData (data) =>
			data.topic_vote ?= {}
			topic_uri = elem.parents(".topic").data("topic_uri")

			if elem.hasClass("active")
				data.topic_vote[topic_uri] = 1
			else
				delete data.topic_vote[topic_uri]
			User.publishData data, (res) =>
				elem.removeClass("loading")
		return false


window.TopicList = new TopicList()