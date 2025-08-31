local Logger = require("@self/logger")

local net = require("@lune/net")
local serde = require("@lune/serde")

local future = require("@packages/futures")

type Table<K, V> = {
	[K]: V,
}

--[=[
  @type RequestMethod "GET" | "POST" | "PATCH" | "PUT" | "DELETE"
  @within Roxios
	HTTP request methods supported by Roxios.
]=]
type RequestMethod = "GET" | "POST" | "PATCH" | "PUT" | "DELETE"

--[=[
  @interface Options
  @within Roxios
  @field url string -- The target URL for the request.
  @field params { [string]: string | { string } }? -- Query parameters to append to the URL.
  @field headers { [any]: any }? -- Request headers.
  @field data any? -- Data to be sent in the request body. Will be encoded as JSON if provided.
  @field options net.FetchParamsOptions? -- Extra options for the request

  Options for a full Roxios request.
]=]
type Options = {
	url: string,
	method: RequestMethod?,
	params: Table<string, string | { string }>?,
	headers: Table<any, any>?,
	data: any?,
	options: net.FetchParamsOptions?,
}

--[=[
  @interface AliasOptions
  @within Roxios
  @field params { [string]: string | { string } }? -- Query parameters to append to the URL.
  @field headers { [any]: any }? -- Request headers.
  @field data any? -- Data to be sent in the request body. Will be encoded as JSON if provided.
  @field options net.FetchParamsOptions? -- Extra options for the request

  Options for alias methods (`get`, `post`, etc.).
]=]
type AliasOptions = {
	headers: Table<any, any>?,
	params: Table<string, string | { string }>?,
	data: any?,
	options: net.FetchParamsOptions?,
}

local logger = Logger.new("Roxios")

--[=[
	@class Roxios
	@tag Networking
	@tag HTTP

	Roxios is a lightweight HTTP client wrapper inspired by Axios.

	It provides helper functions for making requests with methods like `get` and `post`,
	while still allowing full flexibility through `Roxios.request`.

	```lua
	local Roxios = require("@self/roxios")

	-- Simple GET
  ```luau
  local roxios = require(path.to.roxios)
  local response = Roxios.get("https://jsonplaceholder.typicode.com/todos/1"):await()
  if response:isErr() then
    error(`Request failed: {response:unwrapErr()}`)
  end

  local data = response:unwrapOk()
  print(`Got response: {data.title}`)
	```
]=]
local Roxios = {}

local function decode(data: string, contentType: string?): any
	if not contentType then
		return data
	end

	local mime = contentType and string.lower(string.match(contentType, "^[^;]+") :: string) or nil

	if mime == "application/json" then
		local ok, parsed = pcall(serde.decode, "json" :: "json", data)
		if ok then
			return parsed
		end
		return data -- fallback
	elseif mime == "application/yaml" or mime == "text/yaml" then
		local ok, parsed = pcall(serde.decode, "yaml" :: "yaml", data)
		if ok then
			return parsed
		end
		return data
	elseif mime == "application/toml" or mime == "text/toml" then
		local ok, parsed = pcall(serde.decode, "toml" :: "toml", data)
		if ok then
			return parsed
		end
		return data
	else
		-- Any other content type → return raw data (HTML, plain text, etc.)
		return data
	end
end

--[=[
	Perform a custom HTTP request.

	@param options Options -- Request options.
	@return future.FutureLike<(any, net.FetchResponse), string> -- A future resolving with the parsed response (if JSON), or rejecting with an error string.
]=]
function Roxios.request(options: Options): future.FutureLike<(any, net.FetchResponse), string>
	return future.Future.new(function()
		if options.data then
			local didEncode, encodedBody = pcall(serde.encode, "json" :: any, options.data)
			if not didEncode then
				logger:warn("Failed to encode body as JSON! setting encodedBody to nil!")
				options.data = nil
			else
				options.data = encodedBody
			end
		end
		local fixedOptions = {
			url = options.url,
			body = options.data,
			method = options.method or "GET",
			headers = options.headers,
			options = options.options,
			query = options.params,
		} :: net.FetchParams

		local ok, response = pcall(net.request, fixedOptions)

		if ok then
			if response.ok then
				local parsedResponse =
					decode(response.body, response.headers["Content-Type"] or response.headers["content-type"])

				return parsedResponse, response
			else
				return logger:error(`{response.statusCode} - {response.statusMessage}`)
			end
		else
			return logger:error(response)
		end
	end) :: future.FutureLike<(any, net.FetchResponse), string>
end

--[=[
	Perform a `GET` request.

	@param url string -- The target URL.
	@param config AliasOptions? -- Optional alias options.
	@return future.FutureLike<any, string> -- A future resolving with the parsed response (if JSON), or rejecting with an error string.
]=]
function Roxios.get(url: string, config: AliasOptions?): future.FutureLike<any, string>
	local fixedConfig = {
		url = url,
		method = "GET",
		headers = (config and config.headers) and config.headers or nil,
		options = config and config.options or nil,
		params = config and config.params or nil,
	}

	return Roxios.request(fixedConfig)
end

--[=[
	Perform a `POST` request.

	@param url string -- The target URL.
	@param data { any: any }? -- Request body (will be JSON encoded).
	@param config AliasOptions? -- Optional alias options.
	@return future.FutureLike<any, string> -- A future resolving with the parsed response (if JSON), or rejecting with an error string.
]=]
function Roxios.post(url: string, data: Table<any, any>?, config: AliasOptions?): future.FutureLike<any, string>
	local fixedConfig: Options = {
		url = url,
		method = "POST",
		headers = (config and config.headers) and config.headers or nil,
		options = config and config.options or nil,
		params = config and config.params or nil,
		data = data,
	}

	return Roxios.request(fixedConfig)
end

return Roxios
