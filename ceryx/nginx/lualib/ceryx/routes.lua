local cjson = require "cjson"
local http = require "resty.http"
local utils = require "ceryx.utils"

local host = utils.getenv("CERYX_STATICWEB_API_HOST", "https://app.staticweb.io")
local prefix = utils.getenv("CERYX_KEY_PREFIX", "ceryx")

local ip_pattern = "^(%d+)%.(%d+)%.(%d+)%.(%d+)$"

local exports = {}

function jsonPost(uri, body)
   local httpClient = http.new()
   httpClient:set_timeout(5000)
   local request = {
      method = "POST",
      body = cjson.encode(body),
      headers = {
         ["Accept"] = "application/json",
         ["Content-Type"] = "application/json"
      },
      keepalive = false
   }
   local res, err = httpClient:request_uri(uri, request)

   if not res then
      ngx.log(ngx.DEBUG, err)
      return nil, err
   end

   res.body = cjson.decode(res.body)
   return res, nil
end

function targetIsInValid(target)
    return not target or target == ngx.null
end

function getTargetForSource(source)
    local res, err = jsonPost(host .. "/api/ceryx", {source = source})
    if not res then
       return nil, err
    end

    if targetIsInValid(res.body.target) then
        ngx.log(ngx.INFO, "Could not find target for " .. source .. ".")

        res, err = jsonPost(host .. "/api/ceryx", {source = "$wildcard"})
        if not res then
           return nil, err
        end

        if targetIsInValid(res.body.target) then
            return nil, nil
        end

        ngx.log(ngx.DEBUG, "Falling back to " .. target .. ".")
    end

    return res.body.target, nil
end

function getRouteForSource(source)
    local _
    local route = {}
    local cache = ngx.shared.ceryx

    local chunks = { source:match(ip_pattern) }
    if #chunks == 4 then
       ngx.log(ngx.INFO, "Returning 404 for IP address: " .. source)
       route.target = ""
       route.mode = "404"
    else
       ngx.log(ngx.DEBUG, "Looking for a route for " .. source)
       -- Check if key exists in local cache
       local cached_value, _, stale = cache:get_stale(source)

       if cached_value and not stale then
          ngx.log(ngx.DEBUG, "Cache hit for " .. source .. ".")
          route.target = cached_value
          route.mode = "proxy"
       else
          ngx.log(ngx.DEBUG, "Cache miss for " .. source .. ".")
          local target, err = getTargetForSource(source)

          if err and cached_value then
             route.target = cached_value
             route.mode = "proxy"

             ngx.log(ngx.DEBUG, "Error getting target: " .. err .. ". Using stale cache value from " .. source .. " to " .. cached_value .. " and caching for 60 seconds.")
             local success, err, _ = cache:set(source, cached_value, 60)
             if err then
                ngx.log(ngx.DEBUG, "Error caching " .. source .. "... : " .. err)
             end
          else
             if targetIsInValid(target) then
                return nil
             end

             route.target = target
             route.mode = "proxy"
             local success, err, _ = cache:set(source, target, 60)
             if success then
                ngx.log(ngx.DEBUG, "Caching from " .. source .. " to " .. target .. " for 60 seconds.")
             else
                ngx.log(ngx.DEBUG, "Error caching " .. source .. "... : " .. err)
             end
          end
       end
    end

    return route
end

exports.getRouteForSource = getRouteForSource
exports.getTargetForSource = getTargetForSource

return exports
