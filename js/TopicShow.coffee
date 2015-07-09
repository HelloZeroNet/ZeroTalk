class TopicShow extends Class
	actionShow: (topic_id, topic_user_address) ->
		@topic_id = topic_id
		@topic_user_address = topic_user_address
		@topic_uri = @topic_id+"_"+@topic_user_address
		@topic = null

		@loadTopic()
		@loadComments("noanim")

		$(".comment-new .button-submit-form").on "click", =>
			@submitComment()
			return false
			
		textarea = $(".comment-new #comment_body")
		$(".comment-new #comment_body").on "input", =>
			# Update used space
			if User.rules.max_size
				if textarea.val().length > 0
					current_size = User.rules.current_size + textarea.val().length + 90
				else
					current_size = User.rules.current_size
				User.setCurrentSize(current_size)


	queryTopic: (topic_id, topic_user_address) ->
		return "
		 SELECT
		  topic.*,
		  topic_creator_user.value AS topic_creator_user_name,
		  topic_creator_content.directory AS topic_creator_address,
		  topic.topic_id || '_' || topic_creator_content.directory AS row_topic_uri,
		  (SELECT COUNT(*) FROM topic_vote WHERE topic_vote.topic_uri = topic.topic_id || '_' || topic_creator_content.directory)+1 AS votes
		 FROM topic
		  LEFT JOIN json AS topic_creator_json ON (topic_creator_json.json_id = topic.json_id)
		  LEFT JOIN json AS topic_creator_content ON (topic_creator_content.directory = topic_creator_json.directory AND topic_creator_content.file_name = 'content.json')
		  LEFT JOIN keyvalue AS topic_creator_user ON (topic_creator_user.json_id = topic_creator_content.json_id AND topic_creator_user.key = 'cert_user_id')
		 WHERE
		  topic.topic_id = #{topic_id} AND topic_creator_address = '#{topic_user_address}'
		 LIMIT 1"


	loadTopic: (cb=false) ->
		@logStart "Loading topic..."

		$(".topic-full").attr("id", "topic_#{@topic_uri}")
		$(".topic-title").css("display", "none")

		Page.cmd "dbQuery", [@queryTopic(@topic_id, @topic_user_address)], (res) =>
			@topic = res[0]
			TopicList.applyTopicData($(".topic-full"), @topic, "show")

			# Topic has parent, update title breadcrumb
			if @topic.parent_topic_hash
				$(".topic-title").html("&nbsp;").css("display", "")
				[parent_topic_id, parent_topic_user_address] = @topic.parent_topic_hash.split("@")
				Page.cmd "dbQuery", [@queryTopic(parent_topic_id, parent_topic_user_address)], (parent_res) =>
					parent_topic = parent_res[0]
					$(".topic-title").html("
						<span class='parent-link'><a href='?Main'>Main</a> &rsaquo;</span>
						<span class='parent-link'><a href='?Topics:#{parent_topic.topic_id}_#{parent_topic.topic_creator_user_id}/#{Text.toUrl(parent_topic.title)}'>#{parent_topic.title}</a> &rsaquo;</span>
						#{@topic.title}")

			$(".topic-full").css("opacity", 1)
			$("body").addClass("page-topic")

			@logEnd "Loading topic..."

			if cb then cb()


	loadComments: (type="show", cb=false) ->
		# Update visited info
		Page.local_storage["topic.#{@topic_id}_#{@topic_user_address}.visited"] = Time.timestamp()
		Page.cmd "wrapperSetLocalStorage", Page.local_storage
		
		@logStart "Loading comments..."

		# Load comments
		query = "
			SELECT 
			 comment.*,
			 user.value AS user_name,
			 user_json_content.directory AS user_address,
			 (SELECT COUNT(*) FROM comment_vote WHERE comment_vote.comment_uri = comment.comment_id || '_' || user_json_content.directory)+1 AS votes
			FROM comment
			 LEFT JOIN json AS user_json_data ON (user_json_data.json_id = comment.json_id)
			 LEFT JOIN json AS user_json_content ON (user_json_content.directory = user_json_data.directory AND user_json_content.file_name = 'content.json')
			 LEFT JOIN keyvalue AS user ON (user.json_id = user_json_content.json_id AND user.key = 'cert_user_id')
			WHERE comment.topic_uri = '#{@topic_id}_#{@topic_user_address}'
			ORDER BY added DESC
			"
		Page.cmd "dbQuery", [query], (comments) =>
			@logEnd "Loading comments..."
			for comment in comments
				comment_uri = "#{comment.comment_id}_#{comment.user_address}"
				elem = $("#comment_"+comment_uri)
				if elem.length == 0 # Create if not exits
					elem = $(".comment.template").clone().removeClass("template").attr("id", "comment_"+comment_uri).data("topic_uri", @topic_uri)
					if type != "noanim"
						elem.cssSlideDown()
					$(".reply", elem).on "click", (e) => # Reply link
						return @buttonReply $(e.target).parents(".comment")
					$(".score", elem).attr("id", "comment_score_#{comment_uri}").on "click", @submitCommentVote # Submit vote
				@applyCommentData(elem, comment)
				elem.appendTo(".comments")

			$("body").css({"overflow": "auto", "height": "auto"})

			Page.addInlineEditors()

			if cb then cb()


	# Update elem based on data of comment dict
	applyCommentData: (elem, comment) ->
		user_name = comment.user_name
		$(".body", elem).html Text.toMarked(comment.body, {"sanitize": true})
		$(".user_name", elem).text(user_name.replace(/@.*/, "")).css("color": Text.toColor(user_name)).attr("title", user_name+": "+comment.user_address)
		$(".added", elem).text(Time.since(comment.added)).attr("title", Time.date(comment.added, "long"))
		
		comment_uri = elem.attr("id").replace("comment_", "")
		if User.my_comment_votes[comment_uri] # Voted on it
			$(".score-inactive .score-num", elem).text comment.votes-1
			$(".score-active .score-num", elem).text comment.votes
			$(".score", elem).addClass("active")
		else # Not voted on it
			$(".score-inactive .score-num", elem).text comment.votes
			$(".score-active .score-num", elem).text comment.votes+1

		# My comment
		if comment.user_address == Page.site_info.auth_address
			$(elem).attr("data-object", "Comment:#{comment_uri}@#{@topic_uri}").attr("data-deletable", "yes")
			$(".body", elem).attr("data-editable", "body").data("content", comment.body)


	buttonReply: (elem) ->
		@log "Reply to", elem
		user_name = $(".user_name", elem).text()
		post_id = elem.attr("id")
		body_add = "> [#{user_name}](\##{post_id}): "
		elem_quote = $(".body", elem).clone()
		$("blockquote", elem_quote).remove() # Remove other people's quotes
		body_add+= elem_quote.text().trim("\n").replace(/\n/g, "\n> ")
		body_add+= "\n\n"


		$(".comment-new #comment_body").val( $(".comment-new #comment_body").val()+body_add )

		$(".comment-new #comment_body").trigger("input").focus() # Autosize

		return false


	submitComment: ->
		body = $(".comment-new #comment_body").val()
		if not body
			$(".comment-new #comment_body").focus()
			return

		$(".comment-new .button-submit").addClass("loading")
		
		User.getData (data) =>
			data.comment[@topic_uri] ?= []
			data.comment[@topic_uri].push {
				"comment_id": data.next_comment_id, 
				"body": body,
				"added": Time.timestamp()
			}
			data.next_comment_id += 1
			User.publishData data, (res) =>
				$(".comment-new .button-submit").removeClass("loading")
				if res == true
					@log "File written"
					@loadComments()
					$(".comment-new #comment_body").val("").delay(600).animate({"height": 72}, {"duration": 1000, "easing": "easeInOutCubic"})



	submitCommentVote: (e) =>
		if not Page.site_info.cert_user_id # No selected cert
			Page.cmd "wrapperNotification", ["info", "Please, your choose account before upvoting."]
			return false
		
		elem = $(e.currentTarget)
		elem.toggleClass("active").addClass("loading")
		User.getData (data) =>
			data.comment_vote ?= {}
			comment_uri = elem.attr("id").match("_([0-9]+_[A-Za-z0-9]+)$")[1]
			
			if elem.hasClass("active")
				data.comment_vote[comment_uri] = 1
			else
				delete data.comment_vote[comment_uri]
			
			User.publishData data, (res) =>
				elem.removeClass("loading")
		return false


window.TopicShow = new TopicShow()
