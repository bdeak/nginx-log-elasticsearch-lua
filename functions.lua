local json = require 'cjson'
local http = require "resty.http" -- don't forget adding these

local settings = ...

local function send_http(host, port, uri, req_scheme, timeout, payload)
    local hc = http:new()
    local req_url = string.format("%s://%s:%d%s", req_scheme, host, port, uri)
    local ok, code, headers, status, body  = hc:request {
        --- proxy = "http://127.0.0.1:8888",
        url = req_url,
        timeout = 5000,
        scheme = req_scheme,
        method = "POST",
        body = payload,
    }
    if not ok then
        ngx.log(ngx.ERR, "Failed to send data to ", req_url)
    end
end

-- send the buffered logs to elasticsearch
-- log_index and logdata are only needed in case of direct logging
local function send_logs(log_index, logdata_json)
    -- send logs directly on every request
    -- overhead from building up the tcp connection again and again
    local function send_logs_direct(log_index, logdata_json)
        assert(log_index, "Log index must be provided!")
        assert(logdata_json, "Logdata must be provided!")
        -- workaround, using cosockets from log handlers are only supported this way
        -- details/source: http://wiki.nginx.org/HttpLuaModule#Cosockets_Not_Available_Everywhere
        ngx.timer.at(0, function()
            send_http(settings.elasticsearch.host,
                  settings.elasticsearch.bulk_port,
                  settings.elasticsearch.bulk_uri,
                  settings.elasticsearch.bulk_scheme,
                  settings.elasticsearch.bulk_timeout, 
                    json.encode{
                        index = {
                            _index = "nginx-" .. ngx.today(),
                            _type = "nginx-" .. ngx.today(),
                            _id = log_index,
                        }
                    } ..
                    "\n" ..
                    logdata_json ..
                    "\n"
            )
        end
        )
    end

    -- send the logs via the TCP bulk API using an internal buffer
    local function send_logs_http()
        repeat
        keys = ngx.shared.log_buffer:get_keys(1024)
        -- assamble the payload
        local payload = {}
        for i, key in ipairs(keys) do
            logdata_json = ngx.shared.log_buffer:get(key)
            local op = json.encode{
                index = {
                _index = "nginx-" .. ngx.today(),
                _type = "nginx-" .. ngx.today(),
                _id = key,
                }
            }
        
            table.insert(payload, op)
            table.insert(payload, logdata_json)
            ngx.shared.log_buffer:delete(key)
        end
        -- now send the data in one batch
        -- on failure, delete the entries nevertheless, to ensure that the buffer is not getting full
            send_http(settings.elasticsearch.host, 
                  settings.elasticsearch.bulk_port, 
                  settings.elasticsearch.bulk_uri, 
                  settings.elasticsearch.bulk_scheme, 
                  settings.elasticsearch.bulk_timeout, 
                  table.concat(payload, "\n") .. "\n"
                  )
        -- delete the value from the cache
        until #keys == 0
    end

    if settings.elasticsearch.logging_method == "none" then
        -- do nothing
    elseif settings.elasticsearch.logging_method == "buffered" then
        send_logs_http()
    else    
        send_logs_direct(log_index, logdata_json)
    end
end


-- handler for doing dynamic logging of requests to elasticsearch
local function log_request()
    if settings.elasticsearch.logging_method ~= "none" then
        -- assemble the data to be logged - this is the 'logformat' basically
        local logdata = {
            ["@timestamp"] = ngx.var.time_iso8601,
            remote_addr = ngx.var.remote_addr,
            remote_user = ngx.var.remote_user,
            request = ngx.var.request,
            status = ngx.var.status,
            body_bytes_sent = ngx.var.body_bytes_sent,
            http_referer = ngx.var.http_referer or '-',
            http_user_agent = ngx.var.http_user_agent,
            http_x_forwarded_for = ngx.var.http_x_forwarded_for,
            request_time = ngx.var.request_time,
            server_name = ngx.var.server_name,      
            request_method = ngx.var.request_method,
            http_protocol = ngx.var.scheme,
            hostname = ngx.var.hostname,
            connection_serial_id = ngx.var.connection,
            connection_requests = ngx.var.connection_requests,
        }
        
        -- assemble the index dynamically
        local log_index = ngx.md5(string.format("%s_%s_%s_%s_%s", logdata["@timestamp"], logdata.remote_addr, logdata.hostname, logdata.connection_serial_id, logdata.connection_requests))

        -- add the logline to the buffer - if buffering is required
        if settings.elasticsearch.logging_method == "buffered" then
            -- sending of the contents of the buffer is implemented in send_logs().
            local ok, err = ngx.shared.log_buffer:safe_add(log_index, json.encode(logdata))
            if not ok then
                ngx.log(ngx.ERR, "Error while adding log line to buffer, dropping log line: " .. err);
            end
        else
            -- send the request directly
            send_logs(log_index, json.encode(logdata))
        end
    end
end

return {
    send_logs = send_logs;
    log_request = log_request;
}