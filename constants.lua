local Constants = {}

Constants.DEFAULT_COOLDOWN = 0
Constants.DEFAULT_RATE_LIMIT = 10
Constants.DEFAULT_RATE_WINDOW = 5
Constants.DEFAULT_BAN_DURATION = 30
Constants.DEFAULT_PER_SEC_LIMIT = 10 -- max calls per second (any validity) before ban
Constants.CLIENT_TIMEOUT = 10

Constants.LOG_LEVELS = {
	INFO = "INFO",
	WARN = "WARN",
	BLOCKED = "BLOCKED",
	SPAM = "SPAM",
	DENIED = "DENIED",
	ERROR = "ERROR",
}

return Constants
