local cjson = require "cjson"
local http = require "resty.http"
local utils = require "ceryx.utils"

local targetUrl = utils.getenv("CERYX_TARGET_URL", "https://api.staticweb.io/internal/v1/ceryx-target")
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

   if err or not res then
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
    local res, err = jsonPost(targetUrl, {source = source})
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

function isHealthy()
   ngx.log(ngx.INFO, "Performing health check")
   local uri = "https://api.staticweb.io/health"
   local httpClient = http.new()
   httpClient:set_timeout(5000)
   local request = {
      method = "GET"
   }
   local res, err = httpClient:request_uri(uri, request)

   if err or not res then
      ngx.log(ngx.ERR, "Health check failed")
      ngx.log(ngx.DEBUG, err)
      return false, err
   end

   if 200 == res.status or 204 == res.status then
      ngx.log(ngx.INFO, "Health check succeeded with status " .. res.status)
      return true, nil
   else
      ngx.log(ngx.ERR, "Health check failed with status " .. res.status)
      return false, nil
   end
end

function getRouteForSource(source, request_uri)
    local _
    local route = {}
    local cache = ngx.shared.ceryx

    local chunks = { source:match(ip_pattern) }
    if #chunks == 4 then
       local first = chunks[1]
       if "/health" == request_uri and ("10" == first or "127" == first) then
          -- Handle ELB health checks
          local healthy = cache:get("staticweb_healthy")
          if nil == healthy then
             healthy, _ = isHealthy()
             cache:set("staticweb_healthy", healthy, 25)
          end

          if healthy then
             route.target = ""
             route.mode = "200"
          else
             route.target = ""
             route.mode = "503"
          end
       else
          -- Don't waste resources on bots
          ngx.log(ngx.INFO, "Returning 404 for IP address: " .. source)
          route.target = ""
          route.mode = "404"
       end
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
             if target == "https://app.staticweb.io" then
                local success, err, _ = cache:set(source, target, 2)
                if success then
                   ngx.log(ngx.DEBUG, "Caching from " .. source .. " to " .. target .. " for 2 seconds.")
                else
                   ngx.log(ngx.DEBUG, "Error caching " .. source .. "... : " .. err)
                end
             else
                local success, err, _ = cache:set(source, target, 60)
                if success then
                   ngx.log(ngx.DEBUG, "Caching from " .. source .. " to " .. target .. " for 60 seconds.")
                else
                   ngx.log(ngx.DEBUG, "Error caching " .. source .. "... : " .. err)
                end
             end
          end
       end
    end

    if route.target == "https://app.staticweb.io" then
       route.host_header = "app.staticweb.io"
    else
       route.host_header = source
    end

    return route
end

exports.getRouteForSource = getRouteForSource
exports.getTargetForSource = getTargetForSource

return exports
