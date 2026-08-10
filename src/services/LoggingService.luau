local LoggingService = {}

local function Format(source: string, level: string, message: string): string
	return string.format("[%s] [%s] [%s] %s", os.date("%X"), level, source, message)
end

function LoggingService:Print(source: string, message: string)
	print(Format(source, "PRINT", message))
end

function LoggingService:Warn(source: string, message: string)
	warn(Format(source, "WARN", message))
end

function LoggingService:Error(source: string, message: string)
	warn(Format(source, "ERROR", message))
end

function LoggingService:Init() end

return LoggingService
