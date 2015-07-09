class User extends Class
	constructor: ->
		@my_topic_votes = {}
		@my_comment_votes = {}
		@rules = {}  # Last result for fileRules command
		
		@certselectButtons()


	updateMyInfo: (cb = null) ->
		@log "Updating user info...", @my_address
		@updateMyVotes(cb)


	# Load my votes
	updateMyVotes: (cb = null) ->
		query = """
			SELECT 'topic_vote' AS type, topic_uri AS uri FROM json LEFT JOIN topic_vote USING (json_id) WHERE directory = "#{Page.site_info.auth_address}" AND file_name = 'data.json'
			UNION
			SELECT 'comment_vote' AS type, comment_uri AS uri FROM json LEFT JOIN comment_vote USING (json_id) WHERE directory = "#{Page.site_info.auth_address}" AND file_name = 'data.json'
		"""
		Page.cmd "dbQuery", [query], (votes) =>
		  	for vote in votes
		  		if vote.type == "topic_vote"
		  			@my_topic_votes[vote.uri] = true
		  		else
		  			@my_comment_votes[vote.uri] = true
			if cb then cb()


	certselectButtons: ->
		$(".certselect").on "click", =>
			if Page.server_info.rev < 160
				Page.cmd "wrapperNotification", ["error", "Comments requires at least ZeroNet 0.3.0 Please upgade!"]
			else
				Page.cmd "certSelect", [["zeroid.bit"]]
			return false
			
			
	checkCert: (type) ->
		last_cert_user_id = $(".user_name-my").text()
		if $(".comment-new .user_name").text() != Page.site_info.cert_user_id or type == "updaterules" # User changed
			if Page.site_info.cert_user_id
				$(".comment-new").removeClass("comment-nocert")
				$(".user_name-my").text(Page.site_info.cert_user_id).css("color": Text.toColor(Page.site_info.cert_user_id))
			else
				$(".comment-new").addClass("comment-nocert")
				$(".user_name-my").text("Please sign in")
			
			# Update used/allowed space
			if Page.site_info.cert_user_id
				Page.cmd "fileRules", "data/users/#{Page.site_info.auth_address}/content.json", (rules) =>
					@rules = rules
					if rules.max_size
						@setCurrentSize(rules.current_size)
					else
						@setCurrentSize(0)
			else
				@setCurrentSize(0)


	setCurrentSize: (current_size) ->
		if current_size
			current_size_kb = current_size/1000
			$(".user-size").text("used: #{current_size_kb.toFixed(1)}k/#{Math.round(@rules.max_size/1000)}k").attr("title", 
				"Every new user has limited space to store comments, topics and votes.\n" +
				"This indicator shows your used/total allowed KBytes.\n"+
				"The site admin can increase it if you about to run out of it."
			)
			$(".user-size-used").css("width", Math.round(70*current_size/@rules.max_size))
		else
			$(".user-size").text("")
			
			
	getData: (cb) ->
		inner_path = "data/users/#{Page.site_info.auth_address}/data.json"
		Page.cmd "fileGet", {"inner_path": inner_path, "required": false}, (data) =>
			if data
				data = JSON.parse(data)
			else # Default data
				data = {"next_topic_id": 1, "topic": [], "topic_vote": {}, "next_comment_id": 1, "comment": {}, "comment_vote": {}}
			cb(data)
			
			
	publishData: (data, cb) ->
		inner_path = "data/users/#{Page.site_info.auth_address}/data.json"
		Page.writePublish inner_path, Text.jsonEncode(data), (res) =>
			@checkCert("updaterules") # Update used space
			if cb then cb(res)

window.User = new User()