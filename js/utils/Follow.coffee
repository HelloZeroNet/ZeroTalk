class Follow extends Class
	constructor: (@elem) ->
		@menu = new Menu(@elem)
		@feeds = {}
		@follows = {}
		@elem.off "click"
		@elem.on "click", =>
			if Page.server_info.rev > 850
				if @elem.hasClass "following"
					@showFeeds()
				else
					@followDefaultFeeds()
			else
				Page.cmd "wrapperNotification", ["info", "Please update your ZeroNet client to use this feature"]
			return false
		@elem.css "display", "inline-block"
		@width_following = @elem.find(".text-following").width()
		@width_follow = @elem.find(".text-follow").width()
		@elem.css "display", "none"

	init: =>
		if not @feeds
			return

		Page.cmd "feedListFollow", [], (@follows) =>
			# Recover renamed queries (eg language change)
			queries = {}
			for title, [query, menu_item, is_default_feed, param] of @feeds
				queries[query] = title
			for title, [query, param] of @follows
				@log title, "->", queries[query]
				if queries[query] and title != queries[query]
					@log "Renamed query", title, "->", queries[query]
					@follows[queries[query]] = @follows[title]
					delete @follows[title]

			# Check selected queries
			for title, [query, menu_item, is_default_feed, param] of @feeds
				if @follows[title] and param in @follows[title][1]
					menu_item.addClass("selected")
				else
					menu_item.removeClass("selected")
			@updateListitems()
			@elem.css "display", "inline-block"

		setTimeout ( =>
			if typeof(Page.site_info.feed_follow_num) != "undefined" and Page.site_info.feed_follow_num == null  # Has not manipulated followings yet
				@log "Following default feeds"
				@followDefaultFeeds()
		), 100


	addFeed: (title, query, is_default_feed=false, param="") ->
		menu_item = @menu.addItem title, @handleMenuClick
		@feeds[title] = [query, menu_item, is_default_feed, param]


	handleMenuClick: (item) =>
		item.toggleClass("selected")
		@updateListitems()
		@saveFeeds()
		return true


	showFeeds: ->
		@menu.show()


	followDefaultFeeds: ->
		for title, [query, menu_item, is_default_feed, param] of @feeds
			if is_default_feed
				menu_item.addClass "selected"
				@log "Following", title
		@updateListitems()
		@saveFeeds()


	updateListitems: ->
		if @menu.elem.find(".selected").length > 0
			@elem.addClass "following"
			@elem.find(".text-follow").width(0)
			@elem.find(".text-following").width(@width_following+5)
		else
			@elem.removeClass "following"
			@elem.find(".text-following").width(0)
			@elem.find(".text-follow").width(@width_follow+5)


	saveFeeds: ->
		for title, [query, menu_item, is_default_feed, param] of @feeds
			if @follows[title]
				params = (item for item in @follows[title][1] when item != param)  # Remove current param from follow list
			else
				params = []

			if menu_item.hasClass "selected"  # Add if selected
				params.push(param)

			if params.length == 0   # Empty params
				delete @follows[title]
			else
				@follows[title] = [query, params]

		Page.cmd "feedFollow", [@follows]


window.Follow = Follow