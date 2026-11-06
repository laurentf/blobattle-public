local errors = require("server.errors")

local M = {}

M.ACCOUNTS = {
  "AuthenticateApple",
  "AuthenticateCustom",
  "AuthenticateEmail",
  "AuthenticateFacebook",
  "AuthenticateFacebookInstantGame",
  "AuthenticateGameCenter",
  "AuthenticateGoogle",
  "AuthenticateSteam",
  "LinkApple",
  "LinkCustom",
  "LinkDevice",
  "LinkEmail",
  "LinkFacebook",
  "LinkFacebookInstantGame",
  "LinkGameCenter",
  "LinkGoogle",
  "LinkSteam",
}

M.REQUESTS = {
  "WriteStorageObjects",
  "DeleteStorageObjects",
  "CreateGroup",
  "UpdateGroup",
  "JoinGroup",
  "AddFriends",
  "BlockFriends",
  "ImportFacebookFriends",
  "ImportSteamFriends",
  "ListMatches",
}

M.REALTIME = {
  "ChannelJoin",
  "ChannelMessageSend",
  "ChannelMessageUpdate",
  "MatchCreate",
  "MatchmakerAdd",
  "PartyCreate",
  "PartyJoin",
  "StatusFollow",
  "StatusUpdate",
}

function M.refuse()
  errors.raise("unsupported", errors.PERMISSION_DENIED)
end

return M
