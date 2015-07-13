local log_timer = ngx.shared.log_timer

-- create a timer if required
local function create_timer (callback, delay, timer_name)

	local handler 
	handler = function ()
		-- get lock
        local my_pid = ngx.worker.pid()
        local success, err = log_timer:safe_add(timer_name, 1)
        if success then
			callback()
			log_timer:delete(timer_name)
		end
	    local ok, err = ngx.timer.at(delay, handler)
	    if not ok then
	        ngx.log(ngx.ERR, "failed to create the timer: ", err)
	        return
	    end
	end

	local ok, err = ngx.timer.at(delay, handler)
	if not ok then
	    ngx.log(ngx.ERR, "failed to create the timer: ", err)
	    return
	end
end

-- MAIN
handlers = {}
-- create the log handler
local handler = make_handler(log_settings)
handlers["log"] = handler.log_request
handlers["send_logs"] = handler.send_logs

if log_settings.elasticsearch.logging_method == "buffered" then
	create_timer(handlers.send_logs, log_settings.elasticsearch.send_interval, "send_logs")
end

handler = nil