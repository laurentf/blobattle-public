local M = {}

M.INVALID_ARGUMENT = 3
M.NOT_FOUND = 5
M.PERMISSION_DENIED = 7
M.UNAVAILABLE = 14
M.UNAUTHENTICATED = 16

function M.raise(reason, code)
  error({ reason, code }, 0)
end

return M
