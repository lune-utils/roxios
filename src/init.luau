local net = require("@lune/net")
local serde = require("@lune/serde")

local future = require("@packages/future")

type Table<K, V> = {
	[K]: V,
}

type RequestMethod = "GET" | "POST" | "PATCH" | "PUT" | "DELETE"

type Options = {
	url: string,
	method: RequestMethod?,
	params: Table<string, string | { string }>?,
	headers: Table<any, any>?,
	data: any?,
	options: net.FetchParamsOptions?,
}

type AliasOptions = {
	headers: Table<any, any>?,
	params: Table<string, string | { string }>?,
	data: any?,
	options: net.FetchParamsOptions?,
}

local Roxios = {}

function Roxios.request(options: Options): future.FutureLike<(any, net.FetchResponse), string>
	return future.Future.new(function()
		if options.data then
			local didEncode, encodedBody = pcall(serde.encode, "json" :: any, options.data)
			if not didEncode then
				warn("Roxios warn: Failed to encode body as JSON! setting encodedBody to nil!")
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
				local didParse, parsedResponse = pcall(serde.decode, "json" :: "json" | "toml" | "yaml", response.body)

				if didParse then
					return parsedResponse, response
				else
					warn("Roxios warn: Failed to parse response body as JSON! Setting parsedResponse to nil!")
					return nil, response
				end
			else
				return error(
					`Roxios error: Request failed with status code: {response.statusCode} and message: \n{response.statusMessage}`
				)
			end
		else
			return error(`Roxios error:\n{response}`)
		end
	end) :: future.FutureLike<any, string>
end

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
