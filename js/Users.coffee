class Users extends Class
	constructor: ->
		@to_id = {} # { "address": 1 }
		@to_address = {} # { 1: "address" }
		@to_name = {} # { "address": "user_name" }

		@my_address = null
		@my_id = null
		@my_name = null
		@my_max_size = null # Max total file size allowed to user


	# Load userdb
	loadDb: (cb = null) ->
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


	# Update user info
	updateMyInfo: ->
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
				$(".head-user .size").text("Used: #{(sum/1000).toFixed(1)}k / #{parseInt(@my_max_size/1000)}k")
				$(".head-user .size-used").width(parseFloat(sum/@my_max_size)*100)


		else # Not registered yet
			$(".head-user.visitor").css("display", "")
			$(".user_name-my").text("Visitor")


window.Users = new Users()