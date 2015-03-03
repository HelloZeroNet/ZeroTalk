limits = {}
window.LimitRate = (fn, interval) ->
	if not limits[fn]
		limits[fn] = setTimeout (->
			fn()
			delete limits[fn]
		), interval
