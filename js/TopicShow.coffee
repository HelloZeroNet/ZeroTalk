class TopicShow extends Class
	actionShow: (topic_id, topic_user_id) ->
		@topic_id = topic_id
		@topic_user_id = topic_user_id

		@loadTopic()
		@loadComments("noanim")

		$(".comment-new .button-submit").on "click", =>
			if Page.user_name_db[Page.site_info.auth_address] # Check if user exits
				@buttonComment()
			else
				Page.cmd "wrapperNotification", ["info", "Please, request access before posting."]
			return false


	loadTopic: (cb=false)->
		topic_user_address = Page.user_address_db[@topic_user_id]
		# Load topic data
		Page.cmd "fileQuery", ["data/users/#{topic_user_address}/data.json", "topics.topic_id=#{@topic_id}"], (topic) =>
			topic = topic[0]
			topic["inner_path"] = topic_user_address # add user address
			TopicList.applyTopicData($(".topic-full"), topic, "full")
			$(".topic-full").css("opacity", 1)
			#$(".username-my").text(@user_name_db[user_address])
			$("body").addClass("page-topic")

			if cb then cb()


	loadComments: (type="normal", cb=false) ->
		topic_address = @topic_id+"@"+@topic_user_id

		# Update visited info
		Page.local_storage["topic.#{@topic_id}_#{@topic_user_id}.visited"] = Time.timestamp()
		Page.cmd "wrapperSetLocalStorage", Page.local_storage

		# Load comments
		Page.cmd "fileQuery", ["data/users/*/data.json", "comments.#{topic_address}"], (comments) =>
			comments.sort (a, b) -> # Sort by date desc
				return b.added - a.added

			for comment in comments
				user_id = Page.user_id_db[comment.inner_path]
				comment_address = "#{comment.comment_id}_#{user_id}"
				elem = $("#comment_"+comment_address)
				if elem.length == 0 # Create if not exits
					elem = $(".comment.template").clone().removeClass("template").attr("id", "comment_"+comment_address).data("topic_address", topic_address)
					if type != "noanim"
						elem.cssSlideDown()
					$(".added", elem).on "click", (e) => # Reply link
						return @buttonReply $(e.target).parents(".comment")
				@applyCommentData(elem, comment)
				elem.appendTo(".comments")

			$("body").css({"overflow": "auto", "height": "auto"})

			Page.addInlineEditors()

			if cb then cb()


	# Update elem based on data of comment dict
	applyCommentData: (elem, comment) ->
		username = Page.user_name_db[comment.inner_path]
		$(".body", elem).html Text.toMarked(comment.body, {"sanitize": true})
		$(".username", elem).text(username).css("color": Text.toColor(username))
		$(".added", elem).text(Time.since(comment.added))
		# elem.css("border-left", "2px solid #{@textToColor(username)}")


		# My comment
		if comment.inner_path == Page.site_info.auth_address
			user_id = Page.user_id_db[comment.inner_path]
			comment_id = elem.attr("id").replace("comment_", "").replace(/_.*$/, "")
			topic_address = elem.data("topic_address")
			$(elem).attr("data-object", "Comment:#{comment_id}@#{topic_address}").attr("data-deletable", "yes")
			$(".body", elem).attr("data-editable", "body").data("content", comment.body)


	buttonComment: ->
		if not Page.hasOpenPort() then return false

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


	buttonReply: (elem) ->
		@log "Reply to", elem
		username = $(".username", elem).text()
		post_id = elem.attr("id")
		body_add = "> [#{username}](\##{post_id}): "
		body_add+= $(".body", elem).text().trim("\n").replace(/\n/g, "\n> ")
		body_add+= "\n\n"


		$(".comment-new #comment_body").val( $(".comment-new #comment_body").val()+body_add )

		$(".comment-new #comment_body").trigger("input").focus() # Autosize

		return false


window.TopicShow = new TopicShow()
