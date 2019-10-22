import json, random, string, os

topic_uris = []
comment_uris = []

for user_id in range(500):
	# Add user to fake content.json
	user_dir = ''.join(random.choice(string.ascii_uppercase + string.ascii_lowercase + string.digits) for _ in range(34))
	os.mkdir("users/%s" % user_dir)
	# Fake data.json
	data_json = {
		"next_topic_id": random.randint(0,1000),
		"topic": [],
		"topic_vote": {},
		"next_comment_id": random.randint(0,1000),
		"comment": {},
		"comment_vote": {}
	}

	# Fake topics: 0-10pcs
	for i in range(random.randint(0,10)):
		topic_uri = "%s_%s" % (i, user_dir)
		topic_uris.append(topic_uri)
		data_json["topic"].append({
			"topic_id": i,
			"title": "Test topic %s" % topic_uri,
			"body": "Test message! "*random.randint(0,100),
			"added": random.randint(0, 1423439701)
		})	

	# Fake topic upvotes
	for i in range(random.randint(0,100)):
		data_json["topic_vote"][random.choice(topic_uris)] = int(time.time())

	# Fake comments: 0-100pcs
	for i in range(random.randint(0,100)):
		comment_uri = "%s_%s" % (i, user_dir)
		comment_uris.append(comment_uri)
		topic_uri = random.choice(topic_uris)
		if topic_uri not in data_json["comment"]:
			data_json["comment"][topic_uri] = []
		data_json["comment"][topic_uri].append({
			"comment_id": i,
			"body": "Test message! "*random.randint(0,100),
			"added": random.randint(0, 1423439701)
		})	

	# Fake comment upvotes
	for i in range(random.randint(0,100)):
		data_json["comment_vote"][random.choice(comment_uris)] = int(time.time())
	
	# Save data.json
	json.dump(data_json, open("users/%s/data.json" % user_dir, "wb"), indent=4)

	# Save content.json
	content_json = {
		"cert_auth_type": "web",
		"cert_user_id": "fakeuser%s@zeroid.bit" % user_id,
		"cert_sign": "GxFy7o9PLalScvP3S7OaWzRFUYYaR3hx8KXUXDpHP1usZSwqd0qQ7D5BT5QOxOMeqnjzEuX9r/eHO4OcL3BSmz8=",
		  "files": {
		    "data.json": {
		      "sha512": "7be9e5e83ae36885ea036e47c1d7c81e950bd841e402a6367f4c154308b31b68", 
		      "size": 169
		    }
		  }, 
  		"modified": 1429329453.758, 
  		"signs": {
    	 "13mF85kC4dWcsiUZYqq77E5fnQizLdNJHE": "GxFy7o9PLalScvP3S7OaWzRFUYYaR3hx8KXUXDpHP1usZSwqd0qQ7D5BT5QOxOMeqnjzEuX9r/eHO4OcL3BSmz8="
  		}
  	}
	json.dump(content_json, open("users/%s/content.json" % user_dir, "wb"), indent=4)	
	print ".",

