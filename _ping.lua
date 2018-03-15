require("Settings")
local message = "d=".."03-02-2017"
local headers = { 
	["Content-Length"] = string.len(message), 
	["Content-Type"] = "application/x-www-form-urlencoded"
}
local b, c, h = fa.request{
	url = "http://"..server.."/"..serverDir.."/cd.php",
	method = "POST",
	headers = headers,
    body = message
}
print("HELLO", "http://"..server.."/"..serverDir.."/cd.php", message, b)