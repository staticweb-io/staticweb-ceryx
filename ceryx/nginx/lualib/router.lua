local routes = require "ceryx.routes"
local utils = require "ceryx.utils"

local host = ngx.var.host
local request_uri = ngx.var.request_uri

local is_not_https = (ngx.var.scheme ~= "https")

function formatTarget(target)
    target = utils.ensure_protocol(target)
    target = utils.ensure_no_trailing_slash(target)

    return target .. ngx.var.request_uri
end

function redirect(source, target)
    ngx.log(ngx.INFO, "Redirecting request for " .. source .. " to " .. target .. ".")
    return ngx.redirect(target, ngx.HTTP_MOVED_PERMANENTLY)
end

function proxy(source, target)
    ngx.var.target = target
    ngx.log(ngx.INFO, "Proxying request for " .. source .. " to " .. target .. ".")
end

function routeRequest(source, target, mode)
    ngx.log(ngx.DEBUG, "Received " .. mode .. " routing request from " .. source .. " to " .. target)

    target = formatTarget(target)

    if mode == "redirect" then
       return redirect(source, target)
    elseif mode == "200" then
       return ngx.exit(200)
    elseif mode == "404" then
       return ngx.exit(404)
    elseif mode == "503" then
       return ngx.exit(503)
    end

    return proxy(source, target)
end

ngx.log(ngx.INFO, "HOST " .. host)
local route = routes.getRouteForSource(host, request_uri)

if route == nil then
    ngx.log(ngx.INFO, "No $wildcard target configured for fallback. Exiting with Bad Gateway.")
    return ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end

routeRequest(host, route.target, route.mode)
