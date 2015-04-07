class TopicShow extends Class
	actionShow: (topic_id, topic_user_id) ->
		@topic_id = topic_id
		@topic_user_id = topic_user_id
		@topic = null

		@loadTopic()
		@loadComments("noanim")

		$(".comment-new .button-submit").on "click", =>
			@submitComment()
			return false


	queryTopic: (topic_id, topic_user_id) ->

		return "
		 SELECT 
		  topic.*, 
		  topic_creator_user.user_name AS topic_creator_user_name, 
		  topic_creator_user.user_id AS topic_creator_user_id,
		  topic_creator_user.path AS topic_creator_file,
		  topic.topic_id || '@' || topic_creator_user.user_id AS row_topic_hash,
		  (SELECT COUNT(*) FROM topic_vote WHERE topic_vote.topic_hash = topic.topic_id || '@' || topic_creator_user.user_id)+1 AS votes
		 FROM topic 
		  LEFT JOIN json AS topic_creator_json ON (topic_creator_json.json_id = topic.json_id) 
		  LEFT JOIN user AS topic_creator_user ON (topic_creator_json.path = topic_creator_user.path)
		 WHERE
		  topic.topic_id = #{topic_id} AND topic_creator_user_id = #{topic_user_id}
		 LIMIT 1"


	dbLoadTopic: (cb=false) ->
		@logStart "Loading topic..."

		$(".topic-full").attr("id", "topic_#{@topic_id}_#{@topic_user_id}")
		$(".topic-title").css("display", "none")

		Page.cmd "dbQuery", [@queryTopic(@topic_id, @topic_user_id)], (res) =>
			@topic = res[0]
			TopicList.applyTopicData($(".topic-full"), @topic, "show")

			# Topic has parent, update title breadcrumb
			if @topic.parent_topic_hash
				$(".topic-title").html("&nbsp;").css("display", "")
				[parent_topic_id, parent_topic_user_id] = @topic.parent_topic_hash.split("@")
				Page.cmd "dbQuery", [@queryTopic(parent_topic_id, parent_topic_user_id)], (parent_res) =>
					parent_topic = parent_res[0]
					$(".topic-title").html("
						<span class='parent-link'><a href='?Main'>Main</a> &rsaquo;</span>
						<span class='parent-link'><a href='?Topics:#{parent_topic.topic_id}@#{parent_topic.topic_creator_user_id}/#{Text.toUrl(parent_topic.title)}'>#{parent_topic.title}</a> &rsaquo;</span>
						#{@topic.title}")

			$(".topic-full").css("opacity", 1)
			$("body").addClass("page-topic")

			@logEnd "Loading topic..."

			if cb then cb()


	loadTopic: (cb=false)->
		if Page.has_db then return @dbLoadTopic(cb)
		@logStart "Loading topic..."
		topic_user_address = Users.to_address[@topic_user_id]
		$(".topic-full").attr("id", "topic_#{@topic_id}_#{@topic_user_id}")
		# Load topic data
		$(".topic-title").css("display", "none")
		Page.cmd "fileQuery", ["data/users/#{topic_user_address}/data.json", "topics.topic_id=#{@topic_id}"], (topic) =>
			topic = topic[0]
			@topic = topic
			topic["inner_path"] = topic_user_address # add user address
			TopicList.applyTopicData($(".topic-full"), topic, "show")
			$(".topic-full").css("opacity", 1)
			#$(".username-my").text(@user_name_db[user_address])
			$("body").addClass("page-topic")

			# Topic has parent, display parents
			if topic.parent_topic_hash
				$(".topic-title").html("&nbsp;").css("display", "")

			###
			if not topic.parent_topic_hash
				$(".topic-title").html("
					<span class='parent-link'><a href='?Main'>Main</a> &rsaquo;</span>
					#{topic.title}")
			###

			@logEnd "Loading topic..."

			TopicList.loadTopicsStat("show")
			if cb then cb()


	dbLoadComments: (type="show", cb=false) ->
		topic_address = @topic_id+"@"+@topic_user_id

		# Update visited info
		Page.local_storage["topic.#{@topic_id}_#{@topic_user_id}.visited"] = Time.timestamp()
		Page.cmd "wrapperSetLocalStorage", Page.local_storage
		
		@logStart "Loading comments..."

		# Load comments
		Page.cmd "dbQuery", ["
		 SELECT comment.*, user.user_name, user.user_id, json.path, 
		  (SELECT COUNT(*) FROM comment_vote WHERE comment_vote.comment_hash = comment.comment_id || '@' || user.user_id)+1 AS votes
		 FROM comment 
		  LEFT JOIN json USING (json_id)
		  LEFT JOIN user USING (path)
		 WHERE topic_hash = '#{@topic_id}@#{@topic_user_id}' 
		 ORDER BY added DESC"], (comments) =>
			@logEnd "Loading comments..."
			for comment in comments
				comment_address = "#{comment.comment_id}_#{comment.user_id}"
				elem = $("#comment_"+comment_address)
				if elem.length == 0 # Create if not exits
					elem = $(".comment.template").clone().removeClass("template").attr("id", "comment_"+comment_address).data("topic_address", topic_address)
					if type != "noanim"
						elem.cssSlideDown()
					$(".reply", elem).on "click", (e) => # Reply link
						return @buttonReply $(e.target).parents(".comment")
					$(".score", elem).attr("id", "comment_score_#{comment_address}").on "click", @submitCommentVote # Submit vote
				@applyCommentData(elem, comment)
				elem.appendTo(".comments")

			$("body").css({"overflow": "auto", "height": "auto"})

			Page.addInlineEditors()


			if cb then cb()



	loadComments: (type="show", cb=false) ->
		if Page.has_db then return @dbLoadComments(type, cb)
		@logStart "Loading comments..."
		topic_address = @topic_id+"@"+@topic_user_id

		# Update visited info
		Page.local_storage["topic.#{@topic_id}_#{@topic_user_id}.visited"] = Time.timestamp()
		Page.cmd "wrapperSetLocalStorage", Page.local_storage

		# Load comments
		Page.cmd "fileQuery", ["data/users/*/data.json", "comments.#{topic_address}"], (comments) =>
			comments.sort (a, b) -> # Sort by date desc
				return b.added - a.added

			for comment in comments
				user_id = Users.to_id[comment.inner_path]
				comment_address = "#{comment.comment_id}_#{user_id}"
				elem = $("#comment_"+comment_address)
				if elem.length == 0 # Create if not exits
					elem = $(".comment.template").clone().removeClass("template").attr("id", "comment_"+comment_address).data("topic_address", topic_address)
					if type != "noanim"
						elem.cssSlideDown()
					$(".reply", elem).on "click", (e) => # Reply link
						return @buttonReply $(e.target).parents(".comment")
					$(".score", elem).attr("id", "comment_score_#{comment_address}").on "click", @submitCommentVote # Submit vote
				@applyCommentData(elem, comment)
				elem.appendTo(".comments")

			$("body").css({"overflow": "auto", "height": "auto"})

			Page.addInlineEditors()
			@logEnd "Loading comments..."

			if cb then cb()


	# Update elem based on data of comment dict
	applyCommentData: (elem, comment) ->
		if comment.user_name # DB
			user_name = comment.user_name
			user_address = comment.path.replace("/data.json", "")
		else
			user_name = Users.to_name[comment.inner_path]
			user_address = comment.inner_path
		$(".body", elem).html Text.toMarked(comment.body, {"sanitize": true})
		$(".user_name", elem).text(user_name).css("color": Text.toColor(user_name)).attr("title", user_address)
		$(".added", elem).text(Time.since(comment.added)).attr("title", Time.date(comment.added, "long"))
		
		if Page.has_db # DB apply comment votes
			comment_id = elem.attr("id").replace("comment_", "")
			if Users.my_comment_votes[comment_id.replace("_", "@")] # Voted onit
				$(".score-inactive .score-num", elem).text comment.votes-1
				$(".score-active .score-num", elem).text comment.votes
				$(".score", elem).addClass("active")
			else # Not voted on it
				$(".score-inactive .score-num", elem).text comment.votes
				$(".score-active .score-num", elem).text comment.votes+1

		# My comment
		if user_address == Page.site_info.auth_address
			if comment.user_id # DB
				user_id = comment.user_id
			else:
				user_id = Users.to_id[comment.inner_path]
			comment_id = elem.attr("id").replace("comment_", "").replace(/_.*$/, "")
			topic_address = elem.data("topic_address")
			$(elem).attr("data-object", "Comment:#{comment_id}@#{topic_address}").attr("data-deletable", "yes")
			$(".body", elem).attr("data-editable", "body").data("content", comment.body)


	buttonReply: (elem) ->
		@log "Reply to", elem
		user_name = $(".user_name", elem).text()
		post_id = elem.attr("id")
		body_add = "> [#{user_name}](\##{post_id}): "
		body_add+= $(".body", elem).text().trim("\n").replace(/\n/g, "\n> ")
		body_add+= "\n\n"


		$(".comment-new #comment_body").val( $(".comment-new #comment_body").val()+body_add )

		$(".comment-new #comment_body").trigger("input").focus() # Autosize

		return false


	submitComment: ->
		# if not Page.hasOpenPort() then return false
		if not Users.my_name # Not registered
			Page.cmd "wrapperNotification", ["info", "Please, request access before posting."]
			return false

		body = $(".comment-new #comment_body").val()
		if not body then $(".comment-new #comment_body").focus()
		topic_address = @topic_id+"@"+@topic_user_id

		$(".comment-new .button-submit").addClass("loading")
		inner_path = "data/users/#{Page.site_info.auth_address}/data.json"
		Page.cmd "fileGet", [inner_path], (data) =>
			data = JSON.parse(data)
			data.comments[topic_address] ?= []
			data.comments[topic_address].push {
				"comment_id": data.next_message_id, 
				"body": body,
				"added": Time.timestamp()
			}
			data.next_message_id += 1
			Page.writePublish inner_path, Page.jsonEncode(data), (res) =>
				$(".comment-new .button-submit").removeClass("loading")
				if res == true
					@log "File written"
					@loadComments()
					$(".comment-new #comment_body").val("")



	submitCommentVote: (e) =>
		if not Users.my_name # Not registered
			Page.cmd "wrapperNotification", ["info", "Please, request access before voting."]
			return false
		
		elem = $(e.currentTarget)
		elem.toggleClass("active").addClass("loading")
		inner_path = "data/users/#{Users.my_address}/data.json"
		Page.cmd "fileGet", [inner_path], (data) =>
			data = JSON.parse(data)
			data.comment_votes ?= {}
			comment_address = elem.attr("id").match("_([0-9]+_[0-9]+)$")[1].replace("_", "@")
			if elem.hasClass("active")
				data.comment_votes[comment_address] = 1
			else
				delete data.comment_votes[comment_address]
			Page.writePublish inner_path, Page.jsonEncode(data), (res) =>
				elem.removeClass("loading")
				if res == true
					@log "File written"
				else
					elem.toggleClass("active") # Change back
					#Page.cmd "wrapperNotification", ["error", "File write error: #{res}"]
		
		return false

window.TopicShow = new TopicShow()
