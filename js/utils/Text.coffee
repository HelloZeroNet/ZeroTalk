class Text
	toColor: (text) ->
		hash = 0
		for i in [0..text.length-1]
			hash = text.charCodeAt(i) + ((hash << 5) - hash)
		color = '#'
		return "hsl(" + (hash % 360) + ",30%,50%)";
		for i in [0..2]
			value = (hash >> (i * 8)) & 0xFF
			color += ('00' + value.toString(16)).substr(-2)
		return color


	toMarked: (text, options=null) ->
		text = marked(text, options)
		return @fixLinks text


	# Convert zeronet links to relaitve
	fixLinks: (text) ->
		return text.replace(/href="http:\/\/(127.0.0.1|localhost):43110/g, 'href="')


	toUrl: (text) =>
		return text.replace(/[^A-Za-z0-9]/g, "+").replace(/[+]+/g, "+").replace(/[+]+$/, "")


window.Text = new Text()