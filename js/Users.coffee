class Users extends Class
	constructor: ->
		@to_id = {} # { "address": 1 }
		@to_address = {} # { 1: "address" }
		@to_name = {} # { "address": "user_name" }

		@my_address = null
		@my_id = null
		@my_name = null
		@my_max_size = null # Max total file size allowed to user
		@my_topic_votes = {}
		@my_comment_votes = {}


	# Load userdb
	loadDb: (cb = null) ->
		if Page.has_db then return # No need if we has db support

		@logStart "Loading userDB"
		Page.cmd "fileGet", ["data/users/content.json"], (data) =>
			data = JSON.parse(data)
			for path, user of data["includes"]
				address = user.signers[0]
				@to_id[address] = user.user_id
				@to_address[user.user_id] = address
				@to_name[address] = user.user_name
				if address == @my_address # Current user
					@my_max_size = user.max_size
			@logEnd "Loading userDB"
			if cb then cb()


	dbUpdateMyInfo: (cb = null) ->
		@log "Updating user info...", @my_address
		Page.cmd "dbQuery", ["SELECT user.*, json.json_id AS data_json_id FROM user LEFT JOIN json USING(path) WHERE path='#{@my_address}/data.json'"], (res) =>
			if res.error or res.length == 0 # Db not ready yet or No user found
				$(".head-user.visitor").css("display", "")
				$(".user_name-my").text("Visitor")
				if cb then cb()
				return 
			
			@my_row = res[0]
			@my_id = @my_row["user_id"]
			@my_name = @my_row["user_name"]
			@my_max_size = @my_row["max_size"]
			# Update current user data
			if $(".head-user.visitor").css("display") != "none" # Just registered successfuly
				$(".head-user.visitor").css("display", "none")
				Page.cmd "wrapperNotification", ["done", "Hello <b>#{@my_name}</b>!<br>Congratulations, your registration is done!", 10000]
				$(".button.signup").removeClass("loading") 
			$(".head-user.registered").css("display", "")
			$(".user_name-my").text(@my_name).css("color", Text.toColor(@my_name)).attr("title", @my_address)

			@dbUpdateMyVotes(cb)

			# Update used space
			Page.cmd "fileGet", ["data/users/#{@my_address}/content.json"], (content) =>
				content = JSON.parse(content)
				sum = 0
				for relative_path, details of content.files
					sum += details.size
				used = (sum/1000).toFixed(1)
				$(".head-user .size").text("Used: #{used}k / #{parseInt(@my_max_size/1000)}k")
				$(".head-user .size-used").width(parseFloat(sum/@my_max_size)*100)

	# Load my votes
	dbUpdateMyVotes: (cb = null) ->
		Page.cmd "dbQuery", ["
		  SELECT 'topic_vote' AS type, topic_hash AS hash FROM topic_vote WHERE json_id = #{@my_row.data_json_id}
		  UNION
		  SELECT 'comment_vote' AS type, comment_hash AS hash FROM comment_vote WHERE json_id = #{@my_row.data_json_id}"], (votes) =>
		  	for vote in votes
		  		if vote.type == "topic_vote"
		  			@my_topic_votes[vote.hash] = true
		  		else
		  			@my_comment_votes[vote.hash] = true
			if cb then cb()


	# Update user info
	updateMyInfo: ->
		if Page.has_db then return @dbUpdateMyInfo()
		@log "Updating user info...", @my_address
		address = @my_address
		user_name = @to_name[address] # Set my info
		if user_name # Registered user
			@my_name = user_name
			@my_id = @to_id[address]
			if $(".head-user.visitor").css("display") != "none" # Just registered successfuly
				$(".head-user.visitor").css("display", "none")
				Page.cmd "wrapperNotification", ["done", "Hello <b>#{user_name}</b>!<br>Congratulations, your registration is done!", 10000]
				$(".button.signup").removeClass("loading") 

			$(".head-user.registered").css("display", "")
			$(".user_name-my").text(user_name).css("color", Text.toColor(user_name)).attr("title", address)
			Page.cmd "fileGet", ["data/users/#{address}/content.json"], (content) =>
				content = JSON.parse(content)
				sum = 0
				for relative_path, details of content.files
					sum += details.size	
				used = (sum/1000).toFixed(1)
				$(".head-user .size").text("Used: #{used}k / #{parseInt(@my_max_size/1000)}k")
				$(".head-user .size-used").width(parseFloat(sum/@my_max_size)*100)


		else # Not registered yet
			$(".head-user.visitor").css("display", "")
			$(".user_name-my").text("Visitor")


window.Users = new Users()