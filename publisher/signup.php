<?

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST');
header('Access-Control-Allow-Headers: *');


$site = "address";
$private_key = "privatekey";

$zeronet_dir = "/home/zeronet/p-private/dev1/bin-zeronet";
$users_json = "$zeronet_dir/data/$site/data/users/content.json";

if (isset($_SERVER['HTTP_REFERER']) and strpos($_SERVER['HTTP_REFERER'], $site) === false) {
	header('HTTP/1.0 403 Forbidden');
	die("Referer error.");
}


// Parsing parameters...

$auth_address = $_POST["auth_address"];
$user_name = trim($_POST["user_name"], " ");

if (!preg_match("#^[A-Za-z0-9_ ]+$#", $user_name)) {
	header("HTTP/1.0 400 Bad Request");
	die("Only english letters and numbers allowed in username.");
}

if (!preg_match("#^[A-Za-z0-9]+$#", $auth_address)) {
	header("HTTP/1.0 400 Bad Request");
	die("Bad address.");
}


// Loading users...
$data = json_decode(file_get_contents($users_json));

foreach ($data->includes as $inner_path => $user) {
	if (strtolower($user->user_name) == strtolower($user_name)) {
		header("HTTP/1.0 400 Bad Request");
		die("Username $user_name already exits.");
	}
	if (strpos($inner_path, $auth_address) !== false) {
		header("HTTP/1.0 400 Bad Request");
		die("Address $auth_address already exits.");
	}
}


// Creating user dir...
$user_dir = str_replace("content.json", "", $users_json).$auth_address;
mkdir($user_dir, 0777);
chmod($user_dir, 0777);
$f = fopen($user_dir."/data.json", "w");
fwrite($f, '{ "next_topic_id": 1, "topics": [], "next_message_id": 1, "comments": {} }');
fclose($f);
chmod($user_dir."/data.json", 0666);


// Adding user...
$data->includes->{$auth_address."/content.json"} = array(
	"user_name" => $user_name,
	"user_id" => $data->next_user_id,
	"added" => time(), 
	"files_allowed" => "data.json", 
	"includes_allowed" => false, 
	"max_size" => 10000, 
	"signers" => array($auth_address),
	"signers_required" => 1
);
$data->next_user_id += 1;
$out = json_encode($data, JSON_PRETTY_PRINT);

$f = fopen($users_json, "w");
fwrite($f, $out);
fclose($f);


// Signing users...
chdir($zeronet_dir);
$out = array();
exec("python zeronet.py --debug siteSign $site $private_key --inner_path data/users/content.json 2>&1", $out);
$out = implode("\n", $out);

if (strpos($out, "content.json signed!") === false) {
	header("HTTP/1.0 500 Internal Server Error");
	die("Users signing error");
}


// Signing user dir...
chdir($zeronet_dir);
exec("python zeronet.py --debug siteSign $site $private_key --inner_path data/users/$auth_address/content.json 2>&1", $out);
$out = implode("\n", $out);

if (strpos($out, "content.json signed!") === false) {
	header("HTTP/1.0 500 Internal Server Error");
	die("User signing error");
}
chmod($user_dir."/content.json", 0666);


// Publishing content...
$out = array();
$server_ip = $_SERVER['SERVER_ADDR'];
exec("python zeronet.py --debug --ip_external $server_ip sitePublish $site --inner_path data/users/content.json 2>&1", $out);
$out = implode("\n", $out);

if (strpos($out, "Successfuly published") === false) {
	header("HTTP/1.0 500 Internal Server Error");
	die("Publish error");
}


echo "OK";

?>